import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/shell/presentation/home_shell.dart';

void main() {
  test('compact navigation begins before destination labels collide', () {
    expect(usesCompactBottomNavigation(320), isTrue);
    expect(usesCompactBottomNavigation(599), isTrue);
    expect(usesCompactBottomNavigation(600), isFalse);
  });

  testWidgets('compact navigation remains tappable at 320 logical pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);
    var selected = 0;
    const destinations = <(IconData, IconData, String)>[
      (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
      (Icons.task_alt_outlined, Icons.task_alt, 'Tasks'),
      (Icons.calendar_month_outlined, Icons.calendar_month, 'Calendar'),
      (Icons.route_outlined, Icons.route, 'Roadmaps'),
      (Icons.insights_outlined, Icons.insights, 'Activity'),
      (Icons.favorite_border_rounded, Icons.favorite_rounded, 'Health'),
      (Icons.settings_outlined, Icons.settings, 'Settings'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CompactBottomNavigationBar(
            selectedIndex: selected,
            destinations: destinations,
            onDestinationSelected: (index) => selected = index,
          ),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNWidgets(7));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Roadmaps'));
    expect(selected, 3);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Health'));
    expect(selected, 5);
    expect(tester.takeException(), isNull);
  });

  test('dashboard reserves compact-phone width for copy and metrics', () {
    final source = File(
      'lib/features/dashboard/presentation/dashboard_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final horizontalPadding = compact ? 16.0 : 24.0'));
    expect(source, contains('if (constraints.maxWidth < 430)'));
    expect(source, contains('constraints.maxWidth >= 440'));
  });
}
