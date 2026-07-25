-- TaskMaster Pro clean baseline
-- PostgreSQL 17 / Supabase
--
-- Design invariants:
--   * User actions are applied locally first.
--   * Every synchronized row is revisioned and tombstoned.
--   * Commands are idempotent per account and device.
--   * Activity segments are the one physical timeline.
--   * Attributions and contributions never create additional physical time.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
create schema if not exists analytics;

revoke all on schema private from public, anon, authenticated;
revoke all on schema analytics from public, anon;
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema analytics to authenticated, service_role;

create type public.app_theme as enum ('light', 'dark', 'golden', 'system');
create type public.sync_command_status as enum (
  'pending',
  'sending',
  'accepted',
  'conflict',
  'failed',
  'cancelled'
);
create type public.task_status as enum (
  'ready',
  'scheduled',
  'in_progress',
  'paused',
  'completed',
  'overdue',
  'postponed',
  'waiting_review',
  'skipped',
  'cancelled',
  'archived'
);
create type public.execution_mode as enum (
  'pomodoro',
  'continuous',
  'checklist',
  'reading',
  'habit',
  'event',
  'manual',
  'hybrid'
);
create type public.session_state as enum (
  'idle',
  'running',
  'paused',
  'break',
  'completed',
  'cancelled'
);
create type public.attribution_status as enum (
  'proposed',
  'automatic',
  'confirmed',
  'rejected',
  'ignored',
  'needs_review',
  'superseded'
);

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  email text,
  display_name text not null default '',
  username text,
  profile_image_path text,
  onboarding_completed_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb
);

create unique index profiles_username_unique
  on public.profiles (lower(username))
  where username is not null and deleted_at is null;

create table public.user_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  preferred_language text not null default 'en'
    check (preferred_language in ('en', 'ar', 'de')),
  time_zone text not null default 'UTC',
  clock_format text not null default '24h'
    check (clock_format in ('12h', '24h')),
  theme public.app_theme not null default 'system',
  accent_color bigint not null default 4280391411,
  week_starts_on integer not null default 1 check (week_starts_on between 1 and 7),
  notification_sound text not null default 'system',
  workday_settings jsonb not null default '{}'::jsonb,
  sleep_preferences jsonb not null default '{}'::jsonb,
  notification_preferences jsonb not null default '{}'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb
);

create table public.coaching_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  mode text not null default 'standard'
    check (mode in ('quiet', 'standard', 'active', 'persistent', 'custom')),
  enabled_events jsonb not null default '[]'::jsonb,
  feedback_frequency text not null default 'balanced',
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb
);

create table public.privacy_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  application_tracking text not null default 'disabled',
  website_tracking text not null default 'disabled',
  document_tracking boolean not null default false,
  idle_tracking boolean not null default true,
  activity_storage text not null default 'local_only'
    check (activity_storage in ('disabled', 'local_only', 'synchronized')),
  health_coaching_enabled boolean not null default false,
  cycle_sync_enabled boolean not null default false,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb
);

create table public.account_devices (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_name text not null,
  platform text not null check (platform in ('windows', 'android', 'unknown')),
  app_version text,
  device_public_key text,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, id)
);

create table public.device_sync_state (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  last_device_sequence bigint not null default 0,
  last_server_sequence bigint not null default 0,
  last_synced_at timestamptz,
  last_error text,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, device_id),
  foreign key (user_id, device_id)
    references public.account_devices (user_id, id) on delete cascade
);

create table public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  token_ciphertext text not null,
  provider text not null,
  expires_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, device_id, provider)
);

create table public.task_domains (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon_name text not null default 'folder',
  color_value integer not null,
  position numeric(20, 10) not null default 0,
  archived_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, id)
);

create index task_domains_user_position_idx
  on public.task_domains (user_id, position)
  where deleted_at is null;

create table public.task_templates (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  domain_id uuid,
  category_id uuid,
  priority integer not null default 2 check (priority between 0 and 4),
  execution_mode public.execution_mode not null default 'manual',
  default_duration_ms bigint not null default 0 check (default_duration_ms >= 0),
  minimum_duration_ms bigint,
  maximum_duration_ms bigint,
  recurrence_rule_id uuid,
  roadmap_id uuid,
  roadmap_phase_id uuid,
  reminder_defaults jsonb not null default '[]'::jsonb,
  execution_settings jsonb not null default '{}'::jsonb,
  progress_settings jsonb not null default '{}'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, domain_id)
    references public.task_domains (user_id, id)
);

create index task_templates_user_domain_idx
  on public.task_templates (user_id, domain_id)
  where deleted_at is null;

create table public.task_occurrences (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id uuid,
  title text not null,
  description text not null default '',
  domain_id uuid,
  category_id uuid,
  status public.task_status not null default 'ready',
  priority integer not null default 2 check (priority between 0 and 4),
  execution_mode public.execution_mode not null default 'manual',
  scheduled_date date,
  planned_start timestamptz,
  planned_end timestamptz,
  due_at timestamptz,
  estimated_duration_ms bigint not null default 0 check (estimated_duration_ms >= 0),
  actual_start timestamptz,
  actual_finish timestamptz,
  active_duration_ms bigint not null default 0 check (active_duration_ms >= 0),
  paused_duration_ms bigint not null default 0 check (paused_duration_ms >= 0),
  idle_duration_ms bigint not null default 0 check (idle_duration_ms >= 0),
  progress numeric(7, 4) not null default 0 check (progress between 0 and 1),
  roadmap_id uuid,
  roadmap_phase_id uuid,
  parent_task_id uuid,
  occurrence_key text,
  postponed_from timestamptz,
  completion_evidence_required boolean not null default false,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (template_id) references public.task_templates (id),
  foreign key (user_id, domain_id)
    references public.task_domains (user_id, id),
  foreign key (parent_task_id) references public.task_occurrences (id),
  unique (user_id, id),
  unique (user_id, template_id, occurrence_key)
);

