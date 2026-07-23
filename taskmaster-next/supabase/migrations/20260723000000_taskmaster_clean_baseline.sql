-- TaskMaster Pro clean rebuild schema for Supabase.
-- WARNING: This script intentionally wipes the app-owned public/private schemas.
-- Run this only on a new TaskMaster Pro Supabase project or a project whose public app data may be deleted.
-- It preserves Supabase managed schemas such as auth, storage, realtime, extensions, and vault.

-- Best-effort cleanup for TaskMaster Pro storage policies that may already exist.
do $$
begin
  if to_regclass('storage.objects') is not null then
    begin
      drop policy if exists taskmaster_storage_select_own on storage.objects;
      drop policy if exists taskmaster_storage_insert_own on storage.objects;
      drop policy if exists taskmaster_storage_update_own on storage.objects;
      drop policy if exists taskmaster_storage_delete_own on storage.objects;
    exception
      when insufficient_privilege then null;
    end;
  end if;
end $$;

-- Wipe every old app table, trigger, function, policy, and view in public/private.
drop schema if exists public cascade;
drop schema if exists private cascade;
create schema public;

-- Restore Supabase-compatible privileges for the recreated public schema.
grant usage on schema public to postgres, anon, authenticated, service_role;
grant all on schema public to postgres, service_role;
alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on routines to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;
-- TaskMaster Pro clean baseline schema.
-- This migration is intended for a new or fully wiped Supabase project.
-- It deliberately does not depend on any historical TaskMaster Pro migrations.

create extension if not exists pgcrypto;

do $$
declare
  existing_table record;
begin
  for existing_table in
    select tablename
    from pg_tables
    where schemaname = 'public'
      and tablename <> 'spatial_ref_sys'
  loop
    execute format('drop table if exists public.%I cascade', existing_table.tablename);
  end loop;
end $$;

drop schema if exists private cascade;
create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Common helpers
-- ---------------------------------------------------------------------------

create or replace function public.touch_revision()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at = coalesce(new.created_at, now());
    new.updated_at = coalesce(new.updated_at, new.created_at);
    new.revision = coalesce(new.revision, 0);
  elsif tg_op = 'UPDATE' then
    new.created_at = old.created_at;
    new.updated_at = now();
    new.revision = coalesce(old.revision, 0) + 1;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profiles, devices, and settings
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  username text,
  avatar_path text,
  preferred_language text not null default 'en'
    check (preferred_language in ('en', 'ar', 'de')),
  sex text
    check (sex is null or sex in ('male', 'female', 'prefer_not_to_say', 'custom')),
  time_zone_mode text not null default 'device'
    check (time_zone_mode in ('device', 'fixed')),
  fixed_time_zone_id text,
  clock_format text not null default 'system'
    check (clock_format in ('system', '12h', '24h')),
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0
);

create unique index profiles_username_unique
on public.profiles(lower(username))
where username is not null and btrim(username) <> '';

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_name text not null default '',
  platform text not null check (platform in ('windows', 'android')),
  platform_version text not null default '',
  app_version text not null default '',
  build_number text not null default '',
  last_seen_at timestamptz not null default now(),
  notification_enabled boolean not null default true,
  logout_requested_at timestamptz,
  logout_requested_by_device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0
);

create table public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  theme text not null default 'dark_blue',
  language text not null default 'en' check (language in ('en', 'ar', 'de')),
  coaching_intensity text not null default 'active'
    check (
      coaching_intensity in (
        'quiet', 'standard', 'active', 'persistent', 'custom',
        'off', 'light', 'balanced', 'direct'
      )
    ),
  focus_duration_seconds integer not null default 1500
    check (focus_duration_seconds between 60 and 21600),
  short_break_duration_seconds integer not null default 300
    check (short_break_duration_seconds between 60 and 7200),
  long_break_duration_seconds integer not null default 900
    check (long_break_duration_seconds between 60 and 14400),
  long_break_after_focus_count integer not null default 4
    check (long_break_after_focus_count between 1 and 12),
  auto_start_break boolean not null default false,
  auto_start_focus boolean not null default false,
  ask_break_activity boolean not null default true,
  idle_threshold_seconds integer not null default 30
    check (idle_threshold_seconds between 10 and 3600),
  default_search_engine text not null default 'google'
    check (default_search_engine in ('google', 'bing', 'duckduckgo', 'brave')),
  browser_sync_enabled boolean not null default false,
  browser_cookie_sync_enabled boolean not null default false,
  browser_password_sync_enabled boolean not null default false,
  browser_password_autofill_enabled boolean not null default true,
  browser_form_autofill_enabled boolean not null default true,
  bookmark_sync_enabled boolean not null default true,
  health_sync_enabled boolean not null default false,
  cycle_sync_enabled boolean not null default false,
  time_zone_mode text not null default 'device'
    check (time_zone_mode in ('device', 'fixed')),
  fixed_time_zone_id text,
  clock_format text not null default 'system'
    check (clock_format in ('system', '12h', '24h')),
  quiet_hours_start_minutes integer
    check (quiet_hours_start_minutes is null or quiet_hours_start_minutes between 0 and 1439),
  quiet_hours_end_minutes integer
    check (quiet_hours_end_minutes is null or quiet_hours_end_minutes between 0 and 1439),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0
);

create table public.device_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  start_with_windows boolean not null default false,
  start_minimized boolean not null default false,
  keep_running_in_tray boolean not null default true,
  notify_on_device boolean not null default true,
  health_background_reading boolean not null default false,
  widget_enabled boolean not null default true,
  window_x integer,
  window_y integer,
  window_width integer,
  window_height integer,
  window_maximized boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (user_id, device_id)
);

-- ---------------------------------------------------------------------------
-- Tasks, domains, roadmaps, and progress
-- ---------------------------------------------------------------------------

