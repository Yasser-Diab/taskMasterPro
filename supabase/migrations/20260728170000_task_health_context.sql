-- Privacy-safe health evidence linked to real task execution intervals.
--
-- These rows reuse the existing health_summaries command and RLS surface.
-- Daily summaries have task_occurrence_id = null; task summaries contain only
-- compact overlap aggregates, never raw Health Connect samples.

alter table public.health_summaries
  add column if not exists task_occurrence_id uuid,
  add column if not exists execution_session_id uuid,
  add column if not exists interval_start_at timestamptz,
  add column if not exists interval_end_at timestamptz,
  add column if not exists allocation_method text,
  add column if not exists estimated boolean not null default false,
  add column if not exists provenance text,
  add column if not exists overlap_fraction numeric(8,7),
  add column if not exists height_cm numeric(6,2),
  add column if not exists stride_factor numeric(6,5);

-- Include the owner and task in every relationship. A plain UUID foreign key
-- would allow a health row to point at another account's task if its UUID were
-- known, even though RLS correctly hides that task. The three-column session
-- reference also proves that the execution session belongs to this exact task.
create unique index if not exists execution_sessions_health_context_ref_idx
  on public.execution_sessions (user_id, task_occurrence_id, id);

alter table public.health_summaries
  drop constraint if exists health_summaries_task_occurrence_id_fkey,
  drop constraint if exists health_summaries_execution_session_id_fkey,
  drop constraint if exists health_summaries_task_owner_fkey,
  add constraint health_summaries_task_owner_fkey
    foreign key (user_id, task_occurrence_id)
    references public.task_occurrences (user_id, id)
    on delete cascade,
  drop constraint if exists health_summaries_task_session_fkey,
  add constraint health_summaries_task_session_fkey
    foreign key (user_id, task_occurrence_id, execution_session_id)
    references public.execution_sessions (user_id, task_occurrence_id, id)
    on delete cascade;

alter table public.health_summaries
  drop constraint if exists health_summaries_task_interval_valid,
  add constraint health_summaries_task_interval_valid check (
    interval_start_at is null
    or interval_end_at is null
    or interval_start_at <= interval_end_at
  ),
  drop constraint if exists health_summaries_overlap_fraction_valid,
  add constraint health_summaries_overlap_fraction_valid check (
    overlap_fraction is null
    or (overlap_fraction >= 0 and overlap_fraction <= 1)
  ),
  drop constraint if exists health_summaries_height_valid,
  add constraint health_summaries_height_valid check (
    height_cm is null or (height_cm >= 50 and height_cm <= 250)
  ),
  drop constraint if exists health_summaries_stride_factor_valid,
  add constraint health_summaries_stride_factor_valid check (
    stride_factor is null or (stride_factor > 0 and stride_factor < 1)
  ),
  drop constraint if exists health_summaries_task_provenance_required,
  add constraint health_summaries_task_provenance_required check (
    task_occurrence_id is null
    or (
      execution_session_id is not null
      and interval_start_at is not null
      and interval_end_at is not null
      and allocation_method in ('exact_record', 'proportional_overlap')
      and provenance in (
        'health_connect_record_overlap',
        'steps_height_stride_estimate'
      )
    )
  ),
  drop constraint if exists health_summaries_task_metric_evidence_valid,
  add constraint health_summaries_task_metric_evidence_valid check (
    task_occurrence_id is null
    or (
      summary_type in (
        'steps',
        'distance',
        'active_calories',
        'average_heart_rate'
      )
      and value is not null
      and record_count > 0
      and jsonb_array_length(source_applications) > 0
      and last_updated_at is not null
    )
  );

drop index if exists public.health_summaries_user_day_metric_live_idx;

create unique index health_summaries_user_day_metric_live_idx
  on public.health_summaries (user_id, summary_date, summary_type)
  where deleted_at is null and task_occurrence_id is null;

create unique index health_summaries_user_task_session_metric_live_idx
  on public.health_summaries (
    user_id,
    task_occurrence_id,
    execution_session_id,
    summary_type
  )
  where deleted_at is null and task_occurrence_id is not null;

create index health_summaries_task_interval_idx
  on public.health_summaries (
    user_id,
    task_occurrence_id,
    interval_start_at,
    interval_end_at
  )
  where deleted_at is null and task_occurrence_id is not null;

-- Two phones can import the same daily or task interval while offline and
-- therefore legitimately submit different row UUIDs for one semantic
-- summary. Serialize that key and keep the summary with the newest source
-- update. This makes both idempotent creates succeed without double-counting
-- or leaving a permanently retrying unique-index violation.
create or replace function taskmaster_internal.resolve_health_summary_duplicate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  semantic_key text;
  existing_id uuid;
  existing_source_updated_at timestamptz;
  existing_updated_at timestamptz;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  semantic_key := case
    when new.task_occurrence_id is null then
      new.user_id::text || ':daily:' || new.summary_date::text || ':' ||
      new.summary_type
    else
      new.user_id::text || ':task:' || new.task_occurrence_id::text || ':' ||
      new.execution_session_id::text || ':' || new.summary_type
  end;

  perform pg_advisory_xact_lock(hashtextextended(semantic_key, 0));

  select id, last_updated_at, updated_at
  into existing_id, existing_source_updated_at, existing_updated_at
  from public.health_summaries
  where user_id = new.user_id
    and id <> new.id
    and deleted_at is null
    and summary_type = new.summary_type
    and (
      (
        new.task_occurrence_id is null
        and task_occurrence_id is null
        and summary_date = new.summary_date
      )
      or (
        new.task_occurrence_id is not null
        and task_occurrence_id = new.task_occurrence_id
        and execution_session_id = new.execution_session_id
      )
    )
  order by
    coalesce(last_updated_at, updated_at) desc,
    revision desc,
    id desc
  limit 1
  for update;

  if existing_id is null then
    return new;
  end if;

  if coalesce(existing_source_updated_at, existing_updated_at) >
     coalesce(new.last_updated_at, new.updated_at, statement_timestamp())
  then
    new.deleted_at := statement_timestamp();
  else
    update public.health_summaries
    set
      deleted_at = statement_timestamp(),
      revision = revision + 1,
      updated_at = statement_timestamp(),
      updated_by_device_id = new.updated_by_device_id,
      last_command_id = new.last_command_id
    where user_id = new.user_id and id = existing_id;
  end if;

  return new;
end;
$$;

revoke all on function
  taskmaster_internal.resolve_health_summary_duplicate()
from public, anon, authenticated;

drop trigger if exists resolve_health_summary_duplicate
  on public.health_summaries;
create trigger resolve_health_summary_duplicate
before insert or update on public.health_summaries
for each row execute function
  taskmaster_internal.resolve_health_summary_duplicate();

comment on column public.health_summaries.task_occurrence_id is
  'Optional task context. Null denotes a daily aggregate.';
comment on column public.health_summaries.estimated is
  'True when overlap allocation or height-based stride estimation was used.';
