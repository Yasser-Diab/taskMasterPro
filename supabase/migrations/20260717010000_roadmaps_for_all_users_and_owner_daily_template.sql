-- Version 0.1.1: personal roadmap creation for every authenticated user,
-- roadmap child-table ownership, safer phase uniqueness, performance indexes,
-- and the private owner recurring schedule template.

create table if not exists public.roadmaps (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  description text not null default '',
  current_level text,
  target_level text,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'paused', 'completed', 'archived')),
  start_date date not null default current_date,
  original_target_date date,
  current_target_date date,
  forecast_finish_date date,
  weekly_capacity_minutes integer not null default 0 check (weekly_capacity_minutes >= 0),
  maximum_daily_minutes integer not null default 0 check (maximum_daily_minutes >= 0),
  preferred_days integer[] not null default '{}'::integer[],
  scheduling_mode text not null default 'capacity_driven'
    check (scheduling_mode in ('deadline_driven', 'capacity_driven', 'balanced')),
  overall_progress numeric(5,2) not null default 0 check (overall_progress between 0 and 100),
  confidence integer check (confidence between 1 and 5),
  color_seed text not null default '#3B82F6',
  icon_name text,
  template_key text,
  template_version integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.roadmaps
  alter column user_id set default auth.uid(),
  alter column status set default 'draft';

alter table public.roadmaps
  add column if not exists color_seed text not null default '#3B82F6',
  add column if not exists icon_name text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'roadmaps_weekly_capacity_minutes_nonnegative'
      and conrelid = 'public.roadmaps'::regclass
  ) then
    alter table public.roadmaps
      add constraint roadmaps_weekly_capacity_minutes_nonnegative
      check (weekly_capacity_minutes >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'roadmaps_maximum_daily_minutes_nonnegative'
      and conrelid = 'public.roadmaps'::regclass
  ) then
    alter table public.roadmaps
      add constraint roadmaps_maximum_daily_minutes_nonnegative
      check (maximum_daily_minutes >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'roadmaps_overall_progress_range'
      and conrelid = 'public.roadmaps'::regclass
  ) then
    alter table public.roadmaps
      add constraint roadmaps_overall_progress_range
      check (overall_progress between 0 and 100);
  end if;
end;
$$;

alter table public.roadmap_phases
  add column if not exists roadmap_id uuid references public.roadmaps(id) on delete cascade;

alter table public.roadmap_items
  add column if not exists roadmap_id uuid references public.roadmaps(id) on delete cascade;

alter table public.roadmap_forecasts
  add column if not exists roadmap_id uuid references public.roadmaps(id) on delete cascade;

alter table public.roadmap_adjustment_proposals
  add column if not exists roadmap_id uuid references public.roadmaps(id) on delete cascade;

alter table public.roadmap_snapshots
  add column if not exists roadmap_id uuid references public.roadmaps(id) on delete cascade;

do $$
declare
  constraint_row record;
begin
  for constraint_row in
    select conname
    from pg_constraint
    where conrelid = 'public.roadmap_phases'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) ilike '%user_id%'
      and pg_get_constraintdef(oid) ilike '%phase_number%'
  loop
    execute format(
      'alter table public.roadmap_phases drop constraint if exists %I',
      constraint_row.conname
    );
  end loop;
end;
$$;

create unique index if not exists roadmap_phases_roadmap_phase_number_unique
on public.roadmap_phases (roadmap_id, phase_number)
where deleted_at is null;

alter table public.roadmaps enable row level security;
alter table public.roadmap_phases enable row level security;
alter table public.roadmap_items enable row level security;
alter table public.roadmap_dependencies enable row level security;
alter table public.roadmap_forecasts enable row level security;
alter table public.roadmap_adjustment_proposals enable row level security;
alter table public.roadmap_snapshots enable row level security;

drop policy if exists roadmaps_select_own on public.roadmaps;
drop policy if exists roadmaps_insert_own on public.roadmaps;
drop policy if exists roadmaps_update_own on public.roadmaps;
drop policy if exists roadmaps_delete_own on public.roadmaps;

create policy roadmaps_select_own on public.roadmaps
for select to authenticated
using (user_id = auth.uid());

create policy roadmaps_insert_own on public.roadmaps
for insert to authenticated
with check (user_id = auth.uid());

create policy roadmaps_update_own on public.roadmaps
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy roadmaps_delete_own on public.roadmaps
for delete to authenticated
using (user_id = auth.uid());

