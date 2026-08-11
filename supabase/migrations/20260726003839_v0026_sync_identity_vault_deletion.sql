-- TaskMaster Pro v0.0.26
-- Account-scoped device recovery, merge-safe settings, encrypted-vault
-- commands, and recoverable account deletion.

create or replace function public.apply_user_settings_merge_command(
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

  update public.user_settings
  set
    preferred_language = coalesce(
      p_payload ->> 'preferred_language',
      preferred_language
    ),
    time_zone = coalesce(p_payload ->> 'time_zone', time_zone),
    clock_format = coalesce(p_payload ->> 'clock_format', clock_format),
    theme = coalesce((p_payload ->> 'theme')::public.app_theme, theme),
    accent_color = coalesce(
      (p_payload ->> 'accent_color')::bigint,
      accent_color
    ),
    notification_sound = coalesce(
      p_payload ->> 'notification_sound',
      notification_sound
    ),
    workday_settings = case
      when p_payload ? 'workday_settings'
        then coalesce(workday_settings, '{}'::jsonb) ||
             coalesce(p_payload -> 'workday_settings', '{}'::jsonb)
      else workday_settings
    end,
    sleep_preferences = case
      when p_payload ? 'sleep_preferences'
        then coalesce(sleep_preferences, '{}'::jsonb) ||
             coalesce(p_payload -> 'sleep_preferences', '{}'::jsonb)
      else sleep_preferences
    end,
    notification_preferences = case
      when p_payload ? 'notification_preferences'
        then coalesce(notification_preferences, '{}'::jsonb) ||
             coalesce(p_payload -> 'notification_preferences', '{}'::jsonb)
      else notification_preferences
    end,
    data = case
      when p_payload ? 'data'
        then coalesce(data, '{}'::jsonb) ||
             coalesce(p_payload -> 'data', '{}'::jsonb)
      else data
    end,
    updated_by_device_id = p_device_id,
    last_command_id = p_command_id
  where id = settings_id and user_id = owner_id;

  result_payload := jsonb_build_object(
    'status', 'accepted',
    'entity_type', 'user_settings',
    'entity_id', settings_id,
    'revision', current_revision + 1,
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
    'user_settings',
    settings_id,
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

revoke all on function public.apply_user_settings_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) from public, anon;
grant execute on function public.apply_user_settings_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) to authenticated;

-- The v0.0.25 task procedure correctly handled idempotency but its update
-- branch omitted task-template, roadmap, phase, parent and actual-time fields.
-- This wrapper applies those fields once after an accepted command and returns
-- the actual authoritative revision.
create or replace function public.apply_task_occurrence_v0026_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_entity_id uuid,
  p_base_revision bigint,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  result_payload jsonb;
  actual_revision bigint;
