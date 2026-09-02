import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/data/entity_record_repository.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/settings/data/settings_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/owner_routine_installer.dart';
import 'package:taskmaster_pro/features/tasks/data/recurrence_service.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/domain/owner_routine_catalog.dart';
import 'package:taskmaster_pro/features/tasks/domain/pomodoro_execution_state.dart';
import 'package:taskmaster_pro/features/tasks/domain/recurring_occurrence_identity.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_domain_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SupabaseClient client;
  late EntityRecordRepository entities;
  late OwnerRoutineInstaller installer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await _authenticate(client);
    entities = EntityRecordRepository(database, client);
    installer = OwnerRoutineInstaller(
      database: database,
      entities: entities,
      settings: SettingsRepository(database, client),
      now: () => DateTime(2026, 8, 13, 12),
    );
  });

  tearDown(() async {
    await client.dispose();
    await database.close();
  });

  test('catalog exactly models the requested nine routines', () {
    expect(OwnerRoutineCatalog.routines, hasLength(9));
    final byKey = {
      for (final routine in OwnerRoutineCatalog.routines) routine.key: routine,
    };

    _expectRoutine(byKey['work_non_friday']!, '09:00', 510, [1, 2, 3, 4, 6, 7]);
    _expectRoutine(byKey['german_sat_wed']!, '06:30', 40, [1, 2, 3, 6, 7]);
    _expectRoutine(byKey['programming_sat_wed']!, '19:30', 90, [1, 2, 3, 6, 7]);
    _expectRoutine(byKey['german_thursday']!, '06:30', 40, [4]);
    _expectRoutine(byKey['english_thursday']!, '19:30', 45, [4]);
    _expectRoutine(byKey['programming_friday']!, '08:00', 240, [5]);
    _expectRoutine(byKey['german_friday']!, '16:00', 75, [5]);
    _expectRoutine(byKey['english_friday']!, '17:30', 45, [5]);
    _expectRoutine(byKey['duolingo_german_daily']!, '13:00', 10, const []);

    expect(byKey['work_non_friday']!.resourceUrl, isNull);
    expect(byKey['work_non_friday']!.resourceName, isNull);
    expect(byKey['work_non_friday']!.executionMode, 'pomodoro');
    expect(
      byKey['work_non_friday']!.executionSettings['pomodoro_focus_ms'],
      const Duration(minutes: 25).inMilliseconds,
    );
    final workTimer = PomodoroExecutionSnapshot.fromConfiguration(
      runtime: null,
      now: DateTime(2026, 8, 13, 9),
      configuration: byKey['work_non_friday']!.executionSettings,
      plannedMs: byKey['work_non_friday']!.duration.inMilliseconds,
    );
    expect(workTimer.remainingMs, const Duration(minutes: 25).inMilliseconds);
    expect(workTimer.approximateSessions, 21);
    expect(
      OwnerRoutineCatalog.routines.where(
        (routine) => routine.resourceUrl != null,
      ),
      hasLength(8),
    );
  });

  test(
    'eligibility requires the proven imported marker in all three roadmaps',
    () async {
      expect(await installer.isEligible(), isFalse);
      await _insertImportedRoadmaps(database, client.auth.currentUser!.id);
      expect(await installer.isEligible(), isTrue);

      await (database.update(database.localTasks)
            ..where((row) => row.id.equals('marker-2')))
          .write(const LocalTasksCompanion(dataJson: Value('{}')));
      expect(await installer.isEligible(), isFalse);
    },
  );

  test(
    'repairs the exact 00:09 owner-import schedule once through canonical settings',
    () async {
      final userId = client.auth.currentUser!.id;
      await _insertImportedRoadmaps(database, userId);
      await _insertRequiredDomains(database, userId);
      final now = DateTime.utc(2026, 8, 11);
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: localAppSettingsId(userId),
              userId: Value(userId),
              workingDaysJson: const Value('[1,2,3,4,5]'),
              workStartMinutes: const Value(9),
              workEndMinutes: const Value(1050),
              wakeTimeMinutes: const Value(333),
              quietStartMinutes: const Value(1260),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final first = await installer.ensureInstalled();
      expect(first.settingsUpdated, 1);
      final repaired = await (database.select(
        database.localAppSettings,
      )..where((row) => row.id.equals(localAppSettingsId(userId)))).getSingle();
      expect(repaired.workingDaysJson, '[1,2,3,4,6,7]');
      expect(repaired.workStartMinutes, 540);
      expect(repaired.workEndMinutes, 1050);
      expect(repaired.wakeTimeMinutes, 333);
      expect(repaired.quietStartMinutes, 1260);

      final settingsCommands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('user_settings') &
                    row.entityId.equals(userId),
              ))
              .get();
      expect(settingsCommands, hasLength(1));
      final payload = jsonDecode(settingsCommands.single.payloadJson) as Map;
      expect(payload['data'], {
        'working_days': [1, 2, 3, 4, 6, 7],
        'work_start_minutes': 540,
        'work_end_minutes': 1050,
      });

      // Once the bad 00:09 signature is gone, the bootstrap must not act as
      // a permanent policy that overwrites later owner customization.
      await (database.update(
        database.localAppSettings,
      )..where((row) => row.id.equals(localAppSettingsId(userId)))).write(
        const LocalAppSettingsCompanion(workingDaysJson: Value('[1,3]')),
      );
      final second = await installer.ensureInstalled();
      expect(second.changed, isFalse);
      expect(
        (await (database.select(database.localAppSettings)
                  ..where((row) => row.id.equals(localAppSettingsId(userId))))
                .getSingle())
            .workingDaysJson,
        '[1,3]',
      );
      expect(
        await (database.select(
          database.localOutboxCommands,
        )..where((row) => row.entityType.equals('user_settings'))).get(),
        hasLength(1),
      );
    },
  );

  test(
    'repairs the old midnight continuous work routine without rewriting history',
    () async {
      final userId = client.auth.currentUser!.id;
      await _insertImportedRoadmaps(database, userId);
      await _insertRequiredDomains(database, userId);
      await installer.ensureInstalled();

      final templateId = OwnerRoutineCatalog.stableId(
        userId: userId,
        routineKey: 'work_non_friday',
        recordKind: 'template',
      );
      final ruleId = OwnerRoutineCatalog.stableId(
        userId: userId,
        routineKey: 'work_non_friday',
        recordKind: 'rule',
      );
      final template = (await entities.get(templateId))!;
      final rule = (await entities.get(ruleId))!;
      final oldTemplate = entities.decode(template)
        ..['execution_mode'] = 'continuous'
        ..['default_duration_ms'] = const Duration(
          hours: 17,
          minutes: 21,
        ).inMilliseconds
        ..['execution_settings'] = {
          'completion_method': 'duration',
          'time_zone': 'Africa/Cairo',
        };
      final oldRule = entities.decode(rule);
      final nestedRule = Map<String, Object?>.from(oldRule['rule_data'] as Map)
        ..['local_time'] = '00:09';
      oldRule['rule_data'] = nestedRule;
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(templateId))).write(
        LocalEntityRecordsCompanion(dataJson: Value(jsonEncode(oldTemplate))),
      );
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(ruleId))).write(
        LocalEntityRecordsCompanion(dataJson: Value(jsonEncode(oldRule))),
      );

      final tasks = TaskRepository(database, client);
      Future<void> createOldOccurrence(
        String id,
        DateTime day, {
        String status = 'ready',
      }) async {
        final start = DateTime(day.year, day.month, day.day, 0, 9);
        await tasks.createTask(
          TaskDraft(
            id: id,
            title: 'Daily work routine',
            executionMode: 'continuous',
            scheduledDate: day,
            plannedStart: start,
            plannedEnd: start.add(const Duration(hours: 17, minutes: 21)),
            estimatedDuration: const Duration(hours: 17, minutes: 21),
            templateId: templateId,
            occurrenceKey:
                '${day.year.toString().padLeft(4, '0')}-'
                '${day.month.toString().padLeft(2, '0')}-'
                '${day.day.toString().padLeft(2, '0')}',
            configuration: const {
              'owner_routine_key': 'work_non_friday',
              'source_fingerprint': 'keep-source-provenance',
              'user_note': 'preserve me',
              'pomodoro_focus_ms': 60000,
            },
          ),
        );
        if (status != 'ready') {
          await (database.update(
            database.localTasks,
          )..where((row) => row.id.equals(id))).write(
            LocalTasksCompanion(
              status: Value(status),
              actualStart: Value(start),
              actualFinish: status == 'completed'
                  ? Value(start.add(const Duration(minutes: 25)))
                  : const Value.absent(),
            ),
          );
        }
      }

      await createOldOccurrence(
        'old-completed',
        DateTime(2026, 8, 12),
        status: 'completed',
      );
      await createOldOccurrence(
        'old-active',
        DateTime(2026, 8, 13),
        status: 'in_progress',
      );
      await createOldOccurrence('old-future', DateTime(2026, 8, 15));

      // Model a released device whose original creates already reached the
      // server. The corrective pass must enqueue one update per canonical
      // row, not hide the repair inside an unsent create command.
      await database
          .update(database.localOutboxCommands)
          .write(const LocalOutboxCommandsCompanion(status: Value('accepted')));

      final commandsBeforeRepair =
          (await database.select(database.localOutboxCommands).get()).length;
      final repair = await installer.ensureInstalled();
      expect(repair.templatesUpdated, 1);
      expect(repair.rulesUpdated, 1);
      expect(repair.occurrencesUpdated, 1);

      final repaired = (await tasks.getTask('old-future'))!;
      expect(repaired.executionMode, 'pomodoro');
      expect(repaired.plannedStart, DateTime(2026, 8, 15, 9));
      expect(repaired.plannedEnd, DateTime(2026, 8, 15, 17, 30));
      expect(
        repaired.estimatedDurationMs,
        const Duration(hours: 8, minutes: 30).inMilliseconds,
      );
      expect(
        jsonDecode(repaired.dataJson)['pomodoro_focus_ms'],
        const Duration(minutes: 25).inMilliseconds,
      );
      expect(jsonDecode(repaired.dataJson)['user_note'], 'preserve me');
      expect(
        jsonDecode(repaired.dataJson)['source_fingerprint'],
        'keep-source-provenance',
      );

      final completed = (await tasks.getTask('old-completed'))!;
      final active = (await tasks.getTask('old-active'))!;
      expect(completed.executionMode, 'continuous');
      expect(active.executionMode, 'continuous');
      expect(
        completed.estimatedDurationMs,
        const Duration(hours: 17, minutes: 21).inMilliseconds,
      );
      expect(
        active.estimatedDurationMs,
        const Duration(hours: 17, minutes: 21).inMilliseconds,
      );

      final commandsAfterRepair =
          (await database.select(database.localOutboxCommands).get()).length;
      expect(commandsAfterRepair - commandsBeforeRepair, 3);
      final repeated = await installer.ensureInstalled();
      expect(repeated.changed, isFalse);
      expect(
        (await database.select(database.localOutboxCommands).get()).length,
        commandsAfterRepair,
      );
    },
  );

  test(
    'installation creates nine idempotent templates and rules only',
    () async {
      final userId = client.auth.currentUser!.id;
      await _insertImportedRoadmaps(database, userId);
      await _insertRequiredDomains(database, userId);

      final first = await installer.ensureInstalled();
      expect(first.templatesCreated, 9);
      expect(first.rulesCreated, 9);
      final second = await installer.ensureInstalled();
      expect(second.changed, isFalse);

      final templates = await entities.list(entityType: 'task_templates');
      final rules = await entities.list(entityType: 'recurrence_rules');
      expect(templates, hasLength(9));
      expect(rules, hasLength(9));
      expect(await database.select(database.localTasks).get(), hasLength(3));

      for (final routine in OwnerRoutineCatalog.routines) {
        final templateId = OwnerRoutineCatalog.stableId(
          userId: userId,
          routineKey: routine.key,
          recordKind: 'template',
        );
        final ruleId = OwnerRoutineCatalog.stableId(
          userId: userId,
          routineKey: routine.key,
          recordKind: 'rule',
        );
        final template = await entities.get(templateId);
        final rule = await entities.get(ruleId);
        expect(template, isNotNull, reason: routine.key);
        expect(rule, isNotNull, reason: routine.key);
        final templateData = entities.decode(template!);
        final ruleData = entities.decode(rule!);
        expect(templateData['recurrence_rule_id'], ruleId);
        expect(ruleData['starts_on'], OwnerRoutineCatalog.routineStart);
        expect(ruleData['weekdays'], routine.weekdays);
        expect((ruleData['rule_data'] as Map)['local_time'], routine.localTime);
        if (routine.key == 'work_non_friday') {
          expect(
            (templateData['data'] as Map).containsKey('resource_url'),
            isFalse,
          );
          expect(
            (templateData['execution_settings'] as Map).containsKey(
              'suggested_resource',
            ),
            isFalse,
          );
        }
      }

      final pending =
          await (database.select(database.localOutboxCommands)
                ..where((row) => row.status.equals('pending'))
                ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)]))
              .get();
      expect(
        pending.where((row) => row.entityType == 'recurrence_rules'),
        hasLength(9),
      );
      expect(
        pending.where((row) => row.entityType == 'task_templates'),
        hasLength(9),
      );
      for (final routine in OwnerRoutineCatalog.routines) {
        final ruleId = OwnerRoutineCatalog.stableId(
          userId: userId,
          routineKey: routine.key,
          recordKind: 'rule',
        );
        final templateId = OwnerRoutineCatalog.stableId(
          userId: userId,
          routineKey: routine.key,
          recordKind: 'template',
        );
        final ruleIndex = pending.indexWhere((row) => row.entityId == ruleId);
        final templateIndex = pending.indexWhere(
          (row) => row.entityId == templateId,
        );
        expect(ruleIndex, lessThan(templateIndex), reason: routine.key);
      }
    },
  );

  test(
    'explicitly deleted and user-managed routines are never restored',
    () async {
      final userId = client.auth.currentUser!.id;
      await _insertImportedRoadmaps(database, userId);
      await _insertRequiredDomains(database, userId);
      await installer.ensureInstalled();

      final deletedRoutine = OwnerRoutineCatalog.routines.first;
      final deletedTemplateId = OwnerRoutineCatalog.stableId(
        userId: userId,
        routineKey: deletedRoutine.key,
        recordKind: 'template',
      );
      final deletedRuleId = OwnerRoutineCatalog.stableId(
        userId: userId,
        routineKey: deletedRoutine.key,
        recordKind: 'rule',
      );
      await entities.softDelete((await entities.get(deletedRuleId))!);
      await entities.softDelete((await entities.get(deletedTemplateId))!);

      final managedRoutine = OwnerRoutineCatalog.routines[1];
      final managedTemplateId = OwnerRoutineCatalog.stableId(
        userId: userId,
        routineKey: managedRoutine.key,
        recordKind: 'template',
      );
      final managedRuleId = OwnerRoutineCatalog.stableId(
        userId: userId,
        routineKey: managedRoutine.key,
        recordKind: 'rule',
      );
      final managedTemplate = (await entities.get(managedTemplateId))!;
      final managedRule = (await entities.get(managedRuleId))!;
      final templateData = entities.decode(managedTemplate)
        ..['title'] = 'My custom routine'
        ..['user_managed'] = true;
      final ruleData = entities.decode(managedRule)
        ..['frequency'] = 'monthly'
        ..['user_managed'] = true;
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(managedTemplateId))).write(
        LocalEntityRecordsCompanion(dataJson: Value(jsonEncode(templateData))),
      );
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(managedRuleId))).write(
        LocalEntityRecordsCompanion(dataJson: Value(jsonEncode(ruleData))),
      );

      await installer.ensureInstalled();

      expect(
        (await entities.getIncludingDeleted(deletedRuleId))!.deletedAt,
        isNotNull,
      );
      expect(
        (await entities.getIncludingDeleted(deletedTemplateId))!.deletedAt,
        isNotNull,
      );
      expect(
        entities.decode((await entities.get(managedRuleId))!)['frequency'],
        'monthly',
      );
      expect(
        entities.decode((await entities.get(managedTemplateId))!)['title'],
        'My custom routine',
      );
    },
  );

  test('one generator path creates linked deterministic occurrences', () async {
    final userId = client.auth.currentUser!.id;
    await _insertImportedRoadmaps(database, userId);
    await _insertRequiredDomains(database, userId);
    await installer.ensureInstalled();
    final tasks = TaskRepository(database, client);
    final recurrence = RecurrenceService(
      database: database,
      entities: entities,
      tasks: tasks,
      now: () => DateTime(2026, 8, 13),
    );

    expect(await recurrence.generateUpcoming(horizonDays: 2), 12);
    expect(await recurrence.generateUpcoming(horizonDays: 2), 0);

    final occurrences = await (database.select(
      database.localTasks,
    )..where((row) => row.templateId.isNotNull())).get();
    expect(occurrences, hasLength(12));
    final work = occurrences
        .where((task) => task.title == 'Daily work routine')
        .toList();
    expect(work, hasLength(2));
    expect(work.every((task) => task.plannedStart!.hour == 9), isTrue);
    expect(work.every((task) => task.plannedStart!.minute == 0), isTrue);
    expect(
      work.every(
        (task) =>
            task.plannedEnd!.difference(task.plannedStart!) ==
            const Duration(hours: 8, minutes: 30),
      ),
      isTrue,
    );
    expect(work.every((task) => task.executionMode == 'pomodoro'), isTrue);
    expect(
      work.every(
        (task) =>
            jsonDecode(task.dataJson)['pomodoro_focus_ms'] ==
            const Duration(minutes: 25).inMilliseconds,
      ),
      isTrue,
    );
    expect(
      work.any((task) => task.scheduledDate!.weekday == DateTime.friday),
      isFalse,
    );

    final thursdayWork = work.singleWhere(
      (task) => task.occurrenceKey == '2026-08-13',
    );
    expect(
      thursdayWork.id,
      recurringOccurrenceId(
        userId: userId,
        templateId: thursdayWork.templateId!,
        occurrenceKey: '2026-08-13',
      ),
    );

    final resources = await entities.list(entityType: 'task_resources');
    final reminders = await entities.list(entityType: 'task_reminders');
    final links = await entities.list(entityType: 'roadmap_task_links');
    expect(resources, hasLength(10));
    expect(reminders, hasLength(12));
    expect(links, hasLength(10));
    expect(resources.every((row) => row.parentId != null), isTrue);
    expect(
      resources.any(
        (row) =>
            entities.decode(row)['storage_path'] ==
            'https://taskmasterpro.app/work-routine',
      ),
      isFalse,
    );

    final firstIds = occurrences.map((task) => task.id).toSet();
    expect(firstIds, hasLength(12));
    expect(await recurrence.generateUpcoming(horizonDays: 2), 0);
    final repeated = await (database.select(
      database.localTasks,
    )..where((row) => row.templateId.isNotNull())).get();
    expect(repeated.map((task) => task.id).toSet(), firstIds);
  });
}

