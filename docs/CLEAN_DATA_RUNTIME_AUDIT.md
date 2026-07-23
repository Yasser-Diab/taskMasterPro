# TaskMaster Pro clean data/runtime refactor audit

Date: 2026-07-23

Branch: `refactor/clean-data-runtime`

Baseline tag: `before-clean-runtime-refactor`

Commit frozen before refactor: `255e8ae` (`Initial TaskMaster Pro baseline`)

Remote note: this repository has no `origin` remote configured, so the local tag cannot be pushed until a remote is added.

## Scope

This audit is the Stage 1 gate for replacing the broken data architecture without replacing the whole TaskMaster Pro app. The existing app is a Flutter Windows/Android application with Supabase, native Android Health Connect/notification/widget code, native Windows tray/window/WebView2 code, localized UI, branded media assets, and an Inno Setup installer.

The production branch has not been modified. All follow-up refactor work must stay on `refactor/clean-data-runtime`.

## Repository inventory

- Flutter app: `lib/main.dart`, `lib/app/*`, `lib/core/*`, `lib/features/*`
- Platforms: `android/`, `windows/`
- Branding/media: `media/app-logo/*`, `media/notifications-sound/*`, Android launcher/notification assets, Windows icon
- Release setup: `scripts/package-release.ps1`, `installer/TaskMasterPro.iss`
- Supabase: old incremental migrations in `supabase/migrations/*`
- Tests: `test/core_productivity_regression_test.dart`, `test/supabase_key_guard_test.dart`
- Duplicate export folders: `github-ready/`, `github-ready-push/` are untracked and should not be treated as source of truth

## Keep

These systems are real application assets and should remain unless a later implementation detail proves otherwise.

- Branding and logo
  - `lib/core/theme/app_brand.dart` defines `TaskMaster Pro`, app logo paths, auth callback scheme, and support URLs.
  - `media/app-logo/*`, `windows/runner/resources/app_icon.ico`, and Android launcher assets preserve the recognizable product identity.
- Theme and color system
  - `lib/core/theme/app_theme.dart` has the existing light, dark blue, and black/gold theme choices, app color extensions, buttons, cards, inputs, navigation rail styling, and typography.
- Main navigation shape
  - `lib/features/dashboard/presentation/home_shell.dart` keeps the familiar routes: Dashboard, Tasks, Pomodoro, History, Roadmap, Settings.
  - The navigation structure should be repaired for responsive breakpoints, not replaced with a new app shell.
- Authentication UI and deep links
  - `lib/features/auth/presentation/login_screen.dart`, `auth_gate.dart`, `create_new_password_screen.dart`, and `lib/core/deep_links/deep_link_service.dart` are usable UI/flow foundations.
  - The storage/startup behavior behind them must change, but the visible login experience should stay.
- Task screens and workspace shell
  - `lib/features/tasks/presentation/task_list_screen.dart`, `task_editor_dialog.dart`, `task_workspace_screen.dart`, and supporting task UI have a useful interface surface.
  - They should be repaired and reconnected to the clean task/domain/runtime model.
- Browser WebView foundation
  - `lib/features/tasks/presentation/task_browser_workspace.dart` already has native browser hosting, tabs, rename, duplicate, reopen closed, bookmarks-as-resources hooks, search parsing, title events, local profile IDs, and local tab persistence.
  - Android `MainActivity.kt` and Windows `flutter_window.cpp` provide real WebView/WebView2 host implementations and per-profile local browser data folders.
- Notification and sound assets
  - `media/notifications-sound/*` and Android raw notification sounds exist.
  - `android/app/src/main/kotlin/.../TaskReminderReceiver.kt`, `ActiveSessionService.kt`, and Windows reminder/tray notification code are useful native foundations.
- Health Connect native foundation
  - Android `MainActivity.kt` requests Health Connect permissions and reads steps, exercise, distance, heart rate, sleep, active calories, and actual data origins.
  - The Dart sync/storage/provider pipeline must be rebuilt, but the native Health Connect access should be kept.
