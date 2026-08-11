-- One authoritative running-task state per account.  Individual clients keep
-- a local cache for instant UI feedback, but every start/pause/resume/break
-- transition is committed here before it becomes canonical for other devices.

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
  active_session public.execution_sessions%rowtype;
  active_ms bigint := 0;
  result_payload jsonb;
  existing_result jsonb;
  now_at timestamptz := statement_timestamp();
  planned_ms bigint := 0;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_action not in ('start', 'pause', 'resume', 'start_break', 'finish_break', 'complete') then
    raise exception 'unsupported_execution_transition';
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
  if not found then
    insert into public.user_runtime_state (id, user_id)
    values (gen_random_uuid(), owner_id)
    returning * into runtime;
  end if;

  -- Starting another task ends the previous active segment first.  The prior
  -- session is retained as paused history rather than being duplicated.
  if p_action = 'start' then
    if runtime.active_session_id is not null
       and runtime.active_session_id <> p_session_id
       and runtime.state in ('running', 'paused', 'break') then
      update public.execution_sessions
      set state = 'paused',
          active_segment_started_at = null,
          accumulated_active_ms = case
            when runtime.state = 'running' and runtime.active_segment_started_at is not null
              then runtime.accumulated_active_ms + greatest(0, extract(epoch from now_at - runtime.active_segment_started_at) * 1000)::bigint
            else runtime.accumulated_active_ms
          end,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.active_session_id and user_id = owner_id;
      update public.task_occurrences
      set status = 'paused',
          active_duration_ms = case
            when runtime.state = 'running' and runtime.active_segment_started_at is not null
              then runtime.accumulated_active_ms + greatest(0, extract(epoch from now_at - runtime.active_segment_started_at) * 1000)::bigint
            else runtime.accumulated_active_ms
          end,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.active_task_occurrence_id and user_id = owner_id;
    end if;

    select estimated_duration_ms into planned_ms
    from public.task_occurrences
    where id = p_task_occurrence_id and user_id = owner_id and deleted_at is null;
    if planned_ms is null then
      result_payload := jsonb_build_object('status', 'conflict', 'reason', 'missing_task');
    elsif not exists (
      select 1 from public.execution_sessions
      where id = p_session_id and user_id = owner_id and deleted_at is null
    ) then
      result_payload := jsonb_build_object('status', 'conflict', 'reason', 'missing_session');
    else
      update public.execution_sessions
      set task_occurrence_id = p_task_occurrence_id,
          mode = p_mode,
          state = 'running',
          started_at = coalesce(started_at, now_at),
          finished_at = null,
          active_segment_started_at = now_at,
          accumulated_active_ms = coalesce(accumulated_active_ms, 0),
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id,
          deleted_at = null
      where id = p_session_id and user_id = owner_id;
      update public.task_occurrences
      set status = 'in_progress',
          actual_start = coalesce(actual_start, now_at),
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = p_task_occurrence_id and user_id = owner_id;
      update public.user_runtime_state
      set active_session_id = p_session_id,
          active_task_occurrence_id = p_task_occurrence_id,
          state = 'running',
          active_segment_started_at = now_at,
          accumulated_active_ms = 0,
          accumulated_paused_ms = 0,
          lease_device_id = p_device_id,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.id
      returning * into runtime;
      result_payload := jsonb_build_object('status', 'accepted');
    end if;
  elsif runtime.active_session_id is distinct from p_session_id
        or runtime.active_task_occurrence_id is distinct from p_task_occurrence_id then
    -- A late action from another device must not create a second timer.
    result_payload := jsonb_build_object('status', 'accepted', 'canonical_only', true);
  else
    select * into active_session
    from public.execution_sessions
    where id = runtime.active_session_id and user_id = owner_id
    for update;
    active_ms := runtime.accumulated_active_ms + case
      when runtime.state = 'running' and runtime.active_segment_started_at is not null
        then greatest(0, extract(epoch from now_at - runtime.active_segment_started_at) * 1000)::bigint
      else 0
    end;
    select estimated_duration_ms into planned_ms
    from public.task_occurrences where id = p_task_occurrence_id and user_id = owner_id;

    if p_action = 'pause' then
      if runtime.state = 'running' then
        update public.execution_sessions
        set state = 'paused', active_segment_started_at = null,
            accumulated_active_ms = active_ms, updated_by_device_id = p_device_id,
            last_command_id = p_command_id
        where id = runtime.active_session_id and user_id = owner_id;
        update public.task_occurrences
        set status = 'paused', active_duration_ms = active_ms,
            progress = case when planned_ms > 0 then least(1::numeric, active_ms::numeric / planned_ms) else progress end,
            updated_by_device_id = p_device_id, last_command_id = p_command_id
        where id = p_task_occurrence_id and user_id = owner_id;
        update public.user_runtime_state
        set state = 'paused', active_segment_started_at = null,
            accumulated_active_ms = active_ms, lease_device_id = p_device_id,
            updated_by_device_id = p_device_id, last_command_id = p_command_id
        where id = runtime.id returning * into runtime;
      end if;
      result_payload := jsonb_build_object('status', 'accepted');
    elsif p_action = 'resume' then
      if runtime.state = 'paused' then
        update public.execution_sessions
        set state = 'running', active_segment_started_at = now_at,
            updated_by_device_id = p_device_id, last_command_id = p_command_id
        where id = runtime.active_session_id and user_id = owner_id;
        update public.task_occurrences
        set status = 'in_progress', updated_by_device_id = p_device_id,
            last_command_id = p_command_id
        where id = p_task_occurrence_id and user_id = owner_id;
        update public.user_runtime_state
        set state = 'running', active_segment_started_at = now_at,
            lease_device_id = p_device_id, updated_by_device_id = p_device_id,
            last_command_id = p_command_id
        where id = runtime.id returning * into runtime;
      end if;
      result_payload := jsonb_build_object('status', 'accepted');
    elsif p_action = 'start_break' then
      if runtime.state = 'running' then
        update public.execution_sessions
        set state = 'break', active_segment_started_at = now_at,
            accumulated_active_ms = active_ms,
            current_pomodoro_segment = 'break', updated_by_device_id = p_device_id,
            last_command_id = p_command_id
        where id = runtime.active_session_id and user_id = owner_id;
        update public.task_occurrences
        set active_duration_ms = active_ms,
            progress = case when planned_ms > 0 then least(1::numeric, active_ms::numeric / planned_ms) else progress end,
            updated_by_device_id = p_device_id, last_command_id = p_command_id
        where id = p_task_occurrence_id and user_id = owner_id;
        update public.user_runtime_state
        set state = 'break', active_segment_started_at = now_at,
            accumulated_active_ms = active_ms, lease_device_id = p_device_id,
            updated_by_device_id = p_device_id, last_command_id = p_command_id
        where id = runtime.id returning * into runtime;
      end if;
      result_payload := jsonb_build_object('status', 'accepted');
    elsif p_action = 'finish_break' then
      if runtime.state = 'break' then
        update public.execution_sessions
        set state = 'running', active_segment_started_at = now_at,
            current_pomodoro_segment = 'focus', updated_by_device_id = p_device_id,
            last_command_id = p_command_id
        where id = runtime.active_session_id and user_id = owner_id;
        update public.user_runtime_state
        set state = 'running', active_segment_started_at = now_at,
            lease_device_id = p_device_id, updated_by_device_id = p_device_id,
            last_command_id = p_command_id
        where id = runtime.id returning * into runtime;
      end if;
      result_payload := jsonb_build_object('status', 'accepted');
    else -- complete
      update public.execution_sessions
      set state = 'completed', finished_at = now_at, active_segment_started_at = null,
          accumulated_active_ms = active_ms, updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.active_session_id and user_id = owner_id;
      update public.task_occurrences
      set status = 'completed', actual_finish = now_at, active_duration_ms = active_ms,
          progress = 1, updated_by_device_id = p_device_id, last_command_id = p_command_id
      where id = p_task_occurrence_id and user_id = owner_id;
      update public.user_runtime_state
      set active_session_id = null, active_task_occurrence_id = null,
          state = 'idle', active_segment_started_at = null,
          accumulated_active_ms = active_ms, lease_device_id = p_device_id,
          updated_by_device_id = p_device_id, last_command_id = p_command_id
      where id = runtime.id returning * into runtime;
      result_payload := jsonb_build_object('status', 'accepted');
    end if;
  end if;

  if result_payload ->> 'status' = 'accepted' then
    insert into public.session_events (
      id, user_id, session_id, event_type, occurred_at, duration_ms,
      source_device_id, event_payload, created_by_device_id,
      updated_by_device_id, last_command_id
    ) values (
      gen_random_uuid(), owner_id, p_session_id, p_action, now_at,
      case when p_action in ('pause', 'start_break', 'complete') then active_ms else null end,
      p_device_id, jsonb_build_object('task_occurrence_id', p_task_occurrence_id),
      p_device_id, p_device_id, p_command_id
    );
  end if;

  select * into runtime from public.user_runtime_state where user_id = owner_id;
  result_payload := result_payload || jsonb_build_object(
    'session_id', p_session_id,
    'runtime_revision', runtime.revision,
    'runtime_state', runtime.state
  );
  insert into public.processed_commands (
    user_id, command_id, device_id, device_sequence, entity_type, entity_id,
    command_type, base_revision, status, result, created_by_device_id,
    updated_by_device_id, last_command_id
  ) values (
    owner_id, p_command_id, p_device_id, p_device_sequence,
    'execution_runtime', p_session_id, p_action, runtime.revision,
    case when result_payload ->> 'status' = 'accepted'
      then 'accepted'::public.sync_command_status else 'conflict'::public.sync_command_status end,
    result_payload, p_device_id, p_device_id, p_command_id
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