create index task_occurrences_today_idx
  on public.task_occurrences (user_id, scheduled_date, status, planned_start)
  where deleted_at is null;
create index task_occurrences_due_idx
  on public.task_occurrences (user_id, due_at)
  where deleted_at is null and status not in ('completed', 'cancelled', 'archived');

create table public.execution_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  task_occurrence_id uuid,
  mode public.execution_mode not null,
  state public.session_state not null default 'idle',
  started_at timestamptz,
  finished_at timestamptz,
  active_segment_started_at timestamptz,
  accumulated_active_ms bigint not null default 0 check (accumulated_active_ms >= 0),
  accumulated_paused_ms bigint not null default 0 check (accumulated_paused_ms >= 0),
  accumulated_idle_ms bigint not null default 0 check (accumulated_idle_ms >= 0),
  current_pomodoro_segment text,
  current_cycle integer not null default 0,
  is_unscheduled boolean not null default false,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (task_occurrence_id) references public.task_occurrences (id),
  unique (user_id, id)
);

create table public.session_events (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  event_type text not null,
  occurred_at timestamptz not null,
  duration_ms bigint,
  source_device_id uuid,
  event_payload jsonb not null default '{}'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (session_id) references public.execution_sessions (id),
  unique (user_id, id)
);

create index session_events_session_time_idx
  on public.session_events (user_id, session_id, occurred_at);

create table public.user_runtime_state (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  active_session_id uuid,
  active_task_occurrence_id uuid,
  state public.session_state not null default 'idle',
  active_segment_started_at timestamptz,
  accumulated_active_ms bigint not null default 0,
  accumulated_paused_ms bigint not null default 0,
  lease_device_id uuid,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (active_session_id) references public.execution_sessions (id),
  foreign key (active_task_occurrence_id) references public.task_occurrences (id)
);

create table public.checklist_items (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  task_template_id uuid,
  task_occurrence_id uuid,
  title text not null,
  description text not null default '',
  is_required boolean not null default true,
  is_completed boolean not null default false,
  completed_at timestamptz,
  due_at timestamptz,
  weight numeric(12, 4) not null default 1,
  position numeric(20, 10) not null default 0,
  evidence jsonb not null default '[]'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (task_template_id) references public.task_templates (id),
  foreign key (task_occurrence_id) references public.task_occurrences (id),
  check (task_template_id is not null or task_occurrence_id is not null)
);

create table public.roadmaps (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  status text not null default 'active',
  planned_start date,
  original_target_date date,
  forecast_target_date date,
  final_outcome text,
  progress numeric(7, 4) not null default 0 check (progress between 0 and 1),
  required_effort_ms bigint,
  completed_effort_ms bigint not null default 0,
  risk_level text not null default 'low',
  forecast_confidence text,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, id)
);

create table public.roadmap_phases (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  roadmap_id uuid not null,
  title text not null,
  description text not null default '',
  position numeric(20, 10) not null,
  planned_start date,
  planned_finish date,
  forecast_finish date,
  required_effort_ms bigint,
  progress numeric(7, 4) not null default 0 check (progress between 0 and 1),
  status text not null default 'planned',
  risk_level text not null default 'low',
  completion_rules jsonb not null default '[]'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, roadmap_id)
    references public.roadmaps (user_id, id),
  unique (user_id, id)
);

create index roadmap_phases_order_idx
  on public.roadmap_phases (user_id, roadmap_id, position)
  where deleted_at is null;

create table public.roadmap_milestones (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  roadmap_id uuid not null,
  phase_id uuid,
  title text not null,
  description text not null default '',
  target_date date,
  completed_at timestamptz,
  position numeric(20, 10) not null default 0,
  weight numeric(12, 4) not null default 1,
  status text not null default 'planned',
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, roadmap_id)
    references public.roadmaps (user_id, id),
  foreign key (user_id, phase_id)
    references public.roadmap_phases (user_id, id)
);

create table public.roadmap_checkpoints (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  roadmap_id uuid not null,
  phase_id uuid,
  title text not null,
  objective text,
  target_date date,
  estimated_effort_ms bigint,
  actual_effort_ms bigint not null default 0,
  completion_criteria jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '[]'::jsonb,
  status text not null default 'planned',
  weight numeric(12, 4) not null default 1,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, roadmap_id)
    references public.roadmaps (user_id, id),
  foreign key (user_id, phase_id)
    references public.roadmap_phases (user_id, id)
);

create table public.activity_segments (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid not null,
  device_event_id text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_ms bigint generated always as (
    greatest(0, (extract(epoch from (ended_at - started_at)) * 1000)::bigint)
  ) stored,
  source_type text not null,
  application_id uuid,
  website_rule_id uuid,
  resource_id uuid,
  process_name text,
  window_title text,
  domain text,
  url text,
  page_title text,
  input_state text,
  idle_state text,
  screen_state text,
  capture_confidence numeric(5, 4)
    check (capture_confidence is null or capture_confidence between 0 and 1),
  raw_metadata jsonb not null default '{}'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  check (ended_at >= started_at),
  unique (user_id, device_id, device_event_id),
  unique (user_id, id)
);