- Windows app runtime
  - `windows/runner/flutter_window.cpp` has tray commands, deep links, click sounds, foreground app sampling, reminder scheduling, WebView2 hosting, browser detach/dock, profile folders, and window state file support.
- Android packaging, widgets, and services
  - `android/app/src/main/*` includes manifest/resources, widgets, foreground active-session service, reminder receiver, and Health Connect rationale activity.
- Localization resources
  - `lib/core/localization/app_localizations.dart` contains en/ar/de localization and should remain as the localization source.
  - Problem strings and hard-coded personal/domain-specific options must be removed or made data-driven.
- Build/release setup
  - `pubspec.yaml`, Android Gradle setup, Windows CMake runner, `scripts/package-release.ps1`, and `installer/TaskMasterPro.iss` should remain.

## Repair

These systems are structurally useful but currently have bugs, wrong assumptions, or incomplete behavior.

- Responsive layout
  - `HomeShell` uses a single `>= 860` wide breakpoint instead of the required Compact `< 760`, Medium `760-1199`, Expanded `>= 1200` modes.
  - `task_workspace_screen.dart`, `today_dashboard_screen.dart`, `settings_screen.dart`, and roadmap dialogs use mixed fixed widths/heights and ad hoc breakpoints (`600`, `620`, `700`, `720`, `840`, `920`, `980`) that can cause broken compact layouts.
- Window restoration and platform settings
  - Windows native code saves/restores `window_state.txt`, but device settings are mixed with remote platform settings and not represented by the requested `device_settings` table.
  - `AppLifecycleService.applyWindowPreferences` only sends `restoreGeometry` and `restoreMaximized`, not the full device-specific settings model.
- Browser metadata and tab behavior
  - Browser implementation is usable but defaults through `about:blank`, still uses `New tab` fallback titles, and stores browser JSON under `TaskMaster Pro/BrowserState` separate from the app's other `TaskMasterPro` paths.
  - Default start page must become Google, title inheritance must be reliable, and persistence must move to the clean local browser/resource model.
- Notification popup and scheduler
  - `AppNotificationService` and `app_notifications.dart` provide in-app banners, while `TaskReminderScheduler` calls native Windows/Android channels.
  - Scheduling must be reconnected to clean reminders/settings/runtime state and repaired so dead controls and modal barriers are removed.
- Timer display widgets
  - `TaskActionController` already uses timestamp-derived active clock updates and saves recovery checkpoints every 10 seconds.
  - It still depends on old session tables, old command RPC shape, and local controller authority, so widgets should be kept only after runtime replacement.
- Activity list/accounting UI
  - `SessionSegmentType.externalResource.countsAsActive` is correct in principle.
  - The UI still separates task-master/browser/external app data in ways that can make active external work look like non-work. Replace aggregation math, then repair formatting.
- Health settings UI
  - Settings screen exposes Health Connect status, permissions, diagnostics, and summaries.
  - It must hide fake Huawei status unless actual Huawei records or a direct integration exists, and it must use incremental records/summaries instead of reading/syncing summaries on settings open.
- Auth startup
  - Login/deep-link UI is good, but session persistence currently writes `auth_session.json` as JSON and recovers it directly.
  - Replace storage with Android Keystore/Windows protected credentials and repair startup so cached local app state renders before online refresh.
- Settings layout and synchronization
  - `AppConfig`, `AppSettingsStore`, and settings screen contain useful controls.
  - Persistence/sync must move from JSON plus `common_settings`/`windows_settings`/`android_settings` to `user_settings` and `device_settings`.
- Roadmap screens
  - The existing roadmap screen has useful phase editing, phase order, tabs, and summary UI.
  - It must be redesigned in place around explainable progress, milestones/checkpoints/linked tasks/focused time/contributions, and strict roadmap-phase-task relationships.
- Calendar/history formatting
  - Date formatting generally goes through localization/time-zone helpers, but some roadmap/history paths call `toLocal()` directly.
  - Any UI relying on raw UTC or system-local timestamps must be repaired to use user time-zone behavior.

