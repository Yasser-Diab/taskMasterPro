-- Pomodoro work is the union of completed/running focus intervals, never raw
-- wall-clock time. v0.0.28 capped local completion correctly, but the v0028
-- RPC delegated pause, complete and active-task switching to the older v0026
-- implementation. That implementation could add days between the last focus
-- start and a delayed command. These guards make every canonical projection
-- use the already-capped execution-session value and repair only rows backed
-- by their immutable completion snapshot.

create or replace function private.cap_pomodoro_session_active_duration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  runtime_row public.user_runtime_state%rowtype;
  task_row public.task_occurrences%rowtype;
  focus_ms bigint;
  focus_base_ms bigint;
  focus_elapsed_ms bigint;
  focus_remaining_ms bigint;
  elapsed_ms bigint;
  safe_active_ms bigint;
  projected_setting text;
  projected_active_ms bigint;
  projected_boundary_setting text;
  projected_boundary_at timestamptz;
begin
  if new.accumulated_active_ms <= old.accumulated_active_ms then
    return new;
  end if;

  projected_setting := nullif(
    pg_catalog.current_setting('taskmaster.projected_active_ms', true),
    ''
  );
  if new.mode::text is distinct from 'pomodoro'
      and projected_setting is null then
    return new;
  end if;

  if projected_setting is not null then
    if projected_setting !~ '^[0-9]{1,15}$' then
      raise exception 'invalid_projected_active_ms';
    end if;
    projected_active_ms := projected_setting::bigint;
    projected_boundary_setting := nullif(
      pg_catalog.current_setting('taskmaster.boundary_at', true),
      ''
    );
    if projected_boundary_setting is null then
      raise exception 'invalid_projected_boundary_at';
    end if;
    projected_boundary_at := projected_boundary_setting::timestamptz;
  end if;

  -- Paused, break, stopped and completed sessions are inert. A later write can
  -- preserve their total but can never turn their wall-clock lifetime into
  -- focused work.
  if old.state::text <> 'running'
      or old.active_segment_started_at is null then
    if projected_active_ms is not null
        and projected_active_ms <> old.accumulated_active_ms then
      raise exception 'invalid_projected_active_ms';
    end if;
    new.accumulated_active_ms := old.accumulated_active_ms;
    return new;
  end if;

  select *
  into runtime_row
  from public.user_runtime_state runtime_state
  where runtime_state.user_id = new.user_id
    and runtime_state.active_session_id = new.id
    and runtime_state.active_task_occurrence_id = new.task_occurrence_id
  limit 1;

  if not found or runtime_row.state::text <> 'running'
      or runtime_row.active_segment_started_at is null then
    if projected_active_ms is not null
        and projected_active_ms <> old.accumulated_active_ms then
      raise exception 'invalid_projected_active_ms';
    end if;
    new.accumulated_active_ms := old.accumulated_active_ms;
    return new;
  end if;

  select *
  into task_row
  from public.task_occurrences task
  where task.user_id = new.user_id
    and task.id = new.task_occurrence_id
    and task.deleted_at is null;

  if not found then
    if projected_active_ms is not null
        and projected_active_ms <> old.accumulated_active_ms then
      raise exception 'invalid_projected_active_ms';
    end if;
    new.accumulated_active_ms := old.accumulated_active_ms;
    return new;
  end if;

  elapsed_ms := greatest(
    0::bigint,
    extract(
      epoch from statement_timestamp() - runtime_row.active_segment_started_at
    ) * 1000
  )::bigint;

  if new.mode::text = 'pomodoro' then
    focus_ms := coalesce(
      case
        when (task_row.data ->> 'pomodoro_focus_ms') ~ '^[0-9]{1,8}$'
          then (task_row.data ->> 'pomodoro_focus_ms')::bigint
      end,
      case
        when (task_row.data ->> 'pomodoro_focus_minutes') ~ '^[0-9]{1,4}$'
          then (task_row.data ->> 'pomodoro_focus_minutes')::bigint * 60000
      end,
      1500000
    );
    focus_ms := greatest(60000::bigint, least(86400000::bigint, focus_ms));
    focus_base_ms := coalesce(
      case
        when (runtime_row.data ->> 'focus_interval_active_base_ms') ~
            '^[0-9]{1,15}$'
          then (runtime_row.data ->> 'focus_interval_active_base_ms')::bigint
      end,
      -- Missing metadata must fail closed. The already-recorded lifetime total
      -- is a safe base; at most one configured focus may be added.
      greatest(0::bigint, old.accumulated_active_ms)
    );
    focus_base_ms := least(
      greatest(0::bigint, old.accumulated_active_ms),
      greatest(0::bigint, focus_base_ms)
    );
    focus_elapsed_ms := least(
      focus_ms,
      greatest(0::bigint, old.accumulated_active_ms - focus_base_ms)
    );
    focus_remaining_ms := greatest(0::bigint, focus_ms - focus_elapsed_ms);
    safe_active_ms := old.accumulated_active_ms + case
      -- A revision-guarded v0032 command carries the exact local total. Its
      -- Start may have been delivered only milliseconds earlier, so server
      -- elapsed time cannot validate offline work. One remaining focus is the
      -- authoritative upper bound.
      when projected_active_ms is not null then focus_remaining_ms
      else least(elapsed_ms, focus_remaining_ms)
    end;
  else
    -- A client-boundary start/resume gives continuous timers an exact elapsed
    -- upper bound. During the mixed-version rollout an older Start has no such
    -- marker, so accept at most one day for that single guarded transition.
    elapsed_ms := case
      when runtime_row.data ->> 'active_segment_boundary_source' = 'client'
        and projected_boundary_at >= runtime_row.active_segment_started_at
        then greatest(
          0::bigint,
          extract(
            epoch from projected_boundary_at -
              runtime_row.active_segment_started_at
          ) * 1000
        )::bigint
      else 86400000::bigint
    end;
    safe_active_ms := old.accumulated_active_ms
      + least(86400000::bigint, elapsed_ms);
  end if;

  if projected_active_ms is not null then
    if projected_active_ms < old.accumulated_active_ms
        or projected_active_ms > safe_active_ms then
      raise exception 'invalid_projected_active_ms';
    end if;
    new.accumulated_active_ms := projected_active_ms;
  else
    new.accumulated_active_ms := least(
      new.accumulated_active_ms,
      safe_active_ms
    );
  end if;
  return new;
