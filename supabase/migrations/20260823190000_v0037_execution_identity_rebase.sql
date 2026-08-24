-- A runtime revision protects against acting on a different timer, but a
-- revision can also advance while the exact same task/session remains active.
-- In that case silently superseding Pause, Resume or an explicit hand-off
-- makes the initiating device visibly undo a valid user action.
--
-- The v0032 wrappers below opt one command into a revision rebase only after
-- proving the canonical task/session identity and a compatible phase under the
-- account advisory lock. The existing v0028 guard remains fail-closed for
-- every other caller and every genuinely different canonical runtime.

create or replace function taskmaster_internal.guard_execution_runtime_v0028_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_entity_type text,
  p_entity_id uuid,
  p_command_type text,
  p_expected_runtime_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  runtime public.user_runtime_state%rowtype;
  existing_result jsonb;
  result_payload jsonb;
  identity_rebase_command text := nullif(
    pg_catalog.current_setting('taskmaster.identity_rebase_command', true),
    ''
  );
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_command_id is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
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
    select *
    into runtime
    from public.user_runtime_state runtime_row
    where runtime_row.user_id = owner_id;

    if found then
      return existing_result || jsonb_build_object(
        'canonical_runtime', to_jsonb(runtime),
        'runtime_revision', runtime.revision,
        'runtime_state', runtime.state
      );
    end if;
    return existing_result;
  end if;

  if p_expected_runtime_revision is null
      or p_expected_runtime_revision < 0 then
    raise exception 'invalid_expected_runtime_revision';
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

  select *
  into runtime
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id
  for update;

  if not found then
    insert into public.user_runtime_state (id, user_id)
    values (gen_random_uuid(), owner_id)
    returning * into runtime;
  end if;

  if runtime.revision <> p_expected_runtime_revision
      and identity_rebase_command is distinct from p_command_id::text then
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'canonical_only', true,
      'superseded', true,
      'reason', 'stale_runtime_revision',
      'command_id', p_command_id,
      'expected_runtime_revision', p_expected_runtime_revision,
      'runtime_revision', runtime.revision,
      'runtime_state', runtime.state,
      'canonical_runtime', to_jsonb(runtime)
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
      p_entity_type,
      p_entity_id,
      p_command_type,
      p_expected_runtime_revision,
      'accepted'::public.sync_command_status,
      result_payload,
      p_device_id,
      p_device_id,
      p_command_id
    );

    return result_payload;
  end if;

  return null;
end;
$$;

create or replace function taskmaster_internal.apply_execution_transition_v0032_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_session_id uuid,
  p_task_occurrence_id uuid,
  p_action text,
  p_mode public.execution_mode,
  p_projected_active_ms bigint,
  p_boundary_at timestamptz,
  p_expected_runtime_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  runtime public.user_runtime_state%rowtype;
  result_payload jsonb;
  identity_matches boolean := false;
  phase_is_compatible boolean := false;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_projected_active_ms is null or p_projected_active_ms < 0
      or p_boundary_at is null
      or p_boundary_at > statement_timestamp() + interval '5 minutes' then
    raise exception 'invalid_projected_active_ms';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':execution-runtime', 0)
  );
  select *
  into runtime
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id
  for update;

  if found and runtime.revision <> p_expected_runtime_revision then
    identity_matches :=
      runtime.active_session_id is not distinct from p_session_id
      and runtime.active_task_occurrence_id is not distinct from
        p_task_occurrence_id;
    phase_is_compatible := case p_action
      when 'start' then
        runtime.state = 'idle'
        or (identity_matches and runtime.state in ('running', 'paused', 'break'))
      when 'pause' then identity_matches and runtime.state in ('running', 'paused')
      when 'resume' then identity_matches and runtime.state in ('paused', 'running')
      when 'start_break' then
        identity_matches and runtime.state in ('running', 'break')
      when 'skip_break' then identity_matches and runtime.state = 'running'
      when 'finish_break' then
        identity_matches and runtime.state in ('break', 'running')
      when 'complete' then
        identity_matches and runtime.state in ('running', 'paused', 'break')
      else false
    end;
    if phase_is_compatible then
      perform pg_catalog.set_config(
        'taskmaster.identity_rebase_command',
        p_command_id::text,
        true
      );
    end if;
  end if;

  perform pg_catalog.set_config(
    'taskmaster.projected_active_ms',
    p_projected_active_ms::text,
    true
  );
  perform pg_catalog.set_config(
    'taskmaster.boundary_at',
    p_boundary_at::text,
    true
  );
  result_payload :=
    taskmaster_internal.apply_execution_transition_v0028_break_safe_command(
      p_command_id,
      p_device_id,
      p_device_sequence,
      p_session_id,
      p_task_occurrence_id,
      p_action,
      p_mode,
      p_expected_runtime_revision
    );
  perform pg_catalog.set_config('taskmaster.identity_rebase_command', '', true);
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  return result_payload;
exception when others then
  perform pg_catalog.set_config('taskmaster.identity_rebase_command', '', true);
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  raise;
end;
$$;

create or replace function taskmaster_internal.apply_execution_switch_v0032_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_new_session_id uuid,
  p_new_task_occurrence_id uuid,
  p_expected_active_session_id uuid,
  p_expected_active_task_id uuid,
  p_current_task_action text,
  p_mode public.execution_mode,
  p_projected_active_ms bigint,
  p_boundary_at timestamptz,
  p_expected_runtime_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  runtime public.user_runtime_state%rowtype;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_projected_active_ms is null or p_projected_active_ms < 0
      or p_boundary_at is null
      or p_boundary_at > statement_timestamp() + interval '5 minutes' then
    raise exception 'invalid_projected_active_ms';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':execution-runtime', 0)
  );
  select *
  into runtime
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id
  for update;

  if found
      and runtime.revision <> p_expected_runtime_revision
      and runtime.active_session_id is not distinct from
        p_expected_active_session_id
      and runtime.active_task_occurrence_id is not distinct from
        p_expected_active_task_id
      and runtime.state in ('running', 'paused', 'break')
      and p_current_task_action in ('pause', 'finish') then
    perform pg_catalog.set_config(
      'taskmaster.identity_rebase_command',
      p_command_id::text,
      true
    );
  end if;

  perform pg_catalog.set_config(
    'taskmaster.projected_active_ms',
    p_projected_active_ms::text,
    true
  );
  perform pg_catalog.set_config(
    'taskmaster.boundary_at',
    p_boundary_at::text,
    true
  );
  result_payload := taskmaster_internal.apply_execution_switch_v0028_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_new_session_id,
    p_new_task_occurrence_id,
    p_expected_active_session_id,
    p_expected_active_task_id,
    p_current_task_action,
    p_mode,
    p_expected_runtime_revision
  );
  perform pg_catalog.set_config('taskmaster.identity_rebase_command', '', true);
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  return result_payload;
exception when others then
  perform pg_catalog.set_config('taskmaster.identity_rebase_command', '', true);
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  raise;
end;
$$;

comment on function public.apply_execution_transition_v0032_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint,
  timestamptz, bigint
) is
  'Identity-guarded execution transition. A stale revision rebases only while the exact canonical task/session and compatible phase still match.';

comment on function public.apply_execution_switch_v0032_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint, timestamptz, bigint
) is
  'Identity-guarded active-task hand-off. A stale revision rebases only while the exact expected task/session still owns the canonical runtime.';
