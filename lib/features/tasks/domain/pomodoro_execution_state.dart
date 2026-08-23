import 'dart:convert';
import 'dart:math' as math;

import '../../../core/database/app_database.dart';

const pomodoroFocusIntervalBaseKey = 'focus_interval_active_base_ms';
const pomodoroCompletedFocusesKey = 'pomodoro_completed_focuses';

/// A pause is deliberately inert, but after this interval the app asks the
/// user to make an explicit decision instead of leaving forgotten work in an
/// ambiguous paused state forever.
const stalePausedTaskThreshold = Duration(hours: 12);

/// Returns whether [task] has been continuously paused long enough to need a
/// decision. The canonical runtime timestamp wins while it owns the task;
/// otherwise the task's last synchronized pause projection is the boundary.
bool isStalePausedTask({
  required LocalTask task,
  required LocalRuntime? runtime,
  required DateTime now,
}) {
  final ownsPausedRuntime =
      runtime?.activeTaskId == task.id && runtime?.state == 'paused';
  if (!ownsPausedRuntime && task.status != 'paused') return false;
  final pausedAt = ownsPausedRuntime ? runtime!.updatedAt : task.updatedAt;
  return !now.toUtc().isBefore(pausedAt.toUtc().add(stalePausedTaskThreshold));
}

Map<String, Object?> pomodoroRuntimeMetadata(LocalRuntime? runtime) {
  if (runtime == null) return const <String, Object?>{};
  try {
    final decoded = jsonDecode(runtime.dataJson);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : const <String, Object?>{};
  } catch (_) {
    return const <String, Object?>{};
  }
}

int pomodoroFocusIntervalBaseMs(LocalRuntime? runtime, int focusDurationMs) {
  if (runtime == null) return 0;
  final accumulated = math.max(0, runtime.accumulatedActiveMs);
  final metadata = pomodoroRuntimeMetadata(runtime);
  final stored = (metadata[pomodoroFocusIntervalBaseKey] as num?)?.toInt();
  if (stored != null) return stored.clamp(0, accumulated).toInt();

  // A pre-v0.0.29 runtime did not persist interval identity. Preserve its
  // historical behavior until the local/remote event backfill supplies the
  // exact last boundary.
  if (focusDurationMs <= 0) return 0;
  return (accumulated ~/ focusDurationMs) * focusDurationMs;
}

int pomodoroCompletedFocuses(LocalRuntime? runtime, int focusDurationMs) {
  if (runtime == null) return 0;
  final metadata = pomodoroRuntimeMetadata(runtime);
  final stored = (metadata[pomodoroCompletedFocusesKey] as num?)?.toInt();
  if (stored != null) return math.max(0, stored);
  if (focusDurationMs <= 0) return 0;
  return math.max(0, runtime.accumulatedActiveMs) ~/ focusDurationMs;
}

/// Returns the persisted break extension after adding one more interval.
///
/// A completed break may remain open long after its original boundary. Merely
/// adding five minutes to that old boundary leaves the countdown at `00:00`
/// until every overdue minute has been added back manually. Rebase only the
/// overdue portion before applying the requested extension so one tap always
/// produces a visible interval from [now], while an active break still gains
/// exactly the requested amount.
int rebasedActiveBreakExtensionMs({
  required int currentExtensionMs,
  required int currentIntervalDurationMs,
  required DateTime segmentStartedAt,
  required DateTime now,
  required int extensionMs,
}) {
  final safeCurrentExtensionMs = math.max(0, currentExtensionMs);
  final elapsedMs = math.max(
    0,
    now.toUtc().difference(segmentStartedAt.toUtc()).inMilliseconds,
  );
  final overdueMs = math.max(
    0,
    elapsedMs - math.max(0, currentIntervalDurationMs),
  );
  return (safeCurrentExtensionMs + overdueMs + math.max(0, extensionMs))
      .toInt();
}

String updatedPomodoroRuntimeData(
  LocalRuntime? runtime, {
  required int focusIntervalActiveBaseMs,
  required int completedFocuses,
}) {
  final metadata = <String, Object?>{...pomodoroRuntimeMetadata(runtime)};
  metadata[pomodoroFocusIntervalBaseKey] = math.max(
    0,
    focusIntervalActiveBaseMs,
  );
  metadata[pomodoroCompletedFocusesKey] = math.max(0, completedFocuses);
  return jsonEncode(metadata);
}

