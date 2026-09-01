import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/platform/android_home_widget_projection.dart';
import 'package:taskmaster_pro/core/platform/android_home_widget_service.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/domain/pomodoro_execution_state.dart';

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

  Future<List<LocalOutboxCommand>> allCommands() {
    return (database.select(
      database.localOutboxCommands,
    )..orderBy([(row) => drift.OrderingTerm.asc(row.deviceSequence)])).get();
  }

  Future<LocalEntityRecord> sessionFor(LocalRuntime runtime) {
    return (database.select(database.localEntityRecords)..where(
          (row) =>
              row.id.equals(runtime.sessionId!) &
              row.entityType.equals('execution_sessions'),
        ))
        .getSingle();
  }

  List<LocalOutboxCommand> commandsAfter(
    List<LocalOutboxCommand> before,
    List<LocalOutboxCommand> after,
  ) {
    final existing = before.map((command) => command.commandId).toSet();
    return after
        .where((command) => !existing.contains(command.commandId))
        .toList();
  }

  test(
    'optimistic runtime state and outbox transition share one command identity',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Identity test',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': 60000},
        ),
      );
      var task = (await repository.getTask(taskId))!;

      final beforeStart = await allCommands();
      await repository.start(task);
      final started = (await repository.getRuntime())!;
      final startedTask = (await repository.getTask(taskId))!;
      final startedSession = await sessionFor(started);
      final commandsAfterStart = await runtimeCommands();
      final start = commandsAfterStart.single;
      final startPayload =
          jsonDecode(start.payloadJson) as Map<String, dynamic>;
      final startDelta = commandsAfter(beforeStart, await allCommands());

      expect(
        startDelta.map((command) => command.entityType),
        orderedEquals(['execution_sessions', 'execution_runtime']),
      );
      expect(started.lastCommandId, start.commandId);
      expect(startedTask.lastCommandId, start.commandId);
      expect(startedSession.lastCommandId, start.commandId);
      expect(start.baseRevision, 1);
      expect(started.revision, start.baseRevision + 1);
      expect(startPayload['expected_runtime_revision'], start.baseRevision);

      task = (await repository.getTask(taskId))!;
      final beforePause = await allCommands();
      await repository.pause(task);
      final paused = (await repository.getRuntime())!;
      final pausedTask = (await repository.getTask(taskId))!;
      final pausedSession = await sessionFor(paused);
      final commandsAfterPause = await runtimeCommands();
      final pause = commandsAfterPause.last;
      final pausePayload =
          jsonDecode(pause.payloadJson) as Map<String, dynamic>;

      expect(
        commandsAfter(
          beforePause,
          await allCommands(),
        ).map((command) => command.entityType),
        orderedEquals(['execution_runtime']),
      );
      expect(paused.lastCommandId, pause.commandId);
      expect(pausedTask.lastCommandId, pause.commandId);
      expect(pausedSession.lastCommandId, pause.commandId);
      expect(paused.revision, pause.baseRevision + 1);
      expect(pausePayload['expected_runtime_revision'], pause.baseRevision);
      expect(pause.commandId, isNot(start.commandId));
      expect(pause.deviceSequence, greaterThan(start.deviceSequence));

      final beforeResume = await allCommands();
      await repository.resume(pausedTask);
      final resumed = (await repository.getRuntime())!;
      final resume = (await runtimeCommands()).last;
      expect(
        commandsAfter(
          beforeResume,
          await allCommands(),
        ).map((command) => command.entityType),
        orderedEquals(['execution_runtime']),
      );
      expect(
        (await repository.getTask(taskId))!.lastCommandId,
        resume.commandId,
      );
      expect((await sessionFor(resumed)).lastCommandId, resume.commandId);
      expect(resumed.lastCommandId, resume.commandId);

      final beforeBreak = await allCommands();
      await repository.startBreak((await repository.getTask(taskId))!);
      final onBreak = (await repository.getRuntime())!;
      final startBreak = (await runtimeCommands()).last;
      expect(
        commandsAfter(
          beforeBreak,
          await allCommands(),
        ).map((command) => command.entityType),
        orderedEquals(['execution_runtime']),
      );
      expect(
        (await repository.getTask(taskId))!.lastCommandId,
        startBreak.commandId,
      );
      expect((await sessionFor(onBreak)).lastCommandId, startBreak.commandId);
      expect(onBreak.lastCommandId, startBreak.commandId);

      final beforeFinishBreak = await allCommands();
      await repository.finishBreak((await repository.getTask(taskId))!);
      final afterBreak = (await repository.getRuntime())!;
      final finishBreak = (await runtimeCommands()).last;
      expect(
        commandsAfter(
          beforeFinishBreak,
          await allCommands(),
        ).map((command) => command.entityType),
        orderedEquals(['execution_runtime']),
      );
      expect(
        (await sessionFor(afterBreak)).lastCommandId,
        finishBreak.commandId,
      );
      expect(afterBreak.lastCommandId, finishBreak.commandId);
    },
  );

  test(
    'Start keeps idle revision but resets old session totals to a full focus',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Restart after completion',
          executionMode: 'pomodoro',
        ),
      );
      final now = DateTime.now().toUtc();
      await database
          .into(database.localRuntimeStates)
          .insert(
            LocalRuntimeStatesCompanion.insert(
              id: localRuntimeStateId('local'),
              userId: 'local',
              state: const drift.Value('idle'),
              accumulatedActiveMs: const drift.Value(3000000),
              accumulatedPausedMs: const drift.Value(900000),
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
      expect(runtime.accumulatedActiveMs, 0);
      expect(runtime.accumulatedPausedMs, 0);
      final snapshot = PomodoroExecutionSnapshot.fromTask(
        task: (await repository.getTask(taskId))!,
        runtime: runtime,
        now: runtime.segmentStartedAt!,
      );
      expect(snapshot.remainingMs, const Duration(minutes: 25).inMilliseconds);
      expect(
        runtime.segmentStartedAt!.add(
          Duration(milliseconds: snapshot.remainingMs),
        ),
        runtime.segmentStartedAt!.add(const Duration(minutes: 25)),
        reason: 'The boundary alarm must be scheduled in the future.',
      );
    },
  );

  test('completion publishes a revisioned idle widget snapshot', () async {
    final taskId = await repository.createTask(
      const TaskDraft(title: 'Duolingo German'),
    );
    await repository.start((await repository.getTask(taskId))!);
    final running = (await repository.getRuntime())!;

    await repository.complete((await repository.getTask(taskId))!);

    expect(await repository.getRuntime(), isNull);
    final idle = await repository.getRuntimeIncludingIdle();
    expect(idle?.state, 'idle');
    expect(idle?.revision, running.revision + 1);
    final widget = await AndroidHomeWidgetProjection.build(
      repository: repository,
      ownerId: 'local',
      localeCode: 'en',
    );
    expect(widget.mode, AndroidHomeWidgetMode.idle);
    expect(widget.taskId, isNull);
    expect(widget.sessionId, isNull);
    expect(widget.runtimeRevision, idle?.revision);
    expect(widget.runtimeUpdatedAt, idle?.updatedAt);
  });

  test(
    'idle widget reports every ready task while previewing at most three',
    () async {
      for (var index = 1; index <= 5; index += 1) {
        await repository.createTask(TaskDraft(title: 'Ready task $index'));
      }

      final widget = await AndroidHomeWidgetProjection.build(
        repository: repository,
        ownerId: 'local',
        localeCode: 'en',
        now: DateTime.utc(2026, 8, 29, 12),
      );

      expect(widget.mode, AndroidHomeWidgetMode.idle);
      expect(widget.timerLabel, '5 tasks ready');
      expect(widget.suggestions, hasLength(3));
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
    final oldSessionId = before.sessionId!;
    final beforeSwitchCommands = await allCommands();

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
    final previousTask = (await repository.getTask(firstId))!;
    final selectedTask = (await repository.getTask(secondId))!;
    final previousSession =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.id.equals(oldSessionId) &
                  row.entityType.equals('execution_sessions'),
            ))
            .getSingle();
    final selectedSession = await sessionFor(runtime);
    final selectedSessionData =
        jsonDecode(selectedSession.dataJson) as Map<String, dynamic>;
    final switchDelta = commandsAfter(
      beforeSwitchCommands,
      await allCommands(),
    );

    expect(command.baseRevision, before.revision);
    expect(payload['expected_runtime_revision'], before.revision);
    expect(runtime.revision, before.revision + 1);
    expect(runtime.lastCommandId, command.commandId);
    expect(runtime.state, 'running');
    expect(runtime.activeTaskId, secondId);
    expect(previousTask.status, 'paused');
    expect(previousTask.lastCommandId, command.commandId);
    expect(previousSession.status, 'paused');
    expect(previousSession.lastCommandId, command.commandId);
    expect(selectedTask.status, 'in_progress');
    expect(selectedTask.lastCommandId, command.commandId);
    expect(selectedSession.status, 'running');
    expect(selectedSessionData['state'], 'running');
    expect(selectedSessionData['active_segment_started_at'], isNotNull);
    expect(selectedSession.lastCommandId, command.commandId);
    expect(
      switchDelta.map((row) => row.entityType),
      containsAll(['execution_sessions', 'execution_runtime_switch']),
    );
    expect(
      switchDelta.where((row) => row.entityType == 'execution_runtime_switch'),
      hasLength(1),
    );
    expect(
      switchDelta.where(
        (row) =>
            row.entityType == 'task_occurrences' ||
            (row.entityType == 'execution_sessions' &&
                row.commandType == 'update'),
      ),
      isEmpty,
      reason:
          'The switch itself is one runtime command; only the new session create is a prerequisite.',
    );
  });

  test('finish-current switch stamps completed history atomically', () async {
    final firstId = await repository.createTask(
      const TaskDraft(title: 'Finish this task'),
    );
    final secondId = await repository.createTask(
      const TaskDraft(title: 'Run next task'),
    );
    await repository.start((await repository.getTask(firstId))!);
    final before = (await repository.getRuntime())!;

    await repository.switchActiveTask(
      (await repository.getTask(secondId))!,
      action: ActiveTaskSwitchAction.finishCurrent,
    );

    final runtime = (await repository.getRuntime())!;
    final command =
        await (database.select(database.localOutboxCommands)..where(
              (row) => row.entityType.equals('execution_runtime_switch'),
            ))
            .getSingle();
    final oldTask = (await repository.getTask(firstId))!;
    final oldSession = await (database.select(
      database.localEntityRecords,
    )..where((row) => row.id.equals(before.sessionId!))).getSingle();

    expect(oldTask.status, 'completed');
    expect(oldTask.progress, 1);
    expect(oldTask.actualFinish, isNotNull);
    expect(oldTask.lastCommandId, command.commandId);
    expect(oldSession.status, 'completed');
    expect(oldSession.lastCommandId, command.commandId);
    expect(runtime.state, 'running');
    expect(runtime.activeTaskId, secondId);
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
    final beforeSkip = await allCommands();
    expect(await repository.skipOfferedBreak(task), isTrue);

    final runtime = (await repository.getRuntime())!;
    final skippedTask = (await repository.getTask(taskId))!;
    final skippedSession = await sessionFor(runtime);
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
    expect(skippedTask.lastCommandId, skip.commandId);
    expect(skippedSession.lastCommandId, skip.commandId);
    expect(
      commandsAfter(
        beforeSkip,
        await allCommands(),
      ).map((command) => command.entityType),
      orderedEquals(['execution_runtime']),
    );
  });

  test(
    'direct skip rejects an early focus and accepts the exact boundary',
    () async {
      const focusMs = 60000;
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Direct skip boundary',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': focusMs},
        ),
      );
      var task = (await repository.getTask(taskId))!;
      await repository.start(task);
      var runtime = (await repository.getRuntime())!;
      final revisionBeforeEarlySkip = runtime.revision;
      final commandsBeforeEarlySkip = await runtimeCommands();
      await (database.update(
        database.localRuntimeStates,
      )..where((row) => row.id.equals(runtime.id))).write(
        LocalRuntimeStatesCompanion(
          segmentStartedAt: drift.Value(
            DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
          ),
        ),
      );

      task = (await repository.getTask(taskId))!;
      expect(await repository.skipOfferedBreak(task), isFalse);
      runtime = (await repository.getRuntime())!;
      expect(runtime.revision, revisionBeforeEarlySkip);
      expect(runtime.accumulatedActiveMs, 0);
      expect(
        (await runtimeCommands()).where(
          (command) => command.commandType == 'skip_break',
        ),
        isEmpty,
      );
      expect((await runtimeCommands()).length, commandsBeforeEarlySkip.length);

      await (database.update(
        database.localRuntimeStates,
      )..where((row) => row.id.equals(runtime.id))).write(
        LocalRuntimeStatesCompanion(
          segmentStartedAt: drift.Value(
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
          ),
        ),
      );

      expect(await repository.skipOfferedBreak(task), isTrue);
      runtime = (await repository.getRuntime())!;
      expect(runtime.state, 'running');
      expect(runtime.accumulatedActiveMs, focusMs);
      expect(
        (await runtimeCommands()).where(
          (command) => command.commandType == 'skip_break',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'finishing an extended break clears it under the runtime command only',
    () async {
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'One-break extension',
          executionMode: 'pomodoro',
          configuration: {'pomodoro_focus_ms': 60000},
        ),
      );
      await repository.start((await repository.getTask(taskId))!);
      await repository.startBreak((await repository.getTask(taskId))!);
      await repository.extendCurrentBreak((await repository.getTask(taskId))!);

      final extendedTask = (await repository.getTask(taskId))!;
      expect(
        (jsonDecode(extendedTask.dataJson) as Map<String, dynamic>).containsKey(
          'active_break_extension_ms',
        ),
        isTrue,
      );
      final beforeFinish = await allCommands();

      await repository.finishBreak(extendedTask);

      final runtime = (await repository.getRuntime())!;
      final finish = (await runtimeCommands()).last;
      final finishedTask = (await repository.getTask(taskId))!;
      expect(
        commandsAfter(
          beforeFinish,
          await allCommands(),
        ).map((command) => command.entityType),
        orderedEquals(['execution_runtime']),
      );
      expect(finish.commandType, 'finish_break');
      expect(runtime.lastCommandId, finish.commandId);
      expect(finishedTask.lastCommandId, finish.commandId);
      expect(finishedTask.revision, extendedTask.revision + 1);
      expect(
        (jsonDecode(finishedTask.dataJson) as Map<String, dynamic>).containsKey(
          'active_break_extension_ms',
        ),
        isFalse,
      );
    },
  );

  test(
    'an overdue break extension rebases to now and queues one atomic command',
    () async {
      var testNow = DateTime.utc(2026, 8, 23, 8);
      repository = TaskRepository(
        database,
        SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test_key',
        ),
        clock: () => testNow,
      );
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Overdue break',
          executionMode: 'pomodoro',
          configuration: {
            'pomodoro_focus_ms': 60000,
            'short_break_ms': 5 * 60 * 1000,
          },
        ),
      );
      await repository.start((await repository.getTask(taskId))!);
      testNow = testNow.add(const Duration(minutes: 1));
      await repository.startBreak((await repository.getTask(taskId))!);
      final breakRuntime = (await repository.getRuntime())!;
      final breakStartedAt = breakRuntime.segmentStartedAt!;
      testNow = breakStartedAt.add(const Duration(hours: 3));

      final taskBeforeExtension = (await repository.getTask(taskId))!;
      final commandsBeforeExtension = await allCommands();
      expect(
        await repository.extendCurrentBreak(taskBeforeExtension, now: testNow),
        isTrue,
      );

      final extendedTask = (await repository.getTask(taskId))!;
      final extendedConfiguration =
          jsonDecode(extendedTask.dataJson) as Map<String, dynamic>;
      final extensionCommands = commandsAfter(
        commandsBeforeExtension,
        await allCommands(),
      );
      final command = extensionCommands.single;
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
      final snapshot = PomodoroExecutionSnapshot.fromTask(
        task: extendedTask,
        runtime: breakRuntime,
        now: testNow,
      );

      expect(command.entityType, 'execution_break_extension');
      expect(command.entityId, breakRuntime.sessionId);
      expect(command.commandType, 'extend_break');
      expect(command.baseRevision, taskBeforeExtension.revision);
      expect(extendedTask.revision, taskBeforeExtension.revision + 1);
      expect(extendedTask.lastCommandId, command.commandId);
      expect(payload['task_occurrence_id'], taskId);
      expect(payload['session_id'], breakRuntime.sessionId);
      expect(
        payload['break_started_at'],
        breakStartedAt.toUtc().toIso8601String(),
      );
      expect(
        payload['extension_ms'],
        const Duration(minutes: 5).inMilliseconds,
      );
      expect(
        extendedConfiguration['active_break_extension_ms'],
        const Duration(hours: 3).inMilliseconds,
        reason:
            '175 overdue minutes plus the requested five must make five minutes visible now.',
      );
      expect(snapshot.remainingMs, const Duration(minutes: 5).inMilliseconds);

      final beforeSecondExtension = await allCommands();
      expect(
        await repository.extendCurrentBreak(extendedTask, now: testNow),
        isTrue,
      );
      final twiceExtendedTask = (await repository.getTask(taskId))!;
      final twiceExtended = PomodoroExecutionSnapshot.fromTask(
        task: twiceExtendedTask,
        runtime: breakRuntime,
        now: testNow,
      );
      expect(
        twiceExtended.remainingMs,
        const Duration(minutes: 10).inMilliseconds,
      );
      expect(
        commandsAfter(
          beforeSecondExtension,
          await allCommands(),
        ).map((queued) => queued.entityType),
        orderedEquals(['execution_break_extension']),
      );
    },
  );

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

  test('break extension cleanup is a forward-only guarded RPC migration', () {
    final migration = File(
      'supabase/migrations/20260813040500_v0028_atomic_break_extension_cleanup.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains('taskmaster_internal.guard_execution_runtime_v0028_command('),
    );
    expect(
      migration,
      contains('taskmaster_internal.apply_execution_transition_v0028_command('),
    );
    expect(
      migration,
      contains(
        "p_action in ('start_break', 'skip_break') and runtime_before.state = 'running'",
      ),
    );
    expect(
      migration,
      contains("p_action = 'finish_break' and runtime_before.state = 'break'"),
    );
    expect(
      migration,
      contains(
        "data = coalesce(data, '{}'::jsonb) - 'active_break_extension_ms'",
      ),
    );
    expect(
      migration,
      contains(
        "coalesce((result_payload ->> 'canonical_only')::boolean, false) = false",
      ),
    );
    expect(
      migration,
      contains(
        'create or replace function public.apply_execution_transition_v0028_command(',
      ),
      reason: 'The client keeps one stable revision-guarded RPC surface.',
    );
  });

  test('v0036 rebases break extensions as one idempotent command', () {
    final migration = File(
      'supabase/migrations/20260823143000_v0036_atomic_break_extension.sql',
    ).readAsStringSync();

    expect(migration, contains('extend_active_break_v0036_command'));
    expect(migration, contains("p_extension_ms <> 300000"));
    expect(migration, contains("runtime_record.state <> 'break'"));
    expect(migration, contains("guard_reason := 'break_interval_changed'"));
    expect(
      migration,
      contains(
        'overdue_ms := greatest(0::bigint, elapsed_ms - current_interval_ms)',
      ),
    );
    expect(
      migration,
      contains(
        'next_extension_ms := current_extension_ms + overdue_ms + p_extension_ms',
      ),
    );
    expect(migration, contains("'execution_break_extension'"));
    expect(migration, contains("'canonical_task'"));
    expect(migration, contains("'canonical_runtime'"));
    expect(migration, contains("'canonical_only', true"));
    expect(
      migration.indexOf('from public.processed_commands command_row'),
      lessThan(migration.indexOf('from public.account_devices device_row')),
      reason: 'An accepted retry must remain accepted after device revocation.',
    );
    expect(
      migration,
      isNot(contains('task_record.revision <> p_expected_task_revision')),
      reason:
          'Concurrent extensions merge against the locked task instead of conflicting.',
    );
    expect(migration, contains('security definer'));
    expect(migration, contains('security invoker'));
    expect(migration, contains("has_function_privilege('anon'"));
  });

  test('Pomodoro interval identity replaces lifetime modulo arithmetic', () {
    final migration = File(
      'supabase/migrations/'
      '20260815103000_v0028_pomodoro_interval_identity.sql',
    ).readAsStringSync();

    expect(migration, contains('focus_interval_active_base_ms'));
    expect(migration, contains('pomodoro_completed_focuses'));
    expect(migration, contains('aab_prepare_pomodoro_runtime_interval'));
    expect(migration, contains('aab_prepare_pomodoro_session_cycle'));
    expect(migration, contains('with recursive ordered_events as'));
    expect(migration, contains("walk.canonical_state = 'running'"));
    expect(
      migration,
      contains('event_row.duration_ms > walk.last_focus_boundary_ms'),
    );
    expect(
      migration,
      contains('runtime_row.data is distinct from repair.repaired_data'),
      reason: 'A manual operational rerun must not rewrite runtime rows.',
    );
    expect(
      migration,
      contains(
        'session_row.current_cycle is distinct from repair.repaired_cycle',
      ),
      reason: 'A manual operational rerun must not bump session revisions.',
    );
    expect(
      migration,
      contains('runtime.accumulated_active_ms - focus_base_ms'),
    );
    expect(migration, isNot(contains('mod(')));
    expect(
      migration,
      contains("event_row.event_type in ('start_break', 'skip_break')"),
      reason: 'Existing live intervals must be repaired from durable events.',
    );
    final cappedFocusTransitions = migration.substring(
      migration.indexOf("if p_action in ('start_break', 'skip_break') then"),
      migration.indexOf(
        'taskmaster_internal.apply_execution_transition_v0026_command(',
      ),
    );
    expect(
      cappedFocusTransitions,
      contains(
        "if p_action = 'skip_break' and elapsed_ms < focus_remaining_ms",
      ),
      reason: 'Only skipping an offered break requires a completed focus.',
    );
    expect(
      cappedFocusTransitions,
      contains('+ least(elapsed_ms, focus_remaining_ms)'),
      reason:
          'A delayed server command must not record work beyond one focus interval.',
    );
    expect(
      cappedFocusTransitions,
      contains(
        "when p_action = 'start_break' then 'break'::public.session_state",
      ),
      reason: 'An explicit early break must enter the canonical break state.',
    );
    expect(
      cappedFocusTransitions,
      contains("'break_skipped', p_action = 'skip_break'"),
      reason: 'The durable event must distinguish an early break from a skip.',
    );
    expect(
      migration.indexOf('update public.user_runtime_state runtime_row'),
      lessThan(
        migration.lastIndexOf(
          'create trigger aab_prepare_pomodoro_runtime_interval',
        ),
      ),
      reason: 'The backfill must run before the transition trigger is active.',
    );

    final syncSource = File(
      'lib/core/sync/sync_service.dart',
    ).readAsStringSync();
    final runtimeApply = syncSource.substring(
      syncSource.indexOf('Future<void> _applyRemoteRuntime('),
      syncSource.indexOf('Future<void> _restoreCanonicalRuntime('),
    );
    expect(runtimeApply, contains('dataJson: Value('));
    expect(runtimeApply, contains("row['data'] is Map"));
  });

  test(
    'local Pomodoro backfill ignores canonical-only boundaries and is idempotent',
    () async {
      const sessionId = 'historical-pomodoro-session';
      final taskId = await repository.createTask(
        const TaskDraft(
          title: 'Historical Pomodoro',
          executionMode: 'pomodoro',
        ),
      );
      final now = DateTime.utc(2026, 8, 15, 12);
      await database
          .into(database.localRuntimeStates)
          .insert(
            LocalRuntimeStatesCompanion.insert(
              id: localRuntimeStateId('local'),
              userId: 'local',
              activeTaskId: drift.Value(taskId),
              sessionId: const drift.Value(sessionId),
              state: const drift.Value('running'),
              accumulatedActiveMs: const drift.Value(1800000),
              dataJson: const drift.Value('{"preserve":"yes"}'),
              revision: const drift.Value(41),
              updatedAt: now,
            ),
          );

      Future<void> addEvent(int sequence, String eventType, int durationMs) {
        final occurredAt = now.add(Duration(seconds: sequence));
        return database
            .into(database.localEntityRecords)
            .insert(
              LocalEntityRecordsCompanion.insert(
                id: 'historical-event-$sequence',
                userId: 'local',
                entityType: 'session_events',
                parentId: const drift.Value(sessionId),
                dataJson: drift.Value(
                  jsonEncode({
                    'event_type': eventType,
                    'duration_ms': durationMs,
                    'occurred_at': occurredAt.toIso8601String(),
                  }),
                ),
                createdAt: occurredAt,
                updatedAt: occurredAt,
              ),
            );
      }

      // Three real focus boundaries are mixed with v0.0.26-style accepted
      // no-ops: duplicate boundary names, a skip while already on break, and
      // a skip while paused. Only the duration-advancing running transitions
      // are canonical focus completions.
      await addEvent(1, 'start_break', 600000);
      await addEvent(2, 'start_break', 600000);
      await addEvent(3, 'skip_break', 900000);
      await addEvent(4, 'finish_break', 600000);
      await addEvent(5, 'skip_break', 1500000);
      await addEvent(6, 'skip_break', 1500000);
      await addEvent(7, 'pause', 1500000);
      await addEvent(8, 'skip_break', 1700000);
      await addEvent(9, 'resume', 1500000);
      await addEvent(10, 'start_break', 1800000);
      await addEvent(11, 'finish_break', 1800000);

      await database.backfillPomodoroRuntimeIntervalMetadata();
      final repaired = await database
          .select(database.localRuntimeStates)
          .getSingle();
      final repairedData =
          jsonDecode(repaired.dataJson) as Map<String, dynamic>;

      expect(repairedData['focus_interval_active_base_ms'], 1800000);
      expect(repairedData['pomodoro_completed_focuses'], 3);
      expect(repairedData['preserve'], 'yes');
      expect(repaired.revision, 41);

      final firstJson = repaired.dataJson;
      await database.backfillPomodoroRuntimeIntervalMetadata();
      final rerun = await database
          .select(database.localRuntimeStates)
          .getSingle();
      expect(rerun.dataJson, firstJson);
      expect(rerun.revision, 41);
    },
  );
}
