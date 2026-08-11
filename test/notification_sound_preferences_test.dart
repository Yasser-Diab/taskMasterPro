import 'dart:io';

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