create index activity_segments_timeline_idx
  on public.activity_segments (user_id, started_at, ended_at)
  where deleted_at is null;
create index activity_segments_review_idx
  on public.activity_segments (user_id, source_type, started_at)
  where deleted_at is null;

create table public.activity_attributions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_segment_id uuid not null,
  target_type text not null,
  target_id uuid,
  classification text not null,
  confidence numeric(5, 4) not null check (confidence between 0 and 1),
  attribution_status public.attribution_status not null default 'proposed',
  rule_id uuid,
  suggested_by text not null default 'deterministic',
  confirmed_by_user boolean not null default false,
  supersedes_attribution_id uuid,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, activity_segment_id)
    references public.activity_segments (user_id, id),
  foreign key (supersedes_attribution_id)
    references public.activity_attributions (id),
  unique (user_id, id)
);

create index activity_attributions_review_idx
  on public.activity_attributions (user_id, attribution_status, confidence)
  where deleted_at is null;

create table public.activity_contributions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_segment_id uuid not null,
  activity_attribution_id uuid not null,
  target_type text not null,
  target_id uuid,
  contribution_type text not null,
  physical_duration_ms bigint not null check (physical_duration_ms >= 0),
  credited_duration_ms bigint not null check (
    credited_duration_ms >= 0 and credited_duration_ms <= physical_duration_ms
  ),
  progress_value numeric(20, 6),
  source_task_id uuid,
  source_session_id uuid,
  source_break_id uuid,
  is_unscheduled boolean not null default false,
  is_cross_task boolean not null default false,
  is_idle_derived boolean not null default false,
  is_automatic boolean not null default false,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, activity_segment_id)
    references public.activity_segments (user_id, id),
  foreign key (user_id, activity_attribution_id)
    references public.activity_attributions (user_id, id),
  unique (
    user_id,
    activity_segment_id,
    target_type,
    target_id,
    contribution_type
  ),
  unique (user_id, activity_attribution_id, target_type, target_id, contribution_type)
);

create index activity_contributions_target_idx
  on public.activity_contributions (user_id, target_type, target_id, created_at)
  where deleted_at is null;

create table public.contribution_roadmap_effects (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  contribution_id uuid not null,
  roadmap_id uuid not null,
  roadmap_phase_id uuid,
  checkpoint_id uuid,
  effect_type text not null,
  effect_value numeric(20, 6) not null,
  progress_before numeric(7, 4),
  progress_after numeric(7, 4),
  forecast_before date,
  forecast_after date,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (contribution_id) references public.activity_contributions (id),
  foreign key (user_id, roadmap_id)
    references public.roadmaps (user_id, id),
  unique (user_id, contribution_id, roadmap_id, roadmap_phase_id, checkpoint_id, effect_type)
);

create table public.activity_review_queue (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_segment_id uuid not null,
  review_reason text not null,
  priority integer not null default 2 check (priority between 0 and 4),
  suggested_targets jsonb not null default '[]'::jsonb,
  suggested_classification text,
  confidence numeric(5, 4) check (confidence is null or confidence between 0 and 1),
  status text not null default 'pending',
  reviewed_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  foreign key (user_id, activity_segment_id)
    references public.activity_segments (user_id, id),
  unique (user_id, activity_segment_id, review_reason)
);

create table public.processed_commands (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  command_id uuid not null,
  device_id uuid not null,
  device_sequence bigint not null,
  entity_type text not null,
  entity_id uuid,
  command_type text not null,
  base_revision bigint,
  status public.sync_command_status not null,
  result jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default now(),
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, command_id),
  unique (user_id, device_id, device_sequence)
);

create table public.sync_change_log (
  id uuid primary key default gen_random_uuid(),
  change_sequence bigint generated always as identity unique,
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  operation text not null,
  entity_revision bigint not null,
  changed_fields jsonb not null default '{}'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb
);

create index sync_change_log_pull_idx
  on public.sync_change_log (user_id, change_sequence);

create table public.sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  command_id uuid,
  entity_type text not null,
  entity_id uuid not null,
  conflict_type text not null,
  base_revision bigint,
  server_revision bigint,
  local_payload jsonb not null default '{}'::jsonb,
  server_payload jsonb not null default '{}'::jsonb,
  resolution_status text not null default 'unresolved',
  resolution jsonb,
  resolved_at timestamptz,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  unique (user_id, command_id, entity_id)
);

-- Lower-priority feature tables still receive the complete synchronized envelope.
-- Their feature-specific structures can evolve without replacing the sync model.
create or replace function private.create_synced_table(
  p_table_name text,
  p_feature_columns text default ''
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  execute format(
    'create table public.%I (
       id uuid primary key,
       user_id uuid not null references auth.users(id) on delete cascade,
       %s
       revision bigint not null default 1 check (revision > 0),
       created_at timestamptz not null default now(),
       updated_at timestamptz not null default now(),
       created_by_device_id uuid,
       updated_by_device_id uuid,
       last_command_id uuid,
       deleted_at timestamptz,
       data jsonb not null default ''{}''::jsonb,
       unique (user_id, id)
     )',
    p_table_name,
    case
      when coalesce(trim(p_feature_columns), '') = '' then ''
      else p_feature_columns || ','
    end
  );
