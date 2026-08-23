-- Extending a completed break is one account-wide execution command. A break
-- can remain open long after its original deadline, so the server first
-- catches the interval up to statement time and then adds five visible
-- minutes. Simultaneous devices serialize on the canonical runtime and merge
-- without creating generic task-occurrence revision conflicts.

create function taskmaster_internal.extend_active_break_v0036_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_session_id uuid,
  p_task_occurrence_id uuid,
  p_expected_task_revision bigint,
  p_break_started_at timestamptz,
  p_boundary_at timestamptz,
  p_extension_ms bigint,
  p_requested_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_command public.processed_commands%rowtype;
  runtime_record public.user_runtime_state%rowtype;
  task_record public.task_occurrences%rowtype;
  result_payload jsonb;
  guard_reason text;
  now_at timestamptz := statement_timestamp();
  short_break_ms bigint;
  long_break_ms bigint;
  break_duration_ms bigint;
  long_break_after bigint;
  completed_focuses bigint;
  current_extension_ms bigint;
  elapsed_ms bigint;
  current_interval_ms bigint;
  overdue_ms bigint;
  next_extension_ms bigint;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_command_id is null
      or p_device_id is null
      or p_device_sequence is null
      or p_session_id is null
      or p_task_occurrence_id is null
      or p_expected_task_revision is null
      or p_break_started_at is null
      or p_boundary_at is null
      or p_extension_ms is null
      or p_requested_at is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_device_sequence < 1
      or p_expected_task_revision < 1
      or p_extension_ms <> 300000
      or p_break_started_at > now_at + interval '5 minutes'
      or p_boundary_at < p_break_started_at
      or p_requested_at > now_at + interval '5 minutes' then
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
          'execution_break_extension'
        or existing_command.entity_id is distinct from p_session_id
        or existing_command.command_type is distinct from 'extend_break'
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

  -- Serialize with Start/Pause/Finish and with extensions from other devices.
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

  if runtime_record.user_id is null then
    guard_reason := 'missing_runtime';
  elsif runtime_record.deleted_at is not null
      or runtime_record.state <> 'break'::public.session_state then
    guard_reason := 'runtime_not_on_break';
  elsif runtime_record.active_session_id <> p_session_id
      or runtime_record.active_task_occurrence_id <> p_task_occurrence_id then
    guard_reason := 'break_interval_changed';
  elsif runtime_record.active_segment_started_at is null
      or pg_catalog.abs(
        extract(
          epoch from runtime_record.active_segment_started_at -
            p_break_started_at
        ) * 1000
      ) > 2000 then
    guard_reason := 'break_interval_changed';
  elsif task_record.user_id is null or task_record.deleted_at is not null then
    guard_reason := 'missing_task';
  elsif task_record.execution_mode <> 'pomodoro'::public.execution_mode then
    guard_reason := 'task_not_pomodoro';
  end if;

  if guard_reason is null then
    short_break_ms := coalesce(
      case
        when (task_record.data ->> 'short_break_ms') ~ '^[0-9]{1,8}$'
          then (task_record.data ->> 'short_break_ms')::bigint
      end,
      case
        when (task_record.data ->> 'pomodoro_short_break_minutes') ~
            '^[0-9]{1,4}$'
          then
            (task_record.data ->> 'pomodoro_short_break_minutes')::bigint *
              60000
      end,
      300000
    );
    long_break_ms := coalesce(
      case
        when (task_record.data ->> 'long_break_ms') ~ '^[0-9]{1,8}$'
          then (task_record.data ->> 'long_break_ms')::bigint
      end,
      case
        when (task_record.data ->> 'pomodoro_long_break_minutes') ~
            '^[0-9]{1,4}$'
          then
            (task_record.data ->> 'pomodoro_long_break_minutes')::bigint *
              60000
      end,
      900000
    );
    short_break_ms := greatest(
      60000::bigint,
      least(86400000::bigint, short_break_ms)
    );
    long_break_ms := greatest(
      60000::bigint,
      least(86400000::bigint, long_break_ms)
    );
    long_break_after := coalesce(
      case
        when (task_record.data ->> 'long_break_after') ~ '^[0-9]{1,2}$'
          then (task_record.data ->> 'long_break_after')::bigint
      end,
      case
        when (task_record.data ->> 'pomodoro_long_break_after') ~
            '^[0-9]{1,2}$'
          then
            (task_record.data ->> 'pomodoro_long_break_after')::bigint
      end,
      4
    );
    long_break_after := greatest(2::bigint, least(12::bigint, long_break_after));
    completed_focuses := coalesce(
      case
        when (runtime_record.data ->> 'pomodoro_completed_focuses') ~
            '^[0-9]{1,12}$'
          then
            (runtime_record.data ->> 'pomodoro_completed_focuses')::bigint
      end,
      0
    );
    completed_focuses := greatest(0::bigint, completed_focuses);
    break_duration_ms := case
      when completed_focuses > 0
          and completed_focuses % long_break_after = 0 then long_break_ms
      else short_break_ms
    end;
    current_extension_ms := coalesce(
      case
        when (task_record.data ->> 'active_break_extension_ms') ~
            '^[0-9]{1,15}$'
          then
            (task_record.data ->> 'active_break_extension_ms')::bigint
      end,
      0
    );
    current_extension_ms := greatest(0::bigint, current_extension_ms);
    elapsed_ms := greatest(
      0::bigint,
      (
        extract(
          epoch from now_at - runtime_record.active_segment_started_at
        ) * 1000
      )::bigint
    );
    current_interval_ms := break_duration_ms + current_extension_ms;
    overdue_ms := greatest(0::bigint, elapsed_ms - current_interval_ms);
    next_extension_ms := current_extension_ms + overdue_ms + p_extension_ms;

    update public.task_occurrences task_row
    set data = pg_catalog.jsonb_set(
          coalesce(task_row.data, '{}'::jsonb),
          '{active_break_extension_ms}',
          pg_catalog.to_jsonb(next_extension_ms),
          true
        ),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where task_row.user_id = owner_id
      and task_row.id = p_task_occurrence_id
      and task_row.revision = task_record.revision
      and task_row.deleted_at is null
    returning * into task_record;

    if not found then
      raise exception 'break_task_revision_changed';
    end if;

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
      pg_catalog.gen_random_uuid(),
      owner_id,
      p_session_id,
      'extend_break',
      now_at,
      p_extension_ms,
      p_device_id,
      pg_catalog.jsonb_build_object(
        'task_occurrence_id', p_task_occurrence_id,
        'break_started_at', p_break_started_at,
        'previous_boundary_at', p_boundary_at,
        'requested_at', p_requested_at,
        'overdue_rebased_ms', overdue_ms,
        'active_break_extension_ms', next_extension_ms
      ),
      p_device_id,
      p_device_id,
      p_command_id
    );

    result_payload := pg_catalog.jsonb_build_object(
      'status', 'accepted',
      'command_id', p_command_id,
      'extended', true,
      'overdue_rebased_ms', overdue_ms,
      'active_break_extension_ms', next_extension_ms,
      'canonical_task', pg_catalog.to_jsonb(task_record),
      'canonical_runtime', pg_catalog.to_jsonb(runtime_record)
    );
  else
    result_payload := pg_catalog.jsonb_build_object(
      'status', 'accepted',
      'command_id', p_command_id,
      'extended', false,
      'canonical_only', true,
      'superseded', true,
      'reason', guard_reason,
      'canonical_task', case
        when task_record.user_id is null then null
        else pg_catalog.to_jsonb(task_record)
      end,
      'canonical_runtime', case
        when runtime_record.user_id is null then null
        else pg_catalog.to_jsonb(runtime_record)
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
    'execution_break_extension',
    p_session_id,
    'extend_break',
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

create function public.extend_active_break_v0036_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_session_id uuid,
  p_task_occurrence_id uuid,
  p_expected_task_revision bigint,
  p_break_started_at timestamptz,
  p_boundary_at timestamptz,
  p_extension_ms bigint,
  p_requested_at timestamptz
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.extend_active_break_v0036_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_session_id,
    p_task_occurrence_id,
    p_expected_task_revision,
    p_break_started_at,
    p_boundary_at,
    p_extension_ms,
    p_requested_at
  )
