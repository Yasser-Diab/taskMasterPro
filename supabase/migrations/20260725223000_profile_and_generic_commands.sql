-- Account profile fields and the revision-checked command endpoint used by
-- every local-first feature record beyond task occurrences.

alter table public.profiles
  add column if not exists gender_identity text;

alter table public.profiles
  drop constraint if exists profiles_gender_identity_check;

alter table public.profiles
  add constraint profiles_gender_identity_check
  check (
    gender_identity is null
    or gender_identity in (
      'woman',
      'man',
      'non_binary',
      'self_described',
      'prefer_not_to_say'
    )
  );

create or replace function public.apply_entity_command(
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
  allowed_tables constant text[] := array[
    'profiles',
    'user_settings',
    'coaching_settings',
    'privacy_settings',
    'task_domains',
    'task_categories',
    'tags',
    'task_templates',
    'recurrence_rules',
    'recurrence_exceptions',
    'task_dependencies',
    'task_reminders',
    'execution_sessions',
    'session_events',
    'checklist_items',
    'pomodoro_cycles',
    'interruptions',
    'task_completion_evidence',
    'work_demands',
    'learning_checkpoints',
    'reading_targets',
    'reading_positions',
    'habit_records',
    'event_attendance',
    'task_notes',
    'roadmaps',
    'roadmap_phases',
    'roadmap_milestones',
    'roadmap_checkpoints',
    'roadmap_progress_rules',
    'roadmap_evidence',
    'roadmap_forecasts',
    'application_catalog',
    'application_rules',
    'website_rules',
    'activity_segments',
    'activity_attributions',
    'activity_contributions',
    'classification_feedback',
    'task_resources',
    'resource_activity',
    'browser_workspaces',
    'browser_tabs',
    'browser_bookmarks',
    'browser_history_events',
    'browser_closed_tabs',
    'document_positions',
    'coaching_feedback',
    'health_permissions',
    'health_summaries',
    'cycle_records'
  ];
  protected_columns constant text[] := array[
    'id',
    'user_id',
    'revision',
    'created_at',
    'updated_at',
    'created_by_device_id',
    'updated_by_device_id',
    'last_command_id',
    'deleted_at'
  ];
  target_table regclass;
  current_revision bigint;
  existing_result jsonb;
  result_payload jsonb;
  invalid_keys text[];
  payload_columns text;
  payload_values text;
  update_assignments text;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_entity_type <> all (allowed_tables) then
    raise exception 'unsupported_entity_type';
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

  target_table := to_regclass(
    'public.' || quote_ident(p_entity_type)
  );
  if target_table is null then
    raise exception 'missing_entity_table';
  end if;

  select array_agg(payload_key order by payload_key)
  into invalid_keys
  from jsonb_object_keys(coalesce(p_payload, '{}'::jsonb)) as payload(payload_key)
  where payload_key = any (protected_columns)
     or not exists (
       select 1
       from pg_catalog.pg_attribute attribute
       where attribute.attrelid = target_table
         and attribute.attname = payload_key
         and attribute.attnum > 0
         and not attribute.attisdropped
     );

  if invalid_keys is not null then
    raise exception 'invalid_payload_columns: %', invalid_keys;
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

  execute format(
    'select revision from public.%I
     where user_id = $1 and id = $2 for update',
    p_entity_type
  )
  into current_revision
  using owner_id, p_entity_id;

  if p_operation = 'create' and current_revision is null then
    if p_base_revision <> 0 then
      result_payload := jsonb_build_object(
        'status', 'conflict',
        'reason', 'missing_entity',
        'server_revision', null
      );
    else
      select
        string_agg(format('%I', payload_key), ', ' order by payload_key),
        string_agg(
          case
            when attribute.atttypid = 'jsonb'::regtype then
              format('($1 -> %L)::jsonb', payload_key)
            else
              format(
                '($1 ->> %L)::%s',
                payload_key,
                pg_catalog.format_type(
                  attribute.atttypid,
                  attribute.atttypmod
                )
              )
          end,
          ', ' order by payload_key
        )
      into payload_columns, payload_values
      from jsonb_object_keys(coalesce(p_payload, '{}'::jsonb))
        as payload(payload_key)
      join pg_catalog.pg_attribute attribute
        on attribute.attrelid = target_table
       and attribute.attname = payload_key
       and attribute.attnum > 0
       and not attribute.attisdropped;

      if payload_columns is null then
        execute format(
          'insert into public.%I (
             id, user_id, created_by_device_id, updated_by_device_id,
             last_command_id
           ) values ($1, $2, $3, $3, $4)',
          p_entity_type
        )
        using p_entity_id, owner_id, p_device_id, p_command_id;
      else
        execute format(
          'insert into public.%I (
             id, user_id, %s, created_by_device_id, updated_by_device_id,
             last_command_id
           ) values ($2, $3, %s, $4, $4, $5)',
          p_entity_type,
          payload_columns,
          payload_values
        )
        using p_payload, p_entity_id, owner_id, p_device_id, p_command_id;
      end if;

      result_payload := jsonb_build_object(
        'status', 'accepted',
        'entity_type', p_entity_type,
        'entity_id', p_entity_id,
        'revision', 1
      );
    end if;
  elsif current_revision is null then
    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'missing_entity',
      'server_revision', null
    );
  elsif current_revision <> p_base_revision then
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
      updated_by_device_id
    )
    values (
      owner_id,
      p_command_id,
      p_entity_type,
      p_entity_id,
      'revision_mismatch',
      p_base_revision,
      current_revision,
      p_payload,
      jsonb_build_object('revision', current_revision),
      p_device_id,
      p_device_id
    )
    on conflict (user_id, command_id, entity_id) do nothing;

    result_payload := jsonb_build_object(
      'status', 'conflict',
      'reason', 'revision_mismatch',
      'server_revision', current_revision
    );
  elsif p_operation = 'delete' then
    execute format(
      'update public.%I
       set deleted_at = statement_timestamp(),
           updated_by_device_id = $1,
           last_command_id = $2
       where user_id = $3 and id = $4',
      p_entity_type
    )
    using p_device_id, p_command_id, owner_id, p_entity_id;

    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
      'revision', current_revision + 1,
      'deleted', true
    );
  else
    select string_agg(
      case
        when attribute.atttypid = 'jsonb'::regtype then
          format('%I = ($1 -> %L)::jsonb', payload_key, payload_key)
        else
          format(
            '%I = ($1 ->> %L)::%s',
            payload_key,
            payload_key,
            pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
          )
      end,
      ', ' order by payload_key
    )
    into update_assignments
    from jsonb_object_keys(coalesce(p_payload, '{}'::jsonb))
      as payload(payload_key)
    join pg_catalog.pg_attribute attribute
      on attribute.attrelid = target_table
     and attribute.attname = payload_key
     and attribute.attnum > 0
     and not attribute.attisdropped;

    if update_assignments is null then
      execute format(
        'update public.%I
         set updated_by_device_id = $1,
             last_command_id = $2,
             deleted_at = null
         where user_id = $3 and id = $4',
        p_entity_type
      )
      using p_device_id, p_command_id, owner_id, p_entity_id;
    else
      execute format(
        'update public.%I
         set %s,
             updated_by_device_id = $2,
             last_command_id = $3,
             deleted_at = null
         where user_id = $4 and id = $5',
        p_entity_type,
        update_assignments
      )
      using p_payload, p_device_id, p_command_id, owner_id, p_entity_id;
    end if;

    result_payload := jsonb_build_object(
      'status', 'accepted',
      'entity_type', p_entity_type,
      'entity_id', p_entity_id,
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
    p_entity_type,
    p_entity_id,
    p_operation,
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

revoke all on function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) from public, anon;

grant execute on function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) to authenticated;

comment on function public.apply_entity_command is
  'Idempotent revision-checked mutation endpoint for allowlisted user-owned synchronized records.';