end;
$$;

select private.create_synced_table('task_categories',
  'domain_id uuid, name text not null, icon_name text, color_value integer, position numeric(20,10) not null default 0');
select private.create_synced_table('tags',
  'name text not null, color_value integer');
select private.create_synced_table('recurrence_rules',
  'frequency text not null, interval_value integer not null default 1, weekdays integer[], starts_on date not null, ends_on date, maximum_occurrences integer, paused_at timestamptz, rule_data jsonb not null default ''{}''::jsonb');
select private.create_synced_table('recurrence_exceptions',
  'recurrence_rule_id uuid not null, excluded_date date, replacement_date date, exception_type text not null');
select private.create_synced_table('task_dependencies',
  'task_occurrence_id uuid not null, depends_on_task_id uuid not null, dependency_type text not null default ''blocks''');
select private.create_synced_table('task_reminders',
  'task_template_id uuid, task_occurrence_id uuid, reminder_type text not null, scheduled_at timestamptz, offset_ms bigint, repeat_rule jsonb not null default ''{}''::jsonb, sound_key text not null default ''system'', enabled boolean not null default true');
select private.create_synced_table('pomodoro_cycles',
  'session_id uuid not null, cycle_number integer not null, focus_started_at timestamptz, focus_ended_at timestamptz, break_started_at timestamptz, break_ended_at timestamptz, focus_duration_ms bigint not null default 0, break_duration_ms bigint not null default 0, skipped_break boolean not null default false');
select private.create_synced_table('interruptions',
  'session_id uuid not null, task_occurrence_id uuid, started_at timestamptz not null, ended_at timestamptz, interruption_type text not null, target_task_id uuid, notes text');
select private.create_synced_table('task_completion_evidence',
  'task_occurrence_id uuid not null, evidence_type text not null, resource_id uuid, note text, evidence_metadata jsonb not null default ''{}''::jsonb');
select private.create_synced_table('work_demands',
  'task_template_id uuid, task_occurrence_id uuid, title text not null, description text, priority integer not null default 2, status text not null default ''pending'', original_due_at timestamptz, scheduled_at timestamptz, completed_at timestamptz, weight numeric(12,4) not null default 1, rollover_history jsonb not null default ''[]''::jsonb, evidence jsonb not null default ''[]''::jsonb');
select private.create_synced_table('learning_checkpoints',
  'task_template_id uuid, task_occurrence_id uuid, roadmap_checkpoint_id uuid, topic text not null, objective text, target_date date, estimated_effort_ms bigint, actual_effort_ms bigint not null default 0, completion_criteria jsonb not null default ''[]''::jsonb, evidence jsonb not null default ''[]''::jsonb, status text not null default ''planned''');
select private.create_synced_table('reading_targets',
  'task_occurrence_id uuid, resource_id uuid, title text not null, author text, total_pages integer, start_page integer, target_end_page integer, target_date date, count_rereads boolean not null default false');
select private.create_synced_table('reading_positions',
  'reading_target_id uuid not null, resource_id uuid, page_number integer, position_value text, unique_pages integer[] not null default ''{}''::integer[], reread_pages integer[] not null default ''{}''::integer[], reading_duration_ms bigint not null default 0, recorded_at timestamptz not null');
select private.create_synced_table('habit_records',
  'task_template_id uuid, task_occurrence_id uuid, record_date date not null, status text not null, completed_at timestamptz, skip_reason text, recovery_note text');
select private.create_synced_table('event_attendance',
  'task_occurrence_id uuid not null, planned_arrival timestamptz, actual_arrival timestamptz, planned_start timestamptz, actual_start timestamptz, planned_finish timestamptz, actual_finish timestamptz, attendance_status text, follow_up jsonb not null default ''[]''::jsonb');
select private.create_synced_table('task_notes',
  'task_occurrence_id uuid, task_template_id uuid, session_id uuid, body text not null, note_version integer not null default 1, conflicting_copy_of uuid');
select private.create_synced_table('roadmap_progress_rules',
  'roadmap_id uuid not null, roadmap_phase_id uuid, contribution_type text not null, weight numeric(12,4) not null default 1, automatic_credit_allowed boolean not null default false, rule_config jsonb not null default ''{}''::jsonb');
select private.create_synced_table('roadmap_evidence',
  'roadmap_id uuid not null, roadmap_phase_id uuid, milestone_id uuid, checkpoint_id uuid, evidence_type text not null, resource_id uuid, note text');
select private.create_synced_table('roadmap_forecasts',
  'roadmap_id uuid not null, roadmap_phase_id uuid, calculated_at timestamptz not null, original_target date, forecast_target date, remaining_effort_ms bigint, weekly_capacity_ms bigint, required_weekly_effort_ms bigint, risk_level text, confidence text, evidence_count integer not null default 0, reasons jsonb not null default ''[]''::jsonb, recovery_options jsonb not null default ''[]''::jsonb');
select private.create_synced_table('application_catalog',
  'platform text not null, application_identifier text not null, display_name text, publisher text, icon_path text, classification text not null default ''unknown'', first_seen_at timestamptz, last_seen_at timestamptz');
