-- Pomodoro lifetime work and the active focus interval are different facts.
-- Earlier builds inferred the current interval with
-- `accumulated_active_ms % focus_ms`; an early break therefore made every
-- later 25-minute focus start partially elapsed. Persist the interval base
-- and completed-cycle count beside the canonical runtime instead.

-- Operational reruns must reconstruct history without the transition trigger
-- interpreting the repair UPDATE as a new focus boundary. Reinstall both
-- triggers after the idempotent backfill below.
drop trigger if exists aab_prepare_pomodoro_runtime_interval
on public.user_runtime_state;
drop trigger if exists aab_prepare_pomodoro_session_cycle
on public.execution_sessions;

create or replace function private.prepare_pomodoro_runtime_interval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  task_mode text;
  interval_base_ms bigint;
  completed_focuses integer;
begin
  new.data := coalesce(new.data, '{}'::jsonb);

  if new.active_task_occurrence_id is null
      or new.active_session_id is null
      or new.state::text = 'idle' then
    new.data := new.data
      - 'focus_interval_active_base_ms'
      - 'pomodoro_completed_focuses';
    return new;
  end if;

  select task_row.execution_mode::text
  into task_mode
  from public.task_occurrences task_row
  where task_row.user_id = new.user_id
    and task_row.id = new.active_task_occurrence_id
    and task_row.deleted_at is null;

  if task_mode is distinct from 'pomodoro' then
    new.data := new.data
      - 'focus_interval_active_base_ms'
      - 'pomodoro_completed_focuses';
    return new;
  end if;

  interval_base_ms := coalesce(
    case
      when (old.data ->> 'focus_interval_active_base_ms') ~ '^[0-9]{1,15}$'
        then (old.data ->> 'focus_interval_active_base_ms')::bigint
    end,
    0
  );
  completed_focuses := coalesce(
    case
      when (old.data ->> 'pomodoro_completed_focuses') ~ '^[0-9]{1,8}$'
        then (old.data ->> 'pomodoro_completed_focuses')::integer
    end,
    0
  );

  if old.active_session_id is distinct from new.active_session_id
      or old.active_task_occurrence_id is distinct from
        new.active_task_occurrence_id
      or old.state::text = 'idle' then
    interval_base_ms := 0;
    completed_focuses := 0;
  elsif old.state::text = 'running' and new.state::text = 'break' then
    interval_base_ms := greatest(0::bigint, new.accumulated_active_ms);
    completed_focuses := completed_focuses + 1;
  elsif old.state::text = 'break' and new.state::text = 'running' then
    interval_base_ms := greatest(0::bigint, new.accumulated_active_ms);
  elsif old.state::text = 'running'
      and new.state::text = 'running'
      and new.active_segment_started_at is distinct from
        old.active_segment_started_at
      and new.accumulated_active_ms > old.accumulated_active_ms then
    -- Atomic Skip break closes one focus and begins the next focus without an
    -- intermediate break row.
    interval_base_ms := greatest(0::bigint, new.accumulated_active_ms);
    completed_focuses := completed_focuses + 1;
  end if;

  interval_base_ms := least(
    greatest(0::bigint, new.accumulated_active_ms),
    greatest(0::bigint, interval_base_ms)
  );
  new.data := jsonb_set(
    jsonb_set(
      new.data,
      '{focus_interval_active_base_ms}',
      to_jsonb(interval_base_ms),
      true
    ),
    '{pomodoro_completed_focuses}',
    to_jsonb(greatest(0, completed_focuses)),
    true
  );
  return new;
end;
$$;

revoke all on function private.prepare_pomodoro_runtime_interval()
from public, anon, authenticated;

create or replace function private.prepare_pomodoro_session_cycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.mode::text is distinct from 'pomodoro' then
    return new;
  end if;

  if old.state::text = 'running' and new.state::text = 'break' then
    new.current_cycle := greatest(0, old.current_cycle) + 1;
    new.current_pomodoro_segment := 'break';
  elsif old.state::text = 'break' and new.state::text = 'running' then
    new.current_cycle := greatest(0, old.current_cycle);
    new.current_pomodoro_segment := 'focus';
  elsif old.state::text = 'running'
      and new.state::text = 'running'
      and new.active_segment_started_at is distinct from
        old.active_segment_started_at
      and new.accumulated_active_ms > old.accumulated_active_ms then
    new.current_cycle := greatest(0, old.current_cycle) + 1;
    new.current_pomodoro_segment := 'focus';
  elsif old.state::text = 'idle' and new.state::text = 'running' then
    new.current_pomodoro_segment := 'focus';
  end if;
  return new;
