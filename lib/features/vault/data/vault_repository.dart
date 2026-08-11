import 'package:cryptography/cryptography.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import 'vault_crypto_service.dart';
import 'vault_device_key_store.dart';

class VaultItem {
  const VaultItem({
    required this.record,
    required this.name,
    required this.username,
    required this.password,
    required this.website,
    required this.notes,
    this.conflictingCopyOf,
  });

  final LocalEntityRecord record;
  final String name;
  final String username;
  final String password;
  final String website;
  final String notes;
  final String? conflictingCopyOf;
}

/// Ephemeral cleartext returned only after an explicit vault unlock and item
/// selection. It is never persisted, logged, or synchronized in this form.
class VaultAutofillCredential {
  const VaultAutofillCredential({
    required this.username,
    required this.password,
    required this.website,
  });

  final String username;
  final String password;
  final String website;
}

class VaultPreferences {
  const VaultPreferences({
    this.autoLockMinutes = 5,
    this.lockOnBackground = true,
    this.credentialSavingEnabled = true,
    this.autofillEnabled = true,
  });

  final int autoLockMinutes;
  final bool lockOnBackground;
  final bool credentialSavingEnabled;
  final bool autofillEnabled;

  Map<String, Object?> toJson() => {
    'auto_lock_minutes': autoLockMinutes,
    'lock_on_background': lockOnBackground,
    'credential_saving_enabled': credentialSavingEnabled,
    'autofill_enabled': autofillEnabled,
  };
}

class VaultRepository {
  VaultRepository(this.entities);

  final EntityRecordRepository entities;
  final crypto = VaultCryptoService();
  final _deviceKeyStore = VaultDeviceKeyStore();

  Stream<List<LocalEntityRecord>> watchVaults() =>
      entities.watch(entityType: 'user_vaults');

  Stream<List<LocalEntityRecord>> watchItems() =>
      entities.watch(entityType: 'vault_items');

  Future<LocalEntityRecord?> currentVault() async {
    final vaults = await entities.list(entityType: 'user_vaults');
    return vaults.firstOrNull;
  }

  Map<String, Object?> data(LocalEntityRecord record) =>
      entities.decode(record);

  VaultPreferences preferences(LocalEntityRecord vault) {
    final value = data(vault);
    final parameters = Map<String, Object?>.from(
      value['kdf_parameters'] as Map? ?? const {},
    );
    final settings = <String, Object?>{...value, ...parameters};
    return VaultPreferences(
      autoLockMinutes:
          (settings['auto_lock_minutes'] as num?)?.toInt().clamp(1, 60) ?? 5,
      lockOnBackground: settings['lock_on_background'] as bool? ?? true,
      credentialSavingEnabled:
          settings['credential_saving_enabled'] as bool? ?? true,
      autofillEnabled: settings['autofill_enabled'] as bool? ?? true,
    );
  }

  Future<SecretKey> createVault({required String password}) async {
    final material = await crypto.createKey(password);
    final encryptedVerifier = await crypto.createVerifier(material.key);
    final payload = <String, Object?>{
      'kdf_name': 'argon2id',
      'kdf_parameters': {
        ...material.kdfParameters,
        ...const VaultPreferences().toJson(),
      },
      'encrypted_verifier': encryptedVerifier,
      'vault_version': 1,
      'locked_at': null,
      ...const VaultPreferences().toJson(),
    };
    await entities.create(
      EntityRecordDraft(
        entityType: 'user_vaults',
        title: 'Protected vault',
        status: 'available',
        data: payload,
        syncPayload: payload,
      ),
    );
    return material.key;
  }

  Future<SecretKey?> unlockWithPassword(
    LocalEntityRecord vault,
    String password,
  ) async {
    final value = data(vault);
    final parameters = Map<String, Object?>.from(
      value['kdf_parameters'] as Map? ?? const {},
    );
    final key = await crypto.unlockKey(password, parameters);
    final valid = await crypto.verify(
      value['encrypted_verifier'] as String? ?? '',
      key,
    );
    return valid ? key : null;
  }

