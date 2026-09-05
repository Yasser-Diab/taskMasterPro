-- DayVector 0.0.30: two event-driven delivery paths for the authoritative
-- singleton runtime.  The private broadcast is preferred; the filtered row
-- stream ensures a policy/trigger regression can never make Start, Pause or
-- Resume wait for an unrelated action on another device.
--
-- Apply only to the active DayVector project (tmvarulrujkmibqpqoeo). No data
-- rows are rewritten and no legacy TaskMaster Pro backend is touched.

do $$
begin
  if exists (
    select 1 from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) then
    begin
      alter publication supabase_realtime add table public.user_runtime_state;
    exception
      when duplicate_object then null;
      when undefined_object then null;
    end;
  end if;
end
$$;

create or replace function private.broadcast_sync_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'sequence', new.change_sequence,
      'entity_type', new.entity_type,
      'entity_id', new.entity_id,
      'operation', new.operation,
      'revision', new.entity_revision
    ),
    'entity_changed',
    'taskmaster:user:' || new.user_id::text || ':runtime',
    true
  );
  return new;
end;
$$;

drop trigger if exists broadcast_sync_change on public.sync_change_log;
create trigger broadcast_sync_change
  after insert on public.sync_change_log
  for each row execute function private.broadcast_sync_change();

drop policy if exists taskmaster_runtime_broadcast_receive
  on realtime.messages;
create policy taskmaster_runtime_broadcast_receive
  on realtime.messages
  for select
  to authenticated
  using (
    topic =
      'taskmaster:user:' || (select auth.uid())::text || ':runtime'
  );

revoke all on function private.broadcast_sync_change()
  from public, anon, authenticated;
