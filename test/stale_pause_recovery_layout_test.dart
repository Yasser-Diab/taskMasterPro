import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/tasks/data/task_execution_providers.dart';
import 'package:taskmaster_pro/features/tasks/presentation/stale_paused_task_recovery.dart';
import 'package:taskmaster_pro/features/tasks/presentation/task_card.dart';

void main() {
  final now = DateTime.now().toUtc();
  final pausedAt = now.subtract(const Duration(hours: 13));
  final task = LocalTask(
    id: '00000000-0000-4000-8000-000000000101',
    userId: '00000000-0000-4000-8000-000000000001',
    templateId: null,
    title: 'Paused task',
    description: '',
    domainId: null,
    status: 'paused',
    priority: 2,
    executionMode: 'pomodoro',
    scheduledDate: pausedAt,
    plannedStart: pausedAt,
    plannedEnd: null,
    dueAt: null,
    estimatedDurationMs: const Duration(minutes: 25).inMilliseconds,
    actualStart: pausedAt,
    actualFinish: null,
    activeDurationMs: const Duration(minutes: 7).inMilliseconds,
    pausedDurationMs: 0,
    idleDurationMs: 0,
    progress: .1,
    roadmapId: null,
    roadmapPhaseId: null,
    occurrenceKey: null,
    dataJson: '{}',
    revision: 3,
    createdAt: pausedAt,
    updatedAt: pausedAt,
    createdByDeviceId: null,
    updatedByDeviceId: null,
    lastCommandId: null,
    deletedAt: null,
  );
  final runtime = LocalRuntime(
    id: 'runtime:local',
    userId: 'local',
    activeTaskId: task.id,
    sessionId: '00000000-0000-4000-8000-000000000201',
    state: 'paused',
    segmentStartedAt: null,
    accumulatedActiveMs: task.activeDurationMs,
    accumulatedPausedMs: 0,
    dataJson: '{}',
    revision: 4,
    updatedAt: pausedAt,
    lastCommandId: null,
  );

  for (final locale in const [Locale('en'), Locale('ar'), Locale('de')]) {
    testWidgets(
      'stale pause recovery wraps at 320px in ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(8),
                  child: StalePausedTaskRecovery(task: task, runtime: runtime),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(ValueKey('stale-pause-recovery-${task.id}')),
          findsOneWidget,
        );
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(OutlinedButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('stale pause actions stay usable inside a 320px task card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskExecutionRuntimeProvider.overrideWith(
            (ref) => Stream<LocalRuntime?>.value(runtime),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: TaskCard(
              task: task,
              compact: true,
              activeSessionState: 'paused',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final recovery = find.byKey(ValueKey('stale-pause-recovery-${task.id}'));
    expect(recovery, findsOneWidget);
    expect(
      tester.getSize(recovery).width,
      greaterThanOrEqualTo(240),
      reason: 'Recovery decisions need the phone card width, not a narrow row.',
    );
    for (final label in const ['Zur Aufgabenliste', 'Aufgabe überspringen']) {
      final finder = find.text(label);
      expect(finder, findsOneWidget);
      final bounds = tester.getRect(finder);
      expect(bounds.left, greaterThanOrEqualTo(0), reason: label);
      expect(bounds.right, lessThanOrEqualTo(320), reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  test('stale pause copy is complete and unmixed in all three languages', () {
    const keys = [
      'stale_pause_title',
      'stale_pause_body',
      'stale_pause_needs_attention',
      'stale_pause_skip',
      'stale_pause_resolved',
    ];
    const en = AppLocalizations(Locale('en'));
    const ar = AppLocalizations(Locale('ar'));
    const de = AppLocalizations(Locale('de'));
    final arabicScript = RegExp(r'[\u0600-\u06ff]');

    for (final key in keys) {
      final english = en.text(key);
      final arabic = ar.text(key);
      final german = de.text(key);
      expect(english.trim(), isNotEmpty, reason: key);
      expect(arabic, isNot(english), reason: '$key must be Arabic');
      expect(arabic, matches(arabicScript), reason: key);
      expect(german, isNot(english), reason: '$key must be German');
      expect(german, isNot(matches(arabicScript)), reason: key);
      expect(arabic, isNot(key), reason: key);
      expect(german, isNot(key), reason: key);
    }
  });
}
