# MVP Scope

The first build should stay focused on the spec's minimum viable product:

1. Secure login.
2. Tasks, projects, and categories.
3. Pomodoro timer.
4. Windows and Android synchronization.
5. Basic offline support.
6. Daily calendar history.
7. Manual progress and notes.
8. Windows idle detection.
9. Learning links.
10. Arabic, English, and German.
11. RTL and LTR support.
12. Local notifications.
13. Initial roadmap import.

Advanced AI scheduling, complex forecasting, full browser automation, remote push, and relationship analytics should wait until the foundation is reliable.

## Next Implementation Steps

1. Generate Flutter platform runners and run the analyzer.
2. Add a local offline queue for task/session writes.
3. Persist Pomodoro session summaries into `sessions` and `session_segments`.
4. Add Windows native idle detection with separate interactive/video/reading behavior.
5. Add local notifications after the exact Flutter SDK version is known.
6. Add Supabase RLS tests before production use.