end;
$$;

revoke all on function private.prepare_pomodoro_session_cycle()
from public, anon, authenticated;

-- Recover sessions by replaying their state-changing events. v0.0.26 could
-- append an accepted canonical-only start_break/skip_break event even though
-- the timer did not move. A real focus boundary must therefore satisfy both:
-- focus was running, and the durable lifetime duration advanced beyond the
-- preceding accepted boundary.
with recursive ordered_events as (
  select
    session_row.user_id,
    session_row.id as session_id,
    row_number() over (
      partition by session_row.user_id, session_row.id
      order by event_row.occurred_at, event_row.id
    ) as event_number,
    event_row.event_type::text as event_type,
    event_row.duration_ms
  from public.execution_sessions session_row
  join public.session_events event_row
    on event_row.user_id = session_row.user_id
   and event_row.session_id = session_row.id
   and event_row.deleted_at is null
  where session_row.mode::text = 'pomodoro'
    and session_row.deleted_at is null
), event_walk(
  user_id,
  session_id,
  event_number,
  canonical_state,
  completed_focuses,
  last_focus_boundary_ms
) as (
  select
    session_row.user_id,
    session_row.id,
    0::bigint,
    'running'::text,
    0::integer,
    0::bigint
  from public.execution_sessions session_row
  where session_row.mode::text = 'pomodoro'
    and session_row.deleted_at is null
  union all
  select
    walk.user_id,
    walk.session_id,
    event_row.event_number,
    case
      when event_row.event_type = 'complete' then 'completed'
      when event_row.event_type = 'start_break'
        and walk.canonical_state = 'running'
        and event_row.duration_ms is not null
        and event_row.duration_ms > walk.last_focus_boundary_ms
        then 'break'
      when event_row.event_type = 'finish_break'
        and walk.canonical_state = 'break'
        then 'running'
      when event_row.event_type = 'pause'
        and walk.canonical_state = 'running'
        then 'paused'
      when event_row.event_type = 'resume'
        and walk.canonical_state = 'paused'
        then 'running'
      else walk.canonical_state
    end,
    walk.completed_focuses + case
      when event_row.event_type in ('start_break', 'skip_break')
        and walk.canonical_state = 'running'
        and event_row.duration_ms is not null
        and event_row.duration_ms > walk.last_focus_boundary_ms
        then 1
      else 0
    end,
    case
      when event_row.event_type in ('start_break', 'skip_break')
        and walk.canonical_state = 'running'
        and event_row.duration_ms is not null
        and event_row.duration_ms > walk.last_focus_boundary_ms
        then event_row.duration_ms
      else walk.last_focus_boundary_ms
    end
  from event_walk walk
  join ordered_events event_row
    on event_row.user_id = walk.user_id
   and event_row.session_id = walk.session_id
   and event_row.event_number = walk.event_number + 1
), session_totals as (
  select distinct on (walk.user_id, walk.session_id)
    walk.user_id,
    walk.session_id,
    walk.completed_focuses,
    walk.last_focus_boundary_ms
  from event_walk walk
  order by walk.user_id, walk.session_id, walk.event_number desc
), runtime_repairs as (
  select
    runtime_row.id,
    jsonb_set(
      jsonb_set(
        coalesce(runtime_row.data, '{}'::jsonb),
        '{focus_interval_active_base_ms}',
        to_jsonb(
          case
            when runtime_row.state::text = 'break'
              then greatest(0::bigint, runtime_row.accumulated_active_ms)
            else least(
              greatest(0::bigint, runtime_row.accumulated_active_ms),
              greatest(0::bigint, totals.last_focus_boundary_ms)
            )
          end
        ),
        true
      ),
      '{pomodoro_completed_focuses}',
      to_jsonb(greatest(0, totals.completed_focuses)),
      true
    ) as repaired_data
  from public.user_runtime_state runtime_row
  join public.task_occurrences task_row
    on task_row.user_id = runtime_row.user_id
   and task_row.id = runtime_row.active_task_occurrence_id
   and task_row.deleted_at is null
   and task_row.execution_mode::text = 'pomodoro'
  join session_totals totals
    on totals.user_id = runtime_row.user_id
   and totals.session_id = runtime_row.active_session_id
)
update public.user_runtime_state runtime_row
set data = repair.repaired_data
from runtime_repairs repair
where runtime_row.id = repair.id
  and runtime_row.data is distinct from repair.repaired_data;