void _expectRoutine(
  OwnerRoutineDefinition routine,
  String localTime,
  int minutes,
  List<int> weekdays,
) {
  expect(routine.localTime, localTime);
  expect(routine.duration.inMinutes, minutes);
  expect(routine.weekdays, weekdays);
}

Future<void> _authenticate(SupabaseClient client) async {
  const userId = '07704e12-d1c9-4c03-8fb5-04b1b6efe904';
  final user = User(
    id: userId,
    appMetadata: const {},
    userMetadata: const {'display_name': 'Yasser Diab'},
    aud: 'authenticated',
    email: 'owner@example.test',
    createdAt: '2026-08-11T00:00:00Z',
  );
  final session = Session(
    accessToken: 'not-a-jwt',
    refreshToken: 'test-refresh',
    tokenType: 'bearer',
    expiresIn: 86400,
    user: user,
  );
  await client.auth.recoverSession(jsonEncode(session.toJson()));
}

Future<void> _insertImportedRoadmaps(
  AppDatabase database,
  String userId,
) async {
  final now = DateTime.utc(2026, 8, 11);
  const imports = {
    'Full-Stack Development': 'full_stack_development:p0:task:001',
    'German Professional Fluency': 'german_professional_fluency:g0:task:001',
    'English Professional Fluency': 'english_professional_fluency:e0:task:001',
  };
  var index = 0;
  for (final entry in imports.entries) {
    final roadmapId = 'roadmap-${index + 1}';
    await database
        .into(database.localRoadmaps)
        .insert(
          LocalRoadmapsCompanion.insert(
            id: roadmapId,
            userId: userId,
            title: entry.key,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'marker-${index + 1}',
            userId: userId,
            title: '${entry.key.split(' ').first} marker',
            roadmapId: Value(roadmapId),
            dataJson: Value(
              jsonEncode({
                'roadmap_import_key': entry.value,
                'source_fingerprint': OwnerRoutineCatalog.sourceFingerprint,
                'schedule_provenance': OwnerRoutineCatalog.scheduleProvenance,
              }),
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.localEntityRecords)
        .insert(
          LocalEntityRecordsCompanion.insert(
            id: 'phase-${index + 1}',
            userId: userId,
            entityType: 'roadmap_phases',
            parentId: Value(roadmapId),
            title: Value(switch (index) {
              0 => 'P0 - Setup',
              1 => 'G0 - Beginner',
              _ => 'E0 - Baseline',
            }),
            createdAt: now,
            updatedAt: now,
          ),
        );
    index++;
  }
}

Future<void> _insertRequiredDomains(AppDatabase database, String userId) async {
  final now = DateTime.utc(2026, 8, 11);
  for (final key in const ['work', 'learning']) {
    await database
        .into(database.localDomains)
        .insert(
          LocalDomainsCompanion.insert(
            id: TaskDomainCatalog.idFor(userId, key),
            userId: userId,
            name: key,
            colorValue: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
