-- Keep the externally callable conflict endpoint as SECURITY INVOKER. Its
-- narrow privileged implementation lives outside the PostgREST-exposed
-- schema, remains owner-scoped, and retains the empty search path.

create function taskmaster_internal.resolve_sync_conflict_v0028(
  p_conflict_id uuid,
  p_strategy text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  changed_count integer;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_strategy is null or p_strategy not in (
    'accepted_create_superseded_stale_update',
    'canonical_lifecycle_superseded',
    'delete_already_canonical',
    'device_local_activity_not_shared',
    'idempotent_duplicate_create',
    'local_command_already_superseded',
    'missing_local_activity_source'
  ) then
    raise exception 'unsupported_resolution_strategy'
      using errcode = '22023';
  end if;

  update public.sync_conflicts
  set resolution_status = 'auto_resolved',
      resolution = pg_catalog.jsonb_build_object(
        'strategy', p_strategy,
        'resolved_by', 'taskmaster_pro_v0.0.28'
      ),
      resolved_at = pg_catalog.statement_timestamp(),
      updated_at = pg_catalog.statement_timestamp(),
      revision = revision + 1
  where id = p_conflict_id
    and user_id = owner_id
    and resolution_status = 'unresolved';

  get diagnostics changed_count = row_count;
  return changed_count = 1;
end;
$$;

create or replace function public.resolve_sync_conflict_v0026(
  p_conflict_id uuid,
  p_strategy text
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select taskmaster_internal.resolve_sync_conflict_v0028(
    p_conflict_id,
    p_strategy
  )
$$;

revoke all on function taskmaster_internal.resolve_sync_conflict_v0028(
  uuid, text
) from public, anon;
grant execute on function taskmaster_internal.resolve_sync_conflict_v0028(
  uuid, text
) to authenticated, service_role;

revoke all on function public.resolve_sync_conflict_v0026(uuid, text)
  from public, anon;
grant execute on function public.resolve_sync_conflict_v0026(uuid, text)
  to authenticated;

comment on function public.resolve_sync_conflict_v0026(uuid, text) is
  'Owner-scoped conflict-resolution wrapper. The privileged implementation is internal and not PostgREST-exposed.';
