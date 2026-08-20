import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/dashboard/presentation/dashboard_screen.dart';

void main() {
  Widget subject(double width) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: DashboardActiveTaskResponsiveLayout(
              details: const SizedBox(
                key: ValueKey('active-task-details'),
                height: 150,
                child: Text('Daily work routine'),
              ),
              timer: const SizedBox(
                key: ValueKey('active-task-timer'),
                width: 110,
                height: 64,
                child: Text('00:00'),
              ),
              primaryActions: [
                FilledButton.icon(
                  key: const ValueKey('active-task-start-break'),
                  onPressed: () {},
                  icon: const Icon(Icons.coffee_outlined),
                  label: const Text('Start break'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('active-task-skip-break'),
                  onPressed: () {},
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Skip break'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('active-task-complete'),
                  onPressed: () {},
                  icon: const Icon(Icons.check),
                  label: const Text('Complete'),
                ),
              ],
              utilityActions: [
                IconButton.outlined(
                  key: const ValueKey('active-task-interruption'),
                  onPressed: () {},
                  icon: const Icon(Icons.flash_on_outlined),
                ),
                IconButton.outlined(
                  key: const ValueKey('active-task-note'),
                  onPressed: () {},
                  icon: const Icon(Icons.note_add_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('narrow Windows card keeps copy wide and moves controls below', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(943, 631);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(subject(840));

    expect(
      find.byKey(const ValueKey('dashboard-active-task-reflow-layout')),
      findsOneWidget,
    );
    final details = tester.getRect(
      find.byKey(const ValueKey('active-task-details')),
    );
    final timer = tester.getRect(
      find.byKey(const ValueKey('active-task-timer')),
    );
    final actions = tester.getRect(
      find.byKey(const ValueKey('dashboard-active-task-wrapped-actions')),
    );

    expect(details.width, greaterThan(650));
    expect(timer.left, greaterThan(details.right));
    expect(actions.top, greaterThanOrEqualTo(details.bottom + 18));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone card stacks text controls at full available width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(subject(288));

    expect(
      find.byKey(const ValueKey('dashboard-active-task-phone-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dashboard-active-task-stacked-actions')),
      findsOneWidget,
    );
    for (final key in const [
      'active-task-start-break',
      'active-task-skip-break',
      'active-task-complete',
    ]) {
      expect(tester.getSize(find.byKey(ValueKey(key))).width, 288);
    }
    expect(tester.takeException(), isNull);
  });
}
