import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/shell/presentation/home_shell.dart';

String _identity({
  int accumulatedActiveMs = 120000,
  String runtimeDataJson =
      '{"focus_interval_active_base_ms":0,"pomodoro_completed_focuses":0}',
  String taskDataJson = '{"pomodoro_focus_ms":1500000}',
  bool categoryEnabled = true,
  bool notificationsAuthorized = true,
}) {
  return executionAlarmIntervalIdentity(
    taskId: 'task-1',
    sessionId: 'session-1',
    state: 'running',
    runtimeRevision: 7,
    segmentStartedAt: DateTime.utc(2026, 8, 20, 10),
    accumulatedActiveMs: accumulatedActiveMs,
    runtimeDataJson: runtimeDataJson,
    taskRevision: 4,
    estimatedDurationMs: 8 * 60 * 60 * 1000,
    taskDataJson: taskDataJson,
    eventType: 'focus_completed',
    intervalDurationMs: 25 * 60 * 1000,
    completedFocuses: 0,
    isLongBreak: false,
    categoryEnabled: categoryEnabled,
    notificationsAuthorized: notificationsAuthorized,
  );
}

void main() {
  test('first failure retries identical runtime and success deduplicates', () {
    final state = ExecutionAlarmRetryState();
    final identity = _identity();

    expect(state.beginAttempt(identity), isTrue);
    expect(state.recordFailure(identity), isTrue);
    expect(state.beginAttempt(identity), isFalse);
    expect(state.beginAttempt(identity, retry: true), isTrue);

    state.recordSuccess(identity);
    expect(state.beginAttempt(identity), isFalse);
    expect(state.beginAttempt(identity, retry: true), isFalse);
  });

  test('a second failure exhausts the bounded retry', () {
    final state = ExecutionAlarmRetryState();
    final identity = _identity();

    expect(state.beginAttempt(identity), isTrue);
    expect(state.recordFailure(identity), isTrue);
    expect(state.beginAttempt(identity, retry: true), isTrue);
    expect(state.recordFailure(identity), isFalse);
    expect(state.beginAttempt(identity), isFalse);
    expect(state.beginAttempt(identity, retry: true), isFalse);
  });

  test('intentional inactive intervals deduplicate without a retry token', () {
    final state = ExecutionAlarmRetryState();
    final disabled = _identity(categoryEnabled: false);

    expect(state.beginAttempt(disabled), isTrue);
    state.recordInactive(disabled);
    expect(state.beginAttempt(disabled), isFalse);
    expect(state.beginAttempt(disabled, retry: true), isFalse);
    expect(state.beginAttempt(_identity(categoryEnabled: true)), isTrue);
  });

  test('equal-revision timing corrections replace the alarm identity', () {
    final original = _identity();

    expect(_identity(), original);
    expect(_identity(accumulatedActiveMs: 180000), isNot(original));
    expect(
      _identity(
        runtimeDataJson:
            '{"focus_interval_active_base_ms":120000,'
            '"pomodoro_completed_focuses":1}',
      ),
      isNot(original),
    );
    expect(
      _identity(taskDataJson: '{"pomodoro_focus_ms":3000000}'),
      isNot(original),
    );
  });

  test('completed Pomodoro keeps its delivered boundary notification', () {
    expect(
      shouldPreserveCompletedPomodoroBoundary(
        isPomodoro: true,
        intervalComplete: true,
      ),
      isTrue,
    );
    expect(
      shouldPreserveCompletedPomodoroBoundary(
        isPomodoro: true,
        intervalComplete: false,
      ),
      isFalse,
    );
    expect(
      shouldPreserveCompletedPomodoroBoundary(
        isPomodoro: false,
        intervalComplete: true,
      ),
      isFalse,
    );

    final shell = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();
    final preserve = shell.indexOf(
      'shouldPreserveCompletedPomodoroBoundary(',
      shell.indexOf('Future<void> _synchronizeExecutionAlarm('),
    );
    final cancellation = shell.indexOf(
      'cancelExecutionCompletion(task.id)',
      preserve,
    );
    final statusReplacement = shell.indexOf(
      'localNotificationService.showExecutionStatus(',
      preserve,
    );

    expect(preserve, greaterThanOrEqualTo(0));
    expect(cancellation, greaterThan(preserve));
    expect(statusReplacement, greaterThan(cancellation));
    expect(
      shell.substring(preserve, cancellation),
      contains('return;'),
      reason:
          'A completed interval must return before cancellation or quiet-card replacement.',
    );
  });

  test(
    'HomeShell commits only scheduled boundaries and uses one-shot retry',
    () {
      final shell = File(
        'lib/features/shell/presentation/home_shell.dart',
      ).readAsStringSync();
      final notifications = File(
        'lib/core/notifications/notification_sounds.dart',
      ).readAsStringSync();
      final scheduleCall = shell.indexOf(
        'scheduleResult = await localNotificationService',
      );
      final successCommit = shell.indexOf(
        '_executionAlarmRetryState.recordSuccess(scheduleIdentity)',
        scheduleCall,
      );
      final statusCard = shell.indexOf(
        'localNotificationService.showExecutionStatus(',
        successCommit,
      );

      expect(scheduleCall, greaterThanOrEqualTo(0));
      expect(successCommit, greaterThan(scheduleCall));
      expect(statusCard, greaterThan(successCommit));
      expect(shell, contains('ExecutionAlarmScheduleResult.expired'));
      expect(shell, contains('Timer(_executionAlarmRetryDelay'));
      expect(
        shell,
        isNot(contains('Timer.periodic(_executionAlarmRetryDelay')),
      );
      expect(shell, contains('runtime.accumulatedActiveMs'));
      expect(shell, contains('runtimeDataJson: runtime.dataJson'));
      expect(
        notifications,
        contains(
          'Future<ExecutionAlarmScheduleResult> '
          'scheduleExecutionCompletion({',
        ),
      );
      expect(
        notifications,
        contains('return ExecutionAlarmScheduleResult.scheduled'),
      );
      expect(
        notifications,
        contains('return ExecutionAlarmScheduleResult.expired'),
      );
    },
  );

  test('HomeShell reschedules when active task timing changes', () {
    final shell = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();

    expect(
      shell,
      contains(
        '_runtimeSubscription = repository.watchRuntime().listen(\n'
        '      (runtime) => _observeExecutionRuntime(repository, runtime),',
      ),
    );
    expect(
      shell,
      contains(
        '_executionTaskSubscription = repository.watchTask(taskId).listen',
      ),
    );
    expect(shell, contains('_queueExecutionAlarmFromCurrentRuntime('));
    expect(shell, contains('unawaited(_executionTaskSubscription?.cancel())'));
  });
}
