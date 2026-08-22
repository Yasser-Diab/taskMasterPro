import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/data/entity_record_repository.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/vacation_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/vacation_schedule_coordinator.dart';
import 'package:taskmaster_pro/features/tasks/data/vacation_scheduling_service.dart';
import 'package:taskmaster_pro/features/tasks/domain/vacation_period.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlaps are deterministic and skip takes precedence', () {
    final postpone = _period(
      id: 'b-postpone',
      startsOn: DateTime(2026, 8, 10),
      endsOn: DateTime(2026, 8, 12),
      policy: VacationTaskPolicy.postpone,
    );
    final skip = _period(
      id: 'a-skip',
      startsOn: DateTime(2026, 8, 11),
      endsOn: DateTime(2026, 8, 13),
      policy: VacationTaskPolicy.skip,
    );
    final planner = VacationPlanner([postpone, skip]);

    final disposition = planner.dispositionFor(
      occurrenceDate: DateTime(2026, 8, 11),
      templateId: 'daily-work',
    );

    expect(disposition.isSkipped, isTrue);
    expect(disposition.vacationId, 'a-skip');
    expect(disposition.scheduledDate, DateTime(2026, 8, 11));
  });

  test('postponement preserves offset and crosses back-to-back vacations', () {
    final planner = VacationPlanner([
      _period(
        id: 'first',
        startsOn: DateTime(2026, 8, 10),
        endsOn: DateTime(2026, 8, 12),
        policy: VacationTaskPolicy.postpone,
      ),
      _period(
        id: 'second',
        startsOn: DateTime(2026, 8, 14),
        endsOn: DateTime(2026, 8, 15),
        policy: VacationTaskPolicy.postpone,
      ),
    ]);

    // Aug 11 first moves to Aug 14 (same offset after the first period), then
    // moves past the second period to Aug 16.
    final disposition = planner.dispositionFor(
      occurrenceDate: DateTime(2026, 8, 11),
      templateId: 'daily-work',
    );
    expect(disposition.policy, VacationTaskPolicy.postpone);
    expect(disposition.scheduledDate, DateTime(2026, 8, 16));
  });

  test('yearly vacation covers the New Year boundary', () {
    final period = _period(
      id: 'new-year',
      startsOn: DateTime(2025, 12, 30),
      endsOn: DateTime(2026, 1, 2),
      policy: VacationTaskPolicy.postpone,
      recurrence: VacationRecurrence.yearly,
    );

    final occurrence = period.occurrenceContaining(DateTime(2027, 1, 1));
    expect(occurrence, isNotNull);
    expect(occurrence!.startsOn, DateTime(2026, 12, 30));
    expect(occurrence.endsOn, DateTime(2027, 1, 2));
  });

  test('queued vacation keeps schema metadata inside data', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final vacations = VacationRepository(
      EntityRecordRepository(database, client),
    );

    final vacationId = await vacations.create(
      VacationPeriodDraft(
        title: 'Summer holiday',
        startsOn: DateTime(2026, 8, 10),
        endsOn: DateTime(2026, 8, 12),
      ),
    );
    final command =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.entityType.equals(VacationRepository.entityType) &
                  row.entityId.equals(vacationId),
            ))
            .getSingle();
    final payload = Map<String, Object?>.from(
      jsonDecode(command.payloadJson) as Map,
    );

    expect(payload, isNot(contains('schema_version')));
    expect(payload['data'], {'schema_version': 1});
  });

  test('reconciliation is reversible, idempotent and future-only', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final entities = EntityRecordRepository(database, client);
    final tasks = TaskRepository(
      database,
      client,
      clock: () => DateTime.utc(2026, 8, 1),
    );
    final vacations = VacationRepository(entities);
    final service = VacationSchedulingService(
      database: database,
      tasks: tasks,
      vacations: vacations,
      now: () => DateTime(2026, 8, 1),
    );

    final templateId = await entities.create(
      const EntityRecordDraft(
        entityType: 'task_templates',
        title: 'Daily work',
      ),
    );
    final futureTaskId = await tasks.createTask(
      TaskDraft(
        title: 'Daily work',
        templateId: templateId,
        occurrenceKey: '2026-08-11',
        scheduledDate: DateTime(2026, 8, 11),
        plannedStart: DateTime(2026, 8, 11, 9),
        plannedEnd: DateTime(2026, 8, 11, 9, 25),
        dueAt: DateTime(2026, 8, 11, 17, 30),
      ),
    );
    final pastTaskId = await tasks.createTask(
      TaskDraft(
        title: 'Past work',
        templateId: templateId,
        occurrenceKey: '2026-07-11',
        scheduledDate: DateTime(2026, 7, 11),
      ),
    );
    final runningTaskId = await tasks.createTask(
      TaskDraft(
        title: 'Already running',
        templateId: templateId,
        occurrenceKey: '2026-08-12',
        scheduledDate: DateTime(2026, 8, 12),
      ),
    );
    final running = (await tasks.getTask(runningTaskId))!;
    await tasks.changeStatus(running, 'running');
    final completedTaskId = await tasks.createTask(
      TaskDraft(
        title: 'Already completed',
        templateId: templateId,
        occurrenceKey: '2026-08-12-complete',
        scheduledDate: DateTime(2026, 8, 12),
      ),
    );
    final completed = (await tasks.getTask(completedTaskId))!;
    await tasks.changeStatus(completed, 'completed');

    final vacationId = await vacations.create(
      VacationPeriodDraft(
        title: 'Summer holiday',
        startsOn: DateTime(2026, 8, 10),
        endsOn: DateTime(2026, 8, 12),
      ),
    );
    expect(await service.reconcileUpcoming(), 1);

    final adjusted = (await tasks.getTask(futureTaskId))!;
    expect(adjusted.scheduledDate, DateTime(2026, 8, 14));
    expect(adjusted.plannedStart, DateTime(2026, 8, 14, 9));
    expect(adjusted.plannedEnd, DateTime(2026, 8, 14, 9, 25));
    expect(adjusted.dueAt, DateTime(2026, 8, 14, 17, 30));
    expect(adjusted.revision, 2);

    // A JSONB round-trip can reorder object keys. Semantic equality must not
    // manufacture another task revision just to restore serialization order.
    final reordered = jsonDecode(adjusted.dataJson) as Map<String, dynamic>;
    final reversed = <String, Object?>{
      for (final key in reordered.keys.toList().reversed) key: reordered[key],
    };
    await (database.update(database.localTasks)
          ..where((row) => row.id.equals(futureTaskId)))
        .write(LocalTasksCompanion(dataJson: Value(jsonEncode(reversed))));
    expect(await service.reconcileUpcoming(), 0);
    expect((await tasks.getTask(futureTaskId))!.revision, 2);
    expect((await tasks.getTask(pastTaskId))!.revision, 1);
    expect((await tasks.getTask(runningTaskId))!.status, 'running');
    expect((await tasks.getTask(completedTaskId))!.status, 'completed');

    final period = (await vacations.list()).singleWhere(
      (item) => item.id == vacationId,
    );
    await vacations.setEnabled(period, false);
    expect(await service.reconcileUpcoming(), 1);
    final restored = (await tasks.getTask(futureTaskId))!;
    expect(restored.scheduledDate, DateTime(2026, 8, 11));
    expect(restored.plannedStart, DateTime(2026, 8, 11, 9));
    expect(
      (jsonDecode(restored.dataJson) as Map),
      isNot(contains(vacationAdjustmentKey)),
    );
  });

  test(
    'vacation removal restores owned dates but preserves manual edits',
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
      final service = VacationSchedulingService(
        database: database,
        tasks: tasks,
        vacations: vacations,
        now: () => DateTime(2026, 8, 1),
      );
      const templateId = 'template';
      final ownedId = await tasks.createTask(
        TaskDraft(
          title: 'Owned adjustment',
          templateId: templateId,
          occurrenceKey: '2026-08-10',
          scheduledDate: DateTime(2026, 8, 10),
        ),
      );
      final manualId = await tasks.createTask(
        TaskDraft(
          title: 'Manual adjustment',
          templateId: templateId,
          occurrenceKey: '2026-08-11',
          scheduledDate: DateTime(2026, 8, 11),
        ),
      );
      await vacations.create(
        VacationPeriodDraft(
          title: 'Holiday',
          startsOn: DateTime(2026, 8, 10),
          endsOn: DateTime(2026, 8, 11),
        ),
      );
      expect(await service.reconcileUpcoming(), 2);
      await tasks.reschedule(
        (await tasks.getTask(manualId))!,
        DateTime(2026, 8, 20),
      );

      // Reconciliation notices the user-owned schedule and removes only its
      // provenance marker. It never moves the task back under vacation control.
      expect(await service.reconcileUpcoming(), 1);
      expect(
        (await tasks.getTask(manualId))!.scheduledDate,
        DateTime(2026, 8, 20),
      );
      final manualData =
          jsonDecode((await tasks.getTask(manualId))!.dataJson) as Map;
      expect(manualData, isNot(contains(vacationAdjustmentKey)));

      final period = (await vacations.list()).single;
      await vacations.delete(period);
      expect(await service.reconcileUpcoming(), 1);
      expect(
        (await tasks.getTask(ownedId))!.scheduledDate,
        DateTime(2026, 8, 10),
      );
      expect(
        (await tasks.getTask(manualId))!.scheduledDate,
        DateTime(2026, 8, 20),
      );
    },
  );

  test(
    'vacation stream adjusts future occurrences without an app restart',
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
      final service = VacationSchedulingService(
        database: database,
        tasks: tasks,
        vacations: vacations,
        now: () => DateTime(2026, 8, 1),
      );
      final templateId = await entities.create(
        const EntityRecordDraft(
          entityType: 'task_templates',
          title: 'Synced daily routine',
        ),
      );
      final taskId = await tasks.createTask(
        TaskDraft(
          title: 'Synced daily routine',
          templateId: templateId,
          occurrenceKey: '2026-08-10',
          scheduledDate: DateTime(2026, 8, 10),
          plannedStart: DateTime(2026, 8, 10, 9),
        ),
      );
      final drained = Completer<void>();
      final coordinator = VacationScheduleCoordinator(
        changes: vacations.watch(),
        reconcile: service.reconcileUpcoming,
        generate: () async => 0,
        drain: () async {
          if (!drained.isCompleted) drained.complete();
        },
        debounce: const Duration(milliseconds: 1),
      )..start();
      addTearDown(coordinator.dispose);

      // This is the same local projection stream used when canonical rows
      // arrive from another device. No restart or manual synchronization call
      // is made after the new period appears.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await vacations.create(
        VacationPeriodDraft(
          title: 'Remote vacation',
          startsOn: DateTime(2026, 8, 10),
          endsOn: DateTime(2026, 8, 11),
        ),
      );
      await drained.future.timeout(const Duration(seconds: 3));

      final adjusted = (await tasks.getTask(taskId))!;
      expect(adjusted.scheduledDate, DateTime(2026, 8, 12));
      expect(adjusted.plannedStart, DateTime(2026, 8, 12, 9));
    },
  );

  test(
    'vacation coordinator stops before an account database closes',
    () async {
      final changes = StreamController<Object?>();
      var reconciliations = 0;
      final coordinator = VacationScheduleCoordinator(
        changes: changes.stream,
        reconcile: () async {
          reconciliations++;
          return 0;
        },
        generate: () async => 0,
        drain: () async {},
        debounce: const Duration(milliseconds: 1),
      )..start();

      await coordinator.dispose();
      changes.add('next-account');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reconciliations, 0);
      await changes.close();
    },
  );
}

VacationPeriod _period({
  required String id,
  required DateTime startsOn,
  required DateTime endsOn,
  required VacationTaskPolicy policy,
  VacationRecurrence recurrence = VacationRecurrence.none,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return VacationPeriod(
    id: id,
    title: id,
    startsOn: startsOn,
    endsOn: endsOn,
    recurrence: recurrence,
    interval: 1,
    taskPolicy: policy,
    taskScope: VacationTaskScope.allRecurring,
    selectedTemplateIds: const {},
    enabled: true,
    record: LocalEntityRecord(
      id: id,
      userId: 'owner',
      entityType: VacationRepository.entityType,
      title: id,
      status: 'active',
      position: 0,
      dataJson: '{}',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    ),
  );
}
