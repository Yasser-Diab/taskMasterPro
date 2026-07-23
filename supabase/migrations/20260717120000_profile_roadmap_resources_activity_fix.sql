-- Version 0.1.1 follow-up:
-- Functional profile identity, private avatars, personal roadmaps for every
-- authenticated user, editable task resources, and website-activity analytics.
--
-- This migration is intentionally idempotent so it can repair a partially
-- updated Supabase project without duplicating records or weakening RLS.

-- ---------------------------------------------------------------------------
-- Profile identity and private avatars
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists username text,
  add column if not exists avatar_path text,
  add column if not exists pending_email text,
  add column if not exists email_change_requested_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_display_name_length'
  ) then
    alter table public.profiles
      add constraint profiles_display_name_length
      check (
        display_name is null
        or char_length(btrim(display_name)) between 1 and 80
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_username_length'
  ) then
    alter table public.profiles
      add constraint profiles_username_length
      check (
        username is null
        or char_length(btrim(username)) between 3 and 30
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_username_no_whitespace'
  ) then
    alter table public.profiles
      add constraint profiles_username_no_whitespace
      check (username is null or username !~ '\s');
  end if;
end;
$$;

create unique index if not exists profiles_username_lower_unique
on public.profiles (lower(username))
where username is not null
  and deleted_at is null;

alter table public.profiles enable row level security;

drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;

create policy profiles_select_own
on public.profiles
for select
to authenticated
using (id = auth.uid());

create policy profiles_update_own
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

grant select, update
on public.profiles
to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'avatars',
  'avatars',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists avatars_select_own on storage.objects;
drop policy if exists avatars_insert_own on storage.objects;
drop policy if exists avatars_update_own on storage.objects;
drop policy if exists avatars_delete_own on storage.objects;

create policy avatars_select_own
on storage.objects
for select
to authenticated
using (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

create policy avatars_insert_own
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

create policy avatars_update_own
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
)
with check (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

create policy avatars_delete_own
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and name like (auth.uid()::text || '/%')
);

-- ---------------------------------------------------------------------------
-- Personal roadmaps and selected-roadmap phase ownership
-- ---------------------------------------------------------------------------