select private.create_synced_table('application_rules',
  'application_id uuid not null, scope_type text not null, scope_id uuid, classification text not null, target_type text, target_id uuid, contribution_type text, automatic_credit boolean not null default false, priority integer not null default 0');
select private.create_synced_table('website_rules',
  'domain text not null, url_pattern text, scope_type text not null, scope_id uuid, classification text not null, target_type text, target_id uuid, contribution_type text, automatic_credit boolean not null default false, priority integer not null default 0');
select private.create_synced_table('classification_feedback',
  'activity_segment_id uuid, application_id uuid, domain text, suggested_classification text, chosen_classification text not null, suggested_target_type text, suggested_target_id uuid, chosen_target_type text, chosen_target_id uuid, feedback_type text not null');
select private.create_synced_table('task_resources',
  'task_occurrence_id uuid, task_template_id uuid, roadmap_id uuid, name text not null, resource_type text not null, description text, storage_location text, storage_path text, local_path text, privacy_state text not null default ''private'', last_opened_at timestamptz, open_count integer not null default 0');
select private.create_synced_table('resource_activity',
  'resource_id uuid not null, task_occurrence_id uuid, session_id uuid, started_at timestamptz not null, ended_at timestamptz, active_duration_ms bigint not null default 0, position_before text, position_after text');
select private.create_synced_table('browser_workspaces',
  'task_occurrence_id uuid, task_template_id uuid, title text, persistence_mode text not null default ''keep_pinned'', selected_tab_id uuid, search_engine text not null default ''system''');
select private.create_synced_table('browser_tabs',
  'workspace_id uuid not null, url text not null, title text, custom_title text, position numeric(20,10) not null default 0, is_pinned boolean not null default false, is_selected boolean not null default false, last_visited_at timestamptz');
select private.create_synced_table('browser_bookmarks',
  'workspace_id uuid, task_occurrence_id uuid, url text not null, title text, position numeric(20,10) not null default 0');
select private.create_synced_table('browser_history_events',
  'workspace_id uuid, tab_id uuid, url text not null, title text, visited_at timestamptz not null, duration_ms bigint not null default 0, device_event_id text not null');
select private.create_synced_table('browser_closed_tabs',
  'workspace_id uuid not null, url text not null, title text, was_pinned boolean not null default false, previous_position numeric(20,10), closed_at timestamptz not null');
select private.create_synced_table('document_positions',
  'resource_id uuid not null, page_number integer, position_value text, name text, is_bookmark boolean not null default false, note text, recorded_at timestamptz not null');
select private.create_synced_table('coaching_insights',
  'insight_type text not null, observation text not null, reason text, evidence_count integer not null default 0, confidence text not null, suggested_action jsonb, expected_benefit text, state text not null default ''active'', generated_at timestamptz not null');
select private.create_synced_table('coaching_feedback',
  'insight_id uuid not null, feedback text not null, note text, submitted_at timestamptz not null');
select private.create_synced_table('daily_metrics',
  'metric_date date not null, time_zone text not null, planned_ms bigint not null default 0, active_ms bigint not null default 0, idle_ms bigint not null default 0, paused_ms bigint not null default 0, focus_ms bigint not null default 0, break_ms bigint not null default 0, productive_ms bigint not null default 0, distraction_ms bigint not null default 0, completed_count integer not null default 0, overdue_count integer not null default 0, calculated_at timestamptz not null');
select private.create_synced_table('weekly_metrics',
  'week_start date not null, time_zone text not null, metrics jsonb not null default ''{}''::jsonb, calculated_at timestamptz not null');
select private.create_synced_table('monthly_metrics',
  'month_start date not null, time_zone text not null, metrics jsonb not null default ''{}''::jsonb, calculated_at timestamptz not null');
select private.create_synced_table('task_performance_profiles',
  'task_template_id uuid, domain_id uuid, execution_mode text, sample_count integer not null default 0, average_start_delay_ms bigint, average_duration_ms bigint, duration_variance numeric, effective_ratio numeric(7,4), calculated_at timestamptz not null');
select private.create_synced_table('notification_decisions',
  'task_occurrence_id uuid, reminder_id uuid, decision_type text not null, scheduled_at timestamptz, delivered_at timestamptz, responded_at timestamptz, action text, evidence jsonb not null default ''{}''::jsonb');
select private.create_synced_table('user_vaults',
  'kdf_name text not null, kdf_parameters jsonb not null, encrypted_verifier text not null, vault_version integer not null default 1, locked_at timestamptz');
select private.create_synced_table('vault_items',
  'vault_id uuid not null, ciphertext text not null, nonce text not null, encrypted_metadata text, item_revision bigint not null default 1, conflicting_copy_of uuid');
select private.create_synced_table('vault_device_keys',
  'vault_id uuid not null, device_id uuid not null, wrapped_key text not null, wrapping_algorithm text not null, authorized_at timestamptz not null, revoked_at timestamptz');
select private.create_synced_table('health_permissions',
  'device_id uuid not null, data_type text not null, permission_state text not null, selected_sources jsonb not null default ''[]''::jsonb, granted_at timestamptz, withdrawn_at timestamptz');
select private.create_synced_table('health_summaries',
  'summary_date date not null, source text not null, summary_type text not null, value numeric, unit text, encrypted_details text');
select private.create_synced_table('cycle_records',
  'storage_mode text not null default ''local_only'', record_date date not null, ciphertext text, nonce text, local_reference text');
