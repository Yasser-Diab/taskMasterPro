import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TaskRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    repository = TaskRepository(
      database,
      SupabaseClient('https://example.supabase.co', 'sb_publishable_test_key'),
    );
  });

  tearDown(() => database.close());

  test(
    'a tombstoned active task cannot block the next selected task',
    () async {
      final deletedTaskId = await repository.createTask(
        const TaskDraft(title: 'Deleted test task'),
      );
      var deletedTask = (await repository.getTask(deletedTaskId))!;
      await repository.start(deletedTask);
      final ghostRuntime = await database
          .select(database.localRuntimeStates)
          .getSingle();
      expect(ghostRuntime.activeTaskId, deletedTaskId);

      await (database.update(
        database.localTasks,
      )..where((row) => row.id.equals(deletedTaskId))).write(
        LocalTasksCompanion(
          deletedAt: drift.Value(DateTime.utc(2026, 7, 28, 20)),
        ),
      );

      final selectedTaskId = await repository.createTask(
        const TaskDraft(title: 'German structured lesson'),
      );
      final selectedTask = (await repository.getTask(selectedTaskId))!;
      final result = await repository.start(selectedTask);

      expect(result.requiresSwitch, isFalse);
      final repaired = await database
          .select(database.localRuntimeStates)
          .getSingle();
      expect(repaired.activeTaskId, selectedTaskId);
      expect(repaired.activeTaskId, isNot(deletedTaskId));
      expect(repaired.state, 'running');
    },
  );

  test(
    'a runtime whose execution session is missing self-heals to idle',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(title: 'Task with missing session'),
      );
      final now = DateTime.utc(2026, 7, 28, 20);
      await database
          .into(database.localRuntimeStates)
          .insert(
            LocalRuntimeStatesCompanion.insert(
              id: localRuntimeStateId('local'),
              userId: 'local',
              activeTaskId: drift.Value(taskId),
              sessionId: const drift.Value('missing-session'),
              state: const drift.Value('paused'),
              updatedAt: now,
            ),
          );

      expect(await repository.getRuntime(), isNull);
      final repaired = await database
          .select(database.localRuntimeStates)
          .getSingle();
      expect(repaired.state, 'idle');
      expect(repaired.activeTaskId, isNull);
      expect(repaired.sessionId, isNull);
    },
  );

  test(
    'a canonical runtime arriving early can be restored after its references',
    () async {
      const taskId = 'canonical-task';
      const sessionId = 'canonical-session';
      final now = DateTime.utc(2026, 7, 28, 20);
      await database
          .into(database.localRuntimeStates)
          .insert(
            LocalRuntimeStatesCompanion.insert(
              id: localRuntimeStateId('local'),
              userId: 'local',
              activeTaskId: const drift.Value(taskId),
              sessionId: const drift.Value(sessionId),
              state: const drift.Value('paused'),
              revision: const drift.Value(7),
              updatedAt: now,
            ),
          );

      expect(await repository.getRuntime(), isNull);

      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: taskId,
              userId: 'local',
              title: 'Canonical task',
              status: const drift.Value('paused'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: sessionId,
              userId: 'local',
              entityType: 'execution_sessions',
              parentId: const drift.Value(taskId),
              title: const drift.Value('Canonical task session'),
              status: const drift.Value('paused'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (database.update(
        database.localRuntimeStates,
      )..where((row) => row.id.equals(localRuntimeStateId('local')))).write(
        const LocalRuntimeStatesCompanion(
          activeTaskId: drift.Value(taskId),
          sessionId: drift.Value(sessionId),
          state: drift.Value('paused'),
          revision: drift.Value(7),
        ),
      );

      final restored = await repository.getRuntime();
      expect(restored, isNotNull);
      expect(restored!.activeTaskId, taskId);
      expect(restored.sessionId, sessionId);
      expect(restored.revision, 7);
    },
  );

  test(
    'deleting the active task atomically cancels its local execution state',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(title: 'Disposable running task'),
      );
      var task = (await repository.getTask(taskId))!;
      await repository.start(task);
      final active = await repository.getRuntime();
      expect(active, isNotNull);
      final activeSessionId = active!.sessionId!;

      task = (await repository.getTask(taskId))!;
      await repository.softDelete(task);

      expect(await repository.getTask(taskId), isNull);
      final runtime = await database
          .select(database.localRuntimeStates)
          .getSingle();
      expect(runtime.state, 'idle');
      expect(runtime.activeTaskId, isNull);
      expect(runtime.sessionId, isNull);

      final session = await (database.select(
        database.localEntityRecords,
      )..where((row) => row.id.equals(activeSessionId))).getSingle();
      expect(session.status, 'cancelled');

      final executionCommands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityId.equals(activeSessionId) &
                    row.entityType.isIn(const [
                      'execution_sessions',
                      'execution_runtime',
                      'execution_runtime_switch',
                    ]),
              ))
              .get();
      expect(executionCommands, isNotEmpty);
      expect(
        executionCommands.every((command) => command.status == 'superseded'),
        isTrue,
      );
    },
  );
}
