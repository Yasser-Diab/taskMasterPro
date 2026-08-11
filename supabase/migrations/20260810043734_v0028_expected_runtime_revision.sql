-- v0.0.28 runtime commands carry the revision against which the user acted.
-- The guard runs under the same account-wide transaction lock as the legacy
-- executor, so an action observed against revision N cannot mutate revision
-- N+1 after another device has already moved the timer forward.

create function taskmaster_internal.guard_execution_runtime_v0028_command(
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

  -- A command ID is immutable evidence of an accepted transition. Once a
  -- response was lost, device revocation or a stale retry payload must not
  -- turn that accepted command into a fresh failure.
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

  if runtime.revision <> p_expected_runtime_revision then
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

create function taskmaster_internal.apply_execution_transition_v0028_command(
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
  runtime public.user_runtime_state%rowtype;
  task_record public.task_occurrences%rowtype;
  session_record public.execution_sessions%rowtype;
  now_at timestamptz := statement_timestamp();
  focus_ms bigint;
  focus_remaining_ms bigint;
  elapsed_ms bigint;
  recorded_active_ms bigint;
  canonical_only_reason text;
begin
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

  if p_action = 'skip_break' then
    select *
    into runtime
    from public.user_runtime_state runtime_row
    where runtime_row.user_id = owner_id
    for update;

    if runtime.active_session_id is distinct from p_session_id
        or runtime.active_task_occurrence_id is distinct from p_task_occurrence_id then
      canonical_only_reason := 'runtime_target_mismatch';
    elsif runtime.state <> 'running'
        or runtime.active_segment_started_at is null then
      canonical_only_reason := 'focus_not_running';
    else
      select *
      into task_record
      from public.task_occurrences task_row
      where task_row.user_id = owner_id
        and task_row.id = p_task_occurrence_id
        and task_row.deleted_at is null
      for update;

      if not found then
        canonical_only_reason := 'missing_task';
      elsif task_record.execution_mode <> 'pomodoro' or p_mode <> 'pomodoro' then
        canonical_only_reason := 'not_pomodoro';
      else
        select *
        into session_record
        from public.execution_sessions session_row
        where session_row.user_id = owner_id
          and session_row.id = p_session_id
          and session_row.task_occurrence_id = p_task_occurrence_id
          and session_row.deleted_at is null
        for update;

        if not found then
          canonical_only_reason := 'missing_session';
        else
          focus_ms := coalesce(
            case
              when (task_record.data ->> 'pomodoro_focus_ms') ~ '^[0-9]{1,8}$'
                then (task_record.data ->> 'pomodoro_focus_ms')::bigint
            end,
            case
              when (task_record.data ->> 'pomodoro_focus_minutes') ~ '^[0-9]{1,4}$'
                then (task_record.data ->> 'pomodoro_focus_minutes')::bigint
                  * 60000
            end,
            1500000
          );
          focus_ms := greatest(60000::bigint, least(86400000::bigint, focus_ms));
          focus_remaining_ms := focus_ms - mod(
            greatest(0::bigint, runtime.accumulated_active_ms),
            focus_ms
          );
          elapsed_ms := greatest(
            0::bigint,
            extract(epoch from now_at - runtime.active_segment_started_at) * 1000
          )::bigint;

          if elapsed_ms < focus_remaining_ms then
            canonical_only_reason := 'focus_not_complete';
          else
            recorded_active_ms :=
              runtime.accumulated_active_ms + focus_remaining_ms;
          end if;
        end if;
      end if;
    end if;

    if canonical_only_reason is not null then
      result_payload := jsonb_build_object(
        'status', 'accepted',
        'canonical_only', true,
        'superseded', true,
        'reason', canonical_only_reason,
        'command_id', p_command_id,
        'runtime_revision', runtime.revision,
        'runtime_state', runtime.state,
        'canonical_runtime', to_jsonb(runtime)
      );
    else
      update public.execution_sessions
      set state = 'running',
          active_segment_started_at = now_at,
          accumulated_active_ms = recorded_active_ms,
          current_pomodoro_segment = 'focus',
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = p_session_id and user_id = owner_id;

      update public.task_occurrences
      set status = 'in_progress',
          active_duration_ms = recorded_active_ms,
          progress = case
            when estimated_duration_ms > 0 then least(
              1::numeric,
              recorded_active_ms::numeric / estimated_duration_ms
            )
            else progress
          end,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = p_task_occurrence_id and user_id = owner_id;

      update public.user_runtime_state
      set state = 'running',
          active_segment_started_at = now_at,
          accumulated_active_ms = recorded_active_ms,
          lease_device_id = p_device_id,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where id = runtime.id
      returning * into runtime;

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
        p_session_id,
        'skip_break',
        now_at,
        recorded_active_ms,
        p_device_id,
        jsonb_build_object(
          'task_occurrence_id', p_task_occurrence_id,
          'focus_duration_ms', focus_ms,
          'break_skipped', true
        ),
        p_device_id,
        p_device_id,
        p_command_id
      );

      result_payload := jsonb_build_object(
        'status', 'accepted',
        'command_id', p_command_id,
        'session_id', p_session_id,
        'runtime_revision', runtime.revision,
        'runtime_state', runtime.state,
        'canonical_runtime', to_jsonb(runtime)
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
      'execution_runtime',
      p_session_id,
      p_action,
      p_expected_runtime_revision,
      'accepted'::public.sync_command_status,
      result_payload,
      p_device_id,
      p_device_id,
      p_command_id
    );

    return result_payload;
  end if;

  result_payload := taskmaster_internal.apply_execution_transition_v0026_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_session_id,
    p_task_occurrence_id,
    p_action,
    p_mode
  );

  select *
  into runtime
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id;

  return coalesce(result_payload, '{}'::jsonb) || jsonb_build_object(
    'canonical_runtime', to_jsonb(runtime),
    'runtime_revision', runtime.revision,
    'runtime_state', runtime.state
  );
