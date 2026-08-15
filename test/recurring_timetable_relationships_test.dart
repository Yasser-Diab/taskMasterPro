import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/data/entity_record_repository.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/roadmaps/data/roadmap_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/recurrence_service.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'generated timetable tasks retain phase, resource, link and reminder',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
      );
      final entities = EntityRecordRepository(database, client);
      final tasks = TaskRepository(database, client);
      final roadmaps = RoadmapRepository(database, client);
      final recurrence = RecurrenceService(
        database: database,
        entities: entities,
        tasks: tasks,
      );
      addTearDown(database.close);

      final roadmapId = await roadmaps.createRoadmap(
        const RoadmapDraft(title: 'German to Professional Fluency'),
      );
      final phaseId = await roadmaps.addPhase(
        roadmapId: roadmapId,
        title: 'Phase G1 — A1 Foundation',
        position: 0,
      );
      final todayValue = DateTime.now();
      final today = DateTime(todayValue.year, todayValue.month, todayValue.day);
      final sourceTaskId = await tasks.createTask(
        TaskDraft(
          title: 'Duolingo — 10 minutes',
          description: 'Complete one focused German lesson',
          executionMode: 'habit',
          scheduledDate: today,
          plannedStart: today.add(const Duration(hours: 7, minutes: 15)),
          plannedEnd: today.add(const Duration(hours: 7, minutes: 25)),
          estimatedDuration: const Duration(minutes: 10),
          roadmapId: roadmapId,
          roadmapPhaseId: phaseId,
        ),
      );
      final templateId = await entities.create(
        EntityRecordDraft(
          entityType: 'task_templates',
          parentId: sourceTaskId,
          title: 'Duolingo — 10 minutes',
          data: {
            'source_task_occurrence_id': sourceTaskId,
            'title': 'Duolingo — 10 minutes',
            'description': 'Complete one focused German lesson',
            'execution_mode': 'habit',
            'default_duration_ms': 600000,
            'roadmap_id': roadmapId,
            'roadmap_phase_id': phaseId,
            'reminder_defaults': [
              {
                'reminder_type': 'scheduled_start',
                'offset_ms': 300000,
                'sound_key': 'selected',
                'enabled': true,
              },
            ],
            'execution_settings': {
              'suggested_resource': 'https://www.duolingo.com/learn',
            },
            'data': {'resource_url': 'https://www.duolingo.com/learn'},
          },
        ),
      );
      await entities.create(
        EntityRecordDraft(
          entityType: 'recurrence_rules',
          parentId: templateId,
          secondaryParentId: sourceTaskId,
          title: 'Daily recurrence',
          data: {
            'template_id': templateId,
            'frequency': 'daily',
            'interval_value': 1,
            'weekdays': <int>[],
            'starts_on': _dateOnly(today),
            'local_time': '07:15',
          },
        ),
      );
      await tasks.attachTemplate(
        taskId: sourceTaskId,
        templateId: templateId,
        occurrenceKey: _dateOnly(today),
      );

      expect(await recurrence.generateUpcoming(horizonDays: 2), 2);

      final generated =
          await (database.select(database.localTasks)..where(
                (row) =>
                    row.templateId.equals(templateId) &
                    row.id.equals(sourceTaskId).not(),
              ))
              .get();
      final links = await entities.list(
        entityType: 'roadmap_task_links',
        parentId: roadmapId,
      );
      final reminders = await entities.list(entityType: 'task_reminders');
      final resources = await entities.list(entityType: 'task_resources');

      expect(generated, hasLength(2));
      expect(
        generated.every(
          (task) => task.description == 'Complete one focused German lesson',
        ),
        isTrue,
      );
      expect(generated.every((task) => task.roadmapId == roadmapId), isTrue);
      expect(generated.every((task) => task.roadmapPhaseId == phaseId), isTrue);
      expect(links, hasLength(2));
      expect(reminders, hasLength(2));
      expect(resources, hasLength(2));
      for (final resource in resources) {
        final data = entities.decode(resource);
        expect(resource.parentId, isNot(sourceTaskId));
        expect(data['resource_type'], 'url');
        expect(data['storage_path'], 'https://www.duolingo.com/learn');
      }
    },
  );
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
