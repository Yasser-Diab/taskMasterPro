import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptedCyclePayload {
  const EncryptedCyclePayload({required this.ciphertext, required this.nonce});

  final String ciphertext;
  final String nonce;
}

class CycleCryptoService {
  CycleCryptoService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _cipher = AesGcm.with256bits();
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );

  String _storageKey(String userId) => 'taskmaster-cycle-key-$userId';

  Future<bool> hasKey(String userId) async {
    return (await _storage.read(key: _storageKey(userId))) != null;
  }

  Future<void> setPassphrase({
    required String userId,
    required String passphrase,
  }) async {
    if (passphrase.length < 10) {
      throw ArgumentError('Use at least 10 characters for the passphrase');
    }
    final key = await _deriveKey(userId, passphrase);
    final bytes = await key.extractBytes();
    await _storage.write(
      key: _storageKey(userId),
      value: base64UrlEncode(bytes),
    );
  }

  Future<void> removeKey(String userId) {
    return _storage.delete(key: _storageKey(userId));
  }

  Future<EncryptedCyclePayload> encrypt({
    required String userId,
    required Map<String, Object?> data,
  }) async {
    final key = await _readKey(userId);
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
      nonce: nonce,
    );
    return EncryptedCyclePayload(
      ciphertext: jsonEncode({
        'v': 1,
        'ciphertext': base64UrlEncode(box.cipherText),
        'mac': base64UrlEncode(box.mac.bytes),
      }),
      nonce: base64UrlEncode(box.nonce),
    );
  }

  Future<Map<String, Object?>> decrypt({
    required String userId,
    required String ciphertext,
    required String nonce,
  }) async {
    final key = await _readKey(userId);
    final envelope = Map<String, Object?>.from(jsonDecode(ciphertext) as Map);
    final clearText = await _cipher.decrypt(
      SecretBox(
        base64Url.decode(envelope['ciphertext']! as String),
        nonce: base64Url.decode(nonce),
        mac: Mac(base64Url.decode(envelope['mac']! as String)),
      ),
      secretKey: key,
    );
    return Map<String, Object?>.from(jsonDecode(utf8.decode(clearText)) as Map);
  }

  Future<SecretKey> _deriveKey(String userId, String passphrase) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      // Immutable cryptographic context retained across the public rename.
      nonce: utf8.encode('TaskMaster Pro cycle data $userId'),
    );
  }

  Future<SecretKey> _readKey(String userId) async {
    final stored = await _storage.read(key: _storageKey(userId));
    if (stored == null) {
      throw StateError('Cycle encryption passphrase is required');
    }
    return SecretKey(base64Url.decode(stored));
  }
}
