-- TaskMaster Pro v0.0.26 command-integrity hardening.
--
-- Authenticated clients retain owner-scoped reads, but every public-table
-- mutation must originate inside an explicitly allowlisted SECURITY DEFINER
-- command RPC that derives its owner from auth.uid(). Authenticated and anon
-- roles receive no direct public-table mutation privileges.

alter table public.account_devices
  add column if not exists auth_session_id uuid;

comment on column public.account_devices.auth_session_id is
  'Supabase Auth session bound by the server from the signed JWT session_id claim. Never accepted from a client payload.';

create unique index if not exists account_devices_active_auth_session_uidx
  on public.account_devices (user_id, auth_session_id)
  where auth_session_id is not null
    and revoked_at is null
    and deleted_at is null;

-- Registration and revocation both update account_devices. This trigger is
-- SECURITY DEFINER only because authenticated clients cannot inspect
-- auth.sessions. It performs explicit caller, owner, session, and device
-- checks before touching the row.
create or replace function private.enforce_account_device_session_binding()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_session_id uuid;
  old_session_is_active boolean := false;
begin
  if caller_id is null then
    -- Supabase migrations and service maintenance have no end-user JWT.
    -- Authenticated API roles cannot reach this trigger directly because
    -- table mutation privileges are revoked below.
    return new;
  end if;

  if new.user_id is distinct from caller_id then
    raise exception 'account_device_owner_mismatch' using errcode = '42501';
  end if;

  begin
    caller_session_id :=
      nullif((select auth.jwt()) ->> 'session_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'auth_session_missing' using errcode = '42501';
  end;

  if caller_session_id is null then
    raise exception 'auth_session_missing' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from auth.sessions session_row
    where session_row.id = caller_session_id
      and session_row.user_id = caller_id
      and (
        session_row.not_after is null
        or session_row.not_after > statement_timestamp()
      )
  ) then
    raise exception 'auth_session_inactive' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    if new.id is null then
      raise exception 'device_id_required' using errcode = '22023';
    end if;

    if exists (
      select 1
      from public.account_devices existing_device
      where existing_device.user_id = caller_id
        and existing_device.auth_session_id = caller_session_id
        and existing_device.id <> new.id
        and existing_device.revoked_at is null
        and existing_device.deleted_at is null
    ) then
      raise exception 'auth_session_already_registered'
        using errcode = '42501';
    end if;

    new.auth_session_id := caller_session_id;
    new.revoked_at := null;
    new.deleted_at := null;
    new.created_by_device_id := new.id;
    new.updated_by_device_id := new.id;
    return new;
  end if;

  if new.id is distinct from old.id
      or new.user_id is distinct from old.user_id then
    raise exception 'account_device_identity_immutable'
      using errcode = '42501';
  end if;

  if old.revoked_at is not null or old.deleted_at is not null then
    raise exception 'device_revoked' using errcode = '42501';
  end if;

  -- A revocation preserves the target session binding. The caller must be a
  -- different, active device bound to the current JWT session.
  if old.revoked_at is null and new.revoked_at is not null then
    if new.updated_by_device_id is null
        or not exists (
          select 1
          from public.account_devices requesting_device
          where requesting_device.user_id = caller_id
            and requesting_device.id = new.updated_by_device_id
            and requesting_device.auth_session_id = caller_session_id
            and requesting_device.revoked_at is null
            and requesting_device.deleted_at is null
        ) then
      raise exception 'requesting_device_session_mismatch'
        using errcode = '42501';
    end if;

    if new.updated_by_device_id = new.id then
      raise exception 'use_local_sign_out' using errcode = '22023';
    end if;

    new.auth_session_id := old.auth_session_id;
    new.deleted_at := old.deleted_at;
    return new;
  end if;

  -- Normal registration refreshes metadata and last_seen_at. A valid new
  -- login may rebind the installation only after its previous Auth session
  -- has actually disappeared or expired.
  if old.auth_session_id is not null
      and old.auth_session_id <> caller_session_id then
    select exists (
      select 1
      from auth.sessions old_session
      where old_session.id = old.auth_session_id
        and old_session.user_id = caller_id
        and (
          old_session.not_after is null
          or old_session.not_after > statement_timestamp()
        )
    )
    into old_session_is_active;

    if old_session_is_active then
      raise exception 'device_session_already_bound'
        using errcode = '42501';
    end if;
  end if;

  if exists (
    select 1
    from public.account_devices existing_device
    where existing_device.user_id = caller_id
      and existing_device.auth_session_id = caller_session_id
      and existing_device.id <> new.id
      and existing_device.revoked_at is null
      and existing_device.deleted_at is null
  ) then
    raise exception 'auth_session_already_registered'
      using errcode = '42501';
  end if;

  new.auth_session_id := caller_session_id;
  new.revoked_at := null;
  new.deleted_at := null;
  new.updated_by_device_id := new.id;
  return new;