/// Canonical, timestamp-derived Pomodoro state shared by every app surface.
///
/// Keeping this calculation outside individual widgets prevents Dashboard,
/// Execute, notifications, and tests from interpreting the same runtime with
/// different configuration keys or interval boundaries.
class PomodoroExecutionSnapshot {
  const PomodoroExecutionSnapshot({
    required this.focusDurationMs,
    required this.intervalDurationMs,
    required this.nextBreakDurationMs,
    required this.remainingMs,
    required this.focusedMs,
    required this.completedFocuses,
    required this.currentSession,
    required this.approximateSessions,
    required this.isBreak,
    required this.isLongBreak,
    required this.focusComplete,
    required this.breakComplete,
    required this.autoStartBreaks,
    required this.autoStartFocus,
  });

  final int focusDurationMs;
  final int intervalDurationMs;
  final int nextBreakDurationMs;
  final int remainingMs;
  final int focusedMs;
  final int completedFocuses;
  final int currentSession;
  final int approximateSessions;
  final bool isBreak;
  final bool isLongBreak;
  final bool focusComplete;
  final bool breakComplete;
  final bool autoStartBreaks;
  final bool autoStartFocus;

  bool get isWaiting => isBreak ? breakComplete : focusComplete;

  factory PomodoroExecutionSnapshot.fromTask({
    required LocalTask task,
    required LocalRuntime? runtime,
    required DateTime now,
  }) {
    return PomodoroExecutionSnapshot.fromConfiguration(
      runtime: runtime,
      now: now,
      configuration: decodeTaskConfiguration(task.dataJson),
      plannedMs: task.estimatedDurationMs,
    );
  }

  factory PomodoroExecutionSnapshot.fromConfiguration({
    required LocalRuntime? runtime,
    required DateTime now,
    required Map<String, Object?> configuration,
    required int plannedMs,
  }) {
    final focusMs = _durationMs(
      configuration,
      millisecondsKey: 'pomodoro_focus_ms',
      legacyMinutesKey: 'pomodoro_focus_minutes',
      fallbackMs: 25 * 60 * 1000,
    );
    final shortBreakMs = _durationMs(
      configuration,
      millisecondsKey: 'short_break_ms',
      legacyMinutesKey: 'pomodoro_short_break_minutes',
      fallbackMs: 5 * 60 * 1000,
    );
    final longBreakMs = _durationMs(
      configuration,
      millisecondsKey: 'long_break_ms',
      legacyMinutesKey: 'pomodoro_long_break_minutes',
      fallbackMs: 15 * 60 * 1000,
    );
    final longAfter = _integer(configuration, const [
      'long_break_after',
      'pomodoro_long_break_after',
    ], 4).clamp(2, 12).toInt();
    final accumulated = math.max(0, runtime?.accumulatedActiveMs ?? 0);
    final running = runtime?.state == 'running';
    final isBreak = runtime?.state == 'break';
    final rawSegment = (running || isBreak) && runtime?.segmentStartedAt != null
        ? math.max(
            0,
            now
                .toUtc()
                .difference(runtime!.segmentStartedAt!.toUtc())
                .inMilliseconds,
          )
        : 0;
    final focusBase = pomodoroFocusIntervalBaseMs(runtime, focusMs);
    final focusElapsed = (accumulated + (running ? rawSegment : 0) - focusBase)
        .clamp(0, focusMs)
        .toInt();
    final focusComplete =
        running && accumulated + rawSegment >= focusBase + focusMs;
    final completedBeforeInterval = pomodoroCompletedFocuses(runtime, focusMs);
    final completedFocuses =
        completedBeforeInterval + (focusComplete && !isBreak ? 1 : 0);
    final isLongBreak =
        completedFocuses > 0 && completedFocuses % longAfter == 0;
    final nextBreakMs = isLongBreak ? longBreakMs : shortBreakMs;
    final activeBreakExtensionMs = isBreak
        ? math.max(
            0,
            _integer(configuration, const ['active_break_extension_ms'], 0),
          )
        : 0;
    final safeBreakMs = isBreak
        ? nextBreakMs + activeBreakExtensionMs
        : shortBreakMs;
    final breakElapsed = isBreak ? rawSegment.clamp(0, safeBreakMs).toInt() : 0;
    final breakComplete = isBreak && rawSegment >= safeBreakMs;
    final plannedSessions = math.max(1, (plannedMs / focusMs).ceil());
    final currentSession = math.max(
      1,
      isBreak || focusComplete ? completedFocuses : completedFocuses + 1,
    );
    return PomodoroExecutionSnapshot(
      focusDurationMs: focusMs,
      intervalDurationMs: isBreak ? safeBreakMs : focusMs,
      nextBreakDurationMs: nextBreakMs,
      remainingMs: isBreak
          ? math.max(0, safeBreakMs - breakElapsed)
          : math.max(0, focusMs - focusElapsed),
      focusedMs: focusBase + focusElapsed,
      completedFocuses: completedFocuses,
      currentSession: currentSession,
      approximateSessions: plannedSessions,
      isBreak: isBreak,
      isLongBreak: isLongBreak,
      focusComplete: focusComplete,
      breakComplete: breakComplete,
      autoStartBreaks:
          configuration['pomodoro_auto_start_breaks'] == true ||
          configuration['automatic_transitions'] == true,
      autoStartFocus: configuration['pomodoro_auto_start_focus'] == true,
    );
  }
}

