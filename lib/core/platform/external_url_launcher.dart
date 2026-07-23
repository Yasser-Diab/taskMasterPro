import 'package:flutter/services.dart';

class ExternalUrlLauncher {
  ExternalUrlLauncher._();

  static const _channel = MethodChannel('taskmasterpro/task_browser');

  static Future<void> open(String url) async {
    await _channel.invokeMethod<void>('openExternal', {'url': url});
  }
}
