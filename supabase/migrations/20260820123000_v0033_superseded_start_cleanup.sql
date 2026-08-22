-- Retire provisional execution sessions only when an atomic runtime Start was
-- superseded and the account-wide canonical runtime never accepted them.
-- The runtime row is the sole authority; generic entity updates cannot provide
-- this cross-row exclusion and must not be used for this repair.

-- Repair already-stranded provisional sessions only when the immutable
-- command ledger positively proves that this exact Start was accepted as a
-- canonical-only superseded no-op. Merely seeing a zero-work session is not
-- sufficient: its runtime command may still be delayed in another client.
-- The per-owner execution lock is the same lock used by runtime transitions,
-- so a session cannot become canonical between this proof and the update.
do $$
declare
  owner_record record;
begin
  for owner_record in
    select distinct session_row.user_id
    from public.execution_sessions session_row
    where session_row.deleted_at is null
      and session_row.state = 'running'::public.session_state
      and session_row.accumulated_active_ms = 0
      and session_row.accumulated_paused_ms = 0
      and session_row.accumulated_idle_ms = 0
      and session_row.updated_at
        < statement_timestamp() - interval '10 minutes'
      and not exists (
        select 1
        from public.session_events event_row
        where event_row.user_id = session_row.user_id
          and event_row.session_id = session_row.id
      )
      and exists (
        select 1
        from public.processed_commands create_command
        where create_command.user_id = session_row.user_id
          and create_command.command_id = session_row.last_command_id
          and create_command.entity_type = 'execution_sessions'
          and create_command.entity_id = session_row.id
          and create_command.command_type = 'create'
          and create_command.status = 'accepted'::public.sync_command_status
          and create_command.device_id = session_row.created_by_device_id
          and exists (
            select 1
            from public.processed_commands runtime_command
            where runtime_command.user_id = session_row.user_id
              and runtime_command.device_id = create_command.device_id
              and runtime_command.device_sequence
                > create_command.device_sequence
              and runtime_command.entity_type = 'execution_runtime'
              and runtime_command.entity_id = session_row.id
              and runtime_command.command_type = 'start'
              and runtime_command.status =
                'accepted'::public.sync_command_status
              and runtime_command.result ->> 'canonical_only' = 'true'
              and runtime_command.result ->> 'superseded' = 'true'
          )
      )
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        owner_record.user_id::text || ':execution-runtime',
        0
      )
    );

    update public.execution_sessions session_row
    set state = 'cancelled'::public.session_state,
        finished_at = coalesce(
          session_row.finished_at,
          session_row.started_at,
          session_row.updated_at
        ),
        active_segment_started_at = null,
        deleted_at = statement_timestamp(),
        data = coalesce(session_row.data, '{}'::jsonb) ||
          pg_catalog.jsonb_build_object(
            'retired_reason', 'noncanonical_zero_work_session_v0033',
            'retired_at', statement_timestamp()
          )
    where session_row.user_id = owner_record.user_id
      and session_row.deleted_at is null
      and session_row.state = 'running'::public.session_state
      and session_row.accumulated_active_ms = 0
      and session_row.accumulated_paused_ms = 0
      and session_row.accumulated_idle_ms = 0
      and session_row.updated_at
        < statement_timestamp() - interval '10 minutes'
      and not exists (
        select 1
        from public.session_events event_row
        where event_row.user_id = session_row.user_id
          and event_row.session_id = session_row.id
      )
      and not exists (
        select 1
        from public.user_runtime_state runtime_row
        where runtime_row.user_id = session_row.user_id
          and runtime_row.active_session_id = session_row.id
      )
      and exists (
        select 1
        from public.processed_commands create_command
        where create_command.user_id = session_row.user_id
          and create_command.command_id = session_row.last_command_id
          and create_command.entity_type = 'execution_sessions'
          and create_command.entity_id = session_row.id
          and create_command.command_type = 'create'
          and create_command.status = 'accepted'::public.sync_command_status
          and create_command.device_id = session_row.created_by_device_id
          and exists (
            select 1
            from public.processed_commands runtime_command
            where runtime_command.user_id = session_row.user_id
              and runtime_command.device_id = create_command.device_id
              and runtime_command.device_sequence
                > create_command.device_sequence
              and runtime_command.entity_type = 'execution_runtime'
              and runtime_command.entity_id = session_row.id
              and runtime_command.command_type = 'start'
              and runtime_command.status =
                'accepted'::public.sync_command_status
              and runtime_command.result ->> 'canonical_only' = 'true'
              and runtime_command.result ->> 'superseded' = 'true'
          )
      );
  end loop;
end;
$$;