end;
$$;

revoke all on function private.enforce_account_device_session_binding()
  from public, anon, authenticated;

drop trigger if exists enforce_account_device_session_binding
  on public.account_devices;
create trigger enforce_account_device_session_binding
before insert or update on public.account_devices
for each row execute function private.enforce_account_device_session_binding();

-- Deleting the bound auth.sessions row terminates refresh-token use. The
-- already-issued access token remains harmless for commands because the
-- processed_commands trigger below verifies that the session row still
-- exists. This is a trigger rather than a directly callable helper so its
-- EXECUTE privilege can remain revoked from every API role.
create or replace function private.terminate_revoked_account_device_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_session_id uuid;
begin
  if old.revoked_at is not null or new.revoked_at is null then
    return new;
  end if;

  if caller_id is null then
    return new;
  end if;

  if caller_id is null or caller_id <> new.user_id then
    raise exception 'account_device_owner_mismatch' using errcode = '42501';
  end if;

  begin
    caller_session_id :=
      nullif((select auth.jwt()) ->> 'session_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'auth_session_missing' using errcode = '42501';
  end;

  if caller_session_id is null then
    raise exception 'auth_session_missing' using errcode = '42501';
  end if;

  if new.auth_session_id = caller_session_id then
    raise exception 'use_local_sign_out' using errcode = '22023';
  end if;

  if new.auth_session_id is not null then
    delete from auth.sessions target_session
    where target_session.id = new.auth_session_id
      and target_session.user_id = new.user_id;
  end if;

  return new;
end;
$$;

revoke all on function private.terminate_revoked_account_device_session()
  from public, anon, authenticated;

drop trigger if exists terminate_revoked_account_device_session
  on public.account_devices;
create trigger terminate_revoked_account_device_session
after update of revoked_at on public.account_devices
for each row execute function private.terminate_revoked_account_device_session();

-- Every durable command must prove that the submitted device ID belongs to
-- the current JWT session and that Supabase still considers the session
-- active. Because this is BEFORE INSERT, any failure rolls back all
-- earlier mutations performed by the enclosing RPC transaction.
create or replace function private.verify_processed_command_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_session_id uuid;
begin
  if caller_id is null then
    return new;
  end if;

  if caller_id is null or new.user_id is distinct from caller_id then
    raise exception 'command_owner_mismatch' using errcode = '42501';
  end if;

  begin
    caller_session_id :=
      nullif((select auth.jwt()) ->> 'session_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'auth_session_missing' using errcode = '42501';
  end;

  if caller_session_id is null then
    raise exception 'auth_session_missing' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from auth.sessions session_row
    where session_row.id = caller_session_id
      and session_row.user_id = caller_id
      and (
        session_row.not_after is null
        or session_row.not_after > statement_timestamp()
      )
  ) then
    raise exception 'auth_session_inactive' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.account_devices command_device
    where command_device.user_id = caller_id
      and command_device.id = new.device_id
      and command_device.auth_session_id = caller_session_id
      and command_device.revoked_at is null
      and command_device.deleted_at is null
  ) then
    raise exception 'command_device_session_mismatch'
      using errcode = '42501';
  end if;

  if new.created_by_device_id is not null
      and new.created_by_device_id <> new.device_id then
    raise exception 'command_created_by_device_mismatch'
      using errcode = '42501';
  end if;

  if new.updated_by_device_id is not null
      and new.updated_by_device_id <> new.device_id then
    raise exception 'command_updated_by_device_mismatch'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function private.verify_processed_command_session()
  from public, anon, authenticated;

