import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract final class DeviceIdentity {
  static const _deviceIdKey = 'taskmaster.device_id';
  static const _deviceSequenceKey = 'taskmaster.device_sequence';
  static const _uuid = Uuid();
  static Future<String>? _installationIdFuture;
  static Future<void> _sequenceTail = Future<void>.value();

  /// Identifies this installation without tying it to an account.
  ///
  /// This value must never be sent as the synchronized `device_id` directly:
  /// the same installation can be used by more than one TaskMaster Pro
  /// account, while `account_devices.id` is globally unique.
  static Future<String> id() {
    return _installationIdFuture ??= _loadInstallationId();
  }

  static Future<String> _loadInstallationId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _uuid.v4();
    await preferences.setString(_deviceIdKey, created);
    return created;
  }

  /// Returns a stable, valid UUID for this installation and account pair.
  static Future<String> accountId(String userId) async {
    final installationId = await id();
    return _uuid.v5(
      Namespace.url.value,
      'https://taskmasterpro.app/device/$installationId/account/$userId',
    );
  }

  static Future<int> nextSequence(String userId) {
    final queued = _sequenceTail.then((_) => _allocateSequence(userId));
    _sequenceTail = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return queued;
  }

  static Future<int> _allocateSequence(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '$_deviceSequenceKey.$userId';
    final next = (preferences.getInt(key) ?? 0) + 1;
    await preferences.setInt(key, next);
    return next;
  }

  /// Retires the current installation identity after this device was revoked
  /// remotely. The revoked session cannot send another command, while a user
  /// who explicitly signs in again receives a new account-device record.
  ///
  /// The local task cache is deliberately left intact. On the next valid
  /// sign-in the sync service repairs pending commands to the new device ID,
  /// which preserves offline work without allowing the revoked session to
  /// resume silently.
  static Future<void> rotateAfterRemoteRevocation() async {
    await _sequenceTail;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_deviceIdKey);
    _installationIdFuture = null;
    final sequenceKeys = preferences
        .getKeys()
        .where((key) => key.startsWith('$_deviceSequenceKey.'))
        .toList(growable: false);
    for (final key in sequenceKeys) {
      await preferences.remove(key);
    }
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