create function taskmaster_internal.retire_superseded_execution_start_v0033_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_runtime_command_id uuid,
  p_session_create_command_id uuid,
  p_session_id uuid,
  p_task_occurrence_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_command public.processed_commands%rowtype;
  result_payload jsonb;
  guard_reason text;
  runtime_record public.user_runtime_state%rowtype;
  task_record public.task_occurrences%rowtype;
  session_record public.execution_sessions%rowtype;
  runtime_command public.processed_commands%rowtype;
  create_command public.processed_commands%rowtype;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_command_id is null
      or p_device_id is null
      or p_device_sequence is null
      or p_runtime_command_id is null
      or p_session_create_command_id is null
      or p_session_id is null
      or p_task_occurrence_id is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_device_sequence < 1 then
    raise exception 'invalid_device_sequence' using errcode = '22023';
  end if;

  -- Serialize identical command IDs before replay lookup. This preserves the
  -- first committed response and prevents a concurrent duplicate invocation
  -- from reaching the cleanup mutation or the unique command ledger insert.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      owner_id::text || ':' || p_command_id::text,
      0
    )
  );

  -- Idempotency precedes mutable device authorization. A response lost after
  -- commit remains readable without re-running any cleanup mutation, but a
  -- reused command ID must still match every immutable request identity.
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
          'execution_runtime_start_cleanup'
        or existing_command.entity_id is distinct from p_session_id
        or existing_command.command_type is distinct from 'retire'
        or existing_command.result ->> 'runtime_command_id'
          is distinct from p_runtime_command_id::text
        or existing_command.result ->> 'session_create_command_id'
          is distinct from p_session_create_command_id::text
        or existing_command.result ->> 'task_occurrence_id'
          is distinct from p_task_occurrence_id::text then
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

  -- Every runtime transition uses this same account lock. The active-session
  -- exclusion therefore remains true through the guarded session update.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(owner_id::text || ':execution-runtime', 0)
  );

  select *
  into runtime_record
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id
  for update;

  if not found then
    guard_reason := 'missing_canonical_runtime';
  end if;

  select *
  into runtime_command
  from public.processed_commands command_row
  where command_row.user_id = owner_id
    and command_row.command_id = p_runtime_command_id;

  if guard_reason is null and (
    not found
    or runtime_command.device_id is distinct from p_device_id
    or runtime_command.entity_type <> 'execution_runtime'
    or runtime_command.entity_id is distinct from p_session_id
    or runtime_command.command_type <> 'start'
    or runtime_command.status <> 'accepted'::public.sync_command_status
    or coalesce(
      (runtime_command.result ->> 'canonical_only')::boolean,
      false
    ) = false
    or coalesce(
      (runtime_command.result ->> 'superseded')::boolean,
      false
    ) = false
  ) then
    guard_reason := 'runtime_command_not_superseded_start';
  end if;

  select *
  into create_command
  from public.processed_commands command_row
  where command_row.user_id = owner_id
    and command_row.command_id = p_session_create_command_id;

  if guard_reason is null and (
    not found
    or create_command.device_id is distinct from p_device_id
    or create_command.entity_type <> 'execution_sessions'
    or create_command.entity_id is distinct from p_session_id
    or create_command.command_type <> 'create'
    or create_command.status <> 'accepted'::public.sync_command_status
  ) then
    guard_reason := 'session_create_identity_mismatch';
  end if;

  select *
  into task_record
  from public.task_occurrences task_row
  where task_row.user_id = owner_id
    and task_row.id = p_task_occurrence_id
  for update;

  if guard_reason is null and not found then
    guard_reason := 'missing_task';
  end if;

  select *
  into session_record
  from public.execution_sessions session_row
  where session_row.user_id = owner_id
    and session_row.id = p_session_id
    and session_row.task_occurrence_id = p_task_occurrence_id
  for update;

  if guard_reason is null and not found then
    guard_reason := 'missing_session';
  end if;

  if guard_reason is null
      and runtime_record.active_session_id = p_session_id then
    guard_reason := 'session_is_canonical';
  end if;

  -- A migration-time repair may already have retired this exact provisional
  -- row while retaining its original create identity. Return it as canonical
  -- cleanup evidence without mutating it again.
  if guard_reason is null
      and session_record.deleted_at is not null
      and session_record.state = 'cancelled'::public.session_state
      and session_record.last_command_id = p_session_create_command_id
      and session_record.data ->> 'retired_reason'
        = 'noncanonical_zero_work_session_v0033' then
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'retired', true,
      'already_retired', true,
      'canonical_runtime', to_jsonb(runtime_record),
      'canonical_task', to_jsonb(task_record),
      'retired_session', to_jsonb(session_record)
    );
  elsif guard_reason is null and (
    session_record.deleted_at is not null
    or session_record.state <> 'running'::public.session_state
    or session_record.revision <> 1
    or session_record.created_by_device_id is distinct from p_device_id
    or session_record.last_command_id is distinct from
      p_session_create_command_id
    or session_record.accumulated_active_ms <> 0
    or session_record.accumulated_paused_ms <> 0
    or session_record.accumulated_idle_ms <> 0
    or exists (
      select 1
      from public.session_events event_row
      where event_row.user_id = owner_id
        and event_row.session_id = p_session_id
    )
  ) then
    guard_reason := 'session_not_provisional';
  end if;

  if result_payload is null and guard_reason is null then
    update public.execution_sessions session_row
    set state = 'cancelled'::public.session_state,
        finished_at = coalesce(
          session_row.finished_at,
          session_row.started_at,
          session_row.updated_at
        ),
        active_segment_started_at = null,
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        deleted_at = statement_timestamp(),
        data = coalesce(session_row.data, '{}'::jsonb) || jsonb_build_object(
          'retired_reason', 'superseded_start_v0033',
          'runtime_command_id', p_runtime_command_id,
          'session_create_command_id', p_session_create_command_id,
          'retired_at', statement_timestamp()
        )
    where session_row.user_id = owner_id
      and session_row.id = p_session_id
      and session_row.task_occurrence_id = p_task_occurrence_id
      and session_row.revision = session_record.revision
      and session_row.last_command_id = p_session_create_command_id
      and not exists (
        select 1
        from public.user_runtime_state current_runtime
        where current_runtime.user_id = owner_id
          and current_runtime.active_session_id = p_session_id
      )
    returning * into session_record;

    if found then
      result_payload := jsonb_build_object(
        'status', 'accepted',
        'retired', true,
        'canonical_runtime', to_jsonb(runtime_record),
        'canonical_task', to_jsonb(task_record),
        'retired_session', to_jsonb(session_record)
      );
    else
      guard_reason := 'session_changed_during_cleanup';
    end if;
  end if;

  if result_payload is null then
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'retired', false,
      'canonical_only', true,
      'reason', coalesce(guard_reason, 'cleanup_not_required'),
      'canonical_runtime', case
        when runtime_record.user_id is null then null
        else to_jsonb(runtime_record)
      end
    );
  end if;

  -- Persist the immutable parameter identity in every response, including a
  -- guarded no-op, so a replay can be validated before mutable device auth.
  result_payload := result_payload || pg_catalog.jsonb_build_object(
    'runtime_command_id', p_runtime_command_id,
    'session_create_command_id', p_session_create_command_id,
    'task_occurrence_id', p_task_occurrence_id
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
    'execution_runtime_start_cleanup',
    p_session_id,
    'retire',
    coalesce(session_record.revision, 0),
    'accepted'::public.sync_command_status,
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

create function public.retire_superseded_execution_start_v0033_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_runtime_command_id uuid,
  p_session_create_command_id uuid,
  p_session_id uuid,
  p_task_occurrence_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.retire_superseded_execution_start_v0033_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_runtime_command_id,
    p_session_create_command_id,
    p_session_id,
    p_task_occurrence_id
  )
