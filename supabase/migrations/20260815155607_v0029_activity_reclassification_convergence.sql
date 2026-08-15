-- TaskMaster Pro v0.0.33: canonical, revision-guarded Activity reclassification.
--
-- v0027 made an initial classification atomic, but intentionally treated a
-- resolved review as immutable. The client now supports an explicit second
-- review, so this forward-only wrapper adds compare-and-set reclassification
-- with one canonical revision advance. Initial reviews continue through the
-- deployed v0027 transaction; reclassification is applied directly here.

create or replace function taskmaster_internal.activity_classification_response_v0029(
  p_owner_id uuid,
  p_review_item_id uuid,
  p_status text,
  p_outcome text,
  p_reason text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  review_row public.activity_review_queue%rowtype;
  rule_row public.application_rules%rowtype;
  application_row public.application_catalog%rowtype;
  feedback_row public.classification_feedback%rowtype;
  attribution_rows jsonb := '[]'::jsonb;
  contribution_rows jsonb := '[]'::jsonb;
begin
  select *
  into review_row
  from public.activity_review_queue
  where user_id = p_owner_id
    and id = p_review_item_id
    and deleted_at is null;

  if not found then
    return pg_catalog.jsonb_build_object(
      'status', p_status,
      'outcome', p_outcome,
      'reason', p_reason,
      'review_item_id', p_review_item_id,
      'server_revision', null,
      'canonical_review', null,
      'canonical_attributions', '[]'::jsonb,
      'canonical_contributions', '[]'::jsonb,
      'canonical_application', null,
      'canonical_rule', null,
      'canonical_feedback', null
    );
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(attribution) order by attribution.created_at, attribution.id),
    '[]'::jsonb
  )
  into attribution_rows
  from public.activity_attributions as attribution
  where attribution.user_id = p_owner_id
    and attribution.activity_segment_id = review_row.activity_segment_id;

  select coalesce(
    pg_catalog.jsonb_agg(pg_catalog.to_jsonb(contribution) order by contribution.created_at, contribution.id),
    '[]'::jsonb
  )
  into contribution_rows
  from public.activity_contributions as contribution
  where contribution.user_id = p_owner_id
    and contribution.activity_segment_id = review_row.activity_segment_id;

  select *
  into rule_row
  from public.application_rules
  where user_id = p_owner_id
    and id = nullif(review_row.data ->> 'application_rule_id', '')::uuid;

  if found then
    select *
    into application_row
    from public.application_catalog
    where user_id = p_owner_id
      and id = rule_row.application_id;
  end if;

  select *
  into feedback_row
  from public.classification_feedback
  where user_id = p_owner_id
    and activity_segment_id = review_row.activity_segment_id
    and data ->> 'review_item_id' = review_row.id::text
  order by updated_at desc, created_at desc, id
  limit 1;

  return pg_catalog.jsonb_build_object(
    'status', p_status,
    'outcome', p_outcome,
    'reason', p_reason,
    'review_item_id', review_row.id,
    'review_revision', review_row.revision,
    'server_revision', review_row.revision,
    'classification', nullif(review_row.data ->> 'classification', ''),
    'target_task_id', nullif(review_row.data ->> 'target_task_id', '')::uuid,
    'contribution_type', nullif(review_row.data ->> 'contribution_type', ''),
    'attribution_id', nullif(review_row.data ->> 'attribution_id', '')::uuid,
    'contribution_id', nullif(review_row.data ->> 'contribution_id', '')::uuid,
    'application_rule_id', nullif(review_row.data ->> 'application_rule_id', '')::uuid,
    'canonical_review', pg_catalog.to_jsonb(review_row),
    'canonical_attributions', attribution_rows,
    'canonical_contributions', contribution_rows,
    'canonical_application', case
      when application_row.id is null then null
      else pg_catalog.to_jsonb(application_row)
    end,
    'canonical_rule', case
      when rule_row.id is null then null
      else pg_catalog.to_jsonb(rule_row)
    end,
    'canonical_feedback', case
      when feedback_row.id is null then null
      else pg_catalog.to_jsonb(feedback_row)
    end
  );
