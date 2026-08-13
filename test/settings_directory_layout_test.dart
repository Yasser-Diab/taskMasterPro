import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/settings/data/settings_section_catalog.dart';
import 'package:taskmaster_pro/features/settings/presentation/settings_section_directory.dart';

void main() {
  testWidgets('settings directory is usable at 320 logical pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsSectionDirectory(
              onSelected: (key) => selected = key,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Settings sections'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('settings-section-tasks_and_execution')),
    );
    expect(selected, 'tasks_and_execution');

    final aboutKey = find.byKey(
      const ValueKey('settings-section-about_and_legal'),
    );
    await tester.scrollUntilVisible(
      aboutKey,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(aboutKey, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('operational screens are not used as generic settings destinations', () {
    for (final key in const [
      'profile_and_account',
      'tasks_and_execution',
      'pomodoro',
      'activity_and_privacy',
      'reports',
      'appearance',
      'synchronization',
      'help_and_diagnostics',
      'about_and_legal',
    ]) {
      expect(
        settingsSectionDestination(key),
        SettingsSectionDestination.categoryPage,
        reason: '$key must open its own clear settings category page',
      );
    }
    expect(
      settingsSectionDestination('connected_devices'),
      SettingsSectionDestination.connectedDevices,
    );
    expect(
      settingsSectionDestination('coaching'),
      SettingsSectionDestination.coachingPreferences,
    );
    expect(
      settingsSectionDestination('notifications_and_sounds'),
      SettingsSectionDestination.notificationsAndSounds,
    );
    expect(
      settingsSectionDestination('privacy_and_vault'),
      SettingsSectionDestination.vault,
    );
  });

  test('canonical settings registry has unique typed ownership metadata', () {
    expect(hasDuplicateCanonicalSettings(), isFalse);
    expect(
      canonicalSetting('pomodoro.focus_duration').taskOverrideAllowed,
      isTrue,
    );
    expect(
      canonicalSetting('activity.application_tracking').scope,
      CanonicalSettingScope.device,
    );
    expect(canonicalSetting('vault.autofill').sectionKey, 'privacy_and_vault');
  });

  test('legal links are absent from the app updates section', () {
    final source = File(
      'lib/features/settings/presentation/settings_screen.dart',
    ).readAsStringSync();
    final updatesStart = source.indexOf(
      "title: context.l10n.text('app_updates')",
    );
    final aboutStart = source.indexOf('key: _aboutSectionKey', updatesStart);
    expect(updatesStart, greaterThanOrEqualTo(0));
    expect(aboutStart, greaterThan(updatesStart));

    final updateSection = source.substring(updatesStart, aboutStart);
    expect(updateSection, isNot(contains('view_privacy_policy')));
    expect(updateSection, isNot(contains('view_terms_of_use')));
  });
}