$$;

revoke all on function
  taskmaster_internal.retire_superseded_execution_start_v0033_command(
    uuid, uuid, bigint, uuid, uuid, uuid, uuid
  )
from public, anon;

grant execute on function
  taskmaster_internal.retire_superseded_execution_start_v0033_command(
    uuid, uuid, bigint, uuid, uuid, uuid, uuid
  )
to authenticated, service_role;

revoke all on function
  public.retire_superseded_execution_start_v0033_command(
    uuid, uuid, bigint, uuid, uuid, uuid, uuid
  )
from public, anon;

grant execute on function
  public.retire_superseded_execution_start_v0033_command(
    uuid, uuid, bigint, uuid, uuid, uuid, uuid
  )
to authenticated;

comment on function
  public.retire_superseded_execution_start_v0033_command(
    uuid, uuid, bigint, uuid, uuid, uuid, uuid
  ) is
  'Idempotently retires only a zero-work provisional Start session which never became the owner canonical runtime.';

-- Fail closed if the callable surface is accidentally widened or the public
-- invoker can no longer reach the hardened internal definer.
do $$
declare
  internal_oid regprocedure := pg_catalog.to_regprocedure(
    'taskmaster_internal.retire_superseded_execution_start_v0033_command(uuid,uuid,bigint,uuid,uuid,uuid,uuid)'
  );
  wrapper_oid regprocedure := pg_catalog.to_regprocedure(
    'public.retire_superseded_execution_start_v0033_command(uuid,uuid,bigint,uuid,uuid,uuid,uuid)'
  );
  internal_is_definer boolean;
  wrapper_is_definer boolean;
begin
  if internal_oid is null or wrapper_oid is null then
    raise exception 'missing_superseded_start_cleanup_surface';
  end if;
  select procedure_row.prosecdef
  into internal_is_definer
  from pg_catalog.pg_proc procedure_row
  where procedure_row.oid = internal_oid;
  select procedure_row.prosecdef
  into wrapper_is_definer
  from pg_catalog.pg_proc procedure_row
  where procedure_row.oid = wrapper_oid;
  if not internal_is_definer or wrapper_is_definer then
    raise exception 'invalid_superseded_start_cleanup_security_modes';
  end if;
  if not pg_catalog.has_function_privilege(
    'authenticated', internal_oid, 'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'authenticated', wrapper_oid, 'EXECUTE'
  ) then
    raise exception 'missing_superseded_start_cleanup_authenticated_grant';
  end if;
  if pg_catalog.has_function_privilege('anon', internal_oid, 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', wrapper_oid, 'EXECUTE') then
    raise exception 'superseded_start_cleanup_public_grant';
  end if;
end;
$$;
