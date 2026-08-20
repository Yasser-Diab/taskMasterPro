-- Account-owned vacation policies. They are separate from recurrence rules so
-- one period can safely affect many templates without rewriting rule history.

create table if not exists public.vacation_periods (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  status text not null default 'active',
  start_date date not null,
  end_date date not null,
  recurrence text not null default 'none',
  interval_value integer not null default 1,
  task_policy text not null default 'postpone',
  task_scope text not null default 'allRecurring',
  selected_template_ids jsonb not null default '[]'::jsonb,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by_device_id uuid,
  updated_by_device_id uuid,
  last_command_id uuid,
  deleted_at timestamptz,
  data jsonb not null default '{}'::jsonb,
  constraint vacation_periods_date_order check (end_date >= start_date),
  constraint vacation_periods_status check (status in ('active', 'paused')),
  constraint vacation_periods_recurrence check (recurrence in ('none', 'yearly')),
  constraint vacation_periods_interval check (interval_value between 1 and 100),
  constraint vacation_periods_policy check (task_policy in ('postpone', 'skip')),
  constraint vacation_periods_scope check (
    task_scope in ('allRecurring', 'selectedTemplates')
  ),
  constraint vacation_periods_selected_templates_array check (
    case
      when jsonb_typeof(selected_template_ids) <> 'array' then false
      when task_scope = 'selectedTemplates'
        then jsonb_array_length(selected_template_ids) > 0
      else true
    end
  ),
  unique (user_id, id)
);

create index if not exists vacation_periods_active_range_idx
  on public.vacation_periods (user_id, start_date, end_date)
  where deleted_at is null and status = 'active';

drop trigger if exists prepare_vacation_periods on public.vacation_periods;
create trigger prepare_vacation_periods
before insert or update on public.vacation_periods
for each row execute function private.prepare_synchronized_record();

drop trigger if exists log_vacation_periods on public.vacation_periods;
create trigger log_vacation_periods
after insert or update on public.vacation_periods
for each row execute function private.log_synchronized_change();

alter table public.vacation_periods enable row level security;
alter table public.vacation_periods force row level security;

drop policy if exists owner_select_vacation_periods on public.vacation_periods;
create policy owner_select_vacation_periods
  on public.vacation_periods for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists owner_insert_vacation_periods on public.vacation_periods;
drop policy if exists owner_update_vacation_periods on public.vacation_periods;
drop policy if exists owner_delete_vacation_periods on public.vacation_periods;

grant select on public.vacation_periods to authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.vacation_periods from authenticated;
revoke all on public.vacation_periods from anon;

