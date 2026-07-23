import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_task_manager/core/config/supabase_service.dart';
import 'package:personal_task_manager/core/platform/health_data_service.dart';
import 'package:personal_task_manager/core/time/time_zone_service.dart';
import 'package:personal_task_manager/features/pomodoro/domain/pomodoro_controller.dart';
import 'package:personal_task_manager/features/pomodoro/domain/pomodoro_models.dart';
import 'package:personal_task_manager/features/roadmap/domain/roadmap_overview_screen.dart';
import 'package:personal_task_manager/features/roadmap/domain/roadmap_phase.dart';
import 'package:personal_task_manager/features/sessions/domain/session_models.dart';
import 'package:personal_task_manager/features/tasks/application/task_action_controller.dart';
import 'package:personal_task_manager/features/tasks/data/task_local_store.dart';
import 'package:personal_task_manager/features/tasks/domain/learning_activity_models.dart';
import 'package:personal_task_manager/features/tasks/domain/task_item.dart';
import 'package:personal_task_manager/features/tasks/domain/task_workspace_config.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz_data.initializeTimeZones();
    TimeZoneRegistry.deviceZoneId = 'Africa/Cairo';
  });

  group('roadmap phase resolution', () {
    test('sort order does not change the explicit active phase', () {
      final phase = resolveActivePhase([
        const RoadmapPhase(
          phase: 9,
          phaseOrder: 9,
          period: '2030',
          objective: 'Employment preparation',
          exitEvidence: '',
        ),
        const RoadmapPhase(
          phase: 1,
          phaseOrder: 1,
          period: '2026',
          objective: 'HTML and CSS',
          exitEvidence: '',
          status: 'active',
          isExplicitlyActive: true,
        ),
      ]);

      expect(phase?.phaseOrder, 1);
    });

    test('falls back to the first incomplete phase', () {
      final phase = resolveActivePhase([
        const RoadmapPhase(
          phase: 2,
          phaseOrder: 2,
          period: '',
          objective: 'Second',
          exitEvidence: '',
        ),
        const RoadmapPhase(
          phase: 1,
          phaseOrder: 1,
          period: '',
          objective: 'First',
          exitEvidence: '',
          status: 'completed',
        ),
      ]);

      expect(phase?.phaseOrder, 2);
    });
  });

  test('task persistence retains execution fields and historical inputs', () {
    final task = TaskItem(
      title: 'Build profile screen',
      taskType: TaskType.timed,
      projectId: '11111111-1111-1111-1111-111111111111',
      project: 'TaskMaster Pro',
      roadmapId: '22222222-2222-2222-2222-222222222222',
      roadmapPhaseId: '33333333-3333-3333-3333-333333333333',
      milestoneId: '44444444-4444-4444-4444-444444444444',
      checklist: const [TaskChecklistItem(title: 'Persist avatar', done: true)],
      attachments: const ['profile-reference.png'],
      timerEnabled: true,
      adaptiveRemindersEnabled: true,
    );

    final restored = TaskItem.fromMap({'id': task.id, ...task.toInsertMap()});

    expect(restored.taskType, TaskType.timed);
    expect(restored.projectId, task.projectId);
    expect(restored.roadmapId, task.roadmapId);
    expect(restored.checklist.single.done, isTrue);
    expect(restored.attachments, ['profile-reference.png']);
    expect(restored.adaptiveRemindersEnabled, isTrue);
  });

  test('local task journal survives a new store instance', () async {
    final directory = await Directory.systemTemp.createTemp(
      'taskmaster-task-store-',
    );
    addTearDown(() => directory.delete(recursive: true));
    const userId = 'bfefc003-145d-400e-8c7a-2f562be37159';
    final task = TaskItem(title: 'Offline task');
    final first = TaskLocalStore(baseDirectory: directory);

    await first.upsertTask(userId, task);
    await first.enqueue(
      userId,
      PendingTaskOperation(
        id: 'operation-1',
        type: 'update',
        deviceId: 'windows-test',
        entityType: 'task',
        entityId: task.id,
        baseRevision: 3,
        changedFields: const ['title'],
        payload: {'id': task.id, 'title': 'Offline task'},
      ),
    );

    final second = TaskLocalStore(baseDirectory: directory);
    final snapshot = await second.load(userId);
    expect(snapshot.tasks.single.title, 'Offline task');
    expect(snapshot.operations.single.id, 'operation-1');
    expect(snapshot.operations.single.deviceId, 'windows-test');
    expect(snapshot.operations.single.baseRevision, 3);
    expect(snapshot.operations.single.changedFields, ['title']);
  });

  test(
    'local child records replace only their owning task partition',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'taskmaster-child-store-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const userId = 'user-1';
      final store = TaskLocalStore(baseDirectory: directory);
      await store.upsertRow(userId, 'task_resources', 'resource-a', {
        'id': 'resource-a',
        'task_id': 'task-a',
        'url': 'https://developer.mozilla.org',
      });
      await store.upsertRow(userId, 'task_resources', 'resource-b', {
        'id': 'resource-b',
        'task_id': 'task-b',
        'url': 'https://duolingo.com',
      });

      await store.replaceRowsWhere(
        userId,
        'task_resources',
        'task_id',
        {'task-a'},
        [
          {'id': 'resource-a2', 'task_id': 'task-a', 'url': 'https://dart.dev'},
        ],
      );

      final rows = await TaskLocalStore(
        baseDirectory: directory,
      ).loadRows(userId, 'task_resources');
      expect(rows.map((row) => row['id']).toSet(), {
        'resource-a2',
        'resource-b',
      });
    },
  );

  group('time-zone scheduling', () {
    test('Friday 12:00-18:00 Cairo task is overdue only after 18:00', () {
      final task = TaskItem(
        title: 'Friday project block',
        taskType: TaskType.timed,
        scheduledLocalDate: DateTime(2026, 7, 17),
        scheduledLocalTime: '12:00',
        timeZoneId: 'Africa/Cairo',
        estimatedMinutes: 360,
      );

      expect(task.isOverdueAt(DateTime.utc(2026, 7, 17, 14, 59)), isFalse);
      expect(task.isOverdueAt(DateTime.utc(2026, 7, 17, 15, 1)), isTrue);
    });

    test('all-day tasks use the configured end-of-day boundary', () {
      final task = TaskItem(
        title: 'All-day review',
        scheduledLocalDate: DateTime(2026, 7, 17),
        timeZoneId: 'Africa/Cairo',
        allDayEndMinutes: 23 * 60 + 30,
      );

      expect(task.isOverdueAt(DateTime.utc(2026, 7, 17, 20, 29)), isFalse);
      expect(task.isOverdueAt(DateTime.utc(2026, 7, 17, 20, 31)), isTrue);
    });
  });

  test('reading sessions separate new progress from rereading', () {
    final book = ReadingBook(
      readingTaskId: 'task-1',
      title: 'Clean Code',
      totalPages: 420,
      currentPage: 103,
    );
    final session = ReadingSession(
      taskId: 'task-1',
      bookId: book.id,
      startPage: 98,
      endPage: 108,
      previousBookPage: book.currentPage,
      durationSeconds: 1200,
      startedAt: DateTime.utc(2026, 7, 17, 12),
      endedAt: DateTime.utc(2026, 7, 17, 12, 20),
    );

    session.validateFor(book);
    expect(session.pagesTraversed, 10);
    expect(session.uniquePagesAdvanced, 5);
    expect(session.rereadPages, 5);
  });

  group('Pomodoro state machine', () {
    test('focus completion waits for the user before starting break', () {
      fakeAsync((async) {
        final controller = PomodoroController(
          preset: const PomodoroPreset(
            name: 'instant test',
            focusMinutes: 0,
            shortBreakMinutes: 0,
            longBreakMinutes: 0,
            longBreakAfter: 4,
          ),
        );
        addTearDown(controller.dispose);

        controller.startFocus(sessionId: 'session-1');
        expect(controller.state, PomodoroRunState.focusRunning);

        async.elapse(const Duration(seconds: 1));
        expect(controller.state, PomodoroRunState.focusFinishedWaitingForUser);
        expect(controller.phase, PomodoroPhase.focus);
        expect(controller.remainingSeconds, 0);

        controller.startBreak();
        expect(controller.state, PomodoroRunState.breakRunning);

        async.elapse(const Duration(seconds: 1));
        expect(controller.state, PomodoroRunState.breakFinishedWaitingForUser);

        controller.returnToFocus();
        expect(controller.state, PomodoroRunState.focusReady);

        controller.startFocus(sessionId: 'session-1');
        expect(controller.state, PomodoroRunState.focusRunning);
      });
    });

    test('manual transitions keep explicit waiting states', () {
      final controller = PomodoroController(
        preset: const PomodoroPreset(
          name: 'manual test',
          focusMinutes: 25,
          shortBreakMinutes: 5,
          longBreakMinutes: 20,
          longBreakAfter: 4,
        ),
      );
      addTearDown(controller.dispose);

      controller.startFocus(sessionId: 'session-2');
      controller.completeEarly();

      expect(controller.state.stage, PomodoroStage.focusCompletedWaiting);
      expect(controller.completedFocusSessions, 0);

      controller.startBreak();
      expect(controller.state.stage, PomodoroStage.breakRunning);

      controller.finishBreakEarly();
      expect(controller.state.stage, PomodoroStage.breakCompletedWaiting);
      expect(controller.pendingBreakReview, isNotNull);
    });

    test('focus-ready sessions do not restore a stale partial countdown', () {
      final now = DateTime.utc(2026, 7, 18, 18);
      final task = TaskItem(
        id: 'task-1',
        title: 'Main workday',
        taskType: TaskType.focus,
        estimatedPomodoros: 21,
        estimatedMinutes: 525,
      );
      final session = TrackedSession(
        taskId: task.id,
        startedAt: now.subtract(const Duration(hours: 5)),
        activeSeconds: (11 * 25 * 60) + (22 * 60),
        pomodorosCompleted: 11,
      );
      final active = ActiveTaskSession(
        task: task,
        session: session,
        startedAt: session.startedAt,
        pomodoroStage: PomodoroStage.focusReady,
      );

      final timing = active.timingAt(now);

      expect(timing.currentFocusElapsedSeconds, 0);
      expect(timing.pomodoroRemainingSeconds, 25 * 60);
      expect(timing.pomodoroStage, PomodoroStage.focusReady);
    });

    test('new focus segment starts from zero after prior work and rest', () {
      final now = DateTime.utc(2026, 7, 18, 19);
      final task = TaskItem(
        id: 'task-2',
        title: 'Main workday',
        taskType: TaskType.focus,
        estimatedPomodoros: 4,
        estimatedMinutes: 100,
      );
      final session = TrackedSession(
        taskId: task.id,
        startedAt: now.subtract(const Duration(hours: 2)),
        activeSeconds: (2 * 25 * 60) + (18 * 60),
        breakSeconds: 10 * 60,
        pomodorosCompleted: 2,
      );
      final active = ActiveTaskSession(
        task: task,
        session: session,
        startedAt: session.startedAt,
        openSegment: TrackedSessionSegment(
          sessionId: session.id,
          type: SessionSegmentType.active,
          startedAt: now,
          stage: PomodoroStage.focusRunning.storageValue,
          plannedDurationSeconds: 25 * 60,
        ),
        pomodoroStage: PomodoroStage.focusRunning,
      );

      final timing = active.timingAt(now);

      expect(timing.currentFocusElapsedSeconds, 0);
      expect(timing.pomodoroRemainingSeconds, 25 * 60);
      expect(timing.pomodoroStage, PomodoroStage.focusRunning);
    });
  });

  test('session segments persist Pomodoro recovery metadata', () {
    final segment = TrackedSessionSegment(
      sessionId: 'session-1',
      type: SessionSegmentType.active,
      startedAt: DateTime.utc(2026, 7, 18, 12),
      stage: PomodoroStage.focusRunning.storageValue,
      plannedDurationSeconds: 1500,
      accumulatedActiveSeconds: 120,
      accumulatedPausedSeconds: 30,
      completedAt: DateTime.utc(2026, 7, 18, 12, 25),
      transitionReason: 'planned_duration_reached',
      controllingDeviceId: 'android-test',
      lastCheckpointAt: DateTime.utc(2026, 7, 18, 12, 10),
    );

    final restored = TrackedSessionSegment.fromMap({
      'id': segment.id,
      ...segment.toInsertMap(),
    });

    expect(restored.stage, PomodoroStage.focusRunning.storageValue);
    expect(restored.plannedDurationSeconds, 1500);
    expect(restored.accumulatedActiveSeconds, 120);
    expect(restored.accumulatedPausedSeconds, 30);
    expect(restored.transitionReason, 'planned_duration_reached');
    expect(restored.controllingDeviceId, 'android-test');
    expect(restored.lastCheckpointAt, DateTime.utc(2026, 7, 18, 12, 10));
  });

  test('Health Connect native statuses are not collapsed into fake denial', () {
    expect(
      HealthDataService.statusFromNative('available'),
      HealthProviderStatus.available,
    );
    expect(
      HealthDataService.statusFromNative('partially_connected'),
      HealthProviderStatus.partiallyConnected,
    );
    expect(
      HealthDataService.statusFromNative('permission_declined'),
      HealthProviderStatus.permissionDeclined,
    );
    expect(
      HealthDataService.statusFromNative('permission_revoked'),
      HealthProviderStatus.permissionRevoked,
    );
  });

  test('profile sex and cycle settings survive model copies', () {
    const profile = AppUserProfile(
      id: 'user-1',
      email: 'yasser@example.com',
      displayName: 'Yasser',
      username: 'yasser',
      locale: 'en',
      role: AppRole.user,
      onboardingCompleted: true,
      sex: UserSex.female,
      cycleTrackingEnabled: true,
      cycleDataSyncEnabled: false,
    );

    final updated = profile.copyWith(
      sex: UserSex.preferNotToSay,
      cycleTrackingEnabled: false,
      cycleDataSyncEnabled: false,
    );

    expect(UserSexX.fromStorage('female'), UserSex.female);
    expect(updated.sex, UserSex.preferNotToSay);
    expect(updated.cycleTrackingEnabled, isFalse);
    expect(updated.cycleDataSyncEnabled, isFalse);
  });

  test('browser layout storage preserves all three real modes', () {
    expect(
      TaskBrowserLayoutModeX.fromStorage('collapsed'),
      TaskBrowserLayoutMode.collapsed,
    );
    expect(
      TaskBrowserLayoutModeX.fromStorage('right_panel'),
      TaskBrowserLayoutMode.split,
    );
    expect(
      TaskBrowserLayoutModeX.fromStorage('full_browser'),
      TaskBrowserLayoutMode.full,
    );
  });

  group('active session timing', () {
    test('combines persisted active time with the open active segment', () {
      final now = DateTime(2026, 7, 17, 20, 0);
      final task = TaskItem(
        title: 'Protected family time',
        taskType: TaskType.timed,
        estimatedMinutes: 5,
      );
      final session = TrackedSession(
        taskId: task.id,
        startedAt: now.subtract(const Duration(minutes: 3)),
        activeSeconds: 120,
        pausedSeconds: 30,
        status: TrackedSessionStatus.running,
      );
      final active = ActiveTaskSession(
        task: task,
        session: session,
        startedAt: session.startedAt,
        openSegment: TrackedSessionSegment(
          sessionId: session.id,
          type: SessionSegmentType.active,
          startedAt: now.subtract(const Duration(seconds: 10)),
        ),
      );

      final timing = active.timingAt(now);

      expect(timing.activeSeconds, 130);
      expect(timing.pausedSeconds, 30);
      expect(timing.remainingSeconds, 170);
      expect(timing.overtimeSeconds, 0);
    });

    test('paused segments accumulate without increasing active elapsed', () {
      final now = DateTime(2026, 7, 17, 20, 0);
      final task = TaskItem(
        title: 'Laundry',
        taskType: TaskType.timed,
        estimatedMinutes: 10,
      );
      final session = TrackedSession(
        taskId: task.id,
        startedAt: now.subtract(const Duration(minutes: 4)),
        activeSeconds: 120,
        pausedSeconds: 20,
        status: TrackedSessionStatus.paused,
      );
      final pausedAt = now.subtract(const Duration(seconds: 40));
      final active = ActiveTaskSession(
        task: task,
        session: session,
        startedAt: session.startedAt,
        pausedAt: pausedAt,
        openSegment: TrackedSessionSegment(
          sessionId: session.id,
          type: SessionSegmentType.paused,
          startedAt: pausedAt,
        ),
      );

      final timing = active.timingAt(now);

      expect(timing.activeSeconds, 120);
      expect(timing.pausedSeconds, 60);
      expect(timing.isPaused, isTrue);
    });

    test('overtime never exposes a negative remaining duration', () {
      final now = DateTime(2026, 7, 17, 20, 0);
      final task = TaskItem(
        title: 'Household task',
        taskType: TaskType.timed,
        estimatedMinutes: 1,
      );
      final session = TrackedSession(
        taskId: task.id,
        startedAt: now.subtract(const Duration(seconds: 70)),
        activeSeconds: 70,
        status: TrackedSessionStatus.running,
      );
      final active = ActiveTaskSession(
        task: task,
        session: session,
        startedAt: session.startedAt,
      );

      final timing = active.timingAt(now);

      expect(timing.remainingSeconds, 0);
      expect(timing.overtimeSeconds, 10);
      expect(timing.isOvertime, isTrue);
    });
  });
}
