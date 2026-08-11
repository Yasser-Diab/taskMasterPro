import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_occurrence_policy.dart';

void main() {
  const userId = '00000000-0000-4000-8000-000000000001';
  final now = DateTime.utc(2026, 7, 30, 10);

  LocalTask task({
    String status = 'ready',
    DateTime? dueAt,
    DateTime? scheduledDate,
    DateTime? plannedStart,
    String? templateId,
    String? occurrenceKey,
    String dataJson = '{}',
    DateTime? deletedAt,
  }) => LocalTask(
    id: '00000000-0000-4000-8000-000000000002',
    userId: userId,
    templateId: templateId,
    title: 'Learn German',
    description: '',
    domainId: null,
    status: status,
    priority: 2,
    executionMode: 'continuous',
    scheduledDate: scheduledDate,
    plannedStart: plannedStart,
    plannedEnd: null,
    dueAt: dueAt,
    estimatedDurationMs: 2400000,
    actualStart: null,
    actualFinish: null,
    activeDurationMs: 0,
    pausedDurationMs: 0,
    idleDurationMs: 0,
    progress: 0,
    roadmapId: null,
    roadmapPhaseId: null,
    occurrenceKey: occurrenceKey,
    dataJson: dataJson,
    revision: 1,
    createdAt: now.subtract(const Duration(days: 2)),
    updatedAt: now,
    createdByDeviceId: null,
    updatedByDeviceId: null,
    lastCommandId: null,
    deletedAt: deletedAt,
  );

  test('overdue requires a passed real deadline and an open occurrence', () {
    expect(
      TaskOccurrencePolicy.isOverdue(
        task(dueAt: now.subtract(const Duration(seconds: 1))),
        now: now,
        timeZone: 'Africa/Cairo',
      ),
      isTrue,
    );
    expect(
      TaskOccurrencePolicy.isOverdue(
        task(status: 'overdue'),
        now: now,
        timeZone: 'Africa/Cairo',
      ),
      isFalse,
      reason: 'A stale status without a deadline is not canonical evidence.',
    );
    for (final status in const [
      'completed',
      'cancelled',
      'archived',
      'skipped',
      'replaced',
    ]) {
      expect(
        TaskOccurrencePolicy.isOverdue(
          task(status: status, dueAt: now.subtract(const Duration(days: 1))),
          now: now,
          timeZone: 'Africa/Cairo',
        ),
        isFalse,
      );
    }
  });

  test('template markers and tombstones are never real occurrences', () {
    expect(
      TaskOccurrencePolicy.isRealOccurrence(
        task(dataJson: '{"is_recurrence_template":true}'),
      ),
      isFalse,
    );
    expect(
      TaskOccurrencePolicy.isRealOccurrence(
        task(deletedAt: now.subtract(const Duration(minutes: 1))),
      ),
      isFalse,
    );
  });

  test('local calendar boundaries use the selected IANA zone', () {
    final lateUtc = task(plannedStart: DateTime.utc(2026, 7, 29, 22, 30));
    expect(
      TaskOccurrencePolicy.isScheduledOn(
        lateUtc,
        DateTime(2026, 7, 30),
        timeZone: 'Africa/Cairo',
      ),
      isTrue,
    );
    expect(
      TaskOccurrencePolicy.isScheduledOn(
        lateUtc,
        DateTime(2026, 7, 29),
        timeZone: 'Africa/Cairo',
      ),
      isFalse,
    );
  });

  test('completed today requires the canonical completion instant', () {
    expect(
      TaskOccurrencePolicy.isCompletedOn(
        task(status: 'completed'),
        DateTime(2026, 7, 30),
        timeZone: 'Africa/Cairo',
      ),
      isFalse,
    );
  });
}