begin
  result_payload := public.apply_task_occurrence_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_entity_id,
    p_base_revision,
    p_operation,
    p_payload
  );

  if result_payload ->> 'status' = 'accepted'
     and p_operation <> 'delete' then
    update public.task_occurrences
    set
      template_id = case
        when p_payload ? 'template_id'
          then nullif(p_payload ->> 'template_id', '')::uuid
        else template_id
      end,
      roadmap_id = case
        when p_payload ? 'roadmap_id'
          then nullif(p_payload ->> 'roadmap_id', '')::uuid
        else roadmap_id
      end,
      roadmap_phase_id = case
        when p_payload ? 'roadmap_phase_id'
          then nullif(p_payload ->> 'roadmap_phase_id', '')::uuid
        else roadmap_phase_id
      end,
      parent_task_id = case
        when p_payload ? 'parent_task_id'
          then nullif(p_payload ->> 'parent_task_id', '')::uuid
        else parent_task_id
      end,
      occurrence_key = case
        when p_payload ? 'occurrence_key'
          then nullif(p_payload ->> 'occurrence_key', '')
        else occurrence_key
      end,
      actual_start = case
        when p_payload ? 'actual_start'
          then nullif(p_payload ->> 'actual_start', '')::timestamptz
        else actual_start
      end,
      actual_finish = case
        when p_payload ? 'actual_finish'
          then nullif(p_payload ->> 'actual_finish', '')::timestamptz
        else actual_finish
      end,
      active_duration_ms = coalesce(
        (p_payload ->> 'active_duration_ms')::bigint,
        active_duration_ms
      ),
      paused_duration_ms = coalesce(
        (p_payload ->> 'paused_duration_ms')::bigint,
        paused_duration_ms
      ),
      idle_duration_ms = coalesce(
        (p_payload ->> 'idle_duration_ms')::bigint,
        idle_duration_ms
      ),
      updated_by_device_id = p_device_id,
      last_command_id = p_command_id
    where user_id = owner_id
      and id = p_entity_id
      and (
        (p_payload ? 'template_id' and template_id is distinct from
          nullif(p_payload ->> 'template_id', '')::uuid)
        or (p_payload ? 'roadmap_id' and roadmap_id is distinct from
          nullif(p_payload ->> 'roadmap_id', '')::uuid)
        or (p_payload ? 'roadmap_phase_id' and roadmap_phase_id is distinct from
          nullif(p_payload ->> 'roadmap_phase_id', '')::uuid)
        or (p_payload ? 'parent_task_id' and parent_task_id is distinct from
          nullif(p_payload ->> 'parent_task_id', '')::uuid)
        or (p_payload ? 'occurrence_key' and occurrence_key is distinct from
          nullif(p_payload ->> 'occurrence_key', ''))
        or (p_payload ? 'actual_start' and actual_start is distinct from
          nullif(p_payload ->> 'actual_start', '')::timestamptz)
        or (p_payload ? 'actual_finish' and actual_finish is distinct from
          nullif(p_payload ->> 'actual_finish', '')::timestamptz)
        or (p_payload ? 'active_duration_ms' and active_duration_ms is distinct from
          (p_payload ->> 'active_duration_ms')::bigint)
        or (p_payload ? 'paused_duration_ms' and paused_duration_ms is distinct from
          (p_payload ->> 'paused_duration_ms')::bigint)
        or (p_payload ? 'idle_duration_ms' and idle_duration_ms is distinct from
          (p_payload ->> 'idle_duration_ms')::bigint)
      );

    select revision into actual_revision
    from public.task_occurrences
    where user_id = owner_id and id = p_entity_id;
    result_payload := result_payload ||
      jsonb_build_object('revision', actual_revision);
  end if;

  return result_payload;
end;
$$;

revoke all on function public.apply_task_occurrence_v0026_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_task_occurrence_v0026_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated;