end;
$$;

revoke all on function private.cap_pomodoro_session_active_duration()
from public, anon, authenticated;

drop trigger if exists aaa_cap_pomodoro_session_active_duration
on public.execution_sessions;
create trigger aaa_cap_pomodoro_session_active_duration
before update of state, active_segment_started_at, accumulated_active_ms
on public.execution_sessions
for each row execute function private.cap_pomodoro_session_active_duration();

create or replace function private.cap_pomodoro_task_active_duration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  safe_active_ms bigint;
  projected_setting text;
begin
  if new.active_duration_ms <= old.active_duration_ms then
    return new;
  end if;

  projected_setting := nullif(
    pg_catalog.current_setting('taskmaster.projected_active_ms', true),
    ''
  );
  if new.execution_mode::text is distinct from 'pomodoro'
      and projected_setting is null then
    return new;
  end if;

  select session_row.accumulated_active_ms
  into safe_active_ms
  from public.execution_sessions session_row
  where session_row.user_id = new.user_id
    and session_row.task_occurrence_id = new.id
    and session_row.deleted_at is null
    and session_row.last_command_id = new.last_command_id
  order by session_row.updated_at desc, session_row.id
  limit 1;

  if found then
    new.active_duration_ms := least(new.active_duration_ms, safe_active_ms);
    if new.status::text <> 'completed' and new.estimated_duration_ms > 0 then
      new.progress := least(
        1::numeric,
        new.active_duration_ms::numeric / new.estimated_duration_ms
      );
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.cap_pomodoro_task_active_duration()
from public, anon, authenticated;

