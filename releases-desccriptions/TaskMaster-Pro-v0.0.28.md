# TaskMaster Pro 0.0.28 — What’s New

## Synchronization and reliability

- Rebuilt synchronization around revisioned, idempotent commands so an older device update cannot restore a superseded task, focus or break state.
- Added durable command sequencing and canonical reconciliation for task execution, completion, recurrence, roadmaps, activity review and settings.
- Added automatic recovery for legacy malformed commands instead of repeatedly asking the user to retry permanent server rejections.
- Resolved the legacy `execution_runtime_start_cleanup/retire` conflicts without deleting valid work or the active task.
- Resolved missing-entity activity classifications by recreating the required activity segment and safely superseding the obsolete command.
- Added an atomic server command for extending a running break so the duration and runtime revision change together.
- Restricted automatic retries to temporary connection failures; permanent conflicts now receive a durable accepted, superseded or attention decision.
- Added guarded stale-paused-session recovery while protecting sessions that contain real recorded work.
- Reduced repeated full-table downloads through bounded change-log synchronization, high-water marks and targeted recovery reads.
- Consolidated Realtime into one account connection, one account channel and one registered event handler, with duplicate-handler diagnostics.
- Added accurate synchronization diagnostics for connection state, command counts, duplicate handlers, traffic, repeated requests and largest transfers.
- Corrected the synchronization panel so “waiting” and “needs attention” represent the real durable outbox rather than stale UI counters.
- Improved account-device authorization, revoked-device recovery and per-device identity so an obsolete installation cannot silently revive its old state.
- Preserved signed-in local profiles during temporary account-preparation failures instead of incorrectly returning existing users to onboarding.
- Kept local work available offline and reconciled it forward after reconnection rather than blindly rolling optimistic state backward.
- Prevented device-only Health source timestamps from being uploaded as shared records, removing the revision loop that could create hundreds of false “changes needing attention” entries.
- Added bounded automatic convergence for older revision conflicts so already-equivalent Health summaries settle without asking the user to review the same records one by one.
- Corrected task-to-application resource permissions and delete handling so adding an Android application to a task no longer creates permanent `permission_denied` synchronization errors.
- Corrected completed runtime projections so valid completion commands no longer fail with `invalid_projected_active_ms`.

## Pomodoro and task execution

- Unified Dashboard, task workspace, notifications and widgets behind the same canonical execution commands.
- Rebuilt focus, paused, waiting, break, continuous, overtime and completed transitions around one authoritative runtime state.
- Fixed focus sessions that could incorrectly start from remaining break time instead of the configured focus duration.
- Fixed break extension, break skipping, starting focus early, pause, resume and finish actions that previously appeared to work and then reverted.
- Added cross-device pause/resume convergence and exact offline recovery of the current session after reconnecting.
- Made task completion, undo and reopen ordered canonical operations so an immediate follow-up action cannot overtake the completion it depends on.
- Cancelled or superseded obsolete execution state when a task finishes, changes phase or is handled on another device.
- Corrected countdown-to-overtime behavior so overtime visibly continues instead of freezing the primary timer at `00:00`.
- Normalized long durations throughout the app into readable hours and minutes instead of oversized minute totals.
- Prevented stopped and paused sessions from accumulating hidden work time.
- Added optional post-break activity check-ins when no meaningful device activity was detected.
- Added quick break choices for reading, exercise or sport, relaxing, a drink or snack, and a custom activity.
- Added optional linking of a break activity to an existing task when it should contribute to that task.
- Suppressed the break check-in when real device activity explains the interval, while still allowing it for genuine technical idle periods.
- Added sport-aware coaching context so recorded exercise can produce relevant encouragement without exposing private raw activity.

## Android home-screen widget

