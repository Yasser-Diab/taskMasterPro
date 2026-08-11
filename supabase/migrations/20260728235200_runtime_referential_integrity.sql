-- A runtime row is a live execution pointer, never an independent source of
-- truth. Keep it idle when its task or execution session has been tombstoned,
-- completed, cancelled, or otherwise disappeared.

create or replace function private.enforce_live_runtime_references()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_state text := new.state::text;
  has_live_task boolean := false;
  has_live_session boolean := false;
begin
  if requested_state in ('running', 'paused', 'break')
      and new.active_task_occurrence_id is not null
      and new.active_session_id is not null then
    select exists (
      select 1
      from public.task_occurrences task_row
      where task_row.id = new.active_task_occurrence_id
        and task_row.user_id = new.user_id
        and task_row.deleted_at is null
        and task_row.status::text not in ('completed', 'cancelled', 'archived')
    )
    into has_live_task;

    select exists (
      select 1
      from public.execution_sessions session_row
      where session_row.id = new.active_session_id
        and session_row.user_id = new.user_id
        and session_row.task_occurrence_id = new.active_task_occurrence_id
        and session_row.deleted_at is null
        and session_row.state::text in ('running', 'paused', 'break')
    )
    into has_live_session;
  end if;

  if requested_state not in ('running', 'paused', 'break')
      or not has_live_task
      or not has_live_session then
    if requested_state <> 'idle'
        or new.active_task_occurrence_id is not null
        or new.active_session_id is not null then
      new.data := coalesce(new.data, '{}'::jsonb) || jsonb_build_object(
        'runtime_integrity_repair',
        jsonb_build_object(
          'repaired_at', statement_timestamp(),
          'previous_state', requested_state
        )
      );
    end if;
    new.active_session_id := null;
    new.active_task_occurrence_id := null;
    new.state := 'idle'::public.session_state;
    new.active_segment_started_at := null;
    new.lease_device_id := null;
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_live_runtime_references()
from public, anon, authenticated;

drop trigger if exists aaa_validate_live_runtime_references
on public.user_runtime_state;
create trigger aaa_validate_live_runtime_references
before insert or update on public.user_runtime_state
for each row execute function private.enforce_live_runtime_references();

create or replace function private.close_runtime_for_unavailable_task()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  now_at timestamptz := statement_timestamp();
begin
  update public.execution_sessions session_row
  set state = case
        when new.deleted_at is null and new.status::text = 'completed'
          then 'completed'::public.session_state
        else 'cancelled'::public.session_state
      end,
      finished_at = coalesce(session_row.finished_at, now_at),
      active_segment_started_at = null,
      accumulated_active_ms = greatest(
        session_row.accumulated_active_ms,
        runtime_row.accumulated_active_ms + case
          when runtime_row.state = 'running'
              and runtime_row.active_segment_started_at is not null
            then greatest(
              0,
              extract(epoch from now_at - runtime_row.active_segment_started_at)
                * 1000
            )::bigint
          else 0
        end
      ),
      updated_by_device_id = coalesce(
        new.updated_by_device_id,
        runtime_row.updated_by_device_id
      ),
      last_command_id = coalesce(new.last_command_id, runtime_row.last_command_id)
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = new.user_id
    and runtime_row.active_task_occurrence_id = new.id
    and runtime_row.active_session_id = session_row.id
    and session_row.user_id = new.user_id;

  update public.user_runtime_state runtime_row
  set active_session_id = null,
      active_task_occurrence_id = null,
      state = 'idle'::public.session_state,
      active_segment_started_at = null,
      accumulated_active_ms = runtime_row.accumulated_active_ms + case
        when runtime_row.state = 'running'
            and runtime_row.active_segment_started_at is not null
          then greatest(
            0,
            extract(epoch from now_at - runtime_row.active_segment_started_at)
              * 1000
          )::bigint
        else 0
      end,
      lease_device_id = null,
      updated_by_device_id = coalesce(
        new.updated_by_device_id,
        runtime_row.updated_by_device_id
      ),
      last_command_id = coalesce(new.last_command_id, runtime_row.last_command_id),
      data = coalesce(runtime_row.data, '{}'::jsonb) || jsonb_build_object(
        'runtime_integrity_repair',
        jsonb_build_object(
          'repaired_at', now_at,
          'reason', 'active_task_unavailable'
        )
      )
  where runtime_row.user_id = new.user_id
    and runtime_row.active_task_occurrence_id = new.id;

  return new;
end;
$$;

revoke all on function private.close_runtime_for_unavailable_task()
from public, anon, authenticated;

drop trigger if exists close_runtime_for_unavailable_task
on public.task_occurrences;
create trigger close_runtime_for_unavailable_task
after update of deleted_at, status on public.task_occurrences
for each row
when (
  (new.deleted_at is not null and old.deleted_at is distinct from new.deleted_at)
  or (
    new.status::text in ('completed', 'cancelled', 'archived')
    and old.status is distinct from new.status
  )
)
execute function private.close_runtime_for_unavailable_task();