enum TaskExecutionPrimaryAction { start, pause, resume, startBreak, startFocus }

enum PomodoroTimerVisualState { running, paused, waiting }

/// Resolves the timer's visible motion state without coupling it to a widget.
///
/// An inactive interval is a waiting interval, not a running one. This keeps
/// pre-start, paused, and completed timers static on every surface.
PomodoroTimerVisualState pomodoroTimerVisualState({
  required bool active,
  required bool paused,
  required bool waiting,
}) {
  if (paused) return PomodoroTimerVisualState.paused;
  if (waiting || !active) return PomodoroTimerVisualState.waiting;
  return PomodoroTimerVisualState.running;
}

bool shouldAnimatePomodoroTimer({
  required bool active,
  required bool paused,
  required bool waiting,
  required bool reducedMotion,
}) {
  return !reducedMotion &&
      pomodoroTimerVisualState(
            active: active,
            paused: paused,
            waiting: waiting,
          ) ==
          PomodoroTimerVisualState.running;
}

/// Formats a timestamp-derived countdown using ceiling seconds.
///
/// A new 25-minute interval therefore renders `25:00` until its first full
/// second has elapsed, followed by `24:59`, and ends at exactly `00:00`.
String formatPomodoroCountdown(int remainingMs) {
  final safeMilliseconds = math.max(0, remainingMs);
  final totalSeconds = safeMilliseconds == 0
      ? 0
      : (safeMilliseconds + 999) ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds ~/ 60) % 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Planned-effort timers always present remaining work as a countdown.
///
/// This is deliberately only the non-negative remaining portion. Callers
/// must pair it with [taskEffortOvertimeMs] while a task is still running so
/// that a live timer never freezes at `00:00:00` while work keeps accruing.
int taskEffortRemainingMs({required int plannedMs, required int recordedMs}) {
  return math.max(0, math.max(0, plannedMs) - math.max(0, recordedMs));
}

/// The elapsed work beyond a task's planned effort. It is separate from the
/// remaining countdown so progress rings can stay bounded while the visible
/// timer clearly changes to an overtime value.
int taskEffortOvertimeMs({required int plannedMs, required int recordedMs}) {
  return math.max(0, math.max(0, recordedMs) - math.max(0, plannedMs));
}

/// Returns persisted task work plus the current live segment, when one exists.
///
/// Keeping this timestamp calculation beside the shared countdown helpers
/// ensures every compact task-monitoring surface displays the same value.
int liveTaskRecordedWorkMs({
  required int recordedMs,
  required bool running,
  required DateTime? segmentStartedAt,
  required DateTime now,
}) {
  final liveSegmentMs = running && segmentStartedAt != null
      ? math.max(
          0,
          now.toUtc().difference(segmentStartedAt.toUtc()).inMilliseconds,
        )
      : 0;
  return math.max(0, recordedMs) + liveSegmentMs;
}

