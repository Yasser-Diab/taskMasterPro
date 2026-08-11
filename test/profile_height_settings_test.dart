import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/settings/data/settings_repository.dart';
import 'package:taskmaster_pro/features/settings/data/settings_section_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'profile height persists locally and is queued for synchronization',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SettingsRepository(database);
      const user = User(
        id: 'height-user',
        appMetadata: {},
        userMetadata: {'display_name': 'Height owner'},
        aud: 'authenticated',
        email: 'height@example.com',
        createdAt: '2026-07-28T00:00:00Z',
      );

      await repository.ensureLocalAccount(user);
      await repository.updateProfile(
        userId: user.id,
        displayName: 'Height owner',
        heightCm: 178.5,
      );

      final profile = await database.select(database.localProfiles).getSingle();
      final command = await database
          .select(database.localOutboxCommands)
          .getSingle();
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;

      expect(profile.heightCm, 178.5);
      expect(payload['height_cm'], 178.5);
      expect(command.entityType, 'profiles');
    },
  );

  test('settings areas stay in the required reader-facing order', () {
    expect(settingsSectionOrderKeys, const [
      'profile_and_account',
      'schedule_wellbeing',
      'tasks_and_execution',
      'pomodoro',
      'activity_and_privacy',
      'notifications_and_sounds',
      'health',
      'coaching',
      'reports',
      'appearance',
      'synchronization',
      'connected_devices',
      'help_and_diagnostics',
      'about_and_legal',
    ]);

    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      expect(l10n.text('height_cm'), isNot(contains('height_cm')));
      for (final key in settingsSectionOrderKeys) {
        expect(l10n.text(key), isNot(contains('⟦')));
      }
    }
  });

  test('profile repository rejects an impossible height', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SettingsRepository(database);
    const user = User(
      id: 'invalid-height-user',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-07-28T00:00:00Z',
    );
    await repository.ensureLocalAccount(user);

    await expectLater(
      repository.updateProfile(
        userId: user.id,
        displayName: 'Profile',
        heightCm: 420,
      ),
      throwsArgumentError,
    );

    expect(await database.select(database.localOutboxCommands).get(), isEmpty);
  });

  test('remote profile schema validates and merges height', () {
    final migration = File(
      'supabase/migrations/20260728164000_profile_height_cm.sql',
    ).readAsStringSync();

    expect(migration, contains('add column if not exists height_cm'));
    expect(migration, contains('profiles_height_cm_check'));
    expect(migration, contains("when p_payload ? 'height_cm'"));
    expect(
      migration,
      contains('taskmaster_internal.apply_profile_merge_command'),
    );
    expect(migration, contains('security definer'));
    expect(
      migration,
      isNot(
        contains(
          'create or replace function public.apply_profile_merge_command',
        ),
      ),
    );
  });
}
