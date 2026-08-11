import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/config/backend_target_cutover.dart';
import 'package:taskmaster_pro/core/config/supabase_config.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';

void main() {
  group('clean Supabase target cutover', () {
    test('uses the new public target and project-scoped local namespaces', () {
      const account = '0aaee13a-9c58-4dee-bd5b-488bd6cc6712';

      expect(
        SupabaseConfig.url,
        'https://${SupabaseConfig.projectRef}.supabase.co',
      );
      expect(SupabaseConfig.publishableKey, startsWith('sb_publishable_'));
      expect(
        localDatabaseNameForAccount(account),
        'taskmaster_${SupabaseConfig.projectRef}_$account',
      );
      expect(
        localDatabaseNameForAccount(
          account,
          projectRef: 'iejbogkqknldxoyepvun',
        ),
        isNot(localDatabaseNameForAccount(account)),
      );
    });

    test(
      'mismatch stops workers, cancels alarms and clears only auth keys',
      () async {
        const oldProject = 'iejbogkqknldxoyepvun';
        const newProject = 'tmvarulrujkmibqpqoeo';
        final store = _MemoryBackendTargetStore({
          backendProjectMarkerPreferenceKey: oldProject,
          BackendTargetCutover.sessionStorageKeyForProject(oldProject):
              'old-session',
          BackendTargetCutover.sessionStorageKeyForProject(newProject):
              'accidental-new-session',
          BackendTargetCutover.pkceStorageKeyForProject(oldProject): 'old-pkce',
          BackendTargetCutover.pkceStorageKeyForProject(newProject): 'new-pkce',
          legacyPkceVerifierStorageKey: 'legacy-pkce',
          'unrelated.setting': 'keep-me',
        });
        final events = <String>[];

        final result =
            await BackendTargetCutover(
              targetProjectRef: newProject,
              legacyProjectRefs: const {oldProject},
              store: store,
            ).prepare(
              stopSync: () async => events.add('sync-stopped'),
              cancelNotifications: () async =>
                  events.add('notifications-cancelled'),
            );

        expect(events, ['sync-stopped', 'notifications-cancelled']);
        expect(result.targetChanged, isTrue);
        expect(result.previousProjectRef, oldProject);
        expect(store.values[backendProjectMarkerPreferenceKey], newProject);
        expect(
          store.values.containsKey(
            BackendTargetCutover.sessionStorageKeyForProject(oldProject),
          ),
          isFalse,
        );
        expect(
          store.values.containsKey(
            BackendTargetCutover.sessionStorageKeyForProject(newProject),
          ),
          isFalse,
        );
        expect(store.values.containsKey(legacyPkceVerifierStorageKey), isFalse);
        expect(store.values['unrelated.setting'], 'keep-me');
      },
    );

    test(
      'a matching project does not disrupt the active local session',
      () async {
        const project = 'tmvarulrujkmibqpqoeo';
        final sessionKey = BackendTargetCutover.sessionStorageKeyForProject(
          project,
        );
        final store = _MemoryBackendTargetStore({
          backendProjectMarkerPreferenceKey: project,
          sessionKey: 'current-session',
        });
        var stopped = false;
        var notificationsCancelled = false;

        final result =
            await BackendTargetCutover(
              targetProjectRef: project,
              legacyProjectRefs: const {'iejbogkqknldxoyepvun'},
              store: store,
            ).prepare(
              stopSync: () async => stopped = true,
              cancelNotifications: () async => notificationsCancelled = true,
            );

        expect(result.targetChanged, isFalse);
        expect(stopped, isFalse);
        expect(notificationsCancelled, isFalse);
        expect(store.values[sessionKey], 'current-session');
      },
    );

    test('PKCE verifier storage is project scoped', () async {
      const oldProject = 'iejbogkqknldxoyepvun';
      const newProject = 'tmvarulrujkmibqpqoeo';
      final store = _MemoryBackendTargetStore();
      final oldStorage = ProjectScopedGotrueAsyncStorage(
        store: store,
        projectRef: oldProject,
      );
      final newStorage = ProjectScopedGotrueAsyncStorage(
        store: store,
        projectRef: newProject,
      );

      await oldStorage.setItem(
        key: legacyPkceVerifierStorageKey,
        value: 'old-verifier',
      );

      expect(
        await newStorage.getItem(key: legacyPkceVerifierStorageKey),
        isNull,
      );
      expect(
        await oldStorage.getItem(key: legacyPkceVerifierStorageKey),
        'old-verifier',
      );
    });
  });
}

class _MemoryBackendTargetStore implements BackendTargetStore {
  _MemoryBackendTargetStore([Map<String, String>? initial])
    : values = <String, String>{...?initial};

  final Map<String, String> values;

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> writeString(String key, String value) async {
    values[key] = value;
  }
}
