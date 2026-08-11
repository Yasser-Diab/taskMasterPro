-- The guarded public transition RPC delegates to the original implementation.
-- Keeping that implementation in the exposed `public` schema made it callable
-- through `/rest/v1/rpc/...`, allowing an authenticated client to bypass the
-- "start never switches another task" guard. Move the implementation to a
-- deliberately unexposed schema while retaining SECURITY INVOKER semantics.

create schema if not exists taskmaster_internal;

revoke all on schema taskmaster_internal from public, anon;
grant usage on schema taskmaster_internal to authenticated, service_role;

alter function public.apply_execution_transition_v0026_command_legacy(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) set schema taskmaster_internal;

revoke all on function
  taskmaster_internal.apply_execution_transition_v0026_command_legacy(
    uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
  )
from public, anon;

grant execute on function
  taskmaster_internal.apply_execution_transition_v0026_command_legacy(
    uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
  )
to authenticated, service_role;

create or replace function public.apply_execution_transition_v0026_command(
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
  if owner_id is not null then
    perform pg_advisory_xact_lock(
      hashtextextended(owner_id::text || ':execution-runtime', 0)
    );
  end if;

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

  return
    taskmaster_internal.apply_execution_transition_v0026_command_legacy(
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

comment on schema taskmaster_internal is
  'Unexposed implementation details used by guarded TaskMaster Pro RPCs.';

comment on function
  taskmaster_internal.apply_execution_transition_v0026_command_legacy(
    uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
  ) is
  'Internal canonical transition implementation. Not exposed by the Data API.';
