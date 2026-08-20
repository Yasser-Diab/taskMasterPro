import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/platform/windows_shell_service.dart';
import '../../../core/profile/profile_avatar.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';
import '../../../core/updates/app_update_service.dart';
import '../../../core/updates/update_prompt.dart';
import '../../account/data/account_deletion_service.dart';
import '../../account/presentation/account_deletion_screen.dart';
import '../../activity/presentation/activity_review_screen.dart';
import '../../calendar/presentation/planning_calendar_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../roadmaps/presentation/roadmaps_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../settings/presentation/notifications_sounds_screen.dart';
import '../../settings/presentation/schedule_wellbeing_screen.dart';
import '../../sync/presentation/synchronization_panel.dart';
import '../../tasks/data/task_execution_commands.dart';
import '../../tasks/data/execution_exclusivity_coordinator.dart';
import '../../tasks/data/standalone_pomodoro_store.dart';
import '../../tasks/data/task_execution_providers.dart';
import '../../tasks/data/task_repository.dart';
import '../domain/home_shell_back_navigation.dart';
import '../../tasks/domain/pomodoro_execution_state.dart';
import '../../tasks/domain/task_list_projection.dart';
import '../../tasks/presentation/task_completion_flow.dart';
import '../../tasks/presentation/interruption_editor_dialog.dart';
import '../../tasks/presentation/tasks_screen.dart';
import '../../tasks/presentation/standalone_pomodoro_screen.dart';
import '../../tasks/presentation/task_start_flow.dart';
import '../../tasks/presentation/task_workspace_screen.dart';

final syncHealthProvider = StreamProvider<SyncHealth>((ref) async* {
  final service = ref.watch(syncServiceProvider);
  yield service.currentHealth;
  yield* service.health;
});

/// Six destinations do not have enough width for six legible labels on a
/// compact handset.  Keep the semantic names and long-press tooltips, while
/// switching to an icon-first navigation bar before labels start wrapping.
bool usesCompactBottomNavigation(double maxWidth) => maxWidth < 600;

enum ShellSyncVisualState { offline, pending, synced, attention }

