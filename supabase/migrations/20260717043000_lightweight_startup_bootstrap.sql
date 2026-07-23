-- Keep app startup responsive. Owner template installation remains protected,
-- but it must not run inside the login bootstrap path.

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

  return jsonb_build_object(
    'user_id', current_user_id,
    'email', current_email,
    'role', assigned_role,
    'owner_template', jsonb_build_object('status', 'deferred')
  );
end;
$$;

revoke all
on function public.bootstrap_current_user()
from public;

grant execute
on function public.bootstrap_current_user()
to authenticated;

update public.profiles p
set onboarding_completed = true,
    updated_at = now()
from auth.users u
where p.id = u.id
  and lower(u.email) = 'yasserdiabhassan@gmail.com';
