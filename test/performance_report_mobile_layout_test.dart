import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/providers.dart';
import 'package:taskmaster_pro/features/reports/presentation/performance_report_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'performance report stays compact at 320 and 360px in every language',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.now().toUtc();
      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: 'mobile-report-task',
              userId: 'report-owner',
              title: 'A completed focus task used by the responsive report',
              status: const Value('completed'),
              executionMode: const Value('pomodoro'),
              plannedStart: Value(now.subtract(const Duration(hours: 1))),
              plannedEnd: Value(now),
              estimatedDurationMs: const Value(60 * 60 * 1000),
              actualStart: Value(now.subtract(const Duration(minutes: 45))),
              actualFinish: Value(now),
              activeDurationMs: const Value(45 * 60 * 1000),
              createdAt: now.subtract(const Duration(hours: 1)),
              updatedAt: now,
            ),
          );

      for (final size in const [Size(320, 720), Size(360, 800)]) {
        tester.view.physicalSize = size;
        for (final locale in AppLocalizations.supportedLocales) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                databaseProvider.overrideWithValue(database),
                appSettingsProvider.overrideWith((ref) => Stream.value(null)),
              ],
              child: MaterialApp(
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const PerformanceReportScreen(),
              ),
            ),
          );

          for (var frame = 0; frame < 80; frame += 1) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find
                .byKey(const ValueKey('report-metric-grid'))
                .evaluate()
                .isNotEmpty) {
              break;
            }
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }

          final controls = find.byKey(const ValueKey('mobile-report-controls'));
          expect(controls, findsOneWidget);
          expect(
            tester.getSize(controls).height,
            lessThanOrEqualTo(72),
            reason: '${locale.languageCode} at ${size.width}px',
          );
          expect(
            find.byKey(const ValueKey('mobile-report-actions')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('mobile-report-settings')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('report-metric-grid')),
            findsOneWidget,
          );
          expect(find.byType(SegmentedButton<bool>), findsNothing);
          expect(
            tester.takeException(),
            isNull,
            reason: '${locale.languageCode} report at ${size.width}px',
          );

          await tester.tap(
            find.byKey(const ValueKey('mobile-report-settings')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('mobile-report-settings-sheet')),
            findsOneWidget,
          );
          expect(
            find.text(contextLabel(locale, 'report_sections')),
            findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${locale.languageCode} settings at ${size.width}px',
          );

          await tester.tap(find.byTooltip(contextLabel(locale, 'close')));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          // Drift closes watched queries on the next event-loop turn.
          await tester.pump(const Duration(milliseconds: 1));
        }
      }

      tester.platformDispatcher.textScaleFactorTestValue = 1;
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            appSettingsProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: PerformanceReportScreen(),
          ),
        ),
      );
      for (var frame = 0; frame < 80; frame += 1) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find
            .byKey(const ValueKey('report-metric-Planned effort'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      final planned = find.byKey(
        const ValueKey('report-metric-Planned effort'),
      );
      final productive = find.byKey(
        const ValueKey('report-metric-Productive work'),
      );
      expect(planned, findsOneWidget);
      expect(productive, findsOneWidget);
      expect(tester.getTopLeft(planned).dy, tester.getTopLeft(productive).dy);
      expect(tester.getSize(planned).width, lessThan(180));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop report keeps its full action and control layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appSettingsProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: PerformanceReportScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('mobile-report-controls')), findsNothing);
    expect(find.byKey(const ValueKey('mobile-report-actions')), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open report refreshes when synchronized history arrives', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final finishedAt = DateTime.now().toUtc();
    final startedAt = finishedAt.subtract(const Duration(minutes: 30));
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'live-report-task',
            userId: 'report-owner',
            title: 'Synchronized focus task',
            status: const Value('completed'),
            executionMode: const Value('pomodoro'),
            actualStart: Value(startedAt),
            actualFinish: Value(finishedAt),
            activeDurationMs: const Value(0),
            createdAt: startedAt,
            updatedAt: finishedAt,
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appSettingsProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: PerformanceReportScreen(),
        ),
      ),
    );
    for (var frame = 0; frame < 80; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .byKey(const ValueKey('report-metric-Productive work'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    final productiveCard = find.byKey(
      const ValueKey('report-metric-Productive work'),
    );
    expect(
      find.descendant(of: productiveCard, matching: find.text('0 sec')),
      findsOneWidget,
    );

    const recordedMs = 25 * 60 * 1000;
    await database.transaction(() async {
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: 'live-report-session',
              userId: 'report-owner',
              entityType: 'execution_sessions',
              parentId: const Value('live-report-task'),
              status: const Value('completed'),
              dataJson: Value(
                jsonEncode({
                  'task_occurrence_id': 'live-report-task',
                  'started_at': startedAt.toIso8601String(),
                  'finished_at': finishedAt.toIso8601String(),
                  // Reproduce a stale mutable row received before its event.
                  'accumulated_active_ms': 0,
                  'state': 'completed',
                }),
              ),
              createdAt: startedAt,
              updatedAt: finishedAt,
            ),
          );
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: 'live-report-complete-event',
              userId: 'report-owner',
              entityType: 'session_events',
              parentId: const Value('live-report-session'),
              dataJson: Value(
                jsonEncode({
                  'session_id': 'live-report-session',
                  'event_type': 'complete',
                  'occurred_at': finishedAt.toIso8601String(),
                  'duration_ms': recordedMs,
                }),
              ),
              createdAt: finishedAt,
              updatedAt: finishedAt,
            ),
          );
    });

    for (var frame = 0; frame < 80; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find
          .descendant(of: productiveCard, matching: find.text('25 min'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      find.descendant(of: productiveCard, matching: find.text('25 min')),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(
            find.descendant(of: productiveCard, matching: find.byType(Text)),
          )
          .map((widget) => widget.data)
          .join(' | '),
    );
    expect(tester.takeException(), isNull);
  });
}

String contextLabel(Locale locale, String key) =>
    AppLocalizations(locale).text(key);