## Replace

These systems are internally broken enough that rebuilding them behind the existing UI is cleaner and safer than incremental patching.

- Supabase schema and migrations
  - Old migrations are a layered history from `20260716170000_initial_foundation.sql` through `20260720093000_v012_widget_command_events.sql`.
  - They include old tables, old defaults, old owner-specific data, trigger-disabling workarounds, and migration-time failures caused by `auth.uid()`.
  - Replace with one clean baseline migration: `supabase/migrations/20260723000000_taskmaster_clean_baseline.sql`.
- Local database and outbox
  - `TaskLocalStore` is a per-user JSON file (`tasks-local.json`) with an `operations` array.
  - It is not a typed local database, has no durable relational constraints, and has no full conflict/outbox model.
  - Replace with a typed local database and `sync_outbox` matching the requested mutation states.
- Task type/domain architecture
  - `TaskItem` mixes task domain, execution mode, legacy `task_type`, category names, roadmap fields, recurrence template fields, and UTC/local scheduling fields.
  - `TaskCategory` hard-codes category templates.
  - Replace with customizable `task_domains` plus explicit `execution_mode`, task status/priority, planned local date/minutes, UTC instants, recurrence series, and progress method.
- Task-roadmap relationships
  - Current tasks can reference `roadmap_id`, `roadmap_phase_id`, `roadmap_phase`, and `milestone_id`.
  - Roadmap logic falls back from phase IDs to phase numbers, so tasks can remain loosely attached or appear under wrong phases.
  - Replace with strict `tasks.roadmap_id -> roadmaps.id` and `tasks.phase_id -> roadmap_phases.id` plus a relationship validator that does not depend on `auth.uid()`.
- Roadmap progress service
  - Current progress is calculated from weighted task estimated minutes and `task.progressPercentage`, or phase completed task counts.
  - This can produce misleading progress and cannot explain milestones/checkpoints/focused time/practice/reading/manual components.
  - Replace with an explainable progress service and clean schema for roadmaps, phases, milestones, and checkpoints.
- Task occurrences and recurrence
  - Current recurrence uses old template fields/RPC generation and scheduled UTC/local fields.
  - Replace with stable `task_occurrences` and a unique `occurrence_key` to prevent duplicate recurring tasks during sync.
- Session runtime controller
  - `TaskActionController` currently owns runtime authority locally and publishes old session events/commands.
  - Replace the runtime core with authoritative timestamp state, local checkpoints, session/segment persistence, and a shared server RPC.
- Pomodoro state machine
  - The task workspace has some correct waiting states, but the standalone `PomodoroController` decrements `_remainingSeconds` every second and duplicates runtime concepts.
  - Replace the runtime source of truth with the required user-controlled states: focus_ready, focus_running, focus_paused, focus_completed_waiting, break_ready, break_running, break_paused, break_completed_waiting, task_completed, cancelled.
- Multi-device synchronization
  - Current sync uses `sync_events`, duplicate subscriptions, local refreshes, old `session_commands`, and stubbed/no-op session control.
  - Replace with one private user runtime channel, transactional `apply_session_command(...)`, revision checks, command dedupe, and authoritative session snapshots.
- Offline sync and conflict handling
  - Current operations replay is best-effort and table-specific.
  - Replace with stable IDs, revision/base_revision, changed_fields, tombstones, append-only merge behavior, and same-field conflict review.
- Activity contributions and aggregation
  - Current `break_contributions` and task activity records are too narrow and can double-count.
  - Replace with `activity_contributions` and an aggregation service where total session time, active work, idle, context breakdown, and external app work follow the requested definitions.
- Work demands and learning checkpoints
  - Existing `work_demands` and `learning_checkpoints` are old-model tables/repositories.
  - Replace with requested `task_demands` and `task_checkpoints` semantics and recurrence rollover rules.
