-- A selected task may only replace the active task through this explicit,
-- atomic hand-off.  `start` and `resume` remain separate operations so a
-- stale local card can never resume an unrelated session.

create or replace function public.apply_execution_switch_v0026_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_new_session_id uuid,
  p_new_task_occurrence_id uuid,
  p_expected_active_session_id uuid,
  p_expected_active_task_id uuid,
  p_current_task_action text,
  p_mode public.execution_mode
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  runtime public.user_runtime_state%rowtype;
  active_ms bigint := 0;
  old_planned_ms bigint := 0;
  result_payload jsonb;
  existing_result jsonb;
  now_at timestamptz := statement_timestamp();
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_current_task_action not in ('pause', 'finish') then
    raise exception 'unsupported_active_task_action';
  end if;
  if not exists (
    select 1 from public.account_devices
    where id = p_device_id and user_id = owner_id
      and revoked_at is null and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':execution-runtime', 0)
  );
  select result into existing_result
  from public.processed_commands
  where user_id = owner_id and command_id = p_command_id;
  if found then
    return existing_result;
  end if;

  select * into runtime
  from public.user_runtime_state
  where user_id = owner_id
  for update;

  if not found or runtime.active_session_id is distinct from p_expected_active_session_id
      or runtime.active_task_occurrence_id is distinct from p_expected_active_task_id
      or runtime.state not in ('running', 'paused', 'break') then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'active_task_changed'
    );
  elsif not exists (
    select 1 from public.task_occurrences
    where id = p_new_task_occurrence_id and user_id = owner_id and deleted_at is null
  ) then
    result_payload := jsonb_build_object('status', 'conflict', 'reason', 'missing_task');
  elsif not exists (
    select 1 from public.execution_sessions
    where id = p_new_session_id and user_id = owner_id and deleted_at is null
  ) then
    result_payload := jsonb_build_object('status', 'conflict', 'reason', 'missing_session');
  else
    active_ms := runtime.accumulated_active_ms + case
      when runtime.state = 'running' and runtime.active_segment_started_at is not null
        then greatest(0, extract(epoch from now_at - runtime.active_segment_started_at) * 1000)::bigint
      else 0
    end;
    select estimated_duration_ms into old_planned_ms
    from public.task_occurrences
    where id = runtime.active_task_occurrence_id and user_id = owner_id;

    if p_current_task_action = 'finish' then
      update public.execution_sessions
      set state = 'completed', finished_at = now_at, active_segment_started_at = null,
          accumulated_active_ms = active_ms, updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.active_session_id and user_id = owner_id;
      update public.task_occurrences
      set status = 'completed', actual_finish = now_at, active_duration_ms = active_ms,
          progress = 1, updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.active_task_occurrence_id and user_id = owner_id;
    else
      update public.execution_sessions
      set state = 'paused', active_segment_started_at = null,
          accumulated_active_ms = active_ms, updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.active_session_id and user_id = owner_id;
      update public.task_occurrences
      set status = 'paused', active_duration_ms = active_ms,
          progress = case
            when old_planned_ms > 0 then least(1::numeric, active_ms::numeric / old_planned_ms)
            else progress
          end,
          updated_by_device_id = p_device_id, last_command_id = p_command_id
      where id = runtime.active_task_occurrence_id and user_id = owner_id;
    end if;

    update public.execution_sessions
    set task_occurrence_id = p_new_task_occurrence_id,
        mode = p_mode, state = 'running',
        started_at = coalesce(started_at, now_at), finished_at = null,
        active_segment_started_at = now_at,
        accumulated_active_ms = coalesce(accumulated_active_ms, 0),
        current_pomodoro_segment = case when p_mode = 'pomodoro' then 'focus' else null end,
        updated_by_device_id = p_device_id, last_command_id = p_command_id
    where id = p_new_session_id and user_id = owner_id;
    update public.task_occurrences
    set status = 'in_progress', actual_start = coalesce(actual_start, now_at),
        updated_by_device_id = p_device_id, last_command_id = p_command_id
    where id = p_new_task_occurrence_id and user_id = owner_id;
    update public.user_runtime_state
    set active_session_id = p_new_session_id,
        active_task_occurrence_id = p_new_task_occurrence_id,
        state = 'running', active_segment_started_at = now_at,
        accumulated_active_ms = 0, accumulated_paused_ms = 0,
        lease_device_id = p_device_id, updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where id = runtime.id
    returning * into runtime;
    result_payload := jsonb_build_object('status', 'accepted');
  end if;

  select * into runtime from public.user_runtime_state where user_id = owner_id;
  result_payload := result_payload || jsonb_build_object(
    'session_id', p_new_session_id,
    'runtime_revision', coalesce(runtime.revision, 0),
    'runtime_state', coalesce(runtime.state, 'idle')
  );
  insert into public.processed_commands (
    user_id, command_id, device_id, device_sequence, entity_type, entity_id,
    command_type, base_revision, status, result, created_by_device_id,
    updated_by_device_id, last_command_id
  ) values (
    owner_id, p_command_id, p_device_id, p_device_sequence,
    'execution_runtime_switch', p_new_session_id, p_current_task_action,
    coalesce(runtime.revision, 0),
    case when result_payload ->> 'status' = 'accepted'
      then 'accepted'::public.sync_command_status else 'conflict'::public.sync_command_status end,
    result_payload, p_device_id, p_device_id, p_command_id
  );
  return result_payload;
end;
$$;

revoke all on function public.apply_execution_switch_v0026_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode
) from public, anon;
grant execute on function public.apply_execution_switch_v0026_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode
) to authenticated;