drop trigger if exists verify_processed_command_session
  on public.processed_commands;
create trigger verify_processed_command_session
before insert on public.processed_commands
for each row execute function private.verify_processed_command_session();

-- Account deletion commands predate processed_commands. Give them the same
-- session/device guarantee with a narrowly scoped trigger.
create or replace function private.verify_account_deletion_command_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_session_id uuid;
  submitted_device_id uuid :=
    coalesce(new.updated_by_device_id, new.created_by_device_id);
begin
  if caller_id is null then
    return new;
  end if;

  if caller_id is null or new.user_id is distinct from caller_id then
    raise exception 'account_deletion_owner_mismatch'
      using errcode = '42501';
  end if;

  begin
    caller_session_id :=
      nullif((select auth.jwt()) ->> 'session_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'auth_session_missing' using errcode = '42501';
  end;

  if caller_session_id is null then
    raise exception 'auth_session_missing' using errcode = '42501';
  end if;

  if submitted_device_id is null
      or not exists (
        select 1
        from public.account_devices command_device
        join auth.sessions session_row
          on session_row.id = command_device.auth_session_id
         and session_row.user_id = command_device.user_id
        where command_device.user_id = caller_id
          and command_device.id = submitted_device_id
          and command_device.auth_session_id = caller_session_id
          and command_device.revoked_at is null
          and command_device.deleted_at is null
          and (
            session_row.not_after is null
            or session_row.not_after > statement_timestamp()
          )
      ) then
    raise exception 'command_device_session_mismatch'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function private.verify_account_deletion_command_session()
  from public, anon, authenticated;

drop trigger if exists verify_account_deletion_command_session
  on public.account_deletion_requests;
create trigger verify_account_deletion_command_session
before insert or update on public.account_deletion_requests
for each row execute function private.verify_account_deletion_command_session();

-- apply_task_occurrence_v0026_command performs compatibility updates after
-- its nested base command returns. On an idempotent replay the nested command
-- may return an existing result without inserting processed_commands again,
-- so task rows need an immediate session guard as well.
create or replace function private.verify_task_occurrence_command_session()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  caller_session_id uuid;
  submitted_device_id uuid :=
    coalesce(new.updated_by_device_id, new.created_by_device_id);
begin
  -- Server-side maintenance with no user JWT remains possible for privileged
  -- roles. Authenticated roles have read-only table grants and must use a
  -- session-verifying command RPC.
  if caller_id is null then
    return new;
  end if;

  if new.user_id is distinct from caller_id then
    raise exception 'task_owner_mismatch' using errcode = '42501';
  end if;

  begin
    caller_session_id :=
      nullif((select auth.jwt()) ->> 'session_id', '')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'auth_session_missing' using errcode = '42501';
  end;

  if caller_session_id is null then
    raise exception 'auth_session_missing' using errcode = '42501';
  end if;

  if submitted_device_id is null
      or not exists (
        select 1
        from public.account_devices command_device
        join auth.sessions session_row
          on session_row.id = command_device.auth_session_id
         and session_row.user_id = command_device.user_id
        where command_device.user_id = caller_id
          and command_device.id = submitted_device_id
          and command_device.auth_session_id = caller_session_id
          and command_device.revoked_at is null
          and command_device.deleted_at is null
          and (
            session_row.not_after is null
            or session_row.not_after > statement_timestamp()
          )
      ) then
    raise exception 'command_device_session_mismatch'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function private.verify_task_occurrence_command_session()
  from public, anon, authenticated;

drop trigger if exists verify_task_occurrence_command_session
  on public.task_occurrences;
create trigger verify_task_occurrence_command_session
before insert or update on public.task_occurrences
for each row execute function private.verify_task_occurrence_command_session();

-- Device registration is the sole client entry point allowed to create or
-- refresh an account_devices row. auth_session_id is never a parameter.
create or replace function public.register_account_device(
  p_device_id uuid,
  p_device_name text,
  p_platform text,
  p_app_version text default null,
  p_device_public_key text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  existing_device public.account_devices%rowtype;
  registered_device public.account_devices%rowtype;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_device_id is null then
    raise exception 'device_id_required' using errcode = '22023';
  end if;

  if nullif(trim(p_device_name), '') is null then
    raise exception 'device_name_required' using errcode = '22023';
  end if;

  if p_platform not in ('windows', 'android', 'unknown') then
    raise exception 'unsupported_device_platform' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(owner_id::text || ':device:' || p_device_id::text, 0)
  );

  select *
  into existing_device
  from public.account_devices
  where user_id = owner_id
    and id = p_device_id
  for update;

  if found and (
    existing_device.revoked_at is not null
    or existing_device.deleted_at is not null
  ) then
    raise exception 'device_revoked' using errcode = '42501';
  end if;

  if existing_device.id is null then
    insert into public.account_devices (
      id,
      user_id,
      device_name,
      platform,
      app_version,
      device_public_key,
      last_seen_at,
      created_by_device_id,
      updated_by_device_id
    )
    values (
      p_device_id,
      owner_id,
      trim(p_device_name),
      p_platform,
      nullif(trim(p_app_version), ''),
      nullif(p_device_public_key, ''),
      statement_timestamp(),
      p_device_id,
      p_device_id
    )
    returning * into registered_device;
  else
    update public.account_devices
    set device_name = trim(p_device_name),
        platform = p_platform,
        app_version = nullif(trim(p_app_version), ''),
        device_public_key = coalesce(
          nullif(p_device_public_key, ''),
          device_public_key
        ),
        last_seen_at = statement_timestamp(),
        updated_by_device_id = p_device_id
    where user_id = owner_id
      and id = p_device_id
    returning * into registered_device;
  end if;

  return jsonb_build_object(
    'status', 'accepted',
    'device_id', registered_device.id,
    'revision', registered_device.revision,
    'revoked', false
  );
end;
$$;

revoke all on function public.register_account_device(
  uuid, text, text, text, text
) from public, anon;
grant execute on function public.register_account_device(
  uuid, text, text, text, text
) to authenticated;

comment on function public.register_account_device(
  uuid, text, text, text, text
) is
  'Registers the current installation against the active JWT session without accepting a client-provided session ID or reviving revoked devices.';

-- Retain the existing idempotent revocation contract while ensuring the
-- target account_devices update invokes the Auth-session termination trigger.
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
  target_auth_session_id uuid;
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

  select true, revoked_at, auth_session_id
  into target_exists, target_revoked_at, target_auth_session_id
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
    'revoked', true,
    'auth_session_bound', target_auth_session_id is not null
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

revoke all on function public.revoke_account_device(
  uuid, uuid, bigint, uuid
) from public, anon;
grant execute on function public.revoke_account_device(
  uuid, uuid, bigint, uuid
) to authenticated;

comment on function public.revoke_account_device(
  uuid, uuid, bigint, uuid
) is
  'Revokes another device, invalidates its bound Auth session, and records an idempotent session-verified command.';

-- Public tables are read-only to authenticated clients. These narrowly
-- allowlisted command endpoints run with their owner role only after deriving
-- ownership from auth.uid(), validating the registered device, and recording
-- an idempotent command. This avoids unsupported custom GUCs on managed
-- Supabase Postgres while keeping direct client DML closed.
alter function public.apply_task_occurrence_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) security definer;

