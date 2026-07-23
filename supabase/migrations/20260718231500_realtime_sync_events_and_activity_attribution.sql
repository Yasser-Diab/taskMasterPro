-- Durable, user-scoped realtime invalidation events plus activity-attribution
-- fields. These rows are not the source of truth; they tell connected devices
-- which authoritative records to fetch from the normal tables.

create table if not exists public.sync_events (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  event_type text not null,
  revision bigint not null default 0,
  device_id text,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists sync_events_user_time_idx
on public.sync_events(user_id, occurred_at desc);

create index if not exists sync_events_entity_revision_idx
on public.sync_events(user_id, entity_type, entity_id, revision desc);

alter table public.sync_events enable row level security;

drop policy if exists sync_events_select_own on public.sync_events;
create policy sync_events_select_own on public.sync_events
for select to authenticated
using (user_id = auth.uid());

drop policy if exists sync_events_insert_own on public.sync_events;
create policy sync_events_insert_own on public.sync_events
for insert to authenticated
with check (user_id = auth.uid());

grant select, insert on public.sync_events to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sync_events'
  ) then
    alter publication supabase_realtime add table public.sync_events;
  end if;
end $$;

alter table public.task_activity_records
  add column if not exists source_task_id uuid
    references public.tasks(id) on delete set null,
  add column if not exists related_task_id uuid
    references public.tasks(id) on delete set null,
  add column if not exists related_roadmap_id uuid
    references public.roadmaps(id) on delete set null,
  add column if not exists related_phase_id uuid
    references public.roadmap_phases(id) on delete set null,
  add column if not exists normalized_domain text,
  add column if not exists registrable_domain text,
  add column if not exists credited_seconds integer not null default 0,
  add column if not exists attribution_method text,
  add column if not exists user_confirmed boolean not null default false,
  add column if not exists is_cross_task_contribution boolean not null default false;

create index if not exists task_activity_related_task_time_idx
on public.task_activity_records(user_id, related_task_id, started_at desc)
where related_task_id is not null
  and deleted_at is null;

create index if not exists task_activity_related_roadmap_time_idx
on public.task_activity_records(user_id, related_roadmap_id, related_phase_id, started_at desc)
where related_roadmap_id is not null
  and deleted_at is null;

create index if not exists task_activity_normalized_domain_time_idx
on public.task_activity_records(user_id, normalized_domain, started_at desc)
where normalized_domain is not null
  and deleted_at is null;