create table public.task_domains (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  icon text not null default 'circle',
  color text not null default '#64748B',
  sort_order integer not null default 0,
  is_template boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create unique index task_domains_name_active_unique
on public.task_domains(user_id, lower(name))
where deleted_at is null;

create table public.roadmaps (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  goal text not null default '',
  start_date date,
  target_date date,
  status text not null default 'active'
    check (status in ('not_started', 'active', 'paused', 'completed', 'archived', 'cancelled')),
  progress_method text not null default 'weighted'
    check (progress_method in ('milestones', 'checkpoints', 'linked_tasks', 'focused_time', 'practice_contributions', 'reading_progress', 'manual', 'weighted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.roadmap_phases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  roadmap_id uuid not null references public.roadmaps(id) on delete cascade,
  phase_order integer not null default 0,
  title text not null,
  description text not null default '',
  start_date date,
  end_date date,
  status text not null default 'not_started'
    check (status in ('not_started', 'active', 'paused', 'completed', 'archived', 'cancelled')),
  progress_method text not null default 'weighted'
    check (progress_method in ('milestones', 'checkpoints', 'linked_tasks', 'focused_time', 'practice_contributions', 'reading_progress', 'manual', 'weighted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create unique index roadmap_phases_order_active_unique
on public.roadmap_phases(user_id, roadmap_id, phase_order)
where deleted_at is null;

create table public.roadmap_milestones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  roadmap_id uuid not null references public.roadmaps(id) on delete cascade,
  phase_id uuid references public.roadmap_phases(id) on delete set null,
  title text not null,
  description text not null default '',
  weight numeric not null default 1 check (weight >= 0),
  status text not null default 'not_started'
    check (status in ('not_started', 'active', 'completed', 'skipped', 'archived')),
  completion_criteria text not null default '',
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.roadmap_checkpoints (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  roadmap_id uuid not null references public.roadmaps(id) on delete cascade,
  phase_id uuid not null references public.roadmap_phases(id) on delete cascade,
  title text not null,
  status text not null default 'not_started'
    check (status in ('not_started', 'active', 'completed', 'skipped', 'archived')),
  weight numeric not null default 1 check (weight >= 0),
  evidence text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0
);

create table public.roadmap_progress_weights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  roadmap_id uuid not null references public.roadmaps(id) on delete cascade,
  component text not null
    check (component in ('milestones', 'checkpoints', 'linked_tasks', 'focused_time', 'practice_contributions', 'reading_progress', 'manual')),
  weight numeric not null check (weight >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (user_id, roadmap_id, component)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  domain_id uuid references public.task_domains(id) on delete set null,
  roadmap_id uuid references public.roadmaps(id) on delete set null,
  phase_id uuid references public.roadmap_phases(id) on delete set null,
  title text not null,
  description text not null default '',
  execution_mode text not null default 'manual_completion'
    check (execution_mode in ('pomodoro', 'continuous_timer', 'checklist', 'reading', 'habit', 'event', 'manual_completion', 'hybrid')),
  status text not null default 'todo'
    check (status in ('todo', 'in_progress', 'not_started', 'scheduled', 'running', 'paused', 'completed', 'skipped', 'cancelled', 'archived')),
  priority text not null default 'normal'
    check (priority in ('low', 'normal', 'medium', 'high', 'urgent')),
  planned_local_date date,
  planned_start_minutes integer
    check (planned_start_minutes is null or planned_start_minutes between 0 and 1439),
  planned_end_minutes integer
    check (planned_end_minutes is null or planned_end_minutes between 0 and 1440),
  time_zone_behavior text not null default 'floating'
    check (time_zone_behavior in ('floating', 'fixed_time_zone', 'device_time_zone', 'keep_local_clock', 'keep_absolute_time')),
  time_zone_id text,
  planned_start_at_utc timestamptz,
  planned_end_at_utc timestamptz,
  due_at_utc timestamptz,
  estimated_duration_seconds integer check (estimated_duration_seconds is null or estimated_duration_seconds >= 0),
  estimated_focus_sessions integer check (estimated_focus_sessions is null or estimated_focus_sessions >= 0),
  progress_method text not null default 'manual'
    check (progress_method in ('manual', 'checklist', 'checkpoints', 'focused_time', 'reading_progress', 'demands', 'weighted')),
  manual_progress numeric check (manual_progress is null or manual_progress between 0 and 100),
  recurrence_rule text,
  recurrence_time_zone_id text,
  recurrence_series_id uuid,
  recurrence_paused boolean not null default false,
  reminders_enabled boolean not null default true,
  adaptive_reminders_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0,
  constraint tasks_planned_minutes_order_check
    check (planned_start_minutes is null or planned_end_minutes is null or planned_end_minutes >= planned_start_minutes)
);

create index tasks_user_schedule_idx on public.tasks(user_id, planned_local_date, planned_start_minutes)
where deleted_at is null;
create index tasks_user_roadmap_idx on public.tasks(user_id, roadmap_id, phase_id)
where deleted_at is null;

create table public.task_checklist_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  status text not null default 'open'
    check (status in ('open', 'completed', 'skipped')),
  sort_order integer not null default 0,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.task_occurrences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  series_id uuid,
  occurrence_key text not null unique,
  scheduled_local_date date not null,
  planned_start_at_utc timestamptz,
  planned_end_at_utc timestamptz,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'running', 'completed', 'skipped', 'cancelled')),
  skipped_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0
);

create index task_occurrences_user_task_date_idx
on public.task_occurrences(user_id, task_id, scheduled_local_date);

-- ---------------------------------------------------------------------------
-- Runtime, Pomodoro, and multi-device commands
-- ---------------------------------------------------------------------------

create table public.task_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  occurrence_id uuid references public.task_occurrences(id) on delete set null,
  execution_mode text not null
    check (execution_mode in ('pomodoro', 'continuous_timer', 'checklist', 'reading', 'habit', 'event', 'manual_completion', 'hybrid')),
  state text not null
    check (state in ('focus_ready', 'focus_running', 'focus_paused', 'focus_completed_waiting', 'break_ready', 'break_running', 'break_paused', 'break_completed_waiting', 'running', 'paused', 'task_completed', 'cancelled')),
  started_at_utc timestamptz not null,
  completed_at_utc timestamptz,
  accumulated_active_seconds integer not null default 0 check (accumulated_active_seconds >= 0),
  accumulated_paused_seconds integer not null default 0 check (accumulated_paused_seconds >= 0),
  accumulated_idle_seconds integer not null default 0 check (accumulated_idle_seconds >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0
);

create index task_sessions_user_task_state_idx
on public.task_sessions(user_id, task_id, state, updated_at desc);

create table public.session_segments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid not null references public.task_sessions(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  segment_number integer not null,
  segment_type text not null
    check (segment_type in ('focus', 'focus_extension', 'short_break', 'long_break', 'continuous_work', 'reading', 'event', 'manual')),
  state text not null default 'running'
    check (state in ('ready', 'running', 'paused', 'completed', 'cancelled')),
  planned_duration_seconds integer check (planned_duration_seconds is null or planned_duration_seconds >= 0),
  actual_active_seconds integer not null default 0 check (actual_active_seconds >= 0),
  paused_seconds integer not null default 0 check (paused_seconds >= 0),
  idle_seconds integer not null default 0 check (idle_seconds >= 0),
  started_at_utc timestamptz not null,
  last_resumed_at_utc timestamptz,
  last_paused_at_utc timestamptz,
  completed_at_utc timestamptz,
  transition_reason text,
  parent_segment_id uuid references public.session_segments(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (session_id, segment_number)
);

create index session_segments_open_idx
on public.session_segments(user_id, session_id, segment_number desc)
where completed_at_utc is null;

create or replace function private.next_segment_number(p_session_id uuid)
returns integer
language sql
stable
as $$
  select coalesce(max(segment_number), 0) + 1
  from public.session_segments
  where session_id = p_session_id;
$$;

create table public.session_commands (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid references public.task_sessions(id) on delete set null,
  task_id uuid not null references public.tasks(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  command_type text not null
    check (command_type in (
      'start_task', 'pause_task', 'resume_task', 'finish_task',
      'start_focus', 'pause_focus', 'resume_focus', 'finish_focus', 'jump_to_break',
      'start_break', 'pause_break', 'resume_break', 'finish_break', 'skip_break',
      'extend_break', 'return_to_focus'
    )),
  expected_revision bigint not null default 0,
  payload jsonb not null default '{}'::jsonb,
  client_occurred_at timestamptz not null,
  server_applied_at timestamptz,
  result_revision bigint,
  status text not null default 'pending'
    check (status in ('pending', 'applied', 'duplicate', 'conflict', 'rejected', 'failed')),
  error text,
  created_at timestamptz not null default now()
);

create index session_commands_user_session_idx
on public.session_commands(user_id, session_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Offline sync, task-specific records, activity, resources, and browser state
-- ---------------------------------------------------------------------------

create table public.sync_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  operation text not null check (operation in ('insert', 'update', 'delete', 'upsert')),
  base_revision bigint not null default 0,
  changed_fields jsonb not null default '[]'::jsonb,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  retry_count integer not null default 0,
  state text not null default 'pending'
    check (state in ('pending', 'uploading', 'synchronized', 'conflict', 'failed')),
  last_error text
);

create table public.task_demands (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  description text not null default '',
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'urgent')),
  status text not null default 'open'
    check (status in ('open', 'in_progress', 'completed', 'cancelled', 'deferred')),
  original_due_date date,
  current_scheduled_date date,
  completed_at timestamptz,
  rollover_policy text not null default 'next_occurrence'
    check (rollover_policy in ('none', 'next_occurrence', 'next_work_day', 'manual')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.task_checkpoints (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  description text not null default '',
  status text not null default 'not_started'
    check (status in ('not_started', 'in_progress', 'completed', 'skipped', 'archived')),
  completion_criteria text not null default '',
  target_date date,
  evidence text,
  completed_at timestamptz,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.activity_intervals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_id uuid references public.task_sessions(id) on delete set null,
  segment_id uuid references public.session_segments(id) on delete set null,
  task_id uuid references public.tasks(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  context_type text not null
    check (context_type in ('taskmaster', 'browser', 'external_application', 'other_active_context', 'idle')),
  application_id text,
  window_title text,
  resource_id uuid,
  started_at_utc timestamptz not null,
  ended_at_utc timestamptz not null,
  duration_seconds integer not null check (duration_seconds >= 0),
  idle_seconds integer not null default 0 check (idle_seconds >= 0),
  created_at timestamptz not null default now()
);

create table public.activity_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_task_id uuid not null references public.tasks(id) on delete cascade,
  source_session_id uuid not null references public.task_sessions(id) on delete cascade,
  source_segment_id uuid not null references public.session_segments(id) on delete cascade,
  related_task_id uuid references public.tasks(id) on delete set null,
  related_roadmap_id uuid references public.roadmaps(id) on delete set null,
  resource_id uuid,
  activity_type text not null,
  duration_seconds integer not null check (duration_seconds >= 0),
  progress_value numeric,
  attribution_method text not null,
  user_confirmed boolean not null default false,
  started_at_utc timestamptz not null,
  ended_at_utc timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.task_resources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  name text not null,
  resource_type text not null
    check (resource_type in ('web_page', 'bookmark', 'pdf', 'epub', 'image', 'document', 'spreadsheet', 'video', 'audio', 'folder', 'local_file', 'cloud_file', 'external_reference')),
  description text not null default '',
  web_url text,
  remote_storage_path text,
  file_hash text,
  tags jsonb not null default '[]'::jsonb,
  is_default boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

alter table public.activity_intervals
  add constraint activity_intervals_resource_fk
  foreign key (resource_id) references public.task_resources(id) on delete set null;

alter table public.activity_contributions
  add constraint activity_contributions_resource_fk
  foreign key (resource_id) references public.task_resources(id) on delete set null;

create table public.resource_device_locations (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.task_resources(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  local_path text not null,
  availability text not null default 'unknown'
    check (availability in ('available', 'missing', 'remote_only', 'unknown')),
  last_verified_at timestamptz,
  unique (resource_id, device_id)
);

create table public.resource_annotations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  resource_id uuid not null references public.task_resources(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  annotation_type text not null
    check (annotation_type in ('last_position', 'page_bookmark', 'note', 'highlight')),
  page_number integer check (page_number is null or page_number >= 0),
  locator jsonb not null default '{}'::jsonb,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.browser_tabs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid references public.devices(id) on delete set null,
  task_id uuid references public.tasks(id) on delete cascade,
  occurrence_id uuid references public.task_occurrences(id) on delete set null,
  resource_id uuid references public.task_resources(id) on delete set null,
  url text not null default 'https://www.google.com',
  title text not null default 'Google',
  custom_title text,
  pinned boolean not null default false,
  active boolean not null default false,
  sort_order integer not null default 0,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.closed_browser_tabs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid references public.devices(id) on delete set null,
  task_id uuid references public.tasks(id) on delete cascade,
  occurrence_id uuid references public.task_occurrences(id) on delete set null,
  url text not null,
  title text not null,
  custom_title text,
  closed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.browser_vault_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  origin text not null,
  item_type text not null
    check (item_type in ('password', 'form_profile', 'payment_hint', 'cookie_bundle')),
  display_name text not null default '',
  username_hint text,
  encrypted_payload text not null,
  encryption_scheme text not null default 'xchacha20poly1305_v1',
  key_version integer not null default 1 check (key_version > 0),
  device_created_id uuid references public.devices(id) on delete set null,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0,
  unique (user_id, origin, item_type, username_hint)
);

create table public.task_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  occurrence_id uuid references public.task_occurrences(id) on delete cascade,
  device_id uuid references public.devices(id) on delete set null,
  reminder_type text not null default 'task'
    check (reminder_type in ('task', 'focus_alarm', 'break_alarm', 'coaching')),
  title text not null default '',
  body text not null default '',
  scheduled_at timestamptz,
  custom_trigger_at timestamptz,
  offset_minutes integer,
  notification_id text,
  channel text not null default 'task_reminders',
  status text not null default 'pending'
    check (status in ('pending', 'scheduled', 'sent', 'dismissed', 'snoozed', 'cancelled', 'failed')),
  is_adaptive boolean not null default false,
  reason text,
  sent_at timestamptz,
  dismissed_at timestamptz,
  snoozed_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.reading_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  resource_id uuid references public.task_resources(id) on delete set null,
  session_id uuid references public.task_sessions(id) on delete set null,
  started_at_utc timestamptz not null,
  ended_at_utc timestamptz,
  start_locator jsonb not null default '{}'::jsonb,
  end_locator jsonb not null default '{}'::jsonb,
  progress_value numeric,
  duration_seconds integer not null default 0 check (duration_seconds >= 0),
  created_at timestamptz not null default now()
);

create table public.task_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  session_id uuid references public.task_sessions(id) on delete set null,
  resource_id uuid references public.task_resources(id) on delete set null,
  note_type text not null default 'general'
    check (note_type in ('general', 'progress', 'problem', 'idea', 'decision', 'next_action', 'learning_summary', 'work_result')),
  title text not null default '',
  body text not null,
  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.quick_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default '',
  body text not null,
  details text not null default '',
  category text,
  roadmap_id uuid references public.roadmaps(id) on delete set null,
  converted_task_id uuid references public.tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create index quick_notes_user_created_idx
on public.quick_notes(user_id, created_at desc)
where deleted_at is null;

-- ---------------------------------------------------------------------------
-- Health, cycle data, and coaching
-- ---------------------------------------------------------------------------

create table public.health_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  provider text not null default 'health_connect'
    check (provider in ('health_connect')),
  connection_status text not null default 'not_connected'
    check (connection_status in ('not_connected', 'connected', 'partially_connected', 'permission_revoked', 'read_failed')),
  granted_data_types jsonb not null default '[]'::jsonb,
  preferred_sources jsonb not null default '{}'::jsonb,
  sync_cursor jsonb not null default '{}'::jsonb,
  last_read_at timestamptz,
  last_successful_sync_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (user_id, device_id, provider)
);

create table public.health_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  connection_id uuid not null references public.health_connections(id) on delete cascade,
  provider text not null default 'health_connect'
    check (provider in ('health_connect')),
  source_package text not null,
  source_record_id text not null,
  data_type text not null
    check (data_type in ('steps', 'exercise', 'distance', 'heart_rate', 'sleep', 'active_calories')),
  started_at_utc timestamptz not null,
  ended_at_utc timestamptz,
  numeric_value numeric,
  unit text,
  samples jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, provider, source_record_id, data_type)
);

create table public.health_daily_summaries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  summary_date date not null,
  steps integer not null default 0,
  exercise_seconds integer not null default 0,
  distance_meters numeric not null default 0,
  active_calories numeric not null default 0,
  sleep_seconds integer not null default 0,
  latest_heart_rate numeric,
  sources jsonb not null default '{}'::jsonb,
  calculated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (user_id, summary_date)
);

create table public.cycle_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_period_start date,
  last_period_end date,
  cycle_length_days integer not null default 28
    check (cycle_length_days between 18 and 45),
  period_length_days integer not null default 5
    check (period_length_days between 1 and 12),
  reduce_before_period boolean not null default true,
  reduce_first_days boolean not null default true,
  gentle_coaching boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0
);

create table public.cycle_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  entry_date date not null,
  entry_type text not null
    check (entry_type in ('period_start', 'period_end', 'symptom', 'note')),
  value text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

create table public.user_behavior_features (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  feature_key text not null,
  feature_scope text not null default 'global',
  value jsonb not null,
  evidence_count integer not null default 0 check (evidence_count >= 0),
  calculated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  unique (user_id, feature_key, feature_scope)
);

create table public.coaching_recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  recommendation_type text not null,
  reason text not null,
  evidence_count integer not null check (evidence_count >= 0),
  confidence numeric not null check (confidence between 0 and 1),
  suggested_action text not null,
  related_task_id uuid references public.tasks(id) on delete set null,
  related_roadmap_id uuid references public.roadmaps(id) on delete set null,
  status text not null default 'active'
    check (status in ('active', 'accepted', 'dismissed', 'expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  revision bigint not null default 0
);

-- ---------------------------------------------------------------------------
-- Relationship validators. These do not call auth.uid().
-- ---------------------------------------------------------------------------

create or replace function public.validate_device_settings_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.devices d
    where d.id = new.device_id and d.user_id = new.user_id
  ) then
    raise exception 'device_settings.device_id must belong to the same user';
  end if;
  return new;
end;
$$;

create or replace function public.validate_roadmap_phase_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.roadmaps r
    where r.id = new.roadmap_id
      and r.user_id = new.user_id
      and r.deleted_at is null
  ) then
    raise exception 'roadmap_phases.roadmap_id must belong to the same user';
  end if;
  return new;
