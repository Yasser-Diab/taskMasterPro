-- TaskMaster Pro v0.0.27: one Activity decision is one idempotent transaction.
--
-- Raw observations remain device-local by default. Once a user approves a
-- normalized segment, this command resolves its review, records one
-- attribution, credits at most one task contribution, and optionally stores
-- one trusted application rule. Display names and translated labels are never
-- used as identity.

-- Older builds could create several active rules for the same application and
-- scope. Keep the newest rule active and retain the others as tombstoned
-- history before enforcing the semantic identity.
with ranked_rules as (
  select
    id,
    row_number() over (
      partition by
        user_id,
        application_id,
        scope_type,
        coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
      order by updated_at desc, created_at desc, id
    ) as semantic_rank
  from public.application_rules
  where deleted_at is null
)
update public.application_rules as rules
set deleted_at = pg_catalog.statement_timestamp(),
    data = rules.data || pg_catalog.jsonb_build_object(
      'superseded_by_v0027', true,
      'repair_reason', 'duplicate_application_rule_scope'
    )
from ranked_rules
where ranked_rules.id = rules.id
  and ranked_rules.semantic_rank > 1;

create unique index if not exists application_rules_scope_unique_v0027_idx
  on public.application_rules (
    user_id,
    application_id,
    scope_type,
    coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  where deleted_at is null;

-- The baseline already has this invariant. Re-state it idempotently for
-- projects upgraded from an intermediate development migration.
create unique index if not exists activity_contributions_semantic_unique_idx
  on public.activity_contributions (
    user_id,
    activity_segment_id,
    target_type,
    coalesce(target_id, '00000000-0000-0000-0000-000000000000'::uuid),
    contribution_type
  )
  where deleted_at is null;

-- A contribution pointing at a missing/deleted task must not remain in totals.
-- Preserve the row as a tombstone so valid historical evidence is not erased.
update public.activity_contributions as contribution
set deleted_at = pg_catalog.statement_timestamp(),
    data = contribution.data || pg_catalog.jsonb_build_object(
      'tombstoned_by_v0027', true,
      'repair_reason', 'target_task_unavailable'
    )
where contribution.deleted_at is null
  and contribution.target_type = 'task_occurrence'
  and contribution.target_id is not null
  and not exists (
    select 1
    from public.task_occurrences as task
    where task.user_id = contribution.user_id
      and task.id = contribution.target_id
      and task.deleted_at is null
  );

-- Resolve repeated questions for a segment when a canonical review for that
-- same normalized period was already completed.
with canonical_review as (
  select distinct on (user_id, activity_segment_id)
    user_id,
    activity_segment_id,
    status,
    reviewed_at,
    data
  from public.activity_review_queue
  where deleted_at is null
    and status <> 'pending'
  order by
    user_id,
    activity_segment_id,
    reviewed_at desc nulls last,
    updated_at desc
)
update public.activity_review_queue as pending
set status = canonical.status,
    reviewed_at = coalesce(canonical.reviewed_at, pg_catalog.statement_timestamp()),
    data = pending.data || canonical.data || pg_catalog.jsonb_build_object(
      'resolved_by_v0027', true,
      'repair_reason', 'segment_already_classified'
    )
from canonical_review as canonical
where pending.user_id = canonical.user_id
  and pending.activity_segment_id = canonical.activity_segment_id
  and pending.deleted_at is null
  and pending.status = 'pending';

create or replace function taskmaster_internal.classify_activity_review_v0027(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_review_item_id uuid,
  p_expected_revision bigint,
  p_classification text,
  p_target_task_id uuid,
  p_rule_scope text,
  p_details jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
<<activity_classifier>>
declare
  owner_id uuid := (select auth.uid());
  details jsonb := coalesce(p_details, '{}'::jsonb);
  existing_result jsonb;
  result_payload jsonb;
  review_row public.activity_review_queue%rowtype;
  segment_row public.activity_segments%rowtype;
  attribution_row public.activity_attributions%rowtype;
  contribution_row public.activity_contributions%rowtype;
  feedback_row public.classification_feedback%rowtype;
  rule_row public.application_rules%rowtype;
  canonical_application_id uuid;
  requested_attribution_id uuid;
  requested_contribution_id uuid;
  requested_rule_id uuid;
  requested_feedback_id uuid;
  desired_status text := coalesce(nullif(p_details ->> 'status', ''), 'confirmed');
  desired_target_type text :=
    coalesce(nullif(p_details ->> 'target_type', ''), 'task_occurrence');
  desired_contribution_type text :=
    nullif(p_details ->> 'contribution_type', '');
  desired_rule_scope text := nullif(p_rule_scope, '');
  desired_review_reason text :=
    coalesce(nullif(p_details ->> 'review_reason', ''), 'manual_review');
  desired_confidence numeric :=
    least(1, greatest(0, coalesce((p_details ->> 'confidence')::numeric, 1)));
  physical_duration bigint;
  credited_duration bigint;
  source_task_id uuid;
  source_session_id uuid;
  is_automatic boolean := coalesce((p_details ->> 'is_automatic')::boolean, false);
  already_applied boolean := false;
  canonical_classification text;
  canonical_target_task_id uuid;
  canonical_contribution_type text;
  application_platform text;
  application_identifier text;
  application_display_name text;
  rule_scope_id uuid;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_classification is null or pg_catalog.btrim(p_classification) = '' then
    raise exception 'invalid_activity_classification' using errcode = '22023';
  end if;
  if desired_status not in ('confirmed', 'rejected', 'ignored') then
    raise exception 'invalid_activity_review_status' using errcode = '22023';
  end if;
  if desired_rule_scope is not null
     and desired_rule_scope not in ('task', 'user') then
    raise exception 'invalid_activity_rule_scope' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.account_devices
    where user_id = owner_id
      and id = p_device_id
      and revoked_at is null
      and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':activity-review:' || p_review_item_id::text,
      0
    )
  );

  select result
  into existing_result
  from public.processed_commands
  where user_id = owner_id
    and command_id = p_command_id;
  if found then
    return existing_result;
  end if;

  <<apply_classification>>
  begin
    select *
    into review_row
    from public.activity_review_queue
    where user_id = owner_id
      and id = p_review_item_id
      and deleted_at is null
    for update;

    if not found then
      select *
      into segment_row
      from public.activity_segments
      where user_id = owner_id
        and id = nullif(details ->> 'activity_segment_id', '')::uuid
        and deleted_at is null
      for update;
      if not found then
        raise exception 'missing_activity_segment'
          using errcode = '23503';
      end if;

      -- A previous device may have created the semantic review with another
      -- random UUID. Adopt that canonical identity rather than inserting a
      -- duplicate question.
      select *
      into review_row
      from public.activity_review_queue
      where user_id = owner_id
        and activity_segment_id = segment_row.id
        and review_reason = desired_review_reason
        and deleted_at is null
      for update;

      if not found then
        insert into public.activity_review_queue (
          id,
          user_id,
          activity_segment_id,
          review_reason,
          priority,
          suggested_targets,
          suggested_classification,
          confidence,
          status,
          created_by_device_id,
          updated_by_device_id,
          last_command_id,
          data
        )
        values (
          p_review_item_id,
          owner_id,
          segment_row.id,
          desired_review_reason,
          coalesce((details ->> 'priority')::integer, 2),
          '[]'::jsonb,
          p_classification,
          desired_confidence,
          'pending',
          p_device_id,
          p_device_id,
          p_command_id,
          '{}'::jsonb
        )
        returning * into review_row;
      end if;
    else
      select *
      into segment_row
      from public.activity_segments
      where user_id = owner_id
        and id = review_row.activity_segment_id
        and deleted_at is null
      for update;
      if not found then
        raise exception 'missing_activity_segment'
          using errcode = '23503';
      end if;
    end if;

    canonical_classification := nullif(review_row.data ->> 'classification', '');
    canonical_target_task_id :=
      nullif(review_row.data ->> 'target_task_id', '')::uuid;
    canonical_contribution_type :=
      nullif(review_row.data ->> 'contribution_type', '');

    if review_row.status <> 'pending' and canonical_classification is not null then
      if p_target_task_id is not null and desired_contribution_type is not null then
        select *
        into contribution_row
        from public.activity_contributions
        where user_id = owner_id
          and activity_segment_id = review_row.activity_segment_id
          and target_type = desired_target_type
          and target_id is not distinct from p_target_task_id
          and contribution_type = desired_contribution_type
          and deleted_at is null
        for update;
      end if;
      already_applied :=
        canonical_classification = p_classification
        and canonical_target_task_id is not distinct from p_target_task_id
        and canonical_contribution_type is not distinct from desired_contribution_type
        and (
          p_target_task_id is null
          or desired_contribution_type is null
          or contribution_row.id is not null
        );
      if already_applied
         or canonical_classification <> p_classification
         or canonical_target_task_id is distinct from p_target_task_id then
        result_payload := pg_catalog.jsonb_build_object(
          'status', 'accepted',
          'outcome',
            case when already_applied
              then 'already_applied'
              else 'canonical_review_already_resolved'
            end,
          'review_item_id', review_row.id,
          'review_revision', review_row.revision,
          'classification', canonical_classification,
          'target_task_id', canonical_target_task_id,
          'contribution_id', contribution_row.id
        );
        exit apply_classification;
      end if;
      -- A legacy partial write resolved the review without creating its
      -- matching contribution. Continue through the same transaction to
      -- repair the missing dependent row.
    end if;

    if p_target_task_id is not null then
      if desired_target_type <> 'task_occurrence' then
        raise exception 'unsupported_activity_target_type'
          using errcode = '22023';
      end if;
      if not exists (
        select 1
        from public.task_occurrences
        where user_id = owner_id
          and id = p_target_task_id
          and deleted_at is null
      ) then
        raise exception 'target_task_unavailable'
          using errcode = '23503';
      end if;
    end if;

    requested_attribution_id :=
      coalesce(
        nullif(details ->> 'attribution_id', '')::uuid,
        extensions.gen_random_uuid()
      );
    select *
    into attribution_row
    from public.activity_attributions
    where user_id = owner_id
      and activity_segment_id = review_row.activity_segment_id
      and classification = p_classification
      and target_type = desired_target_type
      and target_id is not distinct from p_target_task_id
      and attribution_status in ('automatic', 'confirmed', 'rejected', 'ignored')
      and deleted_at is null
    order by updated_at desc
    limit 1
    for update;

    if not found then
      insert into public.activity_attributions (
        id,
        user_id,
        activity_segment_id,
        target_type,
        target_id,
        classification,
        confidence,
        attribution_status,
        suggested_by,
        confirmed_by_user,
        created_by_device_id,
        updated_by_device_id,
        last_command_id,
        data
      )
      values (
        requested_attribution_id,
        owner_id,
        review_row.activity_segment_id,
        desired_target_type,
        p_target_task_id,
        p_classification,
        desired_confidence,
        case
          when is_automatic then 'automatic'::public.attribution_status
          else desired_status::public.attribution_status
        end,
        case when is_automatic then 'trusted_rule' else 'user_review' end,
        not is_automatic,
        p_device_id,
        p_device_id,
        p_command_id,
        pg_catalog.jsonb_build_object('review_item_id', review_row.id)
      )
      returning * into attribution_row;
    end if;

    requested_feedback_id :=
      coalesce(
        nullif(details ->> 'classification_feedback_id', '')::uuid,
        extensions.gen_random_uuid()
      );
    insert into public.classification_feedback (
      id,
      user_id,
      activity_segment_id,
      application_id,
      domain,
      suggested_classification,
      chosen_classification,
      suggested_target_type,
      suggested_target_id,
      chosen_target_type,
      chosen_target_id,
      feedback_type,
      created_by_device_id,
      updated_by_device_id,
      last_command_id,
      data
    )
    values (
      requested_feedback_id,
      owner_id,
      review_row.activity_segment_id,
      null,
      nullif(details ->> 'domain', ''),
      nullif(details ->> 'suggested_classification', ''),
      p_classification,
      nullif(details ->> 'suggested_target_type', ''),
      nullif(details ->> 'suggested_target_id', '')::uuid,
      desired_target_type,
      p_target_task_id,
      coalesce(nullif(details ->> 'feedback_type', ''), desired_status),
      p_device_id,
      p_device_id,
      p_command_id,
      pg_catalog.jsonb_build_object('review_item_id', review_row.id)
    )
    on conflict (id) do update
    set chosen_classification = excluded.chosen_classification,
        chosen_target_type = excluded.chosen_target_type,
        chosen_target_id = excluded.chosen_target_id,
        feedback_type = excluded.feedback_type,
        updated_by_device_id = excluded.updated_by_device_id,
        last_command_id = excluded.last_command_id,
        deleted_at = null,
        data = public.classification_feedback.data || excluded.data
    where public.classification_feedback.user_id = owner_id
    returning * into feedback_row;

    if p_target_task_id is not null and desired_contribution_type is not null then
      physical_duration :=
        greatest(
          0,
          coalesce(
            (details ->> 'physical_duration_ms')::bigint,
            segment_row.duration_ms
          )
        );
      credited_duration :=
        least(
          physical_duration,
          greatest(
            0,
            coalesce(
              (details ->> 'credited_duration_ms')::bigint,
              physical_duration
            )
          )
        );
      source_task_id := nullif(details ->> 'source_task_id', '')::uuid;
      source_session_id := nullif(details ->> 'source_session_id', '')::uuid;
      requested_contribution_id :=
        coalesce(
          nullif(details ->> 'contribution_id', '')::uuid,
          extensions.gen_random_uuid()
        );

      select *
      into contribution_row
      from public.activity_contributions
      where user_id = owner_id
        and activity_segment_id = review_row.activity_segment_id
        and target_type = desired_target_type
        and target_id is not distinct from p_target_task_id
        and contribution_type = desired_contribution_type
        and deleted_at is null
      for update;

      if not found then
        begin
          insert into public.activity_contributions (
            id,
            user_id,
            activity_segment_id,
            activity_attribution_id,
            target_type,
            target_id,
            contribution_type,
            physical_duration_ms,
            credited_duration_ms,
            progress_value,
            source_task_id,
            source_session_id,
            is_unscheduled,
            is_cross_task,
            is_idle_derived,
            is_automatic,
            created_by_device_id,
            updated_by_device_id,
            last_command_id,
            data
          )
          values (
            requested_contribution_id,
            owner_id,
            review_row.activity_segment_id,
            attribution_row.id,
            desired_target_type,
            p_target_task_id,
            desired_contribution_type,
            physical_duration,
            credited_duration,
            credited_duration,
            source_task_id,
            source_session_id,
            source_task_id is distinct from p_target_task_id,
            source_task_id is not null and source_task_id <> p_target_task_id,
            coalesce((details ->> 'is_idle_derived')::boolean, false),
            is_automatic,
            p_device_id,
            p_device_id,
            p_command_id,
            coalesce(details -> 'contribution_data', '{}'::jsonb)
          )
          returning * into contribution_row;
        exception when unique_violation then
          select *
          into contribution_row
          from public.activity_contributions
          where user_id = owner_id
            and activity_segment_id = review_row.activity_segment_id
            and target_type = desired_target_type
            and target_id is not distinct from p_target_task_id
            and contribution_type = desired_contribution_type
            and deleted_at is null
          for update;
          if not found then
            raise;
          end if;
        end;
      else
        -- An extension of the same normalized segment updates the existing
        -- credit once. It never adds another duration to task totals.
        update public.activity_contributions
        set physical_duration_ms = greatest(
              activity_contributions.physical_duration_ms,
              physical_duration
            ),
            credited_duration_ms = greatest(
              activity_contributions.credited_duration_ms,
              credited_duration
            ),
            progress_value = greatest(
              coalesce(activity_contributions.progress_value, 0),
              credited_duration
            ),
            updated_by_device_id = p_device_id,
            last_command_id = p_command_id,
            data = activity_contributions.data
              || coalesce(details -> 'contribution_data', '{}'::jsonb)
        where user_id = owner_id
          and id = contribution_row.id
        returning * into contribution_row;
      end if;
    end if;

    if desired_rule_scope is not null then
      application_platform := lower(nullif(details ->> 'application_platform', ''));
      application_identifier :=
        lower(nullif(details ->> 'application_identifier', ''));
      application_display_name :=
        nullif(details ->> 'application_display_name', '');
      if application_platform is not null and application_identifier is not null then
        select id
        into canonical_application_id
        from public.application_catalog as catalog
        where user_id = owner_id
          and lower(platform) = application_platform
          and lower(catalog.application_identifier) =
            activity_classifier.application_identifier
          and deleted_at is null
        order by updated_at desc
        limit 1
        for update;

        if not found then
          canonical_application_id :=
            coalesce(
              nullif(details ->> 'application_id', '')::uuid,
              extensions.gen_random_uuid()
            );
          insert into public.application_catalog (
            id,
            user_id,
            platform,
            application_identifier,
            display_name,
            classification,
            first_seen_at,
            last_seen_at,
            created_by_device_id,
            updated_by_device_id,
            last_command_id,
            data
          )
          values (
            canonical_application_id,
            owner_id,
            application_platform,
            application_identifier,
            application_display_name,
            p_classification,
            segment_row.started_at,
            segment_row.ended_at,
            p_device_id,
            p_device_id,
            p_command_id,
            pg_catalog.jsonb_build_object(
              'created_by_activity_classification', true
            )
          );
        end if;

        rule_scope_id :=
          case
            when desired_rule_scope = 'task' then p_target_task_id
            else owner_id
          end;
        if desired_rule_scope = 'task' and rule_scope_id is null then
          rule_scope_id := nullif(details ->> 'rule_scope_id', '')::uuid;
        end if;

        select *
        into rule_row
        from public.application_rules
        where user_id = owner_id
          and application_id = canonical_application_id
          and scope_type = desired_rule_scope
          and scope_id is not distinct from rule_scope_id
          and deleted_at is null
        for update;

        if found then
          update public.application_rules
          set classification = p_classification,
              target_type = case
                when p_target_task_id is null then null
                else desired_target_type
              end,
              target_id = p_target_task_id,
              contribution_type = desired_contribution_type,
              automatic_credit =
                p_target_task_id is not null
                and desired_contribution_type is not null,
              priority = coalesce((details ->> 'rule_priority')::integer, 200),
              updated_by_device_id = p_device_id,
              last_command_id = p_command_id,
              data = application_rules.data || pg_catalog.jsonb_build_object(
                'rule_origin', 'user_confirmed'
              )
          where user_id = owner_id
            and id = rule_row.id
          returning * into rule_row;
        else
          requested_rule_id :=
            coalesce(
              nullif(details ->> 'rule_id', '')::uuid,
              extensions.gen_random_uuid()
            );
          insert into public.application_rules (
            id,
            user_id,
            application_id,
            scope_type,
            scope_id,
            classification,
            target_type,
            target_id,
            contribution_type,
            automatic_credit,
            priority,
            created_by_device_id,
            updated_by_device_id,
            last_command_id,
            data
          )
          values (
            requested_rule_id,
            owner_id,
            canonical_application_id,
            desired_rule_scope,
            rule_scope_id,
            p_classification,
            case when p_target_task_id is null then null else desired_target_type end,
            p_target_task_id,
            desired_contribution_type,
            p_target_task_id is not null
              and desired_contribution_type is not null,
            coalesce((details ->> 'rule_priority')::integer, 200),
            p_device_id,
            p_device_id,
            p_command_id,
            pg_catalog.jsonb_build_object('rule_origin', 'user_confirmed')
          )
          returning * into rule_row;
        end if;
      end if;
    end if;

    update public.activity_review_queue
    set status = desired_status,
        reviewed_at = pg_catalog.statement_timestamp(),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        data = activity_review_queue.data || pg_catalog.jsonb_build_object(
          'classification', p_classification,
          'target_task_id', p_target_task_id,
          'contribution_type', desired_contribution_type,
          'attribution_id', attribution_row.id,
          'contribution_id', contribution_row.id,
          'application_rule_id', rule_row.id,
          'classification_command_id', p_command_id,
          'merged_from_revision',
            case
              when review_row.revision <> p_expected_revision
                then p_expected_revision
              else null
            end
        )
    where user_id = owner_id
      and id = review_row.id
    returning * into review_row;

    update public.activity_review_queue
    set status = desired_status,
        reviewed_at = review_row.reviewed_at,
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        data = activity_review_queue.data || pg_catalog.jsonb_build_object(
          'classification', p_classification,
          'target_task_id', p_target_task_id,
          'contribution_type', desired_contribution_type,
          'resolved_with_review_item_id', review_row.id
        )
    where user_id = owner_id
      and activity_segment_id = review_row.activity_segment_id
      and id <> review_row.id
      and status = 'pending'
      and deleted_at is null;

    result_payload := pg_catalog.jsonb_build_object(
      'status', 'accepted',
      'outcome',
        case
          when review_row.revision <> p_expected_revision + 1
            then 'merged_latest_revision'
          else 'applied'
        end,
      'review_item_id', review_row.id,
      'review_revision', review_row.revision,
      'classification', p_classification,
      'target_task_id', p_target_task_id,
      'attribution_id', attribution_row.id,
      'contribution_id', contribution_row.id,
      'application_rule_id', rule_row.id,
      'classification_feedback_id', feedback_row.id
    );
  end apply_classification;

  insert into public.processed_commands (
    user_id,
    command_id,
    device_id,
    device_sequence,
    entity_type,
    entity_id,
    command_type,
    base_revision,
    status,
    result,
    created_by_device_id,
    updated_by_device_id,
    last_command_id
  )
  values (
    owner_id,
    p_command_id,
    p_device_id,
    p_device_sequence,
    'activity_review_classifications',
    p_review_item_id,
    'classify',
    p_expected_revision,
    case
      when result_payload ->> 'status' = 'accepted'
        then 'accepted'::public.sync_command_status
      else 'conflict'::public.sync_command_status
    end,
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

revoke all on function taskmaster_internal.classify_activity_review_v0027(
  uuid, uuid, bigint, uuid, bigint, text, uuid, text, jsonb
) from public, anon;
grant execute on function taskmaster_internal.classify_activity_review_v0027(
  uuid, uuid, bigint, uuid, bigint, text, uuid, text, jsonb
) to authenticated, service_role;

create or replace function public.classify_activity_review(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_review_item_id uuid,
  p_expected_revision bigint,
  p_classification text,
  p_target_task_id uuid,
  p_rule_scope text,
  p_details jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.classify_activity_review_v0027(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_review_item_id,
    p_expected_revision,
    p_classification,
    p_target_task_id,
    p_rule_scope,
    p_details
  )
$$;

revoke all on function public.classify_activity_review(
  uuid, uuid, bigint, uuid, bigint, text, uuid, text, jsonb
) from public, anon;
grant execute on function public.classify_activity_review(
  uuid, uuid, bigint, uuid, bigint, text, uuid, text, jsonb
) to authenticated;

comment on function public.classify_activity_review(
  uuid, uuid, bigint, uuid, bigint, text, uuid, text, jsonb
) is
  'Atomically and idempotently resolves one Activity review, its attribution, its optional task contribution, and its optional trusted rule.';

-- Proven legacy Activity conflicts are diagnostics history, not unfinished
-- user work. Resolve only rows whose canonical result is already present.
update public.sync_conflicts as conflict
set resolution_status = 'auto_resolved',
    resolution = pg_catalog.jsonb_build_object(
      'strategy', 'atomic_activity_classification',
      'resolved_by', 'migration_20260730010000'
    ),
    resolved_at = pg_catalog.statement_timestamp()
where conflict.resolution_status = 'unresolved'
  and (
    (
      conflict.entity_type = 'activity_review_queue'
      and exists (
        select 1
        from public.activity_review_queue as review
        where review.user_id = conflict.user_id
          and review.id = conflict.entity_id
          and review.status <> 'pending'
      )
    )
    or
    (
      conflict.entity_type = 'activity_contributions'
      and exists (
        select 1
        from public.activity_contributions as contribution
        where contribution.user_id = conflict.user_id
          and contribution.deleted_at is null
          and (
            contribution.id = conflict.entity_id
            or (
              contribution.activity_segment_id =
                nullif(conflict.local_payload ->> 'activity_segment_id', '')::uuid
              and contribution.target_type =
                conflict.local_payload ->> 'target_type'
              and contribution.target_id is not distinct from
                nullif(conflict.local_payload ->> 'target_id', '')::uuid
              and contribution.contribution_type =
                conflict.local_payload ->> 'contribution_type'
            )
          )
      )
    )
  );
