import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/data/entity_record_repository.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/recurrence_service.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_occurrence_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SupabaseClient client;
  late EntityRecordRepository entities;
  late TaskRepository tasks;
  late RecurrenceService recurrence;
  final now = DateTime(2026, 9, 1, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    entities = EntityRecordRepository(database, client);
    tasks = TaskRepository(database, client, clock: () => now.toUtc());
    recurrence = RecurrenceService(
      database: database,
      entities: entities,
      tasks: tasks,
      now: () => now,
    );
  });

  tearDown(() async {
    await client.dispose();
    await database.close();
  });

  test(
    'saved recurrence is readable and one delete removes the series',
    () async {
      final sourceId = await _createSource(tasks);
      await recurrence.saveSeries(
        taskId: sourceId,
        frequency: 'weekly',
        weekdays: const {2, 4},
        startsOn: DateTime(2026, 9, 1),
        endsOn: DateTime(2026, 10, 1),
        localTime: '09:00',
      );

      final source = (await tasks.getTask(sourceId))!;
      final definition = await recurrence.definitionForTask(source);
      expect(definition, isNotNull);
      expect(definition!.frequency, 'weekly');
      expect(definition.weekdays, {2, 4});
      expect(definition.startsOn, DateTime(2026, 9, 1));
      expect(definition.endsOn, DateTime(2026, 10, 1));
      final template = (await entities.get(source.templateId!))!;
      expect(entities.decode(template)['user_managed'], isTrue);

      await entities.create(
        EntityRecordDraft(
          entityType: 'task_reminders',
          parentId: source.id,
          secondaryParentId: source.templateId,
          title: 'scheduled_start',
          data: {
            'task_occurrence_id': source.id,
            'task_template_id': source.templateId,
          },
        ),
      );
      await recurrence.deleteSeries(source);

      final remaining =
          await (database.select(database.localTasks)..where(
                (row) =>
                    row.templateId.equals(source.templateId!) &
                    row.deletedAt.isNull(),
              ))
              .get();
      expect(remaining, isEmpty);
      expect(
        (await entities.getIncludingDeleted(definition.templateId))!.deletedAt,
        isNotNull,
      );
      expect(
        (await entities.getIncludingDeleted(definition.ruleId))!.deletedAt,
        isNotNull,
      );
      expect(await entities.list(entityType: 'task_reminders'), isEmpty);
    },
  );

  test(
    'Does not repeat keeps the edited task and stops future materialization',
    () async {
      final sourceId = await _createSource(tasks);
      await recurrence.saveSeries(
        taskId: sourceId,
        frequency: 'daily',
        weekdays: const {},
        startsOn: DateTime(2026, 9, 1),
        endsOn: null,
        localTime: '09:00',
      );
      final source = (await tasks.getTask(sourceId))!;
      final templateId = source.templateId!;
      final before =
          await (database.select(database.localTasks)..where(
                (row) =>
                    row.templateId.equals(templateId) & row.deletedAt.isNull(),
              ))
              .get();
      expect(before.length, greaterThan(1));

      await recurrence.stopSeriesKeepingTask(source);

      final kept = (await tasks.getTask(sourceId))!;
      expect(kept.templateId, isNull);
      expect(kept.occurrenceKey, isNull);
      final activeSiblings =
          await (database.select(database.localTasks)..where(
                (row) =>
                    row.templateId.equals(templateId) & row.deletedAt.isNull(),
              ))
              .get();
      expect(activeSiblings, isEmpty);
      expect(await recurrence.generateUpcoming(horizonDays: 14), 0);
    },
  );

  test('postponement moves every overdue boundary in one revision', () async {
    final taskId = await tasks.createTask(
      TaskDraft(
        title: 'Prepare launch notes',
        scheduledDate: DateTime(2026, 9, 1),
        plannedStart: DateTime(2026, 9, 1, 9),
        plannedEnd: DateTime(2026, 9, 1, 10),
        dueAt: DateTime(2026, 9, 1, 10, 30),
        estimatedDuration: const Duration(hours: 1),
      ),
    );
    await (database.update(database.localTasks)
          ..where((row) => row.id.equals(taskId)))
        .write(const LocalTasksCompanion(status: Value('overdue')));
    final overdue = (await tasks.getTask(taskId))!;

    expect(await tasks.postpone(overdue, DateTime(2026, 9, 3)), isTrue);

    final postponed = (await tasks.getTask(taskId))!;
    expect(postponed.status, 'ready');
    expect(postponed.scheduledDate, DateTime(2026, 9, 3));
    expect(postponed.plannedStart, DateTime(2026, 9, 3, 9));
    expect(postponed.plannedEnd, DateTime(2026, 9, 3, 10));
    expect(postponed.dueAt, DateTime(2026, 9, 3, 10, 30));
    expect(
      TaskOccurrencePolicy.isOverdue(
        postponed,
        now: now,
        timeZone: 'Africa/Cairo',
      ),
      isFalse,
    );
    final command =
        (await database.select(database.localOutboxCommands).get()).single;
    final payload = jsonDecode(command.payloadJson) as Map;
    expect(payload['scheduled_date'], '2026-09-03');
    expect(payload['status'], 'ready');
  });
}

Future<String> _createSource(TaskRepository tasks) {
  return tasks.createTask(
    TaskDraft(
      title: 'Daily work routine',
      description: 'One managed recurring series',
      executionMode: 'pomodoro',
      scheduledDate: DateTime(2026, 9, 1),
      plannedStart: DateTime(2026, 9, 1, 9),
      plannedEnd: DateTime(2026, 9, 1, 10),
      estimatedDuration: const Duration(hours: 1),
      configuration: const {'pomodoro_focus_ms': 1500000},
    ),
  );
}
