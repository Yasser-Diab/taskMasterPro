import '../../../core/database/app_database.dart';
import 'daily_planned_time.dart';

/// The portion of a local calendar day the person has intentionally made
/// available between wake-up and sleep. It is a scheduling boundary, not a
/// productivity target: rest which belongs inside a task still occupies this
/// window, and a plan may never silently exceed it.
class DayScheduleCapacity {
  const DayScheduleCapacity({required this.planned, required this.available});

  final Duration planned;
  final Duration available;

  bool get isExceeded => planned > available;
  Duration get overflow => isExceeded ? planned - available : Duration.zero;

  static DayScheduleCapacity forTasks({
    required Iterable<LocalTask> tasks,
    required DateTime localDay,
    required String timeZone,
    required int wakeTimeMinutes,
    required int sleepTimeMinutes,
  }) => DayScheduleCapacity(
    planned: DailyPlannedTime.calculateTaskEffort(
      tasks,
      localDay: localDay,
      timeZone: timeZone,
    ),
    available: availableDuration(
      wakeTimeMinutes: wakeTimeMinutes,
      sleepTimeMinutes: sleepTimeMinutes,
    ),
  );

  /// Computes capacity from task cards that are already known to be on the
  /// selected day. This preserves the same source of truth as the dashboard
  /// list, including legacy recurring occurrences whose template anchor no
  /// longer names today's date.
  static DayScheduleCapacity forScheduledTasks({
    required Iterable<LocalTask> tasks,
    required int wakeTimeMinutes,
    required int sleepTimeMinutes,
  }) => DayScheduleCapacity(
    planned: DailyPlannedTime.totalOccupiedDuration(tasks),
    available: availableDuration(
      wakeTimeMinutes: wakeTimeMinutes,
      sleepTimeMinutes: sleepTimeMinutes,
    ),
  );

  /// A sleep time on the following calendar day (for example 23:00 → 07:00)
  /// is handled naturally. Equal values are treated as an explicitly open
  /// 24-hour rhythm rather than an accidental zero-minute hard stop.
  static Duration availableDuration({
    required int wakeTimeMinutes,
    required int sleepTimeMinutes,
  }) {
    final wake = wakeTimeMinutes.clamp(0, 24 * 60 - 1).toInt();
    final sleep = sleepTimeMinutes.clamp(0, 24 * 60 - 1).toInt();
    final minutes = sleep == wake ? 24 * 60 : (sleep - wake) % (24 * 60);
    return Duration(minutes: minutes);
  }
}

/// Raised before a write when a new or edited task would make its scheduled
/// day impossible under the account's own wake/sleep rhythm.
class DayScheduleCapacityExceeded implements Exception {
  const DayScheduleCapacityExceeded({
    required this.localDay,
    required this.capacity,
  });

  final DateTime localDay;
  final DayScheduleCapacity capacity;

  @override
  String toString() =>
      'DayScheduleCapacityExceeded(${localDay.toIso8601String()}: '
      '${capacity.planned.inMinutes}/${capacity.available.inMinutes} min)';
}
