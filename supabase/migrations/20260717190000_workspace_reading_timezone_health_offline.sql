-- TaskMaster Pro coordinated workspace, time-zone, reading, health and
-- offline-first upgrade. Safe to run after 20260717160000.

-- Scheduling intent remains separate from absolute UTC timestamps.
alter table public.tasks
  add column if not exists scheduled_local_date date,
  add column if not exists scheduled_local_time time without time zone,
  add column if not exists time_zone_id text not null default 'Etc/UTC',
  add column if not exists time_zone_behavior text not null default 'keep_local_clock',
  add column if not exists all_day_end_minutes integer not null default 1439,
  add column if not exists revision bigint not null default 0,
  add column if not exists field_revisions jsonb not null default '{}'::jsonb,
  add column if not exists updated_by_device text,
  add column if not exists deleted_by_device text,
  add column if not exists occurrence_key text;

update public.tasks
set scheduled_local_date = coalesce(
      scheduled_local_date,
      planned_date,
      scheduled_start_at::date,
      start_date
    ),
    scheduled_local_time = coalesce(
      scheduled_local_time,
      planned_start_at::time,
      scheduled_start_at::time
    ),
    time_zone_id = coalesce(
      nullif(time_zone_id, ''),
      nullif(recurrence_timezone, ''),
      'Etc/UTC'
    ),
    occurrence_key = coalesce(
      occurrence_key,
      case
        when series_task_id is not null and occurrence_original_start is not null
          then series_task_id::text || ':' ||
            occurrence_original_start::text || ':' ||
            coalesce(nullif(recurrence_timezone, ''), nullif(time_zone_id, ''), 'Etc/UTC')
        else null
      end
    )
where deleted_at is null;

alter table public.tasks drop constraint if exists tasks_task_type_check;
alter table public.tasks add constraint tasks_task_type_check
  check (task_type in ('focus', 'timed', 'event', 'habit', 'reading', 'manual'));

alter table public.tasks drop constraint if exists tasks_time_zone_behavior_check;
alter table public.tasks add constraint tasks_time_zone_behavior_check
  check (time_zone_behavior in ('keep_local_clock', 'keep_absolute_moment', 'home_zone'));

alter table public.tasks drop constraint if exists tasks_all_day_end_minutes_check;
alter table public.tasks add constraint tasks_all_day_end_minutes_check
  check (all_day_end_minutes between 0 and 1439);

create unique index if not exists tasks_occurrence_key_unique
on public.tasks(user_id, occurrence_key)
where occurrence_key is not null and deleted_at is null;

create index if not exists tasks_zone_schedule_idx
on public.tasks(user_id, time_zone_id, scheduled_local_date, scheduled_local_time)
where deleted_at is null;

alter table public.sessions
  add column if not exists revision bigint not null default 0,
  add column if not exists controlling_device_id text,
  add column if not exists control_lease_expires_at timestamptz;

alter table public.task_workspace_state
  add column if not exists browser_mode text not null default 'collapsed',
  add column if not exists browser_zoom numeric(5,2) not null default 1,
  add column if not exists browser_scroll_x numeric(12,2) not null default 0,
  add column if not exists browser_scroll_y numeric(12,2) not null default 0;

-- The existing ownership-validation trigger expects auth.uid(), but database
-- migrations run without an application JWT. Temporarily disable only the
-- ownership triggers attached to task_workspace_state during this backfill.

create temporary table _disabled_workspace_owner_triggers
on commit drop
as
select
  table_ns.nspname as table_schema,
  table_class.relname as table_name,
  trigger_def.tgname as trigger_name
from pg_trigger trigger_def
join pg_proc trigger_function
  on trigger_function.oid = trigger_def.tgfoid
join pg_class table_class
  on table_class.oid = trigger_def.tgrelid
join pg_namespace table_ns
  on table_ns.oid = table_class.relnamespace
where table_ns.nspname = 'public'
  and table_class.relname = 'task_workspace_state'
  and trigger_function.proname = 'validate_task_child_owner'
  and not trigger_def.tgisinternal;

do $disable_workspace_owner_triggers$
declare
  trigger_record record;