with recursive ordered_events as (
  select
    session_row.user_id,
    session_row.id as session_id,
    row_number() over (
      partition by session_row.user_id, session_row.id
      order by event_row.occurred_at, event_row.id
    ) as event_number,
    event_row.event_type::text as event_type,
    event_row.duration_ms
  from public.execution_sessions session_row
  join public.session_events event_row
    on event_row.user_id = session_row.user_id
   and event_row.session_id = session_row.id
   and event_row.deleted_at is null
  where session_row.mode::text = 'pomodoro'
    and session_row.deleted_at is null
), event_walk(
  user_id,
  session_id,
  event_number,
  canonical_state,
  completed_focuses,
  last_focus_boundary_ms
) as (
  select
    session_row.user_id,
    session_row.id,
    0::bigint,
    'running'::text,
    0::integer,
    0::bigint
  from public.execution_sessions session_row
  where session_row.mode::text = 'pomodoro'
    and session_row.deleted_at is null
  union all
  select
    walk.user_id,
    walk.session_id,
    event_row.event_number,
    case
      when event_row.event_type = 'complete' then 'completed'
      when event_row.event_type = 'start_break'
        and walk.canonical_state = 'running'
        and event_row.duration_ms is not null
        and event_row.duration_ms > walk.last_focus_boundary_ms
        then 'break'
      when event_row.event_type = 'finish_break'
        and walk.canonical_state = 'break'
        then 'running'
      when event_row.event_type = 'pause'
        and walk.canonical_state = 'running'
        then 'paused'
      when event_row.event_type = 'resume'
        and walk.canonical_state = 'paused'
        then 'running'
      else walk.canonical_state
    end,
    walk.completed_focuses + case
      when event_row.event_type in ('start_break', 'skip_break')
        and walk.canonical_state = 'running'
        and event_row.duration_ms is not null
        and event_row.duration_ms > walk.last_focus_boundary_ms
        then 1
      else 0
    end,
    case
      when event_row.event_type in ('start_break', 'skip_break')
        and walk.canonical_state = 'running'
        and event_row.duration_ms is not null
        and event_row.duration_ms > walk.last_focus_boundary_ms
        then event_row.duration_ms
      else walk.last_focus_boundary_ms
    end
  from event_walk walk
  join ordered_events event_row
    on event_row.user_id = walk.user_id
   and event_row.session_id = walk.session_id
   and event_row.event_number = walk.event_number + 1
), session_totals as (
  select distinct on (walk.user_id, walk.session_id)
    walk.user_id,
    walk.session_id,
    walk.completed_focuses
  from event_walk walk
  order by walk.user_id, walk.session_id, walk.event_number desc
), session_repairs as (
  select
    session_row.id,
    totals.completed_focuses as repaired_cycle,
    case
      when session_row.state::text = 'break' then 'break'
      when session_row.state::text in ('running', 'paused') then 'focus'
      else session_row.current_pomodoro_segment
    end as repaired_segment
  from public.execution_sessions session_row
  join session_totals totals
    on totals.user_id = session_row.user_id
   and totals.session_id = session_row.id
  where session_row.mode::text = 'pomodoro'
    and session_row.deleted_at is null
)
update public.execution_sessions session_row
set current_cycle = repair.repaired_cycle,
    current_pomodoro_segment = repair.repaired_segment
from session_repairs repair
where session_row.id = repair.id
  and (
    session_row.current_cycle is distinct from repair.repaired_cycle
    or session_row.current_pomodoro_segment is distinct from
      repair.repaired_segment
  );

-- Install the transition-aware triggers only after the historical backfill;
-- otherwise an UPDATE of an old row with no metadata would correctly preserve
-- its OLD values and overwrite the recovered boundary.
drop trigger if exists aab_prepare_pomodoro_runtime_interval
on public.user_runtime_state;
create trigger aab_prepare_pomodoro_runtime_interval
before update on public.user_runtime_state
for each row execute function private.prepare_pomodoro_runtime_interval();

