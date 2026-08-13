import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';

void main() {
  test('standalone Pomodoro is a desktop aside and a compact shortcut', () {
    final shell = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/features/dashboard/presentation/dashboard_screen.dart',
    ).readAsStringSync();

    expect(shell, contains("'sidebar-standalone-pomodoro-destination'"));
    expect(shell, contains('const StandalonePomodoroScreen()'));
    expect(shell, isNot(contains('final railDestinations = [')));
    expect(shell, isNot(contains('final mobileIndex =')));
    expect(
      dashboard,
      contains(
        "ValueKey(\n                          'dashboard-standalone-pomodoro-shortcut'",
      ),
    );
    expect(dashboard, contains('const StandalonePomodoroScreen()'));
  });

  test('standalone controls expose every explicit phase transition', () {
    final screen = File(
      'lib/features/tasks/presentation/standalone_pomodoro_screen.dart',
    ).readAsStringSync();

    for (final key in const [
      'standalone-pomodoro-state-card',
      'standalone-pomodoro-state-label',
      'standalone-pomodoro-continue-focus',
      'standalone-pomodoro-skip-focus',
      'standalone-pomodoro-skip-break',
      'standalone-pomodoro-extend-break',
    ]) {
      expect(screen, contains(key), reason: '$key must remain testable');
    }
    expect(screen, contains('formatPomodoroCountdown(remainingMs)'));
    expect(screen, contains('pomodoroTimerVisualState('));
    expect(screen, contains('state.isFinished'));
    expect(screen, contains('state.isPaused'));
    expect(screen, contains('state.isRunning'));
  });

  test('new standalone transition labels are complete in all locales', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      for (final key in const [
        'standalone_pomodoro',
        'standalone_pomodoro_skip_focus',
        'pomodoro_skip_break',
        'notification_continue_working',
        'notification_extend_break',
      ]) {
        expect(l10n.text(key), isNot(contains('⟦')));
        expect(l10n.text(key).trim(), isNotEmpty);
      }
    }
    expect(AppLocalizations.translationsComplete, isTrue);
  });
}