end;
$$;

revoke all on function taskmaster_internal.activity_classification_response_v0029(
  uuid, uuid, text, text, text
) from public, anon;
grant execute on function taskmaster_internal.activity_classification_response_v0029(
  uuid, uuid, text, text, text
) to authenticated, service_role;

create or replace function taskmaster_internal.classify_activity_review_v0029(
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
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  details jsonb := coalesce(p_details, '{}'::jsonb);
  processed_row public.processed_commands%rowtype;
  review_row public.activity_review_queue%rowtype;
  segment_row public.activity_segments%rowtype;
  existing_attribution public.activity_attributions%rowtype;
  existing_contribution public.activity_contributions%rowtype;
  attribution_row public.activity_attributions%rowtype;
  contribution_row public.activity_contributions%rowtype;
  feedback_row public.classification_feedback%rowtype;
  canonical_application public.application_catalog%rowtype;
  semantic_rule public.application_rules%rowtype;
  canonical_result jsonb;
  raw_result jsonb;
  desired_status text := coalesce(nullif(details ->> 'status', ''), 'confirmed');
  desired_target_type text :=
    coalesce(nullif(details ->> 'target_type', ''), 'task_occurrence');
  desired_contribution_type text := nullif(details ->> 'contribution_type', '');
  desired_platform text := lower(nullif(details ->> 'application_platform', ''));
  desired_identifier text := lower(nullif(details ->> 'application_identifier', ''));
  desired_scope text := nullif(p_rule_scope, '');
  desired_scope_id uuid;
  normalized_identifier text;
  requested_application_id uuid;
  segment_id uuid := nullif(details ->> 'activity_segment_id', '')::uuid;
  canonical_classification text;
  canonical_target_task_id uuid;
  canonical_contribution_type text;
  requested_attribution_id uuid;
  requested_contribution_id uuid;
  requested_rule_id uuid;
  requested_feedback_id uuid;
  desired_confidence numeric :=
    least(1, greatest(0, coalesce((details ->> 'confidence')::numeric, 1)));
  physical_duration bigint;
  credited_duration bigint;
  source_task_id uuid;
  source_session_id uuid;
  is_automatic boolean := coalesce((details ->> 'is_automatic')::boolean, false);
  already_applied boolean := false;
  is_reclassification boolean := false;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_command_id is null
     or p_device_id is null
     or p_device_sequence is null
     or p_review_item_id is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'invalid_expected_revision' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':activity-classification-command:' ||
      p_command_id::text,
      0
    )
  );

  select *
  into processed_row
  from public.processed_commands
  where user_id = owner_id
    and command_id = p_command_id
  for update;
  if found then
    if processed_row.device_id is distinct from p_device_id
       or processed_row.device_sequence is distinct from p_device_sequence
       or processed_row.entity_type is distinct from
         'activity_review_classifications'
       or processed_row.entity_id is distinct from p_review_item_id
       or processed_row.command_type is distinct from 'classify'
       or processed_row.base_revision is distinct from p_expected_revision then
      raise exception 'command_identity_mismatch' using errcode = '22023';
    end if;
    canonical_result :=
      taskmaster_internal.activity_classification_response_v0029(
        owner_id,
        coalesce(
          nullif(processed_row.result ->> 'review_item_id', '')::uuid,
          p_review_item_id
        ),
        case when processed_row.status = 'accepted' then 'accepted' else 'conflict' end,
        coalesce(nullif(processed_row.result ->> 'outcome', ''), 'already_processed'),
        nullif(processed_row.result ->> 'reason', '')
      );
    if processed_row.result is distinct from canonical_result then
      update public.processed_commands
      set result = canonical_result,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where user_id = owner_id
        and command_id = p_command_id;
    end if;
    return canonical_result;
  end if;

  -- Mutable authorization is intentionally checked only after command
  -- identity replay. A response lost before device revocation remains the
  -- same accepted command and receives freshly regenerated canonical state.
  if p_classification is null or pg_catalog.btrim(p_classification) = '' then
    raise exception 'invalid_activity_classification' using errcode = '22023';
  end if;
  if desired_status not in ('confirmed', 'rejected', 'ignored') then
    raise exception 'invalid_activity_review_status' using errcode = '22023';
  end if;
  if desired_scope is not null and desired_scope not in ('task', 'user') then
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

  select *
  into review_row
  from public.activity_review_queue
  where user_id = owner_id
    and id = p_review_item_id
    and deleted_at is null
  for update;

  if not found then
    if p_expected_revision not in (0, 1)
       or segment_id is null
       or not exists (
         select 1
         from public.activity_segments
         where user_id = owner_id
           and id = segment_id
           and deleted_at is null
       ) then
      canonical_result :=
        taskmaster_internal.activity_classification_response_v0029(
          owner_id,
          p_review_item_id,
          'conflict',
          'rejected',
          'missing_entity'
        );
      insert into public.processed_commands (
        user_id, command_id, device_id, device_sequence, entity_type,
        entity_id, command_type, base_revision, status, result,
        created_by_device_id, updated_by_device_id, last_command_id
      ) values (
        owner_id, p_command_id, p_device_id, p_device_sequence,
        'activity_review_classifications', p_review_item_id, 'classify',
        p_expected_revision, 'conflict', canonical_result,
        p_device_id, p_device_id, p_command_id
      );
      return canonical_result;
    end if;
  else
    segment_id := review_row.activity_segment_id;
    if review_row.revision <> p_expected_revision then
      canonical_result :=
        taskmaster_internal.activity_classification_response_v0029(
          owner_id,
          p_review_item_id,
          'conflict',
          'rejected',
          'revision_mismatch'
        );
      insert into public.processed_commands (
        user_id, command_id, device_id, device_sequence, entity_type,
        entity_id, command_type, base_revision, status, result,
        created_by_device_id, updated_by_device_id, last_command_id
      ) values (
        owner_id, p_command_id, p_device_id, p_device_sequence,
        'activity_review_classifications', p_review_item_id, 'classify',
        p_expected_revision, 'conflict', canonical_result,
        p_device_id, p_device_id, p_command_id
      );
      return canonical_result;
    end if;

    canonical_classification := nullif(review_row.data ->> 'classification', '');
    canonical_target_task_id :=
      nullif(review_row.data ->> 'target_task_id', '')::uuid;
    canonical_contribution_type :=
      nullif(review_row.data ->> 'contribution_type', '');

    select *
    into existing_attribution
    from public.activity_attributions
    where user_id = owner_id
      and activity_segment_id = segment_id
      and classification = p_classification
      and target_type = desired_target_type
      and target_id is not distinct from p_target_task_id
      and deleted_at is null
    order by revision desc, updated_at desc, created_at desc, id
    limit 1
    for update;

    if p_target_task_id is not null and desired_contribution_type is not null then
      select *
      into existing_contribution
      from public.activity_contributions
      where user_id = owner_id
        and activity_segment_id = segment_id
        and target_type = desired_target_type
        and target_id = p_target_task_id
        and contribution_type = desired_contribution_type
        and deleted_at is null
      order by revision desc, updated_at desc, created_at desc, id
      limit 1
      for update;
    end if;

    already_applied :=
      review_row.status = desired_status
      and canonical_classification = p_classification
      and canonical_target_task_id is not distinct from p_target_task_id
      and canonical_contribution_type is not distinct from desired_contribution_type
      and existing_attribution.id is not null
      and not exists (
        select 1
        from public.activity_attributions
        where user_id = owner_id
          and activity_segment_id = segment_id
          and id <> existing_attribution.id
          and deleted_at is null
      )
      and (
        (
          (p_target_task_id is null or desired_contribution_type is null)
          and not exists (
            select 1
            from public.activity_contributions
            where user_id = owner_id
              and activity_segment_id = segment_id
              and deleted_at is null
          )
        )
        or (
          p_target_task_id is not null
          and desired_contribution_type is not null
          and existing_contribution.id is not null
          and not exists (
            select 1
            from public.activity_contributions
            where user_id = owner_id
              and activity_segment_id = segment_id
              and id <> existing_contribution.id
              and deleted_at is null
          )
        )
      );
    if already_applied then
      canonical_result :=
        taskmaster_internal.activity_classification_response_v0029(
          owner_id,
          p_review_item_id,
          'accepted',
          'already_applied',
          null
        );
      insert into public.processed_commands (
        user_id, command_id, device_id, device_sequence, entity_type,
        entity_id, command_type, base_revision, status, result,
        created_by_device_id, updated_by_device_id, last_command_id
      ) values (
        owner_id, p_command_id, p_device_id, p_device_sequence,
        'activity_review_classifications', p_review_item_id, 'classify',
        p_expected_revision, 'accepted', canonical_result,
        p_device_id, p_device_id, p_command_id
      );
      return canonical_result;
    end if;
    is_reclassification := review_row.status <> 'pending';
  end if;

  if desired_scope is not null
     and desired_platform is not null
     and desired_identifier is not null then
    desired_scope_id := case
      when desired_scope = 'task' then
        coalesce(p_target_task_id, nullif(details ->> 'rule_scope_id', '')::uuid)
      else owner_id
    end;
    normalized_identifier := private.normalize_application_key(
      desired_platform,
      desired_identifier
    );
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        owner_id::text || ':activity-rule:' || desired_platform || ':' ||
        normalized_identifier || ':' || desired_scope || ':' ||
        coalesce(desired_scope_id::text, 'none'),
        0
      )
    );
    select *
    into canonical_application
    from public.application_catalog
    where user_id = owner_id
      and lower(platform) = desired_platform
      and normalized_application_key = normalized_identifier
      and deleted_at is null
    order by revision desc, updated_at desc, created_at desc, id
    limit 1
    for update;

    if not found then
      requested_application_id :=
        coalesce(
          nullif(details ->> 'application_id', '')::uuid,
          extensions.gen_random_uuid()
        );
      if exists (
        select 1
        from public.application_catalog
        where user_id = owner_id
          and id = requested_application_id
      ) then
        requested_application_id := extensions.gen_random_uuid();
      end if;
      insert into public.application_catalog (
        id,
        user_id,
        platform,
        application_identifier,
        normalized_application_key,
        display_name,
        default_display_name,
        classification,
        first_seen_at,
        last_seen_at,
        created_by_device_id,
        updated_by_device_id,
        last_command_id,
        data
      ) values (
        requested_application_id,
        owner_id,
        desired_platform,
        desired_identifier,
        normalized_identifier,
        coalesce(nullif(details ->> 'application_display_name', ''), desired_identifier),
        coalesce(nullif(details ->> 'application_display_name', ''), desired_identifier),
        p_classification,
        pg_catalog.statement_timestamp(),
        pg_catalog.statement_timestamp(),
        p_device_id,
        p_device_id,
        p_command_id,
        pg_catalog.jsonb_build_object(
          'created_by_activity_classification_v0029', true
        )
      )
      returning * into canonical_application;
    end if;

    -- v0027 predates normalized catalog columns. Supplying the canonical row
    -- makes its inner transaction update/reuse the semantic identity instead
    -- of attempting an obsolete partial catalog insert.
    details := pg_catalog.jsonb_set(
      details,
      '{application_id}',
      pg_catalog.to_jsonb(canonical_application.id::text),
      true
    );
    details := pg_catalog.jsonb_set(
      details,
      '{application_identifier}',
      pg_catalog.to_jsonb(pg_catalog.lower(canonical_application.application_identifier)),
      true
    );

    select *
    into semantic_rule
    from public.application_rules
    where user_id = owner_id
      and application_id = canonical_application.id
      and scope_type = desired_scope
      and scope_id is not distinct from desired_scope_id
      and deleted_at is null
    order by revision desc, updated_at desc, created_at desc, id
    limit 1
    for update;
    if not found
       and nullif(details ->> 'rule_id', '') is not null
       and exists (
         select 1
         from public.application_rules
         where user_id = owner_id
           and id = (details ->> 'rule_id')::uuid
       ) then
      details := pg_catalog.jsonb_set(
        details,
        '{rule_id}',
        pg_catalog.to_jsonb(extensions.gen_random_uuid()::text),
        true
      );
    end if;
  end if;

  if is_reclassification then
    select *
    into segment_row
    from public.activity_segments
    where user_id = owner_id
      and id = segment_id
      and deleted_at is null
    for update;
    if not found then
      raise exception 'missing_activity_segment' using errcode = '23503';
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
        raise exception 'target_task_unavailable' using errcode = '23503';
      end if;
    end if;

    requested_attribution_id := coalesce(
      nullif(details ->> 'attribution_id', '')::uuid,
      extensions.gen_random_uuid()
    );
    if exists (
      select 1 from public.activity_attributions
      where user_id = owner_id
        and id = requested_attribution_id
    ) then
      requested_attribution_id := extensions.gen_random_uuid();
    end if;
    requested_contribution_id := coalesce(
      nullif(details ->> 'contribution_id', '')::uuid,
      extensions.gen_random_uuid()
    );
    if exists (
      select 1 from public.activity_contributions
      where user_id = owner_id
        and id = requested_contribution_id
    ) then
      requested_contribution_id := extensions.gen_random_uuid();
    end if;

    update public.activity_contributions
    set deleted_at = pg_catalog.statement_timestamp(),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        data = activity_contributions.data || pg_catalog.jsonb_build_object(
          'superseded_by_activity_reclassification', true
        )
    where user_id = owner_id
      and activity_segment_id = segment_id
      and deleted_at is null;

    update public.activity_attributions
    set deleted_at = pg_catalog.statement_timestamp(),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        data = activity_attributions.data || pg_catalog.jsonb_build_object(
          'superseded_by_activity_reclassification', true
        )
    where user_id = owner_id
      and activity_segment_id = segment_id
      and deleted_at is null;

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
    ) values (
      requested_attribution_id,
      owner_id,
      segment_id,
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

    requested_feedback_id := coalesce(
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
    ) values (
      requested_feedback_id,
      owner_id,
      segment_id,
      canonical_application.id,
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
    set application_id = excluded.application_id,
        chosen_classification = excluded.chosen_classification,
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
      physical_duration := greatest(
        0,
        coalesce(
          (details ->> 'physical_duration_ms')::bigint,
          segment_row.duration_ms
        )
      );
      credited_duration := least(
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
      ) values (
        requested_contribution_id,
        owner_id,
        segment_id,
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
    end if;

    if desired_scope is not null and canonical_application.id is not null then
      if semantic_rule.id is not null then
        update public.application_rules
        set classification = p_classification,
            target_type = case
              when p_target_task_id is null then null
              else desired_target_type
            end,
            target_id = p_target_task_id,
            contribution_type = desired_contribution_type,
            automatic_credit = p_target_task_id is not null
              and desired_contribution_type is not null,
            priority = coalesce((details ->> 'rule_priority')::integer, 200),
            updated_by_device_id = p_device_id,
            last_command_id = p_command_id,
            data = application_rules.data || pg_catalog.jsonb_build_object(
              'rule_origin', 'user_confirmed'
            )
        where user_id = owner_id
          and id = semantic_rule.id
        returning * into semantic_rule;
      else
        requested_rule_id := coalesce(
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
        ) values (
          requested_rule_id,
          owner_id,
          canonical_application.id,
          desired_scope,
          desired_scope_id,
          p_classification,
          case when p_target_task_id is null then null else desired_target_type end,
          p_target_task_id,
          desired_contribution_type,
          p_target_task_id is not null and desired_contribution_type is not null,
          coalesce((details ->> 'rule_priority')::integer, 200),
          p_device_id,
          p_device_id,
          p_command_id,
          pg_catalog.jsonb_build_object('rule_origin', 'user_confirmed')
        )
        returning * into semantic_rule;
      end if;
    end if;

    -- Exactly one current-review UPDATE means accepted revision N becomes
    -- canonical revision N + 1. A following offline command may safely use it.
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
          'application_rule_id', semantic_rule.id,
          'classification_command_id', p_command_id,
          'reclassified_from_revision', p_expected_revision
        )
    where user_id = owner_id
      and id = p_review_item_id
      and revision = p_expected_revision
    returning * into review_row;
    if not found then
      raise exception 'activity_review_revision_changed' using errcode = '40001';
    end if;

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
      and activity_segment_id = segment_id
      and id <> p_review_item_id
      and status = 'pending'
      and deleted_at is null;

    canonical_result :=
      taskmaster_internal.activity_classification_response_v0029(
        owner_id,
        p_review_item_id,
        'accepted',
        'reclassified',
        null
      );
    insert into public.processed_commands (
      user_id, command_id, device_id, device_sequence, entity_type,
      entity_id, command_type, base_revision, status, result,
      created_by_device_id, updated_by_device_id, last_command_id
    ) values (
      owner_id, p_command_id, p_device_id, p_device_sequence,
      'activity_review_classifications', p_review_item_id, 'classify',
      p_expected_revision, 'accepted', canonical_result,
      p_device_id, p_device_id, p_command_id
    );
    return canonical_result;
  end if;

  if existing_attribution.id is null
     and nullif(details ->> 'attribution_id', '') is not null
     and exists (
       select 1 from public.activity_attributions
       where user_id = owner_id
         and id = (details ->> 'attribution_id')::uuid
     ) then
    details := pg_catalog.jsonb_set(
      details,
      '{attribution_id}',
      pg_catalog.to_jsonb(extensions.gen_random_uuid()::text),
      true
    );
  end if;
  if existing_contribution.id is null
     and nullif(details ->> 'contribution_id', '') is not null
     and exists (
       select 1 from public.activity_contributions
       where user_id = owner_id
         and id = (details ->> 'contribution_id')::uuid
     ) then
    details := pg_catalog.jsonb_set(
      details,
      '{contribution_id}',
      pg_catalog.to_jsonb(extensions.gen_random_uuid()::text),
      true
    );
  end if;

  raw_result := taskmaster_internal.classify_activity_review_v0027(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_review_item_id,
    p_expected_revision,
    p_classification,
    p_target_task_id,
    desired_scope,
    details
  );
  canonical_result :=
    taskmaster_internal.activity_classification_response_v0029(
      owner_id,
      coalesce(
        nullif(raw_result ->> 'review_item_id', '')::uuid,
        p_review_item_id
      ),
      coalesce(nullif(raw_result ->> 'status', ''), 'accepted'),
      coalesce(nullif(raw_result ->> 'outcome', ''), 'applied'),
      nullif(raw_result ->> 'reason', '')
    );
  update public.processed_commands
  set status = case
        when canonical_result ->> 'status' = 'accepted'
          then 'accepted'::public.sync_command_status
        else 'conflict'::public.sync_command_status
      end,
      result = canonical_result,
      updated_by_device_id = p_device_id,
      last_command_id = p_command_id
  where user_id = owner_id
    and command_id = p_command_id;
  return canonical_result;
end;
$$;

revoke all on function taskmaster_internal.classify_activity_review_v0029(
  uuid, uuid, bigint, uuid, bigint, text, uuid, text, jsonb
) from public, anon;
grant execute on function taskmaster_internal.classify_activity_review_v0029(
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
  select taskmaster_internal.classify_activity_review_v0029(
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
  'Revision-guarded and idempotent Activity classification/reclassification with a complete canonical convergence response.';