  Future<bool> rememberKey(
    SecretKey key, {
    required String localizedReason,
  }) async {
    final bytes = await key.extractBytes();
    try {
      return await _deviceKeyStore.store(
        userId: entities.userId,
        keyBytes: bytes,
        localizedReason: localizedReason,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<SecretKey?> unlockWithDevice({required String localizedReason}) async {
    final bytes = await _deviceKeyStore.unlock(
      userId: entities.userId,
      localizedReason: localizedReason,
    );
    return bytes == null ? null : SecretKey(bytes);
  }

  Future<bool> hasRememberedKey() =>
      _deviceKeyStore.hasWrappedKey(userId: entities.userId);

  Future<void> clearRememberedKey() =>
      _deviceKeyStore.clear(userId: entities.userId);

  Future<LocalEntityRecord?> updatePreferences(
    LocalEntityRecord vault,
    VaultPreferences preferences,
  ) async {
    final current = data(vault);
    final parameters = Map<String, Object?>.from(
      current['kdf_parameters'] as Map? ?? const {},
    );
    final payload = <String, Object?>{
      ...current,
      'kdf_parameters': {...parameters, ...preferences.toJson()},
      ...preferences.toJson(),
    };
    await entities.update(vault, data: payload, syncPayload: payload);
    return entities.get(vault.id);
  }

  Future<SecretKey?> changePassword({
    required LocalEntityRecord vault,
    required String currentPassword,
    required String newPassword,
  }) async {
    final currentKey = await unlockWithPassword(vault, currentPassword);
    if (currentKey == null) return null;

    // Invalidate the old device-bound wrapper before changing any ciphertext.
    // If re-encryption fails, the safe recovery path is the privacy password,
    // never an old wrapper for a potentially stale vault key.
    await clearRememberedKey();

    final records = await entities.list(entityType: 'vault_items');
    final clearItems = <LocalEntityRecord, Map<String, dynamic>>{};
    for (final record in records) {
      final row = data(record);
      clearItems[record] = await crypto.decryptJson(
        row['ciphertext'] as String,
        currentKey,
      );
    }

    final material = await crypto.createKey(newPassword);
    for (final entry in clearItems.entries) {
      final encrypted = await crypto.encryptJson(entry.value, material.key);
      final current = data(entry.key);
      final payload = <String, Object?>{
        ...current,
        'ciphertext': encrypted.ciphertext,
        'nonce': encrypted.nonce,
        'item_revision':
            ((current['item_revision'] as num?)?.toInt() ??
                entry.key.revision) +
            1,
      };
      await entities.update(entry.key, data: payload, syncPayload: payload);
    }

    final vaultPayload = <String, Object?>{
      ...data(vault),
      'kdf_name': 'argon2id',
      'kdf_parameters': {
        ...material.kdfParameters,
        ...preferences(vault).toJson(),
      },
      'encrypted_verifier': await crypto.createVerifier(material.key),
      'vault_version': 1,
    };
    await entities.update(vault, data: vaultPayload, syncPayload: vaultPayload);
    return material.key;
  }

  Future<List<VaultItem>> decryptItems(SecretKey key) async {
    final records = await entities.list(entityType: 'vault_items');
    final items = <VaultItem>[];
    for (final record in records) {
      try {
        final row = data(record);
        final clear = await crypto.decryptJson(
          row['ciphertext'] as String,
          key,
        );
        items.add(
          VaultItem(
            record: record,
            name: clear['name'] as String? ?? 'Saved account',
            username: clear['username'] as String? ?? '',
            password: clear['password'] as String? ?? '',
            website: clear['website'] as String? ?? '',
            notes: clear['notes'] as String? ?? '',
            conflictingCopyOf: row['conflicting_copy_of'] as String?,
          ),
        );
      } catch (_) {
        // A record encrypted with a conflicting key remains preserved and can
        // be reviewed after the correct recovery key is supplied.
      }
    }
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  Future<void> saveItem({
    required String vaultId,
    required SecretKey key,
    LocalEntityRecord? existing,
    required String name,
    required String username,
    required String password,
    required String website,
    required String notes,
  }) async {
    final encrypted = await crypto.encryptJson({
      'name': name.trim(),
      'username': username,
      'password': password,
      'website': website.trim(),
      'notes': notes,
    }, key);
    final payload = <String, Object?>{
      'vault_id': vaultId,
      'ciphertext': encrypted.ciphertext,
      'nonce': encrypted.nonce,
      'encrypted_metadata': null,
      'item_revision': existing == null ? 1 : existing.revision + 1,
      'conflicting_copy_of': null,
    };
    if (existing == null) {
      await entities.create(
        EntityRecordDraft(
          entityType: 'vault_items',
          title: 'Protected account',
          status: 'active',
          data: payload,
          syncPayload: payload,
        ),
      );
    } else {
      await entities.update(existing, data: payload, syncPayload: payload);
    }
  }

  Future<void> deleteItem(LocalEntityRecord record) =>
      entities.softDelete(record);
}
