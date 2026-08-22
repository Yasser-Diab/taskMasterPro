import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/notifications/notification_sounds.dart';
import 'package:taskmaster_pro/core/platform/windows_shell_service.dart';
import 'package:taskmaster_pro/core/providers.dart';
import 'package:taskmaster_pro/core/theme/app_theme.dart';
import 'package:taskmaster_pro/features/tasks/data/task_execution_commands.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/domain/pomodoro_execution_state.dart';
import 'package:taskmaster_pro/features/tasks/presentation/task_workspace_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'task-card Start opens Execute only after the canonical start is accepted',
    () {
      final source = File(
        'lib/features/tasks/presentation/task_card.dart',
      ).readAsStringSync();
      final startControl = source.substring(
        source.indexOf('class _CanonicalTaskControlState'),
        source.indexOf(
          '@override\n  Widget build',
          source.indexOf('class _CanonicalTaskControlState'),
        ),
      );

      expect(
        startControl,
        contains('startAccepted = await startTaskWithConfirmation('),
      );
      expect(startControl, contains('launchPreferredResource: false'));
      expect(startControl, contains('if (startAccepted != true)'));
      expect(startControl, contains("text('task_start_rejected')"));
      expect(
        startControl,
        contains(
          'TaskWorkspaceScreen.open(context, widget.task, initialSection: 1)',
        ),
      );
      expect(
        startControl.indexOf('if (startAccepted != true)'),
        lessThan(startControl.indexOf('TaskWorkspaceScreen.open(')),
      );
    },
  );

  group('canonical Pomodoro controls', () {
    final now = DateTime.utc(2026, 7, 28, 12);

    LocalRuntime runtime({
      required String state,
      required DateTime? segmentStartedAt,
      int accumulatedActiveMs = 0,
      String dataJson = '{}',
    }) {
      return LocalRuntime(
        id: 'active',
        userId: 'user-1',
        activeTaskId: 'task-1',
        sessionId: 'session-1',
        state: state,
        segmentStartedAt: segmentStartedAt,
        accumulatedActiveMs: accumulatedActiveMs,
        accumulatedPausedMs: 0,
        dataJson: dataJson,
        revision: 1,
        updatedAt: now,
      );
    }

    test('focus boundary offers the same Start break command everywhere', () {
      final active = runtime(
        state: 'running',
        segmentStartedAt: now.subtract(const Duration(minutes: 25)),
      );
      final pomodoro = PomodoroExecutionSnapshot.fromConfiguration(
        runtime: active,
        now: now,
        configuration: const {
          'pomodoro_focus_ms': 25 * 60 * 1000,
          'short_break_ms': 5 * 60 * 1000,
          'long_break_ms': 15 * 60 * 1000,
          'long_break_after': 4,
        },
        plannedMs: 60 * 60 * 1000,
      );
      final controls = TaskExecutionControlState.from(
        taskId: 'task-1',
        executionMode: 'pomodoro',
        runtime: active,
        pomodoro: pomodoro,
      );

      expect(pomodoro.focusComplete, isTrue);
      expect(pomodoro.remainingMs, 0);
      expect(controls.primary, TaskExecutionPrimaryAction.startBreak);
      expect(controls.canSkipBreak, isTrue);
      expect(controls.canStartBreakEarly, isFalse);
    });

    test('completed break offers Start focus and never generic Start', () {
      final active = runtime(
        state: 'break',
        segmentStartedAt: now.subtract(const Duration(minutes: 5)),
        accumulatedActiveMs: 25 * 60 * 1000,
      );
      final pomodoro = PomodoroExecutionSnapshot.fromConfiguration(
        runtime: active,
        now: now,
        configuration: const {
          'pomodoro_focus_ms': 25 * 60 * 1000,
          'short_break_ms': 5 * 60 * 1000,
        },
        plannedMs: 60 * 60 * 1000,
      );
      final controls = TaskExecutionControlState.from(
        taskId: 'task-1',
        executionMode: 'pomodoro',
        runtime: active,
        pomodoro: pomodoro,
      );

      expect(pomodoro.breakComplete, isTrue);
      expect(controls.primary, TaskExecutionPrimaryAction.startFocus);
      expect(controls.canExtendBreak, isTrue);
    });

    test('legacy minute keys and current millisecond keys agree', () {
      final active = runtime(
        state: 'break',
        segmentStartedAt: now.subtract(const Duration(minutes: 6)),
        accumulatedActiveMs: 25 * 60 * 1000,
      );
      final current = PomodoroExecutionSnapshot.fromConfiguration(
        runtime: active,
        now: now,
        configuration: const {
          'pomodoro_focus_ms': 25 * 60 * 1000,
          'short_break_ms': 5 * 60 * 1000,
          'active_break_extension_ms': 5 * 60 * 1000,
        },
        plannedMs: 60 * 60 * 1000,
      );
      final legacy = PomodoroExecutionSnapshot.fromConfiguration(
        runtime: active,
        now: now,
        configuration: const {
          'pomodoro_focus_minutes': 25,
          'pomodoro_short_break_minutes': 5,
          'active_break_extension_ms': 5 * 60 * 1000,
        },
        plannedMs: 60 * 60 * 1000,
      );

      expect(current.intervalDurationMs, 10 * 60 * 1000);
      expect(legacy.intervalDurationMs, current.intervalDurationMs);
      expect(legacy.remainingMs, current.remainingMs);
      expect(legacy.breakComplete, isFalse);
    });

    test('countdown uses ceiling seconds and compact Pomodoro notation', () {
      expect(formatPomodoroCountdown(25 * 60 * 1000), '25:00');
      expect(formatPomodoroCountdown(25 * 60 * 1000 - 1), '25:00');
      expect(formatPomodoroCountdown(24 * 60 * 1000 + 59 * 1000), '24:59');
      expect(formatPomodoroCountdown(1), '00:01');
      expect(formatPomodoroCountdown(0), '00:00');
      expect(formatPomodoroCountdown(65 * 60 * 1000), '01:05:00');
    });

    test('lifetime work never shortens a newly started focus interval', () {
      const lifetime = 14 * 60 * 1000;
      final active = runtime(
        state: 'running',
        segmentStartedAt: now,
        accumulatedActiveMs: lifetime,
        dataJson: jsonEncode({
          pomodoroFocusIntervalBaseKey: lifetime,
          pomodoroCompletedFocusesKey: 1,
        }),
      );

      final pomodoro = PomodoroExecutionSnapshot.fromConfiguration(
        runtime: active,
        now: now,
        configuration: const {'pomodoro_focus_ms': 25 * 60 * 1000},
        plannedMs: 60 * 60 * 1000,
      );

      expect(pomodoro.remainingMs, 25 * 60 * 1000);
      expect(formatPomodoroCountdown(pomodoro.remainingMs), '25:00');
      expect(pomodoro.focusedMs, lifetime);
      expect(pomodoro.completedFocuses, 1);
      expect(pomodoro.currentSession, 2);
    });

    test('planned task effort changes to an explicit overtime value', () {
      expect(
        taskEffortRemainingMs(
          plannedMs: const Duration(minutes: 40).inMilliseconds,
          recordedMs: 0,
        ),
        const Duration(minutes: 40).inMilliseconds,
      );
      expect(
        formatTaskEffortCountdown(const Duration(minutes: 40).inMilliseconds),
        '00:40:00',
      );
      expect(
        formatTaskEffortCountdown(
          const Duration(minutes: 40).inMilliseconds - 1,
        ),
        '00:40:00',
      );
      expect(
        formatTaskEffortCountdown(
          taskEffortRemainingMs(
            plannedMs: const Duration(minutes: 40).inMilliseconds,
            recordedMs: const Duration(seconds: 1).inMilliseconds,
          ),
        ),
        '00:39:59',
      );
      expect(
        formatTaskEffortCountdown(
          taskEffortRemainingMs(
            plannedMs: const Duration(minutes: 40).inMilliseconds,
            recordedMs: const Duration(minutes: 42).inMilliseconds,
          ),
        ),
        '00:00:00',
      );
      expect(
        formatTaskEffortOvertime(
          taskEffortOvertimeMs(
            plannedMs: const Duration(minutes: 40).inMilliseconds,
            recordedMs: const Duration(minutes: 42).inMilliseconds,
          ),
        ),
        '+00:02:00',
      );
    });

    test('inactive, paused and reduced-motion timers never animate', () {
      expect(
        pomodoroTimerVisualState(active: false, paused: false, waiting: false),
        PomodoroTimerVisualState.waiting,
      );
      expect(
        pomodoroTimerVisualState(active: false, paused: true, waiting: false),
        PomodoroTimerVisualState.paused,
      );
      expect(
        shouldAnimatePomodoroTimer(
          active: true,
          paused: false,
          waiting: false,
          reducedMotion: false,
        ),
        isTrue,
      );
      expect(
        shouldAnimatePomodoroTimer(
          active: true,
          paused: false,
          waiting: false,
          reducedMotion: true,
        ),
        isFalse,
      );
    });

    test('Windows tray receives enough state to suppress invalid controls', () {
      final state = WindowsTrayState(
        signedIn: true,
        hasActiveTask: true,
        taskPaused: false,
        breakActive: false,
        pomodoroAvailable: true,
        focusComplete: true,
        activeTask: 'Focus task',
        elapsed: '00:00',
        syncLabel: 'All changes synced',
        syncAttention: false,
        localeCode: 'en',
      ).toMap();

      expect(state['pomodoroAvailable'], isTrue);
      expect(state['focusComplete'], isTrue);
    });

    test('execution notification payload preserves its exact boundary', () {
      final boundary = DateTime.utc(2026, 7, 28, 12, 25);
      final decoded = LocalNotificationService.decodeOwnedPayload(
        jsonEncode({
          'version': 2,
          'owner_id': 'user-1',
          'route': 'task/task-1',
          'event_type': 'focus_completed',
          'boundary_at': boundary.toIso8601String(),
        }),
      );

      expect(decoded.ownerId, 'user-1');
      expect(decoded.route, 'task/task-1');
      expect(decoded.eventType, 'focus_completed');
      expect(decoded.boundaryAtUtc, boundary);
    });

    test('only the runtime observer schedules execution alarms', () {
      final commands = File(
        'lib/features/tasks/data/task_execution_commands.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/features/shell/presentation/home_shell.dart',
      ).readAsStringSync();

      expect(commands, isNot(contains('scheduleExecutionCompletion(')));
      expect(
        'scheduleExecutionCompletion('.allMatches(shell).length,
        1,
        reason:
            'Task commands may mutate runtime, but one shell-owned scheduler reconciles every device alarm.',
      );
    });
  });

  group('repository transition guards', () {
    late AppDatabase database;
    late TaskRepository repository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase(NativeDatabase.memory());
      repository = TaskRepository(
        database,
        SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test_key',
        ),
      );
    });

    tearDown(() => database.close());

    test(
      'a replayed Start cannot resume a paused task or finish its break',
      () async {
        final taskId = await repository.createTask(
          TaskDraft(
            title: 'Cross-surface Pomodoro',
            executionMode: 'pomodoro',
            estimatedDuration: const Duration(hours: 1),
          ),
        );
        var task = (await repository.getTask(taskId))!;
        await repository.start(task);
        task = (await repository.getTask(taskId))!;
        await repository.pause(task);

        var runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(runtime.state, 'paused');
        expect(
          (await database.select(database.localOutboxCommands).get()).where(
            (command) =>
                command.entityType == 'execution_runtime' &&
                command.commandType == 'resume',
          ),
          isEmpty,
        );

        // A delayed hand-off confirmation was also computed against an older
        // active-task snapshot. It must not reinterpret the newer Pause.
        await repository.switchActiveTask(
          task,
          action: ActiveTaskSwitchAction.pauseCurrent,
        );
        runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(runtime.state, 'paused');
        expect(
          (await database.select(database.localOutboxCommands).get()).where(
            (command) =>
                command.entityType == 'execution_runtime' &&
                command.commandType == 'resume',
          ),
          isEmpty,
        );

        // Models a delayed Start callback from the device that originally
        // started the task arriving after another device paused it.
        await repository.start(task);
        runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(
          runtime.state,
          'paused',
          reason: 'a stale Start intent must not be promoted to Resume',
        );
        expect(
          (await database.select(database.localOutboxCommands).get()).where(
            (command) =>
                command.entityType == 'execution_runtime' &&
                command.commandType == 'resume',
          ),
          isEmpty,
        );

        await repository.resume(task);
        runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(
          runtime.state,
          'running',
          reason: 'the explicit Resume command remains authoritative',
        );

        await repository.startBreak(task);

        runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(runtime.state, 'break');

        await repository.resume(task);
        runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(
          runtime.state,
          'break',
          reason: 'Resume is valid only for the canonical paused state',
        );

        await repository.start(task);
        runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(
          runtime.state,
          'break',
          reason: 'a stale Start intent must not become Finish break',
        );
        expect(
          (await database.select(database.localOutboxCommands).get()).where(
            (command) =>
                command.entityType == 'execution_runtime' &&
                command.commandType == 'finish_break',
          ),
          isEmpty,
        );

        await repository.finishBreak(task);
        runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(
          runtime.state,
          'running',
          reason: 'the explicit Finish break command remains authoritative',
        );
      },
    );

    test(
      'an offered-break action cannot interrupt the following focus interval',
      () async {
        final taskId = await repository.createTask(
          TaskDraft(
            title: 'Boundary guarded Pomodoro',
            executionMode: 'pomodoro',
            estimatedDuration: const Duration(hours: 1),
          ),
        );
        var task = (await repository.getTask(taskId))!;
        await repository.start(task);
        final runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        await (database.update(
          database.localRuntimeStates,
        )..where((row) => row.id.equals(runtime.id))).write(
          LocalRuntimeStatesCompanion(
            segmentStartedAt: drift.Value(
              DateTime.now().toUtc().subtract(const Duration(minutes: 26)),
            ),
          ),
        );

        task = (await repository.getTask(taskId))!;
        expect(
          await TaskExecutionCommands.startOfferedBreak(repository, task),
          isTrue,
        );
        var breakRuntime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        final breakStartedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 6),
        );
        await (database.update(
          database.localRuntimeStates,
        )..where((row) => row.id.equals(breakRuntime.id))).write(
          LocalRuntimeStatesCompanion(
            segmentStartedAt: drift.Value(breakStartedAt),
          ),
        );
        expect(
          await TaskExecutionCommands.startFocusFromCompletedBreak(
            repository,
            task,
            expectedBoundaryAt: breakStartedAt.add(const Duration(minutes: 10)),
          ),
          isFalse,
          reason: 'an action from a different break boundary must be ignored',
        );
        breakRuntime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(breakRuntime.state, 'break');
        expect(
          await TaskExecutionCommands.startFocusFromCompletedBreak(
            repository,
            task,
            expectedBoundaryAt: breakStartedAt.add(const Duration(minutes: 5)),
          ),
          isTrue,
        );
        expect(
          await TaskExecutionCommands.skipOfferedBreak(repository, task),
          isFalse,
          reason:
              'a delayed completion action must not start and instantly end '
              'a new early break',
        );
        final updated = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(updated.state, 'running');
      },
    );

    test('automatic boundaries advance without an Execute page', () async {
      final taskId = await repository.createTask(
        TaskDraft(
          title: 'Automatic Pomodoro',
          executionMode: 'pomodoro',
          estimatedDuration: const Duration(hours: 1),
          configuration: const {
            'pomodoro_focus_ms': 60000,
            'short_break_ms': 60000,
            'pomodoro_auto_start_breaks': true,
            'pomodoro_auto_start_focus': true,
          },
        ),
      );
      var task = (await repository.getTask(taskId))!;
      await repository.start(task);
      var runtime = await database
          .select(database.localRuntimeStates)
          .getSingle();
      await (database.update(
        database.localRuntimeStates,
      )..where((row) => row.id.equals(runtime.id))).write(
        LocalRuntimeStatesCompanion(
          segmentStartedAt: drift.Value(
            DateTime.now().toUtc().subtract(const Duration(seconds: 61)),
          ),
        ),
      );
      task = (await repository.getTask(taskId))!;

      expect(
        await TaskExecutionCommands.advanceAutomaticBoundary(
          repository: repository,
          requestedTask: task,
        ),
        isTrue,
      );
      runtime = await database.select(database.localRuntimeStates).getSingle();
      expect(runtime.state, 'break');

      await (database.update(
        database.localRuntimeStates,
      )..where((row) => row.id.equals(runtime.id))).write(
        LocalRuntimeStatesCompanion(
          segmentStartedAt: drift.Value(
            DateTime.now().toUtc().subtract(const Duration(seconds: 61)),
          ),
        ),
      );
      task = (await repository.getTask(taskId))!;
      expect(
        await TaskExecutionCommands.advanceAutomaticBoundary(
          repository: repository,
          requestedTask: task,
        ),
        isTrue,
      );
      runtime = await database.select(database.localRuntimeStates).getSingle();
      expect(runtime.state, 'running');
    });

    test(
      'legacy focus minutes cap recorded work at the visible boundary',
      () async {
        final taskId = await repository.createTask(
          TaskDraft(
            title: 'Legacy Pomodoro',
            executionMode: 'pomodoro',
            estimatedDuration: const Duration(hours: 1),
            configuration: const {'pomodoro_focus_minutes': 2},
          ),
        );
        var task = (await repository.getTask(taskId))!;
        await repository.start(task);
        final runtime = await database
            .select(database.localRuntimeStates)
            .getSingle();
        await (database.update(
          database.localRuntimeStates,
        )..where((row) => row.id.equals(runtime.id))).write(
          LocalRuntimeStatesCompanion(
            segmentStartedAt: drift.Value(
              DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
            ),
          ),
        );

        task = (await repository.getTask(taskId))!;
        await repository.pause(task);
        final updated = await database
            .select(database.localRuntimeStates)
            .getSingle();
        expect(
          updated.accumulatedActiveMs,
          const Duration(minutes: 2).inMilliseconds,
        );
      },
    );

    test(
      'early break and skipped break each reset focus without erasing lifetime work',
      () async {
        const focusMs = 25 * 60 * 1000;
        final taskId = await repository.createTask(
          TaskDraft(
            title: 'Independent Pomodoro intervals',
            executionMode: 'pomodoro',
            estimatedDuration: const Duration(hours: 2),
            configuration: const {'pomodoro_focus_ms': focusMs},
          ),
        );
        var task = (await repository.getTask(taskId))!;
        await repository.start(task);
        var runtime = (await repository.getRuntime())!;
        await (database.update(
          database.localRuntimeStates,
        )..where((row) => row.id.equals(runtime.id))).write(
          LocalRuntimeStatesCompanion(
            segmentStartedAt: drift.Value(
              DateTime.now().toUtc().subtract(const Duration(minutes: 14)),
            ),
          ),
        );

        task = (await repository.getTask(taskId))!;
        await repository.startBreak(task);
        runtime = (await repository.getRuntime())!;
        final firstLifetime = runtime.accumulatedActiveMs;
        expect(runtime.state, 'break');
        expect(
          firstLifetime,
          inInclusiveRange(
            const Duration(minutes: 14).inMilliseconds,
            const Duration(minutes: 14, seconds: 1).inMilliseconds,
          ),
        );
        expect(pomodoroFocusIntervalBaseMs(runtime, focusMs), firstLifetime);
        expect(pomodoroCompletedFocuses(runtime, focusMs), 1);

        await repository.finishBreak(task);
        runtime = (await repository.getRuntime())!;
        var snapshot = PomodoroExecutionSnapshot.fromConfiguration(
          runtime: runtime,
          now: runtime.segmentStartedAt!,
          configuration: const {'pomodoro_focus_ms': focusMs},
          plannedMs: const Duration(hours: 2).inMilliseconds,
        );
        expect(snapshot.remainingMs, focusMs);
        expect(formatPomodoroCountdown(snapshot.remainingMs), '25:00');
        expect(runtime.accumulatedActiveMs, firstLifetime);

        await (database.update(
          database.localRuntimeStates,
        )..where((row) => row.id.equals(runtime.id))).write(
          LocalRuntimeStatesCompanion(
            segmentStartedAt: drift.Value(
              DateTime.now().toUtc().subtract(const Duration(minutes: 26)),
            ),
          ),
        );
        task = (await repository.getTask(taskId))!;
        expect(await repository.skipOfferedBreak(task), isTrue);

        runtime = (await repository.getRuntime())!;
        expect(runtime.state, 'running');
        expect(runtime.accumulatedActiveMs, firstLifetime + focusMs);
        expect(
          pomodoroFocusIntervalBaseMs(runtime, focusMs),
          runtime.accumulatedActiveMs,
        );
        expect(pomodoroCompletedFocuses(runtime, focusMs), 2);
        snapshot = PomodoroExecutionSnapshot.fromConfiguration(
          runtime: runtime,
          now: runtime.segmentStartedAt!,
          configuration: const {'pomodoro_focus_ms': focusMs},
          plannedMs: const Duration(hours: 2).inMilliseconds,
        );
        expect(snapshot.remainingMs, focusMs);
        expect(formatPomodoroCountdown(snapshot.remainingMs), '25:00');
      },
    );

    test(
      'concurrent Start and Pause taps create one session and one transition',
      () async {
        final taskId = await repository.createTask(
          const TaskDraft(title: 'Rapid controls'),
        );
        final staleTask = (await repository.getTask(taskId))!;

        await Future.wait([
          repository.start(staleTask),
          repository.start(staleTask),
          repository.start(staleTask),
        ]);

        var runtime = await repository.getRuntime();
        expect(runtime?.state, 'running');
        expect(
          await (database.select(
            database.localEntityRecords,
          )..where((row) => row.entityType.equals('execution_sessions'))).get(),
          hasLength(1),
        );
        expect(
          (await database.select(database.localOutboxCommands).get()).where(
            (command) =>
                command.entityType == 'execution_runtime' &&
                command.commandType == 'start',
          ),
          hasLength(1),
        );

        await Future.wait([
          repository.pause(staleTask),
          repository.pause(staleTask),
          repository.pause(staleTask),
        ]);

        runtime = await repository.getRuntime();
        expect(runtime?.state, 'paused');
        expect(
          (await database.select(database.localOutboxCommands).get()).where(
            (command) =>
                command.entityType == 'execution_runtime' &&
                command.commandType == 'pause',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'a valid Resume queued behind Pause is preserved instead of dropped',
      () async {
        final taskId = await repository.createTask(
          const TaskDraft(title: 'Queued controls'),
        );
        final staleTask = (await repository.getTask(taskId))!;
        await repository.start(staleTask);

        final pause = repository.pause(staleTask);
        final resume = repository.resume(staleTask);
        await Future.wait([pause, resume]);

        final runtime = await repository.getRuntime();
        expect(runtime?.state, 'running');
        final transitions =
            (await database.select(database.localOutboxCommands).get()).where(
              (command) => command.entityType == 'execution_runtime',
            );
        expect(
          transitions.map((command) => command.commandType),
          containsAllInOrder(['start', 'pause', 'resume']),
        );
      },
    );

    test(
      'local execution completion does not await delayed synchronization',
      () async {
        var localCommitted = false;
        final synchronization = Completer<void>();

        final result = await TaskExecutionCommands.commitLocallyAndSynchronize(
          localCommand: () async {
            localCommitted = true;
            return 'committed';
          },
          synchronize: () => synchronization.future,
        ).timeout(const Duration(milliseconds: 250));

        expect(result, 'committed');
        expect(localCommitted, isTrue);
        expect(synchronization.isCompleted, isFalse);
        synchronization.complete();
      },
    );

    testWidgets('Execute holographic timer fits 320 px with large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final task = (await tester.runAsync<LocalTask>(() async {
        final taskId = await repository.createTask(
          TaskDraft(
            title: 'Narrow holographic timer',
            executionMode: 'pomodoro',
            estimatedDuration: const Duration(hours: 1),
          ),
        );
        final created = (await repository.getTask(taskId))!;
        await repository.start(created);
        return created;
      }))!;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            taskRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
            home: TaskWorkspaceScreen(taskId: task.id, initialSection: 1),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data ?? ''),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('holographic-execution-timer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('execution-primary-action')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets(
      'every execution mode uses the spacious theme-aware holographic console',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final modes = <String>[
          'manual',
          'pomodoro',
          'continuous',
          'checklist',
          'reading',
          'habit',
          'event',
          'hybrid',
        ];

        Future<Color> pumpTask(LocalTask task, ThemeData theme) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                databaseProvider.overrideWithValue(database),
                taskRepositoryProvider.overrideWithValue(repository),
              ],
              child: MaterialApp(
                theme: theme,
                locale: const Locale('en'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: TaskWorkspaceScreen(taskId: task.id, initialSection: 1),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          expect(
            find.byKey(ValueKey('execution-hero-${task.executionMode}')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('holographic-execution-timer')),
            findsOneWidget,
          );
          if (task.executionMode != 'pomodoro') {
            expect(
              find.text('01:00:00'),
              findsOneWidget,
              reason:
                  '${task.executionMode} must show planned effort counting down',
            );
          }
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey('execution-hero-${task.executionMode}')),
                )
                .width,
            greaterThan(900),
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('holographic-execution-timer')),
                )
                .width,
            greaterThan(340),
          );
          expect(tester.takeException(), isNull);
          final hero = tester.widget<AnimatedContainer>(
            find.byKey(ValueKey('execution-hero-${task.executionMode}')),
          );
          final decoration = hero.decoration! as BoxDecoration;
          return (decoration.gradient! as LinearGradient).colors.first;
        }

        final tasks = (await tester.runAsync<List<LocalTask>>(() async {
          final created = <LocalTask>[];
          for (final mode in modes) {
            final id = await repository.createTask(
              TaskDraft(
                title: '$mode visual',
                executionMode: mode,
                estimatedDuration: const Duration(hours: 1),
              ),
            );
            created.add((await repository.getTask(id))!);
          }
          return created;
        }))!;

        late LocalTask continuousTask;
        late Color continuousDarkSurface;
        for (final task in tasks) {
          final mode = task.executionMode;
          if (mode == 'continuous') continuousTask = task;
          final color = await pumpTask(task, TaskMasterTheme.dark());
          if (mode == 'continuous') continuousDarkSurface = color;
        }

        final lightSurface = await pumpTask(
          continuousTask,
          TaskMasterTheme.light(),
        );
        final goldenSurface = await pumpTask(
          continuousTask,
          TaskMasterTheme.golden(),
        );
        expect(<Color>{
          continuousDarkSurface,
          lightSurface,
          goldenSurface,
        }, hasLength(3));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(Duration.zero);
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  });
}
