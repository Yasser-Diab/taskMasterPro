-- P0 account-isolation hardening.
--
-- The client must never decide record ownership. Keep this migration
-- idempotent so it also protects user-owned tables introduced by a later
-- feature migration. Each policy uses the authenticated Supabase subject,
-- never an email address, device ID, or client-provided owner field.
do $$
declare
  owned_table record;
begin
  for owned_table in
    select distinct table_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'user_id'
  loop
    execute format(
      'alter table public.%I enable row level security',
      owned_table.table_name
    );
    execute format(
      'alter table public.%I force row level security',
      owned_table.table_name
    );

    if not exists (
      select 1
      from pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = owned_table.table_name
        and policy.cmd = 'SELECT'
        and policy.roles::text like '%authenticated%'
        and policy.qual like '%auth.uid()%'
    ) then
      execute format(
        'create policy %I on public.%I for select to authenticated
         using ((select auth.uid()) = user_id)',
        'account_isolation_select_' || owned_table.table_name,
        owned_table.table_name
      );
    end if;

    if not exists (
      select 1
      from pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = owned_table.table_name
        and policy.cmd = 'INSERT'
        and policy.roles::text like '%authenticated%'
        and policy.with_check like '%auth.uid()%'
    ) then
      execute format(
        'create policy %I on public.%I for insert to authenticated
         with check ((select auth.uid()) = user_id)',
        'account_isolation_insert_' || owned_table.table_name,
        owned_table.table_name
      );
    end if;

    if not exists (
      select 1
      from pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = owned_table.table_name
        and policy.cmd = 'UPDATE'
        and policy.roles::text like '%authenticated%'
        and policy.qual like '%auth.uid()%'
        and policy.with_check like '%auth.uid()%'
    ) then
      execute format(
        'create policy %I on public.%I for update to authenticated
         using ((select auth.uid()) = user_id)
         with check ((select auth.uid()) = user_id)',
        'account_isolation_update_' || owned_table.table_name,
        owned_table.table_name
      );
    end if;

    if not exists (
      select 1
      from pg_policies policy
      where policy.schemaname = 'public'
        and policy.tablename = owned_table.table_name
        and policy.cmd = 'DELETE'
        and policy.roles::text like '%authenticated%'
        and policy.qual like '%auth.uid()%'
    ) then
      execute format(
        'create policy %I on public.%I for delete to authenticated
         using ((select auth.uid()) = user_id)',
        'account_isolation_delete_' || owned_table.table_name,
        owned_table.table_name
      );
    end if;
  end loop;
end
$$;

-- Trigger-only private functions must never be callable through the Data API.
revoke all on function private.bootstrap_account() from public, anon, authenticated;
revoke all on function private.broadcast_sync_change() from public, anon, authenticated;
revoke all on function private.log_synchronized_change() from public, anon, authenticated;
revoke all on function private.purge_due_taskmaster_accounts() from public, anon, authenticated;
revoke all on function private.validate_roadmap_task_link() from public, anon, authenticated;

-- This command independently verifies auth.uid(), but an anonymous caller has
-- no valid use for it. Restrict its exposed execute privilege as well.
revoke all on function public.apply_user_settings_command(
  uuid, uuid, bigint, bigint, jsonb
) from public, anon;
grant execute on function public.apply_user_settings_command(
  uuid, uuid, bigint, bigint, jsonb
) to authenticated;