create or replace function private.close_runtime_for_deleted_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  now_at timestamptz := statement_timestamp();
begin
  update public.task_occurrences task_row
  set status = case
        when task_row.status::text in ('completed', 'cancelled', 'archived')
          then task_row.status
        else 'paused'::public.task_status
      end,
      active_duration_ms = greatest(
        task_row.active_duration_ms,
        runtime_row.accumulated_active_ms + case
          when runtime_row.state = 'running'
              and runtime_row.active_segment_started_at is not null
            then greatest(
              0,
              extract(epoch from now_at - runtime_row.active_segment_started_at)
                * 1000
            )::bigint
          else 0
        end
      ),
      updated_by_device_id = coalesce(
        new.updated_by_device_id,
        runtime_row.updated_by_device_id
      ),
      last_command_id = coalesce(new.last_command_id, runtime_row.last_command_id)
  from public.user_runtime_state runtime_row
  where runtime_row.user_id = new.user_id
    and runtime_row.active_session_id = new.id
    and task_row.id = runtime_row.active_task_occurrence_id
    and task_row.user_id = new.user_id;

  update public.user_runtime_state runtime_row
  set active_session_id = null,
      active_task_occurrence_id = null,
      state = 'idle'::public.session_state,
      active_segment_started_at = null,
      accumulated_active_ms = runtime_row.accumulated_active_ms + case
        when runtime_row.state = 'running'
            and runtime_row.active_segment_started_at is not null
          then greatest(
            0,
            extract(epoch from now_at - runtime_row.active_segment_started_at)
              * 1000
          )::bigint
        else 0
      end,
      lease_device_id = null,
      updated_by_device_id = coalesce(
        new.updated_by_device_id,
        runtime_row.updated_by_device_id
      ),
      last_command_id = coalesce(new.last_command_id, runtime_row.last_command_id),
      data = coalesce(runtime_row.data, '{}'::jsonb) || jsonb_build_object(
        'runtime_integrity_repair',
        jsonb_build_object(
          'repaired_at', now_at,
          'reason', 'active_session_unavailable'
        )
      )
  where runtime_row.user_id = new.user_id
    and runtime_row.active_session_id = new.id;

  return new;
end;
$$;

revoke all on function private.close_runtime_for_deleted_session()
from public, anon, authenticated;

drop trigger if exists close_runtime_for_deleted_session
on public.execution_sessions;
create trigger close_runtime_for_deleted_session
after update of deleted_at on public.execution_sessions
for each row
when (
  new.deleted_at is not null
  and old.deleted_at is distinct from new.deleted_at
)
execute function private.close_runtime_for_deleted_session();

-- Repair rows created by earlier builds. The validation trigger converts only
-- invalid live pointers; valid running/paused/break sessions remain untouched.
-- Close the historical session first because its task tombstone/status trigger
-- may have run before this invariant existed.
with invalid_runtime as (
  select
    runtime_row.user_id,
    runtime_row.active_session_id,
    runtime_row.accumulated_active_ms,
    runtime_row.active_segment_started_at,
    runtime_row.state,
    task_row.status as task_status,
    task_row.deleted_at as task_deleted_at
  from public.user_runtime_state runtime_row
  left join public.task_occurrences task_row
    on task_row.id = runtime_row.active_task_occurrence_id
   and task_row.user_id = runtime_row.user_id
  where runtime_row.state::text in ('running', 'paused', 'break')
    and (
      runtime_row.active_task_occurrence_id is null
      or runtime_row.active_session_id is null
      or task_row.id is null
      or task_row.deleted_at is not null
      or task_row.status::text in ('completed', 'cancelled', 'archived')
      or not exists (
        select 1
        from public.execution_sessions live_session
        where live_session.id = runtime_row.active_session_id
          and live_session.user_id = runtime_row.user_id
          and live_session.task_occurrence_id =
            runtime_row.active_task_occurrence_id
          and live_session.deleted_at is null
          and live_session.state::text in ('running', 'paused', 'break')
      )
    )
)
update public.execution_sessions session_row
set state = case
      when invalid_runtime.task_deleted_at is null
          and invalid_runtime.task_status::text = 'completed'
        then 'completed'::public.session_state
      else 'cancelled'::public.session_state
    end,
    finished_at = coalesce(session_row.finished_at, statement_timestamp()),
    active_segment_started_at = null,
    accumulated_active_ms = greatest(
      session_row.accumulated_active_ms,
      invalid_runtime.accumulated_active_ms + case
        when invalid_runtime.state = 'running'
            and invalid_runtime.active_segment_started_at is not null
          then greatest(
            0,
            extract(
              epoch from
                statement_timestamp()
                - invalid_runtime.active_segment_started_at
            ) * 1000
          )::bigint
        else 0
      end
    )
from invalid_runtime
where session_row.id = invalid_runtime.active_session_id
  and session_row.user_id = invalid_runtime.user_id
  and session_row.deleted_at is null
  and session_row.state::text in ('running', 'paused', 'break');

update public.user_runtime_state runtime_row
set updated_at = statement_timestamp()
where runtime_row.state::text in ('running', 'paused', 'break')
  and (
    runtime_row.active_task_occurrence_id is null
    or runtime_row.active_session_id is null
    or not exists (
      select 1
      from public.task_occurrences task_row
      where task_row.id = runtime_row.active_task_occurrence_id
        and task_row.user_id = runtime_row.user_id
        and task_row.deleted_at is null
        and task_row.status::text not in ('completed', 'cancelled', 'archived')
    )
    or not exists (
      select 1
      from public.execution_sessions session_row
      where session_row.id = runtime_row.active_session_id
        and session_row.user_id = runtime_row.user_id
        and session_row.task_occurrence_id =
          runtime_row.active_task_occurrence_id
        and session_row.deleted_at is null
        and session_row.state::text in ('running', 'paused', 'break')
    )
  );