alter function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) security definer;

alter function public.apply_user_settings_command(
  uuid, uuid, bigint, bigint, jsonb
) security definer;

alter function public.apply_user_settings_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) security definer;

alter function public.apply_task_occurrence_v0026_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) security definer;

alter function public.apply_vault_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) security definer;

alter function public.schedule_account_deletion(
  uuid, text
) security definer;

alter function public.cancel_account_deletion(
  uuid
) security definer;

alter function public.apply_roadmap_task_link_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) security definer;

alter function public.apply_activity_contribution_batch(
  jsonb
) security definer;

alter function public.apply_profile_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) security definer;

alter function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) security definer;

alter function public.apply_execution_switch_v0026_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode
) security definer;

alter function public.revoke_account_device(
  uuid, uuid, bigint, uuid
) security definer;

alter function public.register_account_device(
  uuid, text, text, text, text
) security definer;

revoke execute on function
  taskmaster_internal.apply_execution_transition_v0026_command_legacy(
    uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
  )
from public, anon, authenticated, service_role;

-- Replace every existing policy on public user-owned tables. This is
-- intentionally authoritative: PostgreSQL permissive policies combine with
-- OR, so leaving even one broad legacy policy would defeat the command guard.
do $$
declare
  owned_table record;
  existing_policy record;