-- A narrow command endpoint avoids expanding the generic mutation function's
-- allowlist and keeps validation explicit for this scheduling-critical record.
create or replace function taskmaster_internal.apply_vacation_period_command(
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
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  current_revision bigint;
  processed_row public.processed_commands%rowtype;
  result_payload jsonb;
  invalid_keys text[];
  current_scope text;
  current_selected_template_ids jsonb;
  desired_scope text;
  desired_selected_template_ids jsonb;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_command_id is null
     or p_device_id is null
     or p_device_sequence is null
     or p_entity_id is null
     or p_operation is null then
    raise exception 'invalid_command_payload' using errcode = '23502';
  end if;
  if p_device_sequence < 1 then
    raise exception 'invalid_device_sequence' using errcode = '22023';
  end if;
  if p_base_revision is null or p_base_revision < 0 then
    raise exception 'invalid_base_revision' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(owner_id::text || ':' || p_command_id::text, 0)
  );
  select *
  into processed_row
  from public.processed_commands
  where user_id = owner_id and command_id = p_command_id
  for update;
  if found then
    if processed_row.device_id is distinct from p_device_id
       or processed_row.device_sequence is distinct from p_device_sequence
       or processed_row.entity_type is distinct from 'vacation_periods'
       or processed_row.entity_id is distinct from p_entity_id
       or processed_row.command_type is distinct from p_operation
       or processed_row.base_revision is distinct from p_base_revision then
      raise exception 'command_identity_mismatch' using errcode = '22023';
    end if;
    return processed_row.result;
  end if;

  -- Mutable authorization is checked only after a verified replay. A command
  -- whose response was lost remains idempotently replayable after that device
  -- is later revoked.
  if p_operation not in ('create', 'update', 'delete') then
    raise exception 'unsupported_operation' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.account_devices
    where user_id = owner_id
      and id = p_device_id
      and revoked_at is null
      and deleted_at is null
  ) then
    raise exception 'device_not_registered' using errcode = '42501';
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_payload' using errcode = '22023';
  end if;

  select array_agg(payload_key order by payload_key)
  into invalid_keys
  from pg_catalog.jsonb_object_keys(coalesce(p_payload, '{}'::jsonb))
    as payload(payload_key)
  where payload_key not in (
    'title', 'status', 'start_date', 'end_date', 'recurrence',
    'interval_value', 'task_policy', 'task_scope',
    'selected_template_ids', 'data'
  );
  if invalid_keys is not null then
    raise exception 'invalid_payload_columns: %', invalid_keys;
  end if;

  select revision, task_scope, selected_template_ids
  into current_revision, current_scope, current_selected_template_ids
  from public.vacation_periods
  where user_id = owner_id and id = p_entity_id
  for update;

  desired_scope := coalesce(
    p_payload ->> 'task_scope', current_scope, 'allRecurring'
  );
  desired_selected_template_ids := coalesce(
    p_payload -> 'selected_template_ids',
    current_selected_template_ids,
    '[]'::jsonb
  );
  if pg_catalog.jsonb_typeof(desired_selected_template_ids) <> 'array'
     or (
       desired_scope = 'selectedTemplates'
       and pg_catalog.jsonb_array_length(desired_selected_template_ids) = 0
     ) then
    raise exception 'selected_vacation_tasks_required' using errcode = '22023';
  end if;

  if p_operation = 'create' and current_revision is null then
    if p_base_revision <> 0 then
      result_payload := pg_catalog.jsonb_build_object(
        'status', 'conflict', 'reason', 'missing_entity',
        'server_revision', null
      );
    else
      insert into public.vacation_periods (
        id, user_id, title, status, start_date, end_date, recurrence,
        interval_value, task_policy, task_scope, selected_template_ids, data,
        created_by_device_id, updated_by_device_id, last_command_id
      ) values (
        p_entity_id,
        owner_id,
        p_payload ->> 'title',
        coalesce(p_payload ->> 'status', 'active'),
        (p_payload ->> 'start_date')::date,
        (p_payload ->> 'end_date')::date,
        coalesce(p_payload ->> 'recurrence', 'none'),
        coalesce((p_payload ->> 'interval_value')::integer, 1),
        coalesce(p_payload ->> 'task_policy', 'postpone'),
        coalesce(p_payload ->> 'task_scope', 'allRecurring'),
        coalesce(p_payload -> 'selected_template_ids', '[]'::jsonb),
        coalesce(p_payload -> 'data', '{}'::jsonb),
        p_device_id, p_device_id, p_command_id
      );
      result_payload := pg_catalog.jsonb_build_object(
        'status', 'accepted', 'entity_type', 'vacation_periods',
        'entity_id', p_entity_id, 'revision', 1
      );
    end if;
  elsif current_revision is null then
    result_payload := pg_catalog.jsonb_build_object(
      'status', 'conflict', 'reason', 'missing_entity',
      'server_revision', null
    );
  elsif current_revision <> p_base_revision then
    insert into public.sync_conflicts (
      user_id, command_id, entity_type, entity_id, conflict_type,
      base_revision, server_revision, local_payload, server_payload,
      created_by_device_id, updated_by_device_id
    ) values (
      owner_id, p_command_id, 'vacation_periods', p_entity_id,
      'revision_mismatch', p_base_revision, current_revision, p_payload,
      pg_catalog.jsonb_build_object('revision', current_revision),
      p_device_id, p_device_id
    ) on conflict (user_id, command_id, entity_id) do nothing;
    result_payload := pg_catalog.jsonb_build_object(
      'status', 'conflict', 'reason', 'revision_mismatch',
      'server_revision', current_revision
    );
  elsif p_operation = 'delete' then
    update public.vacation_periods
    set deleted_at = statement_timestamp(),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id
    where user_id = owner_id and id = p_entity_id;
    result_payload := pg_catalog.jsonb_build_object(
      'status', 'accepted', 'entity_type', 'vacation_periods',
      'entity_id', p_entity_id, 'revision', current_revision + 1,
      'deleted', true
    );
  else
    update public.vacation_periods
    set title = coalesce(p_payload ->> 'title', title),
        status = coalesce(p_payload ->> 'status', status),
        start_date = coalesce((p_payload ->> 'start_date')::date, start_date),
        end_date = coalesce((p_payload ->> 'end_date')::date, end_date),
        recurrence = coalesce(p_payload ->> 'recurrence', recurrence),
        interval_value = coalesce(
          (p_payload ->> 'interval_value')::integer, interval_value
        ),
        task_policy = coalesce(p_payload ->> 'task_policy', task_policy),
        task_scope = coalesce(p_payload ->> 'task_scope', task_scope),
        selected_template_ids = coalesce(
          p_payload -> 'selected_template_ids', selected_template_ids
        ),
        data = coalesce(p_payload -> 'data', data),
        updated_by_device_id = p_device_id,
        last_command_id = p_command_id,
        deleted_at = null
    where user_id = owner_id and id = p_entity_id;
    result_payload := pg_catalog.jsonb_build_object(
      'status', 'accepted', 'entity_type', 'vacation_periods',
      'entity_id', p_entity_id, 'revision', current_revision + 1
    );
  end if;

  insert into public.processed_commands (
    user_id, command_id, device_id, device_sequence, entity_type, entity_id,
    command_type, base_revision, status, result, created_by_device_id,
    updated_by_device_id, last_command_id
  ) values (
    owner_id, p_command_id, p_device_id, p_device_sequence,
    'vacation_periods', p_entity_id, p_operation, p_base_revision,
    case when result_payload ->> 'status' = 'accepted'
      then 'accepted'::public.sync_command_status
      else 'conflict'::public.sync_command_status end,
    result_payload, p_device_id, p_device_id, p_command_id
  );
  return result_payload;
