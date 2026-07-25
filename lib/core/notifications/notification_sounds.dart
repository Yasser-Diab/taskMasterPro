import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
void taskMasterNotificationBackgroundResponse(NotificationResponse response) {
  LocalNotificationService.backgroundResponses.add(response);
}

class NotificationSoundChoice {
  const NotificationSoundChoice({
    required this.key,
    required this.label,
    this.assetPath,
    this.androidResource,
  });

  final String key;
  final String label;
  final String? assetPath;
  final String? androidResource;
}

abstract final class NotificationSounds {
  static const choices = [
    NotificationSoundChoice(key: 'system', label: 'System default'),
    NotificationSoundChoice(key: 'silent', label: 'Silent'),
    NotificationSoundChoice(
      key: 'alert',
      label: 'Alert',
      assetPath: 'media/notifications-sound/alert-sound.mp3',
      androidResource: 'alert_sound',
    ),
    NotificationSoundChoice(
      key: 'alarm',
      label: 'App alarm',
      assetPath: 'media/notifications-sound/app-alarm.mp3',
      androidResource: 'app_alarm',
    ),
    NotificationSoundChoice(
      key: 'app_notification',
      label: 'App notification',
      assetPath: 'media/notifications-sound/app-notifications.mp3',
      androidResource: 'app_notifications',
    ),
    NotificationSoundChoice(
      key: 'click',
      label: 'Click',
      assetPath: 'media/notifications-sound/click-sound.mp3',
      androidResource: 'click_sound',
    ),
    NotificationSoundChoice(
      key: 'done',
      label: 'Done',
      assetPath: 'media/notifications-sound/done-sound.mp3',
      androidResource: 'done_sound',
    ),
    NotificationSoundChoice(
      key: 'notification',
      label: 'Notification',
      assetPath: 'media/notifications-sound/notifications.mp3',
      androidResource: 'notifications',
    ),
    NotificationSoundChoice(
      key: 'ui_tone',
      label: 'UI tone',
      assetPath: 'media/notifications-sound/UI-notification-tone.mp3',
      androidResource: 'ui_notification_tone',
    ),
  ];

  static NotificationSoundChoice byKey(String key) {
    return choices.firstWhere(
      (choice) => choice.key == key,
      orElse: () => choices.first,
    );
  }
}

class NotificationSoundPreview {
  final AudioPlayer _player = AudioPlayer()
    ..audioCache = AudioCache(prefix: '');

  Future<void> play(NotificationSoundChoice choice) async {
    if (choice.assetPath == null) {
      await _player.stop();
      return;
    }
    await _player.stop();
    await _player.play(AssetSource(choice.assetPath!));
  }

  Future<void> dispose() => _player.dispose();
}

class LocalNotificationService {
  static const _nativeChannel = MethodChannel('taskmasterpro/notifications');
  static final backgroundResponses =
      StreamController<NotificationResponse>.broadcast();
  static final responses = StreamController<NotificationResponse>.broadcast();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  NotificationResponse? _launchResponse;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: 'TaskMaster Pro',
        appUserModelId: 'TaskMasterPro.Desktop',
        guid: '1d4219a0-d2e8-4b11-b478-aa8bb9870d9c',
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: responses.add,
      onDidReceiveBackgroundNotificationResponse:
          taskMasterNotificationBackgroundResponse,
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _launchResponse = launchDetails?.notificationResponse;
    }
    _initialized = true;
  }

  NotificationResponse? takeLaunchResponse() {
    final response = _launchResponse;
    _launchResponse = null;
    return response;
  }

  Future<void> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> openAndroidSystemSoundSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await initialize();
    const channel = AndroidNotificationChannel(
      'taskmaster_system',
      'TaskMaster Pro — System default',
      description: 'Task reminders using a sound selected on this device',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await _nativeChannel.invokeMethod<void>('openNotificationChannelSettings', {
      'channelId': channel.id,
    });
  }

  Future<void> showTest(NotificationSoundChoice sound) async {
    await initialize();
    final androidSound = sound.androidResource == null
        ? null
        : RawResourceAndroidNotificationSound(sound.androidResource!);
    await _plugin.show(
      id: 9001,
      title: 'TaskMaster Pro',
      body: 'Notifications continue to work offline.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'taskmaster_${sound.key}',
          'TaskMaster Pro — ${sound.label}',
          channelDescription: 'Task and execution reminders',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: androidSound,
          actions: const [
            AndroidNotificationAction('open', 'Open', showsUserInterface: true),
            AndroidNotificationAction(
              'snooze',
              'Snooze',
              showsUserInterface: true,
            ),
          ],
        ),
        windows: const WindowsNotificationDetails(),
      ),
      payload: 'settings/notifications',
    );
  }

  Future<void> scheduleTaskReminder({
    required int id,
    required String taskId,
    required String taskTitle,
    required String reminderType,
    required DateTime scheduledAtUtc,
    required NotificationSoundChoice sound,
  }) async {
    await initialize();
    final androidSound = sound.androidResource == null
        ? null
        : RawResourceAndroidNotificationSound(sound.androidResource!);
    await _plugin.zonedSchedule(
      id: id,
      title: taskTitle,
      body: _bodyFor(reminderType),
      scheduledDate: tz.TZDateTime.from(scheduledAtUtc.toUtc(), tz.UTC),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'taskmaster_${sound.key}',
          'TaskMaster Pro — ${sound.label}',
          channelDescription: 'Task reminders and execution events',
          importance: Importance.high,
          priority: Priority.high,
          playSound: sound.key != 'silent',
          sound: androidSound,
          actions: const [
            AndroidNotificationAction(
              'start',
              'Start',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'complete',
              'Complete',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'snooze',
              'Snooze',
              showsUserInterface: true,
            ),
          ],
        ),
        windows: const WindowsNotificationDetails(),
      ),
      payload: 'task/$taskId',
    );
  }

  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }

  String _bodyFor(String type) {
    return switch (type) {
      'before_start' => 'Prepare now so you can begin on time',
      'start' => 'Your planned start time has arrived',
      'planned_end' =>
        'Review progress and decide whether to finish or continue',
      'due' => 'This task is due',
      'overdue' => 'This task is overdue and needs a decision',
      'missed' => 'This task was not started as planned',
      _ => 'Open TaskMaster Pro to review this task',
    };
  }
}

final localNotificationService = LocalNotificationService();