begin
  for owned_table in
    select distinct table_row.oid, table_row.relname
    from pg_catalog.pg_class table_row
    join pg_catalog.pg_namespace table_schema
      on table_schema.oid = table_row.relnamespace
    join pg_catalog.pg_attribute owner_column
      on owner_column.attrelid = table_row.oid
     and owner_column.attname = 'user_id'
     and owner_column.attnum > 0
     and not owner_column.attisdropped
    where table_schema.nspname = 'public'
      and table_row.relkind in ('r', 'p')
  loop
    execute format(
      'alter table public.%I enable row level security',
      owned_table.relname
    );
    execute format(
      'alter table public.%I force row level security',
      owned_table.relname
    );

    for existing_policy in
      select policy_row.polname
      from pg_catalog.pg_policy policy_row
      where policy_row.polrelid = owned_table.oid
    loop
      execute format(
        'drop policy %I on public.%I',
        existing_policy.polname,
        owned_table.relname
      );
    end loop;

    execute format(
      'create policy %I on public.%I for select to authenticated
       using ((select auth.uid()) = user_id)',
      'owner_select_' || owned_table.relname,
      owned_table.relname
    );

  end loop;
end
$$;

-- Authenticated clients can read only their RLS-filtered rows. Every mutation
-- goes through one of the SECURITY DEFINER command functions above.
grant select on all tables in schema public to authenticated;
revoke insert, update, delete, truncate, references, trigger
  on all tables in schema public from authenticated;
revoke all on all tables in schema public from anon;

-- Migration-time assertions prevent a future edit from silently shipping a
-- partial policy or RPC allowlist.
do $$
declare
  owned_table record;
  policy_count integer;
  function_signature text;
  function_oid regprocedure;
  function_is_definer boolean;
  mutation_functions constant text[] := array[
    'public.apply_task_occurrence_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)',
    'public.apply_entity_command(uuid,uuid,bigint,text,uuid,bigint,text,jsonb)',
    'public.apply_user_settings_command(uuid,uuid,bigint,bigint,jsonb)',
    'public.apply_user_settings_merge_command(uuid,uuid,bigint,bigint,jsonb)',
    'public.apply_task_occurrence_v0026_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)',
    'public.apply_vault_command(uuid,uuid,bigint,text,uuid,bigint,text,jsonb)',
    'public.schedule_account_deletion(uuid,text)',
    'public.cancel_account_deletion(uuid)',
    'public.apply_roadmap_task_link_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)',
    'public.apply_activity_contribution_batch(jsonb)',
    'public.apply_profile_merge_command(uuid,uuid,bigint,bigint,jsonb)',
    'public.apply_execution_transition_v0026_command(uuid,uuid,bigint,uuid,uuid,text,public.execution_mode)',
    'public.apply_execution_switch_v0026_command(uuid,uuid,bigint,uuid,uuid,uuid,uuid,text,public.execution_mode)',
    'public.revoke_account_device(uuid,uuid,bigint,uuid)',
    'public.register_account_device(uuid,text,text,text,text)'
  ];
