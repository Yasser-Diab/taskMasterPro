import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/notifications/notification_sounds.dart';

void main() {
  test('uses a category-specific sound when one is synchronized', () {
    final sound = NotificationSounds.forCategory(
      preferencesJson: '{"focus_sound":"alarm"}',
      category: 'focus',
      fallbackKey: 'system',
    );

    expect(sound.key, 'alarm');
  });

  test('keeps the established global sound for older preferences', () {
    final sound = NotificationSounds.forCategory(
      preferencesJson: '{}',
      category: 'breaks',
      fallbackKey: 'done',
    );

    expect(sound.key, 'done');
  });

  test('legacy call sites resolve the v0.0.26 category choice', () {
    final sound = NotificationSounds.forCategory(
      preferencesJson:
          '{"focus_completed_sound":"ui_tone","focus_completed":false,'
          '"focus_completed_vibration":false}',
      category: 'focus',
      fallbackKey: 'system',
    );

    expect(sound.key, 'ui_tone');
    expect(
      NotificationSounds.categoryEnabled(
        preferencesJson: '{"focus_completed":false}',
        category: 'focus',
      ),
      isFalse,
    );
    expect(
      NotificationSounds.vibrationForCategory(
        preferencesJson: '{"focus_completed_vibration":false}',
        category: 'focus',
      ),
      isFalse,
    );
  });

  test('device sound choices survive synchronized JSON storage', () {
    final selected = NotificationSounds.device(
      uri: 'content://media/internal/audio/media/42',
      kind: 'alarm',
      label: 'Morning bell',
    );
    final decoded = NotificationSounds.byKey(selected.key);

    expect(decoded.deviceUri, 'content://media/internal/audio/media/42');
    expect(decoded.deviceKind, 'alarm');
    expect(decoded.deviceLabel, 'Morning bell');
    expect(decoded.channelKey, startsWith('device_'));
  });

  test('device sound channel identity includes its Android audio usage', () {
    const uri = 'content://media/internal/audio/media/42';
    final notification = NotificationSounds.device(
      uri: uri,
      kind: 'notification',
      label: 'Morning bell',
    );
    final alarm = NotificationSounds.device(
      uri: uri,
      kind: 'alarm',
      label: 'Morning bell',
    );

    expect(notification.channelKey, isNot(alarm.channelKey));
  });

  test('notification scheduling rejects due and nearly-due timestamps', () {
    final now = DateTime.utc(2026, 7, 28, 12);

    expect(
      NotificationSchedulePolicy.canSchedule(
        now.subtract(const Duration(seconds: 1)),
        nowUtc: now,
      ),
      isFalse,
    );
    expect(
      NotificationSchedulePolicy.canSchedule(
        now.add(NotificationSchedulePolicy.minimumLeadTime),
        nowUtc: now,
      ),
      isFalse,
    );
    expect(
      NotificationSchedulePolicy.canSchedule(
        now.add(const Duration(seconds: 3)),
        nowUtc: now,
      ),
      isTrue,
    );
    expect(NotificationSchedulePolicy.maxTaskReminders, 64);
  });

  test('execution notification actions require the exact ledger interval', () {
    final boundary = DateTime.utc(2026, 8, 10, 12, 25);
    const payload = OwnedNotificationPayload(
      route: 'task/task-1',
      ownerId: 'owner-1',
      eventType: 'focus_completed',
      notificationId: 'notification-1',
      sessionId: 'session-1',
      runtimeRevision: 42,
      intervalId: 'session-1:running:focus',
    );
    final exactPayload = OwnedNotificationPayload(
      route: payload.route,
      ownerId: payload.ownerId,
      eventType: payload.eventType,
      notificationId: payload.notificationId,
      sessionId: payload.sessionId,
      runtimeRevision: payload.runtimeRevision,
      intervalId: payload.intervalId,
      boundaryAtUtc: boundary,
    );
    final ledger = <String, Object?>{
      'task_id': 'task-1',
      'notification_id': 'notification-1',
      'session_id': 'session-1',
      'runtime_revision': 42,
      'interval_id': 'session-1:running:focus',
      'boundary_at': boundary.toIso8601String(),
      'state': 'scheduled',
    };

    expect(
      executionNotificationIdentityMatches(
        payload: exactPayload,
        ledger: ledger,
      ),
      isTrue,
    );
    expect(
      executionNotificationIdentityMatches(
        payload: exactPayload,
        ledger: {...ledger, 'runtime_revision': 41},
      ),
      isFalse,
    );
    expect(
      executionNotificationIdentityMatches(
        payload: exactPayload,
        ledger: {...ledger, 'state': 'cancelled'},
      ),
      isFalse,
    );
  });

  test('Windows action envelope preserves command and owned task payload', () {
    final payload = LocalNotificationService.ownedPayloadForOwner(
      ownerId: 'owner-1',
      route: 'task/task-1',
      eventType: 'focus_completed',
      boundaryAtUtc: DateTime.utc(2026, 8, 15, 12, 25),
      notificationId: 'notification-1',
      sessionId: 'session-1',
      runtimeRevision: 8,
      intervalId: 'session-1:running:focus',
    );
    final activation = windowsNotificationActionArguments(
      actionId: 'start_break',
      payload: payload,
    );

    final normalized = normalizeNotificationResponse(
      NotificationResponse(
        actionId: activation,
        payload: activation,
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
      ),
    );

    expect(normalized.actionId, 'start_break');
    expect(normalized.payload, payload);
    final decoded = LocalNotificationService.decodeOwnedPayload(
      normalized.payload,
    );
    expect(decoded.taskId, 'task-1');
    expect(decoded.sessionId, 'session-1');
    expect(decoded.runtimeRevision, 8);
  });

  test(
    'Windows body taps open their owned route without inventing a command',
    () {
      final payload = LocalNotificationService.ownedPayloadForOwner(
        ownerId: 'owner-1',
        route: 'task/task-1',
      );

      final normalized = normalizeNotificationResponse(
        NotificationResponse(
          actionId: payload,
          payload: payload,
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
        ),
      );

      expect(normalized.actionId, 'open');
      expect(normalized.payload, payload);
    },
  );

  test('Android response shape remains unchanged by Windows normalization', () {
    const payload = '{"route":"task/task-1"}';
    final normalized = normalizeNotificationResponse(
      const NotificationResponse(
        actionId: 'continue_working',
        payload: payload,
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
      ),
    );

    expect(normalized.actionId, 'continue_working');
    expect(normalized.payload, payload);
  });

  test('Windows execution actions are compact and wait for acceptance', () {
    expect(
      windowsExecutionActionLabelKey('start_break', 'notification_start_break'),
      'notification_action_break_compact',
    );
    expect(
      windowsExecutionActionLabelKey(
        'continue_working',
        'notification_continue_working',
      ),
      'notification_action_continue_compact',
    );
    expect(
      windowsExecutionActionLabelKey('finish_task', 'finish_task'),
      'notification_action_finish_compact',
    );
    for (final action in const <String>[
      'start_break',
      'start_focus',
      'continue_working',
      'finish_task',
      'pause',
      'resume',
    ]) {
      expect(
        windowsExecutionActionBehavior(action),
        WindowsNotificationBehavior.pendingUpdate,
        reason: '$action must not dismiss before canonical acceptance',
      );
    }
    expect(
      windowsExecutionActionBehavior('dismiss'),
      WindowsNotificationBehavior.dismiss,
    );
    expect(
      windowsExecutionActionBehavior('open'),
      WindowsNotificationBehavior.dismiss,
    );

    for (final action in const ['start', 'complete', 'snooze']) {
      expect(
        windowsReminderActionBehavior(action),
        WindowsNotificationBehavior.pendingUpdate,
        reason: '$action must wait for reminder-command acceptance',
      );
    }
    expect(
      windowsReminderActionBehavior('dismiss'),
      WindowsNotificationBehavior.dismiss,
    );
  });

  test('ordinary reminder identity survives the Windows action envelope', () {
    final payload = LocalNotificationService.ownedPayloadForOwner(
      ownerId: 'owner-1',
      route: 'task/task-1',
      reminderId: '8242',
    );
    final activation = windowsNotificationActionArguments(
      actionId: 'complete',
      payload: payload,
    );
    final normalized = normalizeNotificationResponse(
      NotificationResponse(
        actionId: activation,
        payload: activation,
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
      ),
    );

    expect(normalized.actionId, 'complete');
    expect(
      LocalNotificationService.decodeOwnedPayload(
        normalized.payload,
      ).reminderId,
      8242,
    );
  });

  test('a cancelled interval can be replaced by its next schedule', () {
    final cancelled = <String, Object?>{
      'task_id': 'task-1',
      'notification_id': 'old-notification',
      'state': 'cancelled',
    };

    expect(
      executionLedgerTransitionAllowed(
        existing: cancelled,
        requestedState: 'scheduled',
        notificationId: 'new-notification',
      ),
      isTrue,
    );
    expect(
      executionLedgerTransitionAllowed(
        existing: {
          ...cancelled,
          'notification_id': 'new-notification',
          'state': 'scheduled',
        },
        requestedState: 'cancelled',
        notificationId: 'old-notification',
      ),
      isFalse,
    );
  });

  test(
    'running execution cards expose canonical pause and resume controls',
    () {
      final notificationSource = File(
        'lib/core/notifications/notification_sounds.dart',
      ).readAsStringSync();
      final shellSource = File(
        'lib/features/shell/presentation/home_shell.dart',
      ).readAsStringSync();

      expect(notificationSource, contains('showExecutionStatus'));
      expect(notificationSource, contains("('pause', 'pause')"));
      expect(notificationSource, contains("('resume', 'resume')"));
      expect(notificationSource, contains('chronometerCountDown: !paused'));
      expect(shellSource, contains("case 'pause':"));
      expect(shellSource, contains("case 'resume':"));
    },
  );

  test('quiet execution status cannot replace the audible boundary alarm', () {
    final boundary = LocalNotificationService.executionNotificationId('task-1');
    final status = LocalNotificationService.executionStatusNotificationId(
      'task-1',
    );
    final shellSource = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();

    expect(status, isNot(boundary));
    expect(shellSource, contains('executionStatusNotificationId(task.id)'));
  });

  test(
    'standalone Pomodoro boundary is shell-owned and audible off-screen',
    () {
      final notifications = File(
        'lib/core/notifications/notification_sounds.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/features/shell/presentation/home_shell.dart',
      ).readAsStringSync();
      final screen = File(
        'lib/features/tasks/presentation/standalone_pomodoro_screen.dart',
      ).readAsStringSync();

      expect(notifications, contains('scheduleStandalonePomodoroCompletion'));
      expect(notifications, contains("'standalone-pomodoro'"));
      expect(
        notifications,
        contains('AndroidScheduleMode.exactAllowWhileIdle'),
      );
      expect(shell, contains('_standaloneSubscription'));
      expect(shell, contains('_standaloneBoundaryTimer'));
      expect(shell, contains('.advanceIfDue(now: DateTime.now().toUtc())'));
      expect(
        screen,
        isNot(contains('.advanceIfDue(now: DateTime.now().toUtc())')),
        reason: 'closing the timer route must not stop phase advancement',
      );
    },
  );

  test(
    'global active-task pill exposes compact canonical interval actions',
    () {
      final shell = File(
        'lib/features/shell/presentation/home_shell.dart',
      ).readAsStringSync();

      expect(
        shell,
        contains("ValueKey('compact-active-task-primary-control')"),
      );
      expect(shell, contains("ValueKey('compact-active-task-more-controls')"));
      expect(shell, contains('_CompactTimerAction.startBreakEarly'));
      expect(shell, contains('_CompactTimerAction.skipOfferedBreak'));
      expect(shell, contains('_CompactTimerAction.extendBreak'));
      expect(shell, contains('TaskExecutionCommands.skipOfferedBreak('));
      expect(shell, contains('TaskExecutionCommands.extendBreak('));
    },
  );

  test('notification mutations are acknowledged only after local acceptance', () {
    final shellSource = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();

    expect(
      shellSource,
      isNot(
        contains(
          "case 'pause':\n        await localNotificationService.cancelExecutionCompletion",
        ),
      ),
    );
    expect(
      shellSource,
      isNot(
        contains(
          "case 'resume':\n        await localNotificationService.cancelExecutionCompletion",
        ),
      ),
    );
    expect(shellSource, contains('if (requiresExecutionValidation) {'));
    expect(shellSource, contains('if (transitionAccepted) {'));
    expect(
      shellSource,
      contains(
        'transitionAccepted = await TaskExecutionCommands.skipOfferedBreak',
      ),
    );
    expect(shellSource, contains("completedTask?.status == 'completed'"));
    expect(shellSource, contains('after.activeTaskId != task.id'));
    expect(
      shellSource,
      contains('transitionAccepted = await startTaskWithConfirmation('),
    );
    expect(
      shellSource,
      contains("(await repository.getTask(task.id))?.status == 'completed'"),
    );
    expect(shellSource, contains('cancelTaskReminder(ownedPayload)'));
    expect(
      shellSource,
      contains('} else if (retiresReminderPendingAction) {'),
      reason:
          'A declined or raced Windows pendingUpdate action must still retire its reminder toast.',
    );
  });

  test('reminder dismiss cannot cancel a running execution alarm', () {
    final shellSource = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();
    final dismissCase = shellSource.substring(
      shellSource.indexOf("case 'dismiss':"),
      shellSource.indexOf('default:', shellSource.indexOf("case 'dismiss':")),
    );

    expect(dismissCase, contains('ownedPayload.hasExecutionIdentity'));
    expect(
      shellSource,
      contains('ownedPayload.reminderId != null'),
      reason: 'Ordinary dismiss is scoped to its reminder id.',
    );
  });

  test('rejected pending Windows actions retire then restore authority', () {
    final shellSource = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();
    final retirement = shellSource.substring(
      shellSource.indexOf('Future<void> _retireRejectedExecutionNotification('),
      shellSource.indexOf(
        'void _selectDestination(',
        shellSource.indexOf(
          'Future<void> _retireRejectedExecutionNotification(',
        ),
      ),
    );

    expect(retirement, contains("state: 'superseded'"));
    expect(retirement, contains("ledgerState: 'superseded'"));
    expect(retirement, contains('_queueExecutionAlarmSynchronization('));
  });

  test(
    'Android execution commands launch canonical UI and never dismiss early',
    () {
      const mutations = <String>{
        'pause',
        'resume',
        'start_break',
        'start_focus',
        'continue_working',
        'extend_break',
        'finish_task',
      };

      for (final action in mutations) {
        final delivery = executionNotificationActionDelivery(action);
        expect(
          delivery.showsUserInterface,
          isTrue,
          reason: '$action must reach HomeShell canonical command handling',
        );
        expect(
          delivery.cancelNotification,
          isFalse,
          reason: '$action must keep its card until the command is accepted',
        );
      }

      final dismiss = executionNotificationActionDelivery('dismiss');
      expect(dismiss.showsUserInterface, isFalse);
      expect(dismiss.cancelNotification, isTrue);
    },
  );

  test('Android reminder mutations also remain until local acceptance', () {
    for (final action in const ['start', 'complete', 'snooze']) {
      final delivery = reminderNotificationActionDelivery(action);
      expect(delivery.showsUserInterface, isTrue);
      expect(delivery.cancelNotification, isFalse);
    }
    final dismiss = reminderNotificationActionDelivery('dismiss');
    expect(dismiss.showsUserInterface, isFalse);
    expect(dismiss.cancelNotification, isTrue);
  });

  test('cold-start notification actions run before ledger reconciliation', () {
    final shellSource = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();
    final ordered = shellSource.substring(
      shellSource.indexOf(
        'Future<void> _restoreNotificationAuthorityAfterLaunchAction()',
      ),
      shellSource.indexOf(
        'Future<void> _restoreCanonicalNotificationAuthority()',
      ),
    );

    expect(ordered, contains('await _drainNotificationLaunchActions();'));
    expect(
      ordered.indexOf('await _drainNotificationLaunchActions();'),
      lessThan(
        ordered.indexOf('await _restoreCanonicalNotificationAuthority();'),
      ),
    );
  });

  test('Android foreground action PendingIntents preserve the payload', () {
    final nativePlugin = File(
      'third_party/flutter_local_notifications/android/src/main/java/'
      'com/dexterous/flutterlocalnotifications/'
      'FlutterLocalNotificationsPlugin.java',
    ).readAsStringSync();

    expect(nativePlugin, contains('SELECT_FOREGROUND_NOTIFICATION_ACTION'));
    expect(nativePlugin, contains('PendingIntent.getActivity('));
    expect(nativePlugin, contains('.putExtra(ACTION_ID, action.id)'));
    expect(
      nativePlugin,
      contains('.putExtra(PAYLOAD, notificationDetails.payload)'),
    );
    expect(
      nativePlugin,
      contains('channel.invokeMethod("didReceiveNotificationResponse"'),
    );
  });

  test('startup retires obsolete owned execution alarms, not reminders', () {
    final boundary = DateTime.utc(2026, 8, 13, 10, 25);
    final currentExecution = LocalNotificationService.ownedPayloadForOwner(
      ownerId: 'owner-1',
      route: 'task/current-task',
      eventType: 'focus_completed',
      boundaryAtUtc: boundary,
      notificationId: 'notification-current',
      sessionId: 'session-current',
      runtimeRevision: 7,
      intervalId: 'session-current:running:focus',
    );
    final otherOwnerReminder = LocalNotificationService.ownedPayloadForOwner(
      ownerId: 'owner-2',
      route: 'task/other-owner-task',
    );
    final currentOwnerReminder = LocalNotificationService.ownedPayloadForOwner(
      ownerId: 'owner-1',
      route: 'task/reminder-task',
    );

    final obsolete = obsoleteOwnedTaskNotificationIds(
      ownerId: 'owner-1',
      pending: [
        PendingNotificationRequest(1, 'Legacy', null, 'task/legacy-task'),
        PendingNotificationRequest(2, 'Old owner', null, otherOwnerReminder),
        PendingNotificationRequest(3, 'Execution', null, currentExecution),
        PendingNotificationRequest(4, 'Reminder', null, currentOwnerReminder),
        const PendingNotificationRequest(
          5,
          'Wellbeing',
          null,
          'settings/wellbeing',
        ),
      ],
    );

    expect(obsolete, {1, 2, 3, 4});
    expect(isExecutionNotificationTag('execution:id:focus_completed'), isTrue);
    expect(isExecutionNotificationTag('reminder:id:task_reminders'), isFalse);
    expect(isExecutionNotificationTag('wellbeing:sleep'), isFalse);
  });

  test(
    'startup cancels both execution slots from the ledger before superseding',
    () {
      final source = File(
        'lib/core/notifications/notification_sounds.dart',
      ).readAsStringSync();
      final body = source.substring(
        source.indexOf(
          'Future<void> reconcileOwnedTaskNotificationsOnStartup({',
        ),
        source.indexOf(
          'Future<void> cancel(int id)',
          source.indexOf(
            'Future<void> reconcileOwnedTaskNotificationsOnStartup({',
          ),
        ),
      );

      expect(body, contains('for (final taskId in entries.keys)'));
      expect(body, contains('executionNotificationId(taskId)'));
      expect(body, contains('executionStatusNotificationId(taskId)'));
      expect(
        body,
        contains('if (id == _sleepReminderNotificationId) continue'),
      );
      expect(
        body.indexOf('await _plugin.cancel(id: id)'),
        lessThan(body.indexOf("'state': 'superseded'")),
      );
      expect(
        source,
        contains('static const _sleepReminderNotificationId = 820026'),
      );
      expect(body, isNot(contains('cancel(_sleepReminderNotificationId)')));
    },
  );

  test('Android receiver validates execution identity before display', () {
    final receiver = File(
      'third_party/flutter_local_notifications/android/src/main/java/'
      'com/dexterous/flutterlocalnotifications/'
      'ScheduledNotificationReceiver.java',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(receiver, contains('executionIdentityIsCurrent('));
    expect(receiver, contains('event_type'));
    expect(receiver, contains('runtime_revision'));
    expect(receiver, contains('notification_id'));
    expect(receiver, contains('Suppressed stale TaskMaster'));
    expect(
      manifest,
      contains(
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
      ),
    );
    expect(mainActivity, contains('writeExecutionAlarmLedger'));
    expect(mainActivity, contains('taskmaster.execution_alarm_ledger.v0028'));
  });

  test(
    'vendored Windows scheduler replaces tags and contains WinRT errors',
    () {
      final source = File(
        'third_party/flutter_local_notifications_windows/src/ffi_api.cpp',
      ).readAsStringSync();
      final scheduleBody = source.substring(
        source.indexOf('bool scheduleNotification'),
        source.indexOf('NativeUpdateResult updateNotification'),
      );

      expect(scheduleBody, contains('GetScheduledToastNotifications'));
      expect(scheduleBody, contains('RemoveFromSchedule(existing)'));
      expect(
        scheduleBody.indexOf('RemoveFromSchedule(existing)'),
        lessThan(scheduleBody.indexOf('AddToSchedule(notification)')),
      );
      expect(scheduleBody, contains('catch (const winrt::hresult_error&)'));
    },
  );

  test('Android LED styling always includes a complete blink cycle', () {
    final source = File(
      'lib/core/notifications/notification_sounds.dart',
    ).readAsStringSync();

    expect(source, contains('enableLights: true'));
    expect(source, contains('ledColor: accent'));
    expect(source, contains('ledOnMs: 700'));
    expect(source, contains('ledOffMs: 1300'));
  });
}
