import 'dart:async';

import 'package:flutter/foundation.dart';

enum AppNotificationLevel { info, success, warning, error }

class AppNotificationAction {
  const AppNotificationAction({
    required this.label,
    required this.onPressed,
    this.dismissAfterPressed = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool dismissAfterPressed;
}

class AppNotificationMessage {
  const AppNotificationMessage({
    required this.id,
    required this.message,
    required this.level,
    required this.duration,
    this.action,
  });

  final String id;
  final String message;
  final AppNotificationLevel level;
  final Duration? duration;
  final AppNotificationAction? action;
}

class AppNotificationService extends ChangeNotifier {
  AppNotificationMessage? _current;
  Duration _remaining = Duration.zero;
  Timer? _timer;
  bool _paused = false;

  AppNotificationMessage? get current => _current;
  bool get isPaused => _paused;

  double get progress {
    final message = _current;
    final duration = message?.duration;
    if (message == null || duration == null || duration.inMilliseconds <= 0) {
      return 1;
    }
    return (_remaining.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
  }

  int get secondsRemaining {
    if (_current?.duration == null) {
      return 0;
    }
    return (_remaining.inMilliseconds / 1000).ceil().clamp(0, 999);
  }

  void showInfo(String message, {AppNotificationAction? action, String? id}) {
    show(message, level: AppNotificationLevel.info, action: action, id: id);
  }

  void showSuccess(
    String message, {
    AppNotificationAction? action,
    String? id,
  }) {
    show(message, level: AppNotificationLevel.success, action: action, id: id);
  }

  void showWarning(
    String message, {
    AppNotificationAction? action,
    String? id,
  }) {
    show(message, level: AppNotificationLevel.warning, action: action, id: id);
  }

  void showError(String message, {AppNotificationAction? action, String? id}) {
    show(message, level: AppNotificationLevel.error, action: action, id: id);
  }

  void show(
    String message, {
    required AppNotificationLevel level,
    AppNotificationAction? action,
    String? id,
  }) {
    final notificationId =
        id ?? '${level.name}:${message.trim()}:${action?.label ?? ''}';
    final duration = _durationFor(level);
    _timer?.cancel();
    _paused = false;
    _remaining = duration ?? Duration.zero;
    _current = AppNotificationMessage(
      id: notificationId,
      message: message,
      level: level,
      duration: duration,
      action: action,
    );
    notifyListeners();
    _startTimerIfNeeded();
  }

  void pause() {
    if (_current?.duration == null || _paused) {
      return;
    }
    _paused = true;
    _timer?.cancel();
    notifyListeners();
  }

  void resume() {
    if (_current?.duration == null || !_paused) {
      return;
    }
    _paused = false;
    notifyListeners();
    _startTimerIfNeeded();
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    _paused = false;
    _remaining = Duration.zero;
    _current = null;
    notifyListeners();
  }

  void runAction() {
    final action = _current?.action;
    if (action == null) {
      return;
    }
    action.onPressed();
    if (action.dismissAfterPressed) {
      dismiss();
    }
  }

  void _startTimerIfNeeded() {
    if (_current?.duration == null || _paused) {
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _remaining -= const Duration(milliseconds: 100);
      if (_remaining <= Duration.zero) {
        dismiss();
        return;
      }
      notifyListeners();
    });
  }

  Duration? _durationFor(AppNotificationLevel level) {
    return switch (level) {
      AppNotificationLevel.info => const Duration(seconds: 4),
      AppNotificationLevel.success => const Duration(seconds: 3),
      AppNotificationLevel.warning => const Duration(seconds: 6),
      AppNotificationLevel.error => null,
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