begin
  for trigger_record in
    select *
    from _disabled_workspace_owner_triggers
  loop
    execute format(
      'alter table %I.%I disable trigger %I',
      trigger_record.table_schema,
      trigger_record.table_name,
      trigger_record.trigger_name
    );
  end loop;
end;
$disable_workspace_owner_triggers$;

update public.task_workspace_state
set browser_mode = case
  when workspace_layout in ('full', 'full_browser') then 'full'
  when browser_expanded
       or workspace_layout in ('split', 'right_panel') then 'split'
  else 'collapsed'
end;

do $enable_workspace_owner_triggers$
declare
  trigger_record record;
begin
  for trigger_record in
    select *
    from _disabled_workspace_owner_triggers
  loop
    execute format(
      'alter table %I.%I enable trigger %I',
      trigger_record.table_schema,
      trigger_record.table_name,
      trigger_record.trigger_name
    );
  end loop;
end;
$enable_workspace_owner_triggers$;

alter table public.task_workspace_state
  drop constraint if exists task_workspace_state_browser_mode_check;
alter table public.task_workspace_state
  add constraint task_workspace_state_browser_mode_check
  check (browser_mode in ('collapsed', 'split', 'full'));

-- Useful break work is attributed without creating another scheduled task or
-- adding a second copy of the same minutes to the user's day.
create table if not exists public.break_contributions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  source_task_id uuid not null references public.tasks(id) on delete cascade,
  source_session_id uuid not null references public.sessions(id) on delete cascade,
  related_task_id uuid references public.tasks(id) on delete set null,
  related_book_id uuid,
  contribution_type text not null,
  duration_seconds integer not null,
  progress_value numeric(12,3),
  evidence_type text,
  evidence_reference text,
  user_confirmed boolean not null default false,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  mutation_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint break_contributions_duration_check
    check (duration_seconds >= 0 and ended_at >= started_at),
  constraint break_contributions_type_check
    check (contribution_type in (
      'rest', 'german', 'reading', 'exercise', 'another_task', 'other'
    ))
);

create table if not exists public.books (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  reading_task_id uuid not null references public.tasks(id) on delete cascade,
  title text not null,
  author text not null default '',
  edition text,
  isbn text,
  format text not null default 'physical',
  total_pages integer not null,
  current_page integer not null default 0,
  status text not null default 'planned',
  cover_reference text,
  -- This remains null unless a user explicitly uploads the book. Device paths
  -- are kept only in the local database.
  remote_file_reference text,
  web_url text,
  target_finish_date date,
  notes text not null default '',
  priority integer not null default 0,
  roadmap_id uuid references public.roadmaps(id) on delete set null,
  roadmap_phase_id uuid references public.roadmap_phases(id) on delete set null,
  revision bigint not null default 0,
  updated_by_device text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint books_pages_check
    check (total_pages > 0 and current_page between 0 and total_pages),
  constraint books_format_check
    check (format in ('physical', 'pdf', 'epub', 'web', 'audiobook', 'other')),
  constraint books_status_check
    check (status in ('planned', 'reading', 'paused', 'completed', 'abandoned'))
);

alter table public.break_contributions
  drop constraint if exists break_contributions_related_book_id_fkey;
alter table public.break_contributions
  add constraint break_contributions_related_book_id_fkey
  foreign key (related_book_id) references public.books(id) on delete set null;

create table if not exists public.reading_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  book_id uuid not null references public.books(id) on delete cascade,
  task_session_id uuid references public.sessions(id) on delete set null,
  start_page integer not null,
  end_page integer not null,
  unique_pages_advanced integer not null default 0,
  reread_pages integer not null default 0,
  duration_seconds integer not null,
  reading_mode text not null default 'external',
  started_at timestamptz not null,
  ended_at timestamptz not null,
  notes text not null default '',
  mutation_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reading_sessions_pages_check check (
    start_page >= 0 and end_page >= start_page
    and unique_pages_advanced >= 0 and reread_pages >= 0
    and unique_pages_advanced + reread_pages = end_page - start_page
  ),
  constraint reading_sessions_duration_check
    check (duration_seconds >= 0 and ended_at >= started_at),
  constraint reading_sessions_mode_check
    check (reading_mode in ('internal', 'external', 'break', 'audiobook'))
);

create index if not exists books_task_priority_idx
on public.books(user_id, reading_task_id, priority desc, created_at)
where deleted_at is null;

