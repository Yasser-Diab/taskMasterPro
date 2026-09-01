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
      final shell = File(
        'lib/features/shell/presentation/home_shell.dart',
      ).readAsStringSync();
      final wellbeing = File(
        'lib/features/settings/presentation/schedule_wellbeing_screen.dart',
      ).readAsStringSync();

      expect(settings, contains('builder: (_) => Platform.isAndroid'));
      expect(settings, contains('? const HealthConnectScreen()'));
      expect(settings, contains(': const WindowsHealthSummaryScreen()'));
      expect(
        shell,
        contains('platform == TargetPlatform.windows'),
        reason: 'The Windows rail must open the synchronized summary surface.',
      );
      expect(shell, contains('? const WindowsHealthSummaryScreen()'));
      expect(shell, contains(': const HealthConnectScreen()'));
      expect(
        wellbeing,
        contains('if (!coachingOnly && Platform.isAndroid)'),
        reason: 'Health Connect preferences must not be offered on Windows.',
      );
    });

    test('Health Connect refreshes terminate and expose access settings', () {
      final screen = File(
        'lib/features/health/presentation/health_connect_screen.dart',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/MainActivity.kt',
      ).readAsStringSync();

      expect(screen, contains('_healthRefreshDeadline'));
      expect(screen, contains('.timeout(_healthReadTimeout)'));
      expect(screen, contains("'health_operation_timed_out'"));
      expect(screen, contains("'openHealthConnectSettings'"));
      expect(
        screen,
        contains('HealthDataType.TOTAL_CALORIES_BURNED'),
        reason:
            'The health plugin enriches WORKOUT records with total calories, '
            'so Android must grant that separate read permission.',
      );
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(
        manifest,
        contains('android.permission.health.READ_TOTAL_CALORIES_BURNED'),
      );
      expect(activity, contains('healthConnectStepTrackingAvailable'));
      expect(
        activity,
        contains('android.health.connect.action.HEALTH_HOME_SETTINGS'),
      );
      expect(
        activity,
        contains('androidx.health.ACTION_HEALTH_CONNECT_SETTINGS'),
      );
    });

    test('Health Connect recovery guidance is localized', () {
      const keys = [
        'health_manage_access',
        'health_operation_timed_out',
        'health_no_recent_records_explanation',
        'health_no_records_today_explanation',
        'health_on_device_steps_waiting',
      ];

      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = AppLocalizations(locale);
        for (final key in keys) {
          expect(l10n.text(key), isNot(contains('⟦$key⟧')));
          expect(l10n.text(key).trim(), isNotEmpty);
        }
      }
    });

    test('Health dashboard is mobile-first and lists connected watches only', () {
      final screen = File(
        'lib/features/health/presentation/health_connect_screen.dart',
      ).readAsStringSync();

      expect(screen, contains('body: RefreshIndicator('));
      expect(screen, contains('onRefresh: _refreshDashboard'));
      expect(screen, contains('AlwaysScrollableScrollPhysics'));
      expect(
        screen,
        contains("PageStorageKey<String>('health-connect-scroll')"),
        reason: 'The list offset must have its own PageStorage identity.',
      );
      expect(
        screen,
        contains("PageStorageKey<String>('health-sources-expansion')"),
        reason:
            'Expansion state must not read the list scroll offset as a bool.',
      );
      expect(screen, contains('class _WeeklyStepsPainter'));
      expect(
        screen,
        contains('.where((wearable) => wearable.isConnected)'),
        reason: 'Disconnected paired watches must not be rendered as sources.',
      );
      expect(
        screen,
        isNot(
          contains(
            "label: Text(\n                            context.l10n.text('health_wearables_refresh')",
          ),
        ),
        reason:
            'Refresh belongs to the pull gesture, not a desktop-style button.',
      );

      const keys = [
        'health_weekly_steps',
        'health_weekly_steps_detail',
        'health_pull_to_refresh',
        'health_connected_watches',
        'health_connected_watches_detail',
        'health_wearables_none_connected',
      ];
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = AppLocalizations(locale);
        for (final key in keys) {
          expect(l10n.text(key), isNot(contains('⟦$key⟧')));
          expect(l10n.text(key).trim(), isNotEmpty);
        }
      }
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
