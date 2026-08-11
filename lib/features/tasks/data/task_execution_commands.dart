import 'dart:async';

import '../../../core/database/app_database.dart';
import '../domain/pomodoro_execution_state.dart';
import 'task_repository.dart';

/// Compound execution commands used by Dashboard, Execute, notifications and
/// compact platform surfaces. Each method is built from the same repository
/// transitions, so no surface invents a device-only state change.
abstract final class TaskExecutionCommands {
  /// Completes the durable local command before starting any network or
  /// platform follow-up. UI controls await this Future for immediate feedback;
  /// slow synchronization continues independently from the main tap path.
  static Future<T> commitLocallyAndSynchronize<T>({
    required Future<T> Function() localCommand,
    required Future<void> Function() synchronize,
  }) async {
    final result = await localCommand();
    try {
      unawaited(
        synchronize().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    } catch (_) {
      // A synchronous platform/bootstrap failure is retried by the durable
      // sync worker and must never turn a committed Start/Pause into a failed
      // button press.
    }
    return result;
  }

  /// Starts the break offered at a completed focus boundary.
  ///
  /// Unlike an explicit "start break early" command, this revalidates the
  /// boundary immediately before mutating state. A delayed notification or a
  /// stale card can therefore never interrupt the following focus interval.
  static Future<bool> startOfferedBreak(
    TaskRepository repository,
    LocalTask requestedTask, {
    DateTime? now,
    DateTime? expectedBoundaryAt,
    Future<void> Function()? beforeTransition,
  }) async {
    final runtime = await repository.getRuntime();
    final task = await repository.getTask(requestedTask.id);
    if (task == null ||
        task.executionMode != 'pomodoro' ||
        runtime == null ||
        runtime.activeTaskId != task.id ||
        runtime.state != 'running') {
      return false;
    }
    final pomodoro = PomodoroExecutionSnapshot.fromTask(
      task: task,
      runtime: runtime,
      now: (now ?? DateTime.now()).toUtc(),
    );
    if (!pomodoro.focusComplete ||
        !_matchesExpectedBoundary(
          runtime: runtime,
          pomodoro: pomodoro,
          expectedBoundaryAt: expectedBoundaryAt,
        )) {
      return false;
    }
    if (beforeTransition != null) await beforeTransition();
    final currentRuntime = await repository.getRuntime();
    if (!_sameRuntimeBoundary(runtime, currentRuntime)) return false;
    await repository.startBreak(task);
    final updated = await repository.getRuntime();
    return updated?.activeTaskId == task.id && updated?.state == 'break';
  }

  static Future<bool> skipOfferedBreak(
    TaskRepository repository,
    LocalTask requestedTask, {
    DateTime? now,
    DateTime? expectedBoundaryAt,
    Future<void> Function()? beforeTransition,
  }) async {
    final runtime = await repository.getRuntime();
    final task = await repository.getTask(requestedTask.id);
    if (task == null ||
        task.executionMode != 'pomodoro' ||
        runtime == null ||
        runtime.activeTaskId != task.id ||
        runtime.state != 'running') {
      return false;
    }
    final pomodoro = PomodoroExecutionSnapshot.fromTask(
      task: task,
      runtime: runtime,
      now: (now ?? DateTime.now()).toUtc(),
    );
    if (!pomodoro.focusComplete ||
        !_matchesExpectedBoundary(
          runtime: runtime,
          pomodoro: pomodoro,
          expectedBoundaryAt: expectedBoundaryAt,
        )) {
      return false;
    }
    if (beforeTransition != null) await beforeTransition();
    final currentRuntime = await repository.getRuntime();
    if (!_sameRuntimeBoundary(runtime, currentRuntime)) return false;
    // This is one canonical command. It never publishes an intermediate
    // `break` state that a Realtime delivery could later restore.
    return repository.skipOfferedBreak(task);
  }

  static Future<bool> startFocusFromCompletedBreak(
    TaskRepository repository,
    LocalTask requestedTask, {
    DateTime? now,
    DateTime? expectedBoundaryAt,
    Future<void> Function()? beforeTransition,
  }) async {
    final runtime = await repository.getRuntime();
    final task = await repository.getTask(requestedTask.id);
    if (task == null ||
        task.executionMode != 'pomodoro' ||
        runtime == null ||
        runtime.activeTaskId != task.id ||
        runtime.state != 'break') {
      return false;
    }
    final pomodoro = PomodoroExecutionSnapshot.fromTask(
      task: task,
      runtime: runtime,
      now: (now ?? DateTime.now()).toUtc(),
    );
    if (!pomodoro.breakComplete ||
        !_matchesExpectedBoundary(
          runtime: runtime,
          pomodoro: pomodoro,
          expectedBoundaryAt: expectedBoundaryAt,
        )) {
      return false;
    }
    if (beforeTransition != null) await beforeTransition();
    final currentRuntime = await repository.getRuntime();
    if (!_sameRuntimeBoundary(runtime, currentRuntime)) return false;
    await repository.finishBreak(task);
    final updated = await repository.getRuntime();
    return updated?.activeTaskId == task.id && updated?.state == 'running';
  }

  /// Performs configured automatic focus/break transitions independently of
  /// whichever application page happens to be visible.
  static Future<bool> advanceAutomaticBoundary({
    required TaskRepository repository,
    required LocalTask requestedTask,
    DateTime? now,
  }) async {
    final runtime = await repository.getRuntime();
    final task = await repository.getTask(requestedTask.id);
    if (task == null ||
        task.executionMode != 'pomodoro' ||
        runtime == null ||
        runtime.activeTaskId != task.id) {
      return false;
    }
    final pomodoro = PomodoroExecutionSnapshot.fromTask(
      task: task,
      runtime: runtime,
      now: (now ?? DateTime.now()).toUtc(),
    );
    if (!pomodoro.isWaiting) return false;
    if (pomodoro.isBreak) {
      if (!pomodoro.autoStartFocus) return false;
      await repository.finishBreak(task);
      final updated = await repository.getRuntime();
      return updated?.activeTaskId == task.id && updated?.state == 'running';
    }
    if (!pomodoro.autoStartBreaks) return false;
    return startOfferedBreak(repository, task, now: now);
  }

  /// Extends the canonical break interval. Notification scheduling deliberately
  /// does not live here: HomeShell observes the runtime revision and is the
  /// single per-device scheduler for every focus/break alarm.
  static Future<bool> extendBreak({
    required TaskRepository repository,
    required LocalTask task,
    DateTime? now,
    DateTime? expectedBoundaryAt,
  }) async {
    if (expectedBoundaryAt != null) {
      final beforeRuntime = await repository.getRuntime();
      final beforeTask = await repository.getTask(task.id);
      if (beforeRuntime == null ||
          beforeTask == null ||
          beforeRuntime.activeTaskId != task.id ||
          beforeRuntime.state != 'break') {
        return false;
      }
      final before = PomodoroExecutionSnapshot.fromTask(
        task: beforeTask,
        runtime: beforeRuntime,
        now: (now ?? DateTime.now()).toUtc(),
      );
      if (!before.breakComplete ||
          !_matchesExpectedBoundary(
            runtime: beforeRuntime,
            pomodoro: before,
            expectedBoundaryAt: expectedBoundaryAt,
          )) {
        return false;
      }
    }
    await repository.extendCurrentBreak(task);
    final runtime = await repository.getRuntime();
    if (runtime == null ||
        runtime.activeTaskId != task.id ||
        runtime.state != 'break') {
      return false;
    }
    return true;
  }

  static bool _matchesExpectedBoundary({
    required LocalRuntime runtime,
    required PomodoroExecutionSnapshot pomodoro,
    required DateTime? expectedBoundaryAt,
  }) {
    if (expectedBoundaryAt == null) return true;
    final startedAt = runtime.segmentStartedAt;
    if (startedAt == null) return false;
    final intervalFromSegmentStart = pomodoro.isBreak
        ? pomodoro.intervalDurationMs
        : pomodoro.focusDurationMs -
              (runtime.accumulatedActiveMs % pomodoro.focusDurationMs);
    final actualBoundary = startedAt.toUtc().add(
      Duration(milliseconds: intervalFromSegmentStart),
    );
    return actualBoundary
            .difference(expectedBoundaryAt.toUtc())
            .inMilliseconds
            .abs() <=
        const Duration(seconds: 2).inMilliseconds;
  }

  static bool _sameRuntimeBoundary(
    LocalRuntime expected,
    LocalRuntime? current,
  ) {
    return current != null &&
        current.activeTaskId == expected.activeTaskId &&
        current.sessionId == expected.sessionId &&
        current.state == expected.state &&
        current.revision == expected.revision &&
        current.segmentStartedAt?.toUtc() == expected.segmentStartedAt?.toUtc();
  }
}
