import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color, DartPluginRegistrant, Locale;

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../localization/app_localizations.dart';

@pragma('vm:entry-point')
void taskMasterNotificationBackgroundResponse(
  NotificationResponse response,
) async {
  // This callback is invoked in a background isolate. A StreamController in
  // that isolate is not the one listened to by the foreground application, so
  // actions used to disappear when Android had to launch TaskMaster Pro. Keep
  // the small, non-sensitive action envelope until HomeShell is ready.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await LocalNotificationService.storeBackgroundResponse(response);
}

class StoredNotificationResponse {
  const StoredNotificationResponse({
    required this.payload,
    required this.actionId,
  });

  final String? payload;
  final String? actionId;
}

const _windowsActionEnvelopeVersion = 1;

/// Windows toast activation returns the action `arguments` as both the
/// response payload and action id.  Keep the canonical notification payload in
/// those arguments so a button can identify both the command and the exact
/// task/runtime interval it was rendered for.
@visibleForTesting
String windowsNotificationActionArguments({
  required String actionId,
  required String payload,
}) => jsonEncode(<String, Object?>{
  'taskmaster_action_version': _windowsActionEnvelopeVersion,
  'action_id': actionId,
  'payload': payload,
});

/// Normalizes the platform-specific response shape before any route or
/// execution-ledger validation runs.
///
/// Android already supplies `payload` and `actionId` separately. The vendored
/// Windows plugin receives only the toast activation arguments, so TaskMaster
/// actions use [windowsNotificationActionArguments] to carry both values.
StoredNotificationResponse normalizeNotificationResponse(
  NotificationResponse response,
) {
  final activation = response.actionId;
  if (activation != null && activation.isNotEmpty) {
    try {
      final decoded = jsonDecode(activation);
      if (decoded is Map &&
          decoded['taskmaster_action_version'] ==
              _windowsActionEnvelopeVersion &&
          decoded['action_id'] is String &&
          decoded['payload'] is String) {
        return StoredNotificationResponse(
          payload: decoded['payload'] as String,
          actionId: decoded['action_id'] as String,
        );
      }

      // The Windows implementation reports a click on the toast body as an
      // action whose arguments are the original JSON payload. Treat that as
      // Open, never as an unknown mutating action.
      if (decoded is Map && decoded['route'] is String) {
        return StoredNotificationResponse(
          payload: activation,
          actionId: 'open',
        );
      }
    } catch (_) {
      // Android action ids and legacy plain routes are intentionally not JSON.
    }
  }
  return StoredNotificationResponse(
    payload: response.payload,
    actionId: response.actionId,
  );
}

/// Windows allocates very little horizontal space to toast actions. Keep the
/// command ids unchanged while using labels which remain readable at normal
/// and large text scales.
@visibleForTesting
String windowsExecutionActionLabelKey(String actionId, String fallbackKey) {
  return switch (actionId) {
    'start_break' => 'notification_action_break_compact',
    'start_focus' ||
    'continue_working' => 'notification_action_continue_compact',
    'finish_task' => 'notification_action_finish_compact',
    _ => fallbackKey,
  };
}

/// A mutating Windows toast must remain pending until TaskMaster has applied
/// the revision-guarded runtime command. Open/Dismiss actions may close
/// immediately because they do not change canonical task state.
@visibleForTesting
WindowsNotificationBehavior windowsExecutionActionBehavior(String actionId) {
  return const {
        'pause',
        'resume',
        'start_break',
        'start_focus',
        'continue_working',
        'extend_break',
        'finish_task',
      }.contains(actionId)
      ? WindowsNotificationBehavior.pendingUpdate
      : WindowsNotificationBehavior.dismiss;
}

/// Task-reminder mutations need the same acknowledgement contract as timer
/// actions on Windows. A toast remains visible (with Windows' pending state)
/// until HomeShell confirms that Start/Complete/Snooze reached local canonical
/// state. Open and Dismiss are navigation-only/explicit-retirement actions.
@visibleForTesting
WindowsNotificationBehavior windowsReminderActionBehavior(String actionId) {
  return const {'start', 'complete', 'snooze'}.contains(actionId)
      ? WindowsNotificationBehavior.pendingUpdate
      : WindowsNotificationBehavior.dismiss;
}

class OwnedNotificationPayload {
  const OwnedNotificationPayload({
    required this.route,
    required this.ownerId,
    this.eventType,
    this.boundaryAtUtc,
    this.notificationId,
    this.sessionId,
    this.runtimeRevision,
    this.intervalId,
    this.reminderId,
  });

  final String route;
  final String? ownerId;
  final String? eventType;
  final DateTime? boundaryAtUtc;
  final String? notificationId;
  final String? sessionId;
  final int? runtimeRevision;
  final String? intervalId;
  final int? reminderId;

  String? get taskId =>
      route.startsWith('task/') ? route.substring('task/'.length).trim() : null;

  bool get hasExecutionIdentity =>
      notificationId != null &&
      notificationId!.isNotEmpty &&
      sessionId != null &&
      sessionId!.isNotEmpty &&
      runtimeRevision != null &&
      intervalId != null &&
      intervalId!.isNotEmpty;
}

/// The per-device notification ledger is deliberately strict.  An Android
/// alarm can arrive after an OS cancellation race, but it cannot perform a
/// task transition unless it still represents the exact active interval that
/// this device scheduled.
@visibleForTesting
bool executionNotificationIdentityMatches({
  required OwnedNotificationPayload payload,
  required Map<String, Object?> ledger,
}) {
  final taskId = payload.taskId;
  if (taskId == null || taskId.isEmpty || !payload.hasExecutionIdentity) {
    return false;
  }
  return ledger['state'] is String &&
      const {'scheduled', 'delivered'}.contains(ledger['state']) &&
      ledger['task_id'] == taskId &&
      ledger['notification_id'] == payload.notificationId &&
      ledger['session_id'] == payload.sessionId &&
      (ledger['runtime_revision'] as num?)?.toInt() ==
          payload.runtimeRevision &&
      ledger['interval_id'] == payload.intervalId &&
      ledger['boundary_at'] == payload.boundaryAtUtc?.toUtc().toIso8601String();
}

/// Protects the single execution-notification slot from delayed actions while
/// still allowing the scheduler to replace an interval it just cancelled.
///
/// A cancellation without an identity deliberately retains the old identity
/// in the ledger.  The next canonical schedule therefore has a different ID
/// and must be allowed to take ownership when that old row is terminal.
bool executionLedgerTransitionAllowed({
  required Map<String, Object?>? existing,
  required String requestedState,
  required String? notificationId,
}) {
  if (existing == null || notificationId == null) return true;
  if (existing['notification_id'] == notificationId) return true;
  return requestedState == 'scheduled' &&
      const {
        'cancelled',
        'superseded',
        'expired',
        'handled',
      }.contains(existing['state']);
}

/// Android must route every execution-changing action through the foreground
/// application isolate. The background notification isolate has no account
/// database or canonical runtime repository; letting it own Pause/Resume/etc.
/// would only dismiss a card while leaving the task unchanged.
///
/// Keep the card until the canonical transition succeeds. HomeShell's runtime
/// observer then cancels or replaces it with the card for the accepted
/// revision. Only an explicit non-mutating dismiss is allowed to remove the
/// notification directly.
class AndroidNotificationActionDelivery {
  const AndroidNotificationActionDelivery({
    required this.showsUserInterface,
    required this.cancelNotification,
  });

  final bool showsUserInterface;
  final bool cancelNotification;
}

@visibleForTesting
AndroidNotificationActionDelivery reminderNotificationActionDelivery(
  String actionId,
) {
  final mutatesReminder = const {
    'start',
    'complete',
    'snooze',
  }.contains(actionId);
  return AndroidNotificationActionDelivery(
    showsUserInterface: mutatesReminder,
    cancelNotification: !mutatesReminder,
  );
}

@visibleForTesting
AndroidNotificationActionDelivery executionNotificationActionDelivery(
  String actionId,
) {
  final dismissesOnly = actionId == 'dismiss';
  return AndroidNotificationActionDelivery(
    showsUserInterface: !dismissesOnly,
    cancelNotification: dismissesOnly,
  );
}

