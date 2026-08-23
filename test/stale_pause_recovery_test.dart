import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/domain/pomodoro_execution_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DateTime now;
  late TaskRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 8, 22, 6);
    repository = TaskRepository(
      database,
      SupabaseClient('https://example.supabase.co', 'sb_publishable_test_key'),
      clock: () => now,
    );
  });

  tearDown(() => database.close());

  test(
    'twelve-hour boundary returns a paused task without adding work',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Forgotten focus',
          executionMode: 'continuous',
          estimatedDuration: Duration(hours: 2),
        ),
      );
      await repository.start((await repository.getTask(taskId))!);
      now = now.add(const Duration(minutes: 18));
      await repository.pause((await repository.getTask(taskId))!);
      final paused = (await repository.getTask(taskId))!;
      final pausedRuntime = (await repository.getRuntime())!;

      now = now.add(const Duration(hours: 11, minutes: 59));
      expect(
        isStalePausedTask(task: paused, runtime: pausedRuntime, now: now),
        isFalse,
      );
      expect(
        await repository.resolveStalePausedTask(
          paused,
          StalePausedTaskDecision.needsAttention,
        ),
        isFalse,
      );

      now = now.add(const Duration(minutes: 1));
      expect(
        isStalePausedTask(task: paused, runtime: pausedRuntime, now: now),
        isTrue,
      );
      expect(
        await repository.resolveStalePausedTask(
          paused,
          StalePausedTaskDecision.needsAttention,
        ),
        isTrue,
      );

      final resolved = (await repository.getTask(taskId))!;
      final storedRuntime = await (database.select(
        database.localRuntimeStates,
      )).getSingle();
      final session =
          await (database.select(database.localEntityRecords)..where(
                (row) =>
                    row.entityType.equals('execution_sessions') &
                    row.parentId.equals(taskId),
              ))
              .getSingle();
      final command =
          await (database.select(database.localOutboxCommands)..where(
                (row) => row.entityType.equals('execution_runtime_stale_pause'),
              ))
              .getSingle();
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;

      expect(resolved.status, 'waiting_review');
      expect(
        resolved.activeDurationMs,
        const Duration(minutes: 18).inMilliseconds,
      );
      expect(storedRuntime.state, 'idle');
      expect(storedRuntime.activeTaskId, isNull);
      expect(storedRuntime.accumulatedActiveMs, resolved.activeDurationMs);
      expect(session.status, 'cancelled');
      expect(payload['decision'], 'needs_attention');
      expect(payload['expected_runtime_revision'], pausedRuntime.revision);
    },
  );

  test(
    'skipping an old paused task never interrupts a newer running task',
    () async {
      final firstId = await repository.createTask(
        const TaskDraft(title: 'First task', executionMode: 'continuous'),
      );
      final secondId = await repository.createTask(
        const TaskDraft(title: 'Second task', executionMode: 'continuous'),
      );
      await repository.start((await repository.getTask(firstId))!);
      now = now.add(const Duration(minutes: 10));
      await repository.pause((await repository.getTask(firstId))!);
      await repository.switchActiveTask(
        (await repository.getTask(secondId))!,
        action: ActiveTaskSwitchAction.pauseCurrent,
      );
      final runningBefore = (await repository.getRuntime())!;
      expect(runningBefore.activeTaskId, secondId);
      final firstPaused = (await repository.getTask(firstId))!;
      final firstSession =
          await (database.select(database.localEntityRecords)..where(
                (row) =>
                    row.entityType.equals('execution_sessions') &
                    row.parentId.equals(firstId),
              ))
              .getSingle();
      final firstSessionData =
          jsonDecode(firstSession.dataJson) as Map<String, dynamic>
            ..['accumulated_active_ms'] = const Duration(
              minutes: 18,
            ).inMilliseconds;
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(firstSession.id))).write(
        LocalEntityRecordsCompanion(
          dataJson: Value(jsonEncode(firstSessionData)),
        ),
      );

      now = now.add(stalePausedTaskThreshold);
      expect(
        await repository.resolveStalePausedTask(
          firstPaused,
          StalePausedTaskDecision.skip,
        ),
        isTrue,
      );

      final firstAfter = (await repository.getTask(firstId))!;
      final runningAfter = (await repository.getRuntime())!;
      expect(firstAfter.status, 'skipped');
      expect(
        firstAfter.activeDurationMs,
        const Duration(minutes: 18).inMilliseconds,
      );
      expect(
        (jsonDecode(firstAfter.dataJson)
            as Map<String, dynamic>)['occurrence_state'],
        'skipped',
      );
      expect(runningAfter.activeTaskId, secondId);
      expect(runningAfter.sessionId, runningBefore.sessionId);
      expect(runningAfter.revision, runningBefore.revision);
      expect(runningAfter.state, 'running');
    },
  );

  test(
    'Pomodoro stale resolution preserves the persisted session boundary',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Bounded focus',
          executionMode: 'pomodoro',
          estimatedDuration: Duration(hours: 1),
          configuration: {'pomodoro_focus_ms': 1500000},
        ),
      );
      await repository.start((await repository.getTask(taskId))!);
      now = now.add(const Duration(minutes: 18));
      await repository.pause((await repository.getTask(taskId))!);

      final pausedTask = (await repository.getTask(taskId))!;
      final pausedRuntime = (await repository.getRuntime())!;
      final pausedSession =
          await (database.select(database.localEntityRecords)..where(
                (row) =>
                    row.entityType.equals('execution_sessions') &
                    row.parentId.equals(taskId),
              ))
              .getSingle();
      final sessionData =
          jsonDecode(pausedSession.dataJson) as Map<String, dynamic>;
      expect(
        sessionData['accumulated_active_ms'],
        const Duration(minutes: 18).inMilliseconds,
      );

      // Simulate a partial snapshot in which the session boundary arrived
      // before the mutable task/runtime projections.
      await (database.update(
        database.localTasks,
      )..where((row) => row.id.equals(taskId))).write(
        LocalTasksCompanion(
          activeDurationMs: Value(const Duration(minutes: 5).inMilliseconds),
        ),
      );
      await (database.update(
        database.localRuntimeStates,
      )..where((row) => row.id.equals(pausedRuntime.id))).write(
        LocalRuntimeStatesCompanion(
          accumulatedActiveMs: Value(const Duration(minutes: 7).inMilliseconds),
        ),
      );

      now = now.add(stalePausedTaskThreshold);
      expect(
        await repository.resolveStalePausedTask(
          pausedTask,
          StalePausedTaskDecision.needsAttention,
        ),
        isTrue,
      );

      final resolvedTask = (await repository.getTask(taskId))!;
      final resolvedRuntime = await (database.select(
        database.localRuntimeStates,
      )).getSingle();
      expect(
        resolvedTask.activeDurationMs,
        const Duration(minutes: 18).inMilliseconds,
      );
      expect(
        resolvedRuntime.accumulatedActiveMs,
        resolvedTask.activeDurationMs,
      );
      expect(
        resolvedTask.activeDurationMs,
        lessThanOrEqualTo(const Duration(minutes: 25).inMilliseconds),
      );
    },
  );

  test('v0034 server command is guarded, idempotent, and owner scoped', () {
    final source = File(
      'supabase/migrations/20260822203435_v0034_stale_paused_task_decisions.sql',
    ).readAsStringSync();

    expect(source, contains("interval '12 hours'"));
    expect(source, contains("p_decision not in ('needs_attention', 'skip')"));
    expect(source, contains("runtime_row.user_id = owner_id"));
    expect(source, contains('task_row.revision = p_expected_task_revision'));
    expect(source, contains('session_active_ms bigint := 0'));
    expect(source, contains('session_record.accumulated_active_ms'));
    expect(source, contains('public.processed_commands'));
    expect(source, contains('security definer'));
    expect(source, contains('security invoker'));
    expect(source, contains('from public, anon'));
    expect(source, contains('to authenticated'));
    expect(source, isNot(contains('recurrence_rules')));
    expect(source, isNot(contains('task_templates')));
  });
}
