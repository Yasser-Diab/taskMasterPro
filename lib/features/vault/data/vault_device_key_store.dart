import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Stores a protected, device-bound way to recover a vault key.
///
/// The vault key itself is never written through Flutter secure storage.  The
/// Android encrypts it with a non-exportable Android Keystore key and binds
/// each unwrap to BiometricPrompt. Windows stores it through encrypted secure
/// storage (AES-GCM with its key in Windows Credential Manager) and requires a
/// fresh Windows Hello challenge before reading it. Unsupported platforms
/// return no remembered key; the privacy password remains the portable unlock.
class VaultDeviceKeyStore {
  static const _channel = MethodChannel('taskmasterpro/vault');
  static const _legacyStorage = FlutterSecureStorage();
  static const _windowsProtectedStorage = FlutterSecureStorage();
  static final _localAuthentication = LocalAuthentication();

  String _legacyKey(String userId) => 'taskmaster.vault.$userId.device_key';
  String _windowsProtectedKey(String userId) =>
      'taskmaster.vault.$userId.windows_hello_key.v1';

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
    if (Platform.isWindows) {
      if (!await _authenticateWindows(localizedReason)) return false;
      try {
        await _windowsProtectedStorage.write(
          key: _windowsProtectedKey(userId),
          value: base64UrlEncode(keyBytes),
        );
        return true;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }
    if (!Platform.isAndroid) return false;
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
    if (Platform.isWindows) {
      if (!await _authenticateWindows(localizedReason)) return null;
      try {
        final encoded = await _windowsProtectedStorage.read(
          key: _windowsProtectedKey(userId),
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
    if (!Platform.isAndroid) return null;
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
    if (Platform.isWindows) {
      try {
        return await _windowsProtectedStorage.containsKey(
          key: _windowsProtectedKey(userId),
        );
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }
    if (!Platform.isAndroid) return false;
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
    if (Platform.isWindows) {
      try {
        await _windowsProtectedStorage.delete(
          key: _windowsProtectedKey(userId),
        );
      } on PlatformException {
        // There is no usable remembered key when secure storage is absent.
      } on MissingPluginException {
        // Unit tests and unsupported Windows runners have no plugin bridge.
      }
      return;
    }
    if (!Platform.isAndroid) return;
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

  Future<bool> _authenticateWindows(String localizedReason) async {
    try {
      if (!await _localAuthentication.isDeviceSupported()) return false;
      return await _localAuthentication.authenticate(
        localizedReason: localizedReason,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
