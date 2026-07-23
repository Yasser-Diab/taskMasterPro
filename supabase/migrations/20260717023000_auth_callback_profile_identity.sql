-- Version 0.1.1: account identity, private avatars, and confirmed-email sync.
--
-- Hosted Supabase Authentication URL configuration is managed in the
-- Dashboard/API, not by a database migration. Production redirect URLs must
-- include:
--   taskmasterpro://auth/callback
--   taskmasterpro://auth/**

alter table public.profiles
  add column if not exists username text,
  add column if not exists avatar_path text,
  add column if not exists pending_email text,
  add column if not exists email_change_requested_at timestamptz;

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

drop policy if exists avatars_select_own
on storage.objects;

drop policy if exists avatars_insert_own
on storage.objects;

drop policy if exists avatars_update_own
on storage.objects;

drop policy if exists avatars_delete_own
on storage.objects;

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

create or replace function public.sync_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set email = lower(new.email),
      pending_email = case
        when lower(coalesce(pending_email, '')) = lower(coalesce(new.email, ''))
          then null
        else pending_email
      end,
      email_change_requested_at = case
        when lower(coalesce(pending_email, '')) = lower(coalesce(new.email, ''))
          then null
        else email_change_requested_at
      end,
      updated_at = now()
  where id = new.id;

  return new;
end;
$$;

drop trigger if exists sync_profile_email_after_auth_update
on auth.users;

create trigger sync_profile_email_after_auth_update
after update of email, email_confirmed_at
on auth.users
for each row
execute function public.sync_profile_email_from_auth();

create or replace function public.bootstrap_current_user()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_email text;
  current_meta jsonb := '{}'::jsonb;
  assigned_role text;
  owner_installation jsonb := '{}'::jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(email), coalesce(raw_user_meta_data, '{}'::jsonb)
  into current_email, current_meta
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
    coalesce(nullif(current_meta ->> 'full_name', ''), current_email),
    case
      when current_meta ->> 'preferred_language' in ('ar', 'en', 'de')
        then current_meta ->> 'preferred_language'
      else 'en'
    end,
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
    begin
      owner_installation := public.install_owner_template_if_needed();
    exception when undefined_function then
      owner_installation := '{}'::jsonb;
    end;
  end if;

  return jsonb_build_object(
    'user_id', current_user_id,
    'email', current_email,
    'role', assigned_role,
    'owner_template', owner_installation
  );
end;
$$;

revoke all
on function public.bootstrap_current_user()
from public;

grant execute
on function public.bootstrap_current_user()
to authenticated;
