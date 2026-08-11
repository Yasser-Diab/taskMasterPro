-- Keep the aggregate small and privacy-safe while retaining enough evidence
-- to prove which Health Connect application produced it and when it changed.
alter table public.health_summaries
  add column if not exists source_applications jsonb not null default '[]'::jsonb,
  add column if not exists source_record_counts jsonb not null default '{}'::jsonb,
  add column if not exists last_updated_at timestamptz,
  add column if not exists window_start_at timestamptz,
  add column if not exists window_end_at timestamptz,
  add column if not exists raw_record_count integer not null default 0,
  add column if not exists discarded_overlap_count integer not null default 0;

update public.health_summaries
set
  source_applications = case
    when source is null or btrim(source) = '' then '[]'::jsonb
    else jsonb_build_array(source)
  end,
  source_record_counts = case
    when source is null or btrim(source) = '' then '{}'::jsonb
    else jsonb_build_object(source, greatest(record_count, 0))
  end,
  last_updated_at = coalesce(last_updated_at, updated_at),
  raw_record_count = greatest(raw_record_count, record_count, 0)
where
  source_applications = '[]'::jsonb
  or source_record_counts = '{}'::jsonb
  or last_updated_at is null
  or raw_record_count < record_count;

alter table public.health_summaries
  drop constraint if exists health_summaries_source_applications_array,
  add constraint health_summaries_source_applications_array
    check (jsonb_typeof(source_applications) = 'array'),
  drop constraint if exists health_summaries_source_record_counts_object,
  add constraint health_summaries_source_record_counts_object
    check (jsonb_typeof(source_record_counts) = 'object'),
  drop constraint if exists health_summaries_record_counts_valid,
  add constraint health_summaries_record_counts_valid check (
    record_count >= 0
    and raw_record_count >= record_count
    and discarded_overlap_count >= 0
    and discarded_overlap_count <= raw_record_count
  ),
  drop constraint if exists health_summaries_window_valid,
  add constraint health_summaries_window_valid check (
    window_start_at is null
    or window_end_at is null
    or window_start_at <= window_end_at
  );

-- Older clients could create more than one live row for a metric/day. Keep the
-- newest canonical revision and turn the rest into synchronized tombstones
-- before adding the invariant.
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, summary_date, summary_type
      order by revision desc, updated_at desc, id desc
    ) as duplicate_rank
  from public.health_summaries
  where deleted_at is null
)
update public.health_summaries as summary
set
  deleted_at = coalesce(summary.deleted_at, now()),
  revision = summary.revision + 1,
  updated_at = now()
from ranked
where summary.id = ranked.id
  and ranked.duplicate_rank > 1;

create unique index if not exists health_summaries_user_day_metric_live_idx
  on public.health_summaries (user_id, summary_date, summary_type)
  where deleted_at is null;
