import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_domain_catalog.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_list_projection.dart';

void main() {
  const userId = '00000000-0000-4000-8000-000000000001';
  final now = DateTime.utc(2026, 7, 30, 10);

  LocalTask task(
    String id, {
    String title = 'German lesson',
    String status = 'ready',
    DateTime? scheduledDate,
    DateTime? plannedStart,
    DateTime? dueAt,
    DateTime? actualFinish,
    String? templateId,
    String? occurrenceKey,
    String? domainId,
    String? roadmapId,
    String executionMode = 'continuous',
    int priority = 2,
  }) => LocalTask(
    id: id,
    userId: userId,
    templateId: templateId,
    title: title,
    description: '',
    domainId: domainId,
    status: status,
    priority: priority,
    executionMode: executionMode,
    scheduledDate: scheduledDate,
    plannedStart: plannedStart,
    plannedEnd: null,
    dueAt: dueAt,
    estimatedDurationMs: 2400000,
    actualStart: null,
    actualFinish: actualFinish,
    activeDurationMs: 0,
    pausedDurationMs: 0,
    idleDurationMs: 0,
    progress: status == 'completed' ? 1 : 0,
    roadmapId: roadmapId,
    roadmapPhaseId: null,
    occurrenceKey: occurrenceKey,
    dataJson: '{}',
    revision: 1,
    createdAt: now.subtract(const Duration(days: 2)),
    updatedAt: actualFinish ?? now,
    createdByDeviceId: null,
    updatedByDeviceId: null,
    lastCommandId: null,
    deletedAt: null,
  );

  test(
    'normal Tasks list collapses recurring occurrences by UUID template',
    () {
      const templateId = '00000000-0000-4000-8000-000000000010';
      final tasks = [
        task(
          '00000000-0000-4000-8000-000000000011',
          templateId: templateId,
          occurrenceKey: '2026-07-30',
          scheduledDate: DateTime(2026, 7, 30),
        ),
        task(
          '00000000-0000-4000-8000-000000000012',
          templateId: templateId,
          occurrenceKey: '2026-07-31',
          scheduledDate: DateTime(2026, 7, 31),
        ),
        task('00000000-0000-4000-8000-000000000013', title: 'One-time task'),
      ];

      final result = const TaskListQuery().apply(
        tasks,
        now: now,
        timeZone: 'Africa/Cairo',
      );
      expect(result, hasLength(2));
      expect(
        result
            .singleWhere((entry) => entry.isRecurringTemplate)
            .occurrenceCount,
        2,
      );
    },
  );

  test('Completed filter preserves completed occurrence history', () {
    const templateId = '00000000-0000-4000-8000-000000000010';
    final tasks = [
      task(
        '00000000-0000-4000-8000-000000000011',
        status: 'completed',
        actualFinish: now,
        templateId: templateId,
      ),
      task(
        '00000000-0000-4000-8000-000000000012',
        status: 'completed',
        actualFinish: now.subtract(const Duration(days: 1)),
        templateId: templateId,
      ),
    ];
    final result = const TaskListQuery(
      filter: TaskListFilter.completed,
    ).apply(tasks, now: now, timeZone: 'Africa/Cairo');
    expect(result, hasLength(2));
    expect(result.every((entry) => !entry.isRecurringTemplate), isTrue);
  });

  test('filter dimensions use UUID relationships rather than labels', () {
    const domainId = '00000000-0000-4000-8000-000000000020';
    const roadmapId = '00000000-0000-4000-8000-000000000030';
    final matching = task(
      '00000000-0000-4000-8000-000000000011',
      title: 'تعلم اللغة الألمانية',
      domainId: domainId,
      roadmapId: roadmapId,
      executionMode: 'pomodoro',
      priority: 3,
    );
    final result = const TaskListQuery(
      domainId: domainId,
      roadmapId: roadmapId,
      executionMode: 'pomodoro',
      priority: 3,
    ).apply([matching], now: now, timeZone: 'Africa/Cairo');
    expect(result.single.task.id, matching.id);
  });

  test('built-in domain IDs are stable per account and key', () {
    final learning = TaskDomainCatalog.idFor(userId, 'learning');
    expect(learning, TaskDomainCatalog.idFor(userId, 'learning'));
    expect(
      learning,
      isNot(
        TaskDomainCatalog.idFor(
          '00000000-0000-4000-8000-000000000099',
          'learning',
        ),
      ),
    );
    expect(TaskDomainCatalog.builtInKeyForId(userId, learning), 'learning');
  });
}
