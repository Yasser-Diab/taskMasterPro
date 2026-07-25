import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract final class DeviceIdentity {
  static const _deviceIdKey = 'taskmaster.device_id';
  static const _deviceSequenceKey = 'taskmaster.device_sequence';
  static const _uuid = Uuid();

  static Future<String> id() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _uuid.v4();
    await preferences.setString(_deviceIdKey, created);
    return created;
  }

  static Future<int> nextSequence() async {
    final preferences = await SharedPreferences.getInstance();
    final next = (preferences.getInt(_deviceSequenceKey) ?? 0) + 1;
    await preferences.setInt(_deviceSequenceKey, next);
    return next;
  }

  static String get platform {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  static String get displayName {
    if (Platform.isWindows) return 'Windows device';
    if (Platform.isAndroid) return 'Android device';
    return 'TaskMaster Pro device';
  }
}
