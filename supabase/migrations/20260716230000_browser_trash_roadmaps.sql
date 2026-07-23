-- Stable browser workspaces, soft-delete trash support and per-user roadmap
-- planning tables.

alter table public.tasks
  add column if not exists workspace_navigation_mode text not null default 'normal'
    check (workspace_navigation_mode in ('normal', 'trusted_domains_only', 'starting_domain_only')),
  add column if not exists workspace_restore_browser_session boolean not null default true,
  add column if not exists workspace_restore_open_tabs boolean not null default true,
  add column if not exists workspace_open_starting_page_in_new_tab boolean not null default false,
  add column if not exists workspace_selected_tab_index integer not null default 0,
  add column if not exists archived_at timestamptz,
  add column if not exists deletion_reason text,
  add column if not exists deleted_previous_status text;

create table if not exists public.task_deletion_audit (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  task_id uuid references public.tasks(id) on delete set null,
  deletion_type text not null default 'soft'
    check (deletion_type in ('soft', 'restore', 'permanent', 'anonymize')),
  previous_status text,
  had_sessions boolean not null default false,
  had_notes boolean not null default false,
  had_interruptions boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.task_recurrence_exclusions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  recurrence_id uuid not null references public.task_recurrences(id) on delete cascade,
  occurrence_original_start timestamptz not null,
  reason text not null default 'deleted',
  task_id uuid references public.tasks(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, recurrence_id, occurrence_original_start)
);