end;
$$;

create function taskmaster_internal.apply_execution_switch_v0028_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_new_session_id uuid,
  p_new_task_occurrence_id uuid,
  p_expected_active_session_id uuid,
  p_expected_active_task_id uuid,
  p_current_task_action text,
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
  runtime public.user_runtime_state%rowtype;
begin
  guard_result := taskmaster_internal.guard_execution_runtime_v0028_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    'execution_runtime_switch',
    p_new_session_id,
    p_current_task_action,
    p_expected_runtime_revision
  );
  if guard_result is not null then
    return guard_result;
  end if;

  result_payload := taskmaster_internal.apply_execution_switch_v0026_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_new_session_id,
    p_new_task_occurrence_id,
    p_expected_active_session_id,
    p_expected_active_task_id,
    p_current_task_action,
    p_mode
  );

  select *
  into runtime
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = owner_id;

  return coalesce(result_payload, '{}'::jsonb) || jsonb_build_object(
    'canonical_runtime', to_jsonb(runtime),
    'runtime_revision', runtime.revision,
    'runtime_state', runtime.state
  );
end;
$$;

create function public.apply_execution_transition_v0028_command(
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
  select taskmaster_internal.apply_execution_transition_v0028_command(
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

create function public.apply_execution_switch_v0028_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_new_session_id uuid,
  p_new_task_occurrence_id uuid,
  p_expected_active_session_id uuid,
  p_expected_active_task_id uuid,
  p_current_task_action text,
  p_mode public.execution_mode,
  p_expected_runtime_revision bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_execution_switch_v0028_command(
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
  )
$$;

revoke all on function taskmaster_internal.guard_execution_runtime_v0028_command(
  uuid, uuid, bigint, text, uuid, text, bigint
) from public, anon;
grant execute on function taskmaster_internal.guard_execution_runtime_v0028_command(
  uuid, uuid, bigint, text, uuid, text, bigint
) to authenticated, service_role;

revoke all on function taskmaster_internal.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) from public, anon;
grant execute on function taskmaster_internal.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) to authenticated, service_role;

revoke all on function taskmaster_internal.apply_execution_switch_v0028_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint
) from public, anon;
grant execute on function taskmaster_internal.apply_execution_switch_v0028_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint
) to authenticated, service_role;

revoke all on function public.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) from public, anon;
grant execute on function public.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) to authenticated;

revoke all on function public.apply_execution_switch_v0028_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint
) from public, anon;
grant execute on function public.apply_execution_switch_v0028_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint
) to authenticated;

comment on function public.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) is
  'Revision-guarded canonical runtime transition. A stale expected revision is accepted as a no-op with the full canonical runtime.';

comment on function public.apply_execution_switch_v0028_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint
) is
  'Revision-guarded canonical active-task hand-off. A stale expected revision is accepted as a no-op with the full canonical runtime.';
