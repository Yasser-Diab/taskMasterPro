-- Persisted session history, completed-task analytics, account controls,
-- login bootstrap repair, and rolling recurring-task occurrences.

alter table public.sessions
  add column if not exists session_type text not null default 'personal'
    check (session_type in ('work', 'learning', 'personal', 'household', 'family', 'health', 'social', 'custom')),
  add column if not exists status text not null default 'created'
    check (status in ('created', 'running', 'paused', 'idle', 'interrupted', 'completed', 'stopped', 'recovered', 'corrected', 'discarded')),
  add column if not exists gross_seconds integer not null default 0,
  add column if not exists active_seconds integer not null default 0,
  add column if not exists idle_seconds integer not null default 0,
  add column if not exists paused_seconds integer not null default 0,
  add column if not exists interrupted_seconds integer not null default 0,
  add column if not exists break_seconds integer not null default 0,
  add column if not exists manual_seconds integer not null default 0,
  add column if not exists pomodoros_completed integer not null default 0,
  add column if not exists completion_reason text,
  add column if not exists sync_status text not null default 'synced';

update public.sessions
set gross_seconds = greatest(gross_seconds, gross_duration_seconds),
    active_seconds = greatest(active_seconds, active_duration_seconds),
    idle_seconds = greatest(idle_seconds, idle_duration_seconds),
    paused_seconds = greatest(paused_seconds, paused_duration_seconds),
    status = case completion_status
      when 'completed' then 'completed'
      when 'discarded' then 'discarded'
      else status
    end
where gross_seconds = 0
   or active_seconds = 0
   or idle_seconds = 0
   or paused_seconds = 0;

alter table public.session_segments
  drop constraint if exists session_segments_segment_type_check,
  add column if not exists source text not null default 'timer',
  add column if not exists tracking_mode text not null default 'interactive'
    check (tracking_mode in ('interactive', 'video', 'reading', 'manual'));

alter table public.session_segments
  add constraint session_segments_segment_type_check
  check (segment_type in (
    'active',
    'idle',
    'paused',
    'interruption',
    'break',
    'manual',
    'video',
    'reading',
    'external_resource'
  ));

alter table public.tasks
  add column if not exists recurrence_id uuid references public.task_recurrences(id) on delete set null,
  add column if not exists series_task_id uuid references public.tasks(id) on delete cascade,
  add column if not exists occurrence_original_start timestamptz,
  add column if not exists scheduled_start_at timestamptz,
  add column if not exists scheduled_end_at timestamptz,
  add column if not exists is_recurring_template boolean not null default false,
  add column if not exists is_recurrence_exception boolean not null default false,
  add column if not exists skipped_at timestamptz,
  add column if not exists template_key text,
  add column if not exists template_version integer;

alter table public.task_recurrences
  add column if not exists timezone text not null default 'UTC',
  add column if not exists rrule text,
  add column if not exists starts_at timestamptz,
  add column if not exists duration_minutes integer not null default 25,
  add column if not exists end_type text not null default 'never'
    check (end_type in ('never', 'on_date', 'after_count')),
  add column if not exists ends_at timestamptz,
  add column if not exists maximum_occurrences integer,
  add column if not exists generated_until timestamptz,
  add column if not exists is_active boolean not null default true;

create unique index if not exists tasks_recurrence_occurrence_unique
on public.tasks (user_id, recurrence_id, occurrence_original_start)
where recurrence_id is not null
  and occurrence_original_start is not null
  and deleted_at is null;

create unique index if not exists tasks_user_template_unique
on public.tasks (user_id, template_key, template_version)
where template_key is not null
  and deleted_at is null;

create index if not exists tasks_user_scheduled_idx
on public.tasks (user_id, scheduled_start_at, status)
where deleted_at is null;

