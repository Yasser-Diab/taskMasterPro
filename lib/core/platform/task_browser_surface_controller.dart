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

  static Future<void> destroyAll() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isAndroid)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('destroy');
    } on Object {
      // The native browser surface is optional; a failed release must not block UI.
    }
  }

  static Future<void> destroy({required String browserId}) async {
    if (kIsWeb || !(Platform.isWindows || Platform.isAndroid)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('destroy', {'browserId': browserId});
    } on Object {
      // The native browser surface is optional; a failed release must not block UI.
    }
  }
}