@visibleForTesting
bool isExecutionNotificationTag(String? tag) {
  if (tag == null || !tag.startsWith('execution:')) return false;
  final category = tag.split(':').last;
  return const {
    'focus_completed',
    'short_break_completed',
    'long_break_completed',
    'task_reminders',
  }.contains(category);
}

/// Selects only TaskMaster task notifications which cannot belong to the
/// current canonical account/session after startup.
///
/// Every task alarm is rebuilt from canonical local records/runtime
/// immediately after this repair. Legacy plain `task/...` payloads cannot
/// prove an owner or revision, so they are retired rather than allowed to
/// mutate current work.
@visibleForTesting
Set<int> obsoleteOwnedTaskNotificationIds({
  required String ownerId,
  required Iterable<PendingNotificationRequest> pending,
}) {
  final obsolete = <int>{};
  for (final request in pending) {
    final payload = LocalNotificationService.decodeOwnedPayload(
      request.payload,
    );
    if (payload.taskId == null) continue;
    obsolete.add(request.id);
  }
  return obsolete;
}

class NotificationSoundChoice {
  const NotificationSoundChoice({
    required this.key,
    this.assetPath,
    this.androidResource,
    this.deviceUri,
    this.deviceKind,
    this.deviceLabel,
  });

  final String key;
  final String? assetPath;
  final String? androidResource;
  final String? deviceUri;
  final String? deviceKind;
  final String? deviceLabel;

  bool get isDeviceSound => deviceUri != null;

  String get channelKey {
    if (deviceUri == null) return key.replaceAll(RegExp('[^a-z0-9_]'), '_');
    // AudioAttributesUsage is immutable once Android creates a notification
    // channel. The same MediaStore URI can be chosen from the notification,
    // alarm, or ringtone picker, so the kind must participate in the identity.
    final identity = '${deviceKind ?? 'notification'}:$deviceUri';
    return 'device_${sha256.convert(utf8.encode(identity)).toString().substring(0, 16)}';
  }
}

abstract final class NotificationSounds {
  static const _devicePrefix = 'device:';
  static const categories = <String>[
    'task_reminders',
    'scheduled_starts',
    'overdue_tasks',
    'focus_completed',
    'short_break_completed',
    'long_break_completed',
    'roadmaps',
    'activity_review',
    'coaching',
    'sleep_health',
    'synchronization',
    'security',
  ];

  static const choices = [
    NotificationSoundChoice(key: 'system'),
    NotificationSoundChoice(key: 'silent'),
    NotificationSoundChoice(
      key: 'alert',
      assetPath: 'media/notifications-sound/alert-sound.mp3',
      androidResource: 'alert_sound',
    ),
    NotificationSoundChoice(
      key: 'alarm',
      assetPath: 'media/notifications-sound/app-alarm.mp3',
      androidResource: 'app_alarm',
    ),
    NotificationSoundChoice(
      key: 'app_notification',
      assetPath: 'media/notifications-sound/app-notifications.mp3',
      androidResource: 'app_notifications',
    ),
    NotificationSoundChoice(
      key: 'click',
      assetPath: 'media/notifications-sound/click-sound.mp3',
      androidResource: 'click_sound',
    ),
    NotificationSoundChoice(
      key: 'done',
      assetPath: 'media/notifications-sound/done-sound.mp3',
      androidResource: 'done_sound',
    ),
    NotificationSoundChoice(
      key: 'notification',
      assetPath: 'media/notifications-sound/notifications.mp3',
      androidResource: 'notifications',
    ),
    NotificationSoundChoice(
      key: 'ui_tone',
      assetPath: 'media/notifications-sound/UI-notification-tone.mp3',
      androidResource: 'ui_notification_tone',
    ),
  ];

  static NotificationSoundChoice byKey(String key) {
    final device = _decodeDeviceChoice(key);
    if (device != null) return device;
    return choices.firstWhere(
      (choice) => choice.key == key,
      orElse: () => choices.first,
    );
  }

  static NotificationSoundChoice device({
    required String uri,
    required String kind,
    required String label,
  }) {
    final encoded = base64Url.encode(
      utf8.encode(jsonEncode({'uri': uri, 'kind': kind, 'label': label})),
    );
    return NotificationSoundChoice(
      key: '$_devicePrefix$encoded',
      deviceUri: uri,
      deviceKind: kind,
      deviceLabel: label,
    );
  }

  static NotificationSoundChoice? _decodeDeviceChoice(String key) {
    if (!key.startsWith(_devicePrefix)) return null;
    try {
      final raw = key.substring(_devicePrefix.length);
      final data = Map<String, Object?>.from(
        jsonDecode(utf8.decode(base64Url.decode(raw))) as Map,
      );
      final uri = data['uri'] as String?;
      final kind = data['kind'] as String?;
      final label = data['label'] as String?;
      if (uri == null || kind == null || label == null) return null;
      return NotificationSoundChoice(
        key: key,
        deviceUri: uri,
        deviceKind: kind,
        deviceLabel: label,
      );
    } catch (_) {
      return null;
    }
  }

  static String legacyCategory(String category) => switch (category) {
    'task_reminders' || 'scheduled_starts' || 'overdue_tasks' => 'tasks',
    'focus_completed' => 'focus',
    'short_break_completed' || 'long_break_completed' => 'breaks',
    'activity_review' => 'activity',
    'sleep_health' => 'health',
    'synchronization' => 'sync',
    _ => category,
  };

  static String canonicalCategory(String category) => switch (category) {
    'tasks' => 'task_reminders',
    'focus' => 'focus_completed',
    'breaks' => 'short_break_completed',
    'activity' => 'activity_review',
    'health' => 'sleep_health',
    'sync' => 'synchronization',
    _ => category,
  };

  static String categoryForReminderType(String reminderType) {
    return switch (reminderType) {
      'before_start' || 'start' => 'scheduled_starts',
      'overdue' || 'missed' => 'overdue_tasks',
      _ => 'task_reminders',
    };
  }

  static Map<String, Object?> preferences(String encoded) {
    try {
      return Map<String, Object?>.from(jsonDecode(encoded) as Map);
    } catch (_) {
      return const {};
    }
  }

  static bool categoryEnabled({
    required String preferencesJson,
    required String category,
  }) {
    final values = preferences(preferencesJson);
    final canonical = canonicalCategory(category);
    return values[canonical] as bool? ??
        values[category] as bool? ??
        values[legacyCategory(canonical)] as bool? ??
        true;
  }

  static bool vibrationForCategory({
    required String preferencesJson,
    required String category,
  }) {
    final values = preferences(preferencesJson);
    final canonical = canonicalCategory(category);
    return values['${canonical}_vibration'] as bool? ??
        values['${category}_vibration'] as bool? ??
        values['${legacyCategory(canonical)}_vibration'] as bool? ??
        values['vibration'] as bool? ??
        true;
  }

  /// Category choices live in the synchronized notification-preferences
  /// document so changing, for example, the focus alarm never changes a task
  /// reminder or a sleep reminder.  Older accounts simply use the existing
  /// global choice until the user picks a category-specific one.
  static NotificationSoundChoice forCategory({
    required String preferencesJson,
    required String category,
    required String fallbackKey,
  }) {
    try {
      final preferences = NotificationSounds.preferences(preferencesJson);
      final canonical = canonicalCategory(category);
      final selected =
          preferences['${canonical}_sound'] as String? ??
          preferences['${category}_sound'] as String? ??
          preferences['${legacyCategory(canonical)}_sound'] as String?;
      return byKey(selected ?? fallbackKey);
    } catch (_) {
      return byKey(fallbackKey);
    }
  }
}

class NotificationSoundPreview {
  static const _nativeChannel = MethodChannel('taskmasterpro/notifications');
  final AudioPlayer _player = AudioPlayer()
    ..audioCache = AudioCache(prefix: '');

