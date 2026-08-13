import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/time/time_zone_service.dart';

/// Calculates elapsed planned time for one local calendar day.
///
/// Timed tasks are an interval union: a study session inside a longer work
/// window describes the same elapsed clock time and is not added twice.
/// A dated task without a complete clock interval still contributes its
/// estimate on that date, but only into the unallocated portion of the day.
abstract final class DailyPlannedTime {
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
      final interval = _intervalFor(
        task,
        estimateMs: estimateMs,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );
      if (interval == null) {
        // A clock anchor outside this day is positioned work with zero daily
        // overlap, not an unpositioned estimate to add somewhere else.
        if (task.plannedStart == null &&
            task.plannedEnd == null &&
            _isFloatingScheduleOn(task.scheduledDate, localDay)) {
          estimatesWithoutPositionMs += estimateMs;
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
