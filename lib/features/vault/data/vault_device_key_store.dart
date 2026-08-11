import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores an *encrypted wrapper* for a vault key on Android.
///
/// The vault key itself is never written through Flutter secure storage.  The
/// Android implementation encrypts it with a non-exportable Android Keystore
/// key and requires an interactive biometric prompt before each unwrap.
/// Unsupported platforms simply return no remembered key; the privacy
/// password remains the portable way to unlock a synchronized vault.
class VaultDeviceKeyStore {
  static const _channel = MethodChannel('taskmasterpro/vault');
  static const _legacyStorage = FlutterSecureStorage();

  String _legacyKey(String userId) => 'taskmaster.vault.$userId.device_key';

  /// Removes the v0.0.27 raw-key entry without ever reading its value.
  ///
  /// A user who previously opted into device unlock must enter the privacy
  /// password once, then opt in again to create the Keystore-wrapped entry.
  Future<void> _clearLegacyRawKey(String userId) async {
    try {
      await _legacyStorage.delete(key: _legacyKey(userId));
    } on PlatformException {
      // The migration is best effort on a platform without the old storage.
    } on MissingPluginException {
      // Unit tests and unsupported platforms have no secure-storage bridge.
    }
  }

  Future<bool> store({
    required String userId,
    required List<int> keyBytes,
    required String localizedReason,
  }) async {
    if (keyBytes.length != 32) return false;
    await _clearLegacyRawKey(userId);
    try {
      return await _channel.invokeMethod<bool>('storeWrappedVaultKey', {
            'userId': userId,
            'key': base64UrlEncode(keyBytes),
            'localizedReason': localizedReason,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Uint8List?> unlock({
    required String userId,
    required String localizedReason,
  }) async {
    await _clearLegacyRawKey(userId);
    try {
      final encoded = await _channel.invokeMethod<String>(
        'unlockWrappedVaultKey',
        {'userId': userId, 'localizedReason': localizedReason},
      );
      if (encoded == null) return null;
      final key = Uint8List.fromList(base64Url.decode(encoded));
      return key.length == 32 ? key : null;
    } on FormatException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> hasWrappedKey({required String userId}) async {
    await _clearLegacyRawKey(userId);
    try {
      return await _channel.invokeMethod<bool>('hasWrappedVaultKey', {
            'userId': userId,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> clear({required String userId}) async {
    await _clearLegacyRawKey(userId);
    try {
      await _channel.invokeMethod<void>('clearWrappedVaultKey', {
        'userId': userId,
      });
    } on PlatformException {
      // There is no usable remembered key when the platform bridge is absent.
    } on MissingPluginException {
      // As above; unsupported platforms always require the privacy password.
    }
  }
}