$$;

revoke all on function
  taskmaster_internal.extend_active_break_v0036_command(
    uuid, uuid, bigint, uuid, uuid, bigint, timestamptz, timestamptz,
    bigint, timestamptz
  )
from public, anon;

grant execute on function
  taskmaster_internal.extend_active_break_v0036_command(
    uuid, uuid, bigint, uuid, uuid, bigint, timestamptz, timestamptz,
    bigint, timestamptz
  )
to authenticated, service_role;

revoke all on function public.extend_active_break_v0036_command(
  uuid, uuid, bigint, uuid, uuid, bigint, timestamptz, timestamptz,
  bigint, timestamptz
)
from public, anon;

grant execute on function public.extend_active_break_v0036_command(
  uuid, uuid, bigint, uuid, uuid, bigint, timestamptz, timestamptz,
  bigint, timestamptz
)
to authenticated;

comment on function public.extend_active_break_v0036_command(
  uuid, uuid, bigint, uuid, uuid, bigint, timestamptz, timestamptz,
  bigint, timestamptz
) is
  'Idempotently rebases an active overdue break and adds five visible minutes.';

do $$
declare
  internal_oid regprocedure := pg_catalog.to_regprocedure(
    'taskmaster_internal.extend_active_break_v0036_command(uuid,uuid,bigint,uuid,uuid,bigint,timestamptz,timestamptz,bigint,timestamptz)'
  );
  wrapper_oid regprocedure := pg_catalog.to_regprocedure(
    'public.extend_active_break_v0036_command(uuid,uuid,bigint,uuid,uuid,bigint,timestamptz,timestamptz,bigint,timestamptz)'
  );
begin
  if internal_oid is null or wrapper_oid is null then
    raise exception 'missing_break_extension_surface';
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
    raise exception 'invalid_break_extension_security_modes';
  end if;
  if pg_catalog.has_function_privilege('anon', internal_oid, 'EXECUTE')
      or pg_catalog.has_function_privilege('anon', wrapper_oid, 'EXECUTE') then
    raise exception 'break_extension_public_grant';
  end if;
end;
$$;
