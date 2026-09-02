import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/activity/data/activity_repository.dart';
import '../../features/roadmaps/data/roadmap_repository.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/tasks/data/standalone_pomodoro_store.dart';
import '../../features/tasks/data/task_execution_commands.dart';
import '../../features/tasks/data/task_repository.dart';
import '../../features/tasks/domain/pomodoro_execution_state.dart';
import '../config/backend_target_cutover.dart';
import '../config/supabase_config.dart';
import '../database/app_database.dart';
import '../notifications/notification_sounds.dart';
import '../sync/sync_service.dart';
import 'android_home_widget_projection.dart';
import 'android_home_widget_service.dart';

const _backgroundActionChannel = MethodChannel(
  'taskmasterpro/background_actions',
);

/// Executes one external control inside a dedicated headless Flutter engine.
/// The engine is started by an explicit Android BroadcastReceiver/Service and
/// never creates or foregrounds MainActivity.
abstract final class BackgroundExecutionActionService {
  static Future<void>? _supabaseInitialization;

  static Future<void> runPendingAndroidAction() async {
    final raw = await _backgroundActionChannel
        .invokeMapMethod<Object?, Object?>('takeAction');
    final values = raw == null ? null : Map<Object?, Object?>.from(raw);
    final deliveryId = values?['deliveryId']?.toString().trim() ?? '';
    if (values == null || deliveryId.isEmpty) return;

    var handled = false;
    try {
      handled = switch (values['kind']?.toString()) {
        'widget' => await _handleWidget(values),
        'notification' => await _handleNotification(values),
        _ => false,
      };
    } catch (error, stackTrace) {
      debugPrint('Headless task control failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      await _backgroundActionChannel.invokeMethod<void>('completeAction', {
        'deliveryId': deliveryId,
        'handled': handled,
      });
    }
  }

  static Future<bool> _handleWidget(Map<Object?, Object?> values) async {
    final action = AndroidHomeWidgetAction.fromMap(values);
    if (action == null) return false;
    final context = await _openAccount(action.ownerId);
    if (context == null) return false;
    try {
      final accepted = await _executeWidgetAction(context, action);
      if (accepted) {
        await _drainOutbox(context);
      }
      // Sync can acknowledge the optimistic command or replace it with a
      // newer canonical revision. Project only after that decision so the
      // launcher never keeps a state which the app has already rolled back.
      await _refreshWidget(context);
      await _refreshExecutionNotifications(
        context,
        previousTaskId: action.taskId,
      );
      return accepted;
    } finally {
      await context.database.close();
    }
  }

  static Future<bool> _handleNotification(Map<Object?, Object?> values) async {
    final payload = values['payload']?.toString().trim() ?? '';
    final actionId = values['id']?.toString().trim() ?? '';
    if (payload.isEmpty || actionId.isEmpty) return false;
    final owned = LocalNotificationService.decodeOwnedPayload(payload);
    final ownerId = owned.ownerId;
    if (ownerId == null || ownerId.isEmpty) return false;
    if (actionId == 'dismiss') return true;

    final context = await _openAccount(ownerId);
    if (context == null) return false;
    try {
      await localNotificationService.initialize();
      final taskId = owned.taskId;
      if (taskId == null || taskId.isEmpty) return false;
      final task = await context.tasks.getTask(taskId);
      if (task == null) return false;

      final mutatesExecution = const {
        'pause',
        'resume',
        'start_break',
        'start_focus',
        'continue_working',
        'extend_break',
        'finish_task',
      }.contains(actionId);
      if (mutatesExecution) {
        if (!owned.hasExecutionIdentity) return false;
        if (!await localNotificationService
            .validateExecutionNotificationPayload(owned)) {
          await _reconcileRejectedExternalAction(
            context,
            previousTaskId: task.id,
          );
          return false;
        }
        final runtime = await context.tasks.getRuntime();
        if (runtime == null ||
            runtime.activeTaskId != task.id ||
            runtime.sessionId != owned.sessionId ||
            runtime.revision != owned.runtimeRevision ||
            runtime.state == 'idle') {
          await _reconcileRejectedExternalAction(
            context,
            previousTaskId: task.id,
          );
          return false;
        }
      }

      final accepted = await _executeNotificationAction(
        context,
        task,
        actionId: actionId,
        owned: owned,
      );
      if (!accepted) {
        await _reconcileRejectedExternalAction(
          context,
          previousTaskId: task.id,
        );
        return false;
      }

      if (mutatesExecution) {
        await localNotificationService.cancelExecutionCompletionWithState(
          task.id,
          ledgerState: 'handled',
        );
      } else if (owned.reminderId != null) {
        await localNotificationService.cancelTaskReminder(owned);
      }
      await _drainOutbox(context);
      await _refreshWidget(context);
      await _refreshExecutionNotifications(context, previousTaskId: task.id);
      return true;
    } finally {
      await context.database.close();
    }
  }

  static Future<_BackgroundAccountContext?> _openAccount(String ownerId) async {
    await (_supabaseInitialization ??= _initializeSupabase());
    final client = Supabase.instance.client;
    if (client.auth.currentUser?.id != ownerId) return null;
    final database = AppDatabase.forAccount(ownerId);
    final roadmaps = RoadmapRepository(database, client);
    return _BackgroundAccountContext(
      ownerId: ownerId,
      database: database,
      client: client,
      tasks: TaskRepository(
        database,
        client,
        recalculateRoadmap: roadmaps.recalculateProgress,
      ),
      settings: SettingsRepository(database, client),
      activity: ActivityRepository(database, client),
    );
  }

  static Future<void> _initializeSupabase() async {
    final targetStore = await SharedPreferencesBackendTargetStore.open();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        // A service-owned engine must never compete with the foreground app
        // for an OAuth or recovery callback.
        detectSessionInUri: false,
        localStorage: SharedPreferencesLocalStorage(
          persistSessionKey: BackendTargetCutover.sessionStorageKeyForProject(
            SupabaseConfig.projectRef,
          ),
        ),
        pkceAsyncStorage: ProjectScopedGotrueAsyncStorage(
          store: targetStore,
          projectRef: SupabaseConfig.projectRef,
        ),
      ),
    );
  }

  static bool _matchesWidgetRuntime(
    LocalRuntime? runtime,
    AndroidHomeWidgetAction action,
  ) =>
      runtime != null &&
      runtime.activeTaskId == action.taskId &&
      runtime.sessionId == action.sessionId &&
      runtime.revision == action.runtimeRevision &&
      runtime.state != 'idle';

  static Future<bool> _executeWidgetAction(
    _BackgroundAccountContext context,
    AndroidHomeWidgetAction action,
  ) async {
    final runtime = await context.tasks.getRuntime();
    if (!_matchesWidgetRuntime(runtime, action)) return false;
    final task = await context.tasks.getTask(action.taskId);
    if (task == null) return false;

    switch (action.id) {
      case 'pause':
        if (runtime!.state != 'running') return false;
        await context.tasks.pause(task);
        return (await context.tasks.getRuntime())?.state == 'paused';
      case 'resume':
        if (runtime!.state != 'paused') return false;
        await context.tasks.resume(task);
        return (await context.tasks.getRuntime())?.state == 'running';
      case 'start_break':
        if (runtime!.state != 'running' || task.executionMode != 'pomodoro') {
          return false;
        }
        final pomodoro = PomodoroExecutionSnapshot.fromTask(
          task: task,
          runtime: runtime,
          now: DateTime.now().toUtc(),
        );
        if (pomodoro.focusComplete) {
          return TaskExecutionCommands.startOfferedBreak(context.tasks, task);
        }
        await context.tasks.startBreak(task);
        return (await context.tasks.getRuntime())?.state == 'break';
      case 'start_focus':
        if (runtime!.state != 'break') return false;
        return _finishBreakAndQueueReview(context, task, runtime: runtime);
      case 'extend_break':
        if (runtime!.state != 'break') return false;
        return TaskExecutionCommands.extendBreak(
          repository: context.tasks,
          task: task,
        );
      case 'finish_task':
        await context.tasks.complete(task);
        return (await context.tasks.getTask(task.id))?.status == 'completed';
      default:
        return false;
    }
  }

  static Future<bool> _executeNotificationAction(
    _BackgroundAccountContext context,
    LocalTask task, {
    required String actionId,
    required OwnedNotificationPayload owned,
  }) async {
    final runtime = await context.tasks.getRuntime();
    final expectedBoundary = owned.boundaryAtUtc;
    final isStatus = owned.isExecutionStatus;
    final isFocusBoundary =
        owned.eventType == null || owned.eventType == 'focus_completed';
    final isBreakBoundary =
        owned.eventType == null ||
        owned.eventType == 'break_completed' ||
        owned.eventType == 'short_break_completed' ||
        owned.eventType == 'long_break_completed';

    switch (actionId) {
      case 'start':
        final standalone = await StandalonePomodoroStore(
          accountId: context.ownerId,
        ).load();
        if (standalone.isActive) return false;
        final result = await context.tasks.start(task);
        if (result.requiresSwitch) return false;
        final started = await context.tasks.getRuntime();
        return started?.activeTaskId == task.id && started?.state == 'running';
      case 'complete':
      case 'finish_task':
        await context.tasks.complete(task);
        return (await context.tasks.getTask(task.id))?.status == 'completed';
      case 'pause':
        if (runtime?.state != 'running') return false;
        await context.tasks.pause(task);
        return (await context.tasks.getRuntime())?.state == 'paused';
      case 'resume':
        if (runtime?.state != 'paused') return false;
        await context.tasks.resume(task);
        return (await context.tasks.getRuntime())?.state == 'running';
      case 'start_break':
        if (!isFocusBoundary) return false;
        return TaskExecutionCommands.startOfferedBreak(
          context.tasks,
          task,
          expectedBoundaryAt: expectedBoundary,
        );
      case 'start_focus':
        if (runtime == null || runtime.state != 'break') return false;
        if (isStatus) {
          return _finishBreakAndQueueReview(context, task, runtime: runtime);
        }
        if (!isBreakBoundary) return false;
        return _finishBreakAndQueueReview(
          context,
          task,
          runtime: runtime,
          requireCompletedBoundary: true,
          expectedBoundaryAt: expectedBoundary,
        );
      case 'continue_working':
        if (!isFocusBoundary) return false;
        return TaskExecutionCommands.skipOfferedBreak(
          context.tasks,
          task,
          expectedBoundaryAt: expectedBoundary,
        );
      case 'extend_break':
        if (isStatus) {
          return TaskExecutionCommands.extendBreak(
            repository: context.tasks,
            task: task,
          );
        }
        if (!isBreakBoundary) return false;
        return TaskExecutionCommands.extendBreak(
          repository: context.tasks,
          task: task,
          expectedBoundaryAt: expectedBoundary,
        );
      case 'snooze':
        final settings = await context.settings.watchSettings().first;
        final preferences = settings?.notificationPreferencesJson ?? '{}';
        await localNotificationService.scheduleTaskReminder(
          id: LocalNotificationService.taskReminderNotificationId(
            '${task.id}:snooze',
          ),
          taskId: task.id,
          taskTitle: task.title,
          reminderType: 'snooze',
          ownerId: context.ownerId,
          scheduledAtUtc: DateTime.now().toUtc().add(
            const Duration(minutes: 10),
          ),
          sound: NotificationSounds.forCategory(
            preferencesJson: preferences,
            category: 'task_reminders',
            fallbackKey: settings?.notificationSoundKey ?? 'system',
          ),
          category: 'task_reminders',
          enabled: NotificationSounds.categoryEnabled(
            preferencesJson: preferences,
            category: 'task_reminders',
          ),
          vibration: NotificationSounds.vibrationForCategory(
            preferencesJson: preferences,
            category: 'task_reminders',
          ),
          localeCode: settings?.localeCode ?? 'en',
        );
        return true;
      default:
        return false;
    }
  }

  static Future<bool> _finishBreakAndQueueReview(
    _BackgroundAccountContext context,
    LocalTask task, {
    required LocalRuntime runtime,
    bool requireCompletedBoundary = false,
    DateTime? expectedBoundaryAt,
  }) async {
    ActivityReviewEntry? review;
    final transition = requireCompletedBoundary
        ? await TaskExecutionCommands.startFocusFromCompletedBreak(
            context.tasks,
            task,
            expectedBoundaryAt: expectedBoundaryAt,
            beforeFinishBreak: (task, runtime) async {
              review = await context.activity
                  .prepareBreakActivityReviewIfNeeded(
                    taskId: task.id,
                    sessionId: runtime.sessionId!,
                    startedAt: runtime.segmentStartedAt!,
                    endedAt: expectedBoundaryAt,
                  );
            },
          )
        : await TaskExecutionCommands.startFocusFromActiveBreak(
            context.tasks,
            task,
            beforeFinishBreak: (task, runtime) async {
              review = await context.activity
                  .prepareBreakActivityReviewIfNeeded(
                    taskId: task.id,
                    sessionId: runtime.sessionId!,
                    startedAt: runtime.segmentStartedAt!,
                  );
            },
          );
    if (transition && review != null) {
      await _showBreakReviewNotification(context, task.id);
    }
    return transition;
  }

  static Future<void> _showBreakReviewNotification(
    _BackgroundAccountContext context,
    String taskId,
  ) async {
    final settings = await context.settings.watchSettings().first;
    final preferences = settings?.notificationPreferencesJson ?? '{}';
    await localNotificationService.showActivityReviewAlert(
      taskId: taskId,
      sound: NotificationSounds.forCategory(
        preferencesJson: preferences,
        category: 'activity_review',
        fallbackKey: settings?.notificationSoundKey ?? 'system',
      ),
      enabled: NotificationSounds.categoryEnabled(
        preferencesJson: preferences,
        category: 'activity_review',
      ),
      vibration: NotificationSounds.vibrationForCategory(
        preferencesJson: preferences,
        category: 'activity_review',
      ),
      localeCode: settings?.localeCode ?? 'en',
    );
  }

  static Future<void> _refreshWidget(_BackgroundAccountContext context) async {
    final settings = await context.settings.watchSettings().first;
    final state = await AndroidHomeWidgetProjection.build(
      repository: context.tasks,
      ownerId: context.ownerId,
      localeCode: settings?.localeCode ?? 'en',
    );
    final service = AndroidHomeWidgetService(
      channel: _backgroundActionChannel,
      supportedPlatform: true,
    );
    await service.update(state);
  }

  static Future<void> _reconcileRejectedExternalAction(
    _BackgroundAccountContext context, {
    required String previousTaskId,
  }) async {
    await localNotificationService.cancelExecutionCompletionWithState(
      previousTaskId,
      ledgerState: 'superseded',
    );
    await _refreshWidget(context);
    await _refreshExecutionNotifications(
      context,
      previousTaskId: previousTaskId,
    );
  }

  static Future<void> _refreshExecutionNotifications(
    _BackgroundAccountContext context, {
    required String previousTaskId,
  }) async {
    await localNotificationService.initialize();
    final runtime = await context.tasks.getRuntime();
    if (runtime == null ||
        runtime.activeTaskId == null ||
        runtime.state == 'idle') {
      await localNotificationService.cancelOrphanedExecutionNotifications(
        activeTaskId: null,
      );
      await localNotificationService.cancelExecutionCompletion(previousTaskId);
      return;
    }
    await localNotificationService.cancelOrphanedExecutionNotifications(
      activeTaskId: runtime.activeTaskId,
    );
    final task = await context.tasks.getTask(runtime.activeTaskId!);
    if (task == null || runtime.sessionId == null) return;
    final settings = await context.settings.watchSettings().first;
    final now = DateTime.now().toUtc();
    late int remainingMs;
    late String eventType;
    if (task.executionMode == 'pomodoro') {
      final pomodoro = PomodoroExecutionSnapshot.fromTask(
        task: task,
        runtime: runtime,
        now: now,
      );
      remainingMs = pomodoro.remainingMs;
      eventType = pomodoro.isBreak
          ? pomodoro.isLongBreak
                ? 'long_break_completed'
                : 'short_break_completed'
          : 'focus_completed';
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
    final preferences = settings?.notificationPreferencesJson ?? '{}';
    final sound = NotificationSounds.forCategory(
      preferencesJson: preferences,
      category: category,
      fallbackKey: settings?.notificationSoundKey ?? 'system',
    );
    final boundary = now.add(Duration(milliseconds: remainingMs));
    final intervalId = [
      runtime.sessionId!,
      runtime.state,
      eventType,
      runtime.segmentStartedAt?.toUtc().toIso8601String() ??
          runtime.updatedAt.toUtc().toIso8601String(),
    ].join(':');

    await localNotificationService.cancelExecutionCompletion(previousTaskId);
    if (previousTaskId != task.id) {
      await localNotificationService.cancelExecutionCompletion(task.id);
    }
    if (runtime.state != 'paused' &&
        NotificationSounds.categoryEnabled(
          preferencesJson: preferences,
          category: category,
        )) {
      await localNotificationService.scheduleExecutionCompletion(
        id: LocalNotificationService.executionNotificationId(task.id),
        taskId: task.id,
        taskTitle: task.title,
        eventType: eventType,
        scheduledAtUtc: boundary,
        sound: sound,
        sessionId: runtime.sessionId,
        runtimeRevision: runtime.revision,
        intervalId: intervalId,
        category: category,
        enabled: true,
        vibration: NotificationSounds.vibrationForCategory(
          preferencesJson: preferences,
          category: category,
        ),
        localeCode: settings?.localeCode ?? 'en',
      );
    }
    await localNotificationService.showExecutionStatus(
      id: LocalNotificationService.executionStatusNotificationId(task.id),
      taskId: task.id,
      taskTitle: task.title,
      state: runtime.state,
      boundaryAtUtc: boundary,
      sound: sound,
      sessionId: runtime.sessionId!,
      runtimeRevision: runtime.revision,
      intervalId: intervalId,
      eventType: eventType,
      vibration: false,
      localeCode: settings?.localeCode ?? 'en',
    );
  }

  static Future<void> _drainOutbox(_BackgroundAccountContext context) async {
    final sync = SyncService(
      database: context.database,
      client: context.client,
    );
    try {
      await sync.deliverPendingOutboxForHeadlessAction().timeout(
        const Duration(seconds: 20),
      );
    } catch (error, stackTrace) {
      debugPrint('Headless task control delivery deferred: $error');
      debugPrintStack(stackTrace: stackTrace);
      // The durable local command remains queued for the normal sync worker.
    } finally {
      await sync.dispose();
    }
  }
}

class _BackgroundAccountContext {
  const _BackgroundAccountContext({
    required this.ownerId,
    required this.database,
    required this.client,
    required this.tasks,
    required this.settings,
    required this.activity,
  });

  final String ownerId;
  final AppDatabase database;
  final SupabaseClient client;
  final TaskRepository tasks;
  final SettingsRepository settings;
  final ActivityRepository activity;
}
