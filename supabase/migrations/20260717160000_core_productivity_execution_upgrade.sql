-- TaskMaster Pro 0.1.1 core productivity and task-execution upgrade.
--
-- This migration is intentionally idempotent. It extends the existing task,
-- recurrence, roadmap, session, resource and activity records without deleting
-- historical rows or replacing the private owner-template engine.

-- ---------------------------------------------------------------------------
-- Stable roadmap phase ordering and one explicit active phase per roadmap
-- ---------------------------------------------------------------------------

alter table public.roadmap_phases
  add column if not exists phase_order integer,
  add column if not exists start_date date,
  add column if not exists end_date date,
  add column if not exists is_explicitly_active boolean not null default false;

update public.roadmap_phases
set phase_order = coalesce(phase_order, phase_number),
    start_date = coalesce(start_date, planned_start),
    end_date = coalesce(end_date, planned_finish),
    is_explicitly_active = coalesce(is_explicitly_active, false)
where phase_order is null
   or start_date is null
   or end_date is null;

with ranked_active as (
  select
    id,
    row_number() over (
      partition by roadmap_id
      order by
        case when status = 'active' then 0 else 1 end,
        coalesce(phase_order, phase_number),
        created_at,
        id
    ) as active_rank
  from public.roadmap_phases
  where deleted_at is null
    and (status = 'active' or is_explicitly_active = true)
)
update public.roadmap_phases phase
set status = case
      when ranked_active.active_rank = 1 then 'active'
      when phase.status = 'active' then 'not_started'
      else phase.status
    end,
    is_explicitly_active = ranked_active.active_rank = 1,
    updated_at = now()
from ranked_active
where phase.id = ranked_active.id;

alter table public.roadmap_phases
  alter column phase_order set not null;

create unique index if not exists roadmap_phases_order_unique
on public.roadmap_phases(roadmap_id, phase_order)
where roadmap_id is not null
  and deleted_at is null;

create unique index if not exists roadmap_phases_one_explicit_active
on public.roadmap_phases(roadmap_id)
where roadmap_id is not null
  and deleted_at is null
  and (status = 'active' or is_explicitly_active = true);

create index if not exists roadmap_phases_order_idx
on public.roadmap_phases(user_id, roadmap_id, phase_order asc)
where deleted_at is null;

create or replace function public.keep_roadmap_phase_dates_in_sync()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.phase_order := coalesce(new.phase_order, new.phase_number);
  new.phase_number := coalesce(new.phase_number, new.phase_order);
  new.start_date := coalesce(new.start_date, new.planned_start);
  new.end_date := coalesce(new.end_date, new.planned_finish);
  new.planned_start := coalesce(new.planned_start, new.start_date);
  new.planned_finish := coalesce(new.planned_finish, new.end_date);
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    new.is_explicitly_active := new.status = 'active';
  elsif tg_op = 'UPDATE'
      and new.is_explicitly_active is distinct from old.is_explicitly_active then
    if new.is_explicitly_active then
      new.status := 'active';
    elsif new.status = 'active' then
      new.status := 'not_started';
    end if;
  elsif new.status = 'active' then
    new.is_explicitly_active := true;
  else
    new.is_explicitly_active := false;
  end if;
  return new;
end;
$$;

drop trigger if exists roadmap_phase_sync_fields
on public.roadmap_phases;

create trigger roadmap_phase_sync_fields
before insert or update on public.roadmap_phases
for each row execute function public.keep_roadmap_phase_dates_in_sync();

-- ---------------------------------------------------------------------------
-- Task execution types, scheduling, recurrence editing and completion rules
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists task_type text not null default 'focus',
  add column if not exists event_state text not null default 'upcoming',
  add column if not exists milestone_id uuid
    references public.roadmap_items(id) on delete set null,
  add column if not exists planned_date date,
  add column if not exists planned_start_at timestamptz,
  add column if not exists planned_end_at timestamptz,
  add column if not exists due_at timestamptz,
  add column if not exists actual_start_at timestamptz,
  add column if not exists actual_finish_at timestamptz,
  add column if not exists arrival_at timestamptz,
  add column if not exists recurrence_rule text,
  add column if not exists recurrence_timezone text not null default 'UTC',
  add column if not exists recurrence_end_at timestamptz,
  add column if not exists recurrence_end_type text not null default 'never',
  add column if not exists recurrence_maximum_occurrences integer,
  add column if not exists recurrence_paused_at timestamptz,
  add column if not exists adaptive_reminders_enabled boolean not null default false,
  add column if not exists location text,
  add column if not exists calendar_integration boolean not null default false,
  add column if not exists completion_rules jsonb not null default '{}'::jsonb,
  add column if not exists timer_enabled boolean not null default true,
  add column if not exists habit_current_streak integer not null default 0,
  add column if not exists habit_longest_streak integer not null default 0;

update public.tasks
set planned_date = coalesce(planned_date, start_date, scheduled_start_at::date),
    planned_start_at = coalesce(planned_start_at, scheduled_start_at),
    planned_end_at = coalesce(planned_end_at, scheduled_end_at),
    due_at = coalesce(due_at, scheduled_end_at),
    recurrence_rule = coalesce(recurrence_rule, recurrence),
    task_type = case
      when task_type is not null and task_type <> 'focus' then task_type
      when lower(category_name) similar to '%(appointment|meeting|interview|flight|event)%'
        then 'event'
      when lower(title) similar to '%(medicine|prayer|water|stretch)%'
        then 'habit'
      when lower(category_name) similar to '%(household|family|health|social|shopping|exercise)%'
        then 'timed'
      else 'focus'
    end
