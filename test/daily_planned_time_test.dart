import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/tasks/domain/day_schedule_capacity.dart';
import 'package:taskmaster_pro/features/tasks/domain/daily_planned_time.dart';
import 'package:taskmaster_pro/features/tasks/presentation/task_card.dart';

void main() {
  LocalTask task({
    required String id,
    DateTime? start,
    DateTime? end,
    Duration estimate = const Duration(minutes: 30),
  }) => LocalTask(
    id: id,
    userId: 'user-1',
    title: id,
    description: '',
    status: 'ready',
    priority: 2,
    executionMode: 'continuous',
    scheduledDate: DateTime.utc(2026, 7, 1),
    plannedStart: start,
    plannedEnd: end,
    estimatedDurationMs: estimate.inMilliseconds,
    activeDurationMs: 0,
    pausedDurationMs: 0,
    idleDurationMs: 0,
    progress: 0,
    dataJson: '{}',
    revision: 1,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );

  test('overlapping planned windows count elapsed time only once', () {
    final result = DailyPlannedTime.calculate(
      [
        task(
          id: 'daily-work',
          start: DateTime.utc(2026, 7, 1, 0, 9),
          end: DateTime.utc(2026, 7, 1, 17, 30),
          estimate: const Duration(hours: 17, minutes: 21),
        ),
        task(
          id: 'german-inside-work',
          start: DateTime.utc(2026, 7, 1, 6, 30),
          end: DateTime.utc(2026, 7, 1, 7, 10),
          estimate: const Duration(minutes: 40),
        ),
        task(
          id: 'programming-after-work',
          start: DateTime.utc(2026, 7, 1, 19, 30),
          end: DateTime.utc(2026, 7, 1, 21),
          estimate: const Duration(minutes: 90),
        ),
      ],
      localDay: DateTime(2026, 7, 1),
      timeZone: 'UTC',
    );

    expect(result, const Duration(hours: 18, minutes: 51));
  });

  test('clips windows to the day and caps unpositioned estimates at 24h', () {
    final result = DailyPlannedTime.calculate(
      [
        task(
          id: 'cross-midnight',
          start: DateTime.utc(2026, 6, 30, 23),
          end: DateTime.utc(2026, 7, 1, 2),
          estimate: const Duration(hours: 3),
        ),
        task(id: 'without-times-1', estimate: const Duration(hours: 16)),
        task(id: 'without-times-2', estimate: const Duration(hours: 16)),
      ],
      localDay: DateTime(2026, 7, 1),
      timeZone: 'UTC',
    );

    expect(result, const Duration(hours: 24));
  });

  test('a positioned task outside the selected day contributes nothing', () {
    final result = DailyPlannedTime.calculate(
      [
        task(
          id: 'tomorrow',
          start: DateTime.utc(2026, 7, 2, 8),
          end: DateTime.utc(2026, 7, 2, 9),
          estimate: const Duration(hours: 1),
        ),
      ],
      localDay: DateTime(2026, 7, 1),
      timeZone: 'UTC',
    );

    expect(result, Duration.zero);
  });

  test('dashboard effort counts every task card on the scheduled day', () {
    final result = DailyPlannedTime.totalOccupiedDuration(
      [
        task(
          id: 'visible-one',
          estimate: const Duration(hours: 4),
          start: DateTime.utc(2026, 6, 1, 9),
          end: DateTime.utc(2026, 6, 1, 13),
        ),
        // A legacy recurring row can retain its original template anchor.
        // Its scheduled date is authoritative for today's dashboard card.
        task(
          id: 'visible-two',
          estimate: const Duration(hours: 2, minutes: 30),
          start: DateTime.utc(2026, 7, 2, 9),
          end: DateTime.utc(2026, 7, 2, 11, 30),
        ),
      ],
    );

    expect(result, const Duration(hours: 6, minutes: 30));
  });

  test('a selected dashboard card counts despite a stale occurrence date', () {
    final result = DailyPlannedTime.totalOccupiedDuration([
      task(
        id: 'selected-card-with-stale-date',
        estimate: const Duration(hours: 4),
        start: DateTime.utc(2026, 7, 2, 9),
        end: DateTime.utc(2026, 7, 2, 13),
      ),
    ]);

    expect(result, const Duration(hours: 4));
  });

  test('schedule capacity counts the same selected dashboard cards', () {
    final capacity = DayScheduleCapacity.forScheduledTasks(
      tasks: [
        task(id: 'first', estimate: const Duration(hours: 9)),
        task(id: 'second', estimate: const Duration(hours: 8)),
      ],
      wakeTimeMinutes: 7 * 60,
      sleepTimeMinutes: 23 * 60,
    );

    expect(capacity.planned, const Duration(hours: 17));
    expect(capacity.isExceeded, isTrue);
    expect(capacity.overflow, const Duration(hours: 1));
  });

  test('daily capacity follows the wake-to-sleep rhythm', () {
    final capacity = DayScheduleCapacity(
      planned: const Duration(hours: 16, minutes: 1),
      available: DayScheduleCapacity.availableDuration(
        wakeTimeMinutes: 7 * 60,
        sleepTimeMinutes: 23 * 60,
      ),
    );

    expect(capacity.available, const Duration(hours: 16));
    expect(capacity.isExceeded, isTrue);
    expect(capacity.overflow, const Duration(minutes: 1));
  });

  test('1041 minutes uses the shared localized human duration', () {
    const value = Duration(minutes: 1041);

    expect(
      const AppLocalizations(Locale('en')).duration(value),
      '17 hours 21 min',
    );
    expect(
      const AppLocalizations(Locale('ar')).duration(value),
      '17 ساعة و21 دقيقة',
    );
    expect(
      const AppLocalizations(Locale('de')).duration(value),
      '17 Stunden 21 Min.',
    );
  });

  testWidgets('task card renders 1041 minutes as hours and minutes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TaskCard(
              task: task(
                id: 'daily-work',
                estimate: const Duration(minutes: 1041),
              ),
              hideExecutionControl: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('17 hours 21 min'), findsOneWidget);
    expect(find.text('1041 min'), findsNothing);
  });

  testWidgets('overdue task card exposes the one-tap postpone action', (
    tester,
  ) async {
    final overdue = task(
      id: 'overdue-work',
      start: DateTime.utc(2026, 7, 1, 8),
      end: DateTime.utc(2026, 7, 1, 9),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TaskCard(task: overdue, hideExecutionControl: true),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('task-postpone-overdue-work')), findsOne);
    expect(find.byIcon(Icons.event_repeat_rounded), findsOne);
    expect(find.text('Postpone'), findsOne);
  });
}