  Future<void> play(NotificationSoundChoice choice) async {
    if (choice.deviceUri != null) {
      await _player.stop();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _nativeChannel.invokeMethod<void>('previewSystemSound', {
          'uri': choice.deviceUri,
        });
      }
      return;
    }
    if (choice.key == 'system') {
      await _player.stop();
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _nativeChannel.invokeMethod<void>('previewDefaultSound', {
          'type': 'notification',
        });
      }
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _nativeChannel.invokeMethod<void>('stopSoundPreview');
    }
    if (choice.assetPath == null) {
      await _player.stop();
      return;
    }
    await _player.stop();
    await _player.play(AssetSource(choice.assetPath!));
  }

  Future<void> stop() async {
    await _player.stop();
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _nativeChannel.invokeMethod<void>('stopSoundPreview');
    }
  }

  Future<void> dispose() => _player.dispose();
}

class NotificationSoundVerification {
  const NotificationSoundVerification({
    required this.matches,
    required this.channelId,
    this.actualUri,
  });

  final bool matches;
  final String channelId;
  final String? actualUri;
}

abstract final class NotificationSchedulePolicy {
  static const minimumLeadTime = Duration(seconds: 2);
  static const windowsRepairPreferenceKey =
      'taskmaster.windows_notification_schedule_repair.v0026.2';
  static const maxTaskReminders = 64;

  static bool canSchedule(DateTime scheduledAtUtc, {DateTime? nowUtc}) {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    return scheduledAtUtc.toUtc().isAfter(
      now.add(NotificationSchedulePolicy.minimumLeadTime),
    );
  }
}

class LocalNotificationService {
  static const _nativeChannel = MethodChannel('taskmasterpro/notifications');
  static const _backgroundResponseStore =
      'taskmaster.notification.background_actions.v1';
  static const _executionLedgerStore =
      'taskmaster.notification.execution_ledger.v0028';
  static const _executionPermissionPromptedStore =
      'taskmaster.notification.execution_permission_prompted.v0028';
  static final backgroundResponses =
      StreamController<NotificationResponse>.broadcast();
  static final responses = StreamController<NotificationResponse>.broadcast();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initializing;
  Future<void> _notificationMutationQueue = Future<void>.value();
  NotificationResponse? _launchResponse;

  static int executionNotificationId(String taskId) =>
      'execution:$taskId'.hashCode & 0x7fffffff;
  static const standalonePomodoroNotificationId = 820028;

  /// The quiet, ongoing execution card must never reuse the exact alarm ID.
  /// `FlutterLocalNotificationsPlugin.show` replaces a pending schedule with
  /// the same ID on both Android and Windows.  Keeping the live status in a
  /// separate slot means browsing inside TaskMaster cannot silently erase the
  /// audible focus/break boundary.
  static int executionStatusNotificationId(String taskId) =>
      executionNotificationId(taskId) ^ 0x40000000;

  /// A plugin notification ID can be reused to replace an OS alarm. This
  /// identity cannot: it names the exact interval/revision represented by
  /// that alarm and is persisted with the per-device ledger.
  static String executionNotificationIdentity({
    required String taskId,
    required String sessionId,
    required int runtimeRevision,
    required String intervalId,
    required DateTime boundaryAtUtc,
  }) =>
      'execution:$taskId:$sessionId:$runtimeRevision:$intervalId:'
      '${boundaryAtUtc.toUtc().toIso8601String()}';

  WindowsNotificationAudio _windowsAudio(NotificationSoundChoice sound) {
    if (sound.key == 'silent') {
      return WindowsNotificationAudio.silent();
    }
    final preset = switch (sound.key) {
      'alert' || 'done' => WindowsNotificationSound.reminder,
      'alarm' => WindowsNotificationSound.alarm1,
      'app_notification' => WindowsNotificationSound.mail,
      'click' => WindowsNotificationSound.im,
      'notification' || 'ui_tone' => WindowsNotificationSound.sms,
      _ => WindowsNotificationSound.defaultSound,
    };
    return WindowsNotificationAudio.preset(sound: preset);
  }

  AndroidNotificationSound? _androidSound(NotificationSoundChoice sound) {
    if (sound.deviceUri != null) {
      return UriAndroidNotificationSound(sound.deviceUri!);
    }
    if (sound.androidResource != null) {
      return RawResourceAndroidNotificationSound(sound.androidResource!);
    }
    return null;
  }

  AudioAttributesUsage _androidAudioUsage(NotificationSoundChoice sound) {
    return switch (sound.deviceKind) {
      'alarm' => AudioAttributesUsage.alarm,
      'ringtone' => AudioAttributesUsage.notificationRingtone,
      _ => AudioAttributesUsage.notification,
    };
  }

  String _channelId({
    required String category,
    required NotificationSoundChoice sound,
    required bool vibration,
  }) {
    final canonicalCategory = NotificationSounds.canonicalCategory(category);
    final safeCategory = canonicalCategory.toLowerCase().replaceAll(
      RegExp('[^a-z0-9_]'),
      '_',
    );
    final importance = _notificationImportance(canonicalCategory);
    // Version the channel contract because Android channel sound, vibration,
    // audio usage, and importance cannot be updated after first creation.
    return 'taskmaster_v2_${safeCategory}_${sound.channelKey}'
        '_v${vibration ? 1 : 0}_i${importance.value}';
  }

  String _channelName(AppLocalizations l10n, String category) {
    final canonicalCategory = NotificationSounds.canonicalCategory(category);
    final key = 'notification_category_$canonicalCategory';
    final value = l10n.text(key);
    return value == key ? 'TaskMaster Pro' : 'TaskMaster Pro — $value';
  }

  String _channelDescription(AppLocalizations l10n, String category) {
    final canonicalCategory = NotificationSounds.canonicalCategory(category);
    final key = 'notification_category_${canonicalCategory}_description';
    final value = l10n.text(key);
    return value == key ? _channelName(l10n, canonicalCategory) : value;
  }

