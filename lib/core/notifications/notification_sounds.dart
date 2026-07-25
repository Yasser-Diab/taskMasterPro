import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  final AudioPlayer _player = AudioPlayer();

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
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: 'TaskMaster Pro',
        appUserModelId: 'TaskMasterPro.Desktop',
        guid: '1d4219a0-d2e8-4b11-b478-aa8bb9870d9c',
      ),
    );
    await _plugin.initialize(settings: settings);
  }

  Future<void> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> showTest(NotificationSoundChoice sound) async {
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
            AndroidNotificationAction('open', 'Open'),
            AndroidNotificationAction('snooze', 'Snooze'),
          ],
        ),
        windows: const WindowsNotificationDetails(),
      ),
      payload: 'settings/notifications',
    );
  }
}