drop trigger if exists aaa_cap_pomodoro_task_active_duration
on public.task_occurrences;
create trigger aaa_cap_pomodoro_task_active_duration
before update of status, active_duration_ms on public.task_occurrences
for each row execute function private.cap_pomodoro_task_active_duration();

create or replace function private.cap_pomodoro_runtime_active_duration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  safe_active_ms bigint;
  projected_setting text;
begin
  if new.accumulated_active_ms <= old.accumulated_active_ms then
    return new;
  end if;

  projected_setting := nullif(
    pg_catalog.current_setting('taskmaster.projected_active_ms', true),
    ''
  );

  -- During completion the task-status integrity trigger can make the runtime
  -- idle before the legacy RPC performs its final runtime UPDATE. Match the
  -- exact command lineage as well as the former active session so that this
  -- second write cannot reintroduce the raw wall-clock value.
  select session_row.accumulated_active_ms
  into safe_active_ms
  from public.execution_sessions session_row
  where session_row.user_id = new.user_id
    and (
      session_row.mode::text = 'pomodoro'
      or projected_setting is not null
    )
    and session_row.deleted_at is null
    and (
      session_row.id = old.active_session_id
      or (
        new.last_command_id is not null
        and session_row.last_command_id = new.last_command_id
      )
    )
  order by
    case when session_row.last_command_id = new.last_command_id then 0 else 1 end,
    session_row.updated_at desc,
    session_row.id
  limit 1;

  if found then
    new.accumulated_active_ms := least(
      new.accumulated_active_ms,
      safe_active_ms
    );
  elsif old.state::text in ('paused', 'break', 'idle') then
    new.accumulated_active_ms := old.accumulated_active_ms;
  end if;
  return new;
end;
$$;

revoke all on function private.cap_pomodoro_runtime_active_duration()
from public, anon, authenticated;

drop trigger if exists aaa_cap_pomodoro_runtime_active_duration
on public.user_runtime_state;
create trigger aaa_cap_pomodoro_runtime_active_duration
before update of state, active_session_id, active_task_occurrence_id,
  accumulated_active_ms on public.user_runtime_state
for each row execute function private.cap_pomodoro_runtime_active_duration();

create or replace function private.apply_execution_session_boundary_timestamp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  boundary_setting text := nullif(
    pg_catalog.current_setting('taskmaster.boundary_at', true),
    ''
  );
  boundary_at timestamptz;
begin
  if boundary_setting is null then
    return new;
  end if;
  boundary_at := boundary_setting::timestamptz;

  if tg_op = 'INSERT' then
    if new.state::text in ('running', 'break') then
      new.started_at := coalesce(new.started_at, boundary_at);
      new.active_segment_started_at := boundary_at;
    elsif new.state::text = 'completed' then
      new.finished_at := boundary_at;
    end if;
    return new;
  end if;

  if new.state::text in ('running', 'break')
      and (
        old.state::text is distinct from new.state::text
        or new.active_segment_started_at is distinct from
          old.active_segment_started_at
      ) then
    new.started_at := coalesce(old.started_at, boundary_at);
    new.active_segment_started_at := boundary_at;
  elsif new.state::text = 'completed'
      and old.state::text is distinct from 'completed' then
    new.finished_at := boundary_at;
  end if;
  return new;
end;
$$;

create or replace function private.apply_execution_runtime_boundary_timestamp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  boundary_setting text := nullif(
    pg_catalog.current_setting('taskmaster.boundary_at', true),
    ''
  );
  boundary_at timestamptz;
begin
  if boundary_setting is null then
    return new;
  end if;
  boundary_at := boundary_setting::timestamptz;
  new.data := coalesce(new.data, '{}'::jsonb);

  if new.state::text in ('running', 'break')
      and (
        new.active_session_id is distinct from old.active_session_id
        or old.state::text is distinct from new.state::text
        or new.active_segment_started_at is distinct from
          old.active_segment_started_at
      ) then
    new.active_segment_started_at := boundary_at;
    if new.state::text = 'running' then
      new.data := jsonb_set(
        new.data,
        '{active_segment_boundary_source}',
        '"client"'::jsonb,
        true
      );
    else
      new.data := new.data - 'active_segment_boundary_source';
    end if;
  elsif new.state::text not in ('running', 'break') then
    new.data := new.data - 'active_segment_boundary_source';
  end if;
  return new;
