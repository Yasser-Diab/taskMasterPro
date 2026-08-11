import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  });
}
