-- TaskMaster Pro v0.0.27: owner-scoped conflict decisions and audit.
--
-- A notice dismissal never mutates canonical application data. Discarding a
-- local command is enforced by the local durable outbox; this RPC records the
-- decision against the server-side diagnostics row so another device does not
-- revive the same obsolete notice.

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
  resolved_status text;
begin
  if owner_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_strategy not in (
    'accepted_create_superseded_stale_update',
    'already_applied',
    'canonical_lifecycle_superseded',
    'delete_already_canonical',
    'device_local_activity_not_shared',
    'discarded_local_change',
    'idempotent_duplicate_create',
    'kept_device_version',
    'kept_server_version',
    'legacy_transport_retired',
    'local_command_already_superseded',
    'missing_local_activity_source'
  ) then
    raise exception 'unsupported_resolution_strategy'
      using errcode = '22023';
  end if;

  resolved_status := case
    when p_strategy = 'discarded_local_change' then 'discarded_by_user'
    else 'auto_resolved'
  end;

  update public.sync_conflicts
  set resolution_status = resolved_status,
      resolution = pg_catalog.jsonb_build_object(
        'strategy', p_strategy,
        'resolved_by', 'taskmaster_pro_v0.0.27'
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
