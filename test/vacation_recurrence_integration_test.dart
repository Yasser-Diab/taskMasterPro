import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/data/entity_record_repository.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/recurrence_service.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/vacation_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/vacation_scheduling_service.dart';
import 'package:taskmaster_pro/features/tasks/domain/vacation_period.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recurrence keeps source identity while postponing vacation dates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final entities = EntityRecordRepository(database, client);
      final tasks = TaskRepository(database, client);
      final vacations = VacationRepository(entities);
      final templateId = await entities.create(
        const EntityRecordDraft(
          entityType: 'task_templates',
          title: 'Daily learning',
          data: {
            'title': 'Daily learning',
            'execution_mode': 'pomodoro',
            'default_duration_ms': 1500000,
          },
        ),
      );
      await entities.create(
        EntityRecordDraft(
          entityType: 'recurrence_rules',
          parentId: templateId,
          title: 'Daily recurrence',
          data: const {
            'frequency': 'daily',
            'interval_value': 1,
            'starts_on': '2026-08-10',
            'local_time': '09:00',
          },
        ),
      );
      await vacations.create(
        VacationPeriodDraft(
          title: 'Time away',
          startsOn: DateTime(2026, 8, 10),
          endsOn: DateTime(2026, 8, 11),
        ),
      );
      final recurrence = RecurrenceService(
        database: database,
        entities: entities,
        tasks: tasks,
        vacations: vacations,
        now: () => DateTime(2026, 8, 10),
      );

      expect(await recurrence.generateUpcoming(horizonDays: 2), 3);
      expect(await recurrence.generateUpcoming(horizonDays: 2), 0);
      final generated = await database.select(database.localTasks).get();
      final byOccurrence = {
        for (final task in generated) task.occurrenceKey: task,
      };
      expect(byOccurrence.keys, containsAll(['2026-08-10', '2026-08-11']));
      expect(byOccurrence['2026-08-10']!.scheduledDate, DateTime(2026, 8, 12));
      expect(byOccurrence['2026-08-11']!.scheduledDate, DateTime(2026, 8, 13));
      expect(
        byOccurrence['2026-08-10']!.plannedStart,
        DateTime(2026, 8, 12, 9),
      );
    },
  );

  test(
    'selected-task skip does not suppress another recurring template',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final entities = EntityRecordRepository(database, client);
      final tasks = TaskRepository(database, client);
      final vacations = VacationRepository(entities);
      final skippedTemplate = await _dailyTemplate(entities, 'Skipped');
      final keptTemplate = await _dailyTemplate(entities, 'Kept');
      await vacations.create(
        VacationPeriodDraft(
          title: 'Selective break',
          startsOn: DateTime(2026, 8, 10),
          endsOn: DateTime(2026, 8, 10),
          taskPolicy: VacationTaskPolicy.skip,
          taskScope: VacationTaskScope.selectedTemplates,
          selectedTemplateIds: {skippedTemplate},
        ),
      );
      final recurrence = RecurrenceService(
        database: database,
        entities: entities,
        tasks: tasks,
        vacations: vacations,
        now: () => DateTime(2026, 8, 10),
      );

      expect(await recurrence.generateUpcoming(horizonDays: 0), 1);
      final generated = await database.select(database.localTasks).get();
      expect(generated.single.templateId, keptTemplate);
    },
  );

  test('new recurrence never inherits a source vacation marker', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final entities = EntityRecordRepository(database, client);
    final tasks = TaskRepository(database, client);
    const sourceId = '00000000-0000-4000-8000-000000000001';
    await tasks.createTask(
      const TaskDraft(
        id: sourceId,
        title: 'Source occurrence',
        configuration: {
          'kept_setting': true,
          vacationAdjustmentKey: {
            'vacation_id': 'old-vacation',
            'original_scheduled_date': '2026-08-01',
          },
        },
      ),
    );
    final templateId = await entities.create(
      const EntityRecordDraft(
        entityType: 'task_templates',
        title: 'Copied routine',
        data: {
          'title': 'Copied routine',
          'source_task_occurrence_id': sourceId,
        },
      ),
    );
    await entities.create(
      EntityRecordDraft(
        entityType: 'recurrence_rules',
        parentId: templateId,
        title: 'Daily recurrence',
        data: const {'frequency': 'daily', 'starts_on': '2026-08-10'},
      ),
    );
    final recurrence = RecurrenceService(
      database: database,
      entities: entities,
      tasks: tasks,
      now: () => DateTime(2026, 8, 10),
    );

    expect(await recurrence.generateUpcoming(horizonDays: 0), 1);
    final generated = (await database.select(database.localTasks).get())
        .singleWhere((task) => task.templateId == templateId);
    final configuration = jsonDecode(generated.dataJson) as Map;
    expect(configuration['kept_setting'], isTrue);
    expect(configuration, isNot(contains(vacationAdjustmentKey)));
  });
}

Future<String> _dailyTemplate(
  EntityRecordRepository entities,
  String title,
) async {
  final templateId = await entities.create(
    EntityRecordDraft(
      entityType: 'task_templates',
      title: title,
      data: {'title': title, 'default_duration_ms': 600000},
    ),
  );
  await entities.create(
    EntityRecordDraft(
      entityType: 'recurrence_rules',
      parentId: templateId,
      title: '$title recurrence',
      data: const {
        'frequency': 'daily',
        'starts_on': '2026-08-10',
        'local_time': '09:00',
      },
    ),
  );
  return templateId;
}