- Added a native responsive TaskMaster Pro Android widget with compact, medium and expanded layouts.
- Added live focus and break countdowns that remain visible on the home screen.
- Added direct running-session controls for **Pause**, **Break** and **Finish**.
- Added paused-session controls for **Continue** and **Finish**.
- Added break controls for **Focus**, **+5 min** and **Review**.
- Added an idle state with useful task suggestions when no session is running.
- Validated widget actions against the current task, session and runtime revision before executing them.
- Routed widget actions through the same canonical command path used by the application, preventing widget-only state drift.
- Added attractive focus, paused, break and idle visual states that respond to the widget size selected by the user.

## Notifications and alarms

- Consolidated scheduling behind one notification authority and a revision-aware notification ledger.
- Revalidated every alarm against the current occurrence, session, interval and revision before displaying it.
- Cancelled stale alarms immediately after pause, resume, break changes, completion, undo, deletion or a newer cross-device action.
- Prevented completed tasks and superseded intervals from producing old ending notifications later.
- Fixed a Windows race where a quiet status refresh could replace an already delivered Pomodoro boundary notification.
- Connected notification actions to the same execution commands as the main app instead of maintaining a separate notification-only implementation.
- Added reliable actions for continuing, pausing, starting or reviewing a break, finishing focus and finishing the task.
- Limited system notification cards to compact, readable action sets with short labels and no word-by-word button wrapping.
- Improved Android notification layout, monochrome icon handling, dark/light presentation and action sizing.
- Restored bundled Android alarm sounds that had been stripped from release builds.
- Fixed notification sound previews so **Stop preview** stops playback and errors no longer crash the settings screen.
- Added per-category sound, vibration and system-channel controls with in-app test notifications.
- Added Windows sound mapping, including alarm-style delivery and a real silent option.
- Improved notification deep links so tapping a notification opens the relevant TaskMaster Pro screen.

## Activity review and attribution

- Preserved individual activity periods while presenting useful grouped views for related, break, cross-task, inactive and system activity.
- Corrected Dashboard attention cards and Activity filters so their counts and opened results use the same source of truth.
- Removed contradictory states such as a large inactive-review count opening a list with zero matching items.
- Added durable activity classifications that remain consistent across devices.
- Added cross-task contribution handling so useful activity can support the task it actually belongs to without duplicating the same physical minute.
- Added root-domain normalization so pages and subdomains from the same site can reuse the intended task relationship.
- Normalized application and website identities for readable reports instead of exposing package identifiers as display names.
- Excluded TaskMaster Pro itself and learned system activity from productive time, coaching, roadmap progress and forecasts.
- Kept uncertain and idle-looking periods reviewable without uploading private raw window titles or browsing content.
- Improved remembered application and website rules while allowing one resource to support more than one task.

## Reports, roadmaps and coaching

- Expanded reports with clearer task history, activity breakdowns, charts, percentages and normalized application names.
- Connected displayed report metrics to the exact underlying sessions and activity records.
- Corrected corrupted or continuously growing duration totals in task history and roadmap progress.
- Improved roadmap progress, phase forecasts, checkpoints, planned effort and schedule-risk explanations.
- Added evidence counts and confidence levels so coaching and forecasts explain what they are based on.
- Improved coach guidance using verified execution patterns, interruptions, recovery, breaks and approved activity.
- Added sport and recovery awareness to coaching while keeping raw private activity local.
- Added vacation-aware scheduling and safer forecast adjustment around unavailable periods.
- Preserved task, roadmap, recurrence and resource relationships through synchronization repairs.

## Browser, resources and credentials

- Improved task-resource launching so the task is committed locally before handing off to a website, document or external application.
- Kept the canonical timer running when TaskMaster Pro hands work to another application.
- Added a distraction-reduced browser surface with a compact live task bar for timer status and execution controls.
- Improved browser workspace persistence for tabs, navigation state, bookmarks and the last visited location.
- Added durable task-level website resources and normalized matching for deeper pages on the same site.
- Improved the credential-vault flow with a simpler privacy-password setup, recovery path and exact-host credential selection.
- Added secure Android biometric unlock support where the device and user configuration allow it.
- Prevented credential handling from automatically submitting forms or exposing secret values to diagnostics.

## Health and wellbeing

