-- Resolve a task which has remained paused for at least twelve hours without
-- ever converting pause wall time into work. The command can either return
-- the task to a visible needs-attention/overdue state or skip this occurrence.
-- Recurrence templates and future occurrences are deliberately untouched.

create function taskmaster_internal.resolve_stale_paused_task_v0034_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_task_occurrence_id uuid,
  p_session_id uuid,
  p_decision text,
  p_expected_task_revision bigint,
  p_expected_runtime_revision bigint,
  p_resolved_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_command public.processed_commands%rowtype;
  task_record public.task_occurrences%rowtype;
  session_record public.execution_sessions%rowtype;
  runtime_record public.user_runtime_state%rowtype;
  result_payload jsonb;
  guard_reason text;
  owns_runtime boolean := false;
  stale_boundary timestamptz;
  session_active_ms bigint := 0;
  target_status public.task_status;
  now_at timestamptz := statement_timestamp();
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_command_id is null
      or p_device_id is null
      or p_device_sequence is null
      or p_task_occurrence_id is null
      or p_decision is null
      or p_expected_task_revision is null
      or p_resolved_at is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_device_sequence < 1
      or p_expected_task_revision < 1
      or p_decision not in ('needs_attention', 'skip')
      or p_resolved_at > now_at + interval '5 minutes' then
    raise exception 'invalid_command_payload' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':' || p_command_id::text,
      0
    )
  );

  select *
  into existing_command
  from public.processed_commands command_row
  where command_row.user_id = owner_id
    and command_row.command_id = p_command_id
  for update;

  if found then
    if existing_command.device_id is distinct from p_device_id
        or existing_command.device_sequence is distinct from p_device_sequence
        or existing_command.entity_type is distinct from
          'execution_runtime_stale_pause'
        or existing_command.entity_id is distinct from p_task_occurrence_id
        or existing_command.command_type is distinct from p_decision
        or existing_command.base_revision is distinct from
          p_expected_task_revision then
      raise exception 'command_identity_mismatch' using errcode = '22023';
    end if;
    return existing_command.result;
  end if;

  if not exists (
    select 1
    from public.account_devices device_row
    where device_row.user_id = owner_id
      and device_row.id = p_device_id
      and device_row.revoked_at is null
      and device_row.deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  -- Serialize with Start/Pause/Resume and lock all records before deciding.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(owner_id::text || ':execution-runtime', 0)
  );

  select *
  into runtime_record
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id
  for update;

  select *
  into task_record
  from public.task_occurrences task_row
  where task_row.user_id = owner_id
    and task_row.id = p_task_occurrence_id
  for update;

  if not found or task_record.deleted_at is not null then
    guard_reason := 'missing_task';
  elsif task_record.revision <> p_expected_task_revision then
    guard_reason := 'stale_task_revision';
  elsif task_record.status <> 'paused'::public.task_status then
    guard_reason := 'task_not_paused';
  end if;

  if runtime_record.user_id is not null then
    owns_runtime :=
      runtime_record.active_task_occurrence_id = p_task_occurrence_id;
  end if;
  if guard_reason is null and owns_runtime then
    if runtime_record.state <> 'paused'::public.session_state
        or runtime_record.active_session_id is null then
      guard_reason := 'runtime_not_paused';
    elsif p_session_id is not null
        and runtime_record.active_session_id <> p_session_id then
      guard_reason := 'runtime_session_changed';
    elsif p_expected_runtime_revision is null
        or runtime_record.revision <> p_expected_runtime_revision then
      guard_reason := 'stale_runtime_revision';
    end if;
  end if;

  if p_session_id is not null then
    select *
    into session_record
    from public.execution_sessions session_row
    where session_row.user_id = owner_id
      and session_row.id = p_session_id
      and session_row.task_occurrence_id = p_task_occurrence_id
    for update;
    if guard_reason is null and not found then
      guard_reason := 'missing_session';
    elsif guard_reason is null
        and session_record.deleted_at is null
        and session_record.state <> 'paused'::public.session_state
        and session_record.state <> 'cancelled'::public.session_state then
      guard_reason := 'session_not_paused';
    end if;
  elsif guard_reason is null and owns_runtime then
    guard_reason := 'missing_session_identity';
  end if;

  if session_record.user_id is not null
      and session_record.deleted_at is null then
    session_active_ms := greatest(
      0,
      session_record.accumulated_active_ms
    );
  end if;

  if guard_reason is null then
    stale_boundary := case
      when owns_runtime then runtime_record.updated_at
      else task_record.updated_at
    end;
    if stale_boundary > now_at - interval '12 hours' then
      guard_reason := 'pause_not_stale';
    end if;
  end if;

  if guard_reason is null then
    target_status := case
      when p_decision = 'skip' then 'skipped'::public.task_status
      when task_record.due_at is not null and task_record.due_at <= now_at
        then 'overdue'::public.task_status
      else 'waiting_review'::public.task_status
    end;

    if session_record.user_id is not null
        and session_record.deleted_at is null
        and session_record.state = 'paused'::public.session_state then
      update public.execution_sessions session_row
      set state = 'cancelled'::public.session_state,
          finished_at = coalesce(session_row.finished_at, p_resolved_at),
          active_segment_started_at = null,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id,
          data = coalesce(session_row.data, '{}'::jsonb) ||
            pg_catalog.jsonb_build_object(
              'stale_pause_resolution', p_decision,
              'stale_pause_resolved_at', p_resolved_at
            )
      where session_row.user_id = owner_id
        and session_row.id = session_record.id
        and session_row.revision = session_record.revision
      returning * into session_record;
    end if;

    update public.task_occurrences task_row
    set status = target_status,
        actual_finish = case
          when p_decision = 'skip' then p_resolved_at
          else task_row.actual_finish
        end,
        active_duration_ms = greatest(
          task_row.active_duration_ms,
          case
            when owns_runtime then runtime_record.accumulated_active_ms
            else task_row.active_duration_ms
          end,
          session_active_ms
        ),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        data = (
          coalesce(task_row.data, '{}'::jsonb) ||
          case
            when p_decision = 'skip'
              then pg_catalog.jsonb_build_object('occurrence_state', 'skipped')
            else '{}'::jsonb
          end
        ) || pg_catalog.jsonb_build_object(
          'stale_pause_resolution', pg_catalog.jsonb_build_object(
            'decision', p_decision,
            'resolved_at', p_resolved_at,
            'paused_since', stale_boundary
          )
        )
    where task_row.user_id = owner_id
      and task_row.id = p_task_occurrence_id
      and task_row.revision = p_expected_task_revision
    returning * into task_record;

    if not found then
      raise exception 'stale_task_revision';
    end if;

    if owns_runtime then
      update public.user_runtime_state runtime_row
      set active_session_id = null,
          active_task_occurrence_id = null,
          state = 'idle'::public.session_state,
          active_segment_started_at = null,
          lease_device_id = null,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id,
          data = coalesce(runtime_row.data, '{}'::jsonb) ||
            pg_catalog.jsonb_build_object(
              'stale_pause_resolution', p_decision,
              'stale_pause_resolved_at', p_resolved_at
            )
      where runtime_row.user_id = owner_id
        and runtime_row.revision = p_expected_runtime_revision
        and runtime_row.active_task_occurrence_id = p_task_occurrence_id
        and runtime_row.state = 'paused'::public.session_state
      returning * into runtime_record;
      if not found then
        raise exception 'stale_runtime_revision';
      end if;
    end if;

    if session_record.user_id is not null then
      insert into public.session_events (
        id,
        user_id,
        session_id,
        event_type,
        occurred_at,
        duration_ms,
        source_device_id,
        event_payload,
        created_by_device_id,
        updated_by_device_id,
        last_command_id
      ) values (
        gen_random_uuid(),
        owner_id,
        session_record.id,
        case
          when p_decision = 'skip' then 'stale_pause_skipped'
          else 'stale_pause_needs_attention'
        end,
        p_resolved_at,
        session_record.accumulated_active_ms,
        p_device_id,
        pg_catalog.jsonb_build_object(
          'task_occurrence_id', p_task_occurrence_id,
          'paused_since', stale_boundary,
          'decision', p_decision
        ),
        p_device_id,
        p_device_id,
        p_command_id
      );
    end if;

    result_payload := pg_catalog.jsonb_build_object(
      'status', 'accepted',
      'command_id', p_command_id,
      'resolved', true,
      'decision', p_decision,
      'canonical_task', to_jsonb(task_record),
      'canonical_session', case
        when session_record.user_id is null then null
        else to_jsonb(session_record)
      end,
      'canonical_runtime', case
        when runtime_record.user_id is null then null
        else to_jsonb(runtime_record)
      end
    );
  else
    result_payload := pg_catalog.jsonb_build_object(
      'status', 'accepted',
      'command_id', p_command_id,
      'resolved', false,
      'canonical_only', true,
      'superseded', true,
      'reason', guard_reason,
      'decision', p_decision,
      'canonical_task', case
        when task_record.user_id is null then null
        else to_jsonb(task_record)
      end,
      'canonical_session', case
        when session_record.user_id is null then null
        else to_jsonb(session_record)
      end,
      'canonical_runtime', case
        when runtime_record.user_id is null then null
        else to_jsonb(runtime_record)
      end
    );
  end if;

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
    'execution_runtime_stale_pause',
    p_task_occurrence_id,
    p_decision,
    p_expected_task_revision,
    'accepted'::public.sync_command_status,
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

