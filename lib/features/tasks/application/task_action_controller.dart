import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../../../core/platform/task_reminder_scheduler.dart';
import '../../pomodoro/domain/pomodoro_models.dart';
import '../../sessions/application/time_analytics_service.dart';
import '../../sessions/data/session_recovery_store.dart';
import '../../sessions/domain/session_models.dart';
import '../data/task_repository.dart';
import '../domain/task_activity.dart';
import '../domain/task_category.dart';
import '../domain/task_item.dart';
import '../domain/task_support_models.dart';
import '../domain/task_workspace_config.dart';

enum TaskSyncState { idle, syncing, synced, failed }

class ActiveTaskSession {
  const ActiveTaskSession({
    required this.task,
    required this.session,
    required this.startedAt,
    this.openSegment,
    this.pausedAt,
    this.interruptionCount = 0,
    this.pomodoroStage = PomodoroStage.idle,
  });

  final TaskItem task;
  final TrackedSession session;
  final DateTime startedAt;
  final TrackedSessionSegment? openSegment;
  final DateTime? pausedAt;
  final int interruptionCount;
  final PomodoroStage pomodoroStage;

  bool get isPaused => pausedAt != null || pomodoroStage.isPaused;
  bool get isPomodoroFocusTask => task.taskType == TaskType.focus;
  bool get isPomodoroBreak =>
      pomodoroStage.isBreakStage ||
      openSegment?.type == SessionSegmentType.breakTime;
  bool get isPomodoroWaiting => pomodoroStage.isWaiting;

  ActiveSessionTiming timingAt(DateTime now) {
    final open = openSegment;
    final openSeconds = open == null || !open.isOpen
        ? 0
        : now.difference(open.startedAt).inSeconds.clamp(0, 1 << 31);
    var activeSeconds = session.activeSeconds;
    var pausedSeconds = session.pausedSeconds;
    var idleSeconds = session.idleSeconds;
    var interruptedSeconds = session.interruptedSeconds;
    var breakSeconds = session.breakSeconds;

    if (open != null && open.isOpen) {
      if (open.type.countsAsActive) {
        activeSeconds += openSeconds;
      } else {
        switch (open.type) {
          case SessionSegmentType.paused:
            pausedSeconds += openSeconds;
            break;
          case SessionSegmentType.idle:
            idleSeconds += openSeconds;
            break;
          case SessionSegmentType.interruption:
            interruptedSeconds += openSeconds;
            break;
          case SessionSegmentType.breakTime:
            breakSeconds += openSeconds;
            break;
          case SessionSegmentType.active:
          case SessionSegmentType.manual:
          case SessionSegmentType.video:
          case SessionSegmentType.reading:
          case SessionSegmentType.externalResource:
            break;
        }
      }
    }

    final plannedSeconds = (task.estimatedMinutes * 60).clamp(0, 1 << 31);
    final pomodoroSeconds = task.estimatedPomodoros > 0 && plannedSeconds > 0
        ? (plannedSeconds ~/ task.estimatedPomodoros).clamp(60, 2 * 60 * 60)
        : 25 * 60;
    final persistedPomodoros = session.pomodorosCompleted;
    final completedPomodoroSeconds = persistedPomodoros * pomodoroSeconds;
    final elapsedInCurrentPomodoro = (activeSeconds - completedPomodoroSeconds)
        .clamp(0, pomodoroSeconds)
        .toInt();
    final currentFocusElapsedSeconds =
        task.taskType == TaskType.focus && pomodoroSeconds > 0
        ? switch (pomodoroStage) {
            PomodoroStage.focusRunning =>
              ((open?.accumulatedActiveSeconds ?? 0) +
                      (open?.type.countsAsActive == true ? openSeconds : 0))
                  .clamp(0, pomodoroSeconds)
                  .toInt(),
            PomodoroStage.focusPaused =>
              (open?.accumulatedActiveSeconds ?? elapsedInCurrentPomodoro)
                  .clamp(0, pomodoroSeconds)
                  .toInt(),
            PomodoroStage.focusCompletedWaiting => pomodoroSeconds,
            PomodoroStage.focusReady ||
            PomodoroStage.idle ||
            PomodoroStage.taskCompleted ||
            PomodoroStage.cancelled => 0,
            PomodoroStage.breakReady ||
            PomodoroStage.breakRunning ||
            PomodoroStage.breakPaused ||
            PomodoroStage.breakCompletedWaiting => 0,
          }
        : 0;
    final breakPlannedSeconds =
        open?.plannedDurationSeconds ?? _breakSecondsForTask(task);
    final currentBreakElapsedSeconds =
        task.taskType == TaskType.focus && open != null && open.isOpen
        ? switch (pomodoroStage) {
            PomodoroStage.breakRunning =>
              (open.accumulatedActiveSeconds +
                      (open.type == SessionSegmentType.breakTime
                          ? openSeconds
                          : 0))
                  .clamp(0, breakPlannedSeconds)
                  .toInt(),
            PomodoroStage.breakPaused =>
              open.accumulatedActiveSeconds
                  .clamp(0, breakPlannedSeconds)
                  .toInt(),
            PomodoroStage.breakCompletedWaiting => breakPlannedSeconds,
            _ => 0,
          }
        : 0;

    return ActiveSessionTiming(
      observedAt: now,
      activeSeconds: activeSeconds,
      pausedSeconds: pausedSeconds,
      idleSeconds: idleSeconds,
      interruptedSeconds: interruptedSeconds,
      breakSeconds: breakSeconds,
      grossSeconds: session.grossSeconds + openSeconds,
      plannedSeconds: plannedSeconds,
      pomodoroSeconds: pomodoroSeconds,
      completedPomodoros: persistedPomodoros,
      isPaused: isPaused,
      isFocusTask: task.taskType == TaskType.focus,
      pomodoroStage: task.taskType == TaskType.focus
          ? pomodoroStage
          : PomodoroStage.idle,
      currentFocusElapsedSeconds: currentFocusElapsedSeconds,
      currentBreakElapsedSeconds: currentBreakElapsedSeconds,
      breakPlannedSeconds: breakPlannedSeconds,
    );
  }

  int get elapsedSeconds => timingAt(DateTime.now()).activeSeconds;
}

class ActiveSessionTiming {
  const ActiveSessionTiming({
    required this.observedAt,
    required this.activeSeconds,
    required this.pausedSeconds,
    required this.idleSeconds,
    required this.interruptedSeconds,
    required this.breakSeconds,
    required this.grossSeconds,
    required this.plannedSeconds,
    required this.pomodoroSeconds,
    required this.completedPomodoros,
    required this.isPaused,
    required this.isFocusTask,
    required this.pomodoroStage,
    required this.currentFocusElapsedSeconds,
    required this.currentBreakElapsedSeconds,
    required this.breakPlannedSeconds,
  });

  final DateTime observedAt;
  final int activeSeconds;
  final int pausedSeconds;
  final int idleSeconds;
  final int interruptedSeconds;
  final int breakSeconds;
  final int grossSeconds;
  final int plannedSeconds;
  final int pomodoroSeconds;
  final int completedPomodoros;
  final bool isPaused;
  final bool isFocusTask;
  final PomodoroStage pomodoroStage;
  final int currentFocusElapsedSeconds;
  final int currentBreakElapsedSeconds;
  final int breakPlannedSeconds;

  int get remainingSeconds =>
      (plannedSeconds - activeSeconds).clamp(0, plannedSeconds);
  int get overtimeSeconds => (activeSeconds - plannedSeconds).clamp(0, 1 << 31);
  bool get isOvertime => plannedSeconds > 0 && activeSeconds > plannedSeconds;
  double get plannedProgress => plannedSeconds <= 0
      ? 0
      : (activeSeconds / plannedSeconds).clamp(0.0, 1.0);
  int get currentPomodoroElapsedSeconds => currentFocusElapsedSeconds;
  int get pomodoroRemainingSeconds => pomodoroSeconds <= 0
      ? 0
      : (pomodoroSeconds - currentPomodoroElapsedSeconds).clamp(
          0,
          pomodoroSeconds,
        );
  double get pomodoroProgress => pomodoroSeconds <= 0
      ? 0
      : (currentPomodoroElapsedSeconds / pomodoroSeconds).clamp(0.0, 1.0);
  int get breakRemainingSeconds =>
      (breakPlannedSeconds - currentBreakElapsedSeconds).clamp(
        0,
        breakPlannedSeconds,
      );
}

class TaskActionController extends ChangeNotifier {
  TaskActionController(
    this._repository, {
    SessionRecoveryStore? recoveryStore,
    TaskReminderScheduler? reminderScheduler,
  }) : _recoveryStore = recoveryStore ?? SessionRecoveryStore(),
       _reminderScheduler = reminderScheduler ?? const TaskReminderScheduler();

  final TaskRepository _repository;
  final SessionRecoveryStore _recoveryStore;
  final TaskReminderScheduler _reminderScheduler;
  final TimeAnalyticsService _analytics = const TimeAnalyticsService();

  List<TaskItem> _tasks = const [];
  List<TaskItem> _deletedTasks = const [];
  List<TaskCategory> _categories = const [];
  List<TrackedSession> _sessions = const [];
  List<QuickNote> _quickNotes = const [];
  final Map<String, List<TaskNote>> _notesByTask = {};
  final Map<String, List<TaskInterruption>> _interruptionsByTask = {};
  final Map<String, List<TrackedSession>> _sessionsByTask = {};
  final Map<String, List<TrackedSessionSegment>> _segmentsBySession = {};
  final Map<String, List<TaskProgressEntry>> _progressByTask = {};
  final Map<String, List<TaskResource>> _resourcesByTask = {};
  final Map<String, List<TaskReminder>> _remindersByTask = {};
  final Map<String, List<TaskUsageActivity>> _usageByTask = {};
  final ValueNotifier<DateTime> _activeSessionClock = ValueNotifier(
    DateTime.now(),
  );
  Timer? _activeClockTimer;
  Timer? _remoteRefreshDebounce;
  Stopwatch? _activeClockStopwatch;
  DateTime? _activeClockAnchor;
  int _activeClockTicks = 0;
  bool _pomodoroCompletionInProgress = false;
  bool _remoteRefreshInFlight = false;
  RealtimeChannel? _syncChannel;
  String? _syncUserId;
  String? _deviceId;
  TaskEditorLinks? _editorLinks;
  ActiveTaskSession? _activeSession;
  SessionControlClaim? _blockedSessionClaim;
  TaskItem? _blockedSessionTask;
  TaskSyncState _syncState = TaskSyncState.idle;
  String? _error;

