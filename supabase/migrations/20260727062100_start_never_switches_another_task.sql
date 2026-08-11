-- Keep the legacy transition implementation for valid boundaries, but place a
-- strict guard in front of `start`.  Only the explicit switch RPC may replace
-- the canonical active task.
alter function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) rename to apply_execution_transition_v0026_command_legacy;

create function public.apply_execution_transition_v0026_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_session_id uuid,
  p_task_occurrence_id uuid,
  p_action text,
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
begin
  if p_action = 'start' and owner_id is not null then
    select * into runtime
    from public.user_runtime_state
    where user_id = owner_id;
    if found and runtime.active_session_id is not null
        and runtime.active_session_id <> p_session_id
        and runtime.state in ('running', 'paused', 'break') then
      return jsonb_build_object(
        'status', 'conflict',
        'reason', 'another_task_running',
        'active_task_id', runtime.active_task_occurrence_id,
        'runtime_revision', runtime.revision,
        'runtime_state', runtime.state
      );
    end if;
  end if;
  return public.apply_execution_transition_v0026_command_legacy(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_session_id,
    p_task_occurrence_id,
    p_action,
    p_mode
  );
end;
$$;

revoke all on function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) from public, anon;
grant execute on function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) to authenticated;