drop trigger if exists aab_prepare_pomodoro_session_cycle
on public.execution_sessions;
create trigger aab_prepare_pomodoro_session_cycle
before update on public.execution_sessions
for each row execute function private.prepare_pomodoro_session_cycle();

-- Replace only the v0.0.28 internal transition implementation. The public
-- revision-guarded, break-cleanup wrapper and all grants remain unchanged.
create or replace function taskmaster_internal.apply_execution_transition_v0028_command(
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
  focus_base_ms bigint;
  focus_elapsed_ms bigint;
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

  -- Both ways of leaving a focus interval use the same capped lifetime-work
  -- calculation as the local repository. `start_break` may be chosen early;
  -- `skip_break` is valid only once the configured focus boundary is reached.
  if p_action in ('start_break', 'skip_break') then
    select *
    into runtime
    from public.user_runtime_state runtime_row
    where runtime_row.user_id = owner_id
    for update;

    if runtime.active_session_id is distinct from p_session_id
        or runtime.active_task_occurrence_id is distinct from
          p_task_occurrence_id then
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
      elsif task_record.execution_mode <> 'pomodoro'
          or p_mode <> 'pomodoro' then
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
              when (task_record.data ->> 'pomodoro_focus_ms') ~
                  '^[0-9]{1,8}$'
                then (task_record.data ->> 'pomodoro_focus_ms')::bigint
            end,
            case
              when (task_record.data ->> 'pomodoro_focus_minutes') ~
                  '^[0-9]{1,4}$'
                then (task_record.data ->> 'pomodoro_focus_minutes')::bigint
                  * 60000
            end,
            1500000
          );
          focus_ms := greatest(
            60000::bigint,
            least(86400000::bigint, focus_ms)
          );
          focus_base_ms := coalesce(
            case
              when (runtime.data ->> 'focus_interval_active_base_ms') ~
                  '^[0-9]{1,15}$'
                then (
                  runtime.data ->> 'focus_interval_active_base_ms'
                )::bigint
            end,
            -- Compatibility only for a row which somehow missed the
            -- migration backfill. New and repaired rows always use data.
            (greatest(0::bigint, runtime.accumulated_active_ms) / focus_ms)
              * focus_ms
          );
          focus_base_ms := least(
            greatest(0::bigint, runtime.accumulated_active_ms),
            greatest(0::bigint, focus_base_ms)
          );
          focus_elapsed_ms := least(
            focus_ms,
            greatest(
              0::bigint,
              runtime.accumulated_active_ms - focus_base_ms
            )
          );
          focus_remaining_ms := focus_ms - focus_elapsed_ms;
          elapsed_ms := greatest(
            0::bigint,
            extract(
              epoch from now_at - runtime.active_segment_started_at
            ) * 1000
          )::bigint;

          if p_action = 'skip_break' and elapsed_ms < focus_remaining_ms then
            canonical_only_reason := 'focus_not_complete';
          else
            recorded_active_ms :=
              runtime.accumulated_active_ms
              + least(elapsed_ms, focus_remaining_ms);
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
      set state = case
            when p_action = 'start_break' then 'break'::public.session_state
            else 'running'::public.session_state
          end,
          active_segment_started_at = now_at,
          accumulated_active_ms = recorded_active_ms,
          current_pomodoro_segment = case
            when p_action = 'start_break' then 'break'
            else 'focus'
          end,
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
      set state = case
            when p_action = 'start_break' then 'break'::public.session_state
            else 'running'::public.session_state
          end,
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
        p_action,
        now_at,
        recorded_active_ms,
        p_device_id,
        jsonb_build_object(
          'task_occurrence_id', p_task_occurrence_id,
          'focus_duration_ms', focus_ms,
          'break_skipped', p_action = 'skip_break'
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

  result_payload :=
    taskmaster_internal.apply_execution_transition_v0026_command(
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

revoke all on function taskmaster_internal.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) from public, anon;
grant execute on function taskmaster_internal.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) to authenticated, service_role;

comment on function taskmaster_internal.apply_execution_transition_v0028_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode, bigint
) is
  'Revision-guarded canonical runtime transition using explicit Pomodoro interval identity instead of lifetime-work modulo arithmetic.';
