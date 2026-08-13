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
    expect(
      shellSource,
      contains('if (requiresExecutionValidation && transitionAccepted)'),
    );
    expect(
      shellSource,
      contains(
        'transitionAccepted = await TaskExecutionCommands.skipOfferedBreak',
      ),
    );
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
