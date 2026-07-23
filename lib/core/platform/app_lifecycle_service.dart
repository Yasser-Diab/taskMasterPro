import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../config/app_config.dart';

enum AppLifecycleCommand {
  restore,
  tasks,
  pomodoro,
  workSession,
  learningSession,
  notifications,
  synchronization,
  settings,
}

class AppTrayMenuLabels {
  const AppTrayMenuLabels({
    required this.tasks,
    required this.pomodoro,
    required this.workSession,
    required this.learningSession,
    required this.notifications,
    required this.synchronization,
    required this.settings,
    required this.exit,
  });

  final String tasks;
  final String pomodoro;
  final String workSession;
  final String learningSession;
  final String notifications;
  final String synchronization;
  final String settings;
  final String exit;

  Map<String, String> toMap() {
    return {
      'tasks': tasks,
      'pomodoro': pomodoro,
      'workSession': workSession,
      'learningSession': learningSession,
      'notifications': notifications,
      'synchronization': synchronization,
      'settings': settings,
      'exit': exit,
    };
  }
}

class ActiveSessionStatus {
  const ActiveSessionStatus({
    required this.active,
    required this.title,
    required this.summary,
  });

  const ActiveSessionStatus.inactive()
    : active = false,
      title = '',
      summary = '';

  final bool active;
  final String title;
  final String summary;

  String get signature => '$active|$title|$summary';
}

class WidgetSessionCommand {
  const WidgetSessionCommand({required this.command, required this.occurredAt});

  final String command;
  final DateTime occurredAt;
}

class AppLifecycleService {
  AppLifecycleService();

  static const _windowsChannel = MethodChannel(
    'taskmasterpro/windows_lifecycle',
  );
  static const _androidChannel = MethodChannel('taskmasterpro/active_session');
  static const _androidWidgetChannel = MethodChannel('taskmasterpro/widgets');

  final _commandController = StreamController<AppLifecycleCommand>.broadcast();
  final _exitRequestController = StreamController<void>.broadcast();

  bool _initialized = false;
  String? _activeSessionSignature;
  bool _foregroundSessionRunning = false;
  bool _exitInProgress = false;

