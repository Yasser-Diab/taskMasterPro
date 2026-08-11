import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_schedule_policy.dart';

void main() {
  test('06:30 to 07:10 produces one canonical 40 minute duration', () {
    final window = TaskSchedulePolicy.resolve(
      DateTime(2026, 7, 30, 6, 30),
      DateTime(2026, 7, 30, 7, 10),
    );
    expect(window?.duration, const Duration(minutes: 40));
    expect(window?.crossesMidnight, isFalse);
  });

  test('same-day earlier end is normalized as a cross-midnight window', () {
    final window = TaskSchedulePolicy.resolve(
      DateTime(2026, 7, 30, 23, 30),
      DateTime(2026, 7, 30, 0, 15),
    );
    expect(window?.end, DateTime(2026, 7, 31, 0, 15));
    expect(window?.duration, const Duration(minutes: 45));
    expect(window?.crossesMidnight, isTrue);
  });

  test('a forward multi-day end keeps its exact elapsed duration', () {
    final window = TaskSchedulePolicy.resolve(
      DateTime(2026, 8, 11, 9, 30),
      DateTime(2026, 8, 12, 10, 30),
    );

    expect(window?.duration, const Duration(hours: 25));
    expect(window?.crossesMidnight, isFalse);
  });

  test('planned end is clamped to one minute after the planned start', () {
    final start = DateTime(2026, 8, 11, 9, 30);

    expect(
      TaskSchedulePolicy.minimumPlannedEnd(start),
      DateTime(2026, 8, 11, 9, 31),
    );
    expect(
      TaskSchedulePolicy.normalizePlannedEnd(
        start: start,
        end: DateTime(2026, 8, 11, 9, 30),
      ),
      DateTime(2026, 8, 11, 9, 31),
    );
    expect(
      TaskSchedulePolicy.normalizePlannedEnd(
        start: start,
        end: DateTime(2026, 8, 11, 10, 30),
      ),
      DateTime(2026, 8, 11, 10, 30),
    );
  });

  test('useful duration bounds must contain the planned duration', () {
    const planned = Duration(hours: 1);

    expect(
      TaskSchedulePolicy.validateDurationBounds(
        plannedDuration: planned,
        minimumUsefulDuration: const Duration(minutes: 30),
        maximumIntendedDuration: const Duration(hours: 2),
      ),
      isNull,
    );
    expect(
      TaskSchedulePolicy.validateDurationBounds(
        plannedDuration: planned,
        minimumUsefulDuration: const Duration(hours: 2),
        maximumIntendedDuration: Duration.zero,
      ),
      TaskDurationBoundsViolation.minimumExceedsPlanned,
    );
    expect(
      TaskSchedulePolicy.validateDurationBounds(
        plannedDuration: planned,
        minimumUsefulDuration: Duration.zero,
        maximumIntendedDuration: const Duration(minutes: 45),
      ),
      TaskDurationBoundsViolation.maximumBelowPlanned,
    );
    expect(
      TaskSchedulePolicy.validateDurationBounds(
        plannedDuration: planned,
        minimumUsefulDuration: const Duration(minutes: 50),
        maximumIntendedDuration: const Duration(minutes: 40),
      ),
      TaskDurationBoundsViolation.minimumExceedsMaximum,
    );
  });

  test('invalid or duplicate time windows are rejected', () {
    expect(
      TaskSchedulePolicy.resolve(
        DateTime(2026, 7, 30, 6, 30),
        DateTime(2026, 7, 29, 7, 10),
      ),
      isNull,
    );
    expect(
      TaskSchedulePolicy.resolve(
        DateTime(2026, 7, 30, 6, 30),
        DateTime(2026, 7, 30, 6, 30),
      ),
      isNull,
    );
  });
}
