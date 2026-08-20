import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/vault/data/vault_device_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unsupported platforms never retain a fallback vault key', () async {
    final store = VaultDeviceKeyStore();

    expect(await store.hasWrappedKey(userId: 'test-owner'), isFalse);
    expect(
      await store.store(
        userId: 'test-owner',
        keyBytes: List<int>.filled(32, 7),
        localizedReason: 'Test vault device authentication',
      ),
      isFalse,
    );
    expect(
      await store.unlock(
        userId: 'test-owner',
        localizedReason: 'Test vault device authentication',
      ),
      isNull,
    );
  });

  test('vault key persistence is platform protected rather than raw', () {
    final repository = File(
      'lib/features/vault/data/vault_repository.dart',
    ).readAsStringSync();
    final bridge = File(
      'lib/features/vault/data/vault_device_key_store.dart',
    ).readAsStringSync();
    final android = File(
      'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/MainActivity.kt',
    ).readAsStringSync();

    expect(repository, contains('VaultDeviceKeyStore'));
    expect(repository, isNot(contains('FlutterSecureStorage')));
    expect(repository, isNot(contains('LocalAuthentication')));
    expect(bridge, contains('storeWrappedVaultKey'));
    expect(bridge, isNot(contains('_legacyStorage.write')));
    expect(bridge, isNot(contains('_legacyStorage.read')));
    expect(bridge, contains('Platform.isWindows'));
    expect(bridge, contains('_windowsProtectedStorage.write'));
    expect(bridge, contains('_localAuthentication.authenticate'));
    expect(bridge, contains('sensitiveTransaction: true'));
    expect(bridge, contains('Windows Credential Manager'));
    expect(android, contains('AndroidKeyStore'));
    expect(android, contains('AES/GCM/NoPadding'));
    expect(android, contains('KeyProperties.AUTH_BIOMETRIC_STRONG'));
    expect(android, contains('BiometricPrompt.CryptoObject(cipher)'));
  });

  test('profile header is a single clean edit target', () {
    final source = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('class _ProfileCard');
    final end = source.indexOf('class _EmailChangeDialog');
    final header = source.substring(start, end);

    expect(header, contains('onTap: editProfile'));
    expect(header, isNot(contains('heightCm')));
    expect(header, isNot(contains('genderIdentity')));
    expect(header, isNot(contains('_EditableEmailPill')));
    expect(header, isNot(contains('Icons.edit_outlined')));
  });
}