create index if not exists reading_sessions_book_time_idx
on public.reading_sessions(user_id, book_id, started_at desc);

create index if not exists break_contributions_related_time_idx
on public.break_contributions(user_id, related_task_id, started_at desc);

create unique index if not exists reading_sessions_mutation_unique
on public.reading_sessions(user_id, mutation_id)
where mutation_id is not null;

create unique index if not exists break_contributions_mutation_unique
on public.break_contributions(user_id, mutation_id)
where mutation_id is not null;

-- IANA zone preferences are synchronized; detected device state remains clear
-- and auditable without requiring location permission.
create table if not exists public.user_time_zone_settings (
  user_id uuid primary key default auth.uid()
    references auth.users(id) on delete cascade,
  mode text not null default 'device',
  home_time_zone_id text not null default 'Etc/UTC',
  current_time_zone_id text not null default 'Etc/UTC',
  travel_behavior text not null default 'ask',
  ask_before_adjusting boolean not null default true,
  keep_home_while_travelling boolean not null default false,
  last_detected_time_zone_id text,
  last_time_zone_change_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_time_zone_mode_check check (mode in ('device', 'fixed')),
  constraint user_time_zone_travel_check check (
    travel_behavior in ('ask', 'keep_local_clock', 'keep_absolute_moment', 'home_zone')
  )
);

create table if not exists public.health_connections (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  device_id text not null,
  provider text not null,
  connection_status text not null default 'not_connected',
  granted_data_types text[] not null default '{}'::text[],
  background_access_enabled boolean not null default false,
  keep_data_local boolean not null default false,
  last_read_at timestamptz,
  last_successful_sync_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_id, provider),
  constraint health_connections_provider_check
    check (provider in ('health_connect', 'huawei_health')),
  constraint health_connections_status_check
    check (connection_status in ('not_connected', 'connected', 'error', 'revoked'))
);

create table if not exists public.health_records (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  device_id text not null,
  provider text not null,
  source_record_id text not null,
  data_type text not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  numeric_value numeric(18,4),
  unit text,
  metadata jsonb not null default '{}'::jsonb,
  task_id uuid references public.tasks(id) on delete set null,
  task_session_id uuid references public.sessions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, provider, device_id, source_record_id),
  constraint health_records_period_check check (ended_at >= started_at)
);

create index if not exists health_records_type_time_idx
on public.health_records(user_id, data_type, started_at desc)
where deleted_at is null;

create index if not exists health_records_task_time_idx
on public.health_records(user_id, task_id, started_at desc)
where task_id is not null and deleted_at is null;

-- Durable device outbox. Payload contains user-owned entity data only and each
-- mutation ID is globally idempotent.
create table if not exists public.sync_outbox (
  mutation_id uuid primary key,
  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  device_id text not null,
  entity_type text not null,
  entity_id text not null,
  operation text not null,
  base_revision bigint not null default 0,
  changed_fields text[] not null default '{}'::text[],
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null,
  retry_count integer not null default 0,
  sync_state text not null default 'pending',
  last_error text,
  synchronized_at timestamptz,
  constraint sync_outbox_retry_check check (retry_count >= 0),
  constraint sync_outbox_state_check check (
    sync_state in ('pending', 'uploading', 'synchronized', 'conflict', 'failed')
  )
);

create index if not exists sync_outbox_pending_idx
on public.sync_outbox(user_id, device_id, created_at)
where sync_state in ('pending', 'uploading', 'failed');

