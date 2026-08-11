import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/data/entity_record_repository.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/task_resource_service.dart';
import 'package:taskmaster_pro/features/tasks/domain/browser_handoff.dart';
import 'package:taskmaster_pro/features/vault/data/vault_crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('browser address handoff opens URLs and encodes search text', () {
    expect(
      normalizeBrowserAddress('freecodecamp.org/learn'),
      'https://freecodecamp.org/learn',
    );
    expect(
      normalizeBrowserAddress('JavaScript closures'),
      'https://www.google.com/search?q=JavaScript+closures',
    );
    final scriptPaste = normalizeBrowserAddress('javascript:alert(1)');
    expect(scriptPaste, startsWith('https://www.google.com/search?'));
    expect(Uri.parse(scriptPaste).queryParameters['q'], 'javascript:alert(1)');
  });

  test(
    'task URL resources are strict, canonical, and task-retrievable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
      );
      final entities = EntityRecordRepository(database, client);
      final resources = TaskResourceService(entities: entities, client: client);

      await resources.addUrl(
        taskId: 'task-free-code-camp',
        title: 'freeCodeCamp curriculum',
        url: 'www.freecodecamp.org/learn',
      );

      final rows = await entities.list(
        entityType: 'task_resources',
        parentId: 'task-free-code-camp',
      );
      expect(rows, hasLength(1));
      final data = entities.decode(rows.single);
      expect(data['resource_type'], 'url');
      expect(data['storage_location'], 'url');
      expect(data['url'], 'https://www.freecodecamp.org/learn');
      expect(
        taskWebsiteResourceUrl(const {
          'resource_type': 'website',
          'storage_path': 'https://academy.hsoub.com/',
        }),
        'https://academy.hsoub.com/',
      );
      expect(isTaskWebsiteResourceType('url'), isTrue);
      expect(isTaskWebsiteResourceType('website'), isTrue);
      expect(isTaskWebsiteResourceType('file'), isFalse);
      expect(
        () => normalizeTaskResourceUrl('javascript:alert(1)'),
        throwsFormatException,
      );

      final beforeRevision = rows.single.revision;
      final beforeCommands = await database
          .select(database.localOutboxCommands)
          .get();
      await entities.updateLocalData(
        rows.single,
        data: {
          ...data,
          'open_count': 1,
          'last_opened_at': DateTime.utc(2026, 7, 28).toIso8601String(),
        },
      );
      final locallyObserved = await entities.get(rows.single.id);
      final afterCommands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(locallyObserved?.revision, beforeRevision);
      expect(afterCommands, hasLength(beforeCommands.length));
      expect(entities.decode(locallyObserved!)['open_count'], 1);
    },
  );

  test('vault handoff requires an exact website host', () {
    expect(
      websiteMatchesForCredential(
        savedWebsite: 'https://www.duolingo.com/learn',
        pageUrl: 'https://duolingo.com/log-in',
      ),
      isTrue,
    );
    expect(
      websiteMatchesForCredential(
        savedWebsite: 'https://accounts.example.com',
        pageUrl: 'https://example.com',
      ),
      isFalse,
    );
    expect(
      websiteMatchesForCredential(
        savedWebsite: 'https://freecodecamp.org',
        pageUrl: 'https://freecodecamp.org.evil.example/login',
      ),
      isFalse,
    );
  });

  test('explicit fill script changes fields without submitting or storing', () {
    const username = 'qa@example.test';
    const password = r'''dummy-"'\-password''';
    final script = buildCredentialFillScript(
      username: username,
      password: password,
    );

    expect(script, contains(jsonEncode(username)));
    expect(script, contains(jsonEncode(password)));
    expect(script, contains("new Event('input'"));
    expect(script, isNot(contains('.submit(')));
    expect(script, isNot(contains('localStorage')));
    expect(script, isNot(contains('sessionStorage')));
  });

  test('vault test credential remains encrypted at rest', () async {
    final crypto = VaultCryptoService();
    final material = await crypto.createKey('temporary QA vault password');
    final encrypted = await crypto.encryptJson(const {
      'username': 'qa-user@example.test',
      'password': 'temporary-only-password',
      'website': 'https://example.test',
    }, material.key);

    expect(encrypted.ciphertext, isNot(contains('qa-user@example.test')));
    expect(encrypted.ciphertext, isNot(contains('temporary-only-password')));
    final decoded = await crypto.decryptJson(
      encrypted.ciphertext,
      material.key,
    );
    expect(decoded['username'], 'qa-user@example.test');
    expect(decoded['website'], 'https://example.test');
  });
}