create or replace function public.apply_vault_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_entity_type text,
  p_entity_id uuid,
  p_base_revision bigint,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  current_revision bigint;
  existing_result jsonb;
  result_payload jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_entity_type not in ('user_vaults', 'vault_items', 'vault_device_keys') then
    raise exception 'unsupported_vault_entity';
  end if;
  if p_operation not in ('create', 'update', 'delete') then
    raise exception 'unsupported_operation';
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

  select result into existing_result
  from public.processed_commands
  where user_id = owner_id and command_id = p_command_id;
  if found then
    return existing_result;
  end if;

  if p_entity_type = 'user_vaults' then
    select revision into current_revision
    from public.user_vaults
    where user_id = owner_id and id = p_entity_id
    for update;
  elsif p_entity_type = 'vault_items' then
    select revision into current_revision
    from public.vault_items
    where user_id = owner_id and id = p_entity_id
    for update;
  else
    select revision into current_revision
    from public.vault_device_keys
    where user_id = owner_id and id = p_entity_id
    for update;
  end if;

  if p_operation = 'create' and current_revision is null and p_base_revision = 0 then
    if p_entity_type = 'user_vaults' then
      insert into public.user_vaults (
        id, user_id, kdf_name, kdf_parameters, encrypted_verifier,
        vault_version, locked_at, created_by_device_id, updated_by_device_id,
        last_command_id
      ) values (
        p_entity_id, owner_id,
        coalesce(p_payload ->> 'kdf_name', 'argon2id'),
        coalesce(p_payload -> 'kdf_parameters', '{}'::jsonb),
        p_payload ->> 'encrypted_verifier',
        coalesce((p_payload ->> 'vault_version')::integer, 1),
        nullif(p_payload ->> 'locked_at', '')::timestamptz,
        p_device_id, p_device_id, p_command_id
      );
    elsif p_entity_type = 'vault_items' then
      insert into public.vault_items (
        id, user_id, vault_id, ciphertext, nonce, encrypted_metadata,
        item_revision, conflicting_copy_of, created_by_device_id,
        updated_by_device_id, last_command_id
      ) values (
        p_entity_id, owner_id,
        (p_payload ->> 'vault_id')::uuid,
        p_payload ->> 'ciphertext',
        p_payload ->> 'nonce',
        p_payload ->> 'encrypted_metadata',
        coalesce((p_payload ->> 'item_revision')::bigint, 1),
        nullif(p_payload ->> 'conflicting_copy_of', '')::uuid,
        p_device_id, p_device_id, p_command_id
      );
    else
      insert into public.vault_device_keys (
        id, user_id, vault_id, device_id, wrapped_key, wrapping_algorithm,
        authorized_at, revoked_at, created_by_device_id, updated_by_device_id,
        last_command_id
      ) values (
        p_entity_id, owner_id,
        (p_payload ->> 'vault_id')::uuid,
        (p_payload ->> 'device_id')::uuid,
        p_payload ->> 'wrapped_key',
        p_payload ->> 'wrapping_algorithm',
        coalesce(
          nullif(p_payload ->> 'authorized_at', '')::timestamptz,
          statement_timestamp()
        ),
        nullif(p_payload ->> 'revoked_at', '')::timestamptz,
        p_device_id, p_device_id, p_command_id
      );
    end if;
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'revision', 1
    );
  elsif current_revision is null then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'missing_entity',
      'server_revision', null
    );
  elsif current_revision <> p_base_revision then
    insert into public.sync_conflicts (
      user_id, command_id, entity_type, entity_id, conflict_type,
      base_revision, server_revision, local_payload, server_payload,
      created_by_device_id, updated_by_device_id, last_command_id
    ) values (
      owner_id, p_command_id, p_entity_type, p_entity_id,
      'vault_conflicting_copy', p_base_revision, current_revision,
      coalesce(p_payload, '{}'::jsonb),
      jsonb_build_object('revision', current_revision),
      p_device_id, p_device_id, p_command_id
    )
    on conflict (user_id, command_id, entity_id) do nothing;
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'vault_conflicting_copy',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'server_revision', current_revision
    );
  elsif p_operation = 'delete' then
    if p_entity_type = 'user_vaults' then
      update public.user_vaults
      set deleted_at = statement_timestamp(),
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where user_id = owner_id and id = p_entity_id;
    elsif p_entity_type = 'vault_items' then
      update public.vault_items
      set deleted_at = statement_timestamp(),
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where user_id = owner_id and id = p_entity_id;
    else
      update public.vault_device_keys
      set deleted_at = statement_timestamp(),
          revoked_at = statement_timestamp(),
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id
      where user_id = owner_id and id = p_entity_id;
    end if;
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'revision', current_revision + 1,
      'deleted', true
    );
  else
    if p_entity_type = 'user_vaults' then
      update public.user_vaults
      set kdf_name = coalesce(p_payload ->> 'kdf_name', kdf_name),
          kdf_parameters = coalesce(p_payload -> 'kdf_parameters', kdf_parameters),
          encrypted_verifier = coalesce(
            p_payload ->> 'encrypted_verifier',
            encrypted_verifier
          ),
          vault_version = coalesce(
            (p_payload ->> 'vault_version')::integer,
            vault_version
          ),
          locked_at = case
            when p_payload ? 'locked_at'
              then nullif(p_payload ->> 'locked_at', '')::timestamptz
            else locked_at
          end,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id,
          deleted_at = null
      where user_id = owner_id and id = p_entity_id;
    elsif p_entity_type = 'vault_items' then
      update public.vault_items
      set ciphertext = coalesce(p_payload ->> 'ciphertext', ciphertext),
          nonce = coalesce(p_payload ->> 'nonce', nonce),
          encrypted_metadata = coalesce(
            p_payload ->> 'encrypted_metadata',
            encrypted_metadata
          ),
          item_revision = coalesce(
            (p_payload ->> 'item_revision')::bigint,
            item_revision
          ),
          conflicting_copy_of = case
            when p_payload ? 'conflicting_copy_of'
              then nullif(p_payload ->> 'conflicting_copy_of', '')::uuid
            else conflicting_copy_of
          end,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id,
          deleted_at = null
      where user_id = owner_id and id = p_entity_id;
    else
      update public.vault_device_keys
      set wrapped_key = coalesce(p_payload ->> 'wrapped_key', wrapped_key),
          wrapping_algorithm = coalesce(
            p_payload ->> 'wrapping_algorithm',
            wrapping_algorithm
          ),
          revoked_at = case
            when p_payload ? 'revoked_at'
              then nullif(p_payload ->> 'revoked_at', '')::timestamptz
            else revoked_at
          end,
          updated_by_device_id = p_device_id,
          last_command_id = p_command_id,
          deleted_at = null
      where user_id = owner_id and id = p_entity_id;
    end if;
    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'revision', current_revision + 1
    );
  end if;

  insert into public.processed_commands (
    user_id, command_id, device_id, device_sequence, entity_type, entity_id,
    command_type, base_revision, status, result, created_by_device_id,
    updated_by_device_id, last_command_id
  ) values (
    owner_id, p_command_id, p_device_id, p_device_sequence, p_entity_type,
    p_entity_id, p_operation, p_base_revision,
    case when result_payload ->> 'status' = 'accepted'
      then 'accepted'::public.sync_command_status
      else 'conflict'::public.sync_command_status
    end,
    result_payload, p_device_id, p_device_id, p_command_id
  );
  return result_payload;