select private.create_synced_table('notification_jobs',
  'task_occurrence_id uuid, reminder_id uuid, scheduled_at timestamptz not null, status text not null default ''pending'', attempts integer not null default 0, payload jsonb not null default ''{}''::jsonb');
select private.create_synced_table('processing_queue',
  'job_type text not null, entity_type text, entity_id uuid, status text not null default ''pending'', priority integer not null default 2, attempts integer not null default 0, available_at timestamptz not null default now(), payload jsonb not null default ''{}''::jsonb');
select private.create_synced_table('security_audit_events',
  'event_type text not null, device_id uuid, occurred_at timestamptz not null, ip_hash text, user_agent_hash text, event_data jsonb not null default ''{}''::jsonb');

drop function private.create_synced_table(text, text);

-- Useful constraints and indexes on generated feature tables.
create unique index task_categories_name_idx
  on public.task_categories (user_id, domain_id, lower(name))
  where deleted_at is null;
create unique index tags_name_idx
  on public.tags (user_id, lower(name))
  where deleted_at is null;
create unique index application_catalog_identifier_idx
  on public.application_catalog (user_id, platform, application_identifier)
  where deleted_at is null;
create index activity_review_status_idx
  on public.activity_review_queue (user_id, status, priority, created_at)
  where deleted_at is null;
create index browser_history_recent_idx
  on public.browser_history_events (user_id, visited_at desc)
  where deleted_at is null;
create unique index daily_metrics_date_idx
  on public.daily_metrics (user_id, metric_date, time_zone)
  where deleted_at is null;

-- Cover relationship lookups and foreign-key maintenance paths.
create index activity_attributions_segment_fk_idx
  on public.activity_attributions (user_id, activity_segment_id);
create index activity_attributions_supersedes_fk_idx
  on public.activity_attributions (supersedes_attribution_id);
create index checklist_items_occurrence_fk_idx
  on public.checklist_items (task_occurrence_id);
create index checklist_items_template_fk_idx
  on public.checklist_items (task_template_id);
create index checklist_items_user_idx
  on public.checklist_items (user_id);
create index contribution_roadmap_effects_contribution_fk_idx
  on public.contribution_roadmap_effects (contribution_id);
create index contribution_roadmap_effects_roadmap_fk_idx
  on public.contribution_roadmap_effects (user_id, roadmap_id);
create index execution_sessions_occurrence_fk_idx
  on public.execution_sessions (task_occurrence_id);
create index roadmap_checkpoints_roadmap_fk_idx
  on public.roadmap_checkpoints (user_id, roadmap_id);
create index roadmap_checkpoints_phase_fk_idx
  on public.roadmap_checkpoints (user_id, phase_id);
create index roadmap_milestones_roadmap_fk_idx
  on public.roadmap_milestones (user_id, roadmap_id);
create index roadmap_milestones_phase_fk_idx
  on public.roadmap_milestones (user_id, phase_id);
create index session_events_session_fk_idx
  on public.session_events (session_id);
create index task_occurrences_template_fk_idx
  on public.task_occurrences (template_id);
create index task_occurrences_parent_fk_idx
  on public.task_occurrences (parent_task_id);
create index task_occurrences_domain_fk_idx
  on public.task_occurrences (user_id, domain_id);
create index user_runtime_state_session_fk_idx
  on public.user_runtime_state (active_session_id);
create index user_runtime_state_task_fk_idx
  on public.user_runtime_state (active_task_occurrence_id);

-- NULL logical targets still participate in duplicate-prevention.
create unique index activity_contributions_semantic_unique_idx
  on public.activity_contributions (
    user_id,
    activity_segment_id,
    target_type,
    coalesce(target_id, '00000000-0000-0000-0000-000000000000'::uuid),
    contribution_type
  )
  where deleted_at is null;

-- Server timestamps and authoritative revisions for every synchronized table.
create or replace function private.prepare_synchronized_record()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := statement_timestamp();
  if tg_op = 'UPDATE' then
    new.revision := old.revision + 1;
  elsif new.revision is null or new.revision < 1 then
    new.revision := 1;
  end if;
  return new;
end;
$$;

do $$
declare
  table_record record;
begin
  for table_record in
    select table_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'revision'
  loop
    execute format(
      'create trigger %I before insert or update on public.%I
       for each row execute function private.prepare_synchronized_record()',
      'prepare_' || table_record.table_name,
      table_record.table_name
    );
  end loop;
end;
$$;

-- Durable account change log. It records compact envelopes, not complete rows.
create or replace function private.log_synchronized_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid;
  entity_id uuid;
  entity_revision bigint;
  command_id uuid;
  device_id uuid;
begin
  owner_id := coalesce(new.user_id, old.user_id);
  entity_id := coalesce(new.id, old.id);
  entity_revision := coalesce(new.revision, old.revision);
  command_id := coalesce(new.last_command_id, old.last_command_id);
  device_id := coalesce(new.updated_by_device_id, new.created_by_device_id,
                        old.updated_by_device_id, old.created_by_device_id);

  insert into public.sync_change_log (
    user_id,
    entity_type,
    entity_id,
    operation,
    entity_revision,
    updated_by_device_id,
    last_command_id,
    changed_fields
  )
  values (
    owner_id,
    tg_table_name,
    entity_id,
    case
      when tg_op = 'INSERT' then 'upsert'
      when new.deleted_at is not null and old.deleted_at is null then 'delete'
      else 'upsert'
    end,
    entity_revision,
    device_id,
    command_id,
    jsonb_build_object('updated_at', coalesce(new.updated_at, old.updated_at))
  );
  return coalesce(new, old);
