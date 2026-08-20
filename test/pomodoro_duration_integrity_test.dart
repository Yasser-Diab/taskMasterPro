import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DateTime now;
  late TaskRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 8, 17, 6);
    repository = TaskRepository(
      database,
      SupabaseClient('https://example.supabase.co', 'sb_publishable_test_key'),
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  test(
    'offline Start then Pause freezes 10:47 instead of server delivery time',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Offline focus',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': 1500000},
        ),
      );
      await repository.start((await repository.getTask(taskId))!);

      now = now.add(const Duration(minutes: 10, seconds: 47));
      await repository.pause((await repository.getTask(taskId))!);

      final task = (await repository.getTask(taskId))!;
      final command =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('execution_runtime') &
                    row.commandType.equals('pause'),
              ))
              .getSingle();
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;

      expect(task.status, 'paused');
      expect(task.activeDurationMs, 647000);
      expect(payload['projected_active_ms'], 647000);
      expect(
        DateTime.parse(payload['projected_boundary_at'] as String).toUtc(),
        now,
      );
    },
  );

  test(
    'delayed Complete freezes one focus and paused time stays dead',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Bounded completion',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': 1500000},
        ),
      );
      await repository.start((await repository.getTask(taskId))!);

      now = now.add(const Duration(days: 3));
      await repository.complete((await repository.getTask(taskId))!);

      final task = (await repository.getTask(taskId))!;
      final command =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('execution_runtime') &
                    row.commandType.equals('complete'),
              ))
              .getSingle();
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;

      expect(task.status, 'completed');
      expect(task.activeDurationMs, 1500000);
      expect(payload['projected_active_ms'], 1500000);
      expect(
        DateTime.parse(payload['projected_boundary_at'] as String).toUtc(),
        now,
      );
    },
  );

  test(
    'offline focus and break boundaries keep their local timestamps',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Offline break',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': 1500000},
        ),
      );
      await repository.start((await repository.getTask(taskId))!);

      now = now.add(const Duration(minutes: 25));
      final focusBoundary = now;
      await repository.startBreak((await repository.getTask(taskId))!);
      now = now.add(const Duration(minutes: 5));
      final breakBoundary = now;
      await repository.finishBreak((await repository.getTask(taskId))!);

      final commands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('execution_runtime') &
                    row.commandType.isIn(const ['start_break', 'finish_break']),
              ))
              .get();
      Map<String, dynamic> payload(String action) =>
          jsonDecode(
                commands
                    .singleWhere((row) => row.commandType == action)
                    .payloadJson,
              )
              as Map<String, dynamic>;

      expect(payload('start_break')['projected_active_ms'], 1500000);
      expect(
        DateTime.parse(
          payload('start_break')['projected_boundary_at'] as String,
        ).toUtc(),
        focusBoundary,
      );
      expect(payload('finish_break')['projected_active_ms'], 1500000);
      expect(
        DateTime.parse(
          payload('finish_break')['projected_boundary_at'] as String,
        ).toUtc(),
        breakBoundary,
      );
    },
  );

  test(
    'switching a stale Pomodoro records at most one focus interval',
    () async {
      final firstId = await repository.createTask(
        const TaskDraft(
          title: 'Bounded focus',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': 1500000},
        ),
      );
      final secondId = await repository.createTask(
        const TaskDraft(title: 'Next work'),
      );
      await repository.start((await repository.getTask(firstId))!);

      now = now.add(const Duration(days: 3));
      await repository.switchActiveTask(
        (await repository.getTask(secondId))!,
        action: ActiveTaskSwitchAction.pauseCurrent,
      );

      final first = (await repository.getTask(firstId))!;
      final session =
          await (database.select(database.localEntityRecords)..where(
                (row) =>
                    row.entityType.equals('execution_sessions') &
                    row.parentId.equals(firstId),
              ))
              .getSingle();
      final sessionData = jsonDecode(session.dataJson) as Map<String, dynamic>;

      expect(first.status, 'paused');
      expect(first.activeDurationMs, 1500000);
      expect(session.status, 'paused');
      expect(sessionData['accumulated_active_ms'], 1500000);
      final switchCommand =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('execution_runtime_switch') &
                    row.commandType.equals('pause_current'),
              ))
              .getSingle();
      final switchPayload =
          jsonDecode(switchCommand.payloadJson) as Map<String, dynamic>;
      expect(switchPayload['projected_active_ms'], 1500000);
      expect(
        DateTime.parse(
          switchPayload['projected_boundary_at'] as String,
        ).toUtc(),
        now,
      );
    },
  );

  test(
    'finishing during a delayed task switch also freezes one focus',
    () async {
      final firstId = await repository.createTask(
        const TaskDraft(
          title: 'Finish bounded focus',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': 1500000},
        ),
      );
      final secondId = await repository.createTask(
        const TaskDraft(title: 'Next after finish'),
      );
      await repository.start((await repository.getTask(firstId))!);

      now = now.add(const Duration(days: 3));
      await repository.switchActiveTask(
        (await repository.getTask(secondId))!,
        action: ActiveTaskSwitchAction.finishCurrent,
      );

      final first = (await repository.getTask(firstId))!;
      final command =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('execution_runtime_switch') &
                    row.commandType.equals('finish_current'),
              ))
              .getSingle();
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;

      expect(first.status, 'completed');
      expect(first.activeDurationMs, 1500000);
      expect(payload['projected_active_ms'], 1500000);
      expect(
        DateTime.parse(payload['projected_boundary_at'] as String).toUtc(),
        now,
      );
    },
  );

  test(
    'immutable completion evidence repairs all corrupted local projections',
    () async {
      const taskId = 'corrupt-task';
      const sessionId = 'corrupt-session';
      const completionCommand = 'completion-command';
      const boundaryCommand = 'boundary-command';
      const corruptMs = 256031716;
      const safeMs = 3000000;
      final startedAt = DateTime.utc(2026, 8, 17, 7, 38, 39);
      final finishedAt = DateTime.utc(2026, 8, 20, 6, 20, 50);

      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: taskId,
              userId: 'local',
              title: 'Daily work routine',
              status: const Value('completed'),
              executionMode: const Value('pomodoro'),
              estimatedDurationMs: const Value(30600000),
              activeDurationMs: const Value(corruptMs),
              actualStart: Value(startedAt),
              actualFinish: Value(finishedAt),
              revision: const Value(8),
              createdAt: startedAt,
              updatedAt: finishedAt,
              lastCommandId: const Value(completionCommand),
            ),
          );
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: sessionId,
              userId: 'local',
              entityType: 'execution_sessions',
              parentId: const Value(taskId),
              status: const Value('completed'),
              dataJson: Value(
                jsonEncode({
                  'accumulated_active_ms': corruptMs,
                  'preserve': true,
                }),
              ),
              revision: const Value(7),
              createdAt: startedAt,
              updatedAt: finishedAt,
              lastCommandId: const Value(completionCommand),
            ),
          );
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: 'complete-event',
              userId: 'local',
              entityType: 'session_events',
              parentId: const Value(sessionId),
              dataJson: Value(
                jsonEncode({
                  'event_type': 'complete',
                  'duration_ms': corruptMs,
                }),
              ),
              createdAt: finishedAt,
              updatedAt: finishedAt,
              lastCommandId: const Value(completionCommand),
            ),
          );
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: 'completion-snapshot',
              userId: 'local',
              entityType: 'task_completion_evidence',
              parentId: const Value(taskId),
              status: const Value('undoable'),
              dataJson: Value(
                jsonEncode({
                  'evidence_type': 'completion_snapshot',
                  'evidence_metadata': {
                    'previous_runtime_session_id': sessionId,
                    'task_completion_command_id': completionCommand,
                    'pomodoro_boundary_command_id': boundaryCommand,
                    'completed_active_duration_ms': safeMs,
                  },
                }),
              ),
              createdAt: finishedAt,
              updatedAt: finishedAt,
            ),
          );
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: 'final-cycle',
              userId: 'local',
              entityType: 'pomodoro_cycles',
              parentId: const Value(sessionId),
              status: const Value('completed'),
              dataJson: Value(
                jsonEncode({
                  'focus_started_at': startedAt.toIso8601String(),
                  'focus_ended_at': finishedAt.toIso8601String(),
                  'focus_duration_ms': 1500000,
                  'boundary_reason': 'task_completed',
                }),
              ),
              createdAt: finishedAt,
              updatedAt: finishedAt,
              lastCommandId: const Value(boundaryCommand),
            ),
          );
      await database
          .into(database.localRuntimeStates)
          .insert(
            LocalRuntimeStatesCompanion.insert(
              id: localRuntimeStateId('local'),
              userId: 'local',
              state: const Value('idle'),
              accumulatedActiveMs: const Value(corruptMs),
              revision: const Value(43),
              updatedAt: finishedAt,
              lastCommandId: const Value(completionCommand),
            ),
          );

      await database.repairCorruptedPomodoroCompletionDurations();
      await database.repairCorruptedPomodoroCompletionDurations();

      final task = await (database.select(
        database.localTasks,
      )..where((row) => row.id.equals(taskId))).getSingle();
      final records = await database.select(database.localEntityRecords).get();
      Map<String, dynamic> data(String id) =>
          jsonDecode(records.singleWhere((record) => record.id == id).dataJson)
              as Map<String, dynamic>;
      final runtime = await database
          .select(database.localRuntimeStates)
          .getSingle();
      final cycle = data('final-cycle');

      expect(task.activeDurationMs, safeMs);
      expect(task.revision, 8);
      expect(data(sessionId)['accumulated_active_ms'], safeMs);
      expect(data(sessionId)['preserve'], isTrue);
      expect(records.singleWhere((row) => row.id == sessionId).revision, 7);
      expect(data('complete-event')['duration_ms'], safeMs);
      expect(runtime.accumulatedActiveMs, safeMs);
      expect(runtime.revision, 43);
      expect(
        DateTime.parse(cycle['focus_ended_at'] as String).toUtc(),
        startedAt.add(const Duration(minutes: 25)),
      );
    },
  );

  test(
    'zero duration is valid repair evidence but malformed text is ignored',
    () async {
      final timestamp = DateTime.utc(2026, 8, 20, 8);
      for (final entry in const [
        (taskId: 'zero-task', commandId: 'zero-command', value: 0),
        (
          taskId: 'malformed-task',
          commandId: 'malformed-command',
          value: 'not-a-duration',
        ),
      ]) {
        await database
            .into(database.localTasks)
            .insert(
              LocalTasksCompanion.insert(
                id: entry.taskId,
                userId: 'local',
                title: entry.taskId,
                status: const Value('completed'),
                executionMode: const Value('pomodoro'),
                activeDurationMs: const Value(300000),
                revision: const Value(2),
                createdAt: timestamp,
                updatedAt: timestamp,
                lastCommandId: Value(entry.commandId),
              ),
            );
        await database
            .into(database.localEntityRecords)
            .insert(
              LocalEntityRecordsCompanion.insert(
                id: '${entry.taskId}-evidence',
                userId: 'local',
                entityType: 'task_completion_evidence',
                parentId: Value(entry.taskId),
                dataJson: Value(
                  jsonEncode({
                    'evidence_type': 'completion_snapshot',
                    'evidence_metadata': {
                      'previous_runtime_session_id': '${entry.taskId}-session',
                      'task_completion_command_id': entry.commandId,
                      'completed_active_duration_ms': entry.value,
                    },
                  }),
                ),
                createdAt: timestamp,
                updatedAt: timestamp,
              ),
            );
      }

      await database.repairCorruptedPomodoroCompletionDurations();

      final tasks = await database.select(database.localTasks).get();
      expect(
        tasks.singleWhere((task) => task.id == 'zero-task').activeDurationMs,
        0,
      );
      expect(
        tasks
            .singleWhere((task) => task.id == 'malformed-task')
            .activeDurationMs,
        300000,
      );
    },
  );

  test('v0032 guards every projection and repairs stale retry payloads', () {
    final migration = File(
      'supabase/migrations/20260820083000_v0032_pomodoro_duration_integrity.sql',
    ).readAsStringSync();

    expect(migration, contains('aaa_cap_pomodoro_session_active_duration'));
    expect(migration, contains('aaa_cap_pomodoro_task_active_duration'));
    expect(migration, contains('aaa_cap_pomodoro_runtime_active_duration'));
    expect(migration, contains('aa0_cap_execution_event_active_duration'));
    expect(migration, contains('apply_execution_transition_v0032_command'));
    expect(migration, contains('apply_execution_switch_v0032_command'));
    expect(migration, contains("'taskmaster.projected_active_ms'"));
    expect(migration, contains("'taskmaster.boundary_at'"));
    expect(migration, contains('new.duration_ms := safe_active_ms'));
    expect(
      migration,
      contains('when projected_active_ms is not null then focus_remaining_ms'),
    );
    expect(migration, contains('completed_active_duration_ms'));
    expect(migration, contains("event_row.event_type::text = 'complete'"));
    expect(migration, contains("cycle_row.data ->> 'boundary_reason'"));
    expect(
      migration,
      contains("command_row.result, '{}'::jsonb) - 'canonical_runtime'"),
    );
    expect(migration, contains('drop table taskmaster_v0032_duration_repairs'));
  });
}