@visibleForTesting
ShellSyncVisualState shellSyncVisualState(SyncHealth health) {
  return switch (health) {
    SyncHealth.offline => ShellSyncVisualState.offline,
    SyncHealth.syncing => ShellSyncVisualState.pending,
    SyncHealth.idle => ShellSyncVisualState.synced,
    SyncHealth.attention => ShellSyncVisualState.attention,
  };
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.user, required this.themeKey, super.key});

  final User user;
  final TaskMasterThemeKey themeKey;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with RouteAware {
  static const _dashboardIndex = 0;
  int _selectedIndex = 0;
  final _backNavigation = HomeShellBackNavigation();
  TaskListFilter _taskFilter = TaskListFilter.all;
  String _activityFilter = 'all';
  final List<StreamSubscription<NotificationResponse>> _notificationResponses =
      [];
  StreamSubscription<LocalRuntime?>? _runtimeSubscription;
  StreamSubscription<StandalonePomodoroState>? _standaloneSubscription;
  StreamSubscription<String>? _trayCommands;
  Timer? _trayRefresh;
  Timer? _automaticBoundaryRefresh;
  Timer? _standaloneBoundaryTimer;
  bool _automaticBoundaryInFlight = false;
  bool _updateAvailable = false;
  bool _accountDeletionScheduled = false;
  AccountDeletionRequest? _accountDeletionRequest;
  bool _deletionBannerDismissed = false;
  DateTime? _lastRemoteShellCheck;
  DateTime? _lastReminderRefresh;
  final Map<int, int> _scheduledReminderFingerprints = {};
  bool _reminderRefreshInFlight = false;
  bool _reminderRefreshRequested = false;
  bool _forcedReminderRefreshRequested = false;
  bool _refreshedRemindersAfterInitialSync = false;
  bool _executionNotificationPermissionDenied = false;
  String? _lastExecutionState;
  String? _lastExecutionSession;
  String? _lastExecutionTaskId;
  int? _lastExecutionRevision;
  DateTime? _lastExecutionSegmentStartedAt;
  Future<void> _executionAlarmQueue = Future<void>.value();
  Future<void> _standaloneAlarmQueue = Future<void>.value();
  StreamSubscription<List<LocalEntityRecord>>? _taskReminderSubscription;
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _notificationResponses
      ..add(
        LocalNotificationService.responses.stream.listen(
          _handleNotificationResponse,
        ),
      )
      ..add(
        LocalNotificationService.backgroundResponses.stream.listen(
          _handleNotificationResponse,
        ),
      );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreNotificationAuthorityAfterLaunchAction());
      unawaited(_refreshTray());
      unawaited(_advanceAutomaticPomodoroBoundary());
    });
    _trayCommands = WindowsShellService.instance.commands.listen(
      _handleTrayCommand,
    );
    _trayRefresh = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshTray()),
    );
    _automaticBoundaryRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_advanceAutomaticPomodoroBoundary()),
    );
  }

  Future<void> _restoreNotificationAuthorityAfterLaunchAction() async {
    // A mutating Android action launches the foreground app so it can use the
    // same account-scoped repository command as Dashboard/Execute. Execute the
    // action before startup reconciliation supersedes the exact ledger row it
    // must validate. Running these concurrently made a cold-start Pause look
    // like a dismiss-only button.
    await _drainNotificationLaunchActions();
    if (!mounted) return;
    await _restoreCanonicalNotificationAuthority();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    if (_route != null) appRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    // A real route, sheet, or dialog was opened after the shell. Its eventual
    // return must not turn an earlier exit hint into a surprise app exit.
    _backNavigation.cancelExit();
  }

  @override
  void didPopNext() {
    _backNavigation.cancelExit();
  }

  Future<void> _drainNotificationLaunchActions() async {
    final launchResponse = localNotificationService.takeLaunchResponse();
    if (launchResponse != null) {
      await _handleNotificationResponse(launchResponse);
    }
    final stored = await localNotificationService.takeStoredBackgroundResponses(
      ownerId: widget.user.id,
    );
    for (final response in stored) {
      await _handleNotificationAction(
        payload: response.payload,
        actionId: response.actionId,
      );
    }
  }

  Future<void> _restoreCanonicalNotificationAuthority() async {
    // Android vendors can restore AlarmManager entries and active cards after
    // an application process was killed. Reconcile the device-owned queue
    // before watching runtime changes so an obsolete focus/break boundary is
    // never allowed to race the freshly restored canonical session.
    await localNotificationService.reconcileOwnedTaskNotificationsOnStartup(
      ownerId: widget.user.id,
    );
    if (!mounted) return;
    await _synchronizePersistedTaskReminders(force: true);
    if (!mounted) return;
    final repository = ref.read(taskRepositoryProvider);
    _runtimeSubscription = repository.watchRuntime().listen(
      _queueExecutionAlarmSynchronization,
    );
    _queueExecutionAlarmSynchronization(await repository.getRuntime());
    _standaloneSubscription = ref
        .read(standalonePomodoroStoreProvider)
        .watch()
        .listen(_queueStandaloneAlarmSynchronization);
    final database = ref.read(databaseProvider);
    _taskReminderSubscription =
        (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(widget.user.id) &
                  row.entityType.equals('task_reminders'),
            ))
            .watch()
            .listen(
              (_) => unawaited(_synchronizePersistedTaskReminders(force: true)),
            );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    for (final subscription in _notificationResponses) {
      unawaited(subscription.cancel());
    }
    unawaited(_trayCommands?.cancel());
    unawaited(_runtimeSubscription?.cancel());
    unawaited(_standaloneSubscription?.cancel());
    unawaited(_taskReminderSubscription?.cancel());
    _trayRefresh?.cancel();
    _automaticBoundaryRefresh?.cancel();
    _standaloneBoundaryTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTray() async {
    if (!mounted) return;
    if (_lastRemoteShellCheck == null ||
        DateTime.now().difference(_lastRemoteShellCheck!) >
            const Duration(minutes: 15)) {
      await _refreshRemoteShellState();
    }
    final settings = ref.read(appSettingsProvider).value;
    final localeCode = settings?.localeCode ?? 'en';
    final l10n = AppLocalizations(Locale(localeCode));
    final repository = ref.read(taskRepositoryProvider);
    final runtime = await repository.getRuntime();
    final task = runtime?.activeTaskId == null
        ? null
        : await repository.getTask(runtime!.activeTaskId!);
    // The tray refresh is a 15-second local UI tick.  It must never turn into
    // a remote account-devices poll; the SyncService owns bounded network
    // reconciliation and the shell simply reflects its cached health.
    final sync = await ref
        .read(syncServiceProvider)
        .getSnapshot(checkRemoteDevices: false);
    final now = DateTime.now().toUtc();
    final recordedMs = liveTaskRecordedWorkMs(
      recordedMs: runtime?.accumulatedActiveMs ?? task?.activeDurationMs ?? 0,
      running: runtime?.state == 'running',
      segmentStartedAt: runtime?.segmentStartedAt,
      now: now,
    );
    PomodoroExecutionSnapshot? pomodoro;
    if (task?.executionMode == 'pomodoro' && runtime != null) {
      pomodoro = PomodoroExecutionSnapshot.fromTask(
        task: task!,
        runtime: runtime,
        now: now,
      );
    }
    final taskOvertimeMs = task == null
        ? 0
        : taskEffortOvertimeMs(
            plannedMs: task.estimatedDurationMs,
            recordedMs: recordedMs,
          );
    final showsTaskOvertime =
        pomodoro == null && runtime?.state == 'running' && taskOvertimeMs > 0;
    await WindowsShellService.instance.updateTray(
      WindowsTrayState(
        signedIn: true,
        hasActiveTask: task != null,
        taskPaused: runtime?.state == 'paused',
        breakActive: runtime?.state == 'break',
        pomodoroAvailable: pomodoro != null,
        focusComplete: pomodoro?.focusComplete ?? false,
        activeTask: task?.title ?? '',
        elapsed: task == null
            ? ''
            : pomodoro != null
            ? formatPomodoroCountdown(pomodoro.remainingMs)
            : showsTaskOvertime
            ? formatTaskEffortOvertime(taskOvertimeMs)
            : formatTaskEffortCountdown(
                taskEffortRemainingMs(
                  plannedMs: task.estimatedDurationMs,
                  recordedMs: recordedMs,
                ),
              ),
        syncLabel: sync.isTruthfullySynced
            ? l10n.text('sync_all_changes')
            : !sync.connectionAvailable
            ? l10n.text('sync_you_offline')
            : sync.failedChanges > 0
            ? l10n.text('sync_needs_attention')
            : l10n.text('sync_latest'),
        syncAttention: sync.failedChanges > 0 || sync.conflicts > 0,
        localeCode: localeCode,
        updateAvailable: _updateAvailable,
        accountDeletion: _accountDeletionScheduled,
      ),
    );
  }

  Future<void> _advanceAutomaticPomodoroBoundary() async {
    if (!mounted || _automaticBoundaryInFlight) return;
    _automaticBoundaryInFlight = true;
    try {
      final repository = ref.read(taskRepositoryProvider);
      final runtime = await repository.getRuntime();
      if (!mounted ||
          runtime == null ||
          runtime.activeTaskId == null ||
          (runtime.state != 'running' && runtime.state != 'break')) {
        return;
      }
      final task = await repository.getTask(runtime.activeTaskId!);
      if (!mounted || task == null || task.executionMode != 'pomodoro') {
        return;
      }
      final advanced = await TaskExecutionCommands.advanceAutomaticBoundary(
        repository: repository,
        requestedTask: task,
      );
      if (!advanced) return;
      unawaited(ref.read(syncServiceProvider).drainOutbox());
      unawaited(_refreshTray());
    } catch (_) {
      // Authentication refresh and account database rotation can briefly make
      // the canonical runtime unavailable. The next bounded tick retries.
    } finally {
      _automaticBoundaryInFlight = false;
    }
  }

  Future<void> _refreshRemoteShellState() async {
    _lastRemoteShellCheck = DateTime.now();
    try {
      final results = await Future.wait<Object?>([
        AppUpdateService().checkForUpdate().timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        ),
        AccountDeletionService(
          Supabase.instance.client,
        ).current().timeout(const Duration(seconds: 8), onTimeout: () => null),
      ]);
      final updateAvailable = results[0] != null;
      final deletionRequest = results[1] as AccountDeletionRequest?;
      if (mounted) {
        setState(() {
          _updateAvailable = updateAvailable;
          _accountDeletionRequest = deletionRequest;
          _accountDeletionScheduled = deletionRequest != null;
          if (deletionRequest == null) _deletionBannerDismissed = false;
        });
      }
    } catch (_) {
      // Retain the last verified shell state during temporary network failure.
    }
  }

  Future<void> _synchronizeExecutionAlarm(LocalRuntime? runtime) async {
    final previousState = _lastExecutionState;
    final previousSession = _lastExecutionSession;
    final previousTaskId = _lastExecutionTaskId;
    final previousRevision = _lastExecutionRevision;
    final previousSegmentStartedAt = _lastExecutionSegmentStartedAt;
    _lastExecutionState = runtime?.state;
    _lastExecutionSession = runtime?.sessionId;
    _lastExecutionTaskId = runtime?.activeTaskId;
    _lastExecutionRevision = runtime?.revision;
    _lastExecutionSegmentStartedAt = runtime?.segmentStartedAt;
    final taskId = runtime?.activeTaskId;
    if (taskId == null || runtime == null || runtime.state == 'idle') {
      // Completing a task clears activeTaskId.  Keep the prior slot long
      // enough to cancel/supersede it, otherwise its old alarm survives and
      // fires after completion.
      final taskIdsToCancel = <String>{?previousTaskId, ?taskId};
      for (final id in taskIdsToCancel) {
        await localNotificationService.cancelExecutionCompletion(id);
      }
      return;
    }
    final task = await ref.read(taskRepositoryProvider).getTask(taskId);
    if (task == null) return;
    final executionNotificationsAuthorized = await localNotificationService
        .ensureExecutionNotificationsAuthorized();
    if (!executionNotificationsAuthorized) {
      if (mounted && !_executionNotificationPermissionDenied) {
        setState(() => _executionNotificationPermissionDenied = true);
      }
      return;
    }
    if (mounted && _executionNotificationPermissionDenied) {
      setState(() => _executionNotificationPermissionDenied = false);
    }
    final settings = ref.read(appSettingsProvider).value;
    final intervalChanged =
        previousTaskId != taskId ||
        previousState != runtime.state ||
        previousSession != runtime.sessionId ||
        previousRevision != runtime.revision ||
        previousSegmentStartedAt != runtime.segmentStartedAt;
    if (!intervalChanged) return;
    final now = DateTime.now().toUtc();
    late final int remainingMs;
    late final String eventType;
    if (task.executionMode == 'pomodoro') {
      final pomodoro = PomodoroExecutionSnapshot.fromTask(
        task: task,
        runtime: runtime,
        now: now,
      );
      remainingMs = pomodoro.remainingMs;
      if (!pomodoro.isBreak) {
        eventType = 'focus_completed';
      } else {
        eventType = pomodoro.isLongBreak
            ? 'long_break_completed'
            : 'short_break_completed';
      }
    } else {
      final intendedMs = task.estimatedDurationMs >= 60000
          ? task.estimatedDurationMs
          : const Duration(minutes: 30).inMilliseconds;
      final recordedMs = liveTaskRecordedWorkMs(
        recordedMs: runtime.accumulatedActiveMs,
        running: runtime.state == 'running',
        segmentStartedAt: runtime.segmentStartedAt,
        now: now,
      );
      remainingMs = (intendedMs - recordedMs).clamp(60000, intendedMs);
      eventType = 'duration_completed';
    }
    final category = eventType == 'duration_completed'
        ? 'task_reminders'
        : eventType;
    final preferencesJson = settings?.notificationPreferencesJson ?? '{}';
    final sound = NotificationSounds.forCategory(
      preferencesJson: preferencesJson,
      category: category,
      fallbackKey: settings?.notificationSoundKey ?? 'system',
    );
    // Realtime sends the same canonical boundary to every device. Remove the
    // previous interval alert before scheduling its successor so handling the
    // event on one device silences stale alarms everywhere else.
    if (previousTaskId != null && previousTaskId != task.id) {
      await localNotificationService.cancelExecutionCompletion(previousTaskId);
    }
    await localNotificationService.cancelExecutionCompletion(task.id);
    final scheduledAtUtc = now.add(Duration(milliseconds: remainingMs));
    final intervalId = [
      runtime.sessionId ?? 'no-session',
      runtime.state,
      eventType,
      runtime.segmentStartedAt?.toUtc().toIso8601String() ??
          runtime.updatedAt.toUtc().toIso8601String(),
    ].join(':');
    if (runtime.state != 'paused') {
      await localNotificationService.scheduleExecutionCompletion(
        id: LocalNotificationService.executionNotificationId(task.id),
        taskId: task.id,
        taskTitle: task.title,
        eventType: eventType,
        scheduledAtUtc: scheduledAtUtc,
        sound: sound,
        sessionId: runtime.sessionId,
        runtimeRevision: runtime.revision,
        intervalId: intervalId,
        category: category,
        enabled: NotificationSounds.categoryEnabled(
          preferencesJson: preferencesJson,
          category: category,
        ),
        vibration: NotificationSounds.vibrationForCategory(
          preferencesJson: preferencesJson,
          category: category,
        ),
        localeCode: settings?.localeCode ?? 'en',
      );
    }
    if (runtime.sessionId case final sessionId?) {
      await localNotificationService.showExecutionStatus(
        // A foreground status card and a future audible boundary are two
        // different OS notifications. Reusing the boundary ID here causes
        // show() to replace the scheduled alarm while the user is browsing.
        id: LocalNotificationService.executionStatusNotificationId(task.id),
        taskId: task.id,
        taskTitle: task.title,
        state: runtime.state,
        boundaryAtUtc: scheduledAtUtc,
        sound: sound,
        sessionId: sessionId,
        runtimeRevision: runtime.revision,
        intervalId: intervalId,
        eventType: eventType,
        vibration: false,
        localeCode: settings?.localeCode ?? 'en',
      );
    }
  }

  Future<void> _queueExecutionAlarmSynchronization(LocalRuntime? runtime) {
    final previous = _executionAlarmQueue;
    _executionAlarmQueue = previous
        .then((_) async {
          if (!mounted) return;
          await _synchronizeExecutionAlarm(runtime);
        })
        .catchError((Object _, StackTrace _) {
          // Preserve the queue after a transient platform scheduling failure.
        });
    return _executionAlarmQueue;
  }

  Future<void> _synchronizeStandalonePomodoroAlarm(
    StandalonePomodoroState state,
  ) async {
    _standaloneBoundaryTimer?.cancel();
    _standaloneBoundaryTimer = null;
    final boundaryAtUtc = state.boundaryAtUtc;
    if (boundaryAtUtc == null) {
      // A naturally completed interval keeps its just-delivered alert. Pause,
      // reset and mutual-exclusion shutdown retire the pending alarm.
      if (!state.isFinished) {
        await localNotificationService.cancelStandalonePomodoroCompletion();
      }
      return;
    }
    final settings = ref.read(appSettingsProvider).value;
    final category = state.isBreak
        ? 'short_break_completed'
        : 'focus_completed';
    final preferencesJson = settings?.notificationPreferencesJson ?? '{}';
    await localNotificationService.scheduleStandalonePomodoroCompletion(
      isBreak: state.isBreak,
      scheduledAtUtc: boundaryAtUtc,
      sound: NotificationSounds.forCategory(
        preferencesJson: preferencesJson,
        category: category,
        fallbackKey: settings?.notificationSoundKey ?? 'system',
      ),
      enabled: NotificationSounds.categoryEnabled(
        preferencesJson: preferencesJson,
        category: category,
      ),
      vibration: NotificationSounds.vibrationForCategory(
        preferencesJson: preferencesJson,
        category: category,
      ),
      localeCode: settings?.localeCode ?? 'en',
    );
    final delay = boundaryAtUtc.difference(DateTime.now().toUtc());
    _standaloneBoundaryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(
        ref
            .read(standalonePomodoroStoreProvider)
            .advanceIfDue(now: DateTime.now().toUtc()),
      ),
    );
  }

  void _queueStandaloneAlarmSynchronization(StandalonePomodoroState state) {
    final previous = _standaloneAlarmQueue;
    _standaloneAlarmQueue = previous
        .then((_) async {
          if (!mounted) return;
          await _synchronizeStandalonePomodoroAlarm(state);
        })
        .catchError((Object _, StackTrace _) {
          // The next durable standalone state transition retries scheduling.
        });
  }

  Future<void> _configureSleepReminder(LocalAppSetting settings) {
    return localNotificationService.scheduleDailySleepReminder(
      enabled: settings.sleepReminderEnabled,
      sleepTimeMinutes: settings.sleepTimeMinutes,
      reminderOffsetMinutes: settings.sleepReminderOffsetMinutes,
      timeZone: settings.timeZone,
      sound: NotificationSounds.forCategory(
        preferencesJson: settings.notificationPreferencesJson,
        category: 'sleep_health',
        fallbackKey: settings.notificationSoundKey,
      ),
      notificationsEnabled: NotificationSounds.categoryEnabled(
        preferencesJson: settings.notificationPreferencesJson,
        category: 'sleep_health',
      ),
      vibration: NotificationSounds.vibrationForCategory(
        preferencesJson: settings.notificationPreferencesJson,
        category: 'sleep_health',
      ),
      localeCode: settings.localeCode,
    );
  }

  Future<void> _synchronizePersistedTaskReminders({bool force = false}) async {
    if (!mounted) return;
    if (_reminderRefreshInFlight) {
      _reminderRefreshRequested = true;
      _forcedReminderRefreshRequested |= force;
      return;
    }
    _reminderRefreshInFlight = true;
    try {
      await _synchronizePersistedTaskRemindersOnce(force: force);
    } finally {
      _reminderRefreshInFlight = false;
      if (_reminderRefreshRequested && mounted) {
        final forceQueued = _forcedReminderRefreshRequested;
        _reminderRefreshRequested = false;
        _forcedReminderRefreshRequested = false;
        unawaited(_synchronizePersistedTaskReminders(force: forceQueued));
      }
    }
  }

  Future<void> _synchronizePersistedTaskRemindersOnce({
    required bool force,
  }) async {
    final now = DateTime.now().toUtc();
    if (!force &&
        _lastReminderRefresh != null &&
        now.difference(_lastReminderRefresh!) < const Duration(minutes: 1)) {
      return;
    }
    _lastReminderRefresh = now;
    final database = ref.read(databaseProvider);
    final records =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(widget.user.id) &
                  row.entityType.equals('task_reminders'),
            ))
            .get();
    final entities = ref.read(entityRecordRepositoryProvider);
    final tasks = ref.read(taskRepositoryProvider);
    final settings = ref.read(appSettingsProvider).value;
    final preferences = settings?.notificationPreferencesJson ?? '{}';
    final localeCode = settings?.localeCode ?? 'en';
    final pendingNotificationIds = await localNotificationService
        .pendingNotificationIds();
    final candidates =
        <
          ({
            LocalEntityRecord record,
            Map<String, Object?> data,
            Map<String, Object?> nested,
            DateTime scheduledAt,
            String taskId,
          })
        >[];
    for (final record in records) {
      final notificationId = record.id.hashCode & 0x7fffffff;
      final data = entities.decode(record);
      final nested = data['data'] is Map
          ? Map<String, Object?>.from(data['data'] as Map)
          : const <String, Object?>{};
      Object? field(String key) => data[key] ?? nested[key];
      final enabled = field('enabled') != false;
      final taskId = field('task_occurrence_id')?.toString() ?? record.parentId;
      final scheduledAt = DateTime.tryParse(
        field('scheduled_at')?.toString() ?? '',
      )?.toUtc();
      if (record.deletedAt != null ||
          !enabled ||
          taskId == null ||
          scheduledAt == null ||
          !scheduledAt.isAfter(now)) {
        if (pendingNotificationIds.contains(notificationId) ||
            _scheduledReminderFingerprints.containsKey(notificationId)) {
          await localNotificationService.cancel(notificationId);
        }
        _scheduledReminderFingerprints.remove(notificationId);
        continue;
      }
      candidates.add((
        record: record,
        data: data,
        nested: nested,
        scheduledAt: scheduledAt,
        taskId: taskId,
      ));
    }

    // Keep the operating-system alarm queue bounded and deterministic. Older
    // builds appended all reminders again on every refresh, eventually
    // exhausting the Windows scheduled-toast quota and terminating the app.
    candidates.sort(
      (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
    );
    for (final candidate in candidates.skip(
      NotificationSchedulePolicy.maxTaskReminders,
    )) {
      final notificationId = candidate.record.id.hashCode & 0x7fffffff;
      if (pendingNotificationIds.contains(notificationId) ||
          _scheduledReminderFingerprints.containsKey(notificationId)) {
        await localNotificationService.cancel(notificationId);
      }
      _scheduledReminderFingerprints.remove(notificationId);
    }

    final desiredNotificationIds = <int>{};
    for (final candidate in candidates.take(
      NotificationSchedulePolicy.maxTaskReminders,
    )) {
      final record = candidate.record;
      final notificationId = record.id.hashCode & 0x7fffffff;
      final data = candidate.data;
      final nested = candidate.nested;
      Object? field(String key) => data[key] ?? nested[key];
      final taskId = candidate.taskId;
      final scheduledAt = candidate.scheduledAt;
      final task = await tasks.getTask(taskId);
      if (task == null ||
          task.status == 'completed' ||
          task.status == 'cancelled') {
        if (pendingNotificationIds.contains(notificationId) ||
            _scheduledReminderFingerprints.containsKey(notificationId)) {
          await localNotificationService.cancel(notificationId);
        }
        _scheduledReminderFingerprints.remove(notificationId);
        continue;
      }
      final reminderType =
          field('reminder_type')?.toString() ?? 'scheduled_start';
      final category = NotificationSounds.categoryForReminderType(reminderType);
      final soundKey = field('sound_key')?.toString() ?? 'selected';
      final sound = soundKey == 'selected'
          ? NotificationSounds.forCategory(
              preferencesJson: preferences,
              category: category,
              fallbackKey: settings?.notificationSoundKey ?? 'system',
            )
          : NotificationSounds.byKey(soundKey);
      final categoryEnabled = NotificationSounds.categoryEnabled(
        preferencesJson: preferences,
        category: category,
      );
      if (!categoryEnabled) {
        if (pendingNotificationIds.contains(notificationId) ||
            _scheduledReminderFingerprints.containsKey(notificationId)) {
          await localNotificationService.cancel(notificationId);
        }
        _scheduledReminderFingerprints.remove(notificationId);
        continue;
      }
      final reminderFingerprint = Object.hash(
        record.id,
        record.revision,
        record.status,
        record.dataJson,
        task.id,
        task.revision,
        task.status,
        task.title,
        preferences,
        settings?.notificationSoundKey,
        localeCode,
      );
      desiredNotificationIds.add(notificationId);
      if (_scheduledReminderFingerprints[notificationId] ==
              reminderFingerprint &&
          pendingNotificationIds.contains(notificationId)) {
        continue;
      }
      await localNotificationService.scheduleTaskReminder(
        id: notificationId,
        taskId: task.id,
        taskTitle: task.title,
        reminderType: reminderType,
        scheduledAtUtc: scheduledAt,
        sound: sound,
        ownerId: widget.user.id,
        occurrenceId: task.occurrenceKey,
        taskRevision: task.revision,
        reminderRevision: record.revision,
        category: category,
        enabled: true,
        vibration: NotificationSounds.vibrationForCategory(
          preferencesJson: preferences,
          category: category,
        ),
        localeCode: localeCode,
      );
      _scheduledReminderFingerprints[notificationId] = reminderFingerprint;
      pendingNotificationIds.add(notificationId);
    }
    for (final staleId
        in _scheduledReminderFingerprints.keys
            .where((id) => !desiredNotificationIds.contains(id))
            .toList()) {
      if (pendingNotificationIds.contains(staleId)) {
        await localNotificationService.cancel(staleId);
      }
      _scheduledReminderFingerprints.remove(staleId);
    }
  }

  Future<void> _handleTrayCommand(String command) async {
    if (!mounted) return;
    final repository = ref.read(taskRepositoryProvider);
    final runtime = await repository.getRuntime();
    final activeTask = runtime?.activeTaskId == null
        ? null
        : await repository.getTask(runtime!.activeTaskId!);
    if (!mounted) return;
    switch (command) {
      case 'openActiveTask':
      case 'addNote':
        if (activeTask != null) {
          await TaskWorkspaceScreen.open(context, activeTask);
        }
      case 'addInterruption':
        if (activeTask != null) {
          await InterruptionEditorDialog.show(
            context,
            task: activeTask,
            sessionId: runtime?.sessionId,
          );
        }
      case 'pauseTask':
        if (activeTask != null) await repository.pause(activeTask);
      case 'resumeTask':
        if (activeTask != null) await repository.resume(activeTask);
      case 'finishTask':
        if (activeTask != null) {
          await completeTaskWithUndo(context, ref, activeTask);
        }
      case 'startBreak':
        if (activeTask != null) await repository.startBreak(activeTask);
      case 'startOfferedBreak':
        if (activeTask != null) {
          await TaskExecutionCommands.startOfferedBreak(repository, activeTask);
        }
      case 'finishBreak':
        if (activeTask != null) await repository.finishBreak(activeTask);
      case 'startNextTask':
        final tasks = await repository.watchTodayTasks(DateTime.now()).first;
        final next = tasks
            .where(
              (task) =>
                  task.status != 'completed' &&
                  task.status != 'cancelled' &&
                  task.status != 'in_progress',
            )
            .firstOrNull;
        if (next != null && mounted) {
          await startTaskWithConfirmation(
            context,
            ref,
            next,
            onOpenInAppResource: (url) {
              unawaited(
                TaskWorkspaceScreen.open(
                  context,
                  next,
                  initialSection: 3,
                  initialBrowserUrl: url,
                ),
              );
            },
          );
        }
      case 'openSync':
        await SynchronizationPanel.show(context);
      case 'syncNow':
        await _syncNowWithFeedback();
      case 'whatsNew':
        await showWhatsNewDialog(context, service: AppUpdateService());
      case 'settings':
        _selectDestination(5);
      case 'checkUpdate':
        await _checkForUpdateFromTray();
        _lastRemoteShellCheck = null;
        unawaited(_refreshTray());
      case 'accountDeletion':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const AccountDeletionScreen(),
          ),
        );
      case 'exit':
        final confirmed = activeTask == null
            ? true
            : await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.l10n.text('exit_app_question')),
                      content: Text(
                        context.l10n.text('exit_active_timer_saved'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(context.l10n.text('cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(context.l10n.text('exit')),
                        ),
                      ],
                    ),
                  ) ??
                  false;
        if (confirmed) {
          try {
            await ref
                .read(syncServiceProvider)
                .drainOutbox()
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
          await WindowsShellService.instance.exitApplication();
        }
    }
    unawaited(ref.read(syncServiceProvider).drainOutbox());
    unawaited(_refreshTray());
  }

  Future<void> _checkForUpdateFromTray() async {
    final service = AppUpdateService();
    try {
      final release = await service.checkForUpdate();
      if (!mounted) return;
      if (release != null) {
        await showAppUpdateDialog(context, service: service, release: release);
        return;
      }
      final version = await service.currentVersion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.format('update_up_to_date', {'version': version}),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('update_check_failed'))),
      );
    }
  }

  Future<void> _syncNowWithFeedback() async {
    final service = ref.read(syncServiceProvider);
    try {
      await service.pullChanges();
      await service.drainOutbox();
      final snapshot = await service.getSnapshot();
      if (!mounted) return;
      final message = snapshot.isTruthfullySynced
          ? context.l10n.text('sync_everything_up_to_date')
          : !snapshot.connectionAvailable
          ? context.l10n.text('sync_offline_saved')
          : snapshot.failedChanges > 0
          ? context.l10n.format('sync_most_completed', {
              'count': snapshot.failedChanges,
            })
          : context.l10n.format('sync_waiting_count', {
              'count': snapshot.pendingChanges,
            });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('sync_failed_saved'))),
      );
    }
  }

  Future<void> _handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final normalized = normalizeNotificationResponse(response);
    await _handleNotificationAction(
      payload: normalized.payload,
      actionId: normalized.actionId,
    );
  }

  Future<void> _handleNotificationAction({
    required String? payload,
    required String? actionId,
  }) async {
    if (payload == null) return;
    final ownedPayload = LocalNotificationService.decodeOwnedPayload(payload);
    final retiresReminderPendingAction =
        ownedPayload.reminderId != null &&
        const {'start', 'complete', 'snooze', 'dismiss'}.contains(actionId);
    if (ownedPayload.ownerId != null &&
        ownedPayload.ownerId != widget.user.id) {
      if (retiresReminderPendingAction) {
        await localNotificationService.cancelTaskReminder(ownedPayload);
      }
      return;
    }
    final route = ownedPayload.route;
    if (route == 'settings/notifications') {
      if (!mounted || actionId == 'dismiss') return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const NotificationsSoundsScreen(),
        ),
      );
      return;
    }
    if (route == 'settings/wellbeing') {
      if (!mounted || actionId == 'dismiss') return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ScheduleWellbeingScreen(),
        ),
      );
      return;
    }
    if (route == 'standalone-pomodoro') {
      await localNotificationService.cancelStandalonePomodoroCompletion();
      if (!mounted || actionId == 'dismiss') return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const StandalonePomodoroScreen(),
        ),
      );
      return;
    }
    if (route.startsWith('activity/')) {
      if (mounted) _selectDestination(4);
      return;
    }
    if (!route.startsWith('task/')) return;
    final taskId = route.substring('task/'.length);
    final repository = ref.read(taskRepositoryProvider);
    final task = await repository.getTask(taskId);
    if (task == null) {
      if (retiresReminderPendingAction) {
        await localNotificationService.cancelTaskReminder(ownedPayload);
      }
      return;
    }
    final hasExecutionEvent = ownedPayload.eventType != null;
    final requiresExecutionValidation =
        ownedPayload.hasExecutionIdentity &&
        actionId != null &&
        actionId != 'open';
    // A legacy timer card has no interval/revision identity.  It is safe to
    // open its task, but it must never mutate today's runtime: an old Android
    // card cannot be allowed to finish, pause, or restart a newer session.
    if (hasExecutionEvent &&
        !ownedPayload.hasExecutionIdentity &&
        actionId != null &&
        actionId != 'open') {
      return;
    }
    if (requiresExecutionValidation) {
      final ledgerValid = await localNotificationService
          .validateExecutionNotificationPayload(ownedPayload);
      if (!ledgerValid) {
        await _retireRejectedExecutionNotification(
          payload: ownedPayload,
          taskId: task.id,
          repository: repository,
        );
        return;
      }
      final runtime = await repository.getRuntime();
      final matchesCurrentInterval =
          runtime != null &&
          runtime.activeTaskId == task.id &&
          runtime.sessionId == ownedPayload.sessionId &&
          runtime.revision == ownedPayload.runtimeRevision &&
          runtime.state != 'idle';
      if (!matchesCurrentInterval) {
        await _retireRejectedExecutionNotification(
          payload: ownedPayload,
          taskId: task.id,
          repository: repository,
        );
        return;
      }
    }
    final expectedBoundaryAt = ownedPayload.boundaryAtUtc;
    final isFocusBoundary =
        ownedPayload.eventType == null ||
        ownedPayload.eventType == 'focus_completed';
    final isBreakBoundary =
        ownedPayload.eventType == null ||
        ownedPayload.eventType == 'break_completed' ||
        ownedPayload.eventType == 'short_break_completed' ||
        ownedPayload.eventType == 'long_break_completed';
    var transitionAccepted = true;
    switch (actionId) {
      case 'start':
        if (!mounted) {
          transitionAccepted = false;
        } else {
          transitionAccepted = await startTaskWithConfirmation(
            context,
            ref,
            task,
            onOpenInAppResource: (url) {
              unawaited(
                TaskWorkspaceScreen.open(
                  context,
                  task,
                  initialSection: 3,
                  initialBrowserUrl: url,
                ),
              );
            },
          );
        }
      case 'complete':
        if (!mounted) {
          transitionAccepted = false;
        } else {
          await completeTaskWithUndo(context, ref, task);
          transitionAccepted =
              (await repository.getTask(task.id))?.status == 'completed';
        }
      case 'pause':
        final before = await repository.getRuntime();
        await repository.pause(task);
        final after = await repository.getRuntime();
        transitionAccepted =
            before?.activeTaskId == task.id &&
            before?.state == 'running' &&
            after?.activeTaskId == task.id &&
            after?.state == 'paused' &&
            after!.revision > before!.revision;
      case 'resume':
        final before = await repository.getRuntime();
        await repository.resume(task);
        final after = await repository.getRuntime();
        transitionAccepted =
            before?.activeTaskId == task.id &&
            before?.state == 'paused' &&
            after?.activeTaskId == task.id &&
            after?.state == 'running' &&
            after!.revision > before!.revision;
      case 'start_break':
        if (isFocusBoundary) {
          transitionAccepted = await TaskExecutionCommands.startOfferedBreak(
            repository,
            task,
            expectedBoundaryAt: expectedBoundaryAt,
          );
        } else {
          transitionAccepted = false;
        }
      case 'start_focus':
        if (isBreakBoundary) {
          transitionAccepted =
              await TaskExecutionCommands.startFocusFromCompletedBreak(
                repository,
                task,
                expectedBoundaryAt: expectedBoundaryAt,
              );
        } else {
          transitionAccepted = false;
        }
      case 'finish_task':
        if (!mounted) {
          transitionAccepted = false;
        } else {
          final before = await repository.getRuntime();
          if (!mounted) {
            transitionAccepted = false;
            break;
          }
          await completeTaskWithUndo(context, ref, task);
          final completedTask = await repository.getTask(task.id);
          final after = await repository.getRuntime();
          transitionAccepted =
              completedTask?.status == 'completed' &&
              (before?.activeTaskId != task.id ||
                  after == null ||
                  after.activeTaskId != task.id ||
                  after.state == 'idle');
        }
      case 'continue_working':
        // A completed focus interval cannot merely dismiss its alert: the
        // timer would remain frozen at 00:00. Skipping the offered break is
        // one revision-guarded canonical transition that starts the next
        // focus without publishing an intermediate break state.
        if (isFocusBoundary) {
          transitionAccepted = await TaskExecutionCommands.skipOfferedBreak(
            repository,
            task,
            expectedBoundaryAt: expectedBoundaryAt,
          );
        } else {
          transitionAccepted = false;
        }
      case 'extend_break':
        if (isBreakBoundary) {
          transitionAccepted = await TaskExecutionCommands.extendBreak(
            repository: repository,
            task: task,
            expectedBoundaryAt: expectedBoundaryAt,
          );
        } else {
          transitionAccepted = false;
        }
      case 'review_break':
        if (mounted) _selectDestination(4);
      case 'add_time':
        // Older cards exposed “add time” by merely scheduling another local
        // alarm, without changing canonical task state.  Never manufacture a
        // timer from a notification; direct the user to the real task command.
        if (mounted) await TaskWorkspaceScreen.open(context, task);
      case 'snooze':
        final snoozeSettings = ref.read(appSettingsProvider).value;
        final snoozePreferences =
            snoozeSettings?.notificationPreferencesJson ?? '{}';
        await localNotificationService.scheduleTaskReminder(
          id: '${task.id}:snooze'.hashCode & 0x7fffffff,
          taskId: task.id,
          taskTitle: task.title,
          reminderType: 'snooze',
          ownerId: widget.user.id,
          scheduledAtUtc: DateTime.now().toUtc().add(
            const Duration(minutes: 10),
          ),
          sound: NotificationSounds.forCategory(
            preferencesJson: snoozePreferences,
            category: 'task_reminders',
            fallbackKey: snoozeSettings?.notificationSoundKey ?? 'system',
          ),
          category: 'task_reminders',
          enabled: NotificationSounds.categoryEnabled(
            preferencesJson: snoozePreferences,
            category: 'task_reminders',
          ),
          vibration: NotificationSounds.vibrationForCategory(
            preferencesJson: snoozePreferences,
            category: 'task_reminders',
          ),
          localeCode: snoozeSettings?.localeCode ?? 'en',
        );
      case 'dismiss':
        if (ownedPayload.hasExecutionIdentity) {
          await localNotificationService.cancelExecutionCompletion(task.id);
        }
      default:
        if (mounted) await TaskWorkspaceScreen.open(context, task);
    }
    if (requiresExecutionValidation) {
      if (transitionAccepted) {
        await localNotificationService.markExecutionNotificationHandled(
          ownedPayload,
        );
      } else {
        await _retireRejectedExecutionNotification(
          payload: ownedPayload,
          taskId: task.id,
          repository: repository,
        );
      }
    } else if (retiresReminderPendingAction) {
      // Windows mutation actions use pendingUpdate. Resolve that toast even
      // when the user declines a task switch or the local transition loses a
      // race; leaving it pending makes a handled action look unresponsive.
      // The reminder ID is isolated from the execution-alarm slot.
      await localNotificationService.cancelTaskReminder(ownedPayload);
    }
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  Future<void> _retireRejectedExecutionNotification({
    required OwnedNotificationPayload payload,
    required String taskId,
    required TaskRepository repository,
  }) async {
    // Windows pending-update keeps the old toast on screen until the app
    // acknowledges it. A rejected/superseded command must explicitly retire
    // that stale slot, then immediately recreate the notification for the
    // current canonical interval (if one still exists).
    await localNotificationService.markExecutionNotificationHandled(
      payload,
      state: 'superseded',
    );
    await localNotificationService.cancelExecutionCompletionWithState(
      taskId,
      ledgerState: 'superseded',
    );
    _lastExecutionRevision = null;
    await _queueExecutionAlarmSynchronization(await repository.getRuntime());
  }

  void _selectDestination(int index) {
    _backNavigation.recordDestination(from: _selectedIndex, to: index);
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  void _applyBackDestination(int index) {
    _backNavigation.cancelExit();
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  Future<void> _handleBackRequested() async {
    if (!mounted) return;

    // A route, sheet, dialog or browser workspace above the shell owns the
    // first back gesture. The shell never steals that navigation and never
    // turns it into an exit request.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      _backNavigation.cancelExit();
      await navigator.maybePop();
      return;
    }

    final decision = _backNavigation.resolve(
      currentIndex: _selectedIndex,
      rootIndex: _dashboardIndex,
      now: DateTime.now(),
    );
    switch (decision.action) {
      case HomeShellBackAction.navigateInApp:
        _applyBackDestination(decision.destinationIndex!);
        return;
      case HomeShellBackAction.showExitHint:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.text('back_exit_hint')),
              duration: _backNavigation.exitConfirmationWindow,
            ),
          );
        return;
      case HomeShellBackAction.exitApplication:
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await SystemNavigator.pop();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the account-scoped local execution gate alive for the authenticated
    // shell. A canonical runtime activation from another device then stops a
    // restored standalone timer even when its screen is not open.
    ref.watch(executionExclusivityCoordinatorProvider);
    // Keep vacation-aware recurrence materialization live for the account.
    // Canonical vacation rows projected by another device then adjust future
    // occurrences without requiring an app restart or a manual sync action.
    ref.watch(vacationScheduleCoordinatorProvider);
    ref.listen(appSettingsProvider, (previous, next) {
      final settings = next.value;
      if (settings != null &&
          (previous?.value?.sleepReminderEnabled !=
                  settings.sleepReminderEnabled ||
              previous?.value?.sleepTimeMinutes != settings.sleepTimeMinutes ||
              previous?.value?.sleepReminderOffsetMinutes !=
                  settings.sleepReminderOffsetMinutes ||
              previous?.value?.timeZone != settings.timeZone ||
              previous?.value?.localeCode != settings.localeCode ||
              previous?.value?.notificationSoundKey !=
                  settings.notificationSoundKey ||
              previous?.value?.notificationPreferencesJson !=
                  settings.notificationPreferencesJson)) {
        unawaited(_configureSleepReminder(settings));
        unawaited(_synchronizePersistedTaskReminders(force: true));
        unawaited(
          ref
              .read(standalonePomodoroStoreProvider)
              .load()
              .then(_queueStandaloneAlarmSynchronization),
        );
      }
    });
    ref.listen(syncHealthProvider, (previous, next) {
      if (next.value == SyncHealth.idle && previous?.value != SyncHealth.idle) {
        final previousHealth = previous?.value;
        final shouldForce =
            !_refreshedRemindersAfterInitialSync ||
            previousHealth == SyncHealth.offline ||
            previousHealth == SyncHealth.attention;
        _refreshedRemindersAfterInitialSync = true;
        unawaited(_synchronizePersistedTaskReminders(force: shouldForce));
      }
    });
    final l10n = context.l10n;
    final destinations = [
      (Icons.dashboard_outlined, Icons.dashboard, l10n.text('dashboard')),
      (Icons.task_alt_outlined, Icons.task_alt, l10n.text('tasks')),
      (
        Icons.calendar_month_outlined,
        Icons.calendar_month,
        l10n.text('calendar'),
      ),
      (Icons.route_outlined, Icons.route, l10n.text('roadmaps')),
      (Icons.insights_outlined, Icons.insights, l10n.text('activity')),
      (Icons.settings_outlined, Icons.settings, l10n.text('settings')),
    ];
    final pages = [
      DashboardScreen(
        user: widget.user,
        onOpenTasksFilter: (filter) {
          _backNavigation.recordDestination(from: _selectedIndex, to: 1);
          setState(() {
            _taskFilter = switch (filter) {
              'today' => TaskListFilter.today,
              'completed_today' => TaskListFilter.completedToday,
              'overdue' => TaskListFilter.overdue,
              _ => TaskListFilter.all,
            };
            _selectedIndex = 1;
          });
        },
        onOpenActivityFilter: (filter) {
          _backNavigation.recordDestination(from: _selectedIndex, to: 4);
          setState(() {
            _activityFilter = filter;
            _selectedIndex = 4;
          });
        },
      ),
      TasksScreen(
        key: ValueKey<String>('tasks:${_taskFilter.name}'),
        initialFilter: _taskFilter,
      ),
      PlanningCalendarScreen(user: widget.user),
      const RoadmapsScreen(),
      ActivityReviewScreen(
        key: ValueKey<String>('activity:$_activityFilter'),
        initialFilter: _activityFilter,
        onBack: () => unawaited(_handleBackRequested()),
      ),
      SettingsScreen(user: widget.user),
    ];

    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 900;
        if (!useRail) {
          final compactNavigation = usesCompactBottomNavigation(
            constraints.maxWidth,
          );
          return Scaffold(
            body: SafeArea(
              child: _ShellPageStack(
                selectedIndex: _selectedIndex,
                pages: pages,
              ),
            ),
            bottomNavigationBar: compactNavigation
                ? CompactBottomNavigationBar(
                    selectedIndex: _selectedIndex,
                    destinations: destinations,
                    onDestinationSelected: _selectDestination,
                  )
                : NavigationBar(
                    // Wider phones and small tablets retain labels, but
                    // keeping non-selected labels hidden prevents the six
                    // localized destination names from colliding.
                    labelBehavior:
                        NavigationDestinationLabelBehavior.onlyShowSelected,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectDestination,
                    destinations: [
                      for (final destination in destinations)
                        NavigationDestination(
                          icon: Icon(destination.$1),
                          selectedIcon: Icon(destination.$2),
                          label: destination.$3,
                        ),
                    ],
                  ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                Container(
                  width: 248,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: BorderDirectional(
                      end: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                        child: BrandLogo(themeKey: widget.themeKey, height: 54),
                      ),
                      _SidebarProfile(
                        user: widget.user,
                        onTap: () =>
                            _selectDestination(destinations.length - 1),
                      ),
                      Expanded(
                        child: NavigationRail(
                          extended: true,
                          minExtendedWidth: 248,
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: _selectDestination,
                          leading: const SizedBox(height: 12),
                          destinations: [
                            for (final destination in destinations)
                              NavigationRailDestination(
                                icon: Icon(destination.$1),
                                selectedIcon: Icon(destination.$2),
                                label: Text(destination.$3),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: ListTile(
                          key: const ValueKey<String>(
                            'sidebar-standalone-pomodoro-destination',
                          ),
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: const Icon(Icons.timer_outlined),
                          title: Text(l10n.text('standalone_pomodoro')),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const StandalonePomodoroScreen(),
                            ),
                          ),
                        ),
                      ),
                      const _CompactActiveTaskBar(),
                      const _SyncFooter(),
                    ],
                  ),
                ),
                Expanded(
                  child: _ShellPageStack(
                    selectedIndex: _selectedIndex,
                    pages: pages,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    final deletion = _accountDeletionRequest;
    final banners = <Widget>[
      if (_executionNotificationPermissionDenied)
        MaterialBanner(
          leading: const Icon(Icons.notifications_off_outlined),
          content: Text(l10n.text('notification_test_failed')),
          actions: [
            TextButton(
              onPressed: () async {
                await localNotificationService
                    .openAndroidAppNotificationSettings();
              },
              child: Text(l10n.text('open_system_settings')),
            ),
          ],
        ),
      if (deletion != null && !_deletionBannerDismissed)
        MaterialBanner(
          leading: const Icon(Icons.warning_amber_rounded),
          content: Text(
            l10n.format('account_deletion_countdown', {
              'days': deletion.remainingDays,
            }),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountDeletionScreen(),
                  ),
                );
                _lastRemoteShellCheck = null;
                await _refreshRemoteShellState();
              },
              child: Text(l10n.text('account_cancel_deletion')),
            ),
            TextButton(
              onPressed: () => setState(() => _deletionBannerDismissed = true),
              child: Text(l10n.text('account_continue')),
            ),
            TextButton(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              child: Text(l10n.text('sign_out')),
            ),
          ],
        ),
    ];
    final content = banners.isEmpty
        ? shell
        : Column(
            children: [
              ...banners,
              Expanded(child: shell),
            ],
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBackRequested());
      },
      child: content,
    );
  }
}

