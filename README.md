# DayVector

DayVector is a local-first execution, roadmap, activity-attribution, and
evidence-based coaching application for Windows and Android.

## Current baseline

This repository is the clean replacement for the ignored `old/` application.
It includes:

- Flutter phone, tablet, and Windows layouts.
- English, Arabic (RTL), and German presentation.
- Light, dark, and golden themes with their official logos.
- Drift/SQLite local storage and an idempotent synchronization outbox.
- Supabase Auth, PostgreSQL, RLS, Storage, and account-scoped Realtime.
- Local-first tasks, execution state, roadmaps, and activity review foundations.
- Notification sound selection, including system default and all supplied sounds.

The implementation roadmap is in [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md).

## Run

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

Android uses the application ID `pro.taskmaster.app` and the auth callback
`pro.taskmaster.app://auth-callback`.

Only the Supabase publishable key is present in the Flutter client. Never add a
secret or service-role key to this repository.