where deleted_at is null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tasks'::regclass
      and conname = 'tasks_task_type_check'
  ) then
    alter table public.tasks
      add constraint tasks_task_type_check
      check (task_type in ('focus', 'timed', 'event', 'habit', 'manual'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tasks'::regclass
      and conname = 'tasks_event_state_check'
  ) then
    alter table public.tasks
      add constraint tasks_event_state_check
      check (event_state in (
        'upcoming', 'arrived', 'in_progress', 'completed', 'missed', 'cancelled'
      ));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tasks'::regclass
      and conname = 'tasks_habit_streaks_check'
  ) then
    alter table public.tasks
      add constraint tasks_habit_streaks_check
      check (habit_current_streak >= 0 and habit_longest_streak >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tasks'::regclass
      and conname = 'tasks_recurrence_end_check'
  ) then
    alter table public.tasks
      add constraint tasks_recurrence_end_check
      check (
        recurrence_end_type in ('never', 'on_date', 'after_count')
        and (
          recurrence_maximum_occurrences is null
          or recurrence_maximum_occurrences > 0
        )
      );
  end if;
end;
$$;

alter table public.tasks
  drop constraint if exists tasks_workspace_browser_mode_check;

alter table public.tasks
  add constraint tasks_workspace_browser_mode_check
  check (workspace_browser_mode in ('interactive', 'video', 'reading', 'manual'));

create index if not exists tasks_user_type_schedule_idx
on public.tasks(user_id, task_type, planned_start_at)
where deleted_at is null;

create index if not exists tasks_user_roadmap_schedule_idx
on public.tasks(user_id, roadmap_id, roadmap_phase_id, planned_start_at)
where deleted_at is null;

-- Occurrences generated by the existing recurrence engine inherit the new
-- execution fields from their normal series template.
create or replace function public.inherit_task_execution_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  template_task public.tasks%rowtype;
  maximum_count integer;
  existing_count integer;
begin
  if new.series_task_id is null or new.is_recurring_template then
    return new;
  end if;

  select * into template_task
  from public.tasks
  where id = new.series_task_id
    and user_id = new.user_id;

  if template_task.id is null then
    return new;
  end if;

  if new.recurrence_id is not null then
    select recurrence.maximum_occurrences
    into maximum_count
    from public.task_recurrences recurrence
    where recurrence.id = new.recurrence_id
      and recurrence.user_id = new.user_id
      and recurrence.end_type = 'after_count'
      and recurrence.deleted_at is null;
    if maximum_count is not null then
      select count(*) into existing_count
      from public.tasks occurrence
      where occurrence.user_id = new.user_id
        and occurrence.recurrence_id = new.recurrence_id
        and occurrence.is_recurring_template = false
        and occurrence.deleted_at is null;
      if existing_count >= maximum_count then
        return null;
      end if;
    end if;
  end if;

  new.task_type := template_task.task_type;
  new.event_state := 'upcoming';
  new.roadmap_id := template_task.roadmap_id;
  new.milestone_id := template_task.milestone_id;
  new.recurrence_rule := template_task.recurrence_rule;
  new.recurrence_timezone := template_task.recurrence_timezone;
  new.recurrence_end_at := template_task.recurrence_end_at;
  new.recurrence_end_type := template_task.recurrence_end_type;
  new.recurrence_maximum_occurrences := template_task.recurrence_maximum_occurrences;
  new.adaptive_reminders_enabled := template_task.adaptive_reminders_enabled;
  new.location := template_task.location;
  new.calendar_integration := template_task.calendar_integration;
  new.completion_rules := template_task.completion_rules;
  new.timer_enabled := template_task.timer_enabled;
  new.planned_date := coalesce(new.planned_date, new.scheduled_start_at::date);
  new.planned_start_at := coalesce(new.planned_start_at, new.scheduled_start_at);
  new.planned_end_at := coalesce(new.planned_end_at, new.scheduled_end_at);
  new.due_at := coalesce(new.due_at, new.scheduled_end_at);
  return new;
end;
$$;

drop trigger if exists tasks_inherit_execution_fields on public.tasks;
create trigger tasks_inherit_execution_fields
before insert on public.tasks
for each row execute function public.inherit_task_execution_fields();

with ranked_occurrences as (
  select
    occurrence.id,
    recurrence.maximum_occurrences,
    row_number() over (
      partition by occurrence.recurrence_id
      order by occurrence.occurrence_original_start, occurrence.id
    ) as occurrence_number
  from public.tasks occurrence
  join public.task_recurrences recurrence
    on recurrence.id = occurrence.recurrence_id
  where occurrence.deleted_at is null
    and occurrence.is_recurring_template = false
    and recurrence.deleted_at is null
    and recurrence.end_type = 'after_count'
    and recurrence.maximum_occurrences is not null
)
update public.tasks occurrence
set deleted_at = now(), updated_at = now()
from ranked_occurrences ranked
where occurrence.id = ranked.id
  and ranked.occurrence_number > ranked.maximum_occurrences;

-- ---------------------------------------------------------------------------
-- Unlimited resources and multiple reminders
-- ---------------------------------------------------------------------------

alter table public.task_resources
  add column if not exists name text,
  add column if not exists open_mode text not null default 'in_app',
  add column if not exists is_default boolean not null default false,
  add column if not exists is_hidden boolean not null default false;

update public.task_resources
set name = coalesce(nullif(name, ''), title),
    open_mode = case
      when launch_mode = 'external_browser'
        or open_behavior in ('external', 'external_browser', 'open_external')
        then 'external'
      when open_behavior in ('ask', 'ask_every_time') then 'ask'
      else coalesce(nullif(open_mode, ''), 'in_app')
    end,
    is_default = is_starting_page
where name is null
   or name = ''
   or is_default is distinct from is_starting_page;

alter table public.task_resources
  alter column name set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.task_resources'::regclass
      and conname = 'task_resources_open_mode_check'
  ) then
    alter table public.task_resources
      add constraint task_resources_open_mode_check
      check (open_mode in ('in_app', 'external', 'ask'));
  end if;
end;
$$;

drop index if exists public.task_resources_one_starting_page_per_task;
create unique index task_resources_one_starting_page_per_task
on public.task_resources(task_id)
where (is_default = true or is_starting_page = true)
  and is_hidden = false
  and deleted_at is null;

