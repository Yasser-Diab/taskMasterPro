-- v0.0.26 correction: raw polling samples remain on the source device, but
-- durable normalized Activity segments, review state, classifications, rules,
-- and aggregates are shared account data.

comment on table public.activity_segments is
  'Privacy-controlled normalized Activity segments. High-frequency polling samples remain device-local; clients upsert one stable segment while it is active.';

comment on table public.activity_attributions is
  'Synchronized user and rule-based classifications for normalized Activity segments.';

comment on table public.activity_review_queue is
  'Synchronized review state for normalized Activity segments. It contains no raw polling stream.';

comment on table public.activity_contributions is
  'Synchronized task and roadmap contribution summaries derived from normalized Activity segments.';

create index if not exists activity_segments_device_event_idx
  on public.activity_segments (user_id, device_id, device_event_id, updated_at desc);