create table if not exists public.roadmaps (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
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
  weekly_capacity_minutes integer not null default 0
    check (weekly_capacity_minutes >= 0),
  maximum_daily_minutes integer not null default 0
    check (maximum_daily_minutes >= 0),
  preferred_days integer[] not null default '{}'::integer[],
  scheduling_mode text not null default 'capacity_driven'
    check (scheduling_mode in ('deadline_driven', 'capacity_driven', 'balanced')),
  overall_progress numeric(5,2) not null default 0
    check (overall_progress between 0 and 100),
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

alter table public.roadmap_phases
  add column if not exists roadmap_id uuid
    references public.roadmaps(id) on delete cascade,
  add column if not exists status text not null default 'not_started',
  add column if not exists actual_start date,
  add column if not exists actual_finish date,
  add column if not exists weight numeric(8,2) not null default 1,
  add column if not exists planned_progress numeric(5,2) not null default 0,
  add column if not exists actual_hours numeric(8,2) not null default 0,
  add column if not exists next_action text,
  add column if not exists risks text[] not null default '{}'::text[];

alter table public.roadmap_items
  add column if not exists roadmap_id uuid
    references public.roadmaps(id) on delete cascade,
  add column if not exists item_type text not null default 'topic',
  add column if not exists weight numeric(8,2) not null default 1,
  add column if not exists actual_hours numeric(8,2) not null default 0,
  add column if not exists actual_start date,
  add column if not exists actual_finish date,
  add column if not exists is_mandatory boolean not null default true,
  add column if not exists status text not null default 'not_started',
  add column if not exists next_action text,
  add column if not exists blocked_reason text;

alter table public.tasks
  add column if not exists roadmap_id uuid
    references public.roadmaps(id) on delete set null,
  add column if not exists roadmap_phase_id uuid
    references public.roadmap_phases(id) on delete set null;

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

create index if not exists roadmaps_user_status_idx
on public.roadmaps(user_id, status)
where deleted_at is null;

create index if not exists roadmap_phases_user_roadmap_idx
on public.roadmap_phases(user_id, roadmap_id, phase_number)
where deleted_at is null;

create index if not exists roadmap_items_user_roadmap_status_idx
on public.roadmap_items(user_id, roadmap_id, status)
where deleted_at is null;

alter table public.roadmaps enable row level security;
alter table public.roadmap_phases enable row level security;
alter table public.roadmap_items enable row level security;

drop policy if exists roadmaps_select_own on public.roadmaps;
drop policy if exists roadmaps_insert_own on public.roadmaps;
drop policy if exists roadmaps_update_own on public.roadmaps;
drop policy if exists roadmaps_delete_own on public.roadmaps;

create policy roadmaps_select_own
on public.roadmaps
for select
to authenticated
using (user_id = auth.uid());

create policy roadmaps_insert_own
on public.roadmaps
for insert
to authenticated
with check (user_id = auth.uid());

create policy roadmaps_update_own
on public.roadmaps
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy roadmaps_delete_own
on public.roadmaps
for delete
to authenticated
using (user_id = auth.uid());

drop policy if exists roadmap_phases_select_own on public.roadmap_phases;
drop policy if exists roadmap_phases_insert_own on public.roadmap_phases;
drop policy if exists roadmap_phases_update_own on public.roadmap_phases;
drop policy if exists roadmap_phases_delete_own on public.roadmap_phases;

create policy roadmap_phases_select_own
on public.roadmap_phases
for select
to authenticated
using (user_id = auth.uid());

create policy roadmap_phases_insert_own
on public.roadmap_phases
for insert
to authenticated
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

create policy roadmap_phases_update_own
on public.roadmap_phases
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy roadmap_phases_delete_own
on public.roadmap_phases
for delete
to authenticated
using (user_id = auth.uid());

drop policy if exists roadmap_items_select_own on public.roadmap_items;
drop policy if exists roadmap_items_insert_own on public.roadmap_items;
drop policy if exists roadmap_items_update_own on public.roadmap_items;
drop policy if exists roadmap_items_delete_own on public.roadmap_items;

create policy roadmap_items_select_own
on public.roadmap_items
for select
to authenticated
using (user_id = auth.uid());

create policy roadmap_items_insert_own
on public.roadmap_items
for insert
to authenticated
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

create policy roadmap_items_update_own
on public.roadmap_items
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy roadmap_items_delete_own
on public.roadmap_items
for delete
to authenticated
using (user_id = auth.uid());

grant select, insert, update, delete
on public.roadmaps,
   public.roadmap_phases,
   public.roadmap_items
to authenticated;

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

-- ---------------------------------------------------------------------------
-- Editable task URLs and resources
-- ---------------------------------------------------------------------------

create table if not exists public.task_resources (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table public.task_resources
  add column if not exists normalized_domain text,
  add column if not exists resource_type text not null default 'custom',
  add column if not exists description text not null default '',
  add column if not exists sort_order integer not null default 0,
  add column if not exists open_behavior text not null default 'in_app',
  add column if not exists is_starting_page boolean not null default false,
  add column if not exists is_required boolean not null default false,
  add column if not exists is_favorite boolean not null default false,
  add column if not exists open_automatically boolean not null default false,
  add column if not exists estimated_minutes integer,
  add column if not exists roadmap_item_id uuid
    references public.roadmap_items(id) on delete set null,
  add column if not exists series_resource_id uuid
    references public.task_resources(id) on delete set null,
  add column if not exists is_occurrence_override boolean not null default false;

update public.task_resources
set url = ''
where url is null;

alter table public.task_resources
  alter column url set not null,
  alter column resource_type set default 'custom',
  alter column description set default '',
  alter column sort_order set default 0,
  alter column is_starting_page set default false,
  alter column is_required set default false,
  alter column is_favorite set default false,
  alter column open_automatically set default false,
  alter column is_occurrence_override set default false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.task_resources'::regclass
      and conname = 'task_resources_resource_type_check'
  ) then
    alter table public.task_resources
      add constraint task_resources_resource_type_check
      check (
        resource_type in (
          'course',
          'documentation',
          'article',
          'video',
          'repository',
          'exercise',
          'application',
          'deployment',
          'book',
          'reference',
          'meeting',
          'custom'
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.task_resources'::regclass
      and conname = 'task_resources_estimated_minutes_check'
  ) then
    alter table public.task_resources
      add constraint task_resources_estimated_minutes_check
      check (
        estimated_minutes is null
        or estimated_minutes >= 0
      );
  end if;
end;
$$;

create or replace function public.normalize_task_resource_domain(input_url text)
returns text
language plpgsql
immutable
as $$
declare
  cleaned text;
begin
  if input_url is null or btrim(input_url) = '' then
    return null;
  end if;

  cleaned := lower(btrim(input_url));
  cleaned := regexp_replace(cleaned, '^[a-z][a-z0-9+.-]*://', '');
  cleaned := regexp_replace(cleaned, '^www\.', '');
  cleaned := split_part(cleaned, '/', 1);
  cleaned := split_part(cleaned, '?', 1);
  cleaned := split_part(cleaned, '#', 1);
  cleaned := split_part(cleaned, ':', 1);

  return nullif(cleaned, '');
end;
$$;

update public.task_resources
set normalized_domain = public.normalize_task_resource_domain(url)
where normalized_domain is null
  and url is not null
  and url <> '';

insert into public.task_resources (
  user_id,
  task_id,
  title,
  url,
  normalized_domain,
  resource_type,
  is_starting_page,
  sort_order
)
select
  t.user_id,
  t.id,
  coalesce(nullif(t.workspace_resource_title, ''), t.title),
  coalesce(nullif(t.workspace_starting_url, ''), t.learning_resource_link),
  public.normalize_task_resource_domain(
    coalesce(nullif(t.workspace_starting_url, ''), t.learning_resource_link)
  ),
  'custom',
  true,
  0
from public.tasks t
where coalesce(
        nullif(t.workspace_starting_url, ''),
        nullif(t.learning_resource_link, '')
      ) is not null
  and t.deleted_at is null
  and not exists (
    select 1
    from public.task_resources tr
    where tr.task_id = t.id
      and tr.deleted_at is null
  );

with ranked as (
  select
    id,
    row_number() over (
      partition by task_id
      order by is_starting_page desc, sort_order, created_at, id
    ) as row_number
  from public.task_resources
  where deleted_at is null
)
update public.task_resources tr
set is_starting_page = ranked.row_number = 1
from ranked
where ranked.id = tr.id;

create index if not exists task_resources_task_sort_idx
on public.task_resources (
  user_id,
  task_id,
  sort_order
)
where deleted_at is null;

create index if not exists task_resources_domain_idx
on public.task_resources (
  user_id,
  normalized_domain
)
where deleted_at is null;

create unique index if not exists task_resources_one_starting_page_per_task
on public.task_resources(task_id)
where is_starting_page = true
  and deleted_at is null;

alter table public.task_resources enable row level security;

drop policy if exists task_resources_select_own on public.task_resources;
drop policy if exists task_resources_insert_own on public.task_resources;
drop policy if exists task_resources_update_own on public.task_resources;
drop policy if exists task_resources_delete_own on public.task_resources;

create policy task_resources_select_own
on public.task_resources
for select
to authenticated
using (user_id = auth.uid());

create policy task_resources_insert_own
on public.task_resources
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.tasks t
    where t.id = task_id
      and t.user_id = auth.uid()
      and t.deleted_at is null
  )
);

