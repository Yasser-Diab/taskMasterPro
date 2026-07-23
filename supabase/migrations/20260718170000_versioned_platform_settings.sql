-- TaskMaster Pro versioned synchronized settings.
--
-- Runtime/device settings are split so Windows never overwrites Android-only
-- values and Android never overwrites Windows-only values. Secrets such as raw
-- passwords, cookies, OAuth tokens, access tokens, and WebView session data do
-- not belong in these tables.

create table if not exists public.common_settings (
  user_id uuid primary key default auth.uid()
    references auth.users(id) on delete cascade,

  revision bigint not null default 0,
  updated_by_device text,

  language text not null default 'en'
    check (language in ('en', 'ar', 'de')),

  theme text not null default 'system',

  coaching_intensity text not null default 'active'
    check (
      coaching_intensity in (
        'quiet',
        'standard',
        'active',
        'persistent',
        'custom'
      )
    ),

  pomodoro_duration_minutes integer not null default 25
    check (pomodoro_duration_minutes between 1 and 240),

  break_duration_minutes integer not null default 5
    check (break_duration_minutes between 1 and 120),

  long_break_duration_minutes integer not null default 20
    check (long_break_duration_minutes between 1 and 240),

  long_break_after_sessions integer not null default 4
    check (long_break_after_sessions between 1 and 20),

  alarm_sound_selections jsonb not null default '{}'::jsonb,
  reminder_defaults jsonb not null default '{}'::jsonb,

  time_zone_mode text not null default 'device'
    check (time_zone_mode in ('device', 'fixed')),

  fixed_time_zone_id text not null default 'Africa/Cairo',
  home_time_zone_id text not null default 'Africa/Cairo',

  travel_time_zone_behavior text not null default 'ask'
    check (
      travel_time_zone_behavior in (
        'ask',
        'keep_local_clock',
        'keep_absolute_moment',
        'keep_home_time_zone'
      )
    ),

  quiet_hours_start time without time zone,
  quiet_hours_end time without time zone,

  browser_preferences jsonb not null default '{}'::jsonb,
  search_engine text not null default 'google'
    check (search_engine in ('google', 'bing', 'duckduckgo', 'custom')),
  custom_search_url text not null default '',

  activity_tracking_preferences jsonb not null default '{}'::jsonb,
  health_sync_preferences jsonb not null default '{}'::jsonb,

  -- Only non-secret password-manager preferences belong here. Credential
  -- ciphertext belongs in a separate vault table only after explicit opt-in.
  password_manager_preferences jsonb not null default '{}'::jsonb,

  privacy_options jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.android_settings (
  user_id uuid primary key default auth.uid()
    references auth.users(id) on delete cascade,

  revision bigint not null default 0,
  updated_by_device text,

  notification_channels jsonb not null default '{}'::jsonb,
  foreground_timer_service boolean not null default true,
  exact_alarm_guidance boolean not null default true,
  battery_optimization_guidance boolean not null default true,
  background_health_access boolean not null default false,
  app_permission_shortcuts jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.windows_settings (
  user_id uuid primary key default auth.uid()
    references auth.users(id) on delete cascade,

  revision bigint not null default 0,
  updated_by_device text,

  windows_notifications_enabled boolean not null default true,
  start_with_windows boolean not null default false,
  start_minimized boolean not null default false,
  minimize_to_tray boolean not null default true,
  continue_timers_after_close boolean not null default true,
  resume_after_windows_sign_in boolean not null default true,
  allow_wake_timers boolean not null default false,
  run_reminder_service_in_background boolean not null default true,
  notification_audio_settings jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.device_overrides (
  id uuid primary key default extensions.gen_random_uuid(),

  user_id uuid not null default auth.uid()
    references auth.users(id) on delete cascade,

  device_id text not null,
  platform text not null default 'unknown'
    check (
      platform in (
        'android',
        'windows',
        'ios',
        'macos',
        'linux',
        'web',
        'unknown'
      )
    ),

  revision bigint not null default 0,
  settings jsonb not null default '{}'::jsonb,
  updated_by_device text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists device_overrides_active_device_unique
on public.device_overrides(user_id, device_id)
where deleted_at is null;

create index if not exists common_settings_updated_idx
on public.common_settings(user_id, updated_at desc);

create index if not exists android_settings_updated_idx
on public.android_settings(user_id, updated_at desc);

create index if not exists windows_settings_updated_idx
on public.windows_settings(user_id, updated_at desc);

create index if not exists device_overrides_platform_idx
on public.device_overrides(user_id, platform, updated_at desc)
where deleted_at is null;

create or replace function public.increment_settings_revision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  new.revision := coalesce(old.revision, 0) + 1;
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'common_settings',
    'android_settings',
    'windows_settings',
    'device_overrides'
  ] loop
    execute format(
      'drop trigger if exists increment_%I_revision on public.%I',
      table_name,
      table_name
    );
    execute format(
      'create trigger increment_%I_revision before update on public.%I for each row execute function public.increment_settings_revision()',
      table_name,
      table_name
    );
  end loop;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'common_settings',
    'android_settings',
    'windows_settings',
    'device_overrides'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);

    execute format('drop policy if exists %I on public.%I', table_name || '_select_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_insert_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_update_own', table_name);
    execute format('drop policy if exists %I on public.%I', table_name || '_delete_own', table_name);

    execute format(
      'create policy %I on public.%I for select to authenticated using (user_id = auth.uid())',
      table_name || '_select_own',
      table_name
    );

    execute format(
      'create policy %I on public.%I for insert to authenticated with check (user_id = auth.uid())',
      table_name || '_insert_own',
      table_name
    );

    execute format(
      'create policy %I on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      table_name || '_update_own',
      table_name
    );

    execute format(
      'create policy %I on public.%I for delete to authenticated using (user_id = auth.uid())',
      table_name || '_delete_own',
      table_name
    );

    execute format(
      'grant select, insert, update, delete on public.%I to authenticated',
      table_name
    );
  end loop;
end;
$$;

-- Backfill empty rows for existing users so new clients can upsert deltas
-- without waiting for an application-side first-run path.
insert into public.common_settings (user_id)
select user_record.id
from auth.users user_record
on conflict (user_id) do nothing;

insert into public.android_settings (user_id)
select user_record.id
from auth.users user_record
on conflict (user_id) do nothing;

insert into public.windows_settings (user_id)
select user_record.id
from auth.users user_record
on conflict (user_id) do nothing;

-- Supabase linter hardening.
alter function public.increment_settings_revision() set search_path = public;
revoke all on function public.increment_settings_revision() from anon;
