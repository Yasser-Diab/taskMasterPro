import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/domain/pomodoro_execution_state.dart';

void main() {
  test('live planned effort changes visibly from countdown to overtime', () {
    final startedAt = DateTime.utc(2026, 7, 28, 19, 30);

    final recordedMs = liveTaskRecordedWorkMs(
      recordedMs: const Duration(minutes: 5).inMilliseconds,
      running: true,
      segmentStartedAt: startedAt,
      now: startedAt.add(const Duration(minutes: 10, seconds: 1)),
    );
    final remainingMs = taskEffortRemainingMs(
      plannedMs: const Duration(minutes: 40).inMilliseconds,
      recordedMs: recordedMs,
    );

    expect(recordedMs, const Duration(minutes: 15, seconds: 1).inMilliseconds);
    expect(formatTaskEffortCountdown(remainingMs), '00:24:59');
    expect(
      formatTaskEffortCountdown(
        taskEffortRemainingMs(
          plannedMs: const Duration(minutes: 40).inMilliseconds,
          recordedMs: const Duration(hours: 1).inMilliseconds,
        ),
      ),
      '00:00:00',
    );
    expect(
      formatTaskEffortOvertime(
        taskEffortOvertimeMs(
          plannedMs: const Duration(minutes: 40).inMilliseconds,
          recordedMs: const Duration(hours: 1).inMilliseconds,
        ),
      ),
      '+00:20:00',
    );
  });

  test('a future or paused live segment never corrupts recorded work', () {
    final now = DateTime.utc(2026, 7, 28, 19, 30);

    expect(
      liveTaskRecordedWorkMs(
        recordedMs: const Duration(minutes: 5).inMilliseconds,
        running: true,
        segmentStartedAt: now.add(const Duration(minutes: 1)),
        now: now,
      ),
      const Duration(minutes: 5).inMilliseconds,
    );
    expect(
      liveTaskRecordedWorkMs(
        recordedMs: const Duration(minutes: 5).inMilliseconds,
        running: false,
        segmentStartedAt: now.subtract(const Duration(hours: 1)),
        now: now,
      ),
      const Duration(minutes: 5).inMilliseconds,
    );
  });

  test('paused, break, and cleared task clocks never add wall time to work', () {
    final now = DateTime.utc(2026, 8, 20, 9);
    const focusMs = 25 * 60 * 1000;
    const recordedBeforePauseMs = 14 * 60 * 1000;

    LocalRuntime runtime({
      required String state,
      required DateTime segmentStartedAt,
      required int accumulatedActiveMs,
      required int focusBaseMs,
      required int completedFocuses,
    }) {
      return LocalRuntime(
        id: 'active',
        userId: 'user-1',
        activeTaskId: 'task-1',
        sessionId: 'session-1',
        state: state,
        segmentStartedAt: segmentStartedAt,
        accumulatedActiveMs: accumulatedActiveMs,
        accumulatedPausedMs: 0,
        dataJson: jsonEncode({
          pomodoroFocusIntervalBaseKey: focusBaseMs,
          pomodoroCompletedFocusesKey: completedFocuses,
        }),
        revision: 1,
        updatedAt: now,
      );
    }

    final paused = runtime(
      state: 'paused',
      segmentStartedAt: now.subtract(const Duration(hours: 62)),
      accumulatedActiveMs: recordedBeforePauseMs,
      focusBaseMs: 0,
      completedFocuses: 0,
    );
    final pausedNow = PomodoroExecutionSnapshot.fromConfiguration(
      runtime: paused,
      now: now,
      configuration: const {'pomodoro_focus_ms': focusMs},
      plannedMs: const Duration(hours: 8, minutes: 30).inMilliseconds,
    );
    final pausedMuchLater = PomodoroExecutionSnapshot.fromConfiguration(
      runtime: paused,
      now: now.add(const Duration(hours: 62)),
      configuration: const {'pomodoro_focus_ms': focusMs},
      plannedMs: const Duration(hours: 8, minutes: 30).inMilliseconds,
    );

    expect(pausedMuchLater.focusedMs, pausedNow.focusedMs);
    expect(pausedMuchLater.remainingMs, pausedNow.remainingMs);
    expect(pausedMuchLater.focusedMs, recordedBeforePauseMs);
    expect(
      liveTaskRecordedWorkMs(
        recordedMs: recordedBeforePauseMs,
        running: false,
        segmentStartedAt: paused.segmentStartedAt,
        now: now.add(const Duration(hours: 62)),
      ),
      recordedBeforePauseMs,
      reason:
          'Paused and completed/cleared runtimes must render only persisted work.',
    );

    final onBreak = runtime(
      state: 'break',
      segmentStartedAt: now,
      accumulatedActiveMs: focusMs,
      focusBaseMs: focusMs,
      completedFocuses: 1,
    );
    final breakStart = PomodoroExecutionSnapshot.fromConfiguration(
      runtime: onBreak,
      now: now,
      configuration: const {
        'pomodoro_focus_ms': focusMs,
        'short_break_ms': 5 * 60 * 1000,
      },
      plannedMs: const Duration(hours: 8, minutes: 30).inMilliseconds,
    );
    final breakLater = PomodoroExecutionSnapshot.fromConfiguration(
      runtime: onBreak,
      now: now.add(const Duration(minutes: 3)),
      configuration: const {
        'pomodoro_focus_ms': focusMs,
        'short_break_ms': 5 * 60 * 1000,
      },
      plannedMs: const Duration(hours: 8, minutes: 30).inMilliseconds,
    );

    expect(breakLater.focusedMs, breakStart.focusedMs);
    expect(breakLater.focusedMs, focusMs);
    expect(breakStart.remainingMs, 5 * 60 * 1000);
    expect(breakLater.remainingMs, 2 * 60 * 1000);
  });

  test('every task-monitoring surface uses the shared effort countdown', () {
    final homeShell = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/features/dashboard/presentation/dashboard_screen.dart',
    ).readAsStringSync();
    final browser = File(
      'lib/features/tasks/presentation/task_browser_workspace.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/features/tasks/presentation/task_workspace_screen.dart',
    ).readAsStringSync();

    expect(
      'taskEffortRemainingMs'.allMatches(homeShell).length,
      greaterThanOrEqualTo(2),
      reason: 'The Windows tray and active-task shell pill must count down.',
    );
    expect(
      'formatTaskEffortCountdown'.allMatches(homeShell).length,
      greaterThanOrEqualTo(2),
    );
    expect(dashboard, contains('plannedMs: task.estimatedDurationMs'));
    expect(
      dashboard,
      contains("showsOvertime ? 'overtime_label' : 'remaining'"),
      reason:
          'The dashboard must swap the label at the planned boundary instead of presenting a frozen zero countdown.',
    );
    expect(browser, contains('formatTaskEffortCountdown('));
    expect(browser, contains('taskEffortRemainingMs('));
    expect(
      browser,
      contains("running: runtime?.state == 'running'"),
      reason:
          'The browser pill may repaint a break countdown, but only running focus can add recorded work.',
    );
    expect(
      workspace,
      contains('(running ? currentSegment : 0)'),
      reason:
          'The Execute dial must never add its break or paused wall-clock segment to work.',
    );
    expect(
      workspace,
      contains("runtime?.state == 'running' &&"),
      reason:
          'Workspace metrics must derive live work only from a running segment.',
    );
    expect(
      homeShell,
      contains("running: runtime?.state == 'running'"),
      reason:
          'The tray and compact task pill must freeze persisted work while paused or on break.',
    );
    expect(
      dashboard,
      contains("if (runtime?.state == 'running')"),
      reason:
          'Dashboard actual work must not subscribe to a ticking clock while paused or on break.',
    );
    expect(
      homeShell,
      contains('recordedMs: recordedMs'),
      reason:
          'The alarm boundary must subtract the live segment instead of scheduling from persisted accumulated work alone.',
    );
  });
}