end;
$$;

create or replace function public.validate_roadmap_milestone_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.roadmaps r
    where r.id = new.roadmap_id and r.user_id = new.user_id
  ) then
    raise exception 'roadmap_milestones.roadmap_id must belong to the same user';
  end if;

  if new.phase_id is not null and not exists (
    select 1 from public.roadmap_phases p
    where p.id = new.phase_id
      and p.roadmap_id = new.roadmap_id
      and p.user_id = new.user_id
  ) then
    raise exception 'roadmap_milestones.phase_id must belong to the selected roadmap';
  end if;

  return new;
end;
$$;

create or replace function public.validate_roadmap_checkpoint_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.roadmap_phases p
    where p.id = new.phase_id
      and p.roadmap_id = new.roadmap_id
      and p.user_id = new.user_id
  ) then
    raise exception 'roadmap_checkpoints.phase_id must belong to the selected roadmap';
  end if;
  return new;
end;
$$;

create or replace function public.validate_task_relationships()
returns trigger
language plpgsql
as $$
begin
  if new.domain_id is not null and not exists (
    select 1 from public.task_domains d
    where d.id = new.domain_id
      and d.user_id = new.user_id
      and d.deleted_at is null
  ) then
    raise exception 'tasks.domain_id must belong to the same user';
  end if;

  if new.roadmap_id is not null and not exists (
    select 1 from public.roadmaps r
    where r.id = new.roadmap_id
      and r.user_id = new.user_id
      and r.deleted_at is null
  ) then
    raise exception 'tasks.roadmap_id must belong to the same user';
  end if;

  if new.phase_id is not null then
    if new.roadmap_id is null then
      raise exception 'tasks.phase_id requires tasks.roadmap_id';
    end if;

    if not exists (
      select 1 from public.roadmap_phases p
      where p.id = new.phase_id
        and p.roadmap_id = new.roadmap_id
        and p.user_id = new.user_id
        and p.deleted_at is null
    ) then
      raise exception 'tasks.phase_id must belong to tasks.roadmap_id';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.validate_task_child_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.tasks t
    where t.id = new.task_id and t.user_id = new.user_id
  ) then
    raise exception '% task_id must belong to the same user', tg_table_name;
  end if;
  return new;
