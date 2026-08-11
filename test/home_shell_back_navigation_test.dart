import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/shell/domain/home_shell_back_navigation.dart';

void main() {
  test('first shell back returns to the preceding in-app destination', () {
    final navigation = HomeShellBackNavigation();
    navigation.recordDestination(from: 0, to: 1);
    navigation.recordDestination(from: 1, to: 5);

    final firstBack = navigation.resolve(
      currentIndex: 5,
      rootIndex: 0,
      now: DateTime.utc(2026, 8, 11, 10),
    );
    expect(firstBack.action, HomeShellBackAction.navigateInApp);
    expect(firstBack.destinationIndex, 1);

    final secondBack = navigation.resolve(
      currentIndex: 1,
      rootIndex: 0,
      now: DateTime.utc(2026, 8, 11, 10, 0, 1),
    );
    expect(secondBack.action, HomeShellBackAction.navigateInApp);
    expect(secondBack.destinationIndex, 0);

    final rootBack = navigation.resolve(
      currentIndex: 0,
      rootIndex: 0,
      now: DateTime.utc(2026, 8, 11, 10, 0, 2),
    );
    expect(rootBack.action, HomeShellBackAction.showExitHint);
  });

  test('Dashboard exit requires two back gestures within two seconds', () {
    final navigation = HomeShellBackNavigation();
    final start = DateTime.utc(2026, 8, 11, 10);

    expect(
      navigation.resolve(currentIndex: 0, rootIndex: 0, now: start).action,
      HomeShellBackAction.showExitHint,
    );
    expect(
      navigation
          .resolve(
            currentIndex: 0,
            rootIndex: 0,
            now: start.add(const Duration(milliseconds: 1900)),
          )
          .action,
      HomeShellBackAction.exitApplication,
    );
  });

  test('an expired or cancelled exit request can never exit unexpectedly', () {
    final navigation = HomeShellBackNavigation();
    final start = DateTime.utc(2026, 8, 11, 10);

    expect(
      navigation.resolve(currentIndex: 0, rootIndex: 0, now: start).action,
      HomeShellBackAction.showExitHint,
    );
    expect(
      navigation
          .resolve(
            currentIndex: 0,
            rootIndex: 0,
            now: start.add(const Duration(seconds: 3)),
          )
          .action,
      HomeShellBackAction.showExitHint,
    );
    navigation.cancelExit();
    expect(
      navigation
          .resolve(
            currentIndex: 0,
            rootIndex: 0,
            now: start.add(const Duration(seconds: 4)),
          )
          .action,
      HomeShellBackAction.showExitHint,
    );
  });

  test(
    'shell keeps route, sheet, dialog, and browser navigation ahead of exit',
    () {
      final source = File(
        'lib/features/shell/presentation/home_shell.dart',
      ).readAsStringSync();

      expect(source, contains('PopScope('));
      expect(source, contains('navigator.canPop()'));
      expect(source, contains('await navigator.maybePop()'));
      expect(source, contains('SystemNavigator.pop()'));
      expect(source, contains('with RouteAware'));
      expect(source, contains('void didPushNext()'));
      expect(source, contains('void didPopNext()'));
      expect(source, contains("'back_exit_hint'"));
    },
  );
}
