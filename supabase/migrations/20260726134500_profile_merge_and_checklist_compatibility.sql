-- TaskMaster Pro v0.0.26
-- Resolve the account-owned profile by auth.uid() so clients never need the
-- server-generated profile row id. Checklist compatibility is handled in the
-- client before submission; this function keeps profile updates merge-safe.

create or replace function public.apply_profile_merge_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_base_revision bigint,
  p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  profile_id uuid;
  current_revision bigint;
  actual_revision bigint;
  existing_result jsonb;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.account_devices
    where user_id = owner_id
      and id = p_device_id
      and revoked_at is null
      and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':' || p_command_id::text, 0)
  );

  select result
  into existing_result
  from public.processed_commands
  where user_id = owner_id and command_id = p_command_id;

  if found then
    return existing_result;
  end if;

  select id, revision
  into profile_id, current_revision
  from public.profiles
  where user_id = owner_id and deleted_at is null
  for update;

  if profile_id is null then
    raise exception 'missing_profile';
  end if;

  update public.profiles
  set
    email = case
      when p_payload ? 'email' then p_payload ->> 'email'
      else email
    end,
    display_name = case
      when p_payload ? 'display_name'
        then coalesce(p_payload ->> 'display_name', '')
      else display_name
    end,
    username = case
      when p_payload ? 'username' then nullif(p_payload ->> 'username', '')
      else username
    end,
    profile_image_path = case
      when p_payload ? 'profile_image_path'
        then nullif(p_payload ->> 'profile_image_path', '')
      else profile_image_path
    end,
    gender_identity = case
      when p_payload ? 'gender_identity'
        then nullif(p_payload ->> 'gender_identity', '')
      else gender_identity
    end,
    date_of_birth = case
      when p_payload ? 'date_of_birth'
        then nullif(p_payload ->> 'date_of_birth', '')::date
      else date_of_birth
    end,
    onboarding_completed_at = case
      when p_payload ? 'onboarding_completed_at'
        then nullif(p_payload ->> 'onboarding_completed_at', '')::timestamptz
      else onboarding_completed_at
    end,
    data = case
      when p_payload ? 'data'
        then coalesce(data, '{}'::jsonb) ||
             coalesce(p_payload -> 'data', '{}'::jsonb)
      else data
    end,
    updated_by_device_id = p_device_id,
    last_command_id = p_command_id
  where id = profile_id and user_id = owner_id
  returning revision into actual_revision;

  result_payload := jsonb_build_object(
    'status', 'accepted',
    'entity_type', 'profiles',
    'entity_id', profile_id,
    'revision', actual_revision,
    'merged', current_revision <> p_base_revision
  );

  insert into public.processed_commands (
    user_id,
    command_id,
    device_id,
    device_sequence,
    entity_type,
    entity_id,
    command_type,
    base_revision,
    status,
    result,
    created_by_device_id,
    updated_by_device_id,
    last_command_id
  )
  values (
    owner_id,
    p_command_id,
    p_device_id,
    p_device_sequence,
    'profiles',
    profile_id,
    'update',
    p_base_revision,
    'accepted'::public.sync_command_status,
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

revoke all on function public.apply_profile_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) from public, anon;
grant execute on function public.apply_profile_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) to authenticated;