end;
$$;

create or replace function public.validate_session_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.tasks t
    where t.id = new.task_id and t.user_id = new.user_id
  ) then
    raise exception 'task_sessions.task_id must belong to the same user';
  end if;

  if new.occurrence_id is not null and not exists (
    select 1 from public.task_occurrences o
    where o.id = new.occurrence_id
      and o.task_id = new.task_id
      and o.user_id = new.user_id
  ) then
    raise exception 'task_sessions.occurrence_id must belong to the selected task';
  end if;

  return new;
end;
$$;

create or replace function public.validate_segment_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.task_sessions s
    where s.id = new.session_id
      and s.task_id = new.task_id
      and s.user_id = new.user_id
  ) then
    raise exception 'session_segments.session_id must belong to task_id and user_id';
  end if;
  return new;
end;
$$;

create or replace function public.validate_resource_device_location()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1
    from public.task_resources r
    join public.devices d on d.id = new.device_id
    where r.id = new.resource_id
      and r.user_id = d.user_id
  ) then
    raise exception 'resource_device_locations resource and device must belong to the same user';
  end if;
  return new;
end;
$$;

create or replace function public.validate_health_record_relationship()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.health_connections c
    where c.id = new.connection_id
      and c.user_id = new.user_id
      and c.provider = new.provider
  ) then
    raise exception 'health_records.connection_id must belong to user and provider';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Defaults for new users
