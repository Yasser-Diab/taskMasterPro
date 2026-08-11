-- The conflict-resolution endpoint owns elevated table access, so pin an
-- empty search path and qualify every external object it uses.

create or replace function public.resolve_sync_conflict_v0026(
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

  if p_strategy not in (
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
        'resolved_by', 'taskmaster_pro_v0.0.26'
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

revoke all on function public.resolve_sync_conflict_v0026(uuid, text)
  from public, anon;
grant execute on function public.resolve_sync_conflict_v0026(uuid, text)
  to authenticated;
