-- Version 0.1.2 follow-up: durable Android widget action events.
-- The native widget can record an action while the Flutter isolate is cold;
-- once Flutter resumes, the action is applied locally and synchronized here.

create table if not exists public.widget_action_events (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  device_id text,
  widget_kind text not null,
  command_type text not null,
  session_id uuid references public.sessions(id) on delete set null,
  task_id uuid references public.tasks(id) on delete set null,
  session_command_id uuid references public.session_commands(command_id)
    on delete set null,
  local_occurred_at timestamptz not null,
  app_received_at timestamptz,
  applied_at timestamptz,
  status text not null default 'queued',
  payload jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 0,
  constraint widget_action_events_kind_check
  check (widget_kind in ('active_timer', 'today', 'coaching')),
  constraint widget_action_events_command_check
  check (command_type in (
    'open',
    'refresh',
    'start',
    'pause',
    'resume',
    'mark_done',
    'finish_focus',
    'start_break',
    'finish_break',
    'return_to_focus',
    'finish_task'
  )),
  constraint widget_action_events_status_check
  check (status in ('queued', 'applied', 'ignored', 'failed', 'superseded'))
);

create index if not exists widget_action_events_user_time_idx
on public.widget_action_events(user_id, local_occurred_at desc);

create index if not exists widget_action_events_session_time_idx
on public.widget_action_events(user_id, session_id, local_occurred_at desc)
where session_id is not null;

create index if not exists widget_action_events_pending_idx
on public.widget_action_events(user_id, status, local_occurred_at)
where status = 'queued';

alter table public.widget_snapshots
  add column if not exists snapshot_schema_version integer not null default 1,
  add column if not exists locale text,
  add column if not exists text_direction text,
  add column if not exists theme_mode text,
  add column if not exists accent_color text,
  add column if not exists last_action_event_id uuid
    references public.widget_action_events(id) on delete set null;

alter table public.widget_snapshots
  drop constraint if exists widget_snapshots_text_direction_check,
  add constraint widget_snapshots_text_direction_check
  check (text_direction is null or text_direction in ('ltr', 'rtl'));

alter table public.widget_snapshots
  drop constraint if exists widget_snapshots_theme_mode_check,
  add constraint widget_snapshots_theme_mode_check
  check (theme_mode is null or theme_mode in ('system', 'light', 'dark'));

alter table public.widget_action_events enable row level security;

drop policy if exists widget_action_events_select_own
on public.widget_action_events;
create policy widget_action_events_select_own
on public.widget_action_events
for select to authenticated
using (user_id = auth.uid());

drop policy if exists widget_action_events_insert_own
on public.widget_action_events;
create policy widget_action_events_insert_own
on public.widget_action_events
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists widget_action_events_update_own
on public.widget_action_events;
create policy widget_action_events_update_own
on public.widget_action_events
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists widget_action_events_delete_own
on public.widget_action_events;
create policy widget_action_events_delete_own
on public.widget_action_events
for delete to authenticated
using (user_id = auth.uid());

grant select, insert, update, delete on public.widget_action_events
to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'widget_action_events'
  ) then
    alter publication supabase_realtime add table public.widget_action_events;
  end if;
end $$;