create policy task_resources_update_own
on public.task_resources
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy task_resources_delete_own
on public.task_resources
for delete
to authenticated
using (user_id = auth.uid());

grant select, insert, update, delete
on public.task_resources
to authenticated;

-- ---------------------------------------------------------------------------
-- Website activity during active tasks
-- ---------------------------------------------------------------------------

create table if not exists public.task_website_activity (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null
    references auth.users(id) on delete cascade,
  task_id uuid not null
    references public.tasks(id) on delete cascade,
  session_id uuid
    references public.sessions(id) on delete set null,
  roadmap_id uuid
    references public.roadmaps(id) on delete set null,
  roadmap_phase_id uuid
    references public.roadmap_phases(id) on delete set null,
  roadmap_item_id uuid
    references public.roadmap_items(id) on delete set null,
  task_resource_id uuid
    references public.task_resources(id) on delete set null,
  normalized_domain text not null,
  page_title text,
  visit_started_at timestamptz not null,
  visit_ended_at timestamptz,
  foreground_seconds integer not null default 0
    check (foreground_seconds >= 0),
  background_seconds integer not null default 0
    check (background_seconds >= 0),
  interaction_count integer not null default 0
    check (interaction_count >= 0),
  navigation_count integer not null default 0
    check (navigation_count >= 0),
  excluded_from_reports boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists task_website_activity_task_time_idx
on public.task_website_activity (
  user_id,
  task_id,
  visit_started_at desc
)
where deleted_at is null;

create index if not exists task_website_activity_domain_idx
on public.task_website_activity (
  user_id,
  normalized_domain,
  visit_started_at desc
)
where deleted_at is null;

create index if not exists task_website_activity_session_idx
on public.task_website_activity (
  user_id,
  session_id,
  visit_started_at desc
)
where session_id is not null
  and deleted_at is null;

alter table public.task_website_activity enable row level security;

drop policy if exists task_website_activity_select_own
on public.task_website_activity;
drop policy if exists task_website_activity_insert_own
on public.task_website_activity;
drop policy if exists task_website_activity_update_own
on public.task_website_activity;
drop policy if exists task_website_activity_delete_own
on public.task_website_activity;

create policy task_website_activity_select_own
on public.task_website_activity
for select
to authenticated
using (user_id = auth.uid());

create policy task_website_activity_insert_own
on public.task_website_activity
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.tasks t
    where t.id = task_id
      and t.user_id = auth.uid()
  )
);

create policy task_website_activity_update_own
on public.task_website_activity
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy task_website_activity_delete_own
on public.task_website_activity
for delete
to authenticated
using (user_id = auth.uid());

grant select, insert, update, delete
on public.task_website_activity
to authenticated;

-- ---------------------------------------------------------------------------
-- Performance indexes used by optimistic task actions and recurrence loading
-- ---------------------------------------------------------------------------

create index if not exists tasks_user_deleted_status_idx
on public.tasks(user_id, deleted_at, status);

create index if not exists tasks_user_due_idx
on public.tasks(user_id, due_date)
where deleted_at is null;

create index if not exists tasks_user_updated_idx
on public.tasks(user_id, updated_at desc);

create index if not exists tasks_user_scheduled_idx
on public.tasks(user_id, scheduled_start_at)
where deleted_at is null;

create index if not exists tasks_user_roadmap_phase_idx
on public.tasks(user_id, roadmap_phase_id)
where deleted_at is null;

create index if not exists task_recurrences_user_active_idx
on public.task_recurrences(user_id, is_active)
where deleted_at is null;
