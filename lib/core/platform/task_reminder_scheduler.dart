import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/tasks/domain/task_item.dart';
import '../../features/tasks/domain/task_support_models.dart';

class NotificationPlatformStatus {
  const NotificationPlatformStatus({
    required this.notificationsAllowed,
    required this.exactSchedulingAvailable,
    required this.activeTimerRunning,
    this.channelId,
    this.selectedSound,
    this.soundAssetExists,
    this.channelSoundEnabled,
    this.alarmVolume,
    this.vibrationEnabled,
    this.lastNotificationResult,
    this.lastNotificationAt,
    this.nextScheduledAt,
  });

  final bool notificationsAllowed;
  final bool exactSchedulingAvailable;
  final bool activeTimerRunning;
  final String? channelId;
  final String? selectedSound;
  final bool? soundAssetExists;
  final bool? channelSoundEnabled;
  final int? alarmVolume;
  final bool? vibrationEnabled;
  final String? lastNotificationResult;
  final DateTime? lastNotificationAt;
  final DateTime? nextScheduledAt;

  factory NotificationPlatformStatus.fromMap(Map<Object?, Object?> map) {
    DateTime? date(String key) => DateTime.tryParse(map[key]?.toString() ?? '');
    return NotificationPlatformStatus(
      notificationsAllowed: map['notificationsAllowed'] == true,
      exactSchedulingAvailable: map['exactSchedulingAvailable'] == true,
      activeTimerRunning: map['activeTimerRunning'] == true,
      channelId: map['channelId']?.toString(),
      selectedSound: map['selectedSound']?.toString(),
      soundAssetExists: map['soundAssetExists'] as bool?,
      channelSoundEnabled: map['channelSoundEnabled'] as bool?,
      alarmVolume: (map['alarmVolume'] as num?)?.round(),
      vibrationEnabled: map['vibrationEnabled'] as bool?,
      lastNotificationResult: map['lastNotificationResult']?.toString(),
      lastNotificationAt: date('lastNotificationAt'),
      nextScheduledAt: date('nextScheduledAt'),
    );
  }
}

class TaskReminderScheduler {
  const TaskReminderScheduler();

  static const MethodChannel _channel = MethodChannel(
    'taskmasterpro/task_reminders',
  );

  Future<void> scheduleForTask(
    TaskItem task,
    List<TaskReminder> reminders,
  ) async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      return;
    }
    await cancelTask(task.id);
    final anchor = task.effectiveStartUtc ?? task.effectiveDueUtc;
    for (final reminder in reminders) {
      final trigger =
          reminder.snoozedUntil ??
          reminder.customTriggerAt ??
          anchor?.subtract(Duration(minutes: reminder.offsetMinutes ?? 0));
      if (trigger == null || !trigger.isAfter(DateTime.now())) {
        continue;
      }
      try {
        await _channel.invokeMethod<void>('schedule', {
          'id': reminder.notificationId ?? reminder.id,
          'taskId': task.id,
          'title': task.title,
          'body': _bodyFor(task, reminder),
          'triggerAt': trigger.millisecondsSinceEpoch,
          'priority': task.priority.storageValue,
          'isAdaptive': reminder.isAdaptive,
          'reason': reminder.reason,
        });
      } on MissingPluginException {
        return;
      } on PlatformException {
        // Persisted reminder rows remain authoritative and are retried on the
        // next synchronization or application start.
      }
    }
  }

  Future<void> cancelTask(String taskId) async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancelTask', {'taskId': taskId});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<NotificationPlatformStatus?> status() async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getStatus',
      );
      return result == null ? null : NotificationPlatformStatus.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> sendTestNotification({
    required String title,
    required String body,
    String channel = 'task_reminders',
  }) async {
    await showImmediate(title: title, body: body, channel: channel);
  }

  Future<void> showImmediate({
    required String title,
    required String body,
    String channel = 'task_reminders',
    String taskId = 'system',
    String? id,
  }) async {
    if (!Platform.isWindows && !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('showNow', {
        'id': id ?? 'now_${DateTime.now().millisecondsSinceEpoch}',
        'taskId': taskId,
        'title': title,
        'body': body,
        'channel': channel,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<bool> openSystemNotificationSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  String _bodyFor(TaskItem task, TaskReminder reminder) {
    if (reminder.isAdaptive && reminder.reason?.trim().isNotEmpty == true) {
      return reminder.reason!.trim();
    }
    return switch (task.taskType) {
      TaskType.event => 'This event is coming up.',
      TaskType.habit => 'Your habit is ready to complete.',
      TaskType.timed => 'Your scheduled task is ready to start.',
      TaskType.reading => 'Your reading session is ready to start.',
      TaskType.manual => 'This task is ready.',
      TaskType.focus => 'Your focus task is ready to start.',
    };
  }
}