-- At most one device controls the user's active timer. Expired leases are
-- replaceable; takeover is always explicit.
create table if not exists public.active_session_leases (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- A lease is claimed before the session row is created, so this UUID must
  -- not carry a premature foreign key to public.sessions.
  session_id uuid not null,
  task_id uuid not null references public.tasks(id) on delete cascade,
  controlling_device_id text not null,
  lease_acquired_at timestamptz not null default now(),
  lease_expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.active_session_leases
  drop constraint if exists active_session_leases_session_id_fkey;

create or replace function public.claim_active_session_control(
  p_session_id uuid,
  p_task_id uuid,
  p_device_id text,
  p_takeover boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  current_lease public.active_session_leases%rowtype;
  next_expiry timestamptz := now() + interval '90 seconds';
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.tasks
    where id = p_task_id and user_id = uid and deleted_at is null
  ) then raise exception 'Task was not found'; end if;

  -- Serialize first claims as well as updates. A row lock alone cannot lock a
  -- lease row that does not exist yet.
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));

  select * into current_lease from public.active_session_leases
  where user_id = uid for update;

  if current_lease.user_id is not null
     and current_lease.lease_expires_at > now()
     and current_lease.controlling_device_id <> p_device_id
     and not p_takeover then
    return jsonb_build_object(
      'granted', false,
      'controlling_device_id', current_lease.controlling_device_id,
      'session_id', current_lease.session_id,
      'task_id', current_lease.task_id,
      'lease_expires_at', current_lease.lease_expires_at
    );
  end if;

  insert into public.active_session_leases (
    user_id, session_id, task_id, controlling_device_id,
    lease_acquired_at, lease_expires_at, updated_at
  ) values (
    uid, p_session_id, p_task_id, p_device_id, now(), next_expiry, now()
  ) on conflict (user_id) do update set
    session_id = excluded.session_id,
    task_id = excluded.task_id,
    controlling_device_id = excluded.controlling_device_id,
    lease_acquired_at = excluded.lease_acquired_at,
    lease_expires_at = excluded.lease_expires_at,
    updated_at = now();

  return jsonb_build_object(
    'granted', true,
    'controlling_device_id', p_device_id,
    'session_id', p_session_id,
    'task_id', p_task_id,
    'lease_expires_at', next_expiry
  );
end;
$$;

create or replace function public.release_active_session_control(
  p_session_id uuid,
  p_device_id text
)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.active_session_leases
  where user_id = auth.uid()
    and session_id = p_session_id
    and controlling_device_id = p_device_id;
$$;

revoke all on function public.claim_active_session_control(uuid, uuid, text, boolean) from public;
grant execute on function public.claim_active_session_control(uuid, uuid, text, boolean) to authenticated;
revoke all on function public.release_active_session_control(uuid, text) from public;
grant execute on function public.release_active_session_control(uuid, text) to authenticated;

-- Revision increments are server authoritative. Clients send base_revision and
-- field revisions through the outbox for conflict diagnostics.
create or replace function public.increment_entity_revision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.revision := coalesce(old.revision, 0) + 1;
  return new;
end;
$$;

drop trigger if exists increment_tasks_revision on public.tasks;
create trigger increment_tasks_revision
before update on public.tasks for each row
execute function public.increment_entity_revision();

drop trigger if exists increment_books_revision on public.books;
create trigger increment_books_revision
before update on public.books for each row
execute function public.increment_entity_revision();

-- RLS: all synchronized data is isolated by the immutable Auth UUID.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'break_contributions', 'books', 'reading_sessions',
    'health_connections', 'health_records', 'sync_outbox',
    'active_session_leases'
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
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
  end loop;
end;
$$;

alter table public.user_time_zone_settings enable row level security;
drop policy if exists user_time_zone_settings_select_own on public.user_time_zone_settings;
drop policy if exists user_time_zone_settings_insert_own on public.user_time_zone_settings;
drop policy if exists user_time_zone_settings_update_own on public.user_time_zone_settings;
drop policy if exists user_time_zone_settings_delete_own on public.user_time_zone_settings;
create policy user_time_zone_settings_select_own on public.user_time_zone_settings
for select to authenticated using (user_id = auth.uid());
create policy user_time_zone_settings_insert_own on public.user_time_zone_settings
for insert to authenticated with check (user_id = auth.uid());
create policy user_time_zone_settings_update_own on public.user_time_zone_settings
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy user_time_zone_settings_delete_own on public.user_time_zone_settings
for delete to authenticated using (user_id = auth.uid());
grant select, insert, update, delete on public.user_time_zone_settings to authenticated;

-- Child insert policies additionally verify that the referenced parent belongs
-- to the same authenticated user.
drop policy if exists books_insert_own on public.books;
create policy books_insert_own on public.books for insert to authenticated
with check (
  user_id = auth.uid() and exists (
    select 1 from public.tasks t
    where t.id = reading_task_id and t.user_id = auth.uid() and t.deleted_at is null
  )
);

