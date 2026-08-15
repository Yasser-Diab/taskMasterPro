import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';

void main() {
  group('platform capability visibility contracts', () {
    test('Android permission setup never renders on Windows', () {
      final source = File(
        'lib/features/onboarding/presentation/android_permission_setup_gate.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'kIsWeb \|\| defaultTargetPlatform != TargetPlatform\.android',
        ).allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason:
            'Both loading and rendering must short-circuit before Android-only '
            'notification, activity, Bluetooth, usage-access, exact-alarm, and '
            'Health Connect capabilities are inspected.',
      );
    });

    test('settings route each platform to its own health surface', () {
      final settings = File(
        'lib/features/settings/presentation/settings_screen.dart',
      ).readAsStringSync();
      final wellbeing = File(
        'lib/features/settings/presentation/schedule_wellbeing_screen.dart',
      ).readAsStringSync();

      expect(settings, contains('builder: (_) => Platform.isAndroid'));
      expect(settings, contains('? const HealthConnectScreen()'));
      expect(settings, contains(': const WindowsHealthSummaryScreen()'));
      expect(
        wellbeing,
        contains('if (!coachingOnly && Platform.isAndroid)'),
        reason: 'Health Connect preferences must not be offered on Windows.',
      );
    });

    test('usage access and Android sound entry points remain Android-gated', () {
      final settings = File(
        'lib/features/settings/presentation/settings_screen.dart',
      ).readAsStringSync();

      expect(settings, contains('if (!enabled || !Platform.isAndroid)'));
      expect(
        RegExp(
          r"if \(Platform\.isAndroid\s*&&\s*settings\.notificationSoundKey == 'system'\)",
          multiLine: true,
        ).hasMatch(settings),
        isTrue,
      );
    });

    test('platform-neutral default wording is used outside platform gates', () {
      final localization = File(
        'lib/core/localization/app_localizations.dart',
      ).readAsStringSync();

      expect(localization, isNot(contains('Android or system default')));
      expect(localization, isNot(contains('Android- oder Systemstandard')));
      expect(
        localization,
        contains("'sound_system_default': 'Device default'"),
      );

      for (final locale in const [Locale('en'), Locale('ar'), Locale('de')]) {
        final l10n = AppLocalizations(locale);
        expect(
          l10n.text('notification_test_verified'),
          isNot(contains('Android')),
        );
        expect(
          l10n.text('notification_test_sound_mismatch'),
          isNot(contains('Android')),
        );
      }
    });
  });
}