end;
$$;

create or replace function private.apply_execution_task_boundary_timestamp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  boundary_setting text := nullif(
    pg_catalog.current_setting('taskmaster.boundary_at', true),
    ''
  );
  boundary_at timestamptz;
begin
  if boundary_setting is null then
    return new;
  end if;
  boundary_at := boundary_setting::timestamptz;

  if new.status::text = 'in_progress'
      and old.status::text is distinct from 'in_progress' then
    new.actual_start := coalesce(old.actual_start, boundary_at);
  elsif new.status::text = 'completed'
      and old.status::text is distinct from 'completed' then
    new.actual_finish := boundary_at;
  end if;
  return new;
end;
$$;

create or replace function private.cap_execution_event_active_duration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  safe_active_ms bigint;
  boundary_setting text := nullif(
    pg_catalog.current_setting('taskmaster.boundary_at', true),
    ''
  );
begin
  if boundary_setting is not null then
    new.occurred_at := boundary_setting::timestamptz;
  end if;
  if new.event_type::text not in (
    'pause', 'start_break', 'skip_break', 'complete'
  ) or new.duration_ms is null then
    return new;
  end if;

  select session_row.accumulated_active_ms
  into safe_active_ms
  from public.execution_sessions session_row
  where session_row.user_id = new.user_id
    and session_row.id = new.session_id
    and session_row.deleted_at is null
    and session_row.last_command_id = new.last_command_id;

  if found then
    new.duration_ms := safe_active_ms;
  end if;
  return new;
end;
$$;

revoke all on function private.apply_execution_session_boundary_timestamp()
from public, anon, authenticated;
revoke all on function private.apply_execution_runtime_boundary_timestamp()
from public, anon, authenticated;
revoke all on function private.apply_execution_task_boundary_timestamp()
from public, anon, authenticated;
revoke all on function private.cap_execution_event_active_duration()
from public, anon, authenticated;

drop trigger if exists aa0_apply_execution_session_boundary_timestamp
on public.execution_sessions;
create trigger aa0_apply_execution_session_boundary_timestamp
before insert or update of state, started_at, finished_at,
  active_segment_started_at on public.execution_sessions
for each row execute function
  private.apply_execution_session_boundary_timestamp();

drop trigger if exists aa0_apply_execution_runtime_boundary_timestamp
on public.user_runtime_state;
create trigger aa0_apply_execution_runtime_boundary_timestamp
before update of state, active_session_id, active_segment_started_at
on public.user_runtime_state
for each row execute function
  private.apply_execution_runtime_boundary_timestamp();

drop trigger if exists aa0_apply_execution_task_boundary_timestamp
on public.task_occurrences;
create trigger aa0_apply_execution_task_boundary_timestamp
before update of status, actual_start, actual_finish
on public.task_occurrences
for each row execute function private.apply_execution_task_boundary_timestamp();

drop trigger if exists aa0_cap_execution_event_active_duration
on public.session_events;
create trigger aa0_cap_execution_event_active_duration
before insert or update of occurred_at, duration_ms on public.session_events
for each row execute function private.cap_execution_event_active_duration();

