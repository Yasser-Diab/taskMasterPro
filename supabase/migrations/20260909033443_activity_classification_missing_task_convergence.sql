-- DayVector v0.0.30 reliability repair: a task can disappear on another
-- device while an activity review is still queued locally.  That must converge
-- to an unlinked activity decision, never become a permanent retry storm and
-- never credit time to a replacement task.

-- Retire every active task-bound artifact whose task is gone.  Tombstones are
-- intentionally retained for sync convergence and historical auditability.
update public.activity_contributions as contribution
set deleted_at = pg_catalog.statement_timestamp(),
    data = contribution.data || pg_catalog.jsonb_build_object(
      'tombstoned_by_v0031', true,
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

update public.activity_attributions as attribution
set deleted_at = pg_catalog.statement_timestamp(),
    data = attribution.data || pg_catalog.jsonb_build_object(
      'tombstoned_by_v0031', true,
      'repair_reason', 'target_task_unavailable'
    )
where attribution.deleted_at is null
  and attribution.target_type = 'task_occurrence'
  and attribution.target_id is not null
  and not exists (
    select 1
    from public.task_occurrences as task
    where task.user_id = attribution.user_id
      and task.id = attribution.target_id
      and task.deleted_at is null
  );

-- A resolved review is still the canonical user decision, but its deleted task
-- link and task-credit metadata are not.  Keep the decision and make the
-- canonical response explicitly unlinked.  Do not add repair metadata to this
-- privacy-constrained table: its established safe metadata contract remains
-- unchanged.
update public.activity_review_queue as review
set suggested_targets = '[]'::jsonb,
    data = (
      review.data
      - 'target_task_id'
      - 'target_type'
      - 'contribution_type'
      - 'contribution_id'
      - 'suggested_target_id'
      - 'suggested_target_type'
      - 'rule_scope_id'
      - 'application_rule_id'
    )
where review.deleted_at is null
  and nullif(review.data ->> 'target_task_id', '') is not null
  and not exists (
    select 1
    from public.task_occurrences as task
    where task.user_id = review.user_id
      and task.id::text = review.data ->> 'target_task_id'
      and task.deleted_at is null
  );

update public.classification_feedback as feedback
set chosen_target_type = null,
    chosen_target_id = null,
    data = feedback.data || pg_catalog.jsonb_build_object(
      'orphaned_target_task_id', feedback.chosen_target_id::text,
      'target_task_unavailable', true,
      'repair_reason', 'target_task_unavailable_unlinked'
    )
where feedback.deleted_at is null
  and feedback.chosen_target_type = 'task_occurrence'
  and feedback.chosen_target_id is not null
  and not exists (
    select 1
    from public.task_occurrences as task
    where task.user_id = feedback.user_id
      and task.id = feedback.chosen_target_id
      and task.deleted_at is null
  );

-- A task-scoped rule without its task would otherwise manufacture the same
-- invalid command again.  Retire it rather than broadening a task-specific
-- decision into a global rule.
update public.application_rules as rule
set deleted_at = pg_catalog.statement_timestamp(),
    data = rule.data || pg_catalog.jsonb_build_object(
      'tombstoned_by_v0031', true,
      'repair_reason', 'target_task_unavailable',
      'orphaned_target_task_id', coalesce(rule.target_id, rule.scope_id)::text
    )
where rule.deleted_at is null
  and (
    (
      rule.target_type = 'task_occurrence'
      and rule.target_id is not null
      and not exists (
        select 1
        from public.task_occurrences as task
        where task.user_id = rule.user_id
          and task.id = rule.target_id
          and task.deleted_at is null
      )
    )
    or (
      rule.scope_type = 'task'
      and rule.scope_id is not null
      and not exists (
        select 1
        from public.task_occurrences as task
        where task.user_id = rule.user_id
          and task.id = rule.scope_id
          and task.deleted_at is null
      )
    )
  );

-- The v0029 aggregate is still authoritative.  This wrapper handles the race
-- where a task is deleted after a device creates its command but before the
-- command reaches the server.  Only the exact, verified stale-target error is
-- converted; every other integrity error retains its original behaviour.
create or replace function taskmaster_internal.classify_activity_review_v0031(
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
  fallback_details jsonb;
begin
  begin
    return taskmaster_internal.classify_activity_review_v0029(
      p_command_id,
      p_device_id,
      p_device_sequence,
      p_review_item_id,
      p_expected_revision,
      p_classification,
      p_target_task_id,
      p_rule_scope,
      p_details
    );
  exception
    when foreign_key_violation then
      if SQLERRM <> 'target_task_unavailable'
         or p_target_task_id is null
         or owner_id is null
         or exists (
           select 1
           from public.task_occurrences as task
           where task.user_id = owner_id
             and task.id = p_target_task_id
             and task.deleted_at is null
         ) then
        raise;
      end if;

      -- The failing v0029 subtransaction is rolled back before this handler
      -- runs.  Repair every stale artifact for this exact task, then submit
      -- the original activity decision without a target or task-scoped rule.
      update public.activity_review_queue as review
      set suggested_targets = '[]'::jsonb,
          data = (
            review.data
            - 'target_task_id'
            - 'target_type'
            - 'contribution_type'
            - 'contribution_id'
            - 'suggested_target_id'
            - 'suggested_target_type'
            - 'rule_scope_id'
            - 'application_rule_id'
          )
      where review.user_id = owner_id
        and review.id = p_review_item_id
        and review.deleted_at is null
        and review.data ->> 'target_task_id' = p_target_task_id::text;

      update public.activity_contributions as contribution
      set deleted_at = pg_catalog.statement_timestamp(),
          data = contribution.data || pg_catalog.jsonb_build_object(
            'tombstoned_by_v0031', true,
            'repair_reason', 'target_task_unavailable'
          )
      where contribution.user_id = owner_id
        and contribution.deleted_at is null
        and contribution.target_type = 'task_occurrence'
        and contribution.target_id = p_target_task_id;

      update public.activity_attributions as attribution
      set deleted_at = pg_catalog.statement_timestamp(),
          data = attribution.data || pg_catalog.jsonb_build_object(
            'tombstoned_by_v0031', true,
            'repair_reason', 'target_task_unavailable'
          )
      where attribution.user_id = owner_id
        and attribution.deleted_at is null
        and attribution.target_type = 'task_occurrence'
        and attribution.target_id = p_target_task_id;

      update public.classification_feedback as feedback
      set chosen_target_type = null,
          chosen_target_id = null,
          data = feedback.data || pg_catalog.jsonb_build_object(
            'orphaned_target_task_id', p_target_task_id::text,
            'target_task_unavailable', true,
            'repair_reason', 'target_task_unavailable_unlinked'
          )
      where feedback.user_id = owner_id
        and feedback.deleted_at is null
        and feedback.chosen_target_type = 'task_occurrence'
        and feedback.chosen_target_id = p_target_task_id;

      update public.application_rules as rule
      set deleted_at = pg_catalog.statement_timestamp(),
          data = rule.data || pg_catalog.jsonb_build_object(
            'tombstoned_by_v0031', true,
            'repair_reason', 'target_task_unavailable',
            'orphaned_target_task_id', p_target_task_id::text
          )
      where rule.user_id = owner_id
        and rule.deleted_at is null
        and (
          (rule.target_type = 'task_occurrence' and rule.target_id = p_target_task_id)
          or (rule.scope_type = 'task' and rule.scope_id = p_target_task_id)
        );

      fallback_details := (
          coalesce(p_details, '{}'::jsonb)
          - 'target_task_id'
          - 'target_type'
          - 'contribution_type'
          - 'contribution_id'
          - 'rule_scope_id'
          - 'rule_id'
        );

      return taskmaster_internal.classify_activity_review_v0029(
        p_command_id,
        p_device_id,
        p_device_sequence,
        p_review_item_id,
        p_expected_revision,
        p_classification,
        null,
        null,
        fallback_details
      );
  end;
end;
$$;

revoke all on function taskmaster_internal.classify_activity_review_v0031(
  uuid, uuid, bigint, uuid, bigint, text, uuid, text, jsonb
) from public, anon;
grant execute on function taskmaster_internal.classify_activity_review_v0031(
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
  select taskmaster_internal.classify_activity_review_v0031(
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
  'Revision-guarded and idempotent Activity classification with canonical convergence when a selected task was deleted on another device.';