begin
  for owned_table in
    select distinct
      table_row.oid,
      table_row.relname,
      table_row.relrowsecurity,
      table_row.relforcerowsecurity
    from pg_catalog.pg_class table_row
    join pg_catalog.pg_namespace table_schema
      on table_schema.oid = table_row.relnamespace
    join pg_catalog.pg_attribute owner_column
      on owner_column.attrelid = table_row.oid
     and owner_column.attname = 'user_id'
     and owner_column.attnum > 0
     and not owner_column.attisdropped
    where table_schema.nspname = 'public'
      and table_row.relkind in ('r', 'p')
  loop
    if not owned_table.relrowsecurity
        or not owned_table.relforcerowsecurity then
      raise exception 'missing_forced_rls:%', owned_table.relname;
    end if;

    select count(*)
    into policy_count
    from pg_catalog.pg_policy policy_row
    where policy_row.polrelid = owned_table.oid;

    if policy_count <> 1 or not exists (
      select 1
      from pg_catalog.pg_policy policy_row
      where policy_row.polrelid = owned_table.oid
        and policy_row.polcmd = 'r'
    ) then
      raise exception 'unexpected_policy_count:%:%',
        owned_table.relname,
        policy_count;
    end if;

    if has_table_privilege(
      'authenticated',
      owned_table.oid,
      'INSERT'
    ) or has_table_privilege(
      'authenticated',
      owned_table.oid,
      'UPDATE'
    ) or has_table_privilege(
      'authenticated',
      owned_table.oid,
      'DELETE'
    ) then
      raise exception 'authenticated_table_mutation_privilege:%',
        owned_table.relname;
    end if;
  end loop;

  foreach function_signature in array mutation_functions
  loop
    function_oid := to_regprocedure(function_signature);
    if function_oid is null then
      raise exception 'missing_mutation_rpc:%', function_signature;
    end if;

    select procedure_row.prosecdef
    into function_is_definer
    from pg_catalog.pg_proc procedure_row
    where procedure_row.oid = function_oid;

    if not function_is_definer then
      raise exception 'public_mutation_rpc_must_be_security_definer:%',
        function_signature;
    end if;
  end loop;

  function_oid := to_regprocedure(
    'taskmaster_internal.apply_execution_transition_v0026_command_legacy(uuid,uuid,bigint,uuid,uuid,text,public.execution_mode)'
  );
  if function_oid is not null then
    select procedure_row.prosecdef
    into function_is_definer
    from pg_catalog.pg_proc procedure_row
    where procedure_row.oid = function_oid;

    if function_is_definer then
      raise exception 'legacy_execution_rpc_must_remain_security_invoker';
    end if;

    if has_function_privilege(
      'authenticated',
      function_oid,
      'EXECUTE'
    ) then
      raise exception 'legacy_execution_rpc_exposed_to_authenticated';
    end if;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.processed_commands'::regclass
      and trigger_row.tgname = 'verify_processed_command_session'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'missing_processed_command_session_trigger';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.task_occurrences'::regclass
      and trigger_row.tgname = 'verify_task_occurrence_command_session'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'missing_task_occurrence_session_trigger';
  end if;
end
$$;
