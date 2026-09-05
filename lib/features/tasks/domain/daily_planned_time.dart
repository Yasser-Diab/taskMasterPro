import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/time/time_zone_service.dart';
import 'task_schedule_policy.dart';

/// Calculates elapsed planned time for one local calendar day.
///
/// Timed tasks are an interval union: a study session inside a longer work
/// window describes the same elapsed clock time and is not added twice.
/// A dated task without a complete clock interval still contributes its
/// estimate on that date, but only into the unallocated portion of the day.
abstract final class DailyPlannedTime {
  /// Adds the calendar space reserved by every occurrence on [localDay].
  ///
  /// This is intentionally different from [calculate]. The latter is an
  /// interval union for historical reporting, where overlapping clock windows
  /// describe the same elapsed time. A dashboard's **Planned** card and the
  /// daily-capacity guard must instead show the commitment the user has made:
  /// every visible task, plus any rest explicitly reserved within it. Keeping
  /// those two numbers on this one calculation prevents a schedule of many
  /// cards from incorrectly reading as the duration of just one card.
  static Duration calculateTaskEffort(
    Iterable<LocalTask> tasks, {
    required DateTime localDay,
    required String timeZone,
  }) {
    var totalMs = 0;
    for (final task in tasks) {
      if (!isOccurrenceScheduledForDay(
        task,
        localDay: localDay,
        timeZone: timeZone,
      )) {
        continue;
      }
      totalMs += occupiedDuration(task).inMilliseconds;
    }
    return Duration(milliseconds: totalMs.clamp(0, 1 << 62).toInt());
  }

  /// The time an unpositioned task reserves on the user's day. Planned rest
  /// is not productive work, but it still occupies a real slot and therefore
  /// belongs in both capacity and planned-commitment calculations.
  static Duration occupiedDuration(LocalTask task) => occupiedDurationFor(
    estimatedDuration: Duration(
      milliseconds: task.estimatedDurationMs.clamp(0, 1 << 62).toInt(),
    ),
    plannedRest: TaskSchedulePolicy.plannedRestDurationFromJson(task.dataJson),
  );

  static Duration occupiedDurationFor({
    required Duration estimatedDuration,
    required Duration plannedRest,
  }) {
    final total = estimatedDuration.inMilliseconds + plannedRest.inMilliseconds;
    return Duration(milliseconds: total.clamp(0, 1 << 62).toInt());
  }

  /// Uses the occurrence's date column before a legacy wall-clock anchor.
  /// Recurring rows carry a concrete occurrence date, while older imports may
  /// retain the original template's [LocalTask.plannedStart]. That stale
  /// anchor must not erase a card that the dashboard is visibly showing today.
  static bool isOccurrenceScheduledForDay(
    LocalTask task, {
    required DateTime localDay,
    required String timeZone,
  }) {
    final scheduledDate = task.scheduledDate;
    if (scheduledDate != null) {
      return scheduledDate.year == localDay.year &&
          scheduledDate.month == localDay.month &&
          scheduledDate.day == localDay.day;
    }
    final plannedStart = task.plannedStart;
    if (plannedStart == null) return false;
    final location = _location(timeZone);
    final local = tz.TZDateTime.from(plannedStart.toUtc(), location);
    return local.year == localDay.year &&
        local.month == localDay.month &&
        local.day == localDay.day;
  }

  static Duration calculate(
    Iterable<LocalTask> tasks, {
    required DateTime localDay,
    required String timeZone,
  }) {
    final location = _location(timeZone);
    final localStart = tz.TZDateTime(
      location,
      localDay.year,
      localDay.month,
      localDay.day,
    );
    final localEnd = tz.TZDateTime(
      location,
      localDay.year,
      localDay.month,
      localDay.day + 1,
    );
    final dayStart = localStart.toUtc();
    final dayEnd = localEnd.toUtc();
    final maximumDayMs = math.min(
      dayEnd.difference(dayStart).inMilliseconds,
      const Duration(hours: 24).inMilliseconds,
    );

    final intervals = <_PlannedInterval>[];
    var estimatesWithoutPositionMs = 0;
    for (final task in tasks) {
      final estimateMs = task.estimatedDurationMs.clamp(0, maximumDayMs);
      final plannedRestMs = TaskSchedulePolicy.plannedRestDurationFromJson(
        task.dataJson,
      ).inMilliseconds;
      final occupiedEstimateMs = (estimateMs + plannedRestMs).clamp(
        0,
        maximumDayMs,
      );
      final interval = _intervalFor(
        task,
        estimateMs: occupiedEstimateMs,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );
      if (interval == null) {
        // A clock anchor outside this day is positioned work with zero daily
        // overlap, not an unpositioned estimate to add somewhere else.
        if (task.plannedStart == null &&
            task.plannedEnd == null &&
            _isFloatingScheduleOn(task.scheduledDate, localDay)) {
          estimatesWithoutPositionMs += occupiedEstimateMs;
        }
      } else {
        intervals.add(interval);
      }
    }

    intervals.sort((left, right) => left.start.compareTo(right.start));
    var unionMs = 0;
    DateTime? currentStart;
    DateTime? currentEnd;
    for (final interval in intervals) {
      if (currentStart == null) {
        currentStart = interval.start;
        currentEnd = interval.end;
        continue;
      }
      if (!interval.start.isAfter(currentEnd!)) {
        if (interval.end.isAfter(currentEnd)) currentEnd = interval.end;
        continue;
      }
      unionMs += currentEnd.difference(currentStart).inMilliseconds;
      currentStart = interval.start;
      currentEnd = interval.end;
    }
    if (currentStart != null) {
      unionMs += currentEnd!.difference(currentStart).inMilliseconds;
    }

    final remainingMs = math.max(0, maximumDayMs - unionMs);
    return Duration(
      milliseconds: unionMs + math.min(estimatesWithoutPositionMs, remainingMs),
    );
  }

  static _PlannedInterval? _intervalFor(
    LocalTask task, {
    required int estimateMs,
    required DateTime dayStart,
    required DateTime dayEnd,
  }) {
    DateTime? start = task.plannedStart?.toUtc();
    DateTime? end = task.plannedEnd?.toUtc();

    if (start != null && (end == null || !end.isAfter(start))) {
      if (estimateMs <= 0) return null;
      end = start.add(Duration(milliseconds: estimateMs));
    } else if (start == null && end != null) {
      if (estimateMs <= 0) return null;
      start = end.subtract(Duration(milliseconds: estimateMs));
    }
    if (start == null || end == null) return null;

    final clippedStart = start.isAfter(dayStart) ? start : dayStart;
    final clippedEnd = end.isBefore(dayEnd) ? end : dayEnd;
    if (!clippedStart.isBefore(clippedEnd)) return null;
    return _PlannedInterval(clippedStart, clippedEnd);
  }

  static bool _isFloatingScheduleOn(DateTime? scheduled, DateTime localDay) =>
      scheduled != null &&
      scheduled.year == localDay.year &&
      scheduled.month == localDay.month &&
      scheduled.day == localDay.day;

  static tz.Location _location(String value) {
    final normalized = TimeZoneService.isValidIana(value) ? value : 'UTC';
    return tz.getLocation(normalized == 'UTC' ? 'Etc/UTC' : normalized);
  }
}

class _PlannedInterval {
  const _PlannedInterval(this.start, this.end);

  final DateTime start;
  final DateTime end;
}
