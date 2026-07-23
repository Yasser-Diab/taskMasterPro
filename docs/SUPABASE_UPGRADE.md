# Supabase Upgrade

Run the migrations in filename order. The latest coordinated upgrade is:

```text
supabase/migrations/20260717190000_workspace_reading_timezone_health_offline.sql
```

With a linked Supabase CLI project:

```powershell
supabase login
supabase link --project-ref <your-project-ref>
supabase migration list
supabase db push
```

Alternatively, open the latest migration in the Supabase SQL Editor and run it
after every earlier migration through
`20260717160000_core_productivity_execution_upgrade.sql` has succeeded.

The migration is idempotent where PostgreSQL permits it. It adds scheduling
intent, reading and break records, Health Connect summaries, the sync outbox,
task browser state, revision metadata, active-session leases, indexes, grants,
user-owned RLS policies, fixed function search paths, and anonymous-execution
revokes for security-definer RPCs.

Do not place a database password, service-role key, account password, access
token, refresh token, website cookie, or health-provider credential in this
repository or in the Flutter application.

After applying the migration, verify:

```sql
select to_regclass('public.books') as books,
       to_regclass('public.reading_sessions') as reading_sessions,
       to_regclass('public.break_contributions') as break_contributions,
       to_regclass('public.health_records') as health_records,
       to_regclass('public.sync_outbox') as sync_outbox,
       to_regclass('public.active_session_leases') as active_session_leases;

select proname
from pg_proc
where proname in (
  'claim_active_session_control',
  'release_active_session_control'
)
order by proname;
```

Then rerun the Supabase database linter. Anonymous execution warnings for the
app RPCs should be removed. A small number of authenticated
`SECURITY DEFINER` warnings may remain for intentionally callable RPCs such as
startup bootstrap, startup state, owner-checked diagnostics, and account export;
those functions verify `auth.uid()` and user ownership internally.

The leaked-password protection warning is not controlled by SQL migrations.
Enable it in Supabase Dashboard:

```text
Authentication -> Security -> Leaked password protection
```