alter table public.tasks
  add column if not exists default_resource_id uuid
    references public.task_resources(id) on delete set null;

create table if not exists public.task_reminders (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  occurrence_id uuid references public.tasks(id) on delete cascade,
  offset_minutes integer,
  custom_trigger_at timestamptz,
  is_adaptive boolean not null default false,
  reason text,
  notification_id text,
  status text not null default 'pending',
  scheduled_at timestamptz,
  sent_at timestamptz,
  dismissed_at timestamptz,
  snoozed_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint task_reminders_status_check check (
    status in ('pending', 'scheduled', 'sent', 'dismissed', 'snoozed', 'cancelled')
  ),
  constraint task_reminders_trigger_check check (
    offset_minutes is not null or custom_trigger_at is not null or is_adaptive
  )
);

create unique index if not exists task_reminders_notification_unique
on public.task_reminders(user_id, notification_id)
where notification_id is not null and deleted_at is null;

create index if not exists task_reminders_due_idx
on public.task_reminders(user_id, status, scheduled_at)
where deleted_at is null
  and status in ('pending', 'scheduled', 'snoozed');

-- ---------------------------------------------------------------------------
-- Retained task-browser state and auditable activity summaries
-- ---------------------------------------------------------------------------

create table if not exists public.task_browser_tabs (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  url text,
  title text,
  domain text,
  tab_order integer not null default 0,
  is_active boolean not null default false,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  last_active_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists task_browser_tabs_one_active
on public.task_browser_tabs(user_id, task_id)
where is_active = true and closed_at is null and deleted_at is null;

create index if not exists task_browser_tabs_task_order_idx
on public.task_browser_tabs(user_id, task_id, tab_order)
where closed_at is null and deleted_at is null;

create table if not exists public.task_workspace_state (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  browser_expanded boolean not null default false,
  browser_width numeric(8,2) not null default 480,
  workspace_layout text not null default 'right_panel',
  selected_task_panel text not null default 'overview',
  selected_browser_tab_id uuid references public.task_browser_tabs(id)
    on delete set null,
  last_opened_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, task_id),
  constraint task_workspace_state_width_check
    check (browser_width between 280 and 1600),
  constraint task_workspace_state_layout_check
    check (workspace_layout in ('collapsed', 'right_panel', 'split', 'full'))
);

create table if not exists public.task_activity_records (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  browser_tab_id uuid references public.task_browser_tabs(id) on delete set null,
  activity_type text not null,
  application_name text,
  window_title text,
  domain text,
  url text,
  page_title text,
  activity_category text not null default 'neutral',
  started_at timestamptz not null,
  ended_at timestamptz,
  active_seconds integer not null default 0,
  background_seconds integer not null default 0,
  idle_seconds integer not null default 0,
  visit_count integer not null default 1,
  opened_from_search boolean not null default false,
  is_saved_resource boolean not null default false,
  referrer_domain text,
  excluded_from_reports boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint task_activity_records_type_check
    check (activity_type in ('website', 'application')),
  constraint task_activity_records_category_check
    check (activity_category in (
      'productive', 'research', 'communication', 'entertainment',
      'distracting', 'neutral', 'ignored', 'search'
    )),
  constraint task_activity_records_seconds_check
    check (
      active_seconds >= 0 and background_seconds >= 0 and idle_seconds >= 0
      and visit_count >= 0
    )
);

create index if not exists task_activity_records_task_time_idx
on public.task_activity_records(user_id, task_id, started_at desc)
where deleted_at is null;

create index if not exists task_activity_records_domain_time_idx
on public.task_activity_records(user_id, domain, started_at desc)
where activity_type = 'website' and deleted_at is null;

alter table public.task_website_activity
  add column if not exists browser_tab_id uuid
    references public.task_browser_tabs(id) on delete set null,
  add column if not exists url text,
  add column if not exists activity_category text not null default 'neutral',
  add column if not exists idle_seconds integer not null default 0,
  add column if not exists visit_count integer not null default 1,
  add column if not exists opened_from_search boolean not null default false,
  add column if not exists is_saved_resource boolean not null default false,
  add column if not exists referrer_domain text;

create table if not exists public.task_performance_summaries (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  period_start timestamptz not null,
  period_end timestamptz not null,
  total_seconds integer not null default 0,
  direct_work_seconds integer not null default 0,
  browser_research_seconds integer not null default 0,
  external_app_seconds integer not null default 0,
  idle_seconds integer not null default 0,
  paused_seconds integer not null default 0,
  break_seconds integer not null default 0,
  search_seconds integer not null default 0,
  session_count integer not null default 0,
  completion_count integer not null default 0,
  interruption_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, task_id, period_start, period_end),
  constraint task_performance_summaries_period_check
    check (period_end >= period_start),
  constraint task_performance_summaries_nonnegative_check
    check (
      total_seconds >= 0 and direct_work_seconds >= 0
      and browser_research_seconds >= 0 and external_app_seconds >= 0
      and idle_seconds >= 0 and paused_seconds >= 0
      and break_seconds >= 0 and search_seconds >= 0
      and session_count >= 0 and completion_count >= 0
      and interruption_count >= 0
    )
);

create index if not exists task_performance_summaries_period_idx
on public.task_performance_summaries(user_id, task_id, period_start desc)
where deleted_at is null;

create table if not exists public.activity_privacy_preferences (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique default auth.uid()
    references auth.users(id) on delete cascade,
  track_browser_activity boolean not null default true,
  track_full_urls boolean not null default false,
  track_page_titles boolean not null default true,
  track_search_queries boolean not null default false,
  track_external_applications boolean not null default false,
  pause_in_private_mode boolean not null default true,
  excluded_domains text[] not null default '{}'::text[],
  excluded_applications text[] not null default '{}'::text[],
  default_search_engine text not null default 'google',
  custom_search_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint activity_privacy_search_engine_check
    check (default_search_engine in ('google', 'bing', 'duckduckgo', 'custom'))
);

