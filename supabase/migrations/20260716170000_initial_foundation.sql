create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  locale text not null default 'en' check (locale in ('ar', 'en', 'de')),
  theme_choice text not null default 'dark_blue' check (theme_choice in ('dark_blue', 'black_gold', 'light')),
  timezone text not null default 'Africa/Cairo',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.user_settings (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  language text not null default 'en' check (language in ('ar', 'en', 'de')),
  theme_mode text not null default 'system' check (theme_mode in ('system', 'light', 'dark')),
  theme_choice text not null default 'dark_blue' check (theme_choice in ('dark_blue', 'black_gold', 'light')),
  compact_desktop boolean not null default false,
  comfortable_mobile boolean not null default true,
  font_scale numeric(3,2) not null default 1.00 check (font_scale between 0.80 and 1.40),
  reduced_motion boolean not null default false,
  high_contrast boolean not null default false,
  quiet_hours jsonb not null default '{}'::jsonb,
  work_focus_mode boolean not null default false,
  maximum_reminders_per_day integer not null default 6,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.devices (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  platform text not null check (platform in ('windows', 'android', 'web', 'other')),
  device_identifier text,
  last_seen_at timestamptz,
  allow_application_tracking boolean not null default false,
  allowlisted_app_categories text[] not null default '{}'::text[],
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, device_identifier)
);

create table public.device_tokens (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid references public.devices(id) on delete cascade,
  provider text not null check (provider in ('fcm', 'wns', 'local')),
  token text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, provider, token)
);

create table public.notification_preferences (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  global_enabled boolean not null default true,
  by_category jsonb not null default '{}'::jsonb,
  sound_enabled boolean not null default true,
  vibration_enabled boolean not null default true,
  desktop_toast_enabled boolean not null default true,
  android_persistent_timer boolean not null default true,
  snooze_options_minutes integer[] not null default array[10, 30, 60],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.categories (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  color_seed text not null default '#3B82F6',
  sort_order integer not null default 0,
  is_system boolean not null default false,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, name)
);

create table public.projects (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  category_id uuid references public.categories(id) on delete set null,
  description text not null default '',
  status text not null default 'active' check (status in ('active', 'paused', 'completed', 'archived')),
  exit_criteria jsonb not null default '{}'::jsonb,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, name)
);

create table public.roadmap_phases (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phase_number integer not null,
  period text not null,
  objective text not null,
  exit_evidence text not null,
  planned_start date,
  planned_finish date,
  completion_percentage integer not null default 0 check (completion_percentage between 0 and 100),
  confidence integer not null default 3 check (confidence between 1 and 5),
  review_date date,
  current_forecast date,
  original_baseline_date date,
  adjustment_reason text,
  approved_at timestamptz,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, phase_number)
);

create table public.tasks (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  category_id uuid references public.categories(id) on delete set null,
  category_name text not null default 'Programming Learning',
  project_id uuid references public.projects(id) on delete set null,
  project_name text,
  roadmap_phase_id uuid references public.roadmap_phases(id) on delete set null,
  roadmap_phase integer,
  priority text not null default 'normal' check (priority in ('critical', 'high', 'normal', 'low')),
  priority_rank integer not null default 2 check (priority_rank between 0 and 3),
  status text not null default 'planned' check (status in ('planned', 'in_progress', 'waiting', 'review_required', 'someday', 'completed', 'canceled')),
  start_date date,
  due_date date,
  estimated_pomodoros integer not null default 1 check (estimated_pomodoros >= 0),
  estimated_minutes integer not null default 25 check (estimated_minutes >= 0),
  actual_focused_minutes integer not null default 0 check (actual_focused_minutes >= 0),
  recurrence text,
  learning_resource_link text,
  launch_method text,
  notes text not null default '',
  checklist jsonb not null default '[]'::jsonb,
  tags text[] not null default '{}'::text[],
  progress_percentage integer not null default 0 check (progress_percentage between 0 and 100),
  difficulty integer not null default 2 check (difficulty between 1 and 5),
  energy_requirement integer not null default 2 check (energy_requirement between 1 and 5),
  context text,
  attachments jsonb not null default '[]'::jsonb,
  completion_evidence text,
  parent_task_id uuid references public.tasks(id) on delete set null,
  dependencies text[] not null default '{}'::text[],
  reminder_rules jsonb not null default '{}'::jsonb,
  next_action text,
  postponed_count integer not null default 0,
  started_without_progress_count integer not null default 0,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  deleted_at timestamptz
);

