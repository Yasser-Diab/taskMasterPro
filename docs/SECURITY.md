# Security Notes

## Supabase Keys

The client app accepts only a Supabase project URL and a public publishable or anon key.

The app rejects:

- `sb_secret` keys.
- Service-role JWTs.
- Admin JWTs.
- Database connection strings.
- JWT signing secrets.

The service-role key and database password must stay outside Windows and Android client code. Use them only in trusted server-side environments or local administrative tooling.

## Password Recovery

The app uses `resetPasswordForEmail()`, signup confirmation and email-change confirmation with:

```text
taskmasterpro://auth/callback
```

Do not use invitation emails for password reset. Hosted Supabase Auth settings and email templates must not point to `localhost` for production recovery links.

## RLS

The initial migration enables row level security on user-owned tables. User rows are scoped with:

```sql
user_id = auth.uid()
```

The `profiles` table is scoped by:

```sql
id = auth.uid()
```

## Privacy Boundaries

The schema supports activity tracking without storing:

- Keystroke contents.
- Screenshots.
- Passwords.
- Clipboard contents.
- Private document contents.
- Full browser history.

Allowed tracking data is limited to active/idle state, durations, optional process name, optional window category, and task association.

## Time Honesty

Sessions include `data_honesty_source` so planned, timer-recorded, verified-active, manual, estimated-external, and corrected time remain distinguishable.
