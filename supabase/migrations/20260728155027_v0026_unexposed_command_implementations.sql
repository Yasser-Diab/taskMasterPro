-- Keep SECURITY DEFINER command implementations outside every Data API
-- exposed schema. Public RPCs remain SECURITY INVOKER forwarding surfaces,
-- which removes direct privileged code from `/rest/v1/rpc` while retaining
-- the read-only-table command architecture required by v0.0.26.

alter function public.apply_task_occurrence_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) set schema taskmaster_internal;

alter function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) set schema taskmaster_internal;

alter function public.apply_user_settings_command(
  uuid, uuid, bigint, bigint, jsonb
) set schema taskmaster_internal;

alter function public.apply_user_settings_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) set schema taskmaster_internal;

alter function public.apply_task_occurrence_v0026_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) set schema taskmaster_internal;

alter function public.apply_vault_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) set schema taskmaster_internal;

alter function public.schedule_account_deletion(
  uuid, text
) set schema taskmaster_internal;

alter function public.cancel_account_deletion(
  uuid
) set schema taskmaster_internal;

alter function public.apply_roadmap_task_link_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) set schema taskmaster_internal;

alter function public.apply_activity_contribution_batch(
  jsonb
) set schema taskmaster_internal;

alter function public.apply_profile_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) set schema taskmaster_internal;

alter function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) set schema taskmaster_internal;

alter function public.apply_execution_switch_v0026_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode
) set schema taskmaster_internal;

alter function public.revoke_account_device(
  uuid, uuid, bigint, uuid
) set schema taskmaster_internal;

alter function public.register_account_device(
  uuid, text, text, text, text
) set schema taskmaster_internal;

revoke all on all functions in schema taskmaster_internal
  from public, anon;
grant usage on schema taskmaster_internal to authenticated, service_role;
grant execute on all functions in schema taskmaster_internal
  to authenticated, service_role;

-- The legacy transition implementation remains private even from signed-in
-- roles. Only the current internal implementation may invoke it.
revoke execute on function
  taskmaster_internal.apply_execution_transition_v0026_command_legacy(
    uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
  )
from authenticated, service_role;

