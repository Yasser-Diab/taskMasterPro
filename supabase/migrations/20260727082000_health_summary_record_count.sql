-- Health summaries keep a small record-count proof alongside their metric.
-- The Android client already syncs this privacy-safe aggregate; without the
-- column the generic command endpoint rejected valid summaries and left
-- devices permanently reporting pending sync work.
alter table public.health_summaries
  add column if not exists record_count integer not null default 0;