end;
$$;

revoke all on function public.apply_vault_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_vault_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) to authenticated;

create trigger log_user_vaults
  after insert or update on public.user_vaults
  for each row execute function private.log_synchronized_change();
create trigger log_vault_items
  after insert or update on public.vault_items
  for each row execute function private.log_synchronized_change();
create trigger log_vault_device_keys
  after insert or update on public.vault_device_keys
  for each row execute function private.log_synchronized_change();

create table if not exists public.account_deletion_requests (
  id uuid primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  requested_at timestamptz not null,
  scheduled_for timestamptz not null,
  cancelled_at timestamptz,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'cancelled')),
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz
);

alter table public.account_deletion_requests enable row level security;

create policy account_deletion_requests_select_own
  on public.account_deletion_requests for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy account_deletion_requests_insert_own
  on public.account_deletion_requests for insert
  to authenticated
  with check ((select auth.uid()) = user_id);
create policy account_deletion_requests_update_own
  on public.account_deletion_requests for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function private.enforce_account_deletion_request()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.id := (select auth.uid());
    new.user_id := (select auth.uid());
    new.requested_at := statement_timestamp();
    new.scheduled_for := statement_timestamp() + interval '30 days';
    new.status := 'scheduled';
    new.cancelled_at := null;
  else
    new.id := old.id;
    new.user_id := old.user_id;
    if new.status = 'scheduled' and old.status <> 'scheduled' then
      new.requested_at := statement_timestamp();
      new.scheduled_for := statement_timestamp() + interval '30 days';
      new.cancelled_at := null;
    elsif new.status = 'cancelled' and old.status = 'scheduled' then
      new.cancelled_at := statement_timestamp();
      new.scheduled_for := old.scheduled_for;
    else
      new.requested_at := old.requested_at;
      new.scheduled_for := old.scheduled_for;
      new.cancelled_at := old.cancelled_at;
    end if;
  end if;
  return new;