String formatTaskEffortCountdown(int remainingMs) {
  final safeMilliseconds = math.max(0, remainingMs);
  final totalSeconds = safeMilliseconds == 0
      ? 0
      : (safeMilliseconds + 999) ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds ~/ 60) % 60;
  final seconds = totalSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Formats a running task's elapsed overtime with an explicit plus sign.
/// `+00:00:01` cannot be mistaken for a frozen zero countdown.
String formatTaskEffortOvertime(int overtimeMs) =>
    '+${formatTaskEffortCountdown(math.max(0, overtimeMs))}';

/// Pure control availability derived from the same canonical runtime used by
/// the countdown. Widgets can style these actions differently, but cannot
/// disagree about which command a button performs.
class TaskExecutionControlState {
  const TaskExecutionControlState({
    required this.ownsTask,
    required this.primary,
    required this.canStartBreakEarly,
    required this.canSkipBreak,
    required this.canExtendBreak,
  });

  final bool ownsTask;
  final TaskExecutionPrimaryAction primary;
  final bool canStartBreakEarly;
  final bool canSkipBreak;
  final bool canExtendBreak;

  factory TaskExecutionControlState.from({
    required String taskId,
    required String executionMode,
    required LocalRuntime? runtime,
    required PomodoroExecutionSnapshot? pomodoro,
  }) {
    final ownsTask =
        runtime?.activeTaskId == taskId && runtime?.sessionId != null;
    if (!ownsTask) {
      return const TaskExecutionControlState(
        ownsTask: false,
        primary: TaskExecutionPrimaryAction.start,
        canStartBreakEarly: false,
        canSkipBreak: false,
        canExtendBreak: false,
      );
    }
    final isPomodoro = executionMode == 'pomodoro' && pomodoro != null;
    return switch (runtime!.state) {
      'break' => const TaskExecutionControlState(
        ownsTask: true,
        primary: TaskExecutionPrimaryAction.startFocus,
        canStartBreakEarly: false,
        canSkipBreak: false,
        canExtendBreak: true,
      ),
      'paused' => const TaskExecutionControlState(
        ownsTask: true,
        primary: TaskExecutionPrimaryAction.resume,
        canStartBreakEarly: false,
        canSkipBreak: false,
        canExtendBreak: false,
      ),
      'running' when isPomodoro && pomodoro.focusComplete =>
        const TaskExecutionControlState(
          ownsTask: true,
          primary: TaskExecutionPrimaryAction.startBreak,
          canStartBreakEarly: false,
          canSkipBreak: true,
          canExtendBreak: false,
        ),
      'running' => TaskExecutionControlState(
        ownsTask: true,
        primary: TaskExecutionPrimaryAction.pause,
        canStartBreakEarly: isPomodoro,
        canSkipBreak: false,
        canExtendBreak: false,
      ),
      _ => const TaskExecutionControlState(
        ownsTask: false,
        primary: TaskExecutionPrimaryAction.start,
        canStartBreakEarly: false,
        canSkipBreak: false,
        canExtendBreak: false,
      ),
    };
  }
}

Map<String, Object?> decodeTaskConfiguration(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.map((key, value) => MapEntry('$key', value))
        : const <String, Object?>{};
  } catch (_) {
    return const <String, Object?>{};
  }
}

int _durationMs(
  Map<String, Object?> configuration, {
  required String millisecondsKey,
  required String legacyMinutesKey,
  required int fallbackMs,
}) {
  final milliseconds = _nullableInteger(configuration[millisecondsKey]);
  final legacyMinutes = _nullableInteger(configuration[legacyMinutesKey]);
  final raw =
      milliseconds ?? (legacyMinutes == null ? null : legacyMinutes * 60000);
  return (raw ?? fallbackMs).clamp(60000, 24 * 60 * 60 * 1000).toInt();
}

int _integer(
  Map<String, Object?> configuration,
  List<String> keys,
  int fallback,
) {
  for (final key in keys) {
    final parsed = _nullableInteger(configuration[key]);
    if (parsed != null) return parsed;
  }
  return fallback;
}

int? _nullableInteger(Object? value) {
  if (value is num) return value.toInt();
  return value == null ? null : int.tryParse('$value');
}
