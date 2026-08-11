-- Canonical completion restoration for TaskMaster Pro v0.0.26.
--
-- Completion is committed by the execution transition RPC. Undo and Reopen
-- therefore have to use the same serialized command stream; a generic task
-- update can race a completion arriving from another device and resurrect a
-- stale timer. The user-visible Undo window is 15 seconds. The server accepts
-- five additional seconds only as transport grace for an action initiated at
-- the end of that window.

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
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  runtime public.user_runtime_state%rowtype;
  task_record public.task_occurrences%rowtype;
  existing_result jsonb;
  result_payload jsonb;
  now_at timestamptz := statement_timestamp();
  has_execution_session boolean := false;
  restored_status public.task_status;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.account_devices device_row
    where device_row.id = p_device_id
      and device_row.user_id = owner_id
      and device_row.revoked_at is null
      and device_row.deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':execution-runtime', 0)
  );

  select command_row.result
  into existing_result
  from public.processed_commands command_row
  where command_row.user_id = owner_id
    and command_row.command_id = p_command_id;

  if found then
    return existing_result;
  end if;

  select *
  into runtime
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id
  for update;

  -- Starting never switches another active task implicitly. Persisting this
  -- conflict makes retries idempotent and gives diagnostics a durable reason.
  if p_action = 'start'
      and found
      and runtime.active_session_id is not null
      and runtime.active_session_id <> p_session_id
      and runtime.state in ('running', 'paused', 'break') then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'another_task_running',
      'active_task_id', runtime.active_task_occurrence_id,
      'runtime_revision', runtime.revision,
      'runtime_state', runtime.state
    );

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
    ) values (
      owner_id,
      p_command_id,
      p_device_id,
      p_device_sequence,
      'execution_runtime',
      p_session_id,
      p_action,
      runtime.revision,
      'conflict'::public.sync_command_status,
      result_payload,
      p_device_id,
      p_device_id,
      p_command_id
    );

    return result_payload;
  end if;

  if p_action not in ('undo_complete', 'reopen') then
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
  end if;

  select *
  into task_record
  from public.task_occurrences task_row
  where task_row.user_id = owner_id
    and task_row.id = p_task_occurrence_id
    and task_row.deleted_at is null
  for update;

  if not found then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'missing_task',
      'task_id', p_task_occurrence_id
    );
  elsif task_record.status <> 'completed' then
    -- Another online device may already have restored this completion. That
    -- is convergence, not a user-visible conflict.
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'canonical_only', true,
      'task_id', task_record.id,
      'task_revision', task_record.revision,
      'task_status', task_record.status
    );
  elsif p_action = 'undo_complete'
      and (
        task_record.actual_finish is null
        or now_at > task_record.actual_finish + interval '20 seconds'
      ) then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'undo_window_elapsed',
      'task_id', task_record.id,
      'completed_at', task_record.actual_finish,
      'undo_expires_at',
        task_record.actual_finish + interval '15 seconds'
    );
  elsif p_action = 'reopen'
      and task_record.actual_finish is not null
      and now_at < task_record.actual_finish + interval '15 seconds' then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'undo_still_available',
      'task_id', task_record.id,
      'completed_at', task_record.actual_finish,
      'undo_expires_at',
        task_record.actual_finish + interval '15 seconds'
    );
  else
    select exists (
      select 1
      from public.execution_sessions session_row
      where session_row.user_id = owner_id
        and session_row.id = p_session_id
        and session_row.task_occurrence_id = p_task_occurrence_id
        and session_row.deleted_at is null
    )
    into has_execution_session;

    restored_status := case
      when has_execution_session then 'paused'::public.task_status
      else 'ready'::public.task_status
    end;

    update public.task_occurrences
    set status = restored_status,
        actual_finish = null,
        progress = case
          when estimated_duration_ms > 0
            then least(
              1::numeric,
              active_duration_ms::numeric / estimated_duration_ms
            )
          else 0::numeric
        end,
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where user_id = owner_id
      and id = p_task_occurrence_id
    returning * into task_record;

    -- Do not reactivate the old execution session or replace a newer runtime.
    -- The retained completed session is auditable history; a later Start
    -- creates or activates the appropriate canonical session explicitly.
    if has_execution_session then
      insert into public.session_events (
        id,
        user_id,
        session_id,
        event_type,
        occurred_at,
        source_device_id,
        event_payload,
        created_by_device_id,
        updated_by_device_id,
        last_command_id
      ) values (
        gen_random_uuid(),
        owner_id,
        p_session_id,
        case
          when p_action = 'undo_complete' then 'completion_undone'
          else 'reopened'
        end,
        now_at,
        p_device_id,
        jsonb_build_object(
          'task_occurrence_id', p_task_occurrence_id,
          'restored_status', restored_status,
          'preserved_active_duration_ms', task_record.active_duration_ms
        ),
        p_device_id,
        p_device_id,
        p_command_id
      );
    end if;

    result_payload := jsonb_build_object(
      'status', 'accepted',
      'task_id', task_record.id,
      'task_revision', task_record.revision,
      'task_status', task_record.status,
      'active_duration_ms', task_record.active_duration_ms,
      'progress', task_record.progress
    );
  end if;

  select *
  into runtime
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id;

  result_payload := result_payload || jsonb_build_object(
    'session_id', p_session_id,
    'runtime_revision', coalesce(runtime.revision, 0),
    'runtime_state', coalesce(runtime.state::text, 'idle')
  );

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
  ) values (
    owner_id,
    p_command_id,
    p_device_id,
    p_device_sequence,
    'execution_runtime',
    p_session_id,
    p_action,
    task_record.revision,
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

revoke all on function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) from public, anon;

grant execute on function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) to authenticated;

comment on function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) is
  'Serialized canonical task execution, completion, 15-second Undo, and Reopen command endpoint.';