drop policy if exists roadmap_phases_select_own on public.roadmap_phases;
drop policy if exists roadmap_phases_insert_own on public.roadmap_phases;
drop policy if exists roadmap_phases_update_own on public.roadmap_phases;
drop policy if exists roadmap_phases_delete_own on public.roadmap_phases;

create policy roadmap_phases_select_own on public.roadmap_phases
for select to authenticated
using (user_id = auth.uid());

create policy roadmap_phases_insert_own on public.roadmap_phases
for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.roadmaps r
    where r.id = roadmap_id
      and r.user_id = auth.uid()
      and r.deleted_at is null
  )
);

create policy roadmap_phases_update_own on public.roadmap_phases
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy roadmap_phases_delete_own on public.roadmap_phases
for delete to authenticated
using (user_id = auth.uid());

drop policy if exists roadmap_items_select_own on public.roadmap_items;
drop policy if exists roadmap_items_insert_own on public.roadmap_items;
drop policy if exists roadmap_items_update_own on public.roadmap_items;
drop policy if exists roadmap_items_delete_own on public.roadmap_items;

create policy roadmap_items_select_own on public.roadmap_items
for select to authenticated
using (user_id = auth.uid());

create policy roadmap_items_insert_own on public.roadmap_items
for insert to authenticated
with check (
  user_id = auth.uid()
  and (
    roadmap_id is null
    or exists (
      select 1
      from public.roadmaps r
      where r.id = roadmap_id
        and r.user_id = auth.uid()
        and r.deleted_at is null
    )
  )
);

create policy roadmap_items_update_own on public.roadmap_items
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy roadmap_items_delete_own on public.roadmap_items
for delete to authenticated
using (user_id = auth.uid());

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'roadmap_dependencies',
    'roadmap_forecasts',
    'roadmap_adjustment_proposals',
    'roadmap_snapshots',
    'roadmap_velocity_snapshots'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I enable row level security', table_name);
      execute format('drop policy if exists %I on public.%I', table_name || '_select_own', table_name);
      execute format('drop policy if exists %I on public.%I', table_name || '_insert_own', table_name);
      execute format('drop policy if exists %I on public.%I', table_name || '_update_own', table_name);
      execute format('drop policy if exists %I on public.%I', table_name || '_delete_own', table_name);
      execute format('create policy %I on public.%I for select to authenticated using (user_id = auth.uid())', table_name || '_select_own', table_name);
      execute format('create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid())', table_name || '_insert_own', table_name);
      execute format('create policy %I on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', table_name || '_update_own', table_name);
      execute format('create policy %I on public.%I for delete to authenticated using (user_id = auth.uid())', table_name || '_delete_own', table_name);
    end if;
  end loop;
end;
$$;

grant select, insert, update, delete on public.roadmaps to authenticated;
grant select, insert, update, delete on public.roadmap_phases to authenticated;
grant select, insert, update, delete on public.roadmap_items to authenticated;
grant select, insert, update, delete on public.roadmap_dependencies to authenticated;
grant select, insert, update, delete on public.roadmap_forecasts to authenticated;
grant select, insert, update, delete on public.roadmap_adjustment_proposals to authenticated;
grant select, insert, update, delete on public.roadmap_snapshots to authenticated;
grant select, insert, update, delete on public.roadmap_velocity_snapshots to authenticated;

create index if not exists tasks_user_deleted_status_idx
on public.tasks(user_id, deleted_at, status);

create index if not exists tasks_user_due_idx
on public.tasks(user_id, due_date)
where deleted_at is null;

create index if not exists tasks_user_updated_idx
on public.tasks(user_id, updated_at desc);

create index if not exists task_recurrences_user_active_idx
on public.task_recurrences(user_id, is_active)
where deleted_at is null;

create index if not exists roadmaps_user_updated_idx
on public.roadmaps(user_id, updated_at desc)
where deleted_at is null;

create index if not exists roadmap_phases_user_roadmap_idx
on public.roadmap_phases(user_id, roadmap_id, phase_number)
where deleted_at is null;

revoke all on function public._ensure_owner_task(
  uuid,
  text,
  text,
  text,
  text,
  integer,
  text,
  text,
  timestamptz,
  integer,
  text,
  text
) from public, anon, authenticated;