  Stream<AppLifecycleCommand> get commands => _commandController.stream;
  Stream<void> get exitRequests => _exitRequestController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (Platform.isWindows) {
      _windowsChannel.setMethodCallHandler(_handleWindowsMethodCall);
      try {
        await _windowsChannel.invokeMethod<void>('initialize');
      } on MissingPluginException {
        // Unit tests and non-Windows runners do not expose the native channel.
      } on PlatformException {
        // Keep the app usable even if the tray cannot be created.
      }
    }
  }

  Future<void> updateMenuLabels(AppTrayMenuLabels labels) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _windowsChannel.invokeMethod<void>('setMenuLabels', labels.toMap());
    } on MissingPluginException {
      // No-op outside the packaged Windows runner.
    } on PlatformException {
      // The menu will keep its built-in English fallbacks.
    }
  }

  Future<void> updateActiveSession(ActiveSessionStatus status) async {
    if (_activeSessionSignature == status.signature) {
      return;
    }
    _activeSessionSignature = status.signature;

    if (Platform.isWindows) {
      await _sendWindowsActiveSession(status);
    } else if (Platform.isAndroid) {
      await _sendAndroidActiveSession(status);
    }
  }

  Future<WidgetSessionCommand?> takePendingWidgetCommand() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final result = await _androidWidgetChannel
          .invokeMapMethod<String, Object?>('takeLastCommand');
      final command = result?['command']?.toString();
      if (command == null || command.isEmpty) {
        return null;
      }
      final occurredAtMs = result?['occurredAt'];
      final occurredAt = occurredAtMs is num && occurredAtMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(occurredAtMs.toInt())
          : DateTime.now();
      return WidgetSessionCommand(command: command, occurredAt: occurredAt);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> exitApplication() async {
    if (_exitInProgress) {
      return;
    }
    _exitInProgress = true;
    if (Platform.isAndroid && _foregroundSessionRunning) {
      await _sendAndroidActiveSession(const ActiveSessionStatus.inactive());
    }
    if (Platform.isWindows) {
      await _sendWindowsActiveSession(const ActiveSessionStatus.inactive());
    }

    if (Platform.isWindows) {
      try {
        await _windowsChannel.invokeMethod<void>('exitApplication');
        return;
      } on MissingPluginException {
        // Fall through to SystemNavigator for tests or unsupported runners.
      } on PlatformException {
        // Fall through to SystemNavigator as a last resort.
      }
    }

    await SystemNavigator.pop();
  }

  Future<void> resetWindowPosition() async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _windowsChannel.invokeMethod<void>('resetWindowPosition');
    } on MissingPluginException {
      // No native window in tests.
    } on PlatformException {
      // The app remains usable even if the native reset fails.
    }
  }

  Future<bool> isWindowFocused() async {
    if (!Platform.isWindows) return true;
    try {
      return await _windowsChannel.invokeMethod<bool>('isWindowFocused') ??
          true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  Future<Map<String, dynamic>?> sampleForegroundActivity() async {
    if (!Platform.isWindows) return null;
    try {
      final value = await _windowsChannel.invokeMethod<Object?>(
        'sampleForegroundActivity',
      );
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> applyWindowPreferences(AppConfig config) async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      await _windowsChannel.invokeMethod<void>('applyWindowPreferences', {
        'restoreGeometry': config.restoreWindowGeometry,
        'restoreMaximized': config.restoreWindowMaximized,
      });
    } on MissingPluginException {
      // No native window in tests.
    } on PlatformException {
      // Window preferences are a convenience; keep the app usable if they fail.
    }
  }

  Future<dynamic> _handleWindowsMethodCall(MethodCall call) async {
    if (call.method != 'trayCommand') {
      return null;
    }

    final command = call.arguments;
    if (command is! String) {
      return null;
    }

    if (command == 'exit') {
      _exitRequestController.add(null);
      return null;
    }

    final parsed = switch (command) {
      'restore' => AppLifecycleCommand.restore,
      'tasks' => AppLifecycleCommand.tasks,
      'pomodoro' => AppLifecycleCommand.pomodoro,
      'workSession' => AppLifecycleCommand.workSession,
      'learningSession' => AppLifecycleCommand.learningSession,
      'notifications' => AppLifecycleCommand.notifications,
      'synchronization' => AppLifecycleCommand.synchronization,
      'settings' => AppLifecycleCommand.settings,
      _ => null,
    };

    if (parsed != null) {
      _commandController.add(parsed);
    }
    return null;
  }

  Future<void> _sendWindowsActiveSession(ActiveSessionStatus status) async {
    try {
      await _windowsChannel.invokeMethod<void>('setActiveSession', {
        'active': status.active,
        'summary': status.summary,
      });
    } on MissingPluginException {
      // No native window in tests.
    } on PlatformException {
      // Losing a tray tooltip update should not stop the timer.
    }
  }

  Future<void> _sendAndroidActiveSession(ActiveSessionStatus status) async {
    try {
      if (status.active) {
        await _androidChannel.invokeMethod<void>('startOrUpdate', {
          'title': status.title,
          'text': status.summary,
        });
        await _androidWidgetChannel.invokeMethod<void>('updateSnapshot', {
          'kind': 'active_timer',
          'snapshot': {
            'title': status.title,
            'subtitle': status.summary,
            'remaining': status.summary,
            'primary_action_label': 'Pause',
            'primary_action': 'pause',
            'secondary_action_label': 'Finish focus',
            'secondary_action': 'finish_focus',
          },
        });
        _foregroundSessionRunning = true;
      } else if (_foregroundSessionRunning) {
        await _androidChannel.invokeMethod<void>('stop');
        await _androidWidgetChannel.invokeMethod<void>('updateSnapshot', {
          'kind': 'active_timer',
          'snapshot': {
            'title': 'No active timer',
            'subtitle': 'TaskMaster Pro',
            'remaining': '--:--',
            'primary_action_label': 'Open',
            'primary_action': 'open',
            'secondary_action_label': 'Refresh',
            'secondary_action': 'refresh',
          },
        });
        _foregroundSessionRunning = false;
      }
    } on MissingPluginException {
      // No-op on tests and non-Android shells.
    } on PlatformException {
      // The in-app timer keeps running; foreground notification can retry on
      // the next state change.
    }
  }

  void dispose() {
    _commandController.close();
    _exitRequestController.close();
  }
}