create table public.task_dependencies (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  depends_on_task_id uuid not null references public.tasks(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (task_id, depends_on_task_id)
);

create table public.task_checklist_items (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  is_done boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.task_recurrences (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  rule jsonb not null,
  next_occurrence date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.task_resources (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  resource_type text not null,
  title text not null,
  url text,
  launch_mode text not null default 'external_browser',
  trusted_domain boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.task_attachments (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  storage_path text not null,
  display_name text not null,
  mime_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.calendar_blocks (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  category_id uuid references public.categories(id) on delete set null,
  title text not null,
  block_type text not null default 'planned' check (block_type in ('planned', 'protected', 'workday', 'meeting', 'break', 'review')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.pomodoro_presets (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  focus_minutes integer not null default 25,
  short_break_minutes integer not null default 5,
  long_break_minutes integer not null default 20,
  long_break_after integer not null default 4,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, name)
);

create table public.sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  category_id uuid references public.categories(id) on delete set null,
  category_name text,
  project_id uuid references public.projects(id) on delete set null,
  project_name text,
  device_id uuid references public.devices(id) on delete set null,
  started_at timestamptz not null,
  ended_at timestamptz,
  gross_duration_seconds integer not null default 0,
  active_duration_seconds integer not null default 0,
  idle_duration_seconds integer not null default 0,
  paused_duration_seconds integer not null default 0,
  pomodoro_number integer,
  tracking_mode text not null default 'interactive' check (tracking_mode in ('interactive', 'video', 'reading', 'manual')),
  completion_status text not null default 'in_progress' check (completion_status in ('in_progress', 'completed', 'unsuccessful', 'discarded')),
  progress_update text,
  notes text not null default '',
  interruption_count integer not null default 0,
  application_name text,
  learning_url text,
  data_honesty_source text not null default 'timer_recorded' check (data_honesty_source in ('planned', 'timer_recorded', 'verified_active', 'manual', 'estimated_external', 'corrected')),
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.session_segments (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.sessions(id) on delete cascade,
  segment_type text not null check (segment_type in ('active', 'idle', 'paused', 'break', 'interruption')),
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_seconds integer not null default 0,
  optional_application_name text,
  optional_window_category text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.session_interruptions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.sessions(id) on delete cascade,
  reason text not null check (reason in ('phone_call', 'work_request', 'family_need', 'technical_problem', 'distraction', 'break', 'task_completed', 'changed_priority', 'other')),
  note text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.pomodoro_cycles (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  preset_id uuid references public.pomodoro_presets(id) on delete set null,
  cycle_number integer not null default 1,
  started_at timestamptz not null,
  completed_at timestamptz,
  status text not null default 'running' check (status in ('running', 'completed', 'stopped', 'discarded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.manual_time_adjustments (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  adjustment_minutes integer not null,
  source_before text not null,
  source_after text not null,
  reason text not null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.progress_updates (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  update_text text not null,
  confidence integer check (confidence between 1 and 5),
  next_action text,
  evidence_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.daily_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  review_date date not null,
  main_achievement text,
  main_problem text,
  energy_level integer check (energy_level between 1 and 5),
  focus_quality integer check (focus_quality between 1 and 5),
  lesson_learned text,
  first_task_for_tomorrow text,
  optional_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, review_date)
);

create table public.weekly_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  week_starts_on date not null,
  planned_focus_minutes integer not null default 0,
  completed_focus_minutes integer not null default 0,
  programming_output text,
  german_progress text,
  github_activity text,
  main_job_workload text,
  household_balance text,
  family_social_balance text,
  repeatedly_postponed jsonb not null default '[]'::jsonb,
  next_week_capacity_minutes integer,
  recommended_schedule_changes jsonb not null default '[]'::jsonb,
  approved_next_plan_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, week_starts_on)
);

create table public.monthly_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  month_starts_on date not null,
  summary text,
  category_distribution jsonb not null default '{}'::jsonb,
  planned_vs_actual jsonb not null default '{}'::jsonb,
  roadmap_forecast text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, month_starts_on)
);

create table public.skill_assessments (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  skill_area text not null,
  score integer check (score between 1 and 100),
  confidence integer check (confidence between 1 and 5),
  unresolved_topics text[] not null default '{}'::text[],
  assessed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.completion_evidence (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  roadmap_item_id uuid,
  evidence_type text not null,
  title text not null,
  url text,
  storage_path text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.roadmap_items (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phase_id uuid references public.roadmap_phases(id) on delete cascade,
  topic text not null,
  planned_start date,
  planned_finish date,
  prerequisites text[] not null default '{}'::text[],
  estimated_hours numeric(8,2) not null default 0,
  importance integer not null default 3 check (importance between 1 and 5),
  completion_percentage integer not null default 0 check (completion_percentage between 0 and 100),
  confidence integer not null default 3 check (confidence between 1 and 5),
  evidence_requirements jsonb not null default '[]'::jsonb,
  related_resources jsonb not null default '[]'::jsonb,
  related_projects jsonb not null default '[]'::jsonb,
  review_date date,
  current_forecast date,
  original_baseline_date date,
  adjustment_reason text,
  sync_version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.roadmap_dependencies (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  roadmap_item_id uuid not null references public.roadmap_items(id) on delete cascade,
  depends_on_item_id uuid not null references public.roadmap_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (roadmap_item_id, depends_on_item_id)
);

create table public.roadmap_forecasts (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phase_id uuid references public.roadmap_phases(id) on delete cascade,
  generated_at timestamptz not null default now(),
  trailing_four_week_minutes integer not null default 0,
  completion_rate numeric(5,2),
  forecast_finish date,
  recommendation text not null,
  inputs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.roadmap_adjustment_proposals (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phase_id uuid references public.roadmap_phases(id) on delete cascade,
  proposal text not null,
  old_date date,
  proposed_date date,
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.roadmap_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  snapshot_at timestamptz not null default now(),
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.relationships (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  relationship text not null,
  preferred_contact_frequency_days integer not null default 14,
  last_call date,
  last_visit date,
  next_suggested_contact date,
  birthday date,
  important_notes text,
  preferred_contact_method text,
  availability_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.relationship_interactions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  relationship_id uuid not null references public.relationships(id) on delete cascade,
  interaction_type text not null check (interaction_type in ('call', 'message', 'visit', 'gathering', 'other')),
  happened_at timestamptz not null default now(),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.household_lists (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  list_type text not null default 'shopping' check (list_type in ('shopping', 'routine', 'maintenance', 'documents', 'other')),
  preferred_day integer check (preferred_day between 0 and 6),
  required_location text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.household_list_items (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  list_id uuid not null references public.household_lists(id) on delete cascade,
  title text not null,
  estimated_minutes integer not null default 0,
  is_done boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.learning_resources (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  resource_type text not null,
  url text,
  local_path text,
  launch_mode text not null default 'external_browser',
  trusted_domain boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.learning_topics (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  category text not null,
  status text not null default 'planned',
  confidence integer check (confidence between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.learning_topic_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  topic_id uuid not null references public.learning_topics(id) on delete cascade,
  review_date date not null,
  understood_well boolean,
  remains_unclear text,
  needs_review boolean not null default false,
  wrote_code boolean not null default false,
  committed_to_github boolean not null default false,
  next_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.german_skills (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  cefr_level text not null default 'A1',
  current_target text,
  vocabulary integer not null default 0,
  grammar integer not null default 0,
  listening_minutes integer not null default 0,
  reading_minutes integer not null default 0,
  writing_samples integer not null default 0,
  speaking_sessions integer not null default 0,
  technical_german_notes text,
  interview_german_notes text,
  review_queue jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.german_activity (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  activity_type text not null,
  minutes integer not null default 0,
  resource text,
  evidence text,
  confidence integer check (confidence between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles',
    'user_settings',
    'devices',
    'device_tokens',
    'notification_preferences',
    'categories',
    'projects',
    'roadmap_phases',
    'tasks',
    'task_dependencies',
    'task_checklist_items',
    'task_recurrences',
    'task_resources',
    'task_attachments',
    'calendar_blocks',
    'pomodoro_presets',
    'sessions',
    'session_segments',
    'session_interruptions',
    'pomodoro_cycles',
    'manual_time_adjustments',
    'progress_updates',
    'daily_reviews',
    'weekly_reviews',
    'monthly_reviews',
    'skill_assessments',
    'completion_evidence',
    'roadmap_items',
    'roadmap_dependencies',
    'roadmap_forecasts',
    'roadmap_adjustment_proposals',
    'roadmap_snapshots',
    'relationships',
    'relationship_interactions',
    'household_lists',
    'household_list_items',
    'learning_resources',
    'learning_topics',
    'learning_topic_reviews',
    'german_skills',
    'german_activity'
  ] loop
    execute format('create trigger set_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()', table_name, table_name);
  end loop;
end;
$$;

alter table public.profiles enable row level security;
create policy profiles_select_own on public.profiles for select using (id = auth.uid());
create policy profiles_update_own on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'user_settings',
    'devices',
    'device_tokens',
    'notification_preferences',
    'categories',
    'projects',
    'roadmap_phases',
    'tasks',
    'task_dependencies',
    'task_checklist_items',
    'task_recurrences',
    'task_resources',
    'task_attachments',
    'calendar_blocks',
    'pomodoro_presets',
    'sessions',
    'session_segments',
    'session_interruptions',
    'pomodoro_cycles',
    'manual_time_adjustments',
    'progress_updates',
    'daily_reviews',
    'weekly_reviews',
    'monthly_reviews',
    'skill_assessments',
    'completion_evidence',
    'roadmap_items',
    'roadmap_dependencies',
    'roadmap_forecasts',
    'roadmap_adjustment_proposals',
    'roadmap_snapshots',
    'relationships',
    'relationship_interactions',
    'household_lists',
    'household_list_items',
    'learning_resources',
    'learning_topics',
    'learning_topic_reviews',
    'german_skills',
    'german_activity'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('create policy %I on public.%I for select using (user_id = auth.uid())', table_name || '_select_own', table_name);
    execute format('create policy %I on public.%I for insert with check (user_id = auth.uid())', table_name || '_insert_own', table_name);
    execute format('create policy %I on public.%I for update using (user_id = auth.uid()) with check (user_id = auth.uid())', table_name || '_update_own', table_name);
    execute format('create policy %I on public.%I for delete using (user_id = auth.uid())', table_name || '_delete_own', table_name);
  end loop;
end;
$$;

create index categories_user_id_idx on public.categories(user_id);
create index projects_user_status_idx on public.projects(user_id, status);
create index tasks_user_due_status_idx on public.tasks(user_id, due_date, status) where deleted_at is null;
create index tasks_user_category_idx on public.tasks(user_id, category_id) where deleted_at is null;
create index tasks_user_project_idx on public.tasks(user_id, project_id) where deleted_at is null;
create index tasks_user_roadmap_idx on public.tasks(user_id, roadmap_phase_id) where deleted_at is null;
create index sessions_user_started_idx on public.sessions(user_id, started_at desc) where deleted_at is null;
create index sessions_user_task_idx on public.sessions(user_id, task_id) where deleted_at is null;
create index session_segments_session_idx on public.session_segments(session_id, started_at);
create index daily_reviews_user_date_idx on public.daily_reviews(user_id, review_date desc);
create index weekly_reviews_user_week_idx on public.weekly_reviews(user_id, week_starts_on desc);
create index roadmap_items_user_phase_idx on public.roadmap_items(user_id, phase_id);
create index german_activity_user_date_idx on public.german_activity(user_id, activity_date desc);
create index calendar_blocks_user_start_idx on public.calendar_blocks(user_id, starts_at);

create or replace function public.handle_new_user_defaults()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;

  insert into public.user_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.categories (user_id, name, color_seed, sort_order, is_system)
  values
    (new.id, 'Main Job', '#3B82F6', 10, true),
    (new.id, 'Programming Learning', '#22D3EE', 20, true),
    (new.id, 'Programming Practice', '#06B6D4', 30, true),
    (new.id, 'Project Building', '#14B8A6', 40, true),
    (new.id, 'Algorithms', '#A855F7', 50, true),
    (new.id, 'Programming Books', '#6366F1', 60, true),
    (new.id, 'German', '#F59E0B', 70, true),
    (new.id, 'Family', '#EC4899', 80, true),
    (new.id, 'Friends and Sisters', '#F97316', 90, true),
    (new.id, 'Household', '#84CC16', 100, true),
    (new.id, 'Shopping and Errands', '#EAB308', 110, true),
    (new.id, 'Health and Exercise', '#22C55E', 120, true),
    (new.id, 'Personal Administration', '#64748B', 130, true),
    (new.id, 'Weekly Review', '#0EA5E9', 140, true),
    (new.id, 'Rest and Recreation', '#10B981', 150, true)
  on conflict (user_id, name) do nothing;

  insert into public.pomodoro_presets (
    user_id,
    name,
    focus_minutes,
    short_break_minutes,
    long_break_minutes,
    long_break_after,
    is_default
  )
  values
    (new.id, '25/5 default', 25, 5, 20, 4, true),
    (new.id, '50/10 deep work', 50, 10, 20, 4, false),
    (new.id, '45/10 programming', 45, 10, 20, 4, false),
    (new.id, '25/5 German', 25, 5, 20, 4, false),
    (new.id, '15/5 low-energy study', 15, 5, 15, 4, false),
    (new.id, '90/20 project building', 90, 20, 20, 2, false)
  on conflict (user_id, name) do nothing;

  insert into public.roadmap_phases (
    user_id,
    phase_number,
    period,
    objective,
    exit_evidence,
    planned_start,
    planned_finish,
    original_baseline_date
  )
  values
    (new.id, 1, 'Jul-Sep 2026', 'Excellent HTML and CSS', 'Responsive projects, semantic HTML, accessibility, Git history and independent rebuild', date '2026-07-01', date '2026-09-30', date '2026-09-30'),
    (new.id, 2, 'Oct-Dec 2026', 'JavaScript fundamentals', 'Multiple independent applications using DOM, APIs, modules and asynchronous JavaScript', date '2026-10-01', date '2026-12-31', date '2026-12-31'),
    (new.id, 3, 'Jan-Mar 2027', 'Advanced JavaScript and introductory DSA', 'Concept demonstrations, regular algorithm practice and independent debugging', date '2027-01-01', date '2027-03-31', date '2027-03-31'),
    (new.id, 4, 'Apr-Jun 2027', 'React and TypeScript basics', 'Deployed React applications with routing, forms, state management and typed code', date '2027-04-01', date '2027-06-30', date '2027-06-30'),
    (new.id, 5, 'Jul-Sep 2027', 'Backend engineering', 'Authenticated APIs, PostgreSQL, authorization and complete backend projects', date '2027-07-01', date '2027-09-30', date '2027-09-30'),
    (new.id, 6, 'Oct-Dec 2027', 'Deployment and operations', 'Dockerized and deployed applications with CI/CD and production documentation', date '2027-10-01', date '2027-12-31', date '2027-12-31'),
    (new.id, 7, '2028', 'Computer science fundamentals', 'Demonstrated knowledge through projects, notes, tests and algorithm practice', date '2028-01-01', date '2028-12-31', date '2028-12-31'),
    (new.id, 8, '2029', 'Advanced engineering', 'Scalable multi-user systems, caching, messaging, cloud and security', date '2029-01-01', date '2029-12-31', date '2029-12-31'),
    (new.id, 9, '2030', 'Interview and employment preparation', 'Interview readiness, portfolio, CV, German interviews and targeted applications', date '2030-01-01', date '2030-12-31', date '2030-12-31')
  on conflict (user_id, phase_number) do nothing;

  insert into public.german_skills (user_id, cefr_level, current_target)
  values (new.id, 'A1', 'A1 to A2 by the end of 2026')
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user_defaults();
