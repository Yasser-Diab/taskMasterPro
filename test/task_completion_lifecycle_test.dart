import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/roadmaps/data/roadmap_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SupabaseClient client;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
    );
    now = DateTime.utc(2026, 7, 28, 12);
  });

  tearDown(() => database.close());

  TaskRepository repository({
    Future<void> Function(String roadmapId)? recalculateRoadmap,
  }) {
    return TaskRepository(
      database,
      client,
      clock: () => now,
      recalculateRoadmap: recalculateRoadmap,
    );
  }

  test(
    'active completion finalizes task runtime session history and outbox',
    () async {
      final tasks = repository();
      final taskId = await tasks.createTask(
        TaskDraft(
          title: 'Finish the production repair',
          executionMode: 'pomodoro',
          scheduledDate: now,
          estimatedDuration: const Duration(minutes: 30),
        ),
      );
      var task = (await tasks.getTask(taskId))!;
      await tasks.start(task);
      task = (await tasks.getTask(taskId))!;
      final runtime = await database
          .select(database.localRuntimeStates)
          .getSingle();

      // Completing during a break must preserve only accumulated focus time.
      await (database.update(
        database.localRuntimeStates,
      )..where((row) => row.id.equals(runtime.id))).write(
        LocalRuntimeStatesCompanion(
          state: const Value('break'),
          segmentStartedAt: Value(now.subtract(const Duration(hours: 1))),
          accumulatedActiveMs: const Value(12 * 60 * 1000),
        ),
      );

      final results = await Future.wait([
        tasks.complete(task),
        tasks.complete(task),
      ]);
      final result = results.first;
      final completed = (await tasks.getTask(taskId))!;
      final completedRuntime = await database
          .select(database.localRuntimeStates)
          .getSingle();
      final session =
          await (database.select(database.localEntityRecords)..where(
                (row) =>
                    row.entityType.equals('execution_sessions') &
                    row.parentId.equals(taskId),
              ))
              .getSingle();
      final snapshots =
          await (database.select(database.localEntityRecords)..where(
                (row) =>
                    row.entityType.equals('task_completion_evidence') &
                    row.parentId.equals(taskId) &
                    row.status.equals('undoable'),
              ))
              .get();
      final evidence = await _lifecycleEvents(database, taskId);
      final completeCommands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('execution_runtime') &
                    row.commandType.equals('complete'),
              ))
              .get();
      final evidenceCommands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('task_completion_evidence') &
                    row.commandType.equals('create'),
              ))
              .get();

      expect(result.snapshotId, isNotEmpty);
      expect(results.last.snapshotId, result.snapshotId);
      expect(result.undoExpiresAt, now.add(const Duration(seconds: 15)));
      expect(completed.status, 'completed');
      expect(completed.progress, 1);
      expect(completed.activeDurationMs, 12 * 60 * 1000);
      expect(completed.actualFinish?.toUtc(), now);
      expect(completedRuntime.state, 'idle');
      expect(completedRuntime.activeTaskId, isNull);
      expect(completedRuntime.sessionId, isNull);
      expect(completedRuntime.accumulatedActiveMs, 12 * 60 * 1000);
      expect(session.status, 'completed');
      expect(jsonDecode(session.dataJson)['accumulated_active_ms'], 720000);
      expect(snapshots.single.status, 'undoable');
      expect(evidence, ['completed']);
      expect(completeCommands, hasLength(1));
      expect(evidenceCommands, hasLength(2));
      expect(
        evidenceCommands.any(
          (command) => command.payloadJson.contains('"completed"'),
        ),
        isTrue,
      );
      expect(
        await tasks.watchTodayTasks(now).first,
        isEmpty,
        reason: 'completed tasks must leave Today immediately',
      );

      now = now.add(const Duration(seconds: 5));
      expect(
        await tasks.undoCompletion(taskId, snapshotId: result.snapshotId),
        TaskRestorationOutcome.restored,
      );
      final restored = (await tasks.getTask(taskId))!;
      final safeRuntime = await database
          .select(database.localRuntimeStates)
          .getSingle();
      expect(restored.status, 'paused');
      expect(restored.activeDurationMs, 12 * 60 * 1000);
      expect(safeRuntime.state, 'idle');
      expect(safeRuntime.activeTaskId, isNull);
      expect(await _lifecycleEvents(database, taskId), [
        'completed',
        'completion_undone',
      ]);
    },
  );

  test('Pomodoro completion records one capped final focus boundary', () async {
    final tasks = repository();
    final taskId = await tasks.createTask(
      TaskDraft(
        title: 'Finish one focus interval',
        executionMode: 'pomodoro',
        scheduledDate: now,
        estimatedDuration: const Duration(hours: 1),
        configuration: const {'pomodoro_focus_ms': 25 * 60 * 1000},
      ),
    );
    var task = (await tasks.getTask(taskId))!;
    await tasks.start(task);
    task = (await tasks.getTask(taskId))!;
    final runtime = await database
        .select(database.localRuntimeStates)
        .getSingle();
    await (database.update(
      database.localRuntimeStates,
    )..where((row) => row.id.equals(runtime.id))).write(
      LocalRuntimeStatesCompanion(
        state: const Value('running'),
        segmentStartedAt: Value(now.subtract(const Duration(minutes: 40))),
        accumulatedActiveMs: const Value(0),
      ),
    );

    await tasks.complete(task);

    final completed = (await tasks.getTask(taskId))!;
    final boundaries =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.entityType.equals('pomodoro_cycles') &
                  row.secondaryParentId.equals(taskId),
            ))
            .get();
    final boundaryData = jsonDecode(boundaries.single.dataJson) as Map;
    expect(completed.activeDurationMs, 25 * 60 * 1000);
    expect(boundaries, hasLength(1));
    expect(boundaryData['focus_duration_ms'], 25 * 60 * 1000);
    expect(boundaryData['break_duration_ms'], 0);
    expect(boundaryData['boundary_reason'], 'task_completed');
  });

  test(
    'Undo restores safely, records history, and recalculates roadmap progress',
    () async {
      final roadmaps = RoadmapRepository(database, client);
      final tasks = repository(
        recalculateRoadmap: roadmaps.recalculateProgress,
      );
      final roadmapId = await roadmaps.createRoadmap(
        const RoadmapDraft(title: 'Release TaskMaster Pro'),
      );
      final taskId = await tasks.createTask(
        TaskDraft(
          title: 'Pass release validation',
          scheduledDate: now,
          estimatedDuration: const Duration(minutes: 30),
          roadmapId: roadmapId,
        ),
      );
      final task = (await tasks.getTask(taskId))!;
      final completion = await tasks.complete(task);
      var roadmap = await database.select(database.localRoadmaps).getSingle();
      expect(roadmap.progress, greaterThan(0));

      now = now.add(const Duration(seconds: 10));
      final outcome = await tasks.undoCompletion(
        taskId,
        snapshotId: completion.snapshotId,
      );

      final restored = (await tasks.getTask(taskId))!;
      roadmap = await database.select(database.localRoadmaps).getSingle();
      expect(outcome, TaskRestorationOutcome.restored);
      expect(restored.status, 'ready');
      expect(restored.actualFinish, isNull);
      expect(restored.progress, 0);
      expect(restored.activeDurationMs, 0);
      expect(roadmap.progress, 0);
      expect(await _lifecycleEvents(database, taskId), [
        'completed',
        'completion_undone',
      ]);
      expect(
        (await tasks.watchTodayTasks(now).first).map((item) => item.id),
        contains(taskId),
      );
    },
  );

  test('expired Undo requires reopen and preserves recorded work', () async {
    final tasks = repository();
    final taskId = await tasks.createTask(
      TaskDraft(
        title: 'Review completed work',
        scheduledDate: now,
        estimatedDuration: const Duration(minutes: 20),
      ),
    );
    final task = (await tasks.getTask(taskId))!;
    final completion = await tasks.complete(task);

    now = now.add(const Duration(seconds: 16));
    expect(
      await tasks.undoCompletion(taskId, snapshotId: completion.snapshotId),
      TaskRestorationOutcome.undoExpired,
    );
    expect(
      await tasks.reopen(taskId, snapshotId: completion.snapshotId),
      TaskRestorationOutcome.restored,
    );

    final reopened = (await tasks.getTask(taskId))!;
    expect(reopened.status, 'ready');
    expect(reopened.actualFinish, isNull);
    expect(reopened.activeDurationMs, task.activeDurationMs);
    expect(await _lifecycleEvents(database, taskId), ['completed', 'reopened']);
  });
}

Future<List<String>> _lifecycleEvents(
  AppDatabase database,
  String taskId,
) async {
  final records =
      await (database.select(database.localEntityRecords)
            ..where(
              (row) =>
                  row.entityType.equals('task_completion_evidence') &
                  row.parentId.equals(taskId),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();
  return records.expand((record) {
    final data = jsonDecode(record.dataJson) as Map;
    if (data['evidence_type'] != 'lifecycle_event') {
      return const <String>[];
    }
    final metadata = data['evidence_metadata'];
    final eventType = metadata is Map ? metadata['event_type'] : null;
    return eventType is String ? <String>[eventType] : const <String>[];
  }).toList();
}
