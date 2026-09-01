# DayVector 0.0.29 — Updates and features

DayVector 0.0.29 brings the new DayVector identity to the complete experience while preserving existing accounts, tasks, progress, schedules, and local data.

## DayVector identity

- New DayVector name and approved logo across Windows, Android, the home-screen widget, notifications, reports, splash screens, installers, and the website.
- Updated app icons, tray icon, notification icon, favicons, social sharing artwork, product metadata, and release information.
- Cleaner in-app logo rendering at compact sizes, using the purpose-made assets from the approved branding package.

## Faster cross-device updates

- Starting a task now publishes its running state immediately, so another signed-in device can show the same task without waiting for a later pause or resume.
- Start, pause, resume, break, finish, and Pomodoro changes use the same authoritative account state across Windows and Android.
- Realtime updates restore the latest task timer after a change arrives, without continuous background polling; bursts of unrelated updates can no longer keep postponing a task-state refresh.
- Returning to DayVector after Android suspended it performs one bounded catch-up, so a task started while the phone was asleep appears automatically.
- Roadmap progress and forecast snapshots are rebuilt locally from synchronized source data instead of competing for the roadmap revision; stale projection commands are retired automatically.
- If another device has already committed every field in a task update, DayVector proves the canonical match and clears the redundant command without asking the user to resolve a false conflict.
- Synchronization diagnostics distinguish temporary connection problems from changes that genuinely need attention.

## Planned rest inside a task

- A task can now include optional planned rest, such as a 30-minute lunch during a work block.
- Planned rest is stored with the task and synchronized through the existing task history rather than a separate fragile record.
- Work estimates, roadmap effort, recurrence, and calendar occupancy keep working time and planned rest clearly separated.

## Android widget and notification controls

- Widget and notification buttons perform their actions directly without opening the full application.
- The widget reads the same session, phase, and timing authority as the app, preventing an old task or timer from continuing on the home screen.
- Responsive widget sizes show the running task and useful controls, or suitable suggestions when no task is active.
- The idle widget reports the real number of available tasks while keeping its compact preview limited to the three best suggestions.
- Focus, pause, resume, break, extend-break, continue, and finish controls use guarded actions so a stale button cannot complete the wrong task.

## Breaks, activity, and coaching

- After an inactive break, the user can optionally record reading, exercise, relaxation, a drink, or another activity.
- Useful break activity can be linked to an existing task without counting the same time twice.
- Coaching can recognize exercise and other constructive recovery activity and respond with appropriate encouragement.
- Coaching now keeps several useful suggestions available at once, rotates them in a calm carousel, and can surface the current recommendations in notifications.
- Marking one suggestion as too frequent only reduces similar advice; it no longer silences unrelated coaching.
- Activity review totals, cross-task counts, and attention cards now use the same filters and classifications.

## Health and recovery

- Health Connect presents steps, distance, energy, heart rate, sleep, workouts, weekly movement, and connected sources in a clearer responsive layout.
- Exercise sessions are now read from their canonical Health Connect records even when optional calorie, distance, or step enrichment is unavailable, so workouts shared by Nothing X and other providers no longer disappear.
- If there is no workout today, the health card shows the recent seven-day workout total instead of hiding valid exercise behind a dash; Windows receives the same weekly total from synchronized daily summaries.
- Sleep summaries can be read when the source application has shared the supported records through Health Connect.
- Phone health summaries can provide read-only planning context on Windows while detailed records remain on Android.
- The Windows Health sidebar button now opens the synchronized read-only Health and rest dashboard directly, rather than showing Android-only connection controls.
- Pull-to-refresh, connected-source details, and watch capability messages are designed for a modern phone interface.
- Health values use friendly rounding and practical units instead of long raw decimals.
- Legacy health summaries with inconsistent evidence counters are repaired automatically and uploaded once with valid counters instead of remaining as repeated synchronization errors.
- Health source names remain readable in reports and synchronized cards while internal Android package identifiers stay hidden.

## Windows navigation and layout

- Health is now available directly from the Windows sidebar.
- The sidebar can collapse to a compact icon rail and expand again with the edge control or Ctrl+B.
- Ctrl+B follows the physical B key, so the shortcut remains reliable with Arabic, German, and other keyboard layouts.
- Compact navigation keeps profile, active-task, Pomodoro, and synchronization access without crowding the workspace.
- Task controls, health cards, coaching cards, spacing, and responsive sizing have been refined across desktop widths.
- DayVector now permits only one Windows instance; launching it again restores and focuses the already-running window.
- Overdue tasks are derived from their due time or planned end and remain visible even when older synchronized records have not yet stored the newer status explicitly.

## Notifications and reliability

- Session and Pomodoro notifications use the active task state and retire superseded controls safely.
- Notification actions no longer rely on opening the app before applying a supported command.
- Account creation and branded authentication templates use DayVector wording and visual identity.
- Application-resource links, task completion timing, activity classifications, and stale runtime cleanup now follow guarded synchronization paths to avoid recurring conflict entries.

## Website

- The official site uses the DayVector identity, updated app interface previews, and release metadata for version 0.0.29.
- English, German, and Arabic navigation and page direction have been refined.
- Light and dark themes, mobile menus, responsive spacing, health information, the Android widget, and the free browser Pomodoro are presented in user-friendly language.
- Search, sharing, sitemap, manifest, and page metadata now describe DayVector consistently.
