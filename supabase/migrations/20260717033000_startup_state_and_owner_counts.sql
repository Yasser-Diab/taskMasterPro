-- Startup state used by the app before routing to Dashboard or Onboarding.

create or replace function public.get_my_startup_state()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_email text;
  current_role text;
  completed boolean;
  roadmap_count integer;
  roadmap_phase_count integer;
  roadmap_item_count integer;
  task_count integer;
  recurring_template_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(email)
  into current_email
  from auth.users
  where id = current_user_id;

  select role
  into current_role
  from public.user_roles
  where user_id = current_user_id
    and deleted_at is null
  limit 1;

  select coalesce(onboarding_completed, false)
  into completed
  from public.profiles
  where id = current_user_id;

  if completed is null then
    completed := false;
  end if;

  select count(*)
  into roadmap_count
  from public.roadmaps
  where user_id = current_user_id
    and deleted_at is null;

  select count(*)
  into roadmap_phase_count
  from public.roadmap_phases
  where user_id = current_user_id
    and deleted_at is null;

  select count(*)
  into roadmap_item_count
  from public.roadmap_items
  where user_id = current_user_id
    and deleted_at is null;

  select count(*)
  into task_count
  from public.tasks
  where user_id = current_user_id
    and coalesce(is_recurring_template, false) = false
    and deleted_at is null;

  select count(*)
  into recurring_template_count
  from public.tasks
  where user_id = current_user_id
    and coalesce(is_recurring_template, false) = true
    and deleted_at is null;

  return jsonb_build_object(
    'user_id', current_user_id,
    'email', current_email,
    'role', coalesce(current_role, 'user'),
    'onboarding_completed', completed,
    'roadmap_count', roadmap_count,
    'roadmap_phase_count', roadmap_phase_count,
    'roadmap_item_count', roadmap_item_count,
    'task_count', task_count,
    'recurring_template_count', recurring_template_count
  );
end;
$$;

revoke all
on function public.get_my_startup_state()
from public;

grant execute
on function public.get_my_startup_state()
to authenticated;

update public.profiles p
set onboarding_completed = true,
    updated_at = now()
from auth.users u
where p.id = u.id
  and lower(u.email) = 'yasserdiabhassan@gmail.com';
