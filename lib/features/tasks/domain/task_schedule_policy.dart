import 'dart:convert';

const plannedTaskRestDurationMsKey = 'planned_rest_duration_ms';

class TaskScheduleWindow {
  const TaskScheduleWindow({
    required this.start,
    required this.end,
    required this.duration,
    required this.crossesMidnight,
  });

  final DateTime start;
  final DateTime end;
  final Duration duration;
  final bool crossesMidnight;
}

/// The reason a user-provided useful-duration range is not compatible with
/// the task's authoritative planned window.
enum TaskDurationBoundsViolation {
  minimumExceedsPlanned,
  maximumBelowPlanned,
  minimumExceedsMaximum,
}

abstract final class TaskSchedulePolicy {
  static const minimumPlanningWindow = Duration(minutes: 1);

  /// Reads the optional rest reserved inside a task's occupied time.
  ///
  /// The value lives in the task's canonical `data` object so it inherits the
  /// established task revision, outbox, conflict, and Realtime convergence
  /// contract instead of creating a second independently synchronized row.
  static Duration plannedRestDuration(Map<String, Object?> configuration) {
    final raw = configuration[plannedTaskRestDurationMsKey];
    final milliseconds = raw is num
        ? raw.toInt()
        : int.tryParse('${raw ?? ''}') ?? 0;
    return Duration(milliseconds: milliseconds.clamp(0, 0x7fffffff).toInt());
  }

  static Duration plannedRestDurationFromJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? plannedRestDuration(Map<String, Object?>.from(decoded))
          : Duration.zero;
    } on FormatException {
      return Duration.zero;
    }
  }

  /// Expected productive work within an occupied start/end window.
  static Duration workDurationWithin({
    required Duration occupiedDuration,
    required Duration plannedRest,
  }) {
    final milliseconds =
        occupiedDuration.inMilliseconds - plannedRest.inMilliseconds;
    return Duration(milliseconds: milliseconds.clamp(0, 1 << 62).toInt());
  }

  /// Total calendar space needed for unpositioned work plus its planned rest.
  static Duration occupiedDurationFor({
    required Duration workDuration,
    required Duration plannedRest,
  }) => workDuration + plannedRest;

  static bool plannedRestFits({
    required Duration occupiedDuration,
    required Duration plannedRest,
  }) =>
      plannedRest >= Duration.zero &&
      plannedRest.inMilliseconds <= 0x7fffffff &&
      (plannedRest == Duration.zero || plannedRest < occupiedDuration);

  /// The earliest valid end for a task with a concrete start.
  ///
  /// Keeping this rule in the domain policy (rather than only in the picker)
  /// means an occurrence editor, a desktop editor, and any future schedule
  /// surface all agree that a zero-length task is not a valid time window.
  static DateTime minimumPlannedEnd(DateTime start) =>
      start.add(minimumPlanningWindow);

  /// Corrects a selected end to the first valid minute after [start].
  ///
  /// This is intentionally used after a start is moved forward too: an old
  /// end must never silently leave the editor with an impossible window.
  static DateTime normalizePlannedEnd({
    required DateTime start,
    required DateTime end,
  }) {
    final minimum = minimumPlannedEnd(start);
    return end.isBefore(minimum) ? minimum : end;
  }

  /// Validates optional useful-duration bounds against an authoritative
  /// planned window. A value of zero means that bound was not specified.
  static TaskDurationBoundsViolation? validateDurationBounds({
    required Duration plannedDuration,
    required Duration minimumUsefulDuration,
    required Duration maximumIntendedDuration,
  }) {
    if (minimumUsefulDuration > Duration.zero &&
        maximumIntendedDuration > Duration.zero &&
        minimumUsefulDuration > maximumIntendedDuration) {
      return TaskDurationBoundsViolation.minimumExceedsMaximum;
    }
    if (minimumUsefulDuration > Duration.zero &&
        minimumUsefulDuration > plannedDuration) {
      return TaskDurationBoundsViolation.minimumExceedsPlanned;
    }
    if (maximumIntendedDuration > Duration.zero &&
        maximumIntendedDuration < plannedDuration) {
      return TaskDurationBoundsViolation.maximumBelowPlanned;
    }
    return null;
  }

  /// Resolves a complete local planning window.
  ///
  /// An earlier time selected on the same calendar date means the task crosses
  /// midnight. An end on an earlier calendar date or an identical start/end is
  /// rejected. Any forward end is kept exactly as selected, including a
  /// multi-day task, so its planned duration is never replaced by a stale
  /// manual estimate.
  static TaskScheduleWindow? resolve(DateTime? start, DateTime? end) {
    if (start == null || end == null || start == end) return null;
    var normalizedEnd = end;
    var crossesMidnight = false;
    if (end.isBefore(start)) {
      final sameDay =
          end.year == start.year &&
          end.month == start.month &&
          end.day == start.day;
      if (!sameDay) return null;
      normalizedEnd = DateTime(
        end.year,
        end.month,
        end.day + 1,
        end.hour,
        end.minute,
        end.second,
        end.millisecond,
        end.microsecond,
      );
      crossesMidnight = true;
    }
    final duration = normalizedEnd.difference(start);
    if (duration <= Duration.zero) return null;
    return TaskScheduleWindow(
      start: start,
      end: normalizedEnd,
      duration: duration,
      crossesMidnight: crossesMidnight,
    );
  }
}