-- v0.0.39 freezes the local accumulated total at the user boundary and sends
-- it with the durable command. The existing revision guard still decides
-- whether the command is current; this wrapper only prevents later transport
-- time from entering the accepted duration. New names avoid PostgREST overload
-- ambiguity and leave v0028 callable while older installations drain outboxes.
create function taskmaster_internal.apply_execution_transition_v0032_command(
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
  guard_result jsonb;
  result_payload jsonb;
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

  if p_projected_active_ms is null or p_projected_active_ms < 0
      or p_boundary_at is null
      or p_boundary_at > statement_timestamp() + interval '5 minutes' then
    raise exception 'invalid_projected_active_ms';
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
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  return result_payload;
exception when others then
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  raise;
end;
$$;

create function taskmaster_internal.apply_execution_switch_v0032_command(
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
  guard_result jsonb;
  result_payload jsonb;
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

  if p_projected_active_ms is null or p_projected_active_ms < 0
      or p_boundary_at is null
      or p_boundary_at > statement_timestamp() + interval '5 minutes' then
    raise exception 'invalid_projected_active_ms';
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
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  return result_payload;
exception when others then
  perform pg_catalog.set_config('taskmaster.projected_active_ms', '', true);
  perform pg_catalog.set_config('taskmaster.boundary_at', '', true);
  raise;
end;
$$;

create function public.apply_execution_transition_v0032_command(
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
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_execution_transition_v0032_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_session_id,
    p_task_occurrence_id,
    p_action,
    p_mode,
    p_projected_active_ms,
    p_boundary_at,
    p_expected_runtime_revision
  )
$$;

create function public.apply_execution_switch_v0032_command(
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
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_execution_switch_v0032_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_new_session_id,
    p_new_task_occurrence_id,
    p_expected_active_session_id,
    p_expected_active_task_id,
    p_current_task_action,
    p_mode,
    p_projected_active_ms,
    p_boundary_at,
    p_expected_runtime_revision
  )
$$;

revoke all on function
  taskmaster_internal.apply_execution_transition_v0032_command(
    uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint,
    timestamptz, bigint
  ) from public, anon;
grant execute on function
  taskmaster_internal.apply_execution_transition_v0032_command(
    uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint,
    timestamptz, bigint
  ) to authenticated, service_role;

revoke all on function taskmaster_internal.apply_execution_switch_v0032_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint, timestamptz, bigint
) from public, anon;
grant execute on function taskmaster_internal.apply_execution_switch_v0032_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint, timestamptz, bigint
) to authenticated, service_role;

revoke all on function public.apply_execution_transition_v0032_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint,
  timestamptz, bigint
) from public, anon;
grant execute on function public.apply_execution_transition_v0032_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint,
  timestamptz, bigint
) to authenticated;

revoke all on function public.apply_execution_switch_v0032_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint, timestamptz, bigint
) from public, anon;
grant execute on function public.apply_execution_switch_v0032_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint, timestamptz, bigint
) to authenticated;

comment on function public.apply_execution_transition_v0032_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint,
  timestamptz, bigint
) is
  'Revision-guarded execution transition using the exact local boundary duration.';

comment on function public.apply_execution_switch_v0032_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode,
  bigint, timestamptz, bigint
) is
  'Revision-guarded active-task switch using the exact local boundary duration.';

-- The completion snapshot is created locally before the server transition is
-- accepted, and records the capped total plus the exact task/session/command
-- lineage. It is therefore stronger repair evidence than elapsed timestamps.
drop table if exists pg_temp.taskmaster_v0032_duration_repairs;
create temporary table taskmaster_v0032_duration_repairs as
select distinct on (task_row.user_id, task_row.id)
  task_row.user_id,
  task_row.id as task_id,
  (snapshot.evidence_metadata ->> 'previous_runtime_session_id')::uuid
    as session_id,
  (snapshot.evidence_metadata ->> 'task_completion_command_id')::uuid
    as completion_command_id,
  case
    when (snapshot.evidence_metadata ->> 'pomodoro_boundary_command_id') ~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then (snapshot.evidence_metadata ->> 'pomodoro_boundary_command_id')::uuid
  end as pomodoro_boundary_command_id,
  (snapshot.evidence_metadata ->> 'completed_active_duration_ms')::bigint
    as safe_active_ms
from public.task_completion_evidence snapshot
join public.task_occurrences task_row
  on task_row.user_id = snapshot.user_id
 and task_row.id = snapshot.task_occurrence_id
join public.execution_sessions session_row
  on session_row.user_id = task_row.user_id
 and session_row.id::text =
    snapshot.evidence_metadata ->> 'previous_runtime_session_id'
 and session_row.task_occurrence_id = task_row.id
 and session_row.mode::text = 'pomodoro'
 and session_row.deleted_at is null
 and session_row.last_command_id::text =
    snapshot.evidence_metadata ->> 'task_completion_command_id'
