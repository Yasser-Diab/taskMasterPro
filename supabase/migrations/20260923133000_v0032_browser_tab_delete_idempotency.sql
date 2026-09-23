-- A browser-tab close can be delivered twice: for example, when a desktop
-- close races with a resume/reconnect delivery.  The second command must not
-- become a user-visible conflict if the canonical tab is already deleted.
--
-- Keep the mature generic revision-checked command handler intact and put a
-- narrowly scoped idempotency gate in front of it.  A stale delete is accepted
-- only for a tab owned by the authenticated account that is *currently*
-- deleted.  A tab restored after a close still reaches the normal revision
-- check, so an old delete can never erase a later restore.

alter function taskmaster_internal.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) rename to apply_entity_command_revision_checked_v0032;

create or replace function taskmaster_internal.apply_entity_command(
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
security definer
set search_path = ''
as $$
declare
  owner_id uuid := (select auth.uid());
  canonical_revision bigint;
  canonical_deleted_at timestamptz;
  accepted_result jsonb;
begin
  if p_entity_type = 'browser_tabs' and p_operation = 'delete' and owner_id is not null
  then
    -- Preserve the original authentication and device-authorization contract.
    -- An unregistered device is intentionally delegated to the guarded handler
    -- below so it receives the same deterministic rejection as every other
    -- entity command.
    if exists (
      select 1
      from public.account_devices
      where user_id = owner_id
        and id = p_device_id
        and revoked_at is null
        and deleted_at is null
    ) then
      perform pg_advisory_xact_lock(
        hashtextextended(owner_id::text || ':' || p_command_id::text, 0)
      );

      select revision, deleted_at
      into canonical_revision, canonical_deleted_at
      from public.browser_tabs
      where user_id = owner_id
        and id = p_entity_id
      for update;

      if found and canonical_deleted_at is not null then
        accepted_result := jsonb_build_object(
          'status', 'accepted',
          'entity_type', 'browser_tabs',
          'entity_id', p_entity_id,
          'revision', canonical_revision,
          'deleted', true,
          'idempotent', true,
          'reason', 'already_deleted'
        );

        -- A previously recorded revision conflict is safely repaired here as
        -- well.  The canonical row proves that this delete's intent has already
        -- been fulfilled, so replaying the original command ID now converges
        -- instead of requiring user intervention.
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
          'browser_tabs',
          p_entity_id,
          'delete',
          p_base_revision,
          'accepted'::public.sync_command_status,
          accepted_result,
          p_device_id,
          p_device_id,
          p_command_id
        )
        on conflict (user_id, command_id) do update
        set status = excluded.status,
            result = excluded.result,
            processed_at = statement_timestamp(),
            updated_at = statement_timestamp(),
            updated_by_device_id = excluded.updated_by_device_id,
            last_command_id = excluded.last_command_id;

        return accepted_result;
      end if;
    end if;
  end if;

  return taskmaster_internal.apply_entity_command_revision_checked_v0032(
    p_command_id,
    p_device_id,
    p_device_sequence,
    p_entity_type,
    p_entity_id,
    p_base_revision,
    p_operation,
    p_payload
  );
end;
$$;

revoke all on function taskmaster_internal.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) from public, anon;

grant execute on function taskmaster_internal.apply_entity_command(
  uuid, uuid, bigint, text, uuid, bigint, text, jsonb
) to authenticated, service_role;

comment on function taskmaster_internal.apply_entity_command is
  'Revision-checked sync command endpoint with idempotent browser-tab deletion convergence.';

-- Repair earlier duplicate tab closes only when the canonical tab has already
-- been deleted.  No active tab, restore, or unrelated conflict is changed.
with repaired_commands as (
  update public.processed_commands as command
  set status = 'accepted'::public.sync_command_status,
      result = jsonb_build_object(
        'status', 'accepted',
        'entity_type', 'browser_tabs',
        'entity_id', tab.id,
        'revision', tab.revision,
        'deleted', true,
        'idempotent', true,
        'reason', 'already_deleted'
      ),
      processed_at = statement_timestamp(),
      updated_at = statement_timestamp(),
      updated_by_device_id = command.device_id,
      last_command_id = command.command_id
  from public.browser_tabs as tab
  where command.user_id = tab.user_id
    and command.entity_id = tab.id
    and command.entity_type = 'browser_tabs'
    and command.command_type = 'delete'
    and command.status = 'conflict'::public.sync_command_status
    and command.result ->> 'reason' = 'revision_mismatch'
    and tab.deleted_at is not null
  returning command.user_id, command.command_id, command.entity_id
)
update public.sync_conflicts as conflict
set resolution_status = 'superseded',
    resolution = jsonb_build_object(
      'reason', 'browser_tab_already_deleted',
      'resolved_by', 'v0032_browser_tab_delete_idempotency'
    ),
    resolved_at = statement_timestamp(),
    updated_at = statement_timestamp(),
    last_command_id = repaired.command_id
from repaired_commands as repaired
where conflict.user_id = repaired.user_id
  and conflict.command_id = repaired.command_id
  and conflict.entity_id = repaired.entity_id
  and conflict.entity_type = 'browser_tabs'
  and conflict.conflict_type = 'revision_mismatch'
  and conflict.resolution_status = 'unresolved';
