-- One-time QA/production-repair reset for the verified DayVector owner.
--
-- This deliberately preserves account identity, profile/preferences, task
-- domains, and encrypted vault data. It removes the operational workspace
-- that can replay obsolete v0.0.26 commands: tasks, roadmaps, Activity,
-- health summaries, device registrations, browser workspaces, reports,
-- notifications, command ledgers, change-log rows, and sync conflicts.
--
-- Auth users are never touched. Run only after exporting the owner's rows and
-- force-stopping DayVector on every device.

begin;

set local session_replication_role = replica;

do $reset$
declare
  owner_id constant uuid := '4bd3e32d-1dcd-48ed-9f64-9099675047f1';
  relation record;
begin
  if not exists (
    select 1
    from public.profiles
    where user_id = owner_id
      and deleted_at is null
  ) then
    raise exception 'Verified DayVector owner profile is missing';
  end if;

  for relation in
    select distinct columns.table_name
    from information_schema.columns as columns
    join information_schema.tables as tables
      on tables.table_schema = columns.table_schema
     and tables.table_name = columns.table_name
    where columns.table_schema = 'public'
      and columns.column_name = 'user_id'
      and tables.table_type = 'BASE TABLE'
      and columns.table_name not in (
        'profiles',
        'user_settings',
        'privacy_settings',
        'coaching_settings',
        'task_domains',
        'user_vaults',
        'vault_items',
        'vault_device_keys'
      )
    order by columns.table_name
  loop
    execute format(
      'delete from public.%I where user_id = $1',
      relation.table_name
    )
    using owner_id;
  end loop;
end
$reset$;

commit;

select
  (select count(*) from public.roadmaps
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as roadmaps,
  (select count(*) from public.task_occurrences
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as tasks,
  (select count(*) from public.activity_segments
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as activity_segments,
  (select count(*) from public.processed_commands
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as processed_commands,
  (select count(*) from public.sync_conflicts
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as sync_conflicts,
  (select count(*) from public.sync_change_log
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as sync_change_log,
  (select count(*) from public.profiles
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as preserved_profiles,
  (select count(*) from public.user_settings
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as preserved_settings,
  (select count(*) from public.user_vaults
    where user_id = '4bd3e32d-1dcd-48ed-9f64-9099675047f1') as preserved_vaults;
