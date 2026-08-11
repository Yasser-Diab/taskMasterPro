import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/supabase_config.dart';

/// The result of the first Android capability review.
///
/// This is deliberately device-local. Android grants notifications, usage
/// access, Bluetooth access and exact-alarm access to an individual app on an
/// individual device, so copying a completed review to another phone would
/// incorrectly hide that phone's consent flow. The preference key still
/// includes both the backend project and authenticated user so a backend
/// cutover or account switch can never inherit the previous user's decision.
enum AndroidPermissionSetupOutcome { completed, skipped }

class AndroidPermissionSetupRecord {
  const AndroidPermissionSetupRecord({
    required this.outcome,
    required this.reviewedAt,
    required this.capabilityStates,
  });

  final AndroidPermissionSetupOutcome outcome;
  final DateTime reviewedAt;

  /// A diagnostic snapshot only. It is not a permission authority: each
  /// screen rechecks Android before it uses a sensitive capability.
  final Map<String, String> capabilityStates;

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'reviewed_at': reviewedAt.toUtc().toIso8601String(),
    'capability_states': capabilityStates,
  };

  static AndroidPermissionSetupRecord? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final value = Map<Object?, Object?>.from(decoded);
      final outcome = switch (value['outcome']) {
        'completed' => AndroidPermissionSetupOutcome.completed,
        'skipped' => AndroidPermissionSetupOutcome.skipped,
        _ => null,
      };
      final reviewedAt = DateTime.tryParse(
        '${value['reviewed_at'] ?? ''}',
      )?.toUtc();
      if (outcome == null || reviewedAt == null) return null;
      final states = value['capability_states'];
      return AndroidPermissionSetupRecord(
        outcome: outcome,
        reviewedAt: reviewedAt,
        capabilityStates: states is Map
            ? Map.unmodifiable(
                states.map((key, item) => MapEntry('$key', '$item')),
              )
            : const <String, String>{},
      );
    } on FormatException {
      return null;
    }
  }
}

abstract interface class AndroidPermissionSetupStore {
  Future<AndroidPermissionSetupRecord?> read({required String userId});

  Future<void> write({
    required String userId,
    required AndroidPermissionSetupRecord record,
  });

  Future<void> clear({required String userId});
}

class SharedPreferencesAndroidPermissionSetupStore
    implements AndroidPermissionSetupStore {
  SharedPreferencesAndroidPermissionSetupStore(this._preferences);

  final SharedPreferences _preferences;

  static Future<SharedPreferencesAndroidPermissionSetupStore> open() async =>
      SharedPreferencesAndroidPermissionSetupStore(
        await SharedPreferences.getInstance(),
      );

  /// This must remain project- and user-scoped. It represents the local
  /// device's Android consent review, not a server-synchronized preference.
  static String storageKeyFor({
    required String userId,
    String projectRef = SupabaseConfig.projectRef,
  }) => 'taskmaster.android_permission_setup.v1:$projectRef:$userId';

  @override
  Future<AndroidPermissionSetupRecord?> read({required String userId}) async =>
      AndroidPermissionSetupRecord.tryParse(
        _preferences.getString(storageKeyFor(userId: userId)),
      );

  @override
  Future<void> write({
    required String userId,
    required AndroidPermissionSetupRecord record,
  }) async {
    await _preferences.setString(
      storageKeyFor(userId: userId),
      jsonEncode(record.toJson()),
    );
  }

  @override
  Future<void> clear({required String userId}) async {
    await _preferences.remove(storageKeyFor(userId: userId));
  }
}