end;
$$;

revoke all on function taskmaster_internal.apply_vacation_period_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon, authenticated;

grant execute on function taskmaster_internal.apply_vacation_period_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated, service_role;

create or replace function public.apply_vacation_period_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_entity_id uuid,
  p_base_revision bigint,
  p_operation text,
  p_payload jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_vacation_period_command(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_entity_id,
    p_base_revision,
    p_operation,
    p_payload
  )
$$;

revoke all on function public.apply_vacation_period_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon;

grant execute on function public.apply_vacation_period_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated;

comment on function public.apply_vacation_period_command is
  'Idempotent revision-checked mutation endpoint for account vacation policies.';

-- Fail this migration rather than ship a direct-write or privilege bypass.
do $$
declare
  internal_oid regprocedure := pg_catalog.to_regprocedure(
    'taskmaster_internal.apply_vacation_period_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)'
  );
  wrapper_oid regprocedure := pg_catalog.to_regprocedure(
    'public.apply_vacation_period_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)'
  );
  internal_is_definer boolean;
  wrapper_is_definer boolean;
  policy_count integer;
begin
  if internal_oid is null or wrapper_oid is null then
    raise exception 'missing_vacation_command_surface';
  end if;
  select procedure_row.prosecdef into internal_is_definer
  from pg_catalog.pg_proc procedure_row where procedure_row.oid = internal_oid;
  select procedure_row.prosecdef into wrapper_is_definer
  from pg_catalog.pg_proc procedure_row where procedure_row.oid = wrapper_oid;
  if not internal_is_definer or wrapper_is_definer then
    raise exception 'invalid_vacation_command_security_modes';
  end if;
  if pg_catalog.has_table_privilege(
    'authenticated', 'public.vacation_periods', 'INSERT'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'public.vacation_periods', 'UPDATE'
  ) or pg_catalog.has_table_privilege(
    'authenticated', 'public.vacation_periods', 'DELETE'
  ) then
    raise exception 'authenticated_vacation_table_mutation_privilege';
  end if;
  select count(*) into policy_count
  from pg_catalog.pg_policy policy_row
  where policy_row.polrelid = 'public.vacation_periods'::regclass;
  if policy_count <> 1 or not exists (
    select 1 from pg_catalog.pg_policy policy_row
    where policy_row.polrelid = 'public.vacation_periods'::regclass
      and policy_row.polcmd = 'r'
  ) then
    raise exception 'unexpected_vacation_policy_surface:%', policy_count;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.processed_commands'::regclass
      and trigger_row.tgname = 'verify_processed_command_session'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'missing_processed_command_session_trigger';
  end if;
end
$$;
