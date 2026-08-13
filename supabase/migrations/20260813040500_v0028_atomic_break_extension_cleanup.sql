-- Break extension cleanup is part of the same revision-guarded runtime intent
-- that leaves (or skips) a break. It must never be a second task-occurrence
-- command that can conflict, retry independently, or arrive after a newer
-- focus interval.

create function taskmaster_internal.apply_execution_transition_v0028_break_safe_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_session_id uuid,
  p_task_occurrence_id uuid,
  p_action text,
  p_mode public.execution_mode,
  p_expected_runtime_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  guard_result jsonb;
  result_payload jsonb;
  owner_id uuid := (select auth.uid());
  runtime_before public.user_runtime_state%rowtype;
begin
  -- Guard before delegating so a retry of an already-processed command exits
  -- before touching task data. The delegated v0028 function repeats this
  -- guard under the same transaction-scoped advisory lock; that is harmless
  -- and keeps all existing expected-revision and deduplication semantics.
  guard_result := taskmaster_internal.guard_execution_runtime_v0028_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    'execution_runtime',
    p_session_id,
    p_action,
    p_expected_runtime_revision
  );
  if guard_result is not null then
    return guard_result;
  end if;

  select *
  into runtime_before
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id;

  result_payload := taskmaster_internal.apply_execution_transition_v0028_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_session_id,
    p_task_occurrence_id,
    p_action,
    p_mode,
    p_expected_runtime_revision
  );

  if result_payload ->> 'status' = 'accepted'
      and coalesce((result_payload ->> 'canonical_only')::boolean, false) = false
      and runtime_before.active_session_id = p_session_id
      and runtime_before.active_task_occurrence_id = p_task_occurrence_id
      and (
        (p_action in ('start_break', 'skip_break') and runtime_before.state = 'running')
        or (p_action = 'finish_break' and runtime_before.state = 'break')
      ) then
    update public.task_occurrences
    set data = coalesce(data, '{}'::jsonb) - 'active_break_extension_ms',
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where id = p_task_occurrence_id
      and user_id = owner_id
      and deleted_at is null
      and coalesce(data, '{}'::jsonb) ? 'active_break_extension_ms';
  end if;

  return result_payload;
end;
$$;

create or replace function public.apply_execution_transition_v0028_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_session_id uuid,
  p_task_occurrence_id uuid,
  p_action text,
  p_mode public.execution_mode,
  p_expected_runtime_revision bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_execution_transition_v0028_break_safe_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_session_id,
    p_task_occurrence_id,
    p_action,
    p_mode,
    p_expected_runtime_revision
  )
$$;

revoke all on function taskmaster_internal.apply_execution_transition_v0028_break_safe_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) from public, anon;
grant execute on function taskmaster_internal.apply_execution_transition_v0028_break_safe_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) to authenticated, service_role;

revoke all on function public.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) from public, anon;
grant execute on function public.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) to authenticated;

comment on function public.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) is
  'Revision-guarded canonical runtime transition with atomic one-break extension cleanup and idempotent retry behavior.';