create or replace function public.install_owner_daily_schedule_if_needed()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user uuid := auth.uid();
begin
  if target_user is null or not public.is_owner(target_user) then
    raise exception 'owner role required';
  end if;

  insert into public.user_template_installations (
    user_id,
    template_key,
    template_version
  )
  values (
    target_user,
    'yasser_daily_roadmap_v1',
    1
  )
  on conflict (user_id, template_key, template_version) do update
  set deleted_at = null,
      updated_at = now();

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_morning_programming',
    'Morning programming study',
    'Programming Learning',
    'high',
    55,
    'Saturday through Thursday at 05:30',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,SU,MO,TU,WE,TH',
    (current_date::timestamp + time '05:30') at time zone 'Africa/Cairo',
    55,
    'https://developer.mozilla.org/',
    'interactive'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_evening_practice_project',
    'Programming practice or project work',
    'Programming Practice',
    'high',
    55,
    'Saturday, Monday and Wednesday at 21:00',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,MO,WE',
    (current_date::timestamp + time '21:00') at time zone 'Africa/Cairo',
    55,
    'https://github.com/',
    'interactive'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_light_review_recovery',
    'Light review or recovery',
    'Rest and Recreation',
    'normal',
    30,
    'Sunday, Tuesday and Thursday at 21:00',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SU,TU,TH',
    (current_date::timestamp + time '21:00') at time zone 'Africa/Cairo',
    30,
    null,
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_german_micro_practice',
    'German micro-practice',
    'German',
    'normal',
    15,
    'Saturday through Thursday',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,SU,MO,TU,WE,TH',
    (current_date::timestamp + time '06:30') at time zone 'Africa/Cairo',
    15,
    'https://www.duolingo.com/',
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_german_focused',
    'German focused session',
    'German',
    'high',
    60,
    'Saturday and Friday',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,FR',
    (current_date::timestamp + time '16:00') at time zone 'Africa/Cairo',
    60,
    'https://www.duolingo.com/',
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_main_workday',
    'Main workday',
    'Main Job',
    'critical',
    510,
    'Saturday through Thursday, 09:00-17:30',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,SU,MO,TU,WE,TH',
    (current_date::timestamp + time '09:00') at time zone 'Africa/Cairo',
    510,
    null,
    'interactive'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_protected_family_time',
    'Protected family time',
    'Family',
    'high',
    120,
    'Every day at 19:00',
    'FREQ=DAILY;INTERVAL=1',
    (current_date::timestamp + time '19:00') at time zone 'Africa/Cairo',
    120,
    null,
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_laundry_tuesday',
    'Laundry - start, transfer or hang, fold and store',
    'Household',
    'normal',
    30,
    'Tuesday',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=TU',
    (current_date::timestamp + time '18:30') at time zone 'Africa/Cairo',
    30,
    null,
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_laundry_friday',
    'Laundry - start, transfer or hang, fold and store',
    'Household',
    'normal',
    30,
    'Friday',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR',
    (current_date::timestamp + time '10:30') at time zone 'Africa/Cairo',
    30,
    null,
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_weekly_review',
    'Weekly roadmap review',
    'Weekly Review',
    'high',
    60,
    'Friday at 06:00',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR',
    (current_date::timestamp + time '06:00') at time zone 'Africa/Cairo',
    60,
    null,
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_friday_project_block',
    'Friday project-building block',
    'Project Building',
    'high',
    180,
    'Friday at 07:15',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR',
    (current_date::timestamp + time '07:15') at time zone 'Africa/Cairo',
    180,
    'https://github.com/',
    'interactive'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_friday_household_shopping',
    'Friday household and shopping block',
    'Household',
    'normal',
    90,
    'Friday at 10:30',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=FR',
    (current_date::timestamp + time '10:30') at time zone 'Africa/Cairo',
    90,
    null,
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_friends_sisters_rotation',
    'Friends and sisters contact rotation',
    'Friends and Sisters',
    'normal',
    20,
    'Twice weekly',
    'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,WE',
    (current_date::timestamp + time '18:00') at time zone 'Africa/Cairo',
    20,
    null,
    'manual'
  );

  perform public._ensure_owner_task(
    target_user,
    'yasser_daily_roadmap_v1_daily_closing_review',
    'Daily closing review',
    'Weekly Review',
    'normal',
    5,
    'Every day at 23:15',
    'FREQ=DAILY;INTERVAL=1',
    (current_date::timestamp + time '23:15') at time zone 'Africa/Cairo',
    5,
    null,
    'manual'
  );

  return jsonb_build_object(
    'installed', true,
    'template_key', 'yasser_daily_roadmap_v1',
    'template_version', 1
  );
end;
$$;

revoke all on function public.install_owner_daily_schedule_if_needed() from public, anon;
grant execute on function public.install_owner_daily_schedule_if_needed() to authenticated;