create table if not exists public.roadmaps (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  current_level text,
  target_level text,
  status text not null default 'active'
    check (status in ('draft', 'active', 'paused', 'completed', 'archived')),
  start_date date not null default current_date,
  original_target_date date,
  current_target_date date,
  forecast_finish_date date,
  weekly_capacity_minutes integer not null default 0,
  maximum_daily_minutes integer not null default 0,
  preferred_days integer[] not null default '{}'::integer[],
  scheduling_mode text not null default 'capacity_driven'
    check (scheduling_mode in ('deadline_driven', 'capacity_driven', 'balanced')),
  overall_progress numeric(5,2) not null default 0,
  confidence integer check (confidence between 1 and 5),
  template_key text,
  template_version integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.roadmap_phases
  add column if not exists roadmap_id uuid references public.roadmaps(id) on delete cascade,
  add column if not exists actual_start date,
  add column if not exists actual_finish date,
  add column if not exists status text not null default 'not_started',
  add column if not exists weight numeric(8,2) not null default 1,
  add column if not exists planned_progress numeric(5,2) not null default 0,
  add column if not exists actual_hours numeric(8,2) not null default 0,
  add column if not exists next_action text,
  add column if not exists risks text[] not null default '{}'::text[];

alter table public.roadmap_items
  add column if not exists roadmap_id uuid references public.roadmaps(id) on delete cascade,
  add column if not exists item_type text not null default 'topic',
  add column if not exists weight numeric(8,2) not null default 1,
  add column if not exists actual_hours numeric(8,2) not null default 0,
  add column if not exists actual_start date,
  add column if not exists actual_finish date,
  add column if not exists is_mandatory boolean not null default true,
  add column if not exists status text not null default 'not_started',
  add column if not exists next_action text,
  add column if not exists blocked_reason text;

create table if not exists public.roadmap_velocity_snapshots (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  roadmap_id uuid not null references public.roadmaps(id) on delete cascade,
  snapshot_date date not null,
  planned_progress numeric(5,2) not null default 0,
  actual_progress numeric(5,2) not null default 0,
  focused_minutes integer not null default 0,
  rolling_four_week_minutes integer not null default 0,
  forecast_finish_date date,
  schedule_variance_days integer,
  inputs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (roadmap_id, snapshot_date)
);

create table if not exists public.roadmap_activity_events (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  roadmap_id uuid references public.roadmaps(id) on delete cascade,
  phase_id uuid references public.roadmap_phases(id) on delete set null,
  item_id uuid references public.roadmap_items(id) on delete set null,
  event_type text not null,
  summary text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'task_deletion_audit',
    'task_recurrence_exclusions',
    'roadmaps',
    'roadmap_velocity_snapshots',
    'roadmap_activity_events'
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

create index if not exists tasks_user_deleted_idx on public.tasks(user_id, deleted_at) where deleted_at is not null;
create index if not exists task_recurrence_exclusions_lookup_idx
on public.task_recurrence_exclusions(user_id, recurrence_id, occurrence_original_start)
where deleted_at is null;
create index if not exists roadmaps_user_status_idx on public.roadmaps(user_id, status) where deleted_at is null;
create index if not exists roadmap_phases_roadmap_idx on public.roadmap_phases(user_id, roadmap_id, phase_number);
create index if not exists roadmap_items_roadmap_status_idx on public.roadmap_items(user_id, roadmap_id, status);

create or replace function public.soft_delete_task(task_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_task record;
begin
  select *
  into target_task
  from public.tasks
  where id = task_id
    and user_id = auth.uid()
    and deleted_at is null;

  if target_task.id is null then
    raise exception 'Task not found';
  end if;

  update public.tasks
  set deleted_at = now(),
      deleted_previous_status = status,
      updated_at = now()
  where id = task_id
    and user_id = auth.uid();

  if target_task.recurrence_id is not null and target_task.occurrence_original_start is not null then
    insert into public.task_recurrence_exclusions (
      user_id,
      recurrence_id,
      occurrence_original_start,
      task_id,
      reason
    )
    values (
      auth.uid(),
      target_task.recurrence_id,
      target_task.occurrence_original_start,
      target_task.id,
      'deleted'
    )
    on conflict (user_id, recurrence_id, occurrence_original_start)
    do update set deleted_at = null, updated_at = now();
  end if;

  insert into public.task_deletion_audit (
    user_id,
    task_id,
    deletion_type,
    previous_status,
    had_sessions,
    had_notes,
    had_interruptions
  )
  values (
    auth.uid(),
    task_id,
    'soft',
    target_task.status,
    exists (select 1 from public.sessions where task_id = target_task.id and user_id = auth.uid()),
    exists (select 1 from public.task_notes where task_id = target_task.id and user_id = auth.uid()),
    exists (select 1 from public.task_interruptions where task_id = target_task.id and user_id = auth.uid())
  );

  return jsonb_build_object('status', 'deleted', 'task_id', task_id);
end;
$$;

grant execute on function public.soft_delete_task(uuid) to authenticated;

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
  interval_value := greatest(
    coalesce(nullif(public._rrule_token(recurrence.rrule, 'INTERVAL'), '')::integer, 1),
    1
  );
  recurrence_timezone := coalesce(recurrence.timezone, 'UTC');
  recurrence_time := coalesce(
    (recurrence.starts_at at time zone recurrence_timezone)::time,
    time '09:00'
  );
  start_day := greatest(
    (range_start at time zone recurrence_timezone)::date,
    coalesce(
      (recurrence.starts_at at time zone recurrence_timezone)::date,
      (range_start at time zone recurrence_timezone)::date
    )
  );
  end_day := least(
    (range_end at time zone recurrence_timezone)::date,
    coalesce(
      (recurrence.ends_at at time zone recurrence_timezone)::date,
      (range_end at time zone recurrence_timezone)::date
    )
  );
  current_day := start_day;

  while current_day <= end_day loop
    occurrence_start := (current_day::timestamp + recurrence_time) at time zone recurrence_timezone;
    occurrence_end := occurrence_start + make_interval(mins => recurrence.duration_minutes);

    if occurrence_start >= range_start
       and occurrence_start < range_end
       and not exists (
         select 1
         from public.task_recurrence_exclusions exclusion
         where exclusion.user_id = recurrence.user_id
           and exclusion.recurrence_id = recurrence.id
           and exclusion.occurrence_original_start = occurrence_start
           and exclusion.deleted_at is null
       )
       and not exists (
         select 1
         from public.tasks deleted_occurrence
         where deleted_occurrence.user_id = recurrence.user_id
           and deleted_occurrence.recurrence_id = recurrence.id
           and deleted_occurrence.occurrence_original_start = occurrence_start
           and deleted_occurrence.deleted_at is not null
       )
       and (
         (freq = 'DAILY'
          and ((current_day - start_day) % interval_value = 0)
          and public._rrule_day_matches(current_day, byday))
         or
         (freq = 'WEEKLY'
          and public._rrule_day_matches(current_day, byday)
          and (
            (extract(epoch from (
              date_trunc('week', current_day::timestamp)
              - date_trunc('week', start_day::timestamp)
            )) / 604800)::integer % interval_value = 0
          ))
         or
         (freq = 'MONTHLY' and (
            (bymonthday is not null
             and extract(day from current_day)::integer = bymonthday::integer)
            or
            (bymonthday is null
             and extract(day from current_day)::integer =
               extract(day from (recurrence.starts_at at time zone recurrence_timezone))::integer)
          ))
         or
         (freq = 'YEARLY'
          and extract(month from current_day)::integer =
            extract(month from (recurrence.starts_at at time zone recurrence_timezone))::integer
          and extract(day from current_day)::integer =
            extract(day from (recurrence.starts_at at time zone recurrence_timezone))::integer)
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
        workspace_navigation_mode,
        workspace_restore_browser_session,
        workspace_restore_open_tabs,
        workspace_open_starting_page_in_new_tab,
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
        template_task.workspace_navigation_mode,
        template_task.workspace_restore_browser_session,
        template_task.workspace_restore_open_tabs,
        template_task.workspace_open_starting_page_in_new_tab,
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

grant execute on function public.generate_task_occurrences(uuid, timestamptz, timestamptz) to authenticated;