where snapshot.deleted_at is null
  and snapshot.evidence_type = 'completion_snapshot'
  and task_row.deleted_at is null
  and task_row.execution_mode::text = 'pomodoro'
  and task_row.status::text = 'completed'
  and task_row.last_command_id::text =
    snapshot.evidence_metadata ->> 'task_completion_command_id'
  and (snapshot.evidence_metadata ->> 'previous_runtime_session_id') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and (snapshot.evidence_metadata ->> 'task_completion_command_id') ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  and (snapshot.evidence_metadata ->> 'completed_active_duration_ms') ~
    '^[0-9]{1,15}$'
  and task_row.active_duration_ms >
    (snapshot.evidence_metadata ->> 'completed_active_duration_ms')::bigint
order by task_row.user_id, task_row.id, snapshot.created_at desc, snapshot.id;

update public.execution_sessions session_row
set accumulated_active_ms = repair.safe_active_ms
from taskmaster_v0032_duration_repairs repair
where session_row.user_id = repair.user_id
  and session_row.id = repair.session_id
  and session_row.task_occurrence_id = repair.task_id
  and session_row.last_command_id = repair.completion_command_id
  and session_row.mode::text = 'pomodoro'
  and session_row.accumulated_active_ms > repair.safe_active_ms;

update public.session_events event_row
set duration_ms = repair.safe_active_ms
from taskmaster_v0032_duration_repairs repair
where event_row.user_id = repair.user_id
  and event_row.session_id = repair.session_id
  and event_row.event_type::text = 'complete'
  and event_row.last_command_id = repair.completion_command_id
  and event_row.duration_ms > repair.safe_active_ms;

update public.task_occurrences task_row
set active_duration_ms = repair.safe_active_ms
from taskmaster_v0032_duration_repairs repair
where task_row.user_id = repair.user_id
  and task_row.id = repair.task_id
  and task_row.last_command_id = repair.completion_command_id
  and task_row.active_duration_ms > repair.safe_active_ms;

update public.user_runtime_state runtime_row
set accumulated_active_ms = repair.safe_active_ms
from taskmaster_v0032_duration_repairs repair
where runtime_row.user_id = repair.user_id
  and runtime_row.state::text = 'idle'
  and runtime_row.last_command_id = repair.completion_command_id
  and runtime_row.accumulated_active_ms > repair.safe_active_ms;

update public.pomodoro_cycles cycle_row
set focus_ended_at = cycle_row.focus_started_at
      + cycle_row.focus_duration_ms::double precision
        * interval '1 millisecond'
from taskmaster_v0032_duration_repairs repair
where cycle_row.user_id = repair.user_id
  and cycle_row.session_id = repair.session_id
  and cycle_row.last_command_id = repair.pomodoro_boundary_command_id
  and cycle_row.data ->> 'boundary_reason' = 'task_completed'
  and cycle_row.focus_ended_at > cycle_row.focus_started_at
      + cycle_row.focus_duration_ms::double precision
        * interval '1 millisecond';

-- A stale idempotent retry must not return the pre-repair canonical runtime
-- and overwrite the corrected local projection. Removing only that embedded
-- snapshot makes the client consume the fresh sync-change rows emitted by the
-- four guarded UPDATEs above.
update public.processed_commands command_row
set result = (coalesce(command_row.result, '{}'::jsonb) - 'canonical_runtime')
      || jsonb_build_object(
        'duration_repaired', true,
        'active_duration_ms', repair.safe_active_ms
      )
from taskmaster_v0032_duration_repairs repair
where command_row.user_id = repair.user_id
  and command_row.command_id = repair.completion_command_id
  and command_row.entity_type = 'execution_runtime'
  and command_row.command_type = 'complete';

drop table taskmaster_v0032_duration_repairs;

comment on function private.cap_pomodoro_session_active_duration() is
  'Caps every Pomodoro execution boundary to the remaining focus interval.';