  AndroidNotificationDetails _androidDetails({
    required AppLocalizations l10n,
    required String category,
    required NotificationSoundChoice sound,
    required bool vibration,
    String? title,
    String? body,
    String? notificationTag,
    List<AndroidNotificationAction>? actions,
    bool ongoing = false,
    bool autoCancel = true,
    bool onlyAlertOnce = false,
    int? when,
    bool usesChronometer = false,
    bool chronometerCountDown = false,
  }) {
    final canonicalCategory = NotificationSounds.canonicalCategory(category);
    final silent = sound.key == 'silent';
    final accent = _notificationAccent(canonicalCategory);
    return AndroidNotificationDetails(
      _channelId(
        category: canonicalCategory,
        sound: sound,
        vibration: vibration,
      ),
      _channelName(l10n, canonicalCategory),
      channelDescription: _channelDescription(l10n, canonicalCategory),
      icon: 'ic_notification',
      importance: _notificationImportance(canonicalCategory),
      priority: _notificationPriority(canonicalCategory),
      styleInformation: body == null
          ? null
          : BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: _channelName(l10n, canonicalCategory),
            ),
      playSound: !silent,
      silent: silent && !vibration,
      sound: _androidSound(sound),
      enableVibration: vibration,
      audioAttributesUsage: _androidAudioUsage(sound),
      color: accent,
      enableLights: true,
      ledColor: accent,
      ledOnMs: 700,
      ledOffMs: 1300,
      visibility: NotificationVisibility.private,
      category: _androidNotificationCategory(canonicalCategory),
      groupKey: 'taskmaster_$canonicalCategory',
      groupAlertBehavior: GroupAlertBehavior.all,
      ongoing: ongoing,
      autoCancel: autoCancel,
      onlyAlertOnce: onlyAlertOnce,
      when: when,
      usesChronometer: usesChronometer,
      chronometerCountDown: chronometerCountDown,
      ticker: title,
      subText: _channelName(l10n, canonicalCategory),
      tag: notificationTag,
      actions: actions,
    );
  }

  Future<void> showExecutionStatus({
    required int id,
    required String taskId,
    required String taskTitle,
    required String state,
    required DateTime boundaryAtUtc,
    required NotificationSoundChoice sound,
    required String sessionId,
    required int runtimeRevision,
    required String intervalId,
    required String eventType,
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    await initialize();
    final l10n = AppLocalizations(Locale(localeCode));
    final paused = state == 'paused';
    final onBreak = state == 'break';
    final notificationCategory = eventType == 'focus_completed'
        ? 'focus_completed'
        : eventType == 'long_break_completed'
        ? 'long_break_completed'
        : eventType == 'short_break_completed' || eventType == 'break_completed'
        ? 'short_break_completed'
        : 'task_reminders';
    final stateLabel = onBreak
        ? l10n.text('break_in_progress')
        : paused
        ? l10n.text('status_paused')
        : l10n.text('status_running');
    final body = onBreak
        ? '$stateLabel · ${l10n.text('notification_start_focus')}'
        : stateLabel;
    final actions = onBreak
        ? const <(String, String)>[
            ('start_focus', 'notification_start_focus'),
            ('extend_break', 'notification_extend_break'),
            ('finish_task', 'finish_task'),
            ('open', 'open'),
          ]
        : paused
        ? const <(String, String)>[
            ('resume', 'resume'),
            ('finish_task', 'finish_task'),
            ('open', 'open'),
          ]
        : const <(String, String)>[
            ('pause', 'pause'),
            ('finish_task', 'finish_task'),
            ('open', 'open'),
          ];
    final notificationIdentity = executionNotificationIdentity(
      taskId: taskId,
      sessionId: sessionId,
      runtimeRevision: runtimeRevision,
      intervalId: intervalId,
      boundaryAtUtc: boundaryAtUtc,
    );
    final payload = ownedPayload(
      'task/$taskId',
      eventType: eventType,
      boundaryAtUtc: boundaryAtUtc,
      notificationId: notificationIdentity,
      sessionId: sessionId,
      runtimeRevision: runtimeRevision,
      intervalId: intervalId,
    );
    await _serializeNotificationMutation(() async {
      await _plugin.show(
        id: id,
        title: taskTitle,
        body: body,
        notificationDetails: NotificationDetails(
          android: _androidDetails(
            l10n: l10n,
            category: 'task_reminders',
            sound: const NotificationSoundChoice(key: 'silent'),
            vibration: false,
            title: taskTitle,
            body: body,
            notificationTag: 'execution:$taskId:$notificationCategory',
            ongoing: !paused,
            autoCancel: false,
            onlyAlertOnce: true,
            when: boundaryAtUtc.millisecondsSinceEpoch,
            usesChronometer: !paused,
            chronometerCountDown: !paused,
            actions: [
              for (final action in actions)
                AndroidNotificationAction(
                  action.$1,
                  l10n.text(action.$2),
                  showsUserInterface: executionNotificationActionDelivery(
                    action.$1,
                  ).showsUserInterface,
                  cancelNotification: executionNotificationActionDelivery(
                    action.$1,
                  ).cancelNotification,
                ),
            ],
          ),
          windows: WindowsNotificationDetails(
            audio: WindowsNotificationAudio.silent(),
            actions: [
              for (final action in actions)
                WindowsAction(
                  content: l10n.text(
                    windowsExecutionActionLabelKey(action.$1, action.$2),
                  ),
                  arguments: windowsNotificationActionArguments(
                    actionId: action.$1,
                    payload: payload,
                  ),
                  activationBehavior: windowsExecutionActionBehavior(action.$1),
                ),
            ],
          ),
        ),
        payload: payload,
      );
      await _setExecutionLedgerState(
        taskId: taskId,
        state: 'scheduled',
        notificationId: notificationIdentity,
        sessionId: sessionId,
        runtimeRevision: runtimeRevision,
        intervalId: intervalId,
        boundaryAtUtc: boundaryAtUtc,
      );
    });
  }

  Importance _notificationImportance(String category) {
    return switch (category) {
      'focus_completed' ||
      'short_break_completed' ||
      'long_break_completed' => Importance.max,
      'task_reminders' ||
      'scheduled_starts' ||
      'overdue_tasks' ||
      'roadmaps' ||
      'activity_review' ||
      'coaching' ||
      'security' => Importance.high,
      _ => Importance.defaultImportance,
    };
  }

  Priority _notificationPriority(String category) {
    return switch (_notificationImportance(category)) {
      Importance.max => Priority.max,
      Importance.high => Priority.high,
      Importance.low => Priority.low,
      Importance.min || Importance.none => Priority.min,
      _ => Priority.defaultPriority,
    };
  }

  Color _notificationAccent(String category) {
    return switch (category) {
      'focus_completed' => const Color(0xFF38D889),
      'short_break_completed' ||
      'long_break_completed' => const Color(0xFF20C7C7),
      'overdue_tasks' => const Color(0xFFFF8A3D),
      'coaching' => const Color(0xFF8B7CFF),
      'sleep_health' => const Color(0xFF5B9DFF),
      'synchronization' => const Color(0xFF3AA8FF),
      'security' => const Color(0xFFFFB547),
      _ => const Color(0xFF46A6FF),
    };
  }

  AndroidNotificationCategory _androidNotificationCategory(String category) {
    return switch (category) {
      'focus_completed' ||
      'short_break_completed' ||
      'long_break_completed' => AndroidNotificationCategory.alarm,
      'scheduled_starts' ||
      'task_reminders' ||
      'overdue_tasks' => AndroidNotificationCategory.reminder,
      'coaching' => AndroidNotificationCategory.recommendation,
      'sleep_health' => AndroidNotificationCategory.status,
      'synchronization' => AndroidNotificationCategory.progress,
      'security' => AndroidNotificationCategory.error,
      _ => AndroidNotificationCategory.event,
    };
  }

  Future<NotificationSoundVerification> _verifyAndroidChannel({
    required String category,
    required NotificationSoundChoice sound,
    required bool vibration,
  }) async {
    final channelId = _channelId(
      category: category,
      sound: sound,
      vibration: vibration,
    );
    if (defaultTargetPlatform != TargetPlatform.android) {
      return NotificationSoundVerification(matches: true, channelId: channelId);
    }
    final verification = await _nativeChannel
        .invokeMapMethod<String, Object?>('verifyNotificationChannel', {
          'channelId': channelId,
          'kind': sound.key == 'silent'
              ? 'silent'
              : sound.deviceUri != null
              ? 'device'
              : sound.androidResource != null
              ? 'raw'
              : 'system',
          'uri': sound.deviceUri,
          'resource': sound.androidResource,
        });
    return NotificationSoundVerification(
      matches: verification?['matches'] == true,
      channelId: channelId,
      actualUri: verification?['actualUri'] as String?,
    );
  }

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  /// Removes every OS-level TaskMaster notification before this installation
  /// changes Supabase projects. The old notification ledger is only useful
  /// with the old account/cache, so retaining it could resurrect a stale
  /// alarm or action after the clean backend starts.
  ///
  /// This is intentionally local-only: it neither reads nor writes Supabase.
  Future<void> cancelAllForBackendCutover() async {
    await initialize();
    await _serializeNotificationMutation(() => _plugin.cancelAll());
    _launchResponse = null;

    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().where(
      (key) =>
          key == _executionLedgerStore ||
          key.startsWith('$_executionLedgerStore:') ||
          key == _executionPermissionPromptedStore ||
          key.startsWith('$_executionPermissionPromptedStore:') ||
          key == _backgroundResponseStore ||
          key.startsWith('$_backgroundResponseStore:'),
    );
    for (final key in keys.toList(growable: false)) {
      await preferences.remove(key);
    }
  }

  Future<void> _initialize() async {
    try {
      await _initializePlugin();
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializePlugin() async {
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
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
    await _repairWindowsScheduleBacklog();
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _launchResponse = launchDetails?.notificationResponse;
    }
    _initialized = true;
  }

  Future<void> _repairWindowsScheduleBacklog() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(
          NotificationSchedulePolicy.windowsRepairPreferenceKey,
        ) ==
        true) {
      return;
    }

    // Older releases appended a new Windows scheduled toast on every startup,
    // resume and realtime refresh. Clear that stale backlog once; HomeShell
    // immediately recreates the current canonical reminders.
    await _plugin.cancelAll();
    await preferences.setBool(
      NotificationSchedulePolicy.windowsRepairPreferenceKey,
      true,
    );
  }

  Future<T> _serializeNotificationMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _notificationMutationQueue = _notificationMutationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _cancelSerialized(int id) {
    return _serializeNotificationMutation(() => _plugin.cancel(id: id));
  }

  NotificationResponse? takeLaunchResponse() {
    final response = _launchResponse;
    _launchResponse = null;
    return response;
  }

  static Future<void> storeBackgroundResponse(
    NotificationResponse response,
  ) async {
    final normalized = normalizeNotificationResponse(response);
    if (normalized.payload == null) return;
    final preferences = await SharedPreferences.getInstance();
    final owner = decodeOwnedPayload(normalized.payload).ownerId;
    final storeKey = owner == null
        ? _backgroundResponseStore
        : '$_backgroundResponseStore:$owner';
    final existing = preferences.getStringList(storeKey) ?? const <String>[];
    final queued = <String>[
      ...existing.reversed.take(20).toList().reversed,
      jsonEncode({
        'payload': normalized.payload,
        'action_id': normalized.actionId,
      }),
    ];
    await preferences.setStringList(storeKey, queued);
  }

  Future<List<StoredNotificationResponse>> takeStoredBackgroundResponses({
    String? ownerId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final keys = <String>[
      if (ownerId != null) '$_backgroundResponseStore:$ownerId',
      _backgroundResponseStore,
    ];
    final serialized = <String>[];
    for (final key in keys) {
      serialized.addAll(preferences.getStringList(key) ?? const <String>[]);
      await preferences.remove(key);
    }
    final responses = <StoredNotificationResponse>[];
    for (final value in serialized) {
      try {
        final data = Map<String, Object?>.from(jsonDecode(value) as Map);
        responses.add(
          StoredNotificationResponse(
            payload: data['payload'] as String?,
            actionId: data['action_id'] as String?,
          ),
        );
      } catch (_) {
        // A malformed stale entry must not prevent a later valid action.
      }
    }
    return responses;
  }

  String _executionLedgerKey(String ownerId) =>
      '$_executionLedgerStore:$ownerId';

  Future<Map<String, Map<String, Object?>>> _readExecutionLedger(
    String ownerId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_executionLedgerKey(ownerId));
    if (raw == null || raw.isEmpty) return <String, Map<String, Object?>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Map<String, Object?>>{};
      final entries = <String, Map<String, Object?>>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        entries[entry.key as String] = Map<String, Object?>.from(
          entry.value as Map,
        );
      }
      return entries;
    } catch (_) {
      // A malformed legacy preference must never make an old alarm actionable.
      return <String, Map<String, Object?>>{};
    }
  }

  Future<void> _writeExecutionLedger(
    String ownerId,
    Map<String, Map<String, Object?>> entries,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _executionLedgerKey(ownerId),
      jsonEncode(entries),
    );
  }

  Future<void> _mirrorAndroidExecutionLedger({
    required String ownerId,
    required Map<String, Map<String, Object?>> entries,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _nativeChannel.invokeMethod<void>('writeExecutionAlarmLedger', {
        'ownerId': ownerId,
        'ledgerJson': jsonEncode(entries),
      });
    } on MissingPluginException {
      // Unit tests and non-registered background engines do not expose the
      // Android bridge. The Dart ledger remains the action-time authority.
    } on PlatformException {
      // Failing closed at delivery time is handled by the native receiver: an
      // execution alarm without a readable mirror is never displayed.
    }
  }

  Future<void> _setExecutionLedgerState({
    required String taskId,
    required String state,
    String? ownerId,
    String? notificationId,
    String? sessionId,
    int? runtimeRevision,
    String? intervalId,
    DateTime? boundaryAtUtc,
  }) async {
    final effectiveOwner =
        ownerId ?? Supabase.instance.client.auth.currentUser?.id;
    if (effectiveOwner == null || effectiveOwner.isEmpty) return;
    final entries = await _readExecutionLedger(effectiveOwner);
    final existing = entries[taskId];
    if (!executionLedgerTransitionAllowed(
      existing: existing,
      requestedState: state,
      notificationId: notificationId,
    )) {
      // A newer interval owns this task's single execution-notification slot.
      // Never let an old cancellation/action replace the newer ledger row.
      return;
    }
    entries[taskId] = <String, Object?>{
      ...?existing,
      'task_id': taskId,
      'notification_id': ?notificationId,
      'session_id': ?sessionId,
      'runtime_revision': ?runtimeRevision,
      'interval_id': ?intervalId,
      if (boundaryAtUtc != null)
        'boundary_at': boundaryAtUtc.toUtc().toIso8601String(),
      'state': state,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _writeExecutionLedger(effectiveOwner, entries);
    await _mirrorAndroidExecutionLedger(
      ownerId: effectiveOwner,
      entries: entries,
    );
  }

  /// Validates an action from a scheduled execution notification. This runs
  /// before HomeShell invokes any timer command, including background-isolate
  /// actions restored after an Android process restart.
  Future<bool> validateExecutionNotificationPayload(
    OwnedNotificationPayload payload,
  ) async {
    final taskId = payload.taskId;
    final ownerId = payload.ownerId;
    if (taskId == null ||
        taskId.isEmpty ||
        ownerId == null ||
        !payload.hasExecutionIdentity) {
      return false;
    }
    final entries = await _readExecutionLedger(ownerId);
    final entry = entries[taskId];
    if (entry == null ||
        !executionNotificationIdentityMatches(
          payload: payload,
          ledger: entry,
        )) {
      return false;
    }
    await _setExecutionLedgerState(
      taskId: taskId,
      ownerId: ownerId,
      notificationId: payload.notificationId,
      state: 'delivered',
    );
    return true;
  }

  Future<void> markExecutionNotificationHandled(
    OwnedNotificationPayload payload, {
    String state = 'handled',
  }) async {
    final taskId = payload.taskId;
    if (taskId == null || taskId.isEmpty || payload.ownerId == null) return;
    await _setExecutionLedgerState(
      taskId: taskId,
      ownerId: payload.ownerId,
      notificationId: payload.notificationId,
      state: state,
    );
  }

  static String ownedPayload(
    String route, {
    String? eventType,
    DateTime? boundaryAtUtc,
    String? notificationId,
    String? sessionId,
    int? runtimeRevision,
    String? intervalId,
  }) => ownedPayloadForOwner(
    ownerId: Supabase.instance.client.auth.currentUser?.id,
    route: route,
    eventType: eventType,
    boundaryAtUtc: boundaryAtUtc,
    notificationId: notificationId,
    sessionId: sessionId,
    runtimeRevision: runtimeRevision,
    intervalId: intervalId,
  );

  @visibleForTesting
  static String ownedPayloadForOwner({
    required String? ownerId,
    required String route,
    String? eventType,
    DateTime? boundaryAtUtc,
    String? notificationId,
    String? sessionId,
    int? runtimeRevision,
    String? intervalId,
    String? occurrenceId,
    int? taskRevision,
    int? reminderRevision,
    String? reminderId,
  }) {
    if (ownerId == null &&
        eventType == null &&
        boundaryAtUtc == null &&
        notificationId == null &&
        sessionId == null &&
        runtimeRevision == null &&
        intervalId == null &&
        occurrenceId == null &&
        taskRevision == null &&
        reminderRevision == null &&
        reminderId == null) {
      return route;
    }
    final payload = <String, Object?>{'version': 3, 'route': route};
    if (ownerId != null) payload['owner_id'] = ownerId;
    if (eventType != null) payload['event_type'] = eventType;
    if (boundaryAtUtc != null) {
      payload['boundary_at'] = boundaryAtUtc.toUtc().toIso8601String();
    }
    if (notificationId != null) payload['notification_id'] = notificationId;
    if (sessionId != null) payload['session_id'] = sessionId;
    if (runtimeRevision != null) {
      payload['runtime_revision'] = runtimeRevision;
    }
    if (intervalId != null) payload['interval_id'] = intervalId;
    if (occurrenceId != null) payload['occurrence_id'] = occurrenceId;
    if (taskRevision != null) payload['task_revision'] = taskRevision;
    if (reminderRevision != null) {
      payload['reminder_revision'] = reminderRevision;
    }
    if (reminderId != null) payload['reminder_id'] = reminderId;
    return jsonEncode(payload);
  }

  static OwnedNotificationPayload decodeOwnedPayload(String? payload) {
    if (payload == null) {
      return const OwnedNotificationPayload(route: '', ownerId: null);
    }
    try {
      final value = jsonDecode(payload);
      if (value is Map && value['route'] is String) {
        return OwnedNotificationPayload(
          route: value['route'] as String,
          ownerId: value['owner_id'] as String?,
          eventType: value['event_type'] as String?,
          boundaryAtUtc: DateTime.tryParse(
            '${value['boundary_at'] ?? ''}',
          )?.toUtc(),
          notificationId: value['notification_id'] as String?,
          sessionId: value['session_id'] as String?,
          runtimeRevision: (value['runtime_revision'] as num?)?.toInt(),
          intervalId: value['interval_id'] as String?,
          reminderId: int.tryParse('${value['reminder_id'] ?? ''}'),
        );
      }
    } catch (_) {
      // Notifications created by pre-v0.0.26 builds use a plain route.
    }
    return OwnedNotificationPayload(route: payload, ownerId: null);
  }

  Future<bool> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Returns Android's current notification authorization without prompting.
  /// First-run setup uses this to present a truthful status before the user
  /// decides whether to allow notifications.
  Future<bool> areAndroidNotificationsEnabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// Returns whether this Android device currently permits the exact alarms
  /// used for task, focus, and break boundaries. Older Android versions do
  /// not need the special access and report the capability as available.
  Future<bool> canScheduleExactAlarms() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  /// Opens Android's exact-alarm special-access flow when the platform
  /// requires it. It is only called from a deliberate first-run user action.
  Future<bool> requestExactAlarmsPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestExactAlarmsPermission() ?? false;
  }

  /// Requests Android's POST_NOTIFICATIONS permission exactly once when an
  /// execution alarm is first needed. Later denials remain visible to the
  /// shell and lead to the system-settings route rather than repeating a
  /// disruptive prompt on every timer/reconciliation tick.
  Future<bool> ensureExecutionNotificationsAuthorized() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.areNotificationsEnabled() ?? false) return true;
    final ownerId = Supabase.instance.client.auth.currentUser?.id;
    final preferences = await SharedPreferences.getInstance();
    final promptKey = ownerId == null || ownerId.isEmpty
        ? _executionPermissionPromptedStore
        : '$_executionPermissionPromptedStore:$ownerId';
    if (preferences.getBool(promptKey) == true) return false;
    await preferences.setBool(promptKey, true);
    if (await android?.requestNotificationsPermission() ?? false) return true;
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<void> openAndroidAppNotificationSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _nativeChannel.invokeMethod<void>('openAppNotificationSettings');
  }

  Future<void> openAndroidSystemSoundSettings({
    String category = 'task_reminders',
    NotificationSoundChoice sound = const NotificationSoundChoice(
      key: 'system',
    ),
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await initialize();
    final l10n = AppLocalizations(Locale(localeCode));
    final channel = AndroidNotificationChannel(
      _channelId(category: category, sound: sound, vibration: vibration),
      _channelName(l10n, category),
      description: _channelDescription(l10n, category),
      importance: _notificationImportance(
        NotificationSounds.canonicalCategory(category),
      ),
      playSound: sound.key != 'silent',
      sound: _androidSound(sound),
      enableVibration: vibration,
      audioAttributesUsage: _androidAudioUsage(sound),
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

  Future<NotificationSoundChoice?> pickAndroidSystemSound({
    required String type,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final selected = await _nativeChannel.invokeMapMethod<String, Object?>(
      'pickSystemSound',
      {'type': type},
    );
    final uri = selected?['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    final title = selected?['title'] as String? ?? 'Device sound';
    return NotificationSounds.device(uri: uri, kind: type, label: title);
  }

  Future<NotificationSoundVerification> showTest(
    NotificationSoundChoice sound, {
    String category = 'task_reminders',
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    await initialize();
    final l10n = AppLocalizations(Locale(localeCode));
    final title = 'TaskMaster Pro';
    final body = l10n.text('notification_test_body');
    await _plugin.show(
      id: 9001,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          l10n: l10n,
          category: category,
          sound: sound,
          vibration: vibration,
          title: title,
          body: body,
          notificationTag: 'test:$category',
          actions: [
            AndroidNotificationAction(
              'open',
              l10n.text('open'),
              showsUserInterface: true,
            ),
          ],
        ),
        windows: WindowsNotificationDetails(audio: _windowsAudio(sound)),
      ),
      payload: ownedPayload('settings/notifications'),
    );
    return _verifyAndroidChannel(
      category: category,
      sound: sound,
      vibration: vibration,
    );
  }

  Future<void> scheduleTaskReminder({
    required int id,
    required String taskId,
    required String taskTitle,
    required String reminderType,
    required DateTime scheduledAtUtc,
    required NotificationSoundChoice sound,
    String? ownerId,
    String? occurrenceId,
    int? taskRevision,
    int? reminderRevision,
    String? category,
    bool enabled = true,
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    await initialize();
    if (!enabled) {
      await _cancelSerialized(id);
      return;
    }
    final l10n = AppLocalizations(Locale(localeCode));
    final effectiveCategory =
        category ?? NotificationSounds.categoryForReminderType(reminderType);
    final body = _bodyFor(reminderType, l10n);
    final payload = ownedPayloadForOwner(
      ownerId: ownerId,
      route: 'task/$taskId',
      occurrenceId: occurrenceId,
      taskRevision: taskRevision,
      reminderRevision: reminderRevision,
      reminderId: id.toString(),
      boundaryAtUtc: scheduledAtUtc,
    );
    await _serializeNotificationMutation(() async {
      // Windows appends scheduled toasts even when the tag is unchanged. Make
      // every refresh an atomic replace and drop reminders that became due
      // while they were waiting behind another notification mutation.
      await _plugin.cancel(id: id);
      if (!NotificationSchedulePolicy.canSchedule(scheduledAtUtc)) return;
      await _plugin.zonedSchedule(
        id: id,
        title: taskTitle,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledAtUtc.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: _androidDetails(
            l10n: l10n,
            category: effectiveCategory,
            sound: sound,
            vibration: vibration,
            title: taskTitle,
            body: body,
            notificationTag: 'reminder:$taskId:$effectiveCategory',
            actions: [
              AndroidNotificationAction(
                'start',
                l10n.text('start'),
                showsUserInterface: reminderNotificationActionDelivery(
                  'start',
                ).showsUserInterface,
                cancelNotification: reminderNotificationActionDelivery(
                  'start',
                ).cancelNotification,
              ),
              AndroidNotificationAction(
                'complete',
                l10n.text('complete'),
                showsUserInterface: reminderNotificationActionDelivery(
                  'complete',
                ).showsUserInterface,
                cancelNotification: reminderNotificationActionDelivery(
                  'complete',
                ).cancelNotification,
              ),
              AndroidNotificationAction(
                'snooze',
                l10n.text('snooze'),
                showsUserInterface: reminderNotificationActionDelivery(
                  'snooze',
                ).showsUserInterface,
                cancelNotification: reminderNotificationActionDelivery(
                  'snooze',
                ).cancelNotification,
              ),
            ],
          ),
          windows: WindowsNotificationDetails(
            audio: _windowsAudio(sound),
            actions: [
              WindowsAction(
                content: l10n.text('start'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'start',
                  payload: payload,
                ),
                activationBehavior: windowsReminderActionBehavior('start'),
              ),
              WindowsAction(
                content: l10n.text('complete'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'complete',
                  payload: payload,
                ),
                activationBehavior: windowsReminderActionBehavior('complete'),
              ),
              WindowsAction(
                content: l10n.text('snooze'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'snooze',
                  payload: payload,
                ),
                activationBehavior: windowsReminderActionBehavior('snooze'),
              ),
              WindowsAction(
                content: l10n.text('open'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'open',
                  payload: payload,
                ),
              ),
              WindowsAction(
                content: l10n.text('dismiss'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'dismiss',
                  payload: payload,
                ),
              ),
            ],
          ),
        ),
        payload: payload,
      );
    });
  }

  Future<void> scheduleExecutionCompletion({
    required int id,
    required String taskId,
    required String taskTitle,
    required String eventType,
    required DateTime scheduledAtUtc,
    required NotificationSoundChoice sound,
    String? sessionId,
    int? runtimeRevision,
    String? intervalId,
    String? category,
    bool enabled = true,
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    await initialize();
    String? notificationIdentity;
    if (sessionId != null &&
        sessionId.isNotEmpty &&
        runtimeRevision != null &&
        intervalId != null &&
        intervalId.isNotEmpty) {
      notificationIdentity = executionNotificationIdentity(
        taskId: taskId,
        sessionId: sessionId,
        runtimeRevision: runtimeRevision,
        intervalId: intervalId,
        boundaryAtUtc: scheduledAtUtc,
      );
    }
    if (!enabled) {
      await _cancelSerialized(id);
      await _setExecutionLedgerState(
        taskId: taskId,
        state: 'cancelled',
        notificationId: notificationIdentity,
        sessionId: sessionId,
        runtimeRevision: runtimeRevision,
        intervalId: intervalId,
        boundaryAtUtc: scheduledAtUtc,
      );
      return;
    }
    if (!await ensureExecutionNotificationsAuthorized()) {
      // Keep the exact notification slot empty while Android has denied the
      // permission.  A later granted permission causes normal runtime
      // reconciliation to schedule a fresh, current interval—not this stale
      // one.
      await _cancelSerialized(id);
      await _setExecutionLedgerState(
        taskId: taskId,
        state: 'cancelled',
        notificationId: notificationIdentity,
        sessionId: sessionId,
        runtimeRevision: runtimeRevision,
        intervalId: intervalId,
        boundaryAtUtc: scheduledAtUtc,
      );
      return;
    }
    final l10n = AppLocalizations(Locale(localeCode));
    final isBreak =
        eventType == 'break_completed' ||
        eventType == 'short_break_completed' ||
        eventType == 'long_break_completed';
    final isPomodoro = eventType == 'focus_completed';
    final effectiveCategory =
        category ??
        (isPomodoro
            ? 'focus_completed'
            : eventType == 'long_break_completed'
            ? 'long_break_completed'
            : isBreak
            ? 'short_break_completed'
            : 'task_reminders');
    final title = l10n.text(
      isBreak
          ? 'notification_break_completed_title'
          : isPomodoro
          ? 'notification_focus_completed_title'
          : 'notification_duration_completed_title',
    );
    final body = l10n.format(
      isBreak
          ? 'notification_break_completed_body'
          : isPomodoro
          ? 'notification_focus_completed_body'
          : 'notification_duration_completed_body',
      {'task': taskTitle},
    );
    final actions = isBreak
        ? [
            ('start_focus', 'notification_start_focus'),
            ('extend_break', 'notification_extend_break'),
            ('review_break', 'notification_review_break'),
            ('finish_task', 'finish_task'),
            ('dismiss', 'dismiss'),
          ]
        : isPomodoro
        ? [
            ('start_break', 'notification_start_break'),
            ('continue_working', 'notification_continue_working'),
            ('finish_task', 'finish_task'),
            ('dismiss', 'dismiss'),
          ]
        : [
            ('continue_working', 'notification_continue_task'),
            ('finish_task', 'finish_task'),
            ('open', 'open'),
            ('dismiss', 'dismiss'),
          ];
    final androidActions = isBreak
        ? [
            ('start_focus', 'notification_start_focus'),
            ('extend_break', 'notification_extend_break'),
            ('finish_task', 'finish_task'),
            ('open', 'open'),
          ]
        : !isPomodoro
        ? [
            ('continue_working', 'notification_continue_task'),
            ('finish_task', 'finish_task'),
            ('open', 'open'),
          ]
        : [
            ('start_break', 'notification_start_break'),
            ('continue_working', 'notification_continue_working'),
            ('finish_task', 'finish_task'),
            ('open', 'open'),
          ];
    final payload = ownedPayload(
      'task/$taskId',
      eventType: eventType,
      boundaryAtUtc: scheduledAtUtc,
      notificationId: notificationIdentity,
      sessionId: sessionId,
      runtimeRevision: runtimeRevision,
      intervalId: intervalId,
    );
    await _serializeNotificationMutation(() async {
      await _plugin.cancel(id: id);
      if (!NotificationSchedulePolicy.canSchedule(scheduledAtUtc)) {
        await _setExecutionLedgerState(
          taskId: taskId,
          state: 'expired',
          notificationId: notificationIdentity,
          sessionId: sessionId,
          runtimeRevision: runtimeRevision,
          intervalId: intervalId,
          boundaryAtUtc: scheduledAtUtc,
        );
        return;
      }
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledAtUtc.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: _androidDetails(
            l10n: l10n,
            category: effectiveCategory,
            sound: sound,
            vibration: vibration,
            title: title,
            body: body,
            notificationTag: 'execution:$taskId:$effectiveCategory',
            actions: [
              for (final action in androidActions.take(4))
                AndroidNotificationAction(
                  action.$1,
                  l10n.text(action.$2),
                  showsUserInterface: executionNotificationActionDelivery(
                    action.$1,
                  ).showsUserInterface,
                  cancelNotification: executionNotificationActionDelivery(
                    action.$1,
                  ).cancelNotification,
                ),
            ],
          ),
          windows: WindowsNotificationDetails(
            audio: _windowsAudio(sound),
            scenario: isPomodoro || isBreak
                ? WindowsNotificationScenario.alarm
                : null,
            actions: [
              for (final action in actions.take(5))
                WindowsAction(
                  content: l10n.text(
                    windowsExecutionActionLabelKey(action.$1, action.$2),
                  ),
                  arguments: windowsNotificationActionArguments(
                    actionId: action.$1,
                    payload: payload,
                  ),
                  activationBehavior: windowsExecutionActionBehavior(action.$1),
                ),
            ],
          ),
        ),
        payload: payload,
      );
      await _setExecutionLedgerState(
        taskId: taskId,
        state: 'scheduled',
        notificationId: notificationIdentity,
        sessionId: sessionId,
        runtimeRevision: runtimeRevision,
        intervalId: intervalId,
        boundaryAtUtc: scheduledAtUtc,
      );
    });
  }

  /// Schedules the device-local standalone Pomodoro boundary. Unlike a task
  /// execution alert it carries no task/session identity and therefore offers
  /// only safe Open/Dismiss actions; the persistent store reconciles the
  /// expired phase exactly once whether or not the timer screen is mounted.
  Future<void> scheduleStandalonePomodoroCompletion({
    required bool isBreak,
    required DateTime scheduledAtUtc,
    required NotificationSoundChoice sound,
    bool enabled = true,
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    await initialize();
    if (!enabled || !await ensureExecutionNotificationsAuthorized()) {
      await _cancelSerialized(standalonePomodoroNotificationId);
      return;
    }
    final l10n = AppLocalizations(Locale(localeCode));
    final category = isBreak ? 'short_break_completed' : 'focus_completed';
    final title = l10n.text(
      isBreak
          ? 'notification_break_completed_title'
          : 'notification_focus_completed_title',
    );
    final body = l10n.format(
      isBreak
          ? 'notification_break_completed_body'
          : 'notification_focus_completed_body',
      {'task': l10n.text('standalone_pomodoro')},
    );
    final payload = ownedPayload(
      'standalone-pomodoro',
      eventType: isBreak
          ? 'standalone_break_completed'
          : 'standalone_focus_completed',
      boundaryAtUtc: scheduledAtUtc,
    );
    await _serializeNotificationMutation(() async {
      await _plugin.cancel(id: standalonePomodoroNotificationId);
      if (!NotificationSchedulePolicy.canSchedule(scheduledAtUtc)) return;
      await _plugin.zonedSchedule(
        id: standalonePomodoroNotificationId,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledAtUtc.toUtc(), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: _androidDetails(
            l10n: l10n,
            category: category,
            sound: sound,
            vibration: vibration,
            title: title,
            body: body,
            notificationTag: 'standalone-pomodoro:$category',
            actions: [
              AndroidNotificationAction(
                'open',
                l10n.text('open'),
                showsUserInterface: true,
              ),
              AndroidNotificationAction('dismiss', l10n.text('dismiss')),
            ],
          ),
          windows: WindowsNotificationDetails(
            audio: _windowsAudio(sound),
            scenario: WindowsNotificationScenario.alarm,
            actions: [
              WindowsAction(
                content: l10n.text('open'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'open',
                  payload: payload,
                ),
              ),
              WindowsAction(
                content: l10n.text('dismiss'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'dismiss',
                  payload: payload,
                ),
              ),
            ],
          ),
        ),
        payload: payload,
      );
    });
  }

  Future<void> cancelStandalonePomodoroCompletion() =>
      cancel(standalonePomodoroNotificationId);

  Future<void> scheduleDailySleepReminder({
    required bool enabled,
    required int sleepTimeMinutes,
    required int reminderOffsetMinutes,
    required String timeZone,
    required NotificationSoundChoice sound,
    bool notificationsEnabled = true,
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    const id = 820026;
    await initialize();
    if (!enabled || !notificationsEnabled) {
      await _cancelSerialized(id);
      return;
    }
    final l10n = AppLocalizations(Locale(localeCode));
    final location = _location(timeZone);
    final now = tz.TZDateTime.now(location);
    final minuteOfDay = (sleepTimeMinutes - reminderOffsetMinutes) % (24 * 60);
    var scheduled = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    final title = l10n.text('sleep_reminder_title');
    final body = l10n.text('sleep_reminder_body');
    final payload = ownedPayload('settings/wellbeing');
    await _serializeNotificationMutation(() async {
      await _plugin.cancel(id: id);
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        notificationDetails: NotificationDetails(
          android: _androidDetails(
            l10n: l10n,
            category: 'sleep_health',
            sound: sound,
            vibration: vibration,
            title: title,
            body: body,
            notificationTag: 'wellbeing:sleep',
            actions: [
              AndroidNotificationAction(
                'open_wellbeing',
                l10n.text('notification_view_schedule'),
                showsUserInterface: true,
              ),
              AndroidNotificationAction('dismiss', l10n.text('dismiss')),
            ],
          ),
          windows: WindowsNotificationDetails(
            audio: _windowsAudio(sound),
            actions: [
              WindowsAction(
                content: l10n.text('notification_view_schedule'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'open_wellbeing',
                  payload: payload,
                ),
              ),
              WindowsAction(
                content: l10n.text('dismiss'),
                arguments: windowsNotificationActionArguments(
                  actionId: 'dismiss',
                  payload: payload,
                ),
              ),
            ],
          ),
        ),
        payload: payload,
      );
    });
  }

  Future<void> cancelExecutionCompletion(String taskId) async {
    await cancelExecutionCompletionWithState(taskId);
  }

  /// Retires the single execution-toast slot while preserving the reason in
  /// the identity ledger. Rejected/superseded Windows pending-update actions
  /// use `superseded`; ordinary runtime reconciliation uses `cancelled`.
  Future<void> cancelExecutionCompletionWithState(
    String taskId, {
    String ledgerState = 'cancelled',
  }) async {
    await cancel(executionNotificationId(taskId));
    await cancel(executionStatusNotificationId(taskId));
    await _setExecutionLedgerState(taskId: taskId, state: ledgerState);
  }

  /// Cancels only the ordinary persisted reminder represented by [payload].
  /// It deliberately cannot touch the execution alarm slot for the same task.
  Future<void> cancelTaskReminder(OwnedNotificationPayload payload) async {
    final reminderId = payload.reminderId;
    if (reminderId == null) return;
    await cancel(reminderId);
  }

  /// Repairs this installation's task notification queue after auth/runtime
  /// restoration without touching wellbeing, Activity, security or any other
  /// unrelated notification owned by the application.
  ///
  /// Pending request payloads carry owner and interval identity. Android does
  /// not expose payloads for already-delivered cards, so only execution tags
  /// are eligible there. The caller subsequently schedules the one current
  /// runtime boundary, making the operation reconcile forward.
  Future<void> reconcileOwnedTaskNotificationsOnStartup({
    required String ownerId,
  }) async {
    await initialize();
    await _serializeNotificationMutation(() async {
      final pending = await _plugin.pendingNotificationRequests();
      final obsoleteIds = obsoleteOwnedTaskNotificationIds(
        ownerId: ownerId,
        pending: pending,
      );
      for (final id in obsoleteIds) {
        await _plugin.cancel(id: id);
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final active = await _plugin.getActiveNotifications();
          for (final notification in active) {
            final id = notification.id;
            final tag = notification.tag;
            if (id == null || !isExecutionNotificationTag(tag)) continue;
            await _plugin.cancel(id: id, tag: tag);
          }
        } on UnimplementedError {
          // Active-card enumeration is an Android capability. Pending alarms
          // were still reconciled above on every supported platform.
        } on PlatformException {
          // A vendor notification service may briefly deny enumeration during
          // startup. The identity ledger still suppresses all stale actions.
        }
      }

      final entries = await _readExecutionLedger(ownerId);
      if (entries.isEmpty) return;
      final repaired = <String, Map<String, Object?>>{
        for (final entry in entries.entries)
          entry.key: <String, Object?>{
            ...entry.value,
            'state': 'superseded',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
      };
      await _writeExecutionLedger(ownerId, repaired);
      await _mirrorAndroidExecutionLedger(ownerId: ownerId, entries: repaired);
    });
  }

  Future<void> cancel(int id) async {
    await initialize();
    await _cancelSerialized(id);
  }

  Future<Set<int>> pendingNotificationIds() async {
    await initialize();
    return _serializeNotificationMutation(() async {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.map((notification) => notification.id).toSet();
    });
  }

  Future<void> showActivityReviewAlert({
    required String taskId,
    required NotificationSoundChoice sound,
    bool enabled = true,
    bool vibration = true,
    String localeCode = 'en',
  }) async {
    await initialize();
    if (!enabled) return;
    final l10n = AppLocalizations(Locale(localeCode));
    final title = l10n.text('activity_review_notification_title');
    final body = l10n.text('activity_review_over_half');
    final payload = ownedPayload('activity/$taskId');
    await _plugin.show(
      id: 'activity-review:$taskId'.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          l10n: l10n,
          category: 'activity_review',
          sound: sound,
          vibration: vibration,
          title: title,
          body: body,
          notificationTag: 'activity:$taskId',
          actions: [
            AndroidNotificationAction(
              'review_activity',
              l10n.text('activity_review'),
              showsUserInterface: true,
            ),
            AndroidNotificationAction('dismiss', l10n.text('dismiss')),
          ],
        ),
        windows: WindowsNotificationDetails(
          audio: _windowsAudio(sound),
          actions: [
            WindowsAction(
              content: l10n.text('activity_review'),
              arguments: windowsNotificationActionArguments(
                actionId: 'review_activity',
                payload: payload,
              ),
            ),
            WindowsAction(
              content: l10n.text('dismiss'),
              arguments: windowsNotificationActionArguments(
                actionId: 'dismiss',
                payload: payload,
              ),
            ),
          ],
        ),
      ),
      payload: payload,
    );
  }

  Future<NotificationSoundVerification> showCategoryNotification({
    required int id,
    required String category,
    required String title,
    required String body,
    required NotificationSoundChoice sound,
    required String payload,
    bool vibration = true,
    String localeCode = 'en',
    List<AndroidNotificationAction>? androidActions,
    List<WindowsAction>? windowsActions,
  }) async {
    if (!NotificationSounds.categories.contains(category)) {
      throw ArgumentError.value(category, 'category');
    }
    await initialize();
    final l10n = AppLocalizations(Locale(localeCode));
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: _androidDetails(
          l10n: l10n,
          category: category,
          sound: sound,
          vibration: vibration,
          title: title,
          body: body,
          notificationTag: 'category:$category:$id',
          actions: androidActions,
        ),
        windows: WindowsNotificationDetails(
          audio: _windowsAudio(sound),
          actions: windowsActions ?? const <WindowsAction>[],
        ),
      ),
      payload: ownedPayload(payload),
    );
    return _verifyAndroidChannel(
      category: category,
      sound: sound,
      vibration: vibration,
    );
  }

  tz.Location _location(String name) {
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.UTC;
    }
  }

  String _bodyFor(String type, AppLocalizations l10n) {
    return l10n.text(switch (type) {
      'before_start' => 'reminder_before_start',
      'start' => 'reminder_start',
      'planned_end' => 'reminder_planned_end',
      'due' => 'reminder_due',
      'overdue' => 'reminder_overdue',
      'missed' => 'reminder_missed',
      _ => 'reminder_open_task',
    });
  }
}

final localNotificationService = LocalNotificationService();
