-- Remote device revocation is an idempotent account command. It keeps all
-- already synchronized account data while preventing later device commands.
create or replace function public.revoke_account_device(
  p_command_id uuid,
  p_requesting_device_id uuid,
  p_device_sequence bigint,
  p_target_device_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_result jsonb;
  target_exists boolean;
  target_revoked_at timestamptz;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_target_device_id = p_requesting_device_id then
    raise exception 'use_local_sign_out' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.account_devices
    where user_id = owner_id
      and id = p_requesting_device_id
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

  select true, revoked_at
  into target_exists, target_revoked_at
  from public.account_devices
  where user_id = owner_id
    and id = p_target_device_id
    and deleted_at is null
  for update;

  if not coalesce(target_exists, false) then
    raise exception 'device_not_found' using errcode = 'P0002';
  end if;

  if target_revoked_at is null then
    update public.account_devices
    set revoked_at = statement_timestamp(),
        updated_by_device_id = p_requesting_device_id,
        last_command_id = p_command_id
    where user_id = owner_id and id = p_target_device_id;
  end if;

  result_payload := jsonb_build_object(
    'status', 'accepted',
    'entity_type', 'account_devices',
    'entity_id', p_target_device_id,
    'revoked', true
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
    p_requesting_device_id,
    p_device_sequence,
    'account_devices',
    p_target_device_id,
    'revoke',
    0,
    'accepted'::public.sync_command_status,
    result_payload,
    p_requesting_device_id,
    p_requesting_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

revoke all on function public.revoke_account_device(uuid, uuid, bigint, uuid)
  from public, anon;
grant execute on function public.revoke_account_device(uuid, uuid, bigint, uuid)
  to authenticated;

comment on function public.revoke_account_device(uuid, uuid, bigint, uuid) is
  'Revokes a different active account device using an idempotent user command.';