- Resource/attachment system
  - Current task resources and workspace config are static/legacy.
  - Replace with `task_resources` and `resource_device_locations`, including browser bookmarks and PDF/book state.
- Health data pipeline
  - Dart currently writes summary pseudo-records into old `health_records` and `health_connections`.
  - Replace with `health_connections`, `health_records`, and `health_daily_summaries` using cursors/incremental sync and real source detection.
- Coaching pipeline
  - Any static coaching must be replaced with `user_behavior_features` and `coaching_recommendations` based on current user behavior, evidence count, confidence, and suggested action.
- User settings, cycle data, and device settings sync
  - Replace old `common_settings`, `android_settings`, `windows_settings`, local cycle JSON, and profile booleans with clean `user_settings`, `device_settings`, and synchronized cycle data.

## Remove

These should be deleted or made unreachable during the refactor.

- Old database migration assumptions
  - Remove reliance on the old migration chain and old tables such as `categories`, `projects`, `roadmap_items`, old `sessions`, old `session_segments`, `sync_events`, `common_settings`, `windows_settings`, `android_settings`, and old recurrence functions.
- Migration-time auth/trigger workarounds
  - Remove migrations/functions that require `auth.uid()` inside integrity logic or disable user triggers to get admin migrations through SQL Editor.
  - Integrity functions should validate row relationships. RLS policies should validate authenticated clients.
- Hard-coded German/personal data
  - Remove seeded German categories/resources/pomodoro presets and owner-specific roadmap/task data from migrations.
  - Remove `breakUse_german` and any German-only runtime choices from task/break architecture.
- Fake health provider states
  - Remove Huawei provider UI/state unless real Health Connect origins identify Huawei or a direct Huawei integration is implemented.
- Duplicate timer controllers
  - Remove standalone decrementing `PomodoroController` as runtime authority.
  - Keep only a UI adapter if needed while all timing comes from the new session runtime.
- Placeholder Take-control/control flows
  - Remove `SessionControlClaim`, `SessionControlledElsewhere`, `blockedSessionClaim`, `blockedSessionTask`, `_SessionControlConflictBanner`, old `active_session_leases`, and any "Take control" UX.
  - All devices must render the same shared runtime state.
- Obsolete sync code and duplicate subscriptions
  - Remove direct `sync_events` publish/subscribe paths from `TaskMasterApp` and `TaskActionController`.
  - Replace with typed outbox upload and Realtime broadcasts on the requested private user runtime channel.
- Dead notification controls and gray placeholder panels
  - Remove controls that do not schedule real native notifications or only display diagnostic placeholders.
  - Remove fixed-height gray placeholders and orphaned modal barriers during UI hardening.
- Raw UTC display
  - Remove UI paths that format UTC/system-local dates without the app time-zone service or planned local date/minute model.
- Duplicate export folders
  - `github-ready/` and `github-ready-push/` are untracked duplicate exports and should remain outside source control or be deleted only after confirming they contain no user-only files.

## Required implementation gates

1. Do not create or connect the clean Supabase baseline until this audit exists.
2. The clean database must be a zero-baseline migration, not old migrations in filename order.
3. Database relationship validation must not depend on `auth.uid()`.
4. The local database must become the UI source of truth before claiming offline support.
5. Timer success requires installed Windows and Android builds showing the same session/stage, not just a successful migration.
6. Health success requires real Health Connect reads and real detected sources, not provider labels.
7. Browser success requires persistent tabs/title/rename/bookmark state across task occurrences without syncing cookies or login tokens.
8. UI success requires compact, medium, and expanded viewport checks with no gray infinite surfaces, broken overlays, or leaking text.

## Next stage

After this audit is committed, Stage 2 can begin:

- Create `supabase/migrations/20260723000000_taskmaster_clean_baseline.sql`.
- Do not copy the old migrations.
- Add clean RLS, storage/realtime setup, relationship validators, `apply_session_command(...)`, and all requested tables.
- Prepare local database replacement design and repository adapter plan before wiring app calls to the new schema.
