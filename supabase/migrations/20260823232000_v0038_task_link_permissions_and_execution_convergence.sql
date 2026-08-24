-- Task/application endpoints already prove the authenticated owner, registered
-- device and every owner-scoped row before writing. They must run with the
-- function owner's privileges because their atomic transaction calls a
-- deliberately private normalizer and writes the protected command ledger.
alter function public.connect_application_to_task(
  uuid, uuid, bigint, uuid, uuid, uuid, text, text, text, text
) security definer;
alter function public.connect_application_to_task(
  uuid, uuid, bigint, uuid, uuid, uuid, text, text, text, text
) set search_path = '';

alter function public.remove_application_from_task(
  uuid, uuid, bigint, uuid, bigint
) security definer;
alter function public.remove_application_from_task(
  uuid, uuid, bigint, uuid, bigint
) set search_path = '';

revoke all on function public.connect_application_to_task(
  uuid, uuid, bigint, uuid, uuid, uuid, text, text, text, text
) from public, anon;
grant execute on function public.connect_application_to_task(
  uuid, uuid, bigint, uuid, uuid, uuid, text, text, text, text
) to authenticated;

revoke all on function public.remove_application_from_task(
  uuid, uuid, bigint, uuid, bigint
) from public, anon;
grant execute on function public.remove_application_from_task(
  uuid, uuid, bigint, uuid, bigint
) to authenticated;

-- A completion changes the task, session and singleton runtime in one atomic
-- transaction. Depending on trigger order, the runtime can already be idle by
-- the time the session-duration guard runs. The former guard treated that
-- valid in-transaction state as a hostile projection and rejected the whole
-- completion. Derive the safe upper bound from the locked session and client
-- boundary instead, then clamp a well-formed projection into that range.
-- Malformed projections and missing boundaries still fail closed.
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
  safe_boundary_at timestamptz;
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

  -- A session which was already inert before this statement cannot gain work.
  if old.state::text <> 'running'
      or old.active_segment_started_at is null then
    new.accumulated_active_ms := old.accumulated_active_ms;
    return new;
  end if;

  select *
  into runtime_row
  from public.user_runtime_state as runtime_state
  where runtime_state.user_id = new.user_id
  limit 1;

  select *
  into task_row
  from public.task_occurrences as task
  where task.user_id = new.user_id
    and task.id = new.task_occurrence_id
    and task.deleted_at is null;

  if not found then
    new.accumulated_active_ms := old.accumulated_active_ms;
    return new;
  end if;

  safe_boundary_at := least(
    coalesce(projected_boundary_at, pg_catalog.statement_timestamp()),
    pg_catalog.statement_timestamp()
  );
  elapsed_ms := greatest(
    0::bigint,
    extract(epoch from safe_boundary_at - old.active_segment_started_at)
      * 1000
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
      -- An offline boundary carries the client's exact accumulated total. One
      -- remaining focus interval is still the authoritative maximum.
      when projected_active_ms is not null then focus_remaining_ms
      else least(elapsed_ms, focus_remaining_ms)
    end;
  else
    -- Continuous work is bounded by the exact user-action boundary and by one
    -- day for compatibility with the previous mixed-version rollout.
    safe_active_ms := old.accumulated_active_ms
      + least(86400000::bigint, elapsed_ms);
  end if;

  if projected_active_ms is not null then
    new.accumulated_active_ms := least(
      safe_active_ms,
      greatest(old.accumulated_active_ms, projected_active_ms)
    );
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

comment on function private.cap_pomodoro_session_active_duration() is
  'Clamps well-formed execution projections to the locked session boundary without rejecting an atomic completion after its runtime becomes idle.';