create function public.resolve_stale_paused_task_v0034_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_task_occurrence_id uuid,
  p_session_id uuid,
  p_decision text,
  p_expected_task_revision bigint,
  p_expected_runtime_revision bigint,
  p_resolved_at timestamptz
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.resolve_stale_paused_task_v0034_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_task_occurrence_id,
    p_session_id,
    p_decision,
    p_expected_task_revision,
    p_expected_runtime_revision,
    p_resolved_at
  )
$$;

revoke all on function
  taskmaster_internal.resolve_stale_paused_task_v0034_command(
    uuid, uuid, bigint, uuid, uuid, text, bigint, bigint, timestamptz
  )
from public, anon;

grant execute on function
  taskmaster_internal.resolve_stale_paused_task_v0034_command(
    uuid, uuid, bigint, uuid, uuid, text, bigint, bigint, timestamptz
  )
to authenticated, service_role;

revoke all on function public.resolve_stale_paused_task_v0034_command(
  uuid, uuid, bigint, uuid, uuid, text, bigint, bigint, timestamptz
)
from public, anon;

grant execute on function public.resolve_stale_paused_task_v0034_command(
  uuid, uuid, bigint, uuid, uuid, text, bigint, bigint, timestamptz
)
to authenticated;

comment on function public.resolve_stale_paused_task_v0034_command(
  uuid, uuid, bigint, uuid, uuid, text, bigint, bigint, timestamptz
) is
  'Revision-guarded decision for a task paused at least twelve hours; pause wall time remains inert.';

