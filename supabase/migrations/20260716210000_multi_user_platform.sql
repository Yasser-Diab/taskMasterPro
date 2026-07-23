-- Multi-user conversion, owner-protected template installation, task notes,
-- interruptions, adaptive scheduling, smart notifications and task workspaces.

alter table public.profiles
  add column if not exists onboarding_completed boolean not null default false;

create table if not exists public.user_roles (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role text not null default 'user' check (role in ('owner', 'admin', 'support', 'user')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.user_settings
  add column if not exists ui_click_sounds boolean not null default true,
  add column if not exists ui_click_volume numeric(3,2) not null default 0.65 check (ui_click_volume between 0 and 1),
  add column if not exists notification_sounds boolean not null default true,
  add column if not exists pomodoro_sounds boolean not null default true,
  add column if not exists completion_sounds boolean not null default true,
  add column if not exists error_sounds boolean not null default true,
  add column if not exists haptic_feedback boolean not null default true,
  add column if not exists wake_up_time time not null default time '05:00',
  add column if not exists bedtime time not null default time '23:30',
  add column if not exists work_start_time time not null default time '09:00',
  add column if not exists work_end_time time not null default time '17:30',
  add column if not exists workdays integer[] not null default array[6, 7, 1, 2, 3, 4],
  add column if not exists lunch_duration_minutes integer not null default 45,
  add column if not exists commute_to_work_minutes integer not null default 30,
  add column if not exists commute_home_minutes integer not null default 30,
  add column if not exists max_daily_study_minutes integer not null default 180,
  add column if not exists max_weekly_study_minutes integer not null default 780,
  add column if not exists weekly_review_time text not null default 'Friday 06:00';

alter table public.tasks
  alter column category_name set default 'Personal',
  add column if not exists preferred_time_window text,
  add column if not exists minimum_duration_minutes integer not null default 0,
  add column if not exists maximum_duration_minutes integer not null default 0,
  add column if not exists flexibility_level text not null default 'flexible' check (flexibility_level in ('fixed', 'protected', 'flexible', 'highly_flexible')),
  add column if not exists can_be_split boolean not null default true,
  add column if not exists can_move_to_another_day boolean not null default true,
  add column if not exists minimum_gap_before_work_minutes integer not null default 0,
  add column if not exists minimum_gap_before_sleep_minutes integer not null default 60,
  add column if not exists workspace_enabled boolean not null default false,
  add column if not exists workspace_type text not null default 'none' check (workspace_type in ('none', 'in_app_browser', 'external_browser', 'local_file_or_folder', 'application_shortcut')),
  add column if not exists workspace_starting_url text,
  add column if not exists workspace_home_url text,
  add column if not exists workspace_resource_title text,
  add column if not exists workspace_browser_mode text not null default 'interactive' check (workspace_browser_mode in ('interactive', 'video', 'reading')),
  add column if not exists workspace_allowed_domains text[] not null default '{}'::text[],
  add column if not exists workspace_restore_last_page boolean not null default true,
  add column if not exists workspace_open_automatically boolean not null default false,
  add column if not exists workspace_preferred_layout text not null default 'side_by_side' check (workspace_preferred_layout in ('side_by_side', 'full_width')),
  add column if not exists workspace_preferred_dock_state text not null default 'docked' check (workspace_preferred_dock_state in ('docked', 'detached')),
  add column if not exists workspace_allow_external_navigation boolean not null default true,
  add column if not exists workspace_open_unsupported_externally boolean not null default true,
  add column if not exists workspace_last_url text,
  add column if not exists workspace_open_tabs jsonb not null default '[]'::jsonb,
  add column if not exists workspace_window_state jsonb not null default '{}'::jsonb;

-- Safely migrate old task statuses to the new canonical values.

alter table public.tasks
  drop constraint if exists tasks_status_check;

-- Remove the old default before changing the accepted values.
alter table public.tasks
  alter column status drop default;

-- Convert all known old values.
update public.tasks
set status =
  case lower(btrim(coalesce(status, '')))
    -- Old values
    when 'planned' then 'not_started'
    when 'in_progress' then 'running'
    when 'canceled' then 'cancelled'

    -- Already valid new values
    when 'not_started' then 'not_started'
    when 'ready' then 'ready'
    when 'running' then 'running'
    when 'paused' then 'paused'
    when 'interrupted' then 'interrupted'
    when 'completed' then 'completed'
    when 'cancelled' then 'cancelled'
    when 'waiting' then 'waiting'
    when 'overdue' then 'overdue'
    when 'review_required' then 'review_required'
    when 'someday' then 'someday'

    -- Additional common legacy spellings
    when 'not started' then 'not_started'
    when 'pending' then 'not_started'
    when 'todo' then 'not_started'
    when 'to_do' then 'not_started'
    when 'in progress' then 'running'
    when 'active' then 'running'
    when 'started' then 'running'
    when 'on_hold' then 'paused'
    when 'on hold' then 'paused'
    when 'finished' then 'completed'
    when 'done' then 'completed'
    when 'complete' then 'completed'

    -- Preserve an unknown value so the validation below reports it.
    else lower(btrim(coalesce(status, '')))
  end;

-- Stop with a clear error if an unknown status still exists.
do $$
declare
  invalid_statuses text;
begin
  select string_agg(
           distinct quote_literal(status),
           ', '
           order by quote_literal(status)
         )
  into invalid_statuses
  from public.tasks
  where status not in (
    'not_started',
    'ready',
    'running',
    'paused',
    'interrupted',
    'completed',
    'cancelled',
    'waiting',
    'overdue',
    'review_required',
    'someday'
  );

  if invalid_statuses is not null then
    raise exception
      'Unknown task status values remain: %',
      invalid_statuses;
  end if;
end;
$$;

-- Set the new default.
alter table public.tasks
  alter column status set default 'not_started';

-- Recreate the new constraint.
alter table public.tasks
  add constraint tasks_status_check
  check (
    status in (
      'not_started',
      'ready',
      'running',
      'paused',
      'interrupted',
      'completed',
      'cancelled',
      'waiting',
      'overdue',
      'review_required',
      'someday'
    )
  );

create table if not exists public.schedule_anchors (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  anchor_type text not null,
  title text not null,
  days_of_week integer[] not null default '{}'::integer[],
  starts_at time,
  ends_at time,
  is_fixed boolean not null default true,
  is_protected boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.availability_windows (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  day_of_week integer not null check (day_of_week between 1 and 7),
  starts_at time not null,
  ends_at time not null,
  availability_type text not null default 'study' check (availability_type in ('study', 'work', 'family', 'personal', 'household', 'blocked')),
  energy_level integer check (energy_level between 1 and 5),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.task_templates (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  template_key text not null,
  title text not null,
  description text not null default '',
  payload jsonb not null default '{}'::jsonb,
  is_private boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, template_key)
);

create table if not exists public.template_versions (
  id uuid primary key default extensions.gen_random_uuid(),
  template_key text not null,
  template_version integer not null,
  title text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (template_key, template_version)
);

create table if not exists public.user_template_installations (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  template_key text not null,
  template_version integer not null,
  installed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, template_key, template_version)
);

create table if not exists public.learning_goals (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null,
  current_level text,
  target_level text,
  weekly_time_target_minutes integer not null default 0,
  preferred_learning_methods text[] not null default '{}'::text[],
  current_resources jsonb not null default '[]'::jsonb,
  difficulty integer check (difficulty between 1 and 5),
  deadline date,
  progress_evidence jsonb not null default '[]'::jsonb,
  topics_needing_review text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.learning_resources
  add column if not exists name text,
  add column if not exists website_url text,
  add column if not exists subject text,
  add column if not exists topic text,
  add column if not exists required_level text,
  add column if not exists language text,
  add column if not exists free_or_paid text check (free_or_paid in ('free', 'paid', 'mixed')),
  add column if not exists trusted_status text not null default 'trusted' check (trusted_status in ('trusted', 'needs_review', 'blocked')),
  add column if not exists owner_admin_approved boolean not null default false,
  add column if not exists last_verification_date date,
  add column if not exists description text,
  add column if not exists supported_platforms text[] not null default '{}'::text[],
  add column if not exists is_catalog_entry boolean not null default false;

create table if not exists public.resource_recommendations (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  learning_goal_id uuid references public.learning_goals(id) on delete cascade,
  resource_id uuid references public.learning_resources(id) on delete set null,
  recommendation text not null,
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'dismissed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.recommendation_feedback (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recommendation_id uuid references public.resource_recommendations(id) on delete cascade,
  feedback text not null check (feedback in ('useful', 'not_relevant', 'do_not_suggest_again')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.adaptive_schedule_proposals (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  reason text not null,
  source_change jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.schedule_proposal_changes (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  proposal_id uuid not null references public.adaptive_schedule_proposals(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  old_starts_at timestamptz,
  old_ends_at timestamptz,
  proposed_starts_at timestamptz,
  proposed_ends_at timestamptz,
  change_reason text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.smart_notifications (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_category text not null,
  title text not null,
  body text not null,
  language text not null default 'en',
  scheduled_for timestamptz,
  delivered_at timestamptz,
  dismissed_at timestamptz,
  feedback text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.household_routines (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  recurrence_rule jsonb not null default '{}'::jsonb,
  stages jsonb not null default '[]'::jsonb,
  preferred_days integer[] not null default '{}'::integer[],
  estimated_active_minutes integer not null default 0,
  reminder_rules jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, title)
);

create table if not exists public.task_notes (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  note_type text not null default 'general',
  title text not null default '',
  body text not null,
  is_pinned boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.task_interruptions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  interruption_type_id uuid,
  interruption_type text not null default 'other',
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  duration_seconds integer not null default 0,
  paused_task boolean not null default true,
  is_work_related boolean not null default false,
  description text not null default '',
  is_resolved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.task_activity_history (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  activity_type text not null,
  old_value jsonb,
  new_value jsonb,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create or replace function public.is_owner(check_user uuid default auth.uid())
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = check_user
      and role = 'owner'
      and deleted_at is null
  );
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'user_roles',
    'schedule_anchors',
    'availability_windows',
    'task_templates',
    'template_versions',
    'user_template_installations',
    'learning_goals',
    'resource_recommendations',
    'recommendation_feedback',
    'adaptive_schedule_proposals',
    'schedule_proposal_changes',
    'smart_notifications',
    'household_routines',
    'task_notes',
    'task_interruptions',
    'task_activity_history'
  ] loop
    begin
      execute format('create trigger set_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()', table_name, table_name);
    exception
      when duplicate_object then null;
    end;
  end loop;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'schedule_anchors',
    'availability_windows',
    'task_templates',
    'user_template_installations',
    'learning_goals',
    'resource_recommendations',
    'recommendation_feedback',
    'adaptive_schedule_proposals',
    'schedule_proposal_changes',
    'smart_notifications',
    'household_routines',
    'task_notes',
    'task_interruptions',
    'task_activity_history'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_select_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_insert_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete_own', table_name);
    execute format('create policy %I on public.%I for select using (user_id = auth.uid())', table_name || '_select_own', table_name);
    execute format('create policy %I on public.%I for insert with check (user_id = auth.uid())', table_name || '_insert_own', table_name);
    execute format('create policy %I on public.%I for update using (user_id = auth.uid()) with check (user_id = auth.uid())', table_name || '_update_own', table_name);
    execute format('create policy %I on public.%I for delete using (user_id = auth.uid())', table_name || '_delete_own', table_name);
  end loop;
end;
$$;

alter table public.user_roles enable row level security;
drop policy if exists user_roles_select_own on public.user_roles;
create policy user_roles_select_own on public.user_roles
  for select using (user_id = auth.uid());

alter table public.template_versions enable row level security;
drop policy if exists template_versions_owner_select on public.template_versions;
create policy template_versions_owner_select on public.template_versions
  for select using (public.is_owner());

create index if not exists user_roles_user_role_idx on public.user_roles(user_id, role);
create index if not exists task_notes_user_task_idx on public.task_notes(user_id, task_id) where deleted_at is null;
create index if not exists task_interruptions_user_task_idx on public.task_interruptions(user_id, task_id) where deleted_at is null;
create index if not exists schedule_anchors_user_type_idx on public.schedule_anchors(user_id, anchor_type) where deleted_at is null;
create index if not exists availability_windows_user_day_idx on public.availability_windows(user_id, day_of_week) where deleted_at is null;
create index if not exists user_template_installations_user_template_idx on public.user_template_installations(user_id, template_key, template_version);
create index if not exists learning_goals_user_subject_idx on public.learning_goals(user_id, subject) where deleted_at is null;
create index if not exists smart_notifications_user_scheduled_idx on public.smart_notifications(user_id, scheduled_for) where deleted_at is null;
create index if not exists tasks_workspace_user_idx on public.tasks(user_id, workspace_enabled, workspace_type) where deleted_at is null;

create or replace function public.handle_new_user_defaults()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  preferred_locale text := coalesce(new.raw_user_meta_data->>'preferred_language', 'en');
  display text := coalesce(new.raw_user_meta_data->>'full_name', new.email);
  assigned_role text := case
    when lower(coalesce(new.email, '')) = 'yasserdiabhassan@gmail.com' then 'owner'
    else 'user'
  end;
begin
  insert into public.profiles (id, email, display_name, locale, onboarding_completed)
  values (new.id, new.email, display, preferred_locale, false)
  on conflict (id) do update
    set email = excluded.email,
        display_name = coalesce(public.profiles.display_name, excluded.display_name),
        locale = coalesce(public.profiles.locale, excluded.locale);

  insert into public.user_settings (user_id, language)
  values (new.id, preferred_locale)
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.user_roles (user_id, role)
  values (new.id, assigned_role)
  on conflict (user_id) do update
    set role = case
      when public.user_roles.role = 'owner' then 'owner'
      else excluded.role
    end;

  insert into public.pomodoro_presets (
    user_id, name, focus_minutes, short_break_minutes, long_break_minutes,
    long_break_after, is_default
  )
  values (new.id, '25/5 default', 25, 5, 20, 4, true)
  on conflict (user_id, name) do nothing;

  return new;
end;
$$;

insert into public.user_roles (user_id, role)
select id, 'owner'
from auth.users
where lower(email) = 'yasserdiabhassan@gmail.com'
on conflict (user_id) do update set role = 'owner';

create or replace function public.install_owner_template_if_needed()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user uuid := auth.uid();
  inserted_count integer := 0;
  phase_one uuid;
begin
  if target_user is null or not public.is_owner(target_user) then
    raise exception 'owner role required';
  end if;

  insert into public.user_template_installations (user_id, template_key, template_version)
  values (target_user, 'yasser_roadmap_2026_2030', 1)
  on conflict (user_id, template_key, template_version) do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count = 0 then
    return jsonb_build_object('installed', false, 'template_key', 'yasser_roadmap_2026_2030', 'template_version', 1);
  end if;

  update public.user_settings
  set wake_up_time = time '05:00',
      bedtime = time '23:30',
      work_start_time = time '09:00',
      work_end_time = time '17:30',
      workdays = array[6, 7, 1, 2, 3, 4],
      max_weekly_study_minutes = 780
  where user_id = target_user;

  insert into public.categories (user_id, name, color_seed, sort_order, is_system)
  values
    (target_user, 'Main Job', '#3B82F6', 10, true),
    (target_user, 'Programming Learning', '#22D3EE', 20, true),
    (target_user, 'Programming Practice', '#06B6D4', 30, true),
    (target_user, 'Project Building', '#14B8A6', 40, true),
    (target_user, 'Algorithms', '#A855F7', 50, true),
    (target_user, 'Programming Books', '#6366F1', 60, true),
    (target_user, 'German', '#F59E0B', 70, true),
    (target_user, 'Family', '#EC4899', 80, true),
    (target_user, 'Friends and Sisters', '#F97316', 90, true),
    (target_user, 'Household', '#84CC16', 100, true),
    (target_user, 'Weekly Review', '#0EA5E9', 140, true),
    (target_user, 'Rest and Recreation', '#10B981', 150, true)
  on conflict (user_id, name) do nothing;

  insert into public.pomodoro_presets (
    user_id, name, focus_minutes, short_break_minutes, long_break_minutes,
    long_break_after, is_default
  )
  values
    (target_user, '50/10 deep work', 50, 10, 20, 4, false),
    (target_user, '45/10 programming', 45, 10, 20, 4, false),
    (target_user, '25/5 German', 25, 5, 20, 4, false),
    (target_user, '15/5 low-energy study', 15, 5, 15, 4, false),
    (target_user, '90/20 project building', 90, 20, 20, 2, false)
  on conflict (user_id, name) do nothing;

  insert into public.schedule_anchors (user_id, anchor_type, title, days_of_week, starts_at, ends_at, is_fixed, is_protected)
  values
    (target_user, 'wake', 'Wake up', array[1,2,3,4,5,6,7], time '05:00', time '05:00', true, true),
    (target_user, 'sleep', 'Protected sleep', array[1,2,3,4,5,6,7], time '23:30', time '05:00', true, true),
    (target_user, 'work', 'Main job', array[6,7,1,2,3,4], time '09:00', time '17:30', true, true),
    (target_user, 'day_off', 'Friday off', array[5], null, null, true, true),
    (target_user, 'family', 'Daily family time', array[6,7,1,2,3,4], time '19:00', time '21:00', true, true)
  on conflict do nothing;

  insert into public.household_routines (user_id, title, recurrence_rule, stages, preferred_days, estimated_active_minutes, reminder_rules)
  values (
    target_user,
    'Laundry',
    '{"frequency":"twice_weekly"}'::jsonb,
    '[{"title":"Start washing","active_minutes":10},{"title":"Transfer or hang clothes","active_minutes":10},{"title":"Fold and store clothes","active_minutes":20}]'::jsonb,
    array[2,5],
    40,
    '{"between_stages":true}'::jsonb
  )
  on conflict (user_id, title) do nothing;

  insert into public.roadmap_phases (
    user_id, phase_number, period, objective, exit_evidence, planned_start,
    planned_finish, original_baseline_date
  )
  values
    (target_user, 1, 'Jul-Sep 2026', 'Excellent HTML and CSS', 'Responsive projects, semantic HTML, accessibility, Git history and independent rebuild', date '2026-07-01', date '2026-09-30', date '2026-09-30'),
    (target_user, 2, 'Oct-Dec 2026', 'JavaScript fundamentals', 'Multiple independent applications using DOM, APIs, modules and asynchronous JavaScript', date '2026-10-01', date '2026-12-31', date '2026-12-31'),
    (target_user, 3, 'Jan-Mar 2027', 'Advanced JavaScript and introductory DSA', 'Concept demonstrations, regular algorithm practice and independent debugging', date '2027-01-01', date '2027-03-31', date '2027-03-31'),
    (target_user, 4, 'Apr-Jun 2027', 'React and TypeScript basics', 'Deployed React applications with routing, forms, state management and typed code', date '2027-04-01', date '2027-06-30', date '2027-06-30'),
    (target_user, 5, 'Jul-Sep 2027', 'Backend engineering', 'Authenticated APIs, PostgreSQL, authorization and complete backend projects', date '2027-07-01', date '2027-09-30', date '2027-09-30'),
    (target_user, 6, 'Oct-Dec 2027', 'Deployment and operations', 'Dockerized and deployed applications with CI/CD and production documentation', date '2027-10-01', date '2027-12-31', date '2027-12-31'),
    (target_user, 7, '2028', 'Computer science fundamentals', 'Demonstrated knowledge through projects, notes, tests and algorithm practice', date '2028-01-01', date '2028-12-31', date '2028-12-31'),
    (target_user, 8, '2029', 'Advanced engineering', 'Scalable multi-user systems, caching, messaging, cloud and security', date '2029-01-01', date '2029-12-31', date '2029-12-31'),
    (target_user, 9, '2030', 'Interview and employment preparation', 'Interview readiness, portfolio, CV, German interviews and targeted applications', date '2030-01-01', date '2030-12-31', date '2030-12-31')
  on conflict (user_id, phase_number) do nothing;

  select id into phase_one from public.roadmap_phases
  where user_id = target_user and phase_number = 1;

  insert into public.roadmap_items (user_id, phase_id, topic, planned_start, planned_finish, estimated_hours, importance, evidence_requirements)
  values
    (target_user, phase_one, 'Semantic HTML and accessibility fundamentals', date '2026-07-01', date '2026-07-31', 25, 5, '["responsive rebuild","accessibility checklist","Git history"]'::jsonb),
    (target_user, phase_one, 'CSS layout, Flexbox and Grid', date '2026-08-01', date '2026-08-31', 35, 5, '["independent layout projects","mobile support"]'::jsonb),
    (target_user, phase_one, 'HTML/CSS six-month rebuild assessment', date '2026-09-01', date '2026-09-30', 20, 5, '["independent rebuild","README","deployment"]'::jsonb)
  on conflict do nothing;

  insert into public.learning_goals (user_id, subject, current_level, target_level, weekly_time_target_minutes, preferred_learning_methods)
  values
    (target_user, 'Software Engineering', 'HTML/CSS beginner', 'Employment-ready full-stack engineer', 660, array['projects','documentation','practice']),
    (target_user, 'German', 'A1', 'B2/C1 professional and interview fluency', 180, array['vocabulary','listening','speaking','grammar'])
  on conflict do nothing;

  insert into public.learning_resources (
    user_id, title, resource_type, url, launch_mode, trusted_domain,
    name, website_url, subject, topic, required_level, language, free_or_paid,
    trusted_status, owner_admin_approved, last_verification_date,
    description, supported_platforms, is_catalog_entry
  )
  values
    (target_user, 'Hasoub', 'course', 'https://academy.hsoub.com/', 'embedded_browser', true, 'Hasoub', 'https://academy.hsoub.com/', 'Programming', 'Arabic programming courses', 'beginner', 'ar', 'paid', 'trusted', true, current_date, 'Approved Arabic software-learning resource.', array['windows','android','web'], true),
    (target_user, 'freeCodeCamp', 'course', 'https://www.freecodecamp.org/', 'embedded_browser', true, 'freeCodeCamp', 'https://www.freecodecamp.org/', 'Programming', 'Practice and certifications', 'beginner', 'en', 'free', 'trusted', true, current_date, 'Approved programming practice resource.', array['windows','android','web'], true),
    (target_user, 'MDN Web Docs', 'documentation', 'https://developer.mozilla.org/', 'embedded_browser', true, 'MDN', 'https://developer.mozilla.org/', 'Programming', 'Web documentation', 'beginner', 'en', 'free', 'trusted', true, current_date, 'Approved official web documentation.', array['windows','android','web'], true),
    (target_user, 'LeetCode', 'practice', 'https://leetcode.com/', 'external_browser', true, 'LeetCode', 'https://leetcode.com/', 'Algorithms', 'Algorithm practice', 'intermediate', 'en', 'mixed', 'trusted', true, current_date, 'Approved algorithm practice resource.', array['windows','android','web'], true),
    (target_user, 'Duolingo', 'language_app', 'https://www.duolingo.com/', 'external_browser', true, 'Duolingo', 'https://www.duolingo.com/', 'German', 'Vocabulary and daily practice', 'A1', 'multi', 'free', 'trusted', true, current_date, 'German micro-practice resource.', array['android','web'], true)
  on conflict do nothing;

  insert into public.german_skills (user_id, cefr_level, current_target)
  values (target_user, 'A1', 'B2/C1 professional and interview fluency consolidation')
  on conflict do nothing;

  update public.profiles
  set onboarding_completed = true
  where id = target_user;

  return jsonb_build_object('installed', true, 'template_key', 'yasser_roadmap_2026_2030', 'template_version', 1);
end;
$$;

create or replace function public.owner_backend_diagnostics()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_owner(auth.uid()) then
    raise exception 'owner role required';
  end if;

  return jsonb_build_object(
    'server', 'connected',
    'project_ref', 'yilegxcnokndozhwpwlf',
    'schema_version', '20260716210000_multi_user_platform',
    'environment', 'production',
    'auth', 'available',
    'storage', 'available',
    'edge_functions', 'not_configured',
    'pending_offline_operations', 0,
    'generated_at', now()
  );
end;
$$;

grant execute on function public.install_owner_template_if_needed() to authenticated;
grant execute on function public.owner_backend_diagnostics() to authenticated;
grant execute on function public.is_owner(uuid) to authenticated;