drop policy if exists reading_sessions_insert_own on public.reading_sessions;
create policy reading_sessions_insert_own on public.reading_sessions for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (select 1 from public.tasks t where t.id = task_id and t.user_id = auth.uid())
  and exists (select 1 from public.books b where b.id = book_id and b.user_id = auth.uid())
);

drop policy if exists break_contributions_insert_own on public.break_contributions;
create policy break_contributions_insert_own on public.break_contributions for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (select 1 from public.tasks t where t.id = source_task_id and t.user_id = auth.uid())
  and exists (select 1 from public.sessions s where s.id = source_session_id and s.user_id = auth.uid())
  and (related_task_id is null or exists (
    select 1 from public.tasks t where t.id = related_task_id and t.user_id = auth.uid()
  ))
);

-- Append-only histories cannot be rewritten by clients. Retention/deletion is
-- handled through dedicated, auditable backend functions.
revoke update, delete on public.reading_sessions from authenticated;
revoke update, delete on public.break_contributions from authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'break_contributions', 'books', 'reading_sessions',
    'user_time_zone_settings', 'health_connections', 'health_records'
  ] loop
    execute format('drop trigger if exists set_%I_updated_at on public.%I', table_name, table_name);
    execute format(
      'create trigger set_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      table_name, table_name
    );
  end loop;
end;
$$;

-- Supabase linter hardening: previous migrations created several helper/RPC
-- functions. Keep their search paths fixed and do not leave SECURITY DEFINER
-- routines executable by anonymous users through PostgREST.
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'public.set_updated_at()',
    'public._rrule_token(text, text)',
    'public._rrule_day_matches(date, text)',
    'public.normalize_task_resource_domain(text)',
    'public.handle_new_user_defaults()',
    'public.sync_profile_email_from_auth()',
    'public.is_owner(uuid)',
    'public.bootstrap_current_user()',
    'public.get_my_startup_state()',
    'public.export_my_data()',
    'public.request_account_deletion(text)',
    'public.cancel_account_deletion()',
    'public.owner_backend_diagnostics()',
    'public.install_owner_template_if_needed()',
    'public.install_owner_daily_schedule_if_needed()',
    'public.generate_task_occurrences(uuid, timestamptz, timestamptz)',
    'public.soft_delete_task(uuid)',
    'public.edit_task_with_scope(uuid, text, jsonb, jsonb, jsonb)',
    'public.skip_task_occurrence(uuid)',
    'public.set_task_recurrence_state(uuid, text)',
    'public.claim_active_session_control(uuid, uuid, text, boolean)',
    'public.release_active_session_control(uuid, text)'
  ] loop
    if to_regprocedure(fn) is not null then
      execute 'alter function ' || fn ||
        ' set search_path = public, extensions, auth, pg_temp';
      execute 'revoke all on function ' || fn ||
        ' from public, anon';
    end if;
  end loop;

  foreach fn in array array[
    'public.handle_new_user_defaults()',
    'public.sync_profile_email_from_auth()',
    'public.set_updated_at()',
    'public._rrule_token(text, text)',
    'public._rrule_day_matches(date, text)',
    'public.normalize_task_resource_domain(text)'
  ] loop
    if to_regprocedure(fn) is not null then
      execute 'revoke all on function ' || fn || ' from authenticated';
    end if;
  end loop;

  foreach fn in array array[
    'public.is_owner(uuid)',
    'public.bootstrap_current_user()',
    'public.get_my_startup_state()',
    'public.export_my_data()',
    'public.request_account_deletion(text)',
    'public.cancel_account_deletion()',
    'public.owner_backend_diagnostics()',
    'public.install_owner_template_if_needed()',
    'public.install_owner_daily_schedule_if_needed()',
    'public.generate_task_occurrences(uuid, timestamptz, timestamptz)',
    'public.soft_delete_task(uuid)',
    'public.edit_task_with_scope(uuid, text, jsonb, jsonb, jsonb)',
    'public.skip_task_occurrence(uuid)',
    'public.set_task_recurrence_state(uuid, text)',
    'public.claim_active_session_control(uuid, uuid, text, boolean)',
    'public.release_active_session_control(uuid, text)'
  ] loop
    if to_regprocedure(fn) is not null then
      execute 'grant execute on function ' || fn || ' to authenticated';
    end if;
  end loop;
end;
$$;