end;
$$;

do $$
declare
  table_name text;
  tracked_tables text[] := array[
    'profiles',
    'user_settings',
    'coaching_settings',
    'privacy_settings',
    'account_devices',
    'task_domains',
    'task_categories',
    'tags',
    'task_templates',
    'task_occurrences',
    'execution_sessions',
    'session_events',
    'user_runtime_state',
    'checklist_items',
    'work_demands',
    'learning_checkpoints',
    'roadmaps',
    'roadmap_phases',
    'roadmap_milestones',
    'roadmap_checkpoints',
    'activity_segments',
    'activity_attributions',
    'activity_contributions',
    'contribution_roadmap_effects',
    'activity_review_queue',
    'task_resources',
    'browser_workspaces',
    'browser_tabs'
  ];
begin
  foreach table_name in array tracked_tables
  loop
    execute format(
      'create trigger %I after insert or update on public.%I
       for each row execute function private.log_synchronized_change()',
      'log_' || table_name,
      table_name
    );
  end loop;
end;
$$;

-- Account bootstrap is deliberately idempotent.
create or replace function private.bootstrap_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, user_id, email, display_name)
  values (
    new.id,
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'display_name',
             new.raw_user_meta_data ->> 'full_name',
             '')
  )
  on conflict (user_id) do nothing;

  insert into public.user_settings (id, user_id)
  values (gen_random_uuid(), new.id)
  on conflict (user_id) do nothing;

  insert into public.coaching_settings (id, user_id)
  values (gen_random_uuid(), new.id)
  on conflict (user_id) do nothing;

  insert into public.privacy_settings (id, user_id)
  values (gen_random_uuid(), new.id)
  on conflict (user_id) do nothing;

  insert into public.user_runtime_state (id, user_id)
  values (gen_random_uuid(), new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger taskmaster_bootstrap_account
  after insert on auth.users
  for each row execute function private.bootstrap_account();

revoke all on function private.bootstrap_account() from public, anon, authenticated;
revoke all on function private.log_synchronized_change() from public, anon, authenticated;

-- Row-level ownership on every user-owned table in the exposed public schema.
do $$
declare
  table_record record;
begin
  for table_record in
    select distinct table_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'user_id'
  loop
    execute format('alter table public.%I enable row level security', table_record.table_name);
    execute format('alter table public.%I force row level security', table_record.table_name);

    execute format(
      'create policy %I on public.%I for select to authenticated
       using ((select auth.uid()) = user_id)',
      'owner_select_' || table_record.table_name,
      table_record.table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated
       with check ((select auth.uid()) = user_id)',
      'owner_insert_' || table_record.table_name,
      table_record.table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated
       using ((select auth.uid()) = user_id)
       with check ((select auth.uid()) = user_id)',
      'owner_update_' || table_record.table_name,
      table_record.table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated
       using ((select auth.uid()) = user_id)',
      'owner_delete_' || table_record.table_name,
      table_record.table_name
    );
  end loop;
end;
$$;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke all on all tables in schema public from anon;

-- Idempotent command RPC for the initial task occurrence sync path.
create or replace function public.apply_task_occurrence_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_entity_id uuid,
  p_base_revision bigint,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  current_revision bigint;
  existing_result jsonb;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_operation not in ('create', 'update', 'delete') then
    raise exception 'unsupported_operation';
  end if;

  if not exists (
    select 1
    from public.account_devices
    where user_id = owner_id
      and id = p_device_id
      and revoked_at is null
      and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':' || p_command_id::text, 0)
  );

  select result
  into existing_result
  from public.processed_commands
  where user_id = owner_id and command_id = p_command_id;

  if found then
    return existing_result;
  end if;

  select revision
  into current_revision
  from public.task_occurrences
  where user_id = owner_id and id = p_entity_id
  for update;

  if p_operation = 'create' and current_revision is null then
    if p_base_revision <> 0 then
      result_payload := jsonb_build_object(
        'status', 'conflict',
        'reason', 'missing_entity',
        'server_revision', null
      );
    else
      insert into public.task_occurrences (
        id,
        user_id,
        template_id,
        title,
        description,
        domain_id,
        status,
        priority,
        execution_mode,
        scheduled_date,
        planned_start,
        planned_end,
        due_at,
        estimated_duration_ms,
        roadmap_id,
        roadmap_phase_id,
        progress,
        created_by_device_id,
        updated_by_device_id,
        last_command_id,
        data
      )
      values (
        p_entity_id,
        owner_id,
        nullif(p_payload ->> 'template_id', '')::uuid,
        coalesce(nullif(p_payload ->> 'title', ''), 'Untitled task'),
        coalesce(p_payload ->> 'description', ''),
        nullif(p_payload ->> 'domain_id', '')::uuid,
        coalesce((p_payload ->> 'status')::public.task_status, 'ready'),
        coalesce((p_payload ->> 'priority')::integer, 2),
        coalesce((p_payload ->> 'execution_mode')::public.execution_mode, 'manual'),
        nullif(p_payload ->> 'scheduled_date', '')::date,
        nullif(p_payload ->> 'planned_start', '')::timestamptz,
        nullif(p_payload ->> 'planned_end', '')::timestamptz,
        nullif(p_payload ->> 'due_at', '')::timestamptz,
        coalesce((p_payload ->> 'estimated_duration_ms')::bigint, 0),
        nullif(p_payload ->> 'roadmap_id', '')::uuid,
        nullif(p_payload ->> 'roadmap_phase_id', '')::uuid,
        coalesce((p_payload ->> 'progress')::numeric, 0),
        p_device_id,
        p_device_id,
        p_command_id,
        coalesce(p_payload -> 'data', '{}'::jsonb)
      );

      result_payload := jsonb_build_object(
        'status', 'accepted',
        'entity_id', p_entity_id,
        'revision', 1
      );
    end if;
  elsif current_revision is null then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'missing_entity',
      'server_revision', null
    );
  elsif current_revision <> p_base_revision then
    insert into public.sync_conflicts (
      user_id,
      command_id,
      entity_type,
      entity_id,
      conflict_type,
      base_revision,
      server_revision,
      local_payload,
      server_payload,
      created_by_device_id,
      updated_by_device_id
    )
    values (
      owner_id,
      p_command_id,
      'task_occurrences',
      p_entity_id,
      'revision_mismatch',
      p_base_revision,
      current_revision,
      p_payload,
      jsonb_build_object('revision', current_revision),
      p_device_id,
      p_device_id
    )
    on conflict (user_id, command_id, entity_id) do nothing;

    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'revision_mismatch',
      'server_revision', current_revision
    );
  elsif p_operation = 'delete' then
    update public.task_occurrences
    set deleted_at = statement_timestamp(),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where user_id = owner_id and id = p_entity_id;

    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_id', p_entity_id,
      'revision', current_revision + 1,
      'deleted', true
    );
  else
    update public.task_occurrences
    set title = coalesce(p_payload ->> 'title', title),
        description = coalesce(p_payload ->> 'description', description),
        domain_id = case
          when p_payload ? 'domain_id'
            then nullif(p_payload ->> 'domain_id', '')::uuid
          else domain_id
        end,
        status = coalesce((p_payload ->> 'status')::public.task_status, status),
        priority = coalesce((p_payload ->> 'priority')::integer, priority),
        execution_mode = coalesce(
          (p_payload ->> 'execution_mode')::public.execution_mode,
          execution_mode
        ),
        scheduled_date = case
          when p_payload ? 'scheduled_date'
            then nullif(p_payload ->> 'scheduled_date', '')::date
          else scheduled_date
        end,
        planned_start = case
          when p_payload ? 'planned_start'
            then nullif(p_payload ->> 'planned_start', '')::timestamptz
          else planned_start
        end,
        planned_end = case
          when p_payload ? 'planned_end'
            then nullif(p_payload ->> 'planned_end', '')::timestamptz
          else planned_end
        end,
        due_at = case
          when p_payload ? 'due_at'
            then nullif(p_payload ->> 'due_at', '')::timestamptz
          else due_at
        end,
        estimated_duration_ms = coalesce(
          (p_payload ->> 'estimated_duration_ms')::bigint,
          estimated_duration_ms
        ),
        progress = coalesce((p_payload ->> 'progress')::numeric, progress),
        data = data || coalesce(p_payload -> 'data', '{}'::jsonb),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        deleted_at = null
    where user_id = owner_id and id = p_entity_id;

    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_id', p_entity_id,
      'revision', current_revision + 1
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
  )
  values (
    owner_id,
    p_command_id,
    p_device_id,
    p_device_sequence,
    'task_occurrences',
    p_entity_id,
    p_operation,
    p_base_revision,
    case
      when result_payload ->> 'status' = 'accepted'
        then 'accepted'::public.sync_command_status
      else 'conflict'::public.sync_command_status
    end,
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

revoke all on function public.apply_task_occurrence_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_task_occurrence_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated;

-- Compact account-scoped Realtime notification.
create or replace function private.broadcast_sync_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'sequence', new.change_sequence,
      'entity_type', new.entity_type,
      'entity_id', new.entity_id,
      'operation', new.operation,
      'revision', new.entity_revision
    ),
    'entity_changed',
    'taskmaster:user:' || new.user_id::text || ':runtime',
    true
  );
  return new;
end;
$$;

create trigger broadcast_sync_change
  after insert on public.sync_change_log
  for each row execute function private.broadcast_sync_change();

revoke all on function private.broadcast_sync_change() from public, anon, authenticated;

-- Private user-owned Storage buckets. Paths must start with the owner UUID.
-- Storage and Realtime tables are owned by their managed service roles. Their
-- account-scoped policies are configured on the project and intentionally are
-- not altered by this application-schema migration.
insert into storage.buckets (id, name, public, file_size_limit)
values
  ('task-resources', 'task-resources', false, 52428800),
  ('avatars', 'avatars', false, 5242880)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

comment on table public.activity_segments is
  'The single physical activity timeline. Attributions and contributions are semantic layers and must not increase physical totals.';
comment on table public.activity_attributions is
  'Proposed, automatic, confirmed, rejected, ignored, or superseded relationships between raw activity and logical targets.';
comment on table public.activity_contributions is
  'Approved effects from activity. credited_duration_ms may not exceed the source physical duration.';
comment on function public.apply_task_occurrence_command is
  'Idempotent revision-checked task mutation used by the local-first synchronization outbox.';
