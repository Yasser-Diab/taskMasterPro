import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final receiver = File(
    'third_party/flutter_local_notifications/android/src/main/java/'
    'com/dexterous/flutterlocalnotifications/'
    'ScheduledNotificationReceiver.java',
  ).readAsStringSync();

  test('only a grossly overdue owned sleep reminder is suppressed', () {
    expect(receiver, contains('TASKMASTER_SLEEP_REMINDER_ID = 820026'));
    expect(receiver, contains('TimeUnit.HOURS.toMillis(2)'));
    expect(
      receiver,
      contains('notificationDetails.id != TASKMASTER_SLEEP_REMINDER_ID'),
    );
    expect(
      receiver,
      contains('"settings/wellbeing".equals(payload.optString("route"))'),
    );
    expect(
      receiver,
      contains('LocalDateTime.parse(notificationDetails.scheduledDateTime)'),
    );
    expect(receiver, contains('ZoneId.of(notificationDetails.timeZoneName)'));
    expect(
      receiver,
      contains(
        'System.currentTimeMillis() - scheduledAtMillis\n'
        '          > TASKMASTER_SLEEP_MAX_OVERDUE_MILLIS',
      ),
    );
  });

  test('overdue sleep delivery advances recurrence without showing it', () {
    final guard = receiver.indexOf(
      'if (taskMasterSleepReminderIsGrosslyOverdue(notificationDetails))',
    );
    final advance = receiver.indexOf(
      'FlutterLocalNotificationsPlugin.scheduleNextNotification('
      'context, notificationDetails)',
      guard,
    );
    final guardReturn = receiver.indexOf('return;', advance);
    final ordinaryShow = receiver.indexOf(
      'FlutterLocalNotificationsPlugin.showNotification('
      'context, notificationDetails)',
      guardReturn,
    );

    expect(guard, greaterThanOrEqualTo(0));
    expect(advance, greaterThan(guard));
    expect(guardReturn, greaterThan(advance));
    expect(ordinaryShow, greaterThan(guardReturn));
  });
}
