import 'dart:convert';
import 'dart:io';

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

  Future<List<LocalOutboxCommand>> runtimeCommands() {
    return (database.select(database.localOutboxCommands)
          ..where((row) => row.entityType.equals('execution_runtime'))
          ..orderBy([(row) => drift.OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  test(
    'optimistic runtime state and outbox transition share one command identity',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(title: 'Identity test'),
      );
      var task = (await repository.getTask(taskId))!;

      await repository.start(task);
      final started = (await repository.getRuntime())!;
      final commandsAfterStart = await runtimeCommands();
      final start = commandsAfterStart.single;
      final startPayload =
          jsonDecode(start.payloadJson) as Map<String, dynamic>;

      expect(started.lastCommandId, start.commandId);
      expect(start.baseRevision, 1);
      expect(started.revision, start.baseRevision + 1);
      expect(startPayload['expected_runtime_revision'], start.baseRevision);

      task = (await repository.getTask(taskId))!;
      await repository.pause(task);
      final paused = (await repository.getRuntime())!;
      final commandsAfterPause = await runtimeCommands();
      final pause = commandsAfterPause.last;
      final pausePayload =
          jsonDecode(pause.payloadJson) as Map<String, dynamic>;

      expect(paused.lastCommandId, pause.commandId);
      expect(paused.revision, pause.baseRevision + 1);
      expect(pausePayload['expected_runtime_revision'], pause.baseRevision);
      expect(pause.commandId, isNot(start.commandId));
      expect(pause.deviceSequence, greaterThan(start.deviceSequence));
    },
  );

  test(
    'Start uses an idle stored runtime revision instead of revision zero',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(title: 'Restart after completion'),
      );
      final now = DateTime.now().toUtc();
      await database
          .into(database.localRuntimeStates)
          .insert(
            LocalRuntimeStatesCompanion.insert(
              id: localRuntimeStateId('local'),
              userId: 'local',
              state: const drift.Value('idle'),
              revision: const drift.Value(9),
              updatedAt: now,
              lastCommandId: const drift.Value('previous-command'),
            ),
          );

      await repository.start((await repository.getTask(taskId))!);

      final runtime = (await repository.getRuntime())!;
      final command = (await runtimeCommands()).single;
      expect(command.baseRevision, 9);
      expect(runtime.revision, 10);
      expect(runtime.lastCommandId, command.commandId);
    },
  );

  test('active-task switch persists the switch command identity', () async {
    final firstId = await repository.createTask(
      const TaskDraft(title: 'First task'),
    );
    final secondId = await repository.createTask(
      const TaskDraft(title: 'Second task'),
    );
    await repository.start((await repository.getTask(firstId))!);
    final before = (await repository.getRuntime())!;

    await repository.switchActiveTask(
      (await repository.getTask(secondId))!,
      action: ActiveTaskSwitchAction.pauseCurrent,
    );

    final runtime = (await repository.getRuntime())!;
    final command =
        await (database.select(database.localOutboxCommands)..where(
              (row) => row.entityType.equals('execution_runtime_switch'),
            ))
            .getSingle();
    final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;

    expect(command.baseRevision, before.revision);
    expect(payload['expected_runtime_revision'], before.revision);
    expect(runtime.revision, before.revision + 1);
    expect(runtime.lastCommandId, command.commandId);
  });

  test('skip offered break is one optimistic runtime command', () async {
    final taskId = await repository.createTask(
      const TaskDraft(
        title: 'Atomic skip',
        executionMode: 'pomodoro',
        configuration: {'pomodoro_focus_ms': 60000},
      ),
    );
    var task = (await repository.getTask(taskId))!;
    await repository.start(task);
    final before = (await repository.getRuntime())!;
    await (database.update(
      database.localRuntimeStates,
    )..where((row) => row.id.equals(before.id))).write(
      LocalRuntimeStatesCompanion(
        segmentStartedAt: drift.Value(
          DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        ),
      ),
    );

    task = (await repository.getTask(taskId))!;
    expect(await repository.skipOfferedBreak(task), isTrue);

    final runtime = (await repository.getRuntime())!;
    final commands = await runtimeCommands();
    final skip = commands.last;
    final payload = jsonDecode(skip.payloadJson) as Map<String, dynamic>;

    expect(
      commands.where((command) => command.commandType == 'skip_break'),
      hasLength(1),
    );
    expect(skip.commandType, 'skip_break');
    expect(payload['action'], 'skip_break');
    expect(payload['expected_runtime_revision'], skip.baseRevision);
    expect(runtime.state, 'running');
    expect(runtime.revision, skip.baseRevision + 1);
    expect(runtime.lastCommandId, skip.commandId);
  });

  test('v0028 migration contains the guarded atomic execution endpoints', () {
    final migration = File(
      'supabase/migrations/20260810043734_v0028_expected_runtime_revision.sql',
    ).readAsStringSync();

    expect(migration, contains('p_expected_runtime_revision bigint'));
    expect(migration, contains('stale_runtime_revision'));
    expect(migration, contains('canonical_runtime'));
    expect(migration, contains("if p_action = 'skip_break' then"));
    expect(migration, contains("'focus_not_complete'"));
    expect(migration, contains('apply_execution_switch_v0028_command'));

    final guard = migration.substring(
      migration.indexOf(
        'create function taskmaster_internal.guard_execution_runtime_v0028_command',
      ),
      migration.indexOf(
        'create function taskmaster_internal.apply_execution_transition_v0028_command',
      ),
    );
    expect(
      guard.indexOf('from public.processed_commands command_row'),
      lessThan(guard.indexOf('from public.account_devices device_row')),
      reason:
          'A retry must deduplicate before a later device revocation can turn an accepted runtime command into a failure.',
    );
  });
}