- Improved health-source discovery so the app presents actual contributing health applications and connected wearable sources rather than a generic Bluetooth-device list.
- Preserved source application and last-updated evidence from imported health records.
- Added overlap and duplicate prevention so the same physical health interval is not counted more than once across providers.
- Added per-day health summaries that can support appropriate workload and recovery guidance.
- Kept health permissions explicit and avoided claiming historical data from a device that has not provided records.
- Rebuilt Health and rest as a modern daily dashboard on both Android and Windows, with readable summary cards, a seven-day movement chart and a calm source status panel.
- Rounded heart rate, distance, calories and other measurements into useful human-readable values instead of exposing raw floating-point data.
- Grouped synchronized Windows measurements by the freshest record for each metric and date so duplicate providers do not produce duplicate cards.
- Added swipe-to-refresh on phones, with a simple **Data received** confirmation only after fresh records arrive.
- Placed Health directly before Settings in the phone navigation and made the navigation horizontally scrollable instead of squeezing its destinations.
- Consolidated Health Connect applications and connected watches into one Health sources panel, showing only relevant paired wearable sources.
- Fixed the Flutter PageStorage key collision that turned the lower Health screen into an endlessly scrolling grey error panel after the sources card was opened or revisited.
- Read complete Health Connect sleep sessions together with light, deep, REM, awake, out-of-bed and unknown stages, then normalize overlapping stage records into one accurate sleep total without double-counting.

## Interface, accessibility and localization

- Improved responsive layouts across narrow Android phones, tablets, resizable Windows windows and maximized desktop use.
- Corrected clipped controls, excessive gaps, button wrapping and inconsistent card sizing across task, activity, notification and synchronization screens.
- Improved the focus timer with a clear shrinking progress ring, subtle holographic motion and distinct focus, paused, break and waiting presentation.
- Added reduced-motion handling so decorative animation can stop without affecting timer behavior.
- Improved Arabic right-to-left and German layouts, including compact labels that remain readable in constrained system UI.
- Removed duplicated settings and simplified profile presentation and edit affordances.
- Improved offline, connection and synchronization status language so the app reports actionable state without alarming the user during normal recovery.
- Added TaskMaster Pro-branded confirmation, recovery, magic-link, invitation, email-change and reauthentication templates with matching branded subjects for the production authentication service.
- Standardized Dashboard task-control heights and spacing across Windows and narrow layouts.
- Replaced the oversized coaching recommendation presentation with a calmer, compact card that keeps the useful suggestion and evidence prominent.
- Replaced technical execution explanations with a small collapsed information control that opens friendly Pomodoro or working-style guidance only when requested.

## Privacy and data protection

- Isolated the current application and local cache from the retired backend project and preserved legacy data without modifying it.
- Added account-scoped local databases, outboxes, browser workspaces and learned rules.
- Added privacy-safe evidence summaries for coaching and cross-task attribution instead of transmitting raw private activity.
- Protected tombstoned records from stale offline updates and prevented revoked installations from restoring deleted data.
- Kept accepted command history immutable while recording conflict decisions as durable, idempotent operations.

## Background controls

- Widget controls now execute through an explicit headless Android service without opening or foregrounding the app.
- Notification mutation buttons now execute through the same headless command path; only navigation actions such as Open foreground the app.
- Every widget PendingIntent is uniquely identified by account, action, task, session, and runtime revision, preventing Continue from being reused as Finish.
- Background Pause, Continue, Start break, Start focus, Extend break, Continue working, Finish, reminder Start, Complete, and Snooze actions revalidate canonical local state before mutation.
- Completing a break in the background preserves the optional no-device-activity check-in and posts a separate review prompt instead of discarding it.
- The Android widget and current execution notifications refresh from the accepted canonical state after a background action.

## Release identity correction

- All current package, installer, tray, Settings, release-note, and Android version metadata is restored to TaskMaster Pro 0.0.28.
- The corrected release uses build number 54 so it upgrades the incorrectly labeled 0.0.30+53 installation without changing the intended public version.