  List<TaskItem> get tasks => _tasks;
  List<TaskItem> get deletedTasks => _deletedTasks;
  List<TaskCategory> get categories => _categories;
  List<TrackedSession> get sessions => _sessions;
  List<QuickNote> get quickNotes => _quickNotes;
  List<TaskUsageActivity> get cachedUsageRecords => [
    for (final records in _usageByTask.values) ...records,
  ];
  ActiveTaskSession? get activeSession => _activeSession;
  SessionControlClaim? get blockedSessionClaim => _blockedSessionClaim;
  TaskItem? get blockedSessionTask => _blockedSessionTask;
  ValueListenable<DateTime> get activeSessionClock => _activeSessionClock;
  ActiveSessionTiming? get activeTiming =>
      _activeSession?.timingAt(_activeSessionClock.value);
  TaskSyncState get syncState => _syncState;
  String? get error => _error;

  Future<void> recordWidgetAction({
    required String commandType,
    required DateTime localOccurredAt,
    String widgetKind = 'active_timer',
    String? sessionId,
    String? taskId,
    String status = 'applied',
    Map<String, Object?> payload = const {},
    String? errorMessage,
  }) {
    return _repository.recordWidgetActionEvent(
      commandType: commandType,
      localOccurredAt: localOccurredAt,
      widgetKind: widgetKind,
      sessionId: sessionId,
      taskId: taskId,
      status: status,
      payload: payload,
      errorMessage: errorMessage,
    );
  }

  Future<void> load() async {
    final cached = await Future.wait([
      _repository.loadLocalTasks(),
      _repository.loadLocalTasks(deleted: true),
    ]);
    _tasks = cached[0];
    _deletedTasks = cached[1];
    if (_tasks.isNotEmpty || _deletedTasks.isNotEmpty) {
      notifyListeners();
    }
    await _runSync(() async {
      await _repository.synchronizePendingOperations();
      await Future.wait([
        _loadTasks(),
        _loadDeletedTasks(),
        _loadCategories(),
        _loadSessions(),
        _loadQuickNotes(),
      ]);
      await _loadRecoveryCheckpoint();
      await _loadTodayInterruptions();
      await _restoreReminderSchedule();
    });
    unawaited(_ensureRealtimeSubscription());
  }

  Future<void> _loadQuickNotes() async {
    _quickNotes = await _repository.loadQuickNotes();
  }

  Future<void> _ensureRealtimeSubscription() async {
    final client = _repository.clientOrNull;
    final userId = _repository.currentUserId;
    if (client == null || userId == null) {
      return;
    }
    if (_syncChannel != null && _syncUserId == userId) {
      return;
    }
    await _removeRealtimeSubscription();
    _syncUserId = userId;
    _deviceId = await _repository.loadDeviceId();
    final channel = client.channel(
      'taskmaster:user:$userId:runtime',
      opts: const RealtimeChannelConfig(private: true),
    );
    _syncChannel = channel
        .onBroadcast(event: 'task_changed', callback: _handleRealtimeSyncEvent)
        .onBroadcast(
          event: 'session_changed',
          callback: _handleRealtimeSyncEvent,
        )
        .onBroadcast(
          event: 'activity_changed',
          callback: _handleRealtimeSyncEvent,
        )
        .onBroadcast(
          event: 'roadmap_changed',
          callback: _handleRealtimeSyncEvent,
        )
        .subscribe((status, [error]) {
          if (kDebugMode && status == RealtimeSubscribeStatus.channelError) {
            debugPrint('TASK REALTIME ERROR: $error');
          }
        });
  }

