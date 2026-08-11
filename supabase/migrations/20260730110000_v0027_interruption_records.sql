begin;

alter table public.interruptions
  alter column session_id drop not null,
  add column if not exists duration_ms bigint not null default 0,
  add column if not exists necessity text not null default 'necessary',
  add column if not exists counts_toward_current_task boolean not null default false,
  add column if not exists related_responsibility text,
  add column if not exists activity_segment_id uuid;

alter table public.interruptions
  drop constraint if exists interruptions_duration_nonnegative,
  add constraint interruptions_duration_nonnegative
    check (duration_ms >= 0),
  drop constraint if exists interruptions_necessity_valid,
  add constraint interruptions_necessity_valid
    check (necessity in ('necessary', 'avoidable'));

create index if not exists interruptions_user_task_started_idx
  on public.interruptions (user_id, task_occurrence_id, started_at desc)
  where deleted_at is null;

create index if not exists interruptions_user_activity_idx
  on public.interruptions (user_id, activity_segment_id)
  where activity_segment_id is not null and deleted_at is null;

commit;