-- ---------------------------------------------------------------------------

create or replace function public.ensure_user_defaults(
  p_user_id uuid,
  p_email text default null,
  p_display_name text default null,
  p_preferred_language text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_language text := case
    when p_preferred_language in ('en', 'ar', 'de') then p_preferred_language
    else 'en'
  end;
  v_display_name text := coalesce(
    nullif(btrim(p_display_name), ''),
    nullif(split_part(coalesce(p_email, ''), '@', 1), '')
  );
begin
  insert into public.profiles (id, display_name, preferred_language)
  values (p_user_id, v_display_name, v_language)
  on conflict (id) do nothing;

  insert into public.user_settings (user_id, language)
  values (p_user_id, v_language)
  on conflict (user_id) do nothing;

  insert into public.task_domains (user_id, name, icon, color, sort_order, is_template)
  values
    (p_user_id, 'Work', 'briefcase', '#2563EB', 10, true),
    (p_user_id, 'Learning', 'graduation-cap', '#7C3AED', 20, true),
    (p_user_id, 'Reading', 'book-open', '#0891B2', 30, true),
    (p_user_id, 'Self-improvement', 'sparkles', '#DB2777', 40, true),
    (p_user_id, 'Householding', 'home', '#16A34A', 50, true),
    (p_user_id, 'Sport', 'dumbbell', '#EA580C', 60, true),
    (p_user_id, 'Event', 'calendar', '#DC2626', 70, true),
    (p_user_id, 'Personal', 'user', '#475569', 80, true),
    (p_user_id, 'Habit', 'repeat', '#059669', 90, true)
  on conflict do nothing;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_user_defaults(
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'preferred_language'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_taskmaster on auth.users;
create trigger on_auth_user_created_taskmaster
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.bootstrap_current_user()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_display_name text;
  v_preferred_language text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select
    email,
    raw_user_meta_data->>'full_name',
    raw_user_meta_data->>'preferred_language'
  into v_email, v_display_name, v_preferred_language
  from auth.users
  where id = v_user_id;

  perform public.ensure_user_defaults(
    v_user_id,
    v_email,
    v_display_name,
    v_preferred_language
  );

  return jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.id = v_user_id),
    'user_settings', (select to_jsonb(s) from public.user_settings s where s.user_id = v_user_id),
    'task_domains', (
      select coalesce(jsonb_agg(to_jsonb(d) order by d.sort_order), '[]'::jsonb)
      from public.task_domains d
      where d.user_id = v_user_id and d.deleted_at is null
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Runtime RPC and Realtime broadcast
-- ---------------------------------------------------------------------------

create or replace function public.session_snapshot(p_session_id uuid)
returns jsonb
language sql
stable
as $$
  select case
    when s.id is null then null
    else jsonb_build_object(
      'session', to_jsonb(s),
      'current_segment', (
        select to_jsonb(seg)
        from public.session_segments seg
        where seg.session_id = s.id
        order by seg.segment_number desc
        limit 1
      )
    )
  end
  from public.task_sessions s
  where s.id = p_session_id;
$$;

create or replace function public.emit_runtime_event(
  p_user_id uuid,
  p_event text,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    execute 'select realtime.send($1, $2, $3, $4)'
      using p_payload,
            p_event,
            'taskmaster:user:' || p_user_id::text || ':runtime',
            true;
  exception
    when undefined_function or invalid_schema_name then
      null;
  end;
end;
$$;

create or replace function public.apply_session_command(
  p_command_id uuid,
  p_task_id uuid,
  p_device_id uuid,
  p_command_type text,
  p_expected_revision bigint,
  p_session_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_client_occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_task public.tasks%rowtype;
  v_device public.devices%rowtype;
  v_existing public.session_commands%rowtype;
  v_session public.task_sessions%rowtype;
  v_segment public.session_segments%rowtype;
  v_next_state text;
  v_new_segment_type text;
  v_elapsed integer := 0;
  v_paused_elapsed integer := 0;
  v_planned_seconds integer;
  v_result_revision bigint;
  v_error text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into v_existing
  from public.session_commands
  where id = p_command_id;

  if found then
    return jsonb_build_object(
      'status', 'duplicate',
      'revision', v_existing.result_revision,
      'session_id', v_existing.session_id,
      'snapshot', public.session_snapshot(v_existing.session_id)
    );
  end if;

  select * into v_device
  from public.devices
  where id = p_device_id and user_id = v_user_id;

  if not found then
    return jsonb_build_object('status', 'failed', 'error', 'Device not registered');
  end if;

  select * into v_task
  from public.tasks
  where id = p_task_id
    and user_id = v_user_id
    and deleted_at is null;

  if not found then
    insert into public.session_commands (
      id, user_id, session_id, task_id, device_id, command_type,
      expected_revision, payload, client_occurred_at, status, error
    )
    values (
      p_command_id, v_user_id, p_session_id, p_task_id, p_device_id,
      p_command_type, p_expected_revision, coalesce(p_payload, '{}'::jsonb),
      p_client_occurred_at, 'failed', 'Task not found'
    );
    return jsonb_build_object('status', 'failed', 'error', 'Task not found');
  end if;

  if p_session_id is not null then
    select * into v_session
    from public.task_sessions
    where id = p_session_id and user_id = v_user_id
    for update;
  elsif p_command_type in ('start_task', 'start_focus') then
    v_session.id := null;
  else
    select * into v_session
    from public.task_sessions
    where task_id = p_task_id
      and user_id = v_user_id
      and state not in ('task_completed', 'cancelled')
    order by updated_at desc
    limit 1
    for update;
  end if;

  if v_session.id is null and p_command_type in ('start_task', 'start_focus') then
    v_next_state := case
      when p_command_type = 'start_focus' then 'focus_running'
      when v_task.execution_mode = 'pomodoro' then 'focus_ready'
      else 'running'
    end;

    insert into public.task_sessions (
      user_id, task_id, occurrence_id, execution_mode, state,
      started_at_utc, accumulated_active_seconds, accumulated_paused_seconds,
      accumulated_idle_seconds
    )
    values (
      v_user_id,
      p_task_id,
      nullif(p_payload ->> 'occurrence_id', '')::uuid,
      v_task.execution_mode,
      v_next_state,
      v_now,
      0,
      0,
      0
    )
    returning * into v_session;

    if v_next_state in ('focus_running', 'running') then
      v_new_segment_type := case
        when v_next_state = 'focus_running' then 'focus'
        when v_task.execution_mode = 'reading' then 'reading'
        when v_task.execution_mode = 'event' then 'event'
        when v_task.execution_mode = 'continuous_timer' then 'continuous_work'
        else 'manual'
      end;
      v_planned_seconds := coalesce(
        nullif(p_payload ->> 'planned_duration_seconds', '')::integer,
        v_task.estimated_duration_seconds,
        case when v_next_state = 'focus_running'
          then (select focus_duration_seconds from public.user_settings where user_id = v_user_id)
          else null
        end
      );
      insert into public.session_segments (
        user_id, session_id, task_id, segment_number, segment_type, state,
        planned_duration_seconds, started_at_utc, last_resumed_at_utc,
        transition_reason
      )
      values (
        v_user_id, v_session.id, p_task_id, 1, v_new_segment_type, 'running',
        v_planned_seconds, v_now, v_now, p_command_type
      );
    end if;
  elsif v_session.id is null then
    v_error := 'No active session';
  elsif v_session.task_id <> p_task_id then
    v_error := 'Session does not belong to task';
  elsif v_session.revision <> p_expected_revision then
    insert into public.session_commands (
      id, user_id, session_id, task_id, device_id, command_type,
      expected_revision, payload, client_occurred_at, server_applied_at,
      result_revision, status, error
    )
    values (
      p_command_id, v_user_id, v_session.id, p_task_id, p_device_id,
      p_command_type, p_expected_revision, coalesce(p_payload, '{}'::jsonb),
      p_client_occurred_at, v_now, v_session.revision, 'conflict',
      'Revision mismatch'
    );
    return jsonb_build_object(
      'status', 'conflict',
      'revision', v_session.revision,
      'error', 'Revision mismatch',
      'snapshot', public.session_snapshot(v_session.id)
    );
  else
    v_next_state := case p_command_type
      when 'pause_task' then case
        when v_session.state = 'focus_running' then 'focus_paused'
        when v_session.state = 'break_running' then 'break_paused'
        when v_session.state = 'running' then 'paused'
        else null
      end
      when 'resume_task' then case
        when v_session.state = 'focus_paused' then 'focus_running'
        when v_session.state = 'break_paused' then 'break_running'
        when v_session.state = 'paused' then 'running'
        else null
      end
      when 'finish_task' then 'task_completed'
      when 'start_focus' then case
        when v_session.state in ('focus_ready', 'focus_paused', 'break_completed_waiting') then 'focus_running'
        else null
      end
      when 'pause_focus' then case when v_session.state = 'focus_running' then 'focus_paused' else null end
      when 'resume_focus' then case when v_session.state = 'focus_paused' then 'focus_running' else null end
      when 'finish_focus' then case when v_session.state in ('focus_running', 'focus_paused') then 'focus_completed_waiting' else null end
      when 'jump_to_break' then case when v_session.state in ('focus_running', 'focus_paused', 'focus_completed_waiting') then 'break_ready' else null end
      when 'start_break' then case when v_session.state in ('break_ready', 'focus_completed_waiting') then 'break_running' else null end
      when 'pause_break' then case when v_session.state = 'break_running' then 'break_paused' else null end
      when 'resume_break' then case when v_session.state = 'break_paused' then 'break_running' else null end
      when 'finish_break' then case when v_session.state in ('break_running', 'break_paused') then 'break_completed_waiting' else null end
      when 'skip_break' then case when v_session.state in ('break_ready', 'focus_completed_waiting', 'break_running', 'break_paused', 'break_completed_waiting') then 'focus_ready' else null end
      when 'extend_break' then case when v_session.state in ('break_running', 'break_paused', 'break_completed_waiting') then 'break_running' else null end
      when 'return_to_focus' then case when v_session.state in ('break_ready', 'break_running', 'break_paused', 'break_completed_waiting', 'focus_completed_waiting') then 'focus_ready' else null end
      else null
    end;

    if v_next_state is null then
      v_error := 'Invalid state transition';
    end if;
  end if;

  if v_error is not null then
    insert into public.session_commands (
      id, user_id, session_id, task_id, device_id, command_type,
      expected_revision, payload, client_occurred_at, server_applied_at,
      result_revision, status, error
    )
    values (
      p_command_id, v_user_id, v_session.id, p_task_id, p_device_id,
      p_command_type, p_expected_revision, coalesce(p_payload, '{}'::jsonb),
      p_client_occurred_at, v_now, v_session.revision, 'rejected', v_error
    );
    return jsonb_build_object(
      'status', 'rejected',
      'error', v_error,
      'revision', v_session.revision,
      'snapshot', public.session_snapshot(v_session.id)
    );
  end if;

  select * into v_segment
  from public.session_segments
  where session_id = v_session.id
  order by segment_number desc
  limit 1
  for update;

  if found and v_segment.state = 'running' and v_segment.last_resumed_at_utc is not null
     and v_next_state in ('focus_paused', 'break_paused', 'paused', 'focus_completed_waiting', 'break_completed_waiting', 'break_ready', 'focus_ready', 'task_completed', 'cancelled') then
    v_elapsed := greatest(0, floor(extract(epoch from (v_now - v_segment.last_resumed_at_utc)))::integer);
    update public.session_segments
    set actual_active_seconds = actual_active_seconds + v_elapsed,
        state = case
          when v_next_state in ('focus_paused', 'break_paused', 'paused') then 'paused'
          when v_next_state in ('task_completed', 'cancelled', 'focus_completed_waiting', 'break_completed_waiting', 'break_ready', 'focus_ready') then 'completed'
          else state
        end,
        last_resumed_at_utc = null,
        last_paused_at_utc = case
          when v_next_state in ('focus_paused', 'break_paused', 'paused') then v_now
          else last_paused_at_utc
        end,
        completed_at_utc = case
          when v_next_state in ('task_completed', 'cancelled', 'focus_completed_waiting', 'break_completed_waiting', 'break_ready', 'focus_ready') then v_now
          else completed_at_utc
        end,
        transition_reason = p_command_type
    where id = v_segment.id;
  elsif found and v_segment.state = 'paused' and v_segment.last_paused_at_utc is not null
        and v_next_state in ('focus_running', 'break_running', 'running') then
    v_paused_elapsed := greatest(0, floor(extract(epoch from (v_now - v_segment.last_paused_at_utc)))::integer);
    update public.session_segments
    set paused_seconds = paused_seconds + v_paused_elapsed,
        state = 'running',
        last_resumed_at_utc = v_now,
        last_paused_at_utc = null,
        transition_reason = p_command_type
    where id = v_segment.id;
  end if;

  if p_command_type in ('start_focus', 'extend_break')
     or (p_command_type = 'start_break' and v_next_state = 'break_running') then
    v_new_segment_type := case
      when p_command_type = 'extend_break' then 'long_break'
      when v_next_state = 'break_running' then
        case when coalesce((p_payload ->> 'break_type'), 'short_break') = 'long_break'
          then 'long_break' else 'short_break' end
      else 'focus'
    end;
    v_planned_seconds := coalesce(
      nullif(p_payload ->> 'planned_duration_seconds', '')::integer,
      case
        when v_new_segment_type = 'focus' then (select focus_duration_seconds from public.user_settings where user_id = v_user_id)
        when v_new_segment_type = 'long_break' then (select long_break_duration_seconds from public.user_settings where user_id = v_user_id)
        when v_new_segment_type = 'short_break' then (select short_break_duration_seconds from public.user_settings where user_id = v_user_id)
        else null
      end
    );
    if not exists (
      select 1 from public.session_segments
      where session_id = v_session.id and state = 'running'
    ) then
      insert into public.session_segments (
        user_id, session_id, task_id, segment_number, segment_type, state,
        planned_duration_seconds, started_at_utc, last_resumed_at_utc,
        transition_reason
      )
      values (
        v_user_id, v_session.id, p_task_id,
        private.next_segment_number(v_session.id),
        v_new_segment_type, 'running', v_planned_seconds, v_now, v_now,
        p_command_type
      );
    end if;
  end if;

  update public.task_sessions
  set state = v_next_state,
      completed_at_utc = case when v_next_state = 'task_completed' then v_now else completed_at_utc end,
      accumulated_active_seconds = accumulated_active_seconds + v_elapsed,
      accumulated_paused_seconds = accumulated_paused_seconds + v_paused_elapsed
  where id = v_session.id
  returning * into v_session;

  v_result_revision := v_session.revision;

  insert into public.session_commands (
    id, user_id, session_id, task_id, device_id, command_type,
    expected_revision, payload, client_occurred_at, server_applied_at,
    result_revision, status
  )
  values (
    p_command_id, v_user_id, v_session.id, p_task_id, p_device_id,
    p_command_type, p_expected_revision, coalesce(p_payload, '{}'::jsonb),
    p_client_occurred_at, v_now, v_result_revision, 'applied'
  );

  perform public.emit_runtime_event(
    v_user_id,
    'session_changed',
    jsonb_build_object(
      'event', 'session_changed',
      'session_id', v_session.id,
      'task_id', p_task_id,
      'command_type', p_command_type,
      'revision', v_result_revision,
      'snapshot', public.session_snapshot(v_session.id)
    )
  );

  return jsonb_build_object(
    'status', 'applied',
    'revision', v_result_revision,
    'session_id', v_session.id,
    'snapshot', public.session_snapshot(v_session.id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create trigger profiles_touch_revision
before insert or update on public.profiles
for each row execute function public.touch_revision();

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'devices',
    'user_settings',
    'device_settings',
    'task_domains',
    'roadmaps',
    'roadmap_phases',
    'roadmap_milestones',
    'roadmap_checkpoints',
    'roadmap_progress_weights',
    'tasks',
    'task_checklist_items',
    'task_occurrences',
    'task_sessions',
    'session_segments',
    'task_demands',
    'task_checkpoints',
    'task_resources',
    'resource_annotations',
    'browser_tabs',
    'browser_vault_items',
    'task_reminders',
    'health_connections',
    'health_daily_summaries',
    'cycle_preferences',
    'cycle_entries',
    'user_behavior_features',
    'coaching_recommendations',
    'task_notes',
    'quick_notes'
  ]
  loop
    execute format(
      'create trigger %I before insert or update on public.%I for each row execute function public.touch_revision()',
      table_name || '_touch_revision',
      table_name
    );
  end loop;
end $$;

create trigger device_settings_validate_relationship
before insert or update on public.device_settings
for each row execute function public.validate_device_settings_relationship();

create trigger roadmap_phases_validate_relationship
before insert or update on public.roadmap_phases
for each row execute function public.validate_roadmap_phase_relationship();

create trigger roadmap_milestones_validate_relationship
before insert or update on public.roadmap_milestones
for each row execute function public.validate_roadmap_milestone_relationship();

create trigger roadmap_checkpoints_validate_relationship
before insert or update on public.roadmap_checkpoints
for each row execute function public.validate_roadmap_checkpoint_relationship();

create trigger tasks_validate_relationships
before insert or update on public.tasks
for each row execute function public.validate_task_relationships();

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'task_checklist_items',
    'task_occurrences',
    'task_demands',
    'task_checkpoints',
    'task_resources',
    'task_reminders',
    'task_notes'
  ]
  loop
    execute format(
      'create trigger %I before insert or update on public.%I for each row execute function public.validate_task_child_relationship()',
      table_name || '_validate_task_child',
      table_name
    );
  end loop;
end $$;

create trigger task_sessions_validate_relationship
before insert or update on public.task_sessions
for each row execute function public.validate_session_relationship();

create trigger session_segments_validate_relationship
before insert or update on public.session_segments
for each row execute function public.validate_segment_relationship();

create trigger resource_device_locations_validate_relationship
before insert or update on public.resource_device_locations
for each row execute function public.validate_resource_device_location();

create trigger health_records_validate_relationship
before insert or update on public.health_records
for each row execute function public.validate_health_record_relationship();

-- ---------------------------------------------------------------------------
-- RLS and grants
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
create policy profiles_select_own on public.profiles
for select to authenticated using (id = auth.uid());
create policy profiles_insert_own on public.profiles
for insert to authenticated with check (id = auth.uid());
create policy profiles_update_own on public.profiles
for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_delete_own on public.profiles
for delete to authenticated using (id = auth.uid());

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'devices',
    'user_settings',
    'device_settings',
    'task_domains',
    'roadmaps',
    'roadmap_phases',
    'roadmap_milestones',
    'roadmap_checkpoints',
    'roadmap_progress_weights',
    'tasks',
    'task_checklist_items',
    'task_occurrences',
    'task_sessions',
    'session_segments',
    'session_commands',
    'sync_outbox',
    'task_demands',
    'task_checkpoints',
    'activity_intervals',
    'activity_contributions',
    'task_resources',
    'resource_annotations',
    'browser_tabs',
    'closed_browser_tabs',
    'browser_vault_items',
    'task_reminders',
    'reading_sessions',
    'task_notes',
    'quick_notes',
    'health_connections',
    'health_records',
    'health_daily_summaries',
    'cycle_preferences',
    'cycle_entries',
    'user_behavior_features',
    'coaching_recommendations'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid())', table_name || '_select_own', table_name);
    execute format('create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid())', table_name || '_insert_own', table_name);
    execute format('create policy %I on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', table_name || '_update_own', table_name);
    execute format('create policy %I on public.%I for delete to authenticated using (user_id = auth.uid())', table_name || '_delete_own', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
  end loop;
end $$;

alter table public.resource_device_locations enable row level security;
create policy resource_device_locations_select_own
on public.resource_device_locations
for select to authenticated
using (
  exists (
    select 1
    from public.task_resources r
    where r.id = resource_id and r.user_id = auth.uid()
  )
);
create policy resource_device_locations_insert_own
on public.resource_device_locations
for insert to authenticated
with check (
  exists (
    select 1
    from public.task_resources r
    join public.devices d on d.id = device_id
    where r.id = resource_id
      and r.user_id = auth.uid()
      and d.user_id = auth.uid()
  )
);
create policy resource_device_locations_update_own
on public.resource_device_locations
for update to authenticated
using (
  exists (
    select 1
    from public.task_resources r
    where r.id = resource_id and r.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.task_resources r
    join public.devices d on d.id = device_id
    where r.id = resource_id
      and r.user_id = auth.uid()
      and d.user_id = auth.uid()
  )
);
create policy resource_device_locations_delete_own
on public.resource_device_locations
for delete to authenticated
using (
  exists (
    select 1
    from public.task_resources r
    where r.id = resource_id and r.user_id = auth.uid()
  )
);

grant select, insert, update, delete on public.resource_device_locations to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant execute on function public.bootstrap_current_user() to authenticated;
grant execute on function public.apply_session_command(uuid, uuid, uuid, text, bigint, uuid, jsonb, timestamptz) to authenticated;
grant execute on function public.session_snapshot(uuid) to authenticated;

do $$
begin
  if to_regclass('realtime.messages') is not null then
    begin
      execute $policy$
        create policy taskmaster_runtime_broadcast_receive
        on realtime.messages
        for select
        to authenticated
        using (topic = 'taskmaster:user:' || auth.uid()::text || ':runtime')
      $policy$;
    exception
      when duplicate_object or insufficient_privilege then null;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Storage buckets and storage RLS
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public)
    values
      ('avatars', 'avatars', false),
      ('task-resources', 'task-resources', false)
    on conflict (id) do nothing;
  end if;
end $$;

do $$
begin
  if to_regclass('storage.objects') is not null then
    begin
      execute $policy$
        create policy taskmaster_storage_select_own
        on storage.objects
        for select
        to authenticated
        using (
          bucket_id in ('avatars', 'task-resources')
          and name like auth.uid()::text || '/%'
        )
      $policy$;
      execute $policy$
        create policy taskmaster_storage_insert_own
        on storage.objects
        for insert
        to authenticated
        with check (
          bucket_id in ('avatars', 'task-resources')
          and name like auth.uid()::text || '/%'
        )
      $policy$;
      execute $policy$
        create policy taskmaster_storage_update_own
        on storage.objects
        for update
        to authenticated
        using (
          bucket_id in ('avatars', 'task-resources')
          and name like auth.uid()::text || '/%'
        )
        with check (
          bucket_id in ('avatars', 'task-resources')
          and name like auth.uid()::text || '/%'
        )
      $policy$;
      execute $policy$
        create policy taskmaster_storage_delete_own
        on storage.objects
        for delete
        to authenticated
        using (
          bucket_id in ('avatars', 'task-resources')
          and name like auth.uid()::text || '/%'
        )
      $policy$;
    exception
      when duplicate_object or insufficient_privilege then null;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Publication hints for projects using Postgres changes alongside Broadcast.
-- Broadcast events are sent through realtime.messages by apply_session_command.
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'task_sessions'
    ) then
      alter publication supabase_realtime add table public.task_sessions;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'session_commands'
    ) then
      alter publication supabase_realtime add table public.session_commands;
    end if;
  end if;
end $$;

