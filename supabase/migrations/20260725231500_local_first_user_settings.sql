-- Revision-checked local-first settings command. The client intentionally uses
-- the account id in its local outbox; this procedure resolves the canonical
-- settings row by auth.uid() so settings remain editable while offline without
-- exposing or guessing the server-generated settings id.

create or replace function public.apply_user_settings_command(
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
  settings_id uuid;
  current_revision bigint;
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
  into settings_id, current_revision
  from public.user_settings
  where user_id = owner_id and deleted_at is null
  for update;

  if settings_id is null then
    raise exception 'missing_user_settings';
  end if;

  if current_revision <> p_base_revision then
    insert into public.sync_conflicts (
      user_id,
      command_id,
      entity_type,
      entity_id,
      conflict_type,
      base_revision,
      server_revision,
      local_payload,
      server_payload,
      created_by_device_id,
      updated_by_device_id,
      last_command_id
    )
    values (
      owner_id,
      p_command_id,
      'user_settings',
      settings_id,
      'revision_mismatch',
      p_base_revision,
      current_revision,
      coalesce(p_payload, '{}'::jsonb),
      (
        select to_jsonb(settings_row)
        from public.user_settings settings_row
        where settings_row.id = settings_id
      ),
      p_device_id,
      p_device_id,
      p_command_id
    )
    on conflict (user_id, command_id, entity_id) do nothing;

    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'revision_mismatch',
      'entity_id', settings_id,
      'server_revision', current_revision
    );
  else
    update public.user_settings
    set
      preferred_language = coalesce(
        p_payload ->> 'preferred_language',
        preferred_language
      ),
      time_zone = coalesce(p_payload ->> 'time_zone', time_zone),
      clock_format = coalesce(p_payload ->> 'clock_format', clock_format),
      theme = coalesce(
        (p_payload ->> 'theme')::public.app_theme,
        theme
      ),
      accent_color = coalesce(
        (p_payload ->> 'accent_color')::bigint,
        accent_color
      ),
      notification_sound = coalesce(
        p_payload ->> 'notification_sound',
        notification_sound
      ),
      data = case
        when p_payload ? 'data'
          then coalesce(data, '{}'::jsonb) ||
               coalesce(p_payload -> 'data', '{}'::jsonb)
        else data
      end,
      revision = revision + 1,
      updated_at = now(),
      updated_by_device_id = p_device_id,
      last_command_id = p_command_id
    where id = settings_id and user_id = owner_id;

    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', 'user_settings',
      'entity_id', settings_id,
      'revision', current_revision + 1
    );
  end if;

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
    'user_settings',
    settings_id,
    'update',
    p_base_revision,
    case
      when result_payload ->> 'status' = 'accepted'
        then 'accepted'::public.sync_command_status
      else 'conflict'::public.sync_command_status
    end,
    result_payload,
    p_device_id,
    p_device_id,
    p_command_id
  );

  return result_payload;
end;
$$;

grant execute on function public.apply_user_settings_command(
  uuid,
  uuid,
  bigint,
  bigint,
  jsonb
) to authenticated;
