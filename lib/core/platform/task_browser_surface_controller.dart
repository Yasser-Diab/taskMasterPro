import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TaskBrowserSurfaceController {
  const TaskBrowserSurfaceController._();

  static const _channel = MethodChannel('taskmasterpro/task_browser');

  static Future<void> hideAll() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isAndroid)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('hide');
    } on Object {
      // The native browser surface is optional; a failed hide must not block UI.
    }
  }
}