class CompactBottomNavigationBar extends StatelessWidget {
  const CompactBottomNavigationBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final List<(IconData, IconData, String)> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 8,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _CompactNavigationDestination(
                    destination: destinations[index],
                    selected: selectedIndex == index,
                    onPressed: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactNavigationDestination extends StatelessWidget {
  const _CompactNavigationDestination({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final (IconData, IconData, String) destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.$3,
      child: Tooltip(
        message: destination.$3,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? destination.$2 : destination.$1,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mounts only the selected top-level page.
///
/// An IndexedStack kept Dashboard, Tasks, Calendar, Roadmaps, Activity and the
/// entire Settings tree subscribed to Drift/Riverpod at the same time. Those
/// hidden queries and rebuilds made Start/Pause feel delayed on larger owner
/// accounts. PageStorage restores scroll positions while inactive pages fully
/// release their streams, animations and accessibility nodes.
class _ShellPageStack extends StatelessWidget {
  const _ShellPageStack({required this.selectedIndex, required this.pages});

  final int selectedIndex;
  final List<Widget> pages;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: PageStorageKey<String>('taskmaster-shell-page-$selectedIndex'),
      child: pages[selectedIndex],
    );
  }
}

class _SyncFooter extends ConsumerStatefulWidget {
  const _SyncFooter();

  @override
  ConsumerState<_SyncFooter> createState() => _SyncFooterState();
}

class _SyncFooterState extends ConsumerState<_SyncFooter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(syncHealthProvider).value ?? SyncHealth.idle;
    final visualState = shellSyncVisualState(health);
    final (icon, key, color, background) = switch (visualState) {
      ShellSyncVisualState.offline => (
        null,
        'sync_offline_compact',
        Theme.of(context).colorScheme.onSurfaceVariant,
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      ShellSyncVisualState.pending => (
        Icons.sync_rounded,
        'sync_latest',
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.primary,
      ),
      ShellSyncVisualState.attention => (
        Icons.sync_problem_rounded,
        'sync_needs_attention',
        Theme.of(context).colorScheme.error,
        Theme.of(context).colorScheme.error,
      ),
      ShellSyncVisualState.synced => (
        Icons.cloud_done_outlined,
        'sync_all_changes',
        TaskMasterTheme.green,
        TaskMasterTheme.green,
      ),
    };
    if (health == SyncHealth.syncing && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (health != SyncHealth.syncing && _rotation.isAnimating) {
      _rotation
        ..stop()
        ..value = 0;
    }
    final syncIcon = icon == null ? null : Icon(icon, size: 20, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          button: true,
          label: context.l10n.text(key),
          child: Tooltip(
            message: context.l10n.text(key),
            child: visualState == ShellSyncVisualState.offline
                ? TextButton(
                    key: const ValueKey('sync-offline-indicator'),
                    onPressed: () => SynchronizationPanel.show(context),
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      backgroundColor: background,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(color: color.withValues(alpha: 0.24)),
                    ),
                    child: Text(
                      context.l10n.text(key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : IconButton(
                    onPressed: () => SynchronizationPanel.show(context),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: background.withValues(alpha: 0.12),
                      side: BorderSide(
                        color: background.withValues(alpha: 0.24),
                      ),
                    ),
                    icon: health == SyncHealth.syncing
                        ? RotationTransition(turns: _rotation, child: syncIcon!)
                        : syncIcon!,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SidebarProfile extends ConsumerWidget {
  const _SidebarProfile({required this.user, required this.onTap});

  final User user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder(
      stream: ref.watch(settingsRepositoryProvider).watchProfile(user.id),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile == null) return const SizedBox.shrink();
        final name = profile.displayName.trim().isEmpty
            ? user.email?.split('@').first ?? context.l10n.text('profile')
            : profile.displayName;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Material(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    ProfileAvatar(
                      name: name,
                      imagePath: profile.imagePath,
                      radius: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            context.l10n.text('view_profile'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactActiveTaskBar extends ConsumerWidget {
  const _CompactActiveTaskBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    if (runtime == null || runtime.activeTaskId == null) {
      return const SizedBox.shrink();
    }
    final task = ref
        .watch(taskExecutionTaskProvider(runtime.activeTaskId!))
        .value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: task == null
              ? null
              : () =>
                    TaskWorkspaceScreen.open(context, task, initialSection: 1),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(switch (runtime.state) {
                  'running' => Icons.play_circle,
                  'break' => Icons.coffee_rounded,
                  _ => Icons.pause_circle,
                }, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task?.title ?? context.l10n.text('active_execution'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      _CompactElapsed(runtime: runtime, task: task),
                    ],
                  ),
                ),
                if (task != null)
                  _CompactExecutionControl(task: task, runtime: runtime),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactElapsed extends ConsumerWidget {
  const _CompactElapsed({required this.runtime, required this.task});

  final LocalRuntime runtime;
  final LocalTask? task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (runtime.state == 'running' || runtime.state == 'break') {
      ref.watch(taskExecutionClockProvider);
    }
    if (task?.executionMode == 'pomodoro') {
      final pomodoro = PomodoroExecutionSnapshot.fromTask(
        task: task!,
        runtime: runtime,
        now: DateTime.now().toUtc(),
      );
      final clock = formatPomodoroCountdown(pomodoro.remainingMs);
      return Text(
        '${context.l10n.text(pomodoro.isBreak ? 'pomodoro_break_session' : 'pomodoro_focus_session')} · $clock',
        style: Theme.of(context).textTheme.labelSmall,
      );
    }
    if (task == null) {
      return Text(
        context.l10n.taskStatus(runtime.state),
        style: Theme.of(context).textTheme.labelSmall,
      );
    }
    final recordedMs = liveTaskRecordedWorkMs(
      recordedMs: runtime.accumulatedActiveMs,
      running: runtime.state == 'running',
      segmentStartedAt: runtime.segmentStartedAt,
      now: DateTime.now().toUtc(),
    );
    final overtimeMs = taskEffortOvertimeMs(
      plannedMs: task!.estimatedDurationMs,
      recordedMs: recordedMs,
    );
    final showsOvertime = runtime.state == 'running' && overtimeMs > 0;
    final clock = showsOvertime
        ? formatTaskEffortOvertime(overtimeMs)
        : formatTaskEffortCountdown(
            taskEffortRemainingMs(
              plannedMs: task!.estimatedDurationMs,
              recordedMs: recordedMs,
            ),
          );
    return Text(
      '${showsOvertime
          ? context.l10n.text('overtime_label')
          : runtime.state == 'break'
          ? context.l10n.text('break_in_progress')
          : context.l10n.taskStatus(runtime.state)} · $clock',
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _CompactExecutionControl extends ConsumerStatefulWidget {
  const _CompactExecutionControl({required this.task, required this.runtime});

  final LocalTask task;
  final LocalRuntime runtime;

  @override
  ConsumerState<_CompactExecutionControl> createState() =>
      _CompactExecutionControlState();
}

class _CompactExecutionControlState
    extends ConsumerState<_CompactExecutionControl> {
  bool _busy = false;

  Future<void> _run(TaskExecutionPrimaryAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: () async {
          final repository = ref.read(taskRepositoryProvider);
          switch (action) {
            case TaskExecutionPrimaryAction.start:
              await startTaskWithConfirmation(
                context,
                ref,
                widget.task,
                onOpenInAppResource: (url) {
                  unawaited(
                    TaskWorkspaceScreen.open(
                      context,
                      widget.task,
                      initialSection: 3,
                      initialBrowserUrl: url,
                    ),
                  );
                },
              );
            case TaskExecutionPrimaryAction.pause:
              await repository.pause(widget.task);
            case TaskExecutionPrimaryAction.resume:
              await repository.resume(widget.task);
            case TaskExecutionPrimaryAction.startBreak:
              await TaskExecutionCommands.startOfferedBreak(
                repository,
                widget.task,
              );
            case TaskExecutionPrimaryAction.startFocus:
              await repository.finishBreak(widget.task);
          }
        },
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSecondary(_CompactTimerAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    var extended = false;
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: () async {
          final repository = ref.read(taskRepositoryProvider);
          switch (action) {
            case _CompactTimerAction.startBreakEarly:
              await repository.startBreak(widget.task);
            case _CompactTimerAction.skipOfferedBreak:
              await TaskExecutionCommands.skipOfferedBreak(
                repository,
                widget.task,
              );
            case _CompactTimerAction.extendBreak:
              extended = await TaskExecutionCommands.extendBreak(
                repository: repository,
                task: widget.task,
              );
            case _CompactTimerAction.finishTask:
              await completeTaskWithUndo(context, ref, widget.task);
          }
        },
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
      if (extended && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('break_extended_five'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.runtime.state == 'running' || widget.runtime.state == 'break') {
      ref.watch(taskExecutionClockProvider);
    }
    final pomodoro = widget.task.executionMode == 'pomodoro'
        ? PomodoroExecutionSnapshot.fromTask(
            task: widget.task,
            runtime: widget.runtime,
            now: DateTime.now().toUtc(),
          )
        : null;
    final controls = TaskExecutionControlState.from(
      taskId: widget.task.id,
      executionMode: widget.task.executionMode,
      runtime: widget.runtime,
      pomodoro: pomodoro,
    );
    final onBreak = widget.runtime.state == 'break';
    final tooltipKey = onBreak
        ? 'pomodoro_skip_break'
        : switch (controls.primary) {
            TaskExecutionPrimaryAction.start => 'start',
            TaskExecutionPrimaryAction.pause => 'pause',
            TaskExecutionPrimaryAction.resume => 'resume',
            TaskExecutionPrimaryAction.startBreak => 'notification_start_break',
            TaskExecutionPrimaryAction.startFocus => 'notification_start_focus',
          };
    final icon = onBreak
        ? Icons.skip_next_rounded
        : switch (controls.primary) {
            TaskExecutionPrimaryAction.pause => Icons.pause,
            TaskExecutionPrimaryAction.startBreak => Icons.coffee_outlined,
            TaskExecutionPrimaryAction.startFocus => Icons.center_focus_strong,
            _ => Icons.play_arrow,
          };
    final secondaryActions = <_CompactTimerAction>[
      if (controls.canStartBreakEarly) _CompactTimerAction.startBreakEarly,
      if (controls.canSkipBreak) _CompactTimerAction.skipOfferedBreak,
      if (controls.canExtendBreak) _CompactTimerAction.extendBreak,
      if (controls.ownsTask) _CompactTimerAction.finishTask,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('compact-active-task-primary-control'),
          tooltip: context.l10n.text(tooltipKey),
          visualDensity: VisualDensity.compact,
          onPressed: _busy ? null : () => _run(controls.primary),
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon),
        ),
        if (secondaryActions.isNotEmpty)
          PopupMenuButton<_CompactTimerAction>(
            key: const ValueKey('compact-active-task-more-controls'),
            enabled: !_busy,
            tooltip: context.l10n.text('more'),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: _runSecondary,
            itemBuilder: (context) => [
              for (final action in secondaryActions)
                PopupMenuItem<_CompactTimerAction>(
                  value: action,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_compactTimerActionIcon(action)),
                    title: Text(
                      context.l10n.text(_compactTimerActionLabel(action)),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

enum _CompactTimerAction {
  startBreakEarly,
  skipOfferedBreak,
  extendBreak,
  finishTask,
}

String _compactTimerActionLabel(_CompactTimerAction action) => switch (action) {
  _CompactTimerAction.startBreakEarly => 'notification_start_break',
  _CompactTimerAction.skipOfferedBreak => 'pomodoro_skip_break',
  _CompactTimerAction.extendBreak => 'notification_extend_break',
  _CompactTimerAction.finishTask => 'finish_task',
};

IconData _compactTimerActionIcon(_CompactTimerAction action) =>
    switch (action) {
      _CompactTimerAction.startBreakEarly => Icons.coffee_outlined,
      _CompactTimerAction.skipOfferedBreak => Icons.skip_next_rounded,
      _CompactTimerAction.extendBreak => Icons.more_time,
      _CompactTimerAction.finishTask => Icons.check_rounded,
    };
