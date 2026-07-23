# TaskMaster Pro

A private Flutter app for Windows and Android that combines secure login, tasks, Pomodoro sessions, roadmap tracking, language direction support, and daily planning.

This repository contains the Flutter application, native Windows and Android runners, installer, local-first data layer, and ordered Supabase migrations.

## Current Capabilities

- Secure Supabase email/password login screen.
- Pre-login language selector for English, Arabic, and German.
- RTL app direction for Arabic and LTR direction for English/German.
- Supabase target settings for project URL and public publishable/anon key.
- Client-side rejection of service-role, `sb_secret`, database connection strings, and JWT signing secrets.
- Today dashboard focused on the next useful action.
- Task list with Today, Upcoming, List, Overdue, Waiting, Completed, and Review Required views.
- Quick-add task dialog.
- Pomodoro timer with presets, interruptions, session notes, unsuccessful marking, and tracking modes.
- Multi-roadmap planning with stable phase ordering and active-phase resolution.
- A retained multi-tab task browser with collapsed, split, and full modes.
- Local-first task, resource, reminder, activity, note, interruption, reading, and session changes.
- IANA time-zone scheduling with wall-clock recurrence intent and correct overdue boundaries.
- Reading tasks with local PDF/EPUB references and page-progress sessions.
- Optional break activity attribution without double-counting time.
- Android Health Connect summaries with granular permissions and an encrypted local cache.
- One-device-at-a-time active-session leases with explicit takeover.
- Row Level Security, ownership checks, idempotency fields, and synchronization indexes.

## Local Setup

1. Install Flutter and add it to `PATH`.
2. Fetch packages:

   ```powershell
   flutter pub get
   ```

3. Link Supabase:

   ```powershell
   supabase login
   supabase link --project-ref yilegxcnokndozhwpwlf
   supabase db push
   ```

4. Run the app:

   ```powershell
   flutter run -d windows
   ```

5. Open Settings in the app and enter only:

   - Supabase project URL.
   - Public publishable or anon key.

Do not store database passwords, service-role keys, JWT secrets, or `sb_secret` values in the app.

## Build Release Files

Run:

```powershell
npm run package:release
```

This builds and verifies the app, then writes the installable files to `release/`:

- `TaskMasterPro-windows-x64-setup.exe`
- `TaskMasterPro-android-release.apk`

## Password Recovery Redirect

Forgot Password and email confirmation use Supabase Auth with this callback URI:

```text
taskmasterpro://auth/callback
```

The URI is registered in Android through the manifest and in Windows by the installer under the current user's `taskmasterpro://` protocol handler. The same exact URI, plus `taskmasterpro://auth/**`, must also be present in Supabase Authentication Redirect URLs for the hosted project.

## Verification Status

The local release command runs `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build windows --release`, `flutter build apk --release`, and Inno Setup packaging. Supabase CLI is installed, but migrations are not pushed automatically because that would change your live database.

## Useful Files

- Flutter entrypoint: `lib/main.dart`
- App configuration: `lib/core/config/`
- Auth: `lib/features/auth/presentation/`
- Dashboard: `lib/features/dashboard/presentation/`
- Tasks: `lib/features/tasks/`
- Pomodoro: `lib/features/pomodoro/`
- Latest Supabase migration: `supabase/migrations/20260717190000_workspace_reading_timezone_health_offline.sql`
- Supabase upgrade guide: `docs/SUPABASE_UPGRADE.md`
- Security notes: `docs/SECURITY.md`