end;
$$;

revoke insert, update, delete on public.account_deletion_requests from anon;
revoke delete on public.account_deletion_requests from authenticated;
grant select, insert, update on public.account_deletion_requests
  to authenticated;

create trigger enforce_account_deletion_request
  before insert or update on public.account_deletion_requests
  for each row execute function private.enforce_account_deletion_request();

create trigger prepare_account_deletion_requests
  before insert or update on public.account_deletion_requests
  for each row execute function private.prepare_synchronized_record();

create trigger log_account_deletion_requests
  after insert or update on public.account_deletion_requests
  for each row execute function private.log_synchronized_change();

create or replace function public.schedule_account_deletion(
  p_device_id uuid,
  p_confirmation text
)
returns public.account_deletion_requests
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  result public.account_deletion_requests;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if upper(trim(p_confirmation)) <> 'DELETE' then
    raise exception 'confirmation_required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.account_devices
    where id = p_device_id and user_id = owner_id
      and revoked_at is null and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  insert into public.account_deletion_requests (
    id, user_id, requested_at, scheduled_for, status,
    created_by_device_id, updated_by_device_id, last_command_id,
    cancelled_at, deleted_at
  ) values (
    owner_id, owner_id, statement_timestamp(),
    statement_timestamp() + interval '30 days', 'scheduled',
    p_device_id, p_device_id, gen_random_uuid(), null, null
  )
  on conflict (user_id) do update
  set requested_at = excluded.requested_at,
      scheduled_for = excluded.scheduled_for,
      status = 'scheduled',
      cancelled_at = null,
      deleted_at = null,
      updated_by_device_id = p_device_id,
      last_command_id = gen_random_uuid()
  returning * into result;

  return result;
end;
$$;

create or replace function public.cancel_account_deletion(
  p_device_id uuid
)
returns public.account_deletion_requests
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  result public.account_deletion_requests;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.account_devices
    where id = p_device_id and user_id = owner_id
      and revoked_at is null and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;

  update public.account_deletion_requests
  set status = 'cancelled',
      cancelled_at = statement_timestamp(),
      updated_by_device_id = p_device_id,
      last_command_id = gen_random_uuid()
  where user_id = owner_id and status = 'scheduled'
  returning * into result;

  if result.id is null then
    raise exception 'no_scheduled_deletion' using errcode = 'P0002';
  end if;
  return result;
end;
$$;

revoke all on function public.schedule_account_deletion(uuid, text)
  from public, anon;
grant execute on function public.schedule_account_deletion(uuid, text)
  to authenticated;
revoke all on function public.cancel_account_deletion(uuid)
  from public, anon;
grant execute on function public.cancel_account_deletion(uuid)
  to authenticated;

create extension if not exists pg_cron with schema extensions;

create or replace function private.purge_due_taskmaster_accounts()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  due_user record;
begin
  for due_user in
    select user_id
    from public.account_deletion_requests
    where status = 'scheduled'
      and scheduled_for <= statement_timestamp()
    for update skip locked
  loop
    delete from storage.objects
    where split_part(name, '/', 1) = due_user.user_id::text;
    delete from auth.users where id = due_user.user_id;
  end loop;
end;
$$;

revoke all on function private.purge_due_taskmaster_accounts()
  from public, anon, authenticated;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'taskmaster-pro-account-purge';
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
  perform cron.schedule(
    'taskmaster-pro-account-purge',
    '15 * * * *',
    'select private.purge_due_taskmaster_accounts();'
  );
end;
$$;