  Future<void> _removeRealtimeSubscription() async {
    final channel = _syncChannel;
    _syncChannel = null;
    _syncUserId = null;
    if (channel == null) return;
    try {
      await _repository.clientOrNull?.removeChannel(channel);
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('TASK REALTIME REMOVE FAILED: $error');
      }
    }
  }

  void _handleRealtimeSyncEvent(Map<String, dynamic> payload) {
    final nested = payload['payload'];
    final record = nested is Map ? Map<String, dynamic>.from(nested) : payload;
    if (record.isEmpty) return;
    final eventDevice = record['device_id']?.toString();
    if (eventDevice != null && eventDevice == _deviceId) {
      return;
    }
    final entityType = record['entity_type']?.toString();
    if (entityType == null ||
        !{'task', 'session', 'activity'}.contains(entityType)) {
      return;
    }
    _remoteRefreshDebounce?.cancel();
    _remoteRefreshDebounce = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_refreshFromRealtimeEvent()),
    );
  }

  Future<void> _refreshFromRealtimeEvent() async {
    if (_remoteRefreshInFlight) return;
    _remoteRefreshInFlight = true;
    try {
      await _repository.synchronizePendingOperations();
      await Future.wait([
        _loadTasks(),
        _loadDeletedTasks(),
        _loadSessions(),
        _loadTodayInterruptions(),
      ]);
      await _restoreReminderSchedule();
      notifyListeners();
    } on Object catch (error) {
      _error = error.toString();
      if (kDebugMode) {
        debugPrint('TASK REALTIME REFRESH FAILED: $error');
      }
    } finally {
      _remoteRefreshInFlight = false;
    }
  }

  Future<void> rescheduleRemindersForTimeZoneChange() async {
    await _reconcileReminderSchedule();
    notifyListeners();
  }

  Future<void> startTask(TaskItem task) async {
    final now = DateTime.now();
    final deviceId = await _repository.loadDeviceId();
    final updated = task.copyWith(status: TaskStatus.running);
    final baseSession = TrackedSession(
      taskId: task.id,
      categoryName: task.category,
      deviceId: deviceId,
      type: _sessionTypeForTask(task),
      trackingMode: _trackingModeForTask(task),
      status: TrackedSessionStatus.running,
      startedAt: now,
    );
    _blockedSessionClaim = null;
    _blockedSessionTask = null;
    final segment = TrackedSessionSegment(
      sessionId: baseSession.id,
      type: _activeSegmentTypeForMode(baseSession.trackingMode),
      startedAt: now,
      trackingMode: baseSession.trackingMode,
      stage: task.taskType == TaskType.focus
          ? PomodoroStage.focusRunning.storageValue
          : null,
      plannedDurationSeconds: task.taskType == TaskType.focus
          ? _pomodoroSecondsForTask(task)
          : null,
      lastCheckpointAt: now,
    );
    final session = baseSession.copyWith(
      stage: segment.stage,
      currentSegmentId: segment.id,
      plannedDurationSeconds: segment.plannedDurationSeconds,
      lastResumedAt: now,
      accumulatedActiveSeconds: segment.accumulatedActiveSeconds,
      accumulatedPausedSeconds: segment.accumulatedPausedSeconds,
      sourceDeviceId: deviceId,
    );

    _activeSession = ActiveTaskSession(
      task: updated,
      session: session,
      startedAt: now,
      openSegment: segment,
      pomodoroStage: task.taskType == TaskType.focus
          ? PomodoroStage.focusRunning
          : PomodoroStage.idle,
    );
    _startActiveClock(now);
    unawaited(_saveRecoveryCheckpoint('running'));

    await _runSync(() async {
      final savedSession = await _repository.upsertSession(session);
      final savedSegment = await _repository.upsertSegment(segment);
      await _repository.addSessionEvent(
        SessionEventRecord(sessionId: session.id, eventType: 'started'),
      );
      _upsertLocalSession(savedSession);
      _segmentsBySession[session.id] = [savedSegment];
      await _saveTaskWithoutSync(updated);
      await _saveRecoveryCheckpoint('running');
      _queueSharedSessionCommand(
        task: updated,
        session: savedSession,
        commandType: task.taskType == TaskType.focus
            ? 'start_focus'
            : 'start_task',
        occurredAt: now,
        segment: savedSegment,
      );
    });
  }

  Future<void> takeControlAndStart(TaskItem task) async {
    await startTask(task);
  }

  void dismissSessionControlConflict() {
    _blockedSessionClaim = null;
    _blockedSessionTask = null;
    notifyListeners();
  }

  Future<void> pauseTask(TaskItem task) async {
    final active = _activeSession;
    final updated = task.copyWith(status: TaskStatus.paused);
    if (active == null || active.task.id != task.id) {
      await _saveTask(updated);
      return;
    }

    final now = DateTime.now();
    final timing = active.timingAt(now);
    final nextStage = active.pomodoroStage == PomodoroStage.breakRunning
        ? PomodoroStage.breakPaused
        : active.pomodoroStage == PomodoroStage.focusRunning
        ? PomodoroStage.focusPaused
        : active.pomodoroStage;
    final closed = active.openSegment
        ?.close(now)
        .copyWith(stage: nextStage.storageValue, lastCheckpointAt: now);
    final pausedSegment = TrackedSessionSegment(
      sessionId: active.session.id,
      type: SessionSegmentType.paused,
      startedAt: now,
      trackingMode: active.session.trackingMode,
      stage: nextStage.storageValue,
      plannedDurationSeconds: active.openSegment?.plannedDurationSeconds,
      accumulatedActiveSeconds: nextStage == PomodoroStage.breakPaused
          ? timing.currentBreakElapsedSeconds
          : nextStage == PomodoroStage.focusPaused
          ? timing.currentFocusElapsedSeconds
          : 0,
      accumulatedPausedSeconds: timing.pausedSeconds,
      lastCheckpointAt: now,
    );
    final nextSession = _recalculateSession(
      active.session.copyWith(status: TrackedSessionStatus.paused),
      additionalSegments: [?closed, pausedSegment],
    );
    _activeSession = ActiveTaskSession(
      task: updated,
      session: nextSession,
      startedAt: active.startedAt,
      openSegment: pausedSegment,
      pausedAt: now,
      interruptionCount: active.interruptionCount,
      pomodoroStage: nextStage,
    );
    _stopActiveClock(now);
    await _persistActiveTransition(
      task: updated,
      session: nextSession,
      closedSegment: closed,
      nextSegment: pausedSegment,
      eventType: 'paused',
      checkpointState: 'paused',
    );
  }

  Future<void> resumeTask(TaskItem task) async {
    final active = _activeSession;
    final updated = task.copyWith(status: TaskStatus.running);
    if (active == null || active.task.id != task.id) {
      await _saveTask(updated);
      return;
    }

    final now = DateTime.now();
    final timing = active.timingAt(now);
    final nextStage = active.pomodoroStage == PomodoroStage.breakPaused
        ? PomodoroStage.breakRunning
        : active.pomodoroStage == PomodoroStage.focusPaused
        ? PomodoroStage.focusRunning
        : active.pomodoroStage;
    final closed = active.openSegment
        ?.close(now)
        .copyWith(stage: nextStage.storageValue, lastCheckpointAt: now);
    final nextSegment = TrackedSessionSegment(
      sessionId: active.session.id,
      type: nextStage == PomodoroStage.breakRunning
          ? SessionSegmentType.breakTime
          : _activeSegmentTypeForMode(active.session.trackingMode),
      startedAt: now,
      trackingMode: active.session.trackingMode,
      stage: nextStage.storageValue,
      plannedDurationSeconds: nextStage == PomodoroStage.breakRunning
          ? _breakSecondsForTask(active.task)
          : nextStage == PomodoroStage.focusRunning
          ? _pomodoroSecondsForTask(active.task)
          : null,
      accumulatedActiveSeconds: nextStage == PomodoroStage.breakRunning
          ? timing.currentBreakElapsedSeconds
          : nextStage == PomodoroStage.focusRunning
          ? timing.currentFocusElapsedSeconds
          : 0,
      accumulatedPausedSeconds: timing.pausedSeconds,
      lastCheckpointAt: now,
    );
    final nextSession = _recalculateSession(
      active.session.copyWith(status: TrackedSessionStatus.running),
      additionalSegments: [?closed, nextSegment],
    );
    _activeSession = ActiveTaskSession(
      task: updated,
      session: nextSession,
      startedAt: active.startedAt,
      openSegment: nextSegment,
      interruptionCount: active.interruptionCount,
      pomodoroStage: nextStage,
    );
    _startActiveClock(now);
    await _persistActiveTransition(
      task: updated,
      session: nextSession,
      closedSegment: closed,
      nextSegment: nextSegment,
      eventType: 'resumed',
      checkpointState: 'running',
    );
  }

  Future<void> beginPomodoroBreak() async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.openSegment?.type == SessionSegmentType.breakTime ||
        active.pomodoroStage == PomodoroStage.breakRunning) {
      return;
    }
    if (active.pomodoroStage == PomodoroStage.focusRunning ||
        active.pomodoroStage == PomodoroStage.focusPaused) {
      await finishPomodoroFocus(reason: 'manual_jump_to_break');
    }
    final current = _activeSession;
    if (current == null) return;
    final now = DateTime.now();
    final nextSegment = TrackedSessionSegment(
      sessionId: current.session.id,
      type: SessionSegmentType.breakTime,
      startedAt: now,
      trackingMode: current.session.trackingMode,
      stage: PomodoroStage.breakRunning.storageValue,
      plannedDurationSeconds: _breakSecondsForTask(current.task),
      lastCheckpointAt: now,
    );
    final nextSession = _recalculateSession(
      current.session,
      additionalSegments: [nextSegment],
    );
    _activeSession = ActiveTaskSession(
      task: current.task,
      session: nextSession,
      startedAt: current.startedAt,
      openSegment: nextSegment,
      interruptionCount: current.interruptionCount,
      pomodoroStage: PomodoroStage.breakRunning,
    );
    _startActiveClock(now);
    await _persistActiveTransition(
      task: current.task,
      session: nextSession,
      nextSegment: nextSegment,
      eventType: 'pomodoro_break_started',
      checkpointState: 'running',
    );
  }

  Future<void> endPomodoroBreak() async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.openSegment?.type == SessionSegmentType.breakTime) {
      await finishPomodoroBreak(reason: 'return_to_focus');
    }
    await preparePomodoroFocus(reason: 'manual_return_to_focus');
  }

  Future<void> finishPomodoroFocus({String reason = 'completed_early'}) async {
    final active = _activeSession;
    if (active == null ||
        active.task.taskType != TaskType.focus ||
        active.pomodoroStage == PomodoroStage.focusCompletedWaiting ||
        active.pomodoroStage.isBreakStage) {
      return;
    }
    final now = DateTime.now();
    final timing = active.timingAt(now);
    final plannedFocusSeconds =
        active.openSegment?.plannedDurationSeconds ??
        _pomodoroSecondsForTask(active.task);
    final actualFocusSeconds = timing.currentFocusElapsedSeconds
        .clamp(0, plannedFocusSeconds)
        .toInt();
    final countsAsCompleted =
        reason == 'planned_duration_reached' ||
        actualFocusSeconds >= plannedFocusSeconds;
    final closed = active.openSegment
        ?.close(now)
        .copyWith(
          stage: PomodoroStage.focusCompletedWaiting.storageValue,
          completedAt: now,
          transitionReason: reason,
          plannedDurationSeconds: plannedFocusSeconds,
          accumulatedActiveSeconds: actualFocusSeconds,
          accumulatedPausedSeconds: timing.pausedSeconds,
          lastCheckpointAt: now,
        );
    final nextSession = _recalculateSession(
      active.session.copyWith(
        pomodorosCompleted:
            active.session.pomodorosCompleted + (countsAsCompleted ? 1 : 0),
      ),
      additionalSegments: [?closed],
    );
    final updatedTask = _taskWithCalculatedProgress(active.task, nextSession);
    _activeSession = ActiveTaskSession(
      task: updatedTask,
      session: nextSession,
      startedAt: active.startedAt,
      interruptionCount: active.interruptionCount,
      pomodoroStage: PomodoroStage.focusCompletedWaiting,
    );
    _stopActiveClock(now);
    await _persistActiveTransition(
      task: updatedTask,
      session: nextSession,
      closedSegment: closed,
      eventType: 'pomodoro_focus_completed',
      checkpointState: PomodoroStage.focusCompletedWaiting.storageValue,
    );
    if (reason != 'manual_jump_to_break') {
      unawaited(
        _reminderScheduler.showImmediate(
          title: 'Focus completed',
          body: '${formatSecondsForAlarm(actualFocusSeconds)} recorded.',
          channel: 'focus_alarm',
        ),
      );
    }
  }

  Future<void> goToPomodoroBreak() async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.pomodoroStage == PomodoroStage.focusRunning ||
        active.pomodoroStage == PomodoroStage.focusPaused) {
      await finishPomodoroFocus(reason: 'manual_jump_to_break');
    }
    final current = _activeSession;
    if (current == null) return;
    _activeSession = ActiveTaskSession(
      task: current.task,
      session: current.session,
      startedAt: current.startedAt,
      interruptionCount: current.interruptionCount,
      pomodoroStage: PomodoroStage.breakReady,
    );
    await _repository.addSessionEvent(
      SessionEventRecord(
        sessionId: current.session.id,
        eventType: 'pomodoro_break_ready',
        metadata: {'reason': 'manual_jump_to_break'},
      ),
    );
    await _saveRecoveryCheckpoint(PomodoroStage.breakReady.storageValue);
    notifyListeners();
  }

  Future<void> skipPomodoroBreak() async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.openSegment?.type == SessionSegmentType.breakTime) {
      await finishPomodoroBreak(reason: 'break_skipped');
    }
    final current = _activeSession;
    if (current == null) return;
    _activeSession = ActiveTaskSession(
      task: current.task,
      session: current.session,
      startedAt: current.startedAt,
      interruptionCount: current.interruptionCount,
      pomodoroStage: PomodoroStage.focusReady,
    );
    await _repository.addSessionEvent(
      SessionEventRecord(
        sessionId: current.session.id,
        eventType: 'pomodoro_break_skipped',
      ),
    );
    await _saveRecoveryCheckpoint(PomodoroStage.focusReady.storageValue);
    notifyListeners();
  }

  Future<void> continuePomodoroFocus({int minutes = 5}) async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    final now = DateTime.now();
    final nextSegment = TrackedSessionSegment(
      sessionId: active.session.id,
      type: _activeSegmentTypeForMode(active.session.trackingMode),
      startedAt: now,
      trackingMode: active.session.trackingMode,
      stage: PomodoroStage.focusRunning.storageValue,
      plannedDurationSeconds: minutes * 60,
      transitionReason: 'focus_extension',
      lastCheckpointAt: now,
    );
    final nextSession = _recalculateSession(
      active.session.copyWith(status: TrackedSessionStatus.running),
      additionalSegments: [nextSegment],
    );
    _activeSession = ActiveTaskSession(
      task: active.task,
      session: nextSession,
      startedAt: active.startedAt,
      openSegment: nextSegment,
      interruptionCount: active.interruptionCount,
      pomodoroStage: PomodoroStage.focusRunning,
    );
    _startActiveClock(now);
    await _persistActiveTransition(
      task: active.task,
      session: nextSession,
      nextSegment: nextSegment,
      eventType: 'pomodoro_focus_continued',
      checkpointState: 'running',
    );
  }

  Future<void> finishPomodoroBreak({
    String reason = 'break_finished_early',
  }) async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.openSegment?.type != SessionSegmentType.breakTime) {
      _activeSession = ActiveTaskSession(
        task: active.task,
        session: active.session,
        startedAt: active.startedAt,
        interruptionCount: active.interruptionCount,
        pomodoroStage: PomodoroStage.breakCompletedWaiting,
      );
      _stopActiveClock();
      await _saveRecoveryCheckpoint(
        PomodoroStage.breakCompletedWaiting.storageValue,
      );
      notifyListeners();
      return;
    }
    final now = DateTime.now();
    final timing = active.timingAt(now);
    final closed = active.openSegment!
        .close(now)
        .copyWith(
          stage: PomodoroStage.breakCompletedWaiting.storageValue,
          completedAt: now,
          transitionReason: reason,
          accumulatedActiveSeconds: timing.currentBreakElapsedSeconds,
          accumulatedPausedSeconds: timing.pausedSeconds,
          lastCheckpointAt: now,
        );
    final nextSession = _recalculateSession(
      active.session,
      additionalSegments: [closed],
    );
    _activeSession = ActiveTaskSession(
      task: active.task,
      session: nextSession,
      startedAt: active.startedAt,
      interruptionCount: active.interruptionCount,
      pomodoroStage: PomodoroStage.breakCompletedWaiting,
    );
    _stopActiveClock(now);
    await _persistActiveTransition(
      task: active.task,
      session: nextSession,
      closedSegment: closed,
      eventType: 'pomodoro_break_completed',
      checkpointState: PomodoroStage.breakCompletedWaiting.storageValue,
    );
    if (reason == 'planned_duration_reached') {
      unawaited(
        _reminderScheduler.showImmediate(
          title: 'Break completed',
          body: 'Choose your next step.',
          channel: 'break_alarm',
        ),
      );
    }
  }

  Future<void> preparePomodoroFocus({
    String reason = 'manual_return_to_focus',
  }) async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.openSegment?.type == SessionSegmentType.breakTime) {
      await finishPomodoroBreak(reason: reason);
    }
    final current = _activeSession;
    if (current == null) return;
    final now = DateTime.now();
    final nextSession = current.session.copyWith(
      status: TrackedSessionStatus.running,
    );
    _activeSession = ActiveTaskSession(
      task: current.task,
      session: nextSession,
      startedAt: current.startedAt,
      interruptionCount: current.interruptionCount,
      pomodoroStage: PomodoroStage.focusReady,
    );
    _stopActiveClock(now);
    await _persistActiveTransition(
      task: current.task,
      session: nextSession,
      eventType: 'pomodoro_focus_ready',
      checkpointState: PomodoroStage.focusReady.storageValue,
    );
  }

  Future<void> startPomodoroFocus({
    String reason = 'user_started_focus',
  }) async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.pomodoroStage == PomodoroStage.focusRunning) return;
    if (active.openSegment?.type == SessionSegmentType.breakTime) {
      await finishPomodoroBreak(reason: reason);
    }
    final current = _activeSession;
    if (current == null) return;
    final now = DateTime.now();
    final nextSegment = TrackedSessionSegment(
      sessionId: current.session.id,
      type: _activeSegmentTypeForMode(current.session.trackingMode),
      startedAt: now,
      trackingMode: current.session.trackingMode,
      stage: PomodoroStage.focusRunning.storageValue,
      plannedDurationSeconds: _pomodoroSecondsForTask(current.task),
      transitionReason: reason,
      lastCheckpointAt: now,
    );
    final nextSession = _recalculateSession(
      current.session.copyWith(status: TrackedSessionStatus.running),
      additionalSegments: [nextSegment],
    );
    _activeSession = ActiveTaskSession(
      task: current.task,
      session: nextSession,
      startedAt: current.startedAt,
      openSegment: nextSegment,
      interruptionCount: current.interruptionCount,
      pomodoroStage: PomodoroStage.focusRunning,
    );
    _startActiveClock(now);
    await _persistActiveTransition(
      task: current.task,
      session: nextSession,
      nextSegment: nextSegment,
      eventType: 'pomodoro_focus_started',
      checkpointState: 'running',
    );
  }

  Future<void> returnPomodoroToFocus() =>
      startPomodoroFocus(reason: 'user_started_focus');

  Future<void> extendPomodoroBreak({int minutes = 5}) async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    if (active.openSegment?.type == SessionSegmentType.breakTime) {
      final extended = active.openSegment!.copyWith(
        plannedDurationSeconds:
            (active.openSegment!.plannedDurationSeconds ??
                _breakSecondsForTask(active.task)) +
            minutes * 60,
        transitionReason: 'break_extended',
        lastCheckpointAt: DateTime.now(),
      );
      _activeSession = ActiveTaskSession(
        task: active.task,
        session: active.session,
        startedAt: active.startedAt,
        openSegment: extended,
        interruptionCount: active.interruptionCount,
        pomodoroStage: PomodoroStage.breakRunning,
      );
      await _repository.upsertSegment(extended);
      await _saveRecoveryCheckpoint('running');
      notifyListeners();
      return;
    }
    await beginPomodoroBreak();
  }

  Future<void> recordPomodoroBreakActivity(
    PomodoroBreakUse use, {
    String? relatedTaskId,
  }) async {
    final active = _activeSession;
    if (active == null || active.task.taskType != TaskType.focus) return;
    await _repository.addSessionEvent(
      SessionEventRecord(
        sessionId: active.session.id,
        eventType: 'pomodoro_break_activity_classified',
        metadata: {
          'activity': use.name,
          ...?relatedTaskId == null ? null : {'related_task_id': relatedTaskId},
          'stage': active.pomodoroStage.storageValue,
        },
      ),
    );
    notifyListeners();
  }

  Future<void> stopActiveSession({bool discard = false}) async {
    final active = _activeSession;
    if (active == null) return;
    final now = DateTime.now();
    final closed = active.openSegment?.close(now);
    final stopped = _recalculateSession(
      active.session.copyWith(
        status: discard
            ? TrackedSessionStatus.discarded
            : TrackedSessionStatus.stopped,
        endedAt: now,
        completionReason: discard ? 'discarded_by_user' : 'session_saved',
      ),
      additionalSegments: [?closed],
      endAt: now,
    );
    final task = active.task.copyWith(status: TaskStatus.paused);
    _activeSession = null;
    _stopActiveClock(now);
    await _runSync(() async {
      if (closed != null) await _repository.upsertSegment(closed);
      final saved = await _repository.upsertSession(stopped);
      await _repository.addSessionEvent(
        SessionEventRecord(
          sessionId: stopped.id,
          eventType: discard ? 'discarded' : 'stopped',
          eventTime: now,
        ),
      );
      _upsertLocalSession(saved);
      await _saveTaskWithoutSync(task);
      await _repository.releaseSessionControl(stopped.id);
      await _clearRecoveryCheckpoint();
    });
  }

  Future<void> completeTask(TaskItem task) async {
    final active = _activeSession;
    final now = DateTime.now();
    TrackedSession? completedSession;
    TrackedSessionSegment? closed;

    if (active?.task.id == task.id) {
      closed = active!.openSegment?.close(now);
      completedSession = _recalculateSession(
        active.session.copyWith(
          status: TrackedSessionStatus.completed,
          endedAt: now,
          completionReason: 'completed_task',
        ),
        additionalSegments: [?closed],
        endAt: now,
      );
      _activeSession = null;
      _stopActiveClock(now);
    }

    final activeMinutes = completedSession == null
        ? task.actualFocusedMinutes
        : (completedSession.activeSeconds / 60).round();
    final updated = task.copyWith(
      status: TaskStatus.completed,
      progressPercentage: 100,
      actualFocusedMinutes: activeMinutes,
    );

    await _runSync(() async {
      if (closed != null) {
        await _repository.upsertSegment(closed);
      }
      if (completedSession != null) {
        final saved = await _repository.upsertSession(completedSession);
        await _repository.addSessionEvent(
          SessionEventRecord(
            sessionId: completedSession.id,
            eventType: 'completed',
            eventTime: now,
          ),
        );
        _upsertLocalSession(saved);
        await _repository.releaseSessionControl(completedSession.id);
        await _clearRecoveryCheckpoint();
      }
      await _saveTaskWithoutSync(updated);
      await _addProgressEntryWithoutSync(
        TaskProgressEntry(
          taskId: updated.id,
          sessionId: completedSession?.id,
          progressPercentage: 100,
          summary: 'Task completed',
          recordedAt: now,
        ),
      );
      await _reminderScheduler.cancelTask(task.id);
    });
  }

  Future<void> cancelTask(TaskItem task) async {
    final updated = task.copyWith(status: TaskStatus.cancelled);
    final activeSessionId = _activeSession?.task.id == task.id
        ? _activeSession?.session.id
        : null;
    if (_activeSession?.task.id == task.id) {
      _activeSession = null;
      _stopActiveClock();
      await _clearRecoveryCheckpoint();
    }
    if (activeSessionId != null) {
      await _repository.releaseSessionControl(activeSessionId);
    }
    await _saveTask(updated);
    await _reminderScheduler.cancelTask(task.id);
  }

  Future<void> markEventArrived(TaskItem task) async {
    await _saveTask(
      task.copyWith(
        eventState: TaskEventState.arrived,
        arrivalAt: DateTime.now(),
      ),
    );
  }

  Future<void> updateProgress(TaskItem task, int progress) async {
    final safeProgress = progress.clamp(0, 100);
    await _runSync(() async {
      await _saveTaskWithoutSync(
        task.copyWith(progressPercentage: safeProgress),
      );
      await _addProgressEntryWithoutSync(
        TaskProgressEntry(
          taskId: task.id,
          sessionId: _activeSession?.session.id,
          progressPercentage: safeProgress,
          summary: 'Progress updated',
        ),
      );
    });
  }

  Future<void> addTask(TaskItem task) async {
    final previousTasks = _tasks;
    _tasks = [task, ..._tasks.where((item) => item.id != task.id)];
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.createTask(task);
      _tasks = [saved, ..._tasks.where((item) => item.id != saved.id)];
      _syncState = TaskSyncState.synced;
    } on Object catch (error) {
      _tasks = previousTasks;
      _syncState = TaskSyncState.failed;
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> addTaskBundle({
    required TaskItem task,
    required List<TaskResource> resources,
    required List<TaskReminder> reminders,
  }) async {
    final previousTasks = _tasks;
    _tasks = [task, ..._tasks.where((item) => item.id != task.id)];
    _resourcesByTask[task.id] = resources;
    _remindersByTask[task.id] = reminders;
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      var saved = await _repository.createTask(task);
      await _repository.replaceTaskResources(saved.id, resources);
      await _repository.replaceTaskReminders(saved.id, reminders);
      if (task.defaultResourceId != null) {
        saved = await _repository.updateTask(
          saved.copyWith(defaultResourceId: task.defaultResourceId),
        );
      }
      _upsertLocalTask(saved);
      await _reminderScheduler.scheduleForTask(saved, reminders);
      _syncState = TaskSyncState.synced;
    } on Object catch (error) {
      _tasks = previousTasks;
      _resourcesByTask.remove(task.id);
      _remindersByTask.remove(task.id);
      _syncState = TaskSyncState.failed;
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> editTask(TaskItem task) async {
    await _saveTask(task);
  }

  Future<void> editTaskBundle({
    required TaskItem task,
    required List<TaskResource> resources,
    required List<TaskReminder> reminders,
    RecurrenceEditScope scope = RecurrenceEditScope.occurrence,
  }) async {
    final previousTasks = _tasks;
    final previousResources = _resourcesByTask[task.id];
    final previousReminders = _remindersByTask[task.id];
    _upsertLocalTask(task);
    _resourcesByTask[task.id] = resources;
    _remindersByTask[task.id] = reminders;
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.saveTaskBundle(
        task: task,
        resources: resources,
        reminders: reminders,
        scope: scope,
      );
      _upsertLocalTask(saved);
      await _reminderScheduler.scheduleForTask(saved, reminders);
      if (scope != RecurrenceEditScope.occurrence) {
        await _reconcileReminderSchedule();
      }
      _syncState = TaskSyncState.synced;
    } on Object catch (error) {
      _tasks = previousTasks;
      if (previousResources == null) {
        _resourcesByTask.remove(task.id);
      } else {
        _resourcesByTask[task.id] = previousResources;
      }
      if (previousReminders == null) {
        _remindersByTask.remove(task.id);
      } else {
        _remindersByTask[task.id] = previousReminders;
      }
      _syncState = TaskSyncState.failed;
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> duplicateTask(TaskItem task) async {
    final duplicate = task.duplicate();
    await addTask(duplicate);
    final resources = await resourcesForTask(task);
    if (resources.isNotEmpty) {
      final copied = [
        for (final resource in resources)
          TaskResource(
            taskId: duplicate.id,
            name: resource.name,
            url: resource.url,
            type: resource.type,
            openMode: resource.openMode,
            description: resource.description,
            sortOrder: resource.sortOrder,
            isDefault: resource.isDefault,
            isRequired: resource.isRequired,
            isFavorite: resource.isFavorite,
            openAutomatically: resource.openAutomatically,
          ),
      ];
      await editTaskBundle(
        task: duplicate,
        resources: copied,
        reminders: const [],
      );
    }
  }

  Future<void> archiveTask(TaskItem task) async {
    final previous = _tasks;
    _tasks = _tasks.where((item) => item.id != task.id).toList(growable: false);
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      await _repository.archiveTask(task);
      await _reminderScheduler.cancelTask(task.id);
      _syncState = TaskSyncState.synced;
    } on Object catch (error) {
      _tasks = previous;
      _syncState = TaskSyncState.failed;
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> skipToday(TaskItem task) async {
    final previous = _tasks;
    final skipped = task.copyWith(
      status: TaskStatus.cancelled,
      skippedAt: DateTime.now(),
      isRecurrenceException: true,
    );
    _upsertLocalTask(skipped);
    notifyListeners();
    try {
      await _repository.skipOccurrence(task);
      await _reminderScheduler.cancelTask(task.id);
    } on Object catch (error) {
      _tasks = previous;
      _error = error.toString();
      _syncState = TaskSyncState.failed;
      notifyListeners();
    }
  }

  Future<void> pauseRecurrence(TaskItem task) async {
    final paused = task.copyWith(recurrencePausedAt: DateTime.now());
    _upsertLocalTask(paused);
    notifyListeners();
    await _runSync(() => _repository.setRecurrenceState(task, 'pause'));
  }

  Future<void> resumeRecurrence(TaskItem task) async {
    final resumed = task.copyWith(clearRecurrencePause: true);
    _upsertLocalTask(resumed);
    notifyListeners();
    await _runSync(() => _repository.setRecurrenceState(task, 'resume'));
  }

  Future<void> endRecurrence(TaskItem task) async {
    await _runSync(() => _repository.setRecurrenceState(task, 'end'));
    await _reminderScheduler.cancelTask(task.id);
  }

  Future<List<TaskResource>> resourcesForTask(TaskItem task) async {
    if (_resourcesByTask.containsKey(task.id)) {
      return _resourcesByTask[task.id]!;
    }
    final resources = await _repository.loadTaskResources(task);
    _resourcesByTask[task.id] = resources;
    notifyListeners();
    return resources;
  }

  Future<String?> relatedTaskForDomain(
    String domain, {
    String? excludingTaskId,
  }) async {
    final normalized = domain.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    for (final task in _tasks) {
      if (task.id == excludingTaskId || task.isCompleted) continue;
      final legacy = [
        task.workspaceStartingUrl,
        task.workspaceHomeUrl,
        task.learningResourceLink,
      ];
      if (legacy.any((value) {
        final host = Uri.tryParse(
          value ?? '',
        )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
        return host == normalized;
      })) {
        return task.id;
      }
      final cached = _resourcesByTask[task.id];
      if (cached?.any((resource) => resource.domain == normalized) == true) {
        return task.id;
      }
    }
    final taskId = await _repository.findTaskIdForResourceDomain(normalized);
    return taskId == excludingTaskId ? null : taskId;
  }

  Future<TaskEditorLinks> taskEditorLinks({bool refresh = false}) async {
    if (!refresh && _editorLinks != null) return _editorLinks!;
    _editorLinks = await _repository.loadTaskEditorLinks();
    return _editorLinks!;
  }

  Future<List<TaskReminder>> remindersForTask(String taskId) async {
    if (_remindersByTask.containsKey(taskId)) {
      return _remindersByTask[taskId]!;
    }
    final reminders = await _repository.loadTaskReminders(taskId);
    _remindersByTask[taskId] = reminders;
    notifyListeners();
    return reminders;
  }

  Future<List<TaskUsageActivity>> usageForTask(String taskId) async {
    if (_usageByTask.containsKey(taskId)) {
      return _usageByTask[taskId]!;
    }
    final usage = await _repository.loadTaskUsage(taskId);
    _usageByTask[taskId] = usage;
    notifyListeners();
    return usage;
  }

  Future<void> recordUsage(List<TaskUsageActivity> records) async {
    if (records.isEmpty) return;
    for (final record in records) {
      final current = _usageByTask[record.taskId] ?? const [];
      _usageByTask[record.taskId] = [
        record,
        ...current.where((item) => item.id != record.id),
      ];
    }
    await _runSync(
      () => _repository.upsertTaskUsage(records),
      notifyStatus: false,
    );
  }

  Future<void> checkpointBrowserState({
    required TaskItem task,
    required List<Map<String, dynamic>> tabs,
    required int selectedTab,
    required bool browserExpanded,
    required String browserMode,
    required double browserWidth,
    required int selectedPanel,
  }) async {
    await _repository.saveBrowserCheckpoint(
      task: task,
      tabs: tabs,
      selectedTab: selectedTab,
      browserExpanded: browserExpanded,
      browserMode: browserMode,
      browserWidth: browserWidth,
      selectedPanel: selectedPanel,
      sessionId: _activeSession?.task.id == task.id
          ? _activeSession?.session.id
          : null,
    );
  }

  Future<void> deleteTask(
    TaskItem task, {
    bool discardActiveSession = false,
  }) async {
    final previousTasks = _tasks;
    final previousDeletedTasks = _deletedTasks;
    final previousActiveSession = _activeSession;
    final deleted = task.copyWith(deletedAt: DateTime.now());
    _tasks = _tasks.where((item) => item.id != task.id).toList();
    _deletedTasks = [
      deleted,
      ..._deletedTasks.where((item) => item.id != task.id),
    ];
    if (_activeSession?.task.id == task.id) {
      _activeSession = null;
      _stopActiveClock();
    }
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      if (previousActiveSession?.task.id == task.id) {
        _activeSession = previousActiveSession;
        if (!previousActiveSession!.isPaused) {
          _startActiveClock();
        }
        await _endActiveSessionForDeletion(task, discard: discardActiveSession);
        _activeSession = null;
        _stopActiveClock();
      }
      await _repository.moveToTrash(task);
      await _reminderScheduler.cancelTask(task.id);
      _notesByTask.remove(task.id);
      _interruptionsByTask.remove(task.id);
      _sessionsByTask.remove(task.id);
      _syncState = TaskSyncState.synced;
    } on Object catch (error) {
      _tasks = previousTasks;
      _deletedTasks = previousDeletedTasks;
      _activeSession = previousActiveSession;
      if (previousActiveSession != null && !previousActiveSession.isPaused) {
        _startActiveClock();
      }
      _syncState = TaskSyncState.failed;
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> restoreTask(TaskItem task) async {
    final previousTasks = _tasks;
    final previousDeletedTasks = _deletedTasks;
    final optimistic = task.copyWith(clearDeletedAt: true);
    _deletedTasks = _deletedTasks.where((item) => item.id != task.id).toList();
    _tasks = [optimistic, ..._tasks.where((item) => item.id != task.id)];
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      final restored = await _repository.restoreTask(task);
      _deletedTasks = _deletedTasks
          .where((item) => item.id != restored.id)
          .toList();
      _tasks = [restored, ..._tasks.where((item) => item.id != restored.id)];
      _syncState = TaskSyncState.synced;
    } on Object catch (error) {
      _tasks = previousTasks;
      _deletedTasks = previousDeletedTasks;
      _syncState = TaskSyncState.failed;
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> permanentlyDeleteTask(TaskItem task) async {
    await _runSync(() async {
      await _repository.permanentlyDeleteTask(task);
      _deletedTasks = _deletedTasks
          .where((item) => item.id != task.id)
          .toList();
    });
  }

  Future<void> emptyTrash() async {
    final items = List<TaskItem>.from(_deletedTasks);
    for (final task in items) {
      await permanentlyDeleteTask(task);
    }
  }

  Future<List<TaskNote>> notesForTask(String taskId) async {
    if (_notesByTask.containsKey(taskId)) {
      return _notesByTask[taskId]!;
    }
    final notes = await _repository.loadNotes(taskId);
    _notesByTask[taskId] = notes;
    notifyListeners();
    return notes;
  }

  int noteCount(String taskId) {
    return _notesByTask[taskId]?.length ?? 0;
  }

  Future<QuickNote?> addQuickNote(QuickNote note) async {
    final previous = _quickNotes;
    _quickNotes = [note, ..._quickNotes.where((item) => item.id != note.id)];
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      final saved = await _repository.addQuickNote(note);
      _quickNotes = [
        saved,
        ..._quickNotes.where((item) => item.id != saved.id),
      ];
      _syncState = TaskSyncState.synced;
      notifyListeners();
      return saved;
    } on Object catch (error) {
      _quickNotes = previous;
      _syncState = TaskSyncState.failed;
      _error = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> addNote(TaskNote note) async {
    await _runSync(() async {
      final saved = await _repository.addNote(note);
      _notesByTask[note.taskId] = [
        saved,
        ...(_notesByTask[note.taskId] ?? const []),
      ];
    });
  }

  Future<void> updateNote(TaskNote note) async {
    await _runSync(() async {
      final saved = await _repository.updateNote(note);
      final notes = _notesByTask[note.taskId] ?? const [];
      _notesByTask[note.taskId] = [
        for (final item in notes) item.id == saved.id ? saved : item,
      ];
    });
  }

  Future<void> deleteNote(TaskNote note) async {
    await _runSync(() async {
      await _repository.deleteNote(note);
      final notes = _notesByTask[note.taskId] ?? const [];
      _notesByTask[note.taskId] = [
        for (final item in notes)
          if (item.id != note.id) item,
      ];
    });
  }

  Future<List<TaskInterruption>> interruptionsForTask(String taskId) async {
    if (_interruptionsByTask.containsKey(taskId)) {
      return _interruptionsByTask[taskId]!;
    }
    final interruptions = await _repository.loadInterruptions(taskId);
    _interruptionsByTask[taskId] = interruptions;
    notifyListeners();
    return interruptions;
  }

  int interruptionCount(String taskId) {
    return _interruptionsByTask[taskId]?.length ?? 0;
  }

  List<TaskInterruption> interruptionsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return [
      for (final interruptions in _interruptionsByTask.values)
        for (final interruption in interruptions)
          if (!interruption.startedAt.isBefore(start) &&
              interruption.startedAt.isBefore(end))
            interruption,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  Future<void> addInterruption(TaskInterruption interruption) async {
    await _runSync(() async {
      final saved = await _repository.addInterruption(interruption);
      _interruptionsByTask[interruption.taskId] = [
        saved,
        ...(_interruptionsByTask[interruption.taskId] ?? const []),
      ];

      final active = _activeSession;
      if (active?.task.id != interruption.taskId) {
        return;
      }
      final now = DateTime.now();
      final closed = active!.openSegment?.close(now);
      final interruptionSegment = TrackedSessionSegment(
        sessionId: active.session.id,
        type: SessionSegmentType.interruption,
        startedAt: saved.startedAt,
        endedAt: saved.durationSeconds > 0
            ? saved.startedAt.add(Duration(seconds: saved.durationSeconds))
            : now,
        durationSeconds: saved.durationSeconds,
        source: saved.type.storageValue,
        trackingMode: active.session.trackingMode,
      );
      final nextSegment = TrackedSessionSegment(
        sessionId: active.session.id,
        type: saved.pausedTask
            ? SessionSegmentType.paused
            : _activeSegmentTypeForMode(active.session.trackingMode),
        startedAt: now,
        trackingMode: active.session.trackingMode,
      );
      final nextSession = _recalculateSession(
        active.session.copyWith(
          status: saved.pausedTask
              ? TrackedSessionStatus.paused
              : TrackedSessionStatus.running,
        ),
        additionalSegments: [?closed, interruptionSegment, nextSegment],
      );
      if (closed != null) {
        await _repository.upsertSegment(closed);
      }
      await _repository.upsertSegment(interruptionSegment);
      await _repository.upsertSegment(nextSegment);
      final savedSession = await _repository.upsertSession(nextSession);
      await _repository.addSessionEvent(
        SessionEventRecord(
          sessionId: active.session.id,
          eventType: 'interrupted',
          metadata: {'type': saved.type.storageValue},
        ),
      );
      _upsertLocalSession(savedSession);
      _segmentsBySession[active.session.id] = _mergeSegments(
        _segmentsBySession[active.session.id] ?? const [],
        [?closed, interruptionSegment, nextSegment],
      );
      final nextTask = saved.pausedTask
          ? active.task.copyWith(status: TaskStatus.paused)
          : active.task;
      _activeSession = ActiveTaskSession(
        task: nextTask,
        session: savedSession,
        startedAt: active.startedAt,
        openSegment: nextSegment,
        pausedAt: saved.pausedTask ? now : null,
        interruptionCount: active.interruptionCount + 1,
        pomodoroStage: saved.pausedTask
            ? (active.pomodoroStage == PomodoroStage.breakRunning
                  ? PomodoroStage.breakPaused
                  : active.pomodoroStage == PomodoroStage.focusRunning
                  ? PomodoroStage.focusPaused
                  : active.pomodoroStage)
            : active.pomodoroStage,
      );
      if (saved.pausedTask) {
        _stopActiveClock(now);
      } else {
        _startActiveClock(now);
      }
      await _saveRecoveryCheckpoint(
        saved.pausedTask ? 'paused' : 'running',
        openInterruptionId: saved.id,
      );
    });
  }

  Future<void> updateInterruption(TaskInterruption interruption) async {
    await _runSync(() async {
      final saved = await _repository.updateInterruption(interruption);
      final interruptions =
          _interruptionsByTask[interruption.taskId] ?? const [];
      _interruptionsByTask[interruption.taskId] = [
        for (final item in interruptions) item.id == saved.id ? saved : item,
      ];
    });
  }

  Future<void> deleteInterruption(TaskInterruption interruption) async {
    await _runSync(() async {
      await _repository.deleteInterruption(interruption);
      final interruptions =
          _interruptionsByTask[interruption.taskId] ?? const [];
      _interruptionsByTask[interruption.taskId] = [
        for (final item in interruptions)
          if (item.id != interruption.id) item,
      ];
    });
  }

  Future<List<TrackedSession>> sessionsForTask(String taskId) async {
    if (_sessionsByTask.containsKey(taskId)) {
      return _sessionsByTask[taskId]!;
    }
    final sessions = await _repository.loadSessionsForTask(taskId);
    _sessionsByTask[taskId] = sessions;
    _sessions = _mergeSessions(_sessions, sessions);
    notifyListeners();
    return sessions;
  }

  Future<List<TrackedSessionSegment>> segmentsForSession(
    String sessionId,
  ) async {
    if (_segmentsBySession.containsKey(sessionId)) {
      return _segmentsBySession[sessionId]!;
    }
    final segments = await _repository.loadSegmentsForSession(sessionId);
    _segmentsBySession[sessionId] = segments;
    notifyListeners();
    return segments;
  }

  Future<List<TaskProgressEntry>> progressEntriesForTask(String taskId) async {
    if (_progressByTask.containsKey(taskId)) {
      return _progressByTask[taskId]!;
    }
    final entries = await _repository.loadProgressEntries(taskId);
    _progressByTask[taskId] = entries;
    notifyListeners();
    return entries;
  }

  Future<void> _loadTasks() async {
    _tasks = await _repository.loadTasks();
  }

  Future<void> _restoreReminderSchedule() async {
    final reminders = await _repository.loadUpcomingReminders();
    _remindersByTask.addAll(reminders);
    for (final task in _tasks) {
      final taskReminders = reminders[task.id];
      if (taskReminders != null && taskReminders.isNotEmpty) {
        await _reminderScheduler.scheduleForTask(task, taskReminders);
      }
    }
  }

  Future<void> _reconcileReminderSchedule() async {
    for (final task in _tasks) {
      await _reminderScheduler.cancelTask(task.id);
    }
    _remindersByTask.clear();
    await _restoreReminderSchedule();
  }

  Future<void> _loadDeletedTasks() async {
    _deletedTasks = await _repository.loadDeletedTasks();
  }

  Future<void> _loadCategories() async {
    _categories = await _repository.loadCategories();
  }

  Future<void> _loadSessions() async {
    final now = DateTime.now();
    _sessions = await _repository.loadSessionsInRange(
      start: now.subtract(const Duration(days: 180)),
      end: now.add(const Duration(days: 90)),
    );
    _sessionsByTask.clear();
    for (final session in _sessions) {
      _sessionsByTask.putIfAbsent(session.taskId, () => []).add(session);
    }
  }

  Future<void> _loadTodayInterruptions() async {
    final taskIds = _tasks
        .where((task) => task.isDueToday || task.status == TaskStatus.running)
        .map((task) => task.id)
        .toSet();
    await Future.wait([
      for (final taskId in taskIds)
        if (!_interruptionsByTask.containsKey(taskId))
          _repository.loadInterruptions(taskId).then((items) {
            _interruptionsByTask[taskId] = items;
          }),
    ]);
  }

  Future<void> _saveTask(TaskItem task) async {
    await _runSync(() => _saveTaskWithoutSync(task));
  }

  Future<void> _saveTaskWithoutSync(TaskItem task) async {
    final previousTasks = _tasks;
    final previousActiveSession = _activeSession;
    _upsertLocalTask(task);
    notifyListeners();
    try {
      final saved = await _repository.updateTask(task);
      _upsertLocalTask(saved);
    } on Object {
      _tasks = previousTasks;
      _activeSession = previousActiveSession;
      rethrow;
    }
  }

  void _upsertLocalTask(TaskItem saved) {
    final exists = _tasks.any((item) => item.id == saved.id);
    _tasks = exists
        ? [for (final item in _tasks) item.id == saved.id ? saved : item]
        : [saved, ..._tasks];
    if (_activeSession?.task.id == saved.id) {
      _activeSession = ActiveTaskSession(
        task: saved,
        session: _activeSession!.session,
        startedAt: _activeSession!.startedAt,
        openSegment: _activeSession!.openSegment,
        pausedAt: _activeSession!.pausedAt,
        interruptionCount: _activeSession!.interruptionCount,
        pomodoroStage: _activeSession!.pomodoroStage,
      );
    }
  }

  TaskItem _taskWithCalculatedProgress(TaskItem task, TrackedSession session) {
    final nextProgress = switch (task.taskType) {
      TaskType.focus when task.estimatedPomodoros > 0 =>
        (((session.pomodorosCompleted.clamp(0, task.estimatedPomodoros) /
                        task.estimatedPomodoros) *
                    100)
                .round())
            .clamp(0, 100)
            .toInt(),
      TaskType.timed when task.estimatedMinutes > 0 =>
        (((session.activeSeconds / (task.estimatedMinutes * 60)) * 100).round())
            .clamp(0, 100)
            .toInt(),
      _ => task.progressPercentage,
    };
    return nextProgress == task.progressPercentage
        ? task
        : task.copyWith(progressPercentage: nextProgress);
  }

  Future<void> _persistActiveTransition({
    required TaskItem task,
    required TrackedSession session,
    required String eventType,
    required String checkpointState,
    TrackedSessionSegment? closedSegment,
    TrackedSessionSegment? nextSegment,
  }) async {
    await _runSync(() async {
      final deviceId = await _repository.loadDeviceId();
      final runtimeSegment = nextSegment ?? closedSegment;
      final runtimeStage =
          runtimeSegment?.stage ??
          (checkpointState == 'running' || checkpointState == 'paused'
              ? session.stage
              : checkpointState);
      final runtimeSession = _sessionWithRuntimeState(
        session,
        segment: runtimeSegment,
        stage: runtimeStage,
        deviceId: deviceId,
      );
      if (closedSegment != null) {
        await _repository.upsertSegment(closedSegment);
      }
      if (nextSegment != null) {
        await _repository.upsertSegment(nextSegment);
      }
      final savedSession = await _repository.upsertSession(runtimeSession);
      await _repository.addSessionEvent(
        SessionEventRecord(sessionId: session.id, eventType: eventType),
      );
      _upsertLocalSession(savedSession);
      _replaceActiveRuntimeSession(savedSession);
      _segmentsBySession[session.id] = _mergeSegments(
        _segmentsBySession[session.id] ?? const [],
        [?closedSegment, ?nextSegment],
      );
      await _saveTaskWithoutSync(task);
      await _saveRecoveryCheckpoint(checkpointState);
      final commandType = _commandTypeForTransition(
        eventType,
        task: task,
        stage: runtimeSession.stage,
      );
      if (commandType != null) {
        _queueSharedSessionCommand(
          task: task,
          session: savedSession,
          commandType: commandType,
          occurredAt: runtimeSegment?.startedAt ?? DateTime.now(),
          segment: runtimeSegment,
        );
      }
    });
  }

  TrackedSession _sessionWithRuntimeState(
    TrackedSession session, {
    TrackedSessionSegment? segment,
    String? stage,
    String? deviceId,
  }) {
    final isRunningSegment =
        segment != null &&
        segment.endedAt == null &&
        (segment.type.countsAsActive ||
            segment.type == SessionSegmentType.breakTime);
    final currentSegmentId = segment?.endedAt == null ? segment?.id : null;
    return session.copyWith(
      stage: stage,
      currentSegmentId: currentSegmentId,
      plannedDurationSeconds:
          segment?.plannedDurationSeconds ?? session.plannedDurationSeconds,
      lastResumedAt: isRunningSegment
          ? segment.startedAt
          : session.lastResumedAt,
      accumulatedActiveSeconds:
          segment?.accumulatedActiveSeconds ?? session.accumulatedActiveSeconds,
      accumulatedPausedSeconds:
          segment?.accumulatedPausedSeconds ?? session.accumulatedPausedSeconds,
      sourceDeviceId: deviceId,
      clearCurrentSegmentId: currentSegmentId == null,
      clearPlannedDurationSeconds:
          segment == null && session.plannedDurationSeconds == null,
    );
  }

  String? _commandTypeForTransition(
    String eventType, {
    required TaskItem task,
    String? stage,
  }) {
    return switch (eventType) {
      'started' =>
        task.taskType == TaskType.focus ? 'start_focus' : 'start_task',
      'paused' =>
        stage == PomodoroStage.breakPaused.storageValue
            ? 'pause_break'
            : stage == PomodoroStage.focusPaused.storageValue
            ? 'pause_focus'
            : 'pause_task',
      'resumed' =>
        stage == PomodoroStage.breakRunning.storageValue
            ? 'resume_break'
            : stage == PomodoroStage.focusRunning.storageValue
            ? 'resume_focus'
            : 'resume_task',
      'pomodoro_break_started' => 'start_break',
      'pomodoro_break_ready' => 'jump_to_break',
      'pomodoro_break_skipped' => 'skip_break',
      'pomodoro_break_completed' => 'finish_break',
      'pomodoro_focus_started' => 'start_focus',
      'pomodoro_focus_continued' => 'resume_focus',
      'pomodoro_focus_completed' => 'finish_focus',
      'pomodoro_focus_ready' => 'return_to_focus',
      'stopped' || 'completed' => 'finish_task',
      _ => null,
    };
  }

  void _queueSharedSessionCommand({
    required TaskItem task,
    required TrackedSession session,
    required String commandType,
    required DateTime occurredAt,
    TrackedSessionSegment? segment,
  }) {
    unawaited(
      _applySharedSessionCommand(
        task: task,
        session: session,
        commandType: commandType,
        occurredAt: occurredAt,
        segment: segment,
      ),
    );
  }

  Future<void> _applySharedSessionCommand({
    required TaskItem task,
    required TrackedSession session,
    required String commandType,
    required DateTime occurredAt,
    TrackedSessionSegment? segment,
  }) async {
    final result = await _repository.applySessionCommand(
      sessionId: session.id,
      taskId: task.id,
      expectedRevision: session.revision,
      commandType: commandType,
      occurredAt: occurredAt,
      payload: {
        if (segment != null) 'segment_id': segment.id,
        if (segment?.plannedDurationSeconds != null)
          'planned_duration_seconds': segment!.plannedDurationSeconds,
        if (segment != null)
          'accumulated_active_seconds': segment.accumulatedActiveSeconds,
        if (segment != null)
          'accumulated_paused_seconds': segment.accumulatedPausedSeconds,
      },
    );
    if (result == null) {
      return;
    }
    if (!result.applied) {
      _error =
          result.message ??
          'Task state changed on another device. The latest state has been loaded.';
      unawaited(_refreshFromRealtimeEvent());
      notifyListeners();
      return;
    }
    final nextSession = session.copyWith(
      revision: result.revision,
      stage: result.stage,
      currentSegmentId: result.segmentId,
      status: result.sessionState == null
          ? session.status
          : TrackedSessionStatusX.fromStorage(result.sessionState),
      clearStage: result.stage == null,
      clearCurrentSegmentId: result.segmentId == null,
    );
    _upsertLocalSession(nextSession);
    _replaceActiveRuntimeSession(nextSession, notify: true);
  }

  void _replaceActiveRuntimeSession(
    TrackedSession session, {
    bool notify = false,
  }) {
    final active = _activeSession;
    if (active == null || active.session.id != session.id) {
      return;
    }
    _activeSession = ActiveTaskSession(
      task: active.task,
      session: session,
      startedAt: active.startedAt,
      openSegment: active.openSegment,
      pausedAt: active.pausedAt,
      interruptionCount: active.interruptionCount,
      pomodoroStage: active.pomodoroStage,
    );
    if (notify) {
      notifyListeners();
    }
  }

  TrackedSession _recalculateSession(
    TrackedSession session, {
    List<TrackedSessionSegment> additionalSegments = const [],
    DateTime? endAt,
  }) {
    final merged = _mergeSegments(
      _segmentsBySession[session.id] ?? const [],
      additionalSegments,
    );
    final closedForTotals = [
      for (final segment in merged)
        if (!segment.isOpen || endAt != null)
          segment.isOpen && endAt != null ? segment.close(endAt) : segment,
    ];
    final totals = _analytics.fromSegments(closedForTotals);
    return session.copyWith(
      grossSeconds: totals.grossSeconds,
      activeSeconds: totals.activeSeconds,
      idleSeconds: totals.idleSeconds,
      pausedSeconds: totals.pausedSeconds,
      interruptedSeconds: totals.interruptedSeconds,
      breakSeconds: totals.breakSeconds,
      manualSeconds: totals.manualSeconds,
      endedAt: endAt ?? session.endedAt,
    );
  }

  Future<void> _addProgressEntryWithoutSync(TaskProgressEntry entry) async {
    final saved = await _repository.addProgressEntry(entry);
    _progressByTask[entry.taskId] = [
      ...(_progressByTask[entry.taskId] ?? const []),
      saved,
    ]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  }

  Future<void> _endActiveSessionForDeletion(
    TaskItem task, {
    required bool discard,
  }) async {
    final active = _activeSession;
    if (active == null || active.task.id != task.id) {
      return;
    }
    final now = DateTime.now();
    final closed = active.openSegment?.close(now);
    final nextSession = _recalculateSession(
      active.session.copyWith(
        status: discard
            ? TrackedSessionStatus.discarded
            : TrackedSessionStatus.stopped,
        endedAt: now,
        completionReason: discard
            ? 'task_deleted_discarded'
            : 'task_deleted_saved',
      ),
      additionalSegments: [?closed],
      endAt: now,
    );
    if (closed != null) {
      await _repository.upsertSegment(closed);
    }
    final saved = await _repository.upsertSession(nextSession);
    await _repository.addSessionEvent(
      SessionEventRecord(
        sessionId: nextSession.id,
        eventType: discard
            ? 'discarded_for_task_delete'
            : 'stopped_for_task_delete',
        eventTime: now,
      ),
    );
    _upsertLocalSession(saved);
    _activeSession = null;
    _stopActiveClock(now);
    await _clearRecoveryCheckpoint();
  }

  Future<void> _loadRecoveryCheckpoint() async {
    final userId = _repository.currentUserId;
    if (userId == null) {
      return;
    }
    final checkpoint = await _recoveryStore.load(userId);
    if (checkpoint == null || checkpoint.sessionId.isEmpty) {
      return;
    }
    final session = await _repository.loadSessionById(checkpoint.sessionId);
    final task = _tasks
        .where((item) => item.id == checkpoint.taskId && !item.isCompleted)
        .firstOrNull;
    if (session == null || task == null) {
      return;
    }
    _blockedSessionClaim = null;
    _blockedSessionTask = null;
    final segments = await _repository.loadSegmentsForSession(session.id);
    _segmentsBySession[session.id] = segments;
    final restoredStage = task.taskType == TaskType.focus
        ? PomodoroStageX.fromStorage(
            segments.where((segment) => segment.isOpen).lastOrNull?.stage ??
                checkpoint.timerState,
          )
        : PomodoroStage.idle;
    _activeSession = ActiveTaskSession(
      task: task,
      session: session.copyWith(status: TrackedSessionStatus.recovered),
      startedAt: session.startedAt,
      openSegment: segments.where((segment) => segment.isOpen).lastOrNull,
      pausedAt: checkpoint.timerState == 'paused'
          ? checkpoint.lastStateChange
          : null,
      pomodoroStage: restoredStage,
    );
    if (checkpoint.timerState == 'paused' ||
        (task.taskType == TaskType.focus && !restoredStage.isRunning)) {
      _stopActiveClock(checkpoint.lastStateChange);
    } else {
      _startActiveClock();
    }
  }

  Future<void> _saveRecoveryCheckpoint(
    String state, {
    String? openInterruptionId,
  }) async {
    final active = _activeSession;
    final userId = _repository.currentUserId;
    if (active == null || userId == null) {
      return;
    }
    final now = DateTime.now();
    final timing = active.timingAt(now);
    await _recoveryStore.save(
      SessionRecoveryCheckpoint(
        userId: userId,
        taskId: active.task.id,
        sessionId: active.session.id,
        timerState: state,
        lastStateChange: now,
        trackingMode: active.session.trackingMode,
        segmentType: active.openSegment?.type,
        segmentStartedAt: active.openSegment?.startedAt,
        plannedSeconds: timing.plannedSeconds,
        controllingDeviceId: active.session.deviceId,
        lastCheckpointAt: now,
        openInterruptionId: openInterruptionId,
      ),
    );
    await _repository.renewSessionControl(
      sessionId: active.session.id,
      taskId: active.task.id,
    );
  }

  Future<void> _clearRecoveryCheckpoint() async {
    final userId = _repository.currentUserId;
    if (userId != null) {
      await _recoveryStore.clear(userId);
    }
  }

  Future<void> flushActiveSessionCheckpoint() async {
    final active = _activeSession;
    if (active == null) return;
    await _checkpointOpenSegment();
    await _saveRecoveryCheckpoint(
      active.task.taskType == TaskType.focus
          ? active.pomodoroStage.storageValue
          : active.isPaused
          ? 'paused'
          : 'running',
    );
  }

  Future<void> flushForShutdown() async {
    await flushActiveSessionCheckpoint();
    try {
      await _repository.synchronizePendingOperations().timeout(
        const Duration(seconds: 3),
      );
    } on Object {
      // The durable local outbox remains available for the next launch.
    }
  }

  void _startActiveClock([DateTime? anchor]) {
    final active = _activeSession;
    if (active == null || active.isPaused) return;
    _activeClockTimer?.cancel();
    _activeClockAnchor = anchor ?? DateTime.now();
    _activeClockStopwatch = Stopwatch()..start();
    _activeClockTicks = 0;
    _activeSessionClock.value = _activeClockAnchor!;
    _activeClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final stopwatch = _activeClockStopwatch;
      final wallAnchor = _activeClockAnchor;
      if (stopwatch == null || wallAnchor == null) return;
      final observed = wallAnchor.add(stopwatch.elapsed);
      _activeSessionClock.value = observed;
      _activeClockTicks += 1;
      final active = _activeSession;
      if (active != null &&
          active.task.taskType == TaskType.focus &&
          !_pomodoroCompletionInProgress) {
        final timing = active.timingAt(observed);
        if (active.pomodoroStage == PomodoroStage.focusRunning &&
            timing.pomodoroRemainingSeconds <= 0) {
          _pomodoroCompletionInProgress = true;
          unawaited(
            finishPomodoroFocus(
              reason: 'planned_duration_reached',
            ).whenComplete(() => _pomodoroCompletionInProgress = false),
          );
          return;
        }
        if (active.pomodoroStage == PomodoroStage.breakRunning &&
            timing.breakRemainingSeconds <= 0) {
          _pomodoroCompletionInProgress = true;
          unawaited(
            finishPomodoroBreak(
              reason: 'planned_duration_reached',
            ).whenComplete(() => _pomodoroCompletionInProgress = false),
          );
          return;
        }
      }
      if (_activeClockTicks % 10 == 0) {
        unawaited(_saveRecoveryCheckpoint('running'));
      }
    });
  }

  void _stopActiveClock([DateTime? observedAt]) {
    final stopwatch = _activeClockStopwatch;
    final wallAnchor = _activeClockAnchor;
    final resolved =
        observedAt ??
        (stopwatch != null && wallAnchor != null
            ? wallAnchor.add(stopwatch.elapsed)
            : DateTime.now());
    _activeClockTimer?.cancel();
    _activeClockTimer = null;
    stopwatch?.stop();
    _activeClockStopwatch = null;
    _activeClockAnchor = null;
    _activeSessionClock.value = resolved;
  }

  @override
  void dispose() {
    unawaited(flushActiveSessionCheckpoint());
    _activeClockTimer?.cancel();
    _remoteRefreshDebounce?.cancel();
    unawaited(_removeRealtimeSubscription());
    _activeSessionClock.dispose();
    super.dispose();
  }

  Future<void> _checkpointOpenSegment() async {
    final active = _activeSession;
    final open = active?.openSegment;
    if (active == null || open == null || !open.isOpen) {
      return;
    }
    final now = DateTime.now();
    final timing = active.timingAt(now);
    final closed = open.close(now);
    final currentSegmentActiveSeconds = active.task.taskType == TaskType.focus
        ? open.type == SessionSegmentType.breakTime ||
                  active.pomodoroStage.isBreakStage
              ? timing.currentBreakElapsedSeconds
              : timing.currentFocusElapsedSeconds
        : 0;
    final nextOpen = TrackedSessionSegment(
      sessionId: active.session.id,
      type: open.type,
      startedAt: now,
      source: open.source,
      trackingMode: open.trackingMode,
      stage: open.stage,
      plannedDurationSeconds: open.plannedDurationSeconds,
      accumulatedActiveSeconds: currentSegmentActiveSeconds,
      accumulatedPausedSeconds: timing.pausedSeconds,
      controllingDeviceId: open.controllingDeviceId,
      lastCheckpointAt: now,
    );
    final nextSession = _recalculateSession(
      active.session.copyWith(
        status: active.isPaused
            ? TrackedSessionStatus.paused
            : TrackedSessionStatus.running,
      ),
      additionalSegments: [closed, nextOpen],
    );
    _activeSession = ActiveTaskSession(
      task: active.task,
      session: nextSession,
      startedAt: active.startedAt,
      openSegment: nextOpen,
      pausedAt: active.pausedAt,
      interruptionCount: active.interruptionCount,
      pomodoroStage: active.pomodoroStage,
    );
    _segmentsBySession[active.session.id] = _mergeSegments(
      _segmentsBySession[active.session.id] ?? const [],
      [closed, nextOpen],
    );
    try {
      await _repository.upsertSegment(closed);
      await _repository.upsertSegment(nextOpen);
      final savedSession = await _repository.upsertSession(nextSession);
      _upsertLocalSession(savedSession);
    } on Object catch (error) {
      debugPrint('ACTIVE SESSION CHECKPOINT FAILED: $error');
    }
  }

  void _upsertLocalSession(TrackedSession session) {
    _sessions = _mergeSessions(_sessions, [session]);
    final taskSessions = _sessionsByTask[session.taskId] ?? const [];
    _sessionsByTask[session.taskId] = _mergeSessions(taskSessions, [session]);
  }

  Future<void> _runSync(
    Future<void> Function() action, {
    bool notifyStatus = true,
  }) async {
    if (!notifyStatus) {
      try {
        await action();
      } on Object catch (error) {
        _error = error.toString();
        if (kDebugMode) {
          debugPrint('BACKGROUND SYNC FAILED: $error');
        }
      }
      return;
    }
    _syncState = TaskSyncState.syncing;
    _error = null;
    notifyListeners();
    try {
      await action();
      _syncState = TaskSyncState.synced;
    } on Object catch (error) {
      _syncState = TaskSyncState.failed;
      _error = error.toString();
    }
    notifyListeners();
  }

  static List<TrackedSession> _mergeSessions(
    List<TrackedSession> current,
    List<TrackedSession> incoming,
  ) {
    final map = {for (final item in current) item.id: item};
    for (final item in incoming) {
      map[item.id] = item;
    }
    return map.values.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  static List<TrackedSessionSegment> _mergeSegments(
    List<TrackedSessionSegment> current,
    List<TrackedSessionSegment> incoming,
  ) {
    final map = {for (final item in current) item.id: item};
    for (final item in incoming) {
      map[item.id] = item;
    }
    return map.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  static TrackedSessionType _sessionTypeForTask(TaskItem task) {
    final category = task.category.toLowerCase();
    if (category.contains('work') || category.contains('job')) {
      return TrackedSessionType.work;
    }
    if (category.contains('learn') ||
        category.contains('study') ||
        category.contains('course') ||
        task.learningResourceLink != null) {
      return TrackedSessionType.learning;
    }
    if (category.contains('house')) {
      return TrackedSessionType.household;
    }
    if (category.contains('family')) {
      return TrackedSessionType.family;
    }
    if (category.contains('health') || category.contains('fitness')) {
      return TrackedSessionType.health;
    }
    if (category.contains('social') || category.contains('friend')) {
      return TrackedSessionType.social;
    }
    return TrackedSessionType.personal;
  }

  static SessionTrackingMode _trackingModeForTask(TaskItem task) {
    return switch (task.workspaceBrowserMode) {
      TaskTrackingMode.video => SessionTrackingMode.video,
      TaskTrackingMode.reading => SessionTrackingMode.reading,
      TaskTrackingMode.manual => SessionTrackingMode.manual,
      TaskTrackingMode.interactive => SessionTrackingMode.interactive,
    };
  }

  static SessionSegmentType _activeSegmentTypeForMode(
    SessionTrackingMode mode,
  ) {
    return switch (mode) {
      SessionTrackingMode.video => SessionSegmentType.video,
      SessionTrackingMode.reading => SessionSegmentType.reading,
      SessionTrackingMode.manual => SessionSegmentType.manual,
      SessionTrackingMode.interactive => SessionSegmentType.active,
    };
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }

  T? get lastOrNull {
    T? result;
    for (final item in this) {
      result = item;
    }
    return result;
  }
}

int _pomodoroSecondsForTask(TaskItem task) {
  final plannedSeconds = (task.estimatedMinutes * 60).clamp(0, 1 << 31);
  if (task.estimatedPomodoros > 0 && plannedSeconds > 0) {
    return (plannedSeconds ~/ task.estimatedPomodoros).clamp(60, 2 * 60 * 60);
  }
  return 25 * 60;
}

int _breakSecondsForTask(TaskItem task) {
  final configured = task.reminderRules['break_minutes'];
  if (configured is num) {
    return (configured.toInt() * 60).clamp(60, 60 * 60);
  }
  return 5 * 60;
}

String formatSecondsForAlarm(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes <= 1) return '1 minute';
  return '$minutes minutes';
}