create function public.apply_task_occurrence_command(
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
  select taskmaster_internal.apply_task_occurrence_command(
    p_command_id, p_device_id, p_device_sequence, p_entity_id,
    p_base_revision, p_operation, p_payload
  )
$$;

create function public.apply_entity_command(
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
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_entity_command(
    p_command_id, p_device_id, p_device_sequence, p_entity_type, p_entity_id,
    p_base_revision, p_operation, p_payload
  )
$$;

create function public.apply_user_settings_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_base_revision bigint,
  p_payload jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_user_settings_command(
    p_command_id, p_device_id, p_device_sequence, p_base_revision, p_payload
  )
$$;

create function public.apply_user_settings_merge_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_base_revision bigint,
  p_payload jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_user_settings_merge_command(
    p_command_id, p_device_id, p_device_sequence, p_base_revision, p_payload
  )
$$;

create function public.apply_task_occurrence_v0026_command(
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
  select taskmaster_internal.apply_task_occurrence_v0026_command(
    p_command_id, p_device_id, p_device_sequence, p_entity_id,
    p_base_revision, p_operation, p_payload
  )
$$;

create function public.apply_vault_command(
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
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_vault_command(
    p_command_id, p_device_id, p_device_sequence, p_entity_type, p_entity_id,
    p_base_revision, p_operation, p_payload
  )
$$;

create function public.schedule_account_deletion(
  p_device_id uuid,
  p_confirmation text
)
returns public.account_deletion_requests
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return taskmaster_internal.schedule_account_deletion(
    p_device_id,
    p_confirmation
  );
end
$$;

create function public.cancel_account_deletion(
  p_device_id uuid
)
returns public.account_deletion_requests
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return taskmaster_internal.cancel_account_deletion(p_device_id);
end
$$;

create function public.apply_roadmap_task_link_command(
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
  select taskmaster_internal.apply_roadmap_task_link_command(
    p_command_id, p_device_id, p_device_sequence, p_entity_id,
    p_base_revision, p_operation, p_payload
  )
$$;

create function public.apply_activity_contribution_batch(
  p_commands jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_activity_contribution_batch(p_commands)
$$;

create function public.apply_profile_merge_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_base_revision bigint,
  p_payload jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_profile_merge_command(
    p_command_id, p_device_id, p_device_sequence, p_base_revision, p_payload
  )
$$;

create function public.apply_execution_transition_v0026_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_session_id uuid,
  p_task_occurrence_id uuid,
  p_action text,
  p_mode public.execution_mode
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_execution_transition_v0026_command(
    p_command_id, p_device_id, p_device_sequence, p_session_id,
    p_task_occurrence_id, p_action, p_mode
  )
$$;

create function public.apply_execution_switch_v0026_command(
  p_command_id uuid,
  p_device_id uuid,
  p_device_sequence bigint,
  p_new_session_id uuid,
  p_new_task_occurrence_id uuid,
  p_expected_active_session_id uuid,
  p_expected_active_task_id uuid,
  p_current_task_action text,
  p_mode public.execution_mode
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.apply_execution_switch_v0026_command(
    p_command_id, p_device_id, p_device_sequence, p_new_session_id,
    p_new_task_occurrence_id, p_expected_active_session_id,
    p_expected_active_task_id, p_current_task_action, p_mode
  )
$$;

create function public.revoke_account_device(
  p_command_id uuid,
  p_requesting_device_id uuid,
  p_device_sequence bigint,
  p_target_device_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.revoke_account_device(
    p_command_id, p_requesting_device_id, p_device_sequence,
    p_target_device_id
  )
$$;

create function public.register_account_device(
  p_device_id uuid,
  p_device_name text,
  p_platform text,
  p_app_version text default null,
  p_device_public_key text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.register_account_device(
    p_device_id, p_device_name, p_platform, p_app_version,
    p_device_public_key
  )
$$;

revoke all on function public.apply_task_occurrence_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_task_occurrence_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated;

revoke all on function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) to authenticated;

revoke all on function public.apply_user_settings_command(
  uuid, uuid, bigint, bigint, jsonb
) from public, anon;
grant execute on function public.apply_user_settings_command(
  uuid, uuid, bigint, bigint, jsonb
) to authenticated;

revoke all on function public.apply_user_settings_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) from public, anon;
grant execute on function public.apply_user_settings_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) to authenticated;

revoke all on function public.apply_task_occurrence_v0026_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_task_occurrence_v0026_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated;

revoke all on function public.apply_vault_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_vault_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) to authenticated;

revoke all on function public.schedule_account_deletion(
  uuid, text
) from public, anon;
grant execute on function public.schedule_account_deletion(
  uuid, text
) to authenticated;

revoke all on function public.cancel_account_deletion(
  uuid
) from public, anon;
grant execute on function public.cancel_account_deletion(
  uuid
) to authenticated;

revoke all on function public.apply_roadmap_task_link_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) from public, anon;
grant execute on function public.apply_roadmap_task_link_command(
  uuid, uuid, bigint, uuid, bigint, text, jsonb
) to authenticated;

revoke all on function public.apply_activity_contribution_batch(
  jsonb
) from public, anon;
grant execute on function public.apply_activity_contribution_batch(
  jsonb
) to authenticated;

revoke all on function public.apply_profile_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) from public, anon;
grant execute on function public.apply_profile_merge_command(
  uuid, uuid, bigint, bigint, jsonb
) to authenticated;

revoke all on function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) from public, anon;
grant execute on function public.apply_execution_transition_v0026_command(
  uuid, uuid, bigint, uuid, uuid, text, public.execution_mode
) to authenticated;

revoke all on function public.apply_execution_switch_v0026_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode
) from public, anon;
grant execute on function public.apply_execution_switch_v0026_command(
  uuid, uuid, bigint, uuid, uuid, uuid, uuid, text, public.execution_mode
) to authenticated;

revoke all on function public.revoke_account_device(
  uuid, uuid, bigint, uuid
) from public, anon;
grant execute on function public.revoke_account_device(
  uuid, uuid, bigint, uuid
) to authenticated;

revoke all on function public.register_account_device(
  uuid, text, text, text, text
) from public, anon;
grant execute on function public.register_account_device(
  uuid, text, text, text, text
) to authenticated;

do $assertions$
declare
  signature text;
  function_oid regprocedure;
  public_is_definer boolean;
  internal_is_definer boolean;
  command_signatures constant text[] := array[
    'apply_task_occurrence_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)',
    'apply_entity_command(uuid,uuid,bigint,text,uuid,bigint,text,jsonb)',
    'apply_user_settings_command(uuid,uuid,bigint,bigint,jsonb)',
    'apply_user_settings_merge_command(uuid,uuid,bigint,bigint,jsonb)',
    'apply_task_occurrence_v0026_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)',
    'apply_vault_command(uuid,uuid,bigint,text,uuid,bigint,text,jsonb)',
    'schedule_account_deletion(uuid,text)',
    'cancel_account_deletion(uuid)',
    'apply_roadmap_task_link_command(uuid,uuid,bigint,uuid,bigint,text,jsonb)',
    'apply_activity_contribution_batch(jsonb)',
    'apply_profile_merge_command(uuid,uuid,bigint,bigint,jsonb)',
    'apply_execution_transition_v0026_command(uuid,uuid,bigint,uuid,uuid,text,public.execution_mode)',
    'apply_execution_switch_v0026_command(uuid,uuid,bigint,uuid,uuid,uuid,uuid,text,public.execution_mode)',
    'revoke_account_device(uuid,uuid,bigint,uuid)',
    'register_account_device(uuid,text,text,text,text)'
  ];
begin
  foreach signature in array command_signatures
  loop
    function_oid := to_regprocedure('public.' || signature);
    if function_oid is null then
      raise exception 'missing_public_command_wrapper:%', signature;
    end if;
    select procedure_row.prosecdef
    into public_is_definer
    from pg_catalog.pg_proc procedure_row
    where procedure_row.oid = function_oid;
    if public_is_definer then
      raise exception 'public_command_wrapper_is_security_definer:%',
        signature;
    end if;

    function_oid := to_regprocedure('taskmaster_internal.' || signature);
    if function_oid is null then
      raise exception 'missing_internal_command_implementation:%', signature;
    end if;
    select procedure_row.prosecdef
    into internal_is_definer
    from pg_catalog.pg_proc procedure_row
    where procedure_row.oid = function_oid;
    if not internal_is_definer then
      raise exception 'internal_command_not_security_definer:%', signature;
    end if;
  end loop;
end
$assertions$;