-- ---------------------------------------------------------------------------
-- Strict ownership policies for every new entity
-- ---------------------------------------------------------------------------

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'task_reminders',
    'task_browser_tabs',
    'task_workspace_state',
    'task_activity_records',
    'task_performance_summaries',
    'activity_privacy_preferences'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_select_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_insert_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete_own', table_name);
    execute format(
      'create policy %I on public.%I for select to authenticated using (user_id = auth.uid())',
      table_name || '_select_own', table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid())',
      table_name || '_insert_own', table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      table_name || '_update_own', table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (user_id = auth.uid())',
      table_name || '_delete_own', table_name
    );
    execute format(
      'grant select, insert, update, delete on public.%I to authenticated',
      table_name
    );
  end loop;
end;
$$;

-- Child ownership is checked against the immutable authenticated UUID and the
-- actual parent row. A client-supplied user_id alone is never authorization.
create or replace function public.validate_task_child_owner()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not exists (
    select 1 from public.tasks task
    where task.id = new.task_id
      and task.user_id = auth.uid()
  ) then
    raise exception 'Task was not found';
  end if;
  new.user_id := auth.uid();
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'task_reminders',
    'task_browser_tabs',
    'task_workspace_state',
    'task_activity_records',
    'task_performance_summaries'
  ] loop
    execute format('drop trigger if exists validate_task_child_owner on public.%I', table_name);
    execute format(
      'create trigger validate_task_child_owner before insert or update on public.%I for each row execute function public.validate_task_child_owner()',
      table_name
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Transactional editing and recurrence actions
-- ---------------------------------------------------------------------------

create or replace function public.apply_task_edit_payload(
  target_task_id uuid,
  task_values jsonb
)
returns public.tasks
language plpgsql
security invoker
set search_path = public
as $$
declare
  updated_task public.tasks%rowtype;
begin
  update public.tasks task
  set
    title = case when task_values ? 'title' then task_values->>'title' else task.title end,
    description = case when task_values ? 'description' then coalesce(task_values->>'description', '') else task.description end,
    task_type = case when task_values ? 'task_type' then task_values->>'task_type' else task.task_type end,
    event_state = case when task_values ? 'event_state' then task_values->>'event_state' else task.event_state end,
    category_id = case when task_values ? 'category_id' then nullif(task_values->>'category_id', '')::uuid else task.category_id end,
    category_name = case when task_values ? 'category_name' then task_values->>'category_name' else task.category_name end,
    project_id = case when task_values ? 'project_id' then nullif(task_values->>'project_id', '')::uuid else task.project_id end,
    project_name = case when task_values ? 'project_name' then nullif(task_values->>'project_name', '') else task.project_name end,
    roadmap_id = case when task_values ? 'roadmap_id' then nullif(task_values->>'roadmap_id', '')::uuid else task.roadmap_id end,
    roadmap_phase_id = case when task_values ? 'roadmap_phase_id' then nullif(task_values->>'roadmap_phase_id', '')::uuid else task.roadmap_phase_id end,
    milestone_id = case when task_values ? 'milestone_id' then nullif(task_values->>'milestone_id', '')::uuid else task.milestone_id end,
    priority = case when task_values ? 'priority' then task_values->>'priority' else task.priority end,
    priority_rank = case when task_values ? 'priority_rank' then (task_values->>'priority_rank')::integer else task.priority_rank end,
    status = case when task_values ? 'status' then task_values->>'status' else task.status end,
    planned_date = case when task_values ? 'planned_date' then nullif(task_values->>'planned_date', '')::date else task.planned_date end,
    planned_start_at = case when task_values ? 'planned_start_at' then nullif(task_values->>'planned_start_at', '')::timestamptz else task.planned_start_at end,
    planned_end_at = case when task_values ? 'planned_end_at' then nullif(task_values->>'planned_end_at', '')::timestamptz else task.planned_end_at end,
    due_at = case when task_values ? 'due_at' then nullif(task_values->>'due_at', '')::timestamptz else task.due_at end,
    actual_start_at = case when task_values ? 'actual_start_at' then nullif(task_values->>'actual_start_at', '')::timestamptz else task.actual_start_at end,
    actual_finish_at = case when task_values ? 'actual_finish_at' then nullif(task_values->>'actual_finish_at', '')::timestamptz else task.actual_finish_at end,
    arrival_at = case when task_values ? 'arrival_at' then nullif(task_values->>'arrival_at', '')::timestamptz else task.arrival_at end,
    scheduled_start_at = case when task_values ? 'scheduled_start_at' then nullif(task_values->>'scheduled_start_at', '')::timestamptz else task.scheduled_start_at end,
    scheduled_end_at = case when task_values ? 'scheduled_end_at' then nullif(task_values->>'scheduled_end_at', '')::timestamptz else task.scheduled_end_at end,
    due_date = case when task_values ? 'due_date' then nullif(task_values->>'due_date', '')::date else task.due_date end,
    estimated_minutes = case when task_values ? 'estimated_minutes' then (task_values->>'estimated_minutes')::integer else task.estimated_minutes end,
    estimated_pomodoros = case when task_values ? 'estimated_pomodoros' then (task_values->>'estimated_pomodoros')::integer else task.estimated_pomodoros end,
    actual_focused_minutes = case when task_values ? 'actual_focused_minutes' then (task_values->>'actual_focused_minutes')::integer else task.actual_focused_minutes end,
    recurrence = case when task_values ? 'recurrence' then nullif(task_values->>'recurrence', '') else task.recurrence end,
    recurrence_rule = case when task_values ? 'recurrence_rule' then nullif(task_values->>'recurrence_rule', '') else task.recurrence_rule end,
    recurrence_timezone = case when task_values ? 'recurrence_timezone' then coalesce(nullif(task_values->>'recurrence_timezone', ''), 'UTC') else task.recurrence_timezone end,
    recurrence_end_at = case when task_values ? 'recurrence_end_at' then nullif(task_values->>'recurrence_end_at', '')::timestamptz else task.recurrence_end_at end,
    recurrence_end_type = case when task_values ? 'recurrence_end_type' then task_values->>'recurrence_end_type' else task.recurrence_end_type end,
    recurrence_maximum_occurrences = case when task_values ? 'recurrence_maximum_occurrences' then nullif(task_values->>'recurrence_maximum_occurrences', '')::integer else task.recurrence_maximum_occurrences end,
    recurrence_paused_at = case when task_values ? 'recurrence_paused_at' then nullif(task_values->>'recurrence_paused_at', '')::timestamptz else task.recurrence_paused_at end,
    adaptive_reminders_enabled = case when task_values ? 'adaptive_reminders_enabled' then (task_values->>'adaptive_reminders_enabled')::boolean else task.adaptive_reminders_enabled end,
    reminder_rules = case when task_values ? 'reminder_rules' then coalesce(task_values->'reminder_rules', '{}'::jsonb) else task.reminder_rules end,
    location = case when task_values ? 'location' then nullif(task_values->>'location', '') else task.location end,
    calendar_integration = case when task_values ? 'calendar_integration' then (task_values->>'calendar_integration')::boolean else task.calendar_integration end,
    completion_rules = case when task_values ? 'completion_rules' then coalesce(task_values->'completion_rules', '{}'::jsonb) else task.completion_rules end,
    timer_enabled = case when task_values ? 'timer_enabled' then (task_values->>'timer_enabled')::boolean else task.timer_enabled end,
    habit_current_streak = case when task_values ? 'habit_current_streak' then (task_values->>'habit_current_streak')::integer else task.habit_current_streak end,
    habit_longest_streak = case when task_values ? 'habit_longest_streak' then (task_values->>'habit_longest_streak')::integer else task.habit_longest_streak end,
    learning_resource_link = case when task_values ? 'learning_resource_link' then nullif(task_values->>'learning_resource_link', '') else task.learning_resource_link end,
    launch_method = case when task_values ? 'launch_method' then nullif(task_values->>'launch_method', '') else task.launch_method end,
    notes = case when task_values ? 'notes' then coalesce(task_values->>'notes', '') else task.notes end,
    checklist = case when task_values ? 'checklist' then coalesce(task_values->'checklist', '[]'::jsonb) else task.checklist end,
    tags = case when task_values ? 'tags' then array(select jsonb_array_elements_text(task_values->'tags')) else task.tags end,
    progress_percentage = case when task_values ? 'progress_percentage' then (task_values->>'progress_percentage')::integer else task.progress_percentage end,
    difficulty = case when task_values ? 'difficulty' then (task_values->>'difficulty')::integer else task.difficulty end,
    energy_requirement = case when task_values ? 'energy_requirement' then (task_values->>'energy_requirement')::integer else task.energy_requirement end,
    context = case when task_values ? 'context' then nullif(task_values->>'context', '') else task.context end,
    attachments = case when task_values ? 'attachments' then coalesce(task_values->'attachments', '[]'::jsonb) else task.attachments end,
    completion_evidence = case when task_values ? 'completion_evidence' then nullif(task_values->>'completion_evidence', '') else task.completion_evidence end,
    dependencies = case when task_values ? 'dependencies' then array(select jsonb_array_elements_text(task_values->'dependencies')) else task.dependencies end,
    workspace_enabled = case when task_values ? 'workspace_enabled' then (task_values->>'workspace_enabled')::boolean else task.workspace_enabled end,
    workspace_type = case when task_values ? 'workspace_type' then task_values->>'workspace_type' else task.workspace_type end,
    workspace_starting_url = case when task_values ? 'workspace_starting_url' then nullif(task_values->>'workspace_starting_url', '') else task.workspace_starting_url end,
    workspace_home_url = case when task_values ? 'workspace_home_url' then nullif(task_values->>'workspace_home_url', '') else task.workspace_home_url end,
    workspace_resource_title = case when task_values ? 'workspace_resource_title' then nullif(task_values->>'workspace_resource_title', '') else task.workspace_resource_title end,
    workspace_browser_mode = case when task_values ? 'workspace_browser_mode' then task_values->>'workspace_browser_mode' else task.workspace_browser_mode end,
    workspace_allowed_domains = case when task_values ? 'workspace_allowed_domains' then array(select jsonb_array_elements_text(task_values->'workspace_allowed_domains')) else task.workspace_allowed_domains end,
    workspace_restore_last_page = case when task_values ? 'workspace_restore_last_page' then (task_values->>'workspace_restore_last_page')::boolean else task.workspace_restore_last_page end,
    workspace_open_automatically = case when task_values ? 'workspace_open_automatically' then (task_values->>'workspace_open_automatically')::boolean else task.workspace_open_automatically end,
    workspace_preferred_layout = case when task_values ? 'workspace_preferred_layout' then task_values->>'workspace_preferred_layout' else task.workspace_preferred_layout end,
    workspace_preferred_dock_state = case when task_values ? 'workspace_preferred_dock_state' then task_values->>'workspace_preferred_dock_state' else task.workspace_preferred_dock_state end,
    workspace_allow_external_navigation = case when task_values ? 'workspace_allow_external_navigation' then (task_values->>'workspace_allow_external_navigation')::boolean else task.workspace_allow_external_navigation end,
    workspace_open_unsupported_externally = case when task_values ? 'workspace_open_unsupported_externally' then (task_values->>'workspace_open_unsupported_externally')::boolean else task.workspace_open_unsupported_externally end,
    workspace_navigation_mode = case when task_values ? 'workspace_navigation_mode' then task_values->>'workspace_navigation_mode' else task.workspace_navigation_mode end,
    workspace_restore_browser_session = case when task_values ? 'workspace_restore_browser_session' then (task_values->>'workspace_restore_browser_session')::boolean else task.workspace_restore_browser_session end,
    workspace_restore_open_tabs = case when task_values ? 'workspace_restore_open_tabs' then (task_values->>'workspace_restore_open_tabs')::boolean else task.workspace_restore_open_tabs end,
    workspace_open_starting_page_in_new_tab = case when task_values ? 'workspace_open_starting_page_in_new_tab' then (task_values->>'workspace_open_starting_page_in_new_tab')::boolean else task.workspace_open_starting_page_in_new_tab end,
    is_recurrence_exception = case when task_values ? 'is_recurrence_exception' then (task_values->>'is_recurrence_exception')::boolean else task.is_recurrence_exception end,
    updated_at = now()
  where task.id = target_task_id
    and task.user_id = auth.uid()
  returning task.* into updated_task;

  if updated_task.id is null then
    raise exception 'Task was not found';
  end if;
  return updated_task;
end;
$$;

create or replace function public.edit_task_with_scope(
  target_task_id uuid,
  edit_scope text,
  task_values jsonb,
  resource_values jsonb default '[]'::jsonb,
  reminder_values jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_task public.tasks%rowtype;
  result_task public.tasks%rowtype;
  affected_id uuid;
  resource_row jsonb;
  reminder_row jsonb;
  boundary timestamptz;
  effective_recurrence_id uuid;
  series_template_id uuid;
  resource_target_id uuid;
  occurrence_values jsonb;
  schedule_delta interval;
  planned_duration interval;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if edit_scope not in ('occurrence', 'future', 'series') then
    raise exception 'Unsupported edit scope';
  end if;

  select * into target_task from public.tasks
  where id = target_task_id and user_id = auth.uid() and deleted_at is null;
  if target_task.id is null then raise exception 'Task was not found'; end if;

  effective_recurrence_id := target_task.recurrence_id;
  series_template_id := coalesce(target_task.series_task_id, target_task.id);
  if effective_recurrence_id is null then
    select recurrence.id into effective_recurrence_id
    from public.task_recurrences recurrence
    where recurrence.task_id = series_template_id
      and recurrence.user_id = auth.uid()
      and recurrence.deleted_at is null
    order by recurrence.created_at desc
    limit 1;
  end if;

  boundary := coalesce(
    target_task.occurrence_original_start,
    target_task.planned_start_at,
    now()
  );
  schedule_delta := case
    when task_values ? 'planned_start_at'
      and target_task.planned_start_at is not null
      and nullif(task_values->>'planned_start_at', '') is not null
      then (task_values->>'planned_start_at')::timestamptz
        - target_task.planned_start_at
    when task_values ? 'scheduled_start_at'
      and target_task.scheduled_start_at is not null
      and nullif(task_values->>'scheduled_start_at', '') is not null
      then (task_values->>'scheduled_start_at')::timestamptz
        - target_task.scheduled_start_at
    else null
  end;
  planned_duration := case
    when nullif(task_values->>'planned_start_at', '') is not null
      and nullif(task_values->>'planned_end_at', '') is not null
      then (task_values->>'planned_end_at')::timestamptz
        - (task_values->>'planned_start_at')::timestamptz
    else null
  end;
  occurrence_values := task_values - array[
    'planned_date', 'planned_start_at', 'planned_end_at', 'due_at',
    'start_date', 'due_date', 'scheduled_start_at', 'scheduled_end_at',
    'actual_start_at', 'actual_finish_at', 'arrival_at',
    'progress_percentage', 'actual_focused_minutes', 'habit_current_streak',
    'habit_longest_streak'
  ];

  if edit_scope = 'occurrence' or effective_recurrence_id is null then
    result_task := public.apply_task_edit_payload(target_task.id, task_values);
    if effective_recurrence_id is not null then
      update public.tasks set is_recurrence_exception = true
      where id = target_task.id and user_id = auth.uid();
    end if;
  else
    for affected_id in
      select task.id from public.tasks task
      where task.user_id = auth.uid()
        and task.deleted_at is null
        and task.status not in ('completed', 'cancelled')
        and (
          task.id = series_template_id
          or task.id = target_task.id
          or (
            task.recurrence_id = effective_recurrence_id
            and task.occurrence_original_start >= case
              when edit_scope = 'series' then now()
              else boundary
            end
          )
        )
    loop
      if affected_id in (series_template_id, target_task.id) then
        perform public.apply_task_edit_payload(affected_id, task_values);
      else
        perform public.apply_task_edit_payload(affected_id, occurrence_values);
        if schedule_delta is not null then
          update public.tasks occurrence
          set planned_date = coalesce(
                (occurrence.planned_start_at + schedule_delta)::date,
                occurrence.planned_date
              ),
              planned_end_at = case
                when planned_duration is not null
                  and occurrence.planned_start_at is not null
                  then occurrence.planned_start_at + schedule_delta + planned_duration
                when occurrence.planned_end_at is not null
                  then occurrence.planned_end_at + schedule_delta
                else null
              end,
              planned_start_at = case
                when occurrence.planned_start_at is not null
                  then occurrence.planned_start_at + schedule_delta
                else null
              end,
              scheduled_end_at = case
                when planned_duration is not null
                  and occurrence.scheduled_start_at is not null
                  then occurrence.scheduled_start_at + schedule_delta + planned_duration
                when occurrence.scheduled_end_at is not null
                  then occurrence.scheduled_end_at + schedule_delta
                else null
              end,
              scheduled_start_at = case
                when occurrence.scheduled_start_at is not null
                  then occurrence.scheduled_start_at + schedule_delta
                else null
              end,
              due_at = case when occurrence.due_at is not null
                then occurrence.due_at + schedule_delta else null end,
              due_date = case when occurrence.due_date is not null
                then (occurrence.due_date::timestamp + schedule_delta)::date
                else null end,
              updated_at = now()
          where occurrence.id = affected_id
            and occurrence.user_id = auth.uid();
        end if;
      end if;
    end loop;
    select * into result_task from public.tasks
    where id = target_task.id and user_id = auth.uid();

    update public.task_recurrences recurrence
    set rrule = case when task_values ? 'recurrence_rule'
          then nullif(task_values->>'recurrence_rule', '')
          else recurrence.rrule end,
        rule = case when task_values ? 'recurrence_rule'
          then jsonb_set(
            coalesce(recurrence.rule, '{}'::jsonb),
            '{rrule}',
            to_jsonb(task_values->>'recurrence_rule')
          )
          else recurrence.rule end,
        timezone = case when task_values ? 'recurrence_timezone'
          then coalesce(nullif(task_values->>'recurrence_timezone', ''), 'UTC')
          else recurrence.timezone end,
        starts_at = case when task_values ? 'planned_start_at'
          then nullif(task_values->>'planned_start_at', '')::timestamptz
          else recurrence.starts_at end,
        duration_minutes = case when task_values ? 'estimated_minutes'
          then (task_values->>'estimated_minutes')::integer
          else recurrence.duration_minutes end,
        end_type = case when task_values ? 'recurrence_end_type'
          then task_values->>'recurrence_end_type'
          else recurrence.end_type end,
        ends_at = case when task_values ? 'recurrence_end_at'
          then nullif(task_values->>'recurrence_end_at', '')::timestamptz
          else recurrence.ends_at end,
        maximum_occurrences = case
          when task_values ? 'recurrence_maximum_occurrences'
            then nullif(task_values->>'recurrence_maximum_occurrences', '')::integer
          else recurrence.maximum_occurrences end,
        generated_until = case
          when task_values ? 'recurrence_rule'
            or task_values ? 'planned_start_at'
            then boundary - interval '1 second'
          else recurrence.generated_until end,
        updated_at = now()
    where recurrence.id = effective_recurrence_id
      and recurrence.user_id = auth.uid();
  end if;

  resource_target_id := case
    when edit_scope in ('future', 'series') then series_template_id
    else result_task.id
  end;

  update public.task_resources
  set deleted_at = now(), updated_at = now()
  where task_id = resource_target_id and user_id = auth.uid() and deleted_at is null;

  for resource_row in select value from jsonb_array_elements(coalesce(resource_values, '[]'::jsonb))
  loop
    insert into public.task_resources (
      id, user_id, task_id, name, title, url, normalized_domain,
      resource_type, open_mode, open_behavior, description, sort_order,
      is_default, is_starting_page, is_required, is_favorite,
      open_automatically, series_resource_id, is_occurrence_override, is_hidden,
      created_at, updated_at, deleted_at
    ) values (
      coalesce(nullif(resource_row->>'id', '')::uuid, extensions.gen_random_uuid()),
      auth.uid(), resource_target_id,
      coalesce(resource_row->>'name', resource_row->>'title', result_task.title),
      coalesce(resource_row->>'title', resource_row->>'name', result_task.title),
      coalesce(resource_row->>'url', ''), resource_row->>'normalized_domain',
      coalesce(resource_row->>'resource_type', 'custom'),
      coalesce(resource_row->>'open_mode', 'in_app'),
      coalesce(resource_row->>'open_mode', 'in_app'),
      coalesce(resource_row->>'description', ''),
      coalesce((resource_row->>'sort_order')::integer, 0),
      coalesce((resource_row->>'is_default')::boolean, false),
      coalesce((resource_row->>'is_starting_page')::boolean, false),
      coalesce((resource_row->>'is_required')::boolean, false),
      coalesce((resource_row->>'is_favorite')::boolean, false),
      coalesce((resource_row->>'open_automatically')::boolean, false),
      nullif(resource_row->>'series_resource_id', '')::uuid,
      coalesce((resource_row->>'is_occurrence_override')::boolean, false),
      coalesce((resource_row->>'is_hidden')::boolean, false),
      now(), now(), null
    )
    on conflict (id) do update set
      task_id = excluded.task_id,
      name = excluded.name,
      title = excluded.title,
      url = excluded.url,
      normalized_domain = excluded.normalized_domain,
      resource_type = excluded.resource_type,
      open_mode = excluded.open_mode,
      open_behavior = excluded.open_behavior,
      description = excluded.description,
      sort_order = excluded.sort_order,
      is_default = excluded.is_default,
      is_starting_page = excluded.is_starting_page,
      is_required = excluded.is_required,
      is_favorite = excluded.is_favorite,
      open_automatically = excluded.open_automatically,
      series_resource_id = excluded.series_resource_id,
      is_occurrence_override = excluded.is_occurrence_override,
      is_hidden = excluded.is_hidden,
      deleted_at = null,
      updated_at = now();
  end loop;

  update public.tasks
  set default_resource_id = (
        select resource.id
        from public.task_resources resource
        where resource.task_id = resource_target_id
          and resource.user_id = auth.uid()
          and resource.deleted_at is null
          and resource.is_hidden = false
          and (resource.is_default or resource.is_starting_page)
        order by resource.sort_order, resource.created_at
        limit 1
      ),
      updated_at = now()
  where id = resource_target_id and user_id = auth.uid();

  update public.task_reminders
  set status = 'cancelled', updated_at = now()
  where task_id = resource_target_id and user_id = auth.uid()
    and status <> 'cancelled' and deleted_at is null;

  for reminder_row in select value from jsonb_array_elements(coalesce(reminder_values, '[]'::jsonb))
  loop
    insert into public.task_reminders (
      id, user_id, task_id, occurrence_id, offset_minutes,
      custom_trigger_at, is_adaptive, reason, notification_id, status,
      scheduled_at, sent_at, dismissed_at, snoozed_until, updated_at
    ) values (
      coalesce(nullif(reminder_row->>'id', '')::uuid, extensions.gen_random_uuid()),
      auth.uid(), resource_target_id,
      nullif(reminder_row->>'occurrence_id', '')::uuid,
      nullif(reminder_row->>'offset_minutes', '')::integer,
      nullif(reminder_row->>'custom_trigger_at', '')::timestamptz,
      coalesce((reminder_row->>'is_adaptive')::boolean, false),
      reminder_row->>'reason', reminder_row->>'notification_id',
      coalesce(reminder_row->>'status', 'pending'),
      nullif(reminder_row->>'scheduled_at', '')::timestamptz,
      nullif(reminder_row->>'sent_at', '')::timestamptz,
      nullif(reminder_row->>'dismissed_at', '')::timestamptz,
      nullif(reminder_row->>'snoozed_until', '')::timestamptz,
      now()
    )
    on conflict (id) do update set
      task_id = excluded.task_id,
      occurrence_id = excluded.occurrence_id,
      offset_minutes = excluded.offset_minutes,
      custom_trigger_at = excluded.custom_trigger_at,
      is_adaptive = excluded.is_adaptive,
      reason = excluded.reason,
      notification_id = excluded.notification_id,
      status = excluded.status,
      scheduled_at = excluded.scheduled_at,
      snoozed_until = excluded.snoozed_until,
      deleted_at = null,
      updated_at = now();
  end loop;

  if edit_scope in ('future', 'series') and effective_recurrence_id is not null then
    update public.task_reminders reminder
    set status = 'cancelled', updated_at = now()
    where reminder.user_id = auth.uid()
      and reminder.deleted_at is null
      and reminder.status <> 'cancelled'
      and reminder.task_id in (
        select occurrence.id
        from public.tasks occurrence
        where occurrence.user_id = auth.uid()
          and occurrence.recurrence_id = effective_recurrence_id
          and occurrence.deleted_at is null
          and occurrence.status not in ('completed', 'cancelled')
          and occurrence.occurrence_original_start >= case
            when edit_scope = 'series' then now()
            else boundary
          end
      );

    insert into public.task_reminders (
      id, user_id, task_id, occurrence_id, offset_minutes,
      custom_trigger_at, is_adaptive, reason, notification_id, status,
      scheduled_at, updated_at
    )
    select
      extensions.gen_random_uuid(), auth.uid(), occurrence.id, occurrence.id,
      nullif(reminder.value->>'offset_minutes', '')::integer,
      null,
      coalesce((reminder.value->>'is_adaptive')::boolean, false),
      reminder.value->>'reason',
      null,
      'pending',
      coalesce(
        occurrence.planned_start_at,
        occurrence.scheduled_start_at,
        occurrence.due_at
      ) - make_interval(
        mins => coalesce(
          nullif(reminder.value->>'offset_minutes', '')::integer,
          0
        )
      ),
      now()
    from public.tasks occurrence
    cross join lateral jsonb_array_elements(
      coalesce(reminder_values, '[]'::jsonb)
    ) reminder(value)
    where occurrence.user_id = auth.uid()
      and occurrence.recurrence_id = effective_recurrence_id
      and occurrence.deleted_at is null
      and occurrence.status not in ('completed', 'cancelled')
      and occurrence.occurrence_original_start >= case
        when edit_scope = 'series' then now()
        else boundary
      end
      and coalesce(
        occurrence.planned_start_at,
        occurrence.scheduled_start_at,
        occurrence.due_at
      ) is not null;
  end if;

  select * into result_task from public.tasks
  where id = result_task.id and user_id = auth.uid();
  return jsonb_build_object('task', to_jsonb(result_task));
end;
$$;

create or replace function public.skip_task_occurrence(target_task_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_task public.tasks%rowtype;
begin
  select * into target_task from public.tasks
  where id = target_task_id and user_id = auth.uid() and deleted_at is null;
  if target_task.id is null then raise exception 'Task was not found'; end if;

  update public.tasks
  set status = 'cancelled', skipped_at = now(),
      is_recurrence_exception = true, updated_at = now()
  where id = target_task.id and user_id = auth.uid();

  if target_task.recurrence_id is not null
     and target_task.occurrence_original_start is not null then
    insert into public.task_recurrence_exclusions (
      user_id, recurrence_id, occurrence_original_start, reason, task_id
    ) values (
      auth.uid(), target_task.recurrence_id,
      target_task.occurrence_original_start, 'skipped', target_task.id
    )
    on conflict (user_id, recurrence_id, occurrence_original_start)
    do update set reason = 'skipped', deleted_at = null, updated_at = now();
  end if;
  return jsonb_build_object('task_id', target_task.id, 'status', 'skipped');
end;
$$;

create or replace function public.set_task_recurrence_state(
  target_task_id uuid,
  requested_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_task public.tasks%rowtype;
  target_recurrence_id uuid;
begin
  if requested_action not in ('pause', 'resume', 'end') then
    raise exception 'Unsupported recurrence action';
  end if;
  select * into target_task from public.tasks
  where id = target_task_id and user_id = auth.uid() and deleted_at is null;
  if target_task.id is null then raise exception 'Task was not found'; end if;

  target_recurrence_id := target_task.recurrence_id;
  if target_recurrence_id is null then
    select id into target_recurrence_id from public.task_recurrences
    where task_id = coalesce(target_task.series_task_id, target_task.id)
      and user_id = auth.uid() and deleted_at is null
    order by created_at desc limit 1;
  end if;
  if target_recurrence_id is null then raise exception 'Recurring series was not found'; end if;

  update public.task_recurrences
  set is_active = requested_action = 'resume',
      ends_at = case when requested_action = 'end' then now() else ends_at end,
      updated_at = now()
  where id = target_recurrence_id and user_id = auth.uid();

  update public.tasks
  set recurrence_paused_at = case
        when requested_action = 'resume' then null else now()
      end,
      updated_at = now()
  where user_id = auth.uid()
    and deleted_at is null
    and (recurrence_id = target_recurrence_id
      or id = coalesce(target_task.series_task_id, target_task.id));

  return jsonb_build_object(
    'recurrence_id', target_recurrence_id,
    'state', requested_action
  );
end;
$$;

grant execute on function public.apply_task_edit_payload(uuid, jsonb)
to authenticated;
grant execute on function public.edit_task_with_scope(uuid, text, jsonb, jsonb, jsonb)
to authenticated;
grant execute on function public.skip_task_occurrence(uuid)
to authenticated;
grant execute on function public.set_task_recurrence_state(uuid, text)
to authenticated;