do $$
declare
  internal_oid regprocedure := pg_catalog.to_regprocedure(
    'taskmaster_internal.resolve_stale_paused_task_v0034_command(uuid,uuid,bigint,uuid,uuid,text,bigint,bigint,timestamptz)'
  );
  wrapper_oid regprocedure := pg_catalog.to_regprocedure(
    'public.resolve_stale_paused_task_v0034_command(uuid,uuid,bigint,uuid,uuid,text,bigint,bigint,timestamptz)'
  );
begin
  if internal_oid is null or wrapper_oid is null then
    raise exception 'missing_stale_pause_resolution_surface';
  end if;
  if not (
    select procedure_row.prosecdef
    from pg_catalog.pg_proc procedure_row
    where procedure_row.oid = internal_oid
  ) or (
    select procedure_row.prosecdef
    from pg_catalog.pg_proc procedure_row
    where procedure_row.oid = wrapper_oid
  ) then
    raise exception 'invalid_stale_pause_resolution_security_modes';
  end if;
  if pg_catalog.has_function_privilege('anon', internal_oid, 'EXECUTE')
      or pg_catalog.has_function_privilege('anon', wrapper_oid, 'EXECUTE') then
    raise exception 'stale_pause_resolution_public_grant';
  end if;
end;
$$;
