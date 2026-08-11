import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The marker is deliberately independent from any account. It describes the
/// backend that owns this installation's currently active local namespace.
/// It is never sent to Supabase.
const backendProjectMarkerPreferenceKey = 'taskmaster.backend.project_ref.v1';

/// GoTrue's default PKCE verifier was historically global to the application.
/// A project switch must not let a verifier created for one backend complete a
/// sign-in on another backend.
const legacyPkceVerifierStorageKey = 'supabase.auth.token-code-verifier';

/// A minimal asynchronous key-value contract makes the cutover behaviour
/// deterministic in tests and avoids deleting unrelated application settings.
abstract interface class BackendTargetStore {
  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesBackendTargetStore implements BackendTargetStore {
  SharedPreferencesBackendTargetStore(this._preferences);

  final SharedPreferences _preferences;

  static Future<SharedPreferencesBackendTargetStore> open() async =>
      SharedPreferencesBackendTargetStore(
        await SharedPreferences.getInstance(),
      );

  @override
  Future<String?> readString(String key) async => _preferences.getString(key);

  @override
  Future<void> writeString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}

/// Project-scoped PKCE storage. Supabase's built-in session storage already
/// includes the project reference in its default key, but its default PKCE
/// verifier did not. Keeping both scopes explicit makes a target cutover
/// fail closed before any network request can use an old credential.
class ProjectScopedGotrueAsyncStorage extends GotrueAsyncStorage {
  ProjectScopedGotrueAsyncStorage({
    required this.store,
    required this.projectRef,
  });

  final BackendTargetStore store;
  final String projectRef;

  String _scopedKey(String key) => 'taskmaster.auth.$projectRef:$key';

  @override
  Future<String?> getItem({required String key}) =>
      store.readString(_scopedKey(key));

  @override
  Future<void> removeItem({required String key}) =>
      store.remove(_scopedKey(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      store.writeString(_scopedKey(key), value);
}

class BackendTargetCutoverResult {
  const BackendTargetCutoverResult({
    required this.targetChanged,
    required this.previousProjectRef,
    required this.clearedStorageKeys,
  });

  final bool targetChanged;
  final String? previousProjectRef;
  final Set<String> clearedStorageKeys;
}

/// Moves an installation to a different Supabase project without ever opening
/// the prior project's local database or replaying its outbox.
///
/// The old database is deliberately not deleted. Project-scoped database names
/// quarantine it in place for recovery/audit; only stale local auth material
/// and scheduled notifications are cleared. This runs before Supabase is
/// initialized, so it does not create egress on either project.
class BackendTargetCutover {
  BackendTargetCutover({
    required this.targetProjectRef,
    required this.legacyProjectRefs,
    required this.store,
  });

  final String targetProjectRef;
  final Set<String> legacyProjectRefs;
  final BackendTargetStore store;

  static String sessionStorageKeyForProject(String projectRef) =>
      'sb-$projectRef-auth-token';

  static String pkceStorageKeyForProject(String projectRef) =>
      'taskmaster.auth.$projectRef:$legacyPkceVerifierStorageKey';

  Future<BackendTargetCutoverResult> prepare({
    required Future<void> Function() stopSync,
    required Future<void> Function() cancelNotifications,
  }) async {
    final previousProjectRef = await store.readString(
      backendProjectMarkerPreferenceKey,
    );
    if (previousProjectRef == targetProjectRef) {
      return const BackendTargetCutoverResult(
        targetChanged: false,
        previousProjectRef: null,
        clearedStorageKeys: <String>{},
      );
    }

    // Do this before storage changes. It prevents an in-process realtime
    // handler or outbox worker from observing a transition half way through.
    await stopSync();
    await cancelNotifications();

    final projectRefs = <String>{
      targetProjectRef,
      ...legacyProjectRefs,
      if (previousProjectRef != null && previousProjectRef.isNotEmpty)
        previousProjectRef,
    };
    final keysToClear = <String>{
      legacyPkceVerifierStorageKey,
      for (final projectRef in projectRefs)
        sessionStorageKeyForProject(projectRef),
      for (final projectRef in projectRefs)
        pkceStorageKeyForProject(projectRef),
    };

    for (final key in keysToClear) {
      await store.remove(key);
    }
    await store.writeString(
      backendProjectMarkerPreferenceKey,
      targetProjectRef,
    );

    return BackendTargetCutoverResult(
      targetChanged: true,
      previousProjectRef: previousProjectRef,
      clearedStorageKeys: Set.unmodifiable(keysToClear),
    );
  }
}