create table if not exists public.session_events (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null references public.sessions(id) on delete cascade,
  event_type text not null,
  event_time timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.session_corrections (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  session_id uuid not null references public.sessions(id) on delete cascade,
  original_values jsonb not null,
  corrected_values jsonb not null,
  reason text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.task_progress_entries (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  progress_percentage integer not null default 0 check (progress_percentage between 0 and 100),
  progress_value numeric,
  progress_unit text,
  confidence integer check (confidence between 1 and 5),
  remaining_estimate_minutes integer,
  summary text not null default '',
  next_action text,
  recorded_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.task_retrospectives (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  completed_work text,
  unfinished_work text,
  estimate_accuracy_note text,
  delay_causes text,
  performance_helpers text,
  next_time_change text,
  next_related_task_id uuid references public.tasks(id) on delete set null,
  observations jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.daily_summaries (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  summary_date date not null,
  planned_seconds integer not null default 0,
  recorded_seconds integer not null default 0,
  active_seconds integer not null default 0,
  idle_seconds integer not null default 0,
  paused_seconds integer not null default 0,
  interrupted_seconds integer not null default 0,
  category_breakdown jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, summary_date)
);

create table if not exists public.calendar_entries (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  entry_date date not null,
  task_id uuid references public.tasks(id) on delete set null,
  session_id uuid references public.sessions(id) on delete set null,
  entry_type text not null default 'session'
    check (entry_type in ('planned_task', 'completed_task', 'missed_task', 'session', 'review', 'manual_correction')),
  starts_at timestamptz,
  ends_at timestamptz,
  active_seconds integer not null default 0,
  summary text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.analytics_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  snapshot_type text not null check (snapshot_type in ('daily', 'weekly', 'monthly', 'task', 'series')),
  range_start date not null,
  range_end date not null,
  payload jsonb not null,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.account_deletion_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'cancelled', 'completed', 'failed')),
  requested_at timestamptz not null default now(),
  scheduled_delete_at timestamptz not null default now() + interval '30 days',
  cancelled_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.security_audit_events (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  event_time timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'session_events',
    'session_corrections',
    'task_progress_entries',
    'task_retrospectives',
    'daily_summaries',
    'calendar_entries',
    'analytics_snapshots',
    'account_deletion_requests'
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

alter table public.security_audit_events enable row level security;
drop policy if exists security_audit_events_owner_select on public.security_audit_events;
create policy security_audit_events_owner_select on public.security_audit_events
  for select using (public.is_owner());

create index if not exists session_events_session_time_idx on public.session_events(session_id, event_time);
create index if not exists session_corrections_session_idx on public.session_corrections(session_id);
create index if not exists task_progress_entries_task_time_idx on public.task_progress_entries(task_id, recorded_at);
create index if not exists calendar_entries_user_date_idx on public.calendar_entries(user_id, entry_date);
create index if not exists analytics_snapshots_user_range_idx on public.analytics_snapshots(user_id, snapshot_type, range_start, range_end);
create index if not exists account_deletion_user_status_idx on public.account_deletion_requests(user_id, status);

create or replace function public._rrule_token(rule text, token text)
returns text
language sql
immutable
as $$
  select substring(coalesce(rule, '') from token || '=([^;]+)');
$$;

create or replace function public._rrule_day_matches(day_to_check date, byday text)
returns boolean
language plpgsql
immutable
as $$
declare
  iso integer := extract(isodow from day_to_check)::integer;
  day_code text := case iso
    when 1 then 'MO'
    when 2 then 'TU'
    when 3 then 'WE'
    when 4 then 'TH'
    when 5 then 'FR'
    when 6 then 'SA'
    else 'SU'
  end;
begin
  if byday is null or btrim(byday) = '' then
    return true;
  end if;
  return day_code = any(string_to_array(byday, ','));
end;
$$;

create or replace function public.generate_task_occurrences(
  recurrence_id uuid,
  range_start timestamptz,
  range_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  recurrence record;
  template_task record;
  current_day date;
  start_day date;
  end_day date;
  occurrence_start timestamptz;
  occurrence_end timestamptz;
  recurrence_time time;
  recurrence_timezone text;
  freq text;
  byday text;
  bymonthday text;
  interval_value integer;
  weeks_since_start integer;
  inserted_ids uuid[] := array[]::uuid[];
  inserted_id uuid;
  generated_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into recurrence
  from public.task_recurrences
  where id = recurrence_id
    and user_id = auth.uid()
    and deleted_at is null
    and is_active = true;

  if recurrence.id is null then
    raise exception 'Recurring series was not found';
  end if;

  select *
  into template_task
  from public.tasks
  where id = recurrence.task_id
    and user_id = auth.uid()
    and deleted_at is null;

  if template_task.id is null then
    raise exception 'Recurring task template was not found';
  end if;

  freq := coalesce(public._rrule_token(recurrence.rrule, 'FREQ'), 'DAILY');
  byday := public._rrule_token(recurrence.rrule, 'BYDAY');
  bymonthday := public._rrule_token(recurrence.rrule, 'BYMONTHDAY');
  interval_value := greatest(coalesce(nullif(public._rrule_token(recurrence.rrule, 'INTERVAL'), '')::integer, 1), 1);
  recurrence_timezone := coalesce(recurrence.timezone, 'UTC');
  recurrence_time := coalesce((recurrence.starts_at at time zone recurrence_timezone)::time, time '09:00');
  start_day := greatest(
    (range_start at time zone recurrence_timezone)::date,
    coalesce(
      (recurrence.starts_at at time zone recurrence_timezone)::date,
      (range_start at time zone recurrence_timezone)::date
    )
  );
  end_day := least((range_end at time zone recurrence_timezone)::date, coalesce((recurrence.ends_at at time zone recurrence_timezone)::date, (range_end at time zone recurrence_timezone)::date));
  current_day := start_day;

  while current_day <= end_day loop
    occurrence_start := (current_day::timestamp + recurrence_time) at time zone recurrence_timezone;
    occurrence_end := occurrence_start + make_interval(mins => recurrence.duration_minutes);

    if occurrence_start >= range_start
       and occurrence_start < range_end
       and (
         (freq = 'DAILY' and ((current_day - start_day) % interval_value = 0) and public._rrule_day_matches(current_day, byday))
         or
         (freq = 'WEEKLY' and public._rrule_day_matches(current_day, byday) and (
            (extract(epoch from (date_trunc('week', current_day::timestamp) - date_trunc('week', start_day::timestamp))) / 604800)::integer % interval_value = 0
          ))
         or
         (freq = 'MONTHLY' and (
            (bymonthday is not null and extract(day from current_day)::integer = bymonthday::integer)
            or (bymonthday is null and extract(day from current_day)::integer = extract(day from (recurrence.starts_at at time zone recurrence_timezone))::integer)
          ))
         or
         (freq = 'YEARLY'
            and extract(month from current_day)::integer = extract(month from (recurrence.starts_at at time zone recurrence_timezone))::integer
            and extract(day from current_day)::integer = extract(day from (recurrence.starts_at at time zone recurrence_timezone))::integer)
       )
    then
      inserted_id := null;
      insert into public.tasks (
        user_id,
        title,
        description,
        category_id,
        category_name,
        project_id,
        project_name,
        roadmap_phase_id,
        roadmap_phase,
        priority,
        priority_rank,
        status,
        start_date,
        due_date,
        estimated_pomodoros,
        estimated_minutes,
        recurrence,
        learning_resource_link,
        launch_method,
        notes,
        checklist,
        tags,
        progress_percentage,
        difficulty,
        energy_requirement,
        context,
        attachments,
        completion_evidence,
        parent_task_id,
        dependencies,
        reminder_rules,
        workspace_enabled,
        workspace_type,
        workspace_starting_url,
        workspace_home_url,
        workspace_resource_title,
        workspace_browser_mode,
        workspace_allowed_domains,
        workspace_restore_last_page,
        workspace_open_automatically,
        workspace_preferred_layout,
        workspace_preferred_dock_state,
        workspace_allow_external_navigation,
        workspace_open_unsupported_externally,
        recurrence_id,
        series_task_id,
        occurrence_original_start,
        scheduled_start_at,
        scheduled_end_at,
        is_recurring_template,
        is_recurrence_exception
      )
      values (
        template_task.user_id,
        template_task.title,
        template_task.description,
        template_task.category_id,
        template_task.category_name,
        template_task.project_id,
        template_task.project_name,
        template_task.roadmap_phase_id,
        template_task.roadmap_phase,
        template_task.priority,
        template_task.priority_rank,
        'not_started',
        occurrence_start::date,
        occurrence_start::date,
        template_task.estimated_pomodoros,
        template_task.estimated_minutes,
        template_task.recurrence,
        template_task.learning_resource_link,
        template_task.launch_method,
        '',
        template_task.checklist,
        template_task.tags,
        0,
        template_task.difficulty,
        template_task.energy_requirement,
        template_task.context,
        '[]'::jsonb,
        null,
        template_task.id,
        template_task.dependencies,
        template_task.reminder_rules,
        template_task.workspace_enabled,
        template_task.workspace_type,
        template_task.workspace_starting_url,
        template_task.workspace_home_url,
        template_task.workspace_resource_title,
        template_task.workspace_browser_mode,
        template_task.workspace_allowed_domains,
        template_task.workspace_restore_last_page,
        template_task.workspace_open_automatically,
        template_task.workspace_preferred_layout,
        template_task.workspace_preferred_dock_state,
        template_task.workspace_allow_external_navigation,
        template_task.workspace_open_unsupported_externally,
        recurrence.id,
        template_task.id,
        occurrence_start,
        occurrence_start,
        occurrence_end,
        false,
        false
      )
      on conflict (user_id, recurrence_id, occurrence_original_start)
      where recurrence_id is not null
        and occurrence_original_start is not null
        and deleted_at is null
      do nothing
      returning id into inserted_id;

      if inserted_id is not null then
        inserted_ids := array_append(inserted_ids, inserted_id);
        generated_count := generated_count + 1;
      end if;
    end if;

    current_day := current_day + 1;
  end loop;

  update public.task_recurrences
  set generated_until = greatest(coalesce(generated_until, range_start), range_end),
      next_occurrence = (
        select min(occurrence_original_start)::date
        from public.tasks
        where user_id = recurrence.user_id
          and recurrence_id = recurrence.id
          and deleted_at is null
          and status not in ('completed', 'cancelled')
          and occurrence_original_start >= now()
      )
  where id = recurrence.id;

  return jsonb_build_object(
    'recurrence_id', recurrence.id,
    'inserted_count', generated_count,
    'inserted_ids', inserted_ids
  );
end;
$$;

create or replace function public._ensure_owner_task(
  target_user uuid,
  owner_template_key text,
  owner_title text,
  owner_category text,
  owner_priority text,
  owner_estimated_minutes integer,
  owner_recurrence_summary text,
  owner_rrule text,
  owner_starts_at timestamptz,
  owner_duration_minutes integer,
  owner_workspace_url text default null,
  owner_tracking_mode text default 'interactive'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  template_task_id uuid;
  recurrence_row_id uuid;
begin
  insert into public.tasks (
    user_id,
    title,
    category_name,
    priority,
    priority_rank,
    status,
    estimated_pomodoros,
    estimated_minutes,
    recurrence,
    learning_resource_link,
    workspace_enabled,
    workspace_type,
    workspace_starting_url,
    workspace_home_url,
    workspace_resource_title,
    workspace_browser_mode,
    workspace_open_automatically,
    is_recurring_template,
    template_key,
    template_version
  )
  values (
    target_user,
    owner_title,
    owner_category,
    owner_priority,
    case owner_priority when 'critical' then 0 when 'high' then 1 when 'low' then 3 else 2 end,
    'not_started',
    greatest(1, ceil(owner_estimated_minutes::numeric / 25)::integer),
    owner_estimated_minutes,
    owner_recurrence_summary,
    owner_workspace_url,
    owner_workspace_url is not null,
    case when owner_workspace_url is null then 'none' else 'in_app_browser' end,
    owner_workspace_url,
    owner_workspace_url,
    owner_title,
    owner_tracking_mode,
    owner_workspace_url is not null,
    true,
    owner_template_key,
    1
  )
  on conflict (user_id, template_key, template_version)
  where template_key is not null and deleted_at is null
  do update
    set title = excluded.title,
        category_name = excluded.category_name,
        recurrence = excluded.recurrence,
        estimated_minutes = excluded.estimated_minutes,
        updated_at = now()
  returning id into template_task_id;

  select id
  into recurrence_row_id
  from public.task_recurrences
  where user_id = target_user
    and task_id = template_task_id
    and deleted_at is null
  limit 1;

  if recurrence_row_id is null then
    insert into public.task_recurrences (
      user_id,
      task_id,
      rule,
      timezone,
      rrule,
      starts_at,
      duration_minutes,
      end_type,
      is_active
    )
    values (
      target_user,
      template_task_id,
      jsonb_build_object('rrule', owner_rrule),
      'Africa/Cairo',
      owner_rrule,
      owner_starts_at,
      owner_duration_minutes,
      'never',
      true
    )
    returning id into recurrence_row_id;
  else
    update public.task_recurrences
    set rrule = owner_rrule,
        starts_at = owner_starts_at,
        duration_minutes = owner_duration_minutes,
        is_active = true,
        updated_at = now()
    where id = recurrence_row_id;
  end if;

  update public.tasks
  set recurrence_id = recurrence_row_id
  where id = template_task_id;

  perform public.generate_task_occurrences(
    recurrence_row_id,
    now() - interval '7 days',
    now() + interval '90 days'
  );

  return template_task_id;
end;
$$;

create or replace function public.install_owner_template_if_needed()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user uuid := auth.uid();
  phase_one uuid;
begin
  if target_user is null or not public.is_owner(target_user) then
    raise exception 'owner role required';
  end if;

  insert into public.user_template_installations (user_id, template_key, template_version)
  values (target_user, 'yasser_roadmap_2026_2030', 1)
  on conflict (user_id, template_key, template_version) do update
    set installed_at = coalesce(public.user_template_installations.installed_at, excluded.installed_at),
        deleted_at = null,
        updated_at = now();

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
    (target_user, '25/5 default', 25, 5, 20, 4, true),
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
    '{"frequency":"twice_weekly","rrule":"FREQ=WEEKLY;BYDAY=TU,FR"}'::jsonb,
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

  perform public._ensure_owner_task(
    target_user,
    'yasser_main_job_sat_thu',
    'Main job workday',
    'Main Job',
    'critical',
    510,
    'Saturday-Thursday 09:00-17:30',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,SU,MO,TU,WE,TH',
    date_trunc('day', now()) + interval '9 hours',
    510
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_2026_html_css_morning_study',
    'Morning HTML/CSS study',
    'Programming Learning',
    'high',
    55,
    'Saturday-Thursday 05:30',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,SU,MO,TU,WE,TH',
    date_trunc('day', now()) + interval '5 hours 30 minutes',
    55,
    'https://developer.mozilla.org/en-US/docs/Learn',
    'interactive'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_selected_evening_programming',
    'Evening programming practice',
    'Programming Practice',
    'normal',
    50,
    'Saturday, Monday and Wednesday evening',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,MO,WE',
    date_trunc('day', now()) + interval '21 hours',
    50,
    'https://www.freecodecamp.org/learn/',
    'interactive'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_2026_german_daily',
    'German review',
    'German',
    'normal',
    15,
    'Every day',
    'FREQ=DAILY;INTERVAL=1',
    date_trunc('day', now()) + interval '21 hours 45 minutes',
    15,
    'https://www.duolingo.com/',
    'reading'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_weekly_review',
    'Weekly review and roadmap check',
    'Weekly Review',
    'high',
    60,
    'Every Friday morning',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR',
    date_trunc('day', now()) + interval '6 hours',
    60
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_friday_project_building',
    'Friday project-building block',
    'Project Building',
    'high',
    90,
    'Every Friday',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR',
    date_trunc('day', now()) + interval '8 hours',
    90,
    'https://github.com/',
    'interactive'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_family_daily_protected',
    'Protected family time',
    'Family',
    'high',
    120,
    'Every workday evening',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,SU,MO,TU,WE,TH',
    date_trunc('day', now()) + interval '19 hours',
    120
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_laundry_tuesday',
    'Laundry - Tuesday workflow',
    'Household',
    'normal',
    40,
    'Every Tuesday',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=TU',
    date_trunc('day', now()) + interval '19 hours 30 minutes',
    40
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_laundry_friday',
    'Laundry - Friday workflow',
    'Household',
    'normal',
    40,
    'Every Friday',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR',
    date_trunc('day', now()) + interval '11 hours',
    40
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_relationship_rotation',
    'Friends and sisters contact rotation',
    'Friends and Sisters',
    'normal',
    30,
    'Twice weekly',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=TU,FR',
    date_trunc('day', now()) + interval '20 hours 30 minutes',
    30
  );

  update public.profiles
  set onboarding_completed = true
  where id = target_user;

  return jsonb_build_object(
    'installed', true,
    'template_key', 'yasser_roadmap_2026_2030',
    'template_version', 1,
    'generated_until', now() + interval '90 days'
  );
end;
$$;

create or replace function public.bootstrap_current_user()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_email text;
  assigned_role text;
  owner_installation jsonb := '{}'::jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(email)
  into current_email
  from auth.users
  where id = current_user_id;

  if current_email is null then
    raise exception 'Authenticated user was not found';
  end if;

  assigned_role := case
    when current_email = 'yasserdiabhassan@gmail.com' then 'owner'
    else 'user'
  end;

  insert into public.profiles (
    id,
    email,
    display_name,
    locale,
    onboarding_completed
  )
  values (
    current_user_id,
    current_email,
    current_email,
    'en',
    false
  )
  on conflict (id) do update
  set email = excluded.email;

  insert into public.user_settings (user_id, language)
  values (current_user_id, 'en')
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (current_user_id)
  on conflict (user_id) do nothing;

  insert into public.user_roles (user_id, role)
  values (current_user_id, assigned_role)
  on conflict (user_id) do update
  set role = case
      when public.user_roles.role = 'owner' then 'owner'
      else excluded.role
    end,
    deleted_at = null,
    updated_at = now();

  insert into public.pomodoro_presets (
    user_id,
    name,
    focus_minutes,
    short_break_minutes,
    long_break_minutes,
    long_break_after,
    is_default
  )
  values (current_user_id, '25/5 default', 25, 5, 20, 4, true)
  on conflict (user_id, name) do nothing;

  if assigned_role = 'owner' then
    owner_installation := public.install_owner_template_if_needed();
  end if;

  return jsonb_build_object(
    'user_id', current_user_id,
    'email', current_email,
    'role', assigned_role,
    'owner_template', owner_installation
  );
end;
$$;

create or replace function public.export_my_data()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  return jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.id = current_user_id),
    'settings', (select to_jsonb(s) from public.user_settings s where s.user_id = current_user_id),
    'categories', coalesce((select jsonb_agg(to_jsonb(c)) from public.categories c where c.user_id = current_user_id), '[]'::jsonb),
    'projects', coalesce((select jsonb_agg(to_jsonb(p)) from public.projects p where p.user_id = current_user_id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(to_jsonb(t)) from public.tasks t where t.user_id = current_user_id), '[]'::jsonb),
    'sessions', coalesce((select jsonb_agg(to_jsonb(s)) from public.sessions s where s.user_id = current_user_id), '[]'::jsonb),
    'session_segments', coalesce((select jsonb_agg(to_jsonb(ss)) from public.session_segments ss where ss.user_id = current_user_id), '[]'::jsonb),
    'task_notes', coalesce((select jsonb_agg(to_jsonb(n)) from public.task_notes n where n.user_id = current_user_id), '[]'::jsonb),
    'task_interruptions', coalesce((select jsonb_agg(to_jsonb(i)) from public.task_interruptions i where i.user_id = current_user_id), '[]'::jsonb),
    'task_progress_entries', coalesce((select jsonb_agg(to_jsonb(pe)) from public.task_progress_entries pe where pe.user_id = current_user_id), '[]'::jsonb),
    'daily_reviews', coalesce((select jsonb_agg(to_jsonb(r)) from public.daily_reviews r where r.user_id = current_user_id), '[]'::jsonb),
    'weekly_reviews', coalesce((select jsonb_agg(to_jsonb(r)) from public.weekly_reviews r where r.user_id = current_user_id), '[]'::jsonb),
    'roadmap_phases', coalesce((select jsonb_agg(to_jsonb(rp)) from public.roadmap_phases rp where rp.user_id = current_user_id), '[]'::jsonb),
    'roadmap_items', coalesce((select jsonb_agg(to_jsonb(ri)) from public.roadmap_items ri where ri.user_id = current_user_id), '[]'::jsonb),
    'learning_resources', coalesce((select jsonb_agg(to_jsonb(lr)) from public.learning_resources lr where lr.user_id = current_user_id), '[]'::jsonb),
    'relationships', coalesce((select jsonb_agg(to_jsonb(r)) from public.relationships r where r.user_id = current_user_id), '[]'::jsonb),
    'household_routines', coalesce((select jsonb_agg(to_jsonb(h)) from public.household_routines h where h.user_id = current_user_id), '[]'::jsonb),
    'generated_at', now()
  );
end;
$$;

create or replace function public.request_account_deletion(confirmation_text text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  owner_count integer;
  deletion_date timestamptz := now() + interval '30 days';
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if confirmation_text <> 'DELETE MY ACCOUNT' then
    raise exception 'Deletion confirmation is invalid';
  end if;

  if exists (
    select 1 from public.user_roles
    where user_id = current_user_id
      and role = 'owner'
      and deleted_at is null
  ) then
    select count(*)
    into owner_count
    from public.user_roles
    where role = 'owner'
      and deleted_at is null;

    if owner_count <= 1 then
      raise exception 'This is the only owner account. Assign another owner before deleting it.';
    end if;
  end if;

  insert into public.account_deletion_requests (
    user_id,
    status,
    scheduled_delete_at
  )
  values (current_user_id, 'pending', deletion_date);

  insert into public.security_audit_events (user_id, event_type, metadata)
  values (
    current_user_id,
    'account_deletion_requested',
    jsonb_build_object('scheduled_delete_at', deletion_date)
  );

  return jsonb_build_object(
    'status', 'pending',
    'scheduled_delete_at', deletion_date
  );
end;
$$;

create or replace function public.cancel_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  update public.account_deletion_requests
  set status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  where user_id = current_user_id
    and status = 'pending';

  insert into public.security_audit_events (user_id, event_type)
  values (current_user_id, 'account_deletion_cancelled');

  return jsonb_build_object('status', 'cancelled');
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
    'schema_version', '20260716220000_session_history_account_recurrence',
    'environment', 'production',
    'auth', 'available',
    'storage', 'available',
    'edge_functions', 'deletion-worker-required',
    'pending_offline_operations', 0,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.bootstrap_current_user() from public;
revoke all on function public.export_my_data() from public;
revoke all on function public.request_account_deletion(text) from public;
revoke all on function public.cancel_account_deletion() from public;
revoke all on function public.generate_task_occurrences(uuid, timestamptz, timestamptz) from public;

grant execute on function public.bootstrap_current_user() to authenticated;
grant execute on function public.export_my_data() to authenticated;
grant execute on function public.request_account_deletion(text) to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;
grant execute on function public.generate_task_occurrences(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.install_owner_template_if_needed() to authenticated;
grant execute on function public.owner_backend_diagnostics() to authenticated;
