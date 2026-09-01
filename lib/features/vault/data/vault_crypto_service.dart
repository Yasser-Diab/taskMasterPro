import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class VaultKeyMaterial {
  const VaultKeyMaterial({
    required this.key,
    required this.salt,
    required this.kdfParameters,
  });

  final SecretKey key;
  final List<int> salt;
  final Map<String, Object?> kdfParameters;
}

class VaultCiphertext {
  const VaultCiphertext({required this.ciphertext, required this.nonce});

  final String ciphertext;
  final String nonce;
}

class VaultCryptoService {
  static final _cipher = Xchacha20.poly1305Aead();
  static final _random = Random.secure();
  // Immutable encrypted-format identity. Renaming it would make existing
  // DayVector users' vault passwords appear invalid after the brand upgrade.
  static const _verifier = 'TaskMaster Pro Password Vault v1';

  Future<VaultKeyMaterial> createKey(String password) async {
    final salt = _randomBytes(16);
    final parameters = <String, Object?>{
      'salt': base64UrlEncode(salt),
      'memory': 19456,
      'iterations': 2,
      'parallelism': 1,
      'hash_length': 32,
    };
    return VaultKeyMaterial(
      key: await _derive(password, parameters),
      salt: salt,
      kdfParameters: parameters,
    );
  }

  Future<SecretKey> unlockKey(
    String password,
    Map<String, Object?> parameters,
  ) {
    return _derive(password, parameters);
  }

  Future<String> createVerifier(SecretKey key) async {
    final encrypted = await encryptString(_verifier, key);
    return encrypted.ciphertext;
  }

  Future<bool> verify(String encryptedVerifier, SecretKey key) async {
    try {
      return await decryptString(encryptedVerifier, key) == _verifier;
    } catch (_) {
      return false;
    }
  }

  Future<VaultCiphertext> encryptJson(
    Map<String, Object?> value,
    SecretKey key,
  ) {
    return encryptString(jsonEncode(value), key);
  }

  Future<Map<String, dynamic>> decryptJson(
    String ciphertext,
    SecretKey key,
  ) async {
    final decoded = jsonDecode(await decryptString(ciphertext, key));
    if (decoded is! Map) throw const FormatException('Invalid vault item');
    return Map<String, dynamic>.from(decoded);
  }

  Future<VaultCiphertext> encryptString(String value, SecretKey key) async {
    final nonce = _randomBytes(_cipher.nonceLength);
    final box = await _cipher.encrypt(
      utf8.encode(value),
      secretKey: key,
      nonce: nonce,
    );
    return VaultCiphertext(
      ciphertext: base64UrlEncode(box.concatenation(nonce: true, mac: true)),
      nonce: base64UrlEncode(nonce),
    );
  }

  Future<String> decryptString(String value, SecretKey key) async {
    final combined = base64Url.decode(value);
    final box = SecretBox.fromConcatenation(
      combined,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
    );
    return utf8.decode(await _cipher.decrypt(box, secretKey: key));
  }

  Future<SecretKey> _derive(
    String password,
    Map<String, Object?> parameters,
  ) async {
    final salt = base64Url.decode(parameters['salt'] as String);
    final algorithm = Argon2id(
      parallelism: (parameters['parallelism'] as num?)?.toInt() ?? 1,
      memory: (parameters['memory'] as num?)?.toInt() ?? 19456,
      iterations: (parameters['iterations'] as num?)?.toInt() ?? 2,
      hashLength: (parameters['hash_length'] as num?)?.toInt() ?? 32,
    );
    return algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int count) =>
      Uint8List.fromList(List.generate(count, (_) => _random.nextInt(256)));
}
