import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/settings/domain/work_schedule.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('rotation uses the synchronized anchor week, not the device locale', () {
    final plan = WorkSchedulePlan(
      enabled: true,
      workingDays: const {DateTime.monday},
      standardStartMinutes: 9 * 60,
      standardEndMinutes: 17 * 60,
      anchorDate: DateTime(2026, 1, 5),
      rotation: const [
        WorkScheduleShift(week: 1, startMinutes: 8 * 60, endMinutes: 16 * 60),
        WorkScheduleShift(
          week: 2,
          startMinutes: 9 * 60 + 30,
          endMinutes: 17 * 60 + 30,
        ),
        WorkScheduleShift(
          week: 3,
          startMinutes: 11 * 60 + 30,
          endMinutes: 19 * 60 + 30,
        ),
      ],
    );

    final next = plan.nextStartUtc(
      location: tz.getLocation('Europe/Warsaw'),
      nowUtc: DateTime.utc(2026, 1, 11, 12),
    );

    expect(next, DateTime.utc(2026, 1, 12, 8, 30));
  });

  test('disabled native work scheduling does not create a reminder', () {
    final plan = WorkSchedulePlan(
      enabled: false,
      workingDays: {DateTime.monday},
      standardStartMinutes: 9 * 60,
      standardEndMinutes: 17 * 60,
      anchorDate: DateTime(2026, 1, 5),
      rotation: [],
    );

    expect(
      plan.nextStartUtc(location: tz.UTC, nowUtc: DateTime.utc(2026, 1, 5, 8)),
      isNull,
    );
  });

  test('regular weekly schedules use standard hours without a rotation', () {
    final plan = WorkSchedulePlan(
      enabled: true,
      workingDays: const {DateTime.monday, DateTime.wednesday},
      standardStartMinutes: 9 * 60,
      standardEndMinutes: 17 * 60,
      anchorDate: DateTime(2026, 1, 5),
      rotation: const [],
    );

    final next = plan.nextStartUtc(
      location: tz.getLocation('Europe/Warsaw'),
      nowUtc: DateTime.utc(2026, 1, 11, 12),
    );

    expect(next, DateTime.utc(2026, 1, 12, 8));
  });

  test('enabling a reminder after its lead time alerts before this shift', () {
    final timing = workScheduleReminderTiming(
      shiftStartUtc: DateTime.utc(2026, 1, 12, 9),
      nowUtc: DateTime.utc(2026, 1, 12, 8, 50),
      reminderOffset: const Duration(minutes: 15),
    );

    expect(timing.scheduledAtUtc, DateTime.utc(2026, 1, 12, 8, 50, 1));
    expect(timing.minutesUntilStart, 10);
  });
}
