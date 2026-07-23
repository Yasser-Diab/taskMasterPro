import 'dart:async';

import 'package:flutter/services.dart';

import '../config/app_config.dart';

class InteractionFeedbackService {
  InteractionFeedbackService();

  static const _channel = MethodChannel('taskmasterpro/interaction_feedback');
  static const _clickAsset = 'media/notifications-sound/click-sound.mp3';

  bool _initialized = false;
  bool _uiClickEnabled = true;
  double _uiClickVolume = 0.65;

  Future<void> initialize(AppConfig config) async {
    _uiClickEnabled = config.uiClickSounds;
    _uiClickVolume = config.uiClickVolume;
    if (_initialized) {
      await updateConfig(config);
      return;
    }

    try {
      final data = await rootBundle.load(_clickAsset);
      await _channel.invokeMethod<void>('initializeClickSound', {
        'bytes': Uint8List.sublistView(data),
        'volume': _uiClickVolume,
      });
      _initialized = true;
    } on MissingPluginException {
      // Tests and unsupported shells remain usable without audio.
    } on PlatformException {
      // Audio feedback is supplementary; visual feedback still carries UX.
    } on Object {
      // A missing/corrupt asset must not block application startup.
    }
  }

  Future<void> updateConfig(AppConfig config) async {
    _uiClickEnabled = config.uiClickSounds;
    _uiClickVolume = config.uiClickVolume.clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod<void>('setVolume', {
        'volume': _uiClickVolume,
      });
    } on MissingPluginException {
      // No-op in tests.
    } on PlatformException {
      // Keep the setting locally; native side may recover on next startup.
    }
  }

  void playUiClick() {
    if (!_uiClickEnabled || !_initialized) {
      return;
    }
    unawaited(_play('playClick'));
  }

  void playSuccess() {
    if (!_initialized) {
      return;
    }
    unawaited(_play('playClick'));
  }

  void playError() {
    if (!_initialized) {
      return;
    }
    unawaited(_play('playClick'));
  }

  Future<void> _play(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No-op in tests.
    } on PlatformException {
      // Never block the action because the optional sound failed.
    }
  }
}
