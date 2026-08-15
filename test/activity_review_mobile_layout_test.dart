import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/providers.dart';
import 'package:taskmaster_pro/features/activity/presentation/activity_review_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Activity review uses compact filters at 320 and 360px with large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final database = AppDatabase(NativeDatabase.memory());
      final now = DateTime.now().toUtc();
      await database
          .into(database.localActivitySegments)
          .insert(
            LocalActivitySegmentsCompanion.insert(
              id: 'long-mobile-activity',
              userId: 'owner',
              deviceId: 'windows-device',
              deviceEventId: 'event-1',
              startedAt: now.subtract(const Duration(minutes: 12)),
              endedAt: now,
              sourceType: 'windows_foreground',
              processName: const Value('chrome.exe'),
              windowTitle: const Value(
                'A deliberately long activity title that must not squeeze its badge',
              ),
              createdAt: now,
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
                home: const ActivityReviewScreen(),
              ),
            ),
          );
          for (var frame = 0; frame < 40; frame += 1) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find.byType(CustomScrollView).evaluate().isNotEmpty &&
                find.byType(CircularProgressIndicator).evaluate().isEmpty) {
              break;
            }
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
          }

          final strip = find.byKey(
            const ValueKey('mobile-activity-filter-strip'),
          );
          expect(find.byType(ActivityReviewScreen), findsOneWidget);
          expect(find.byType(CustomScrollView), findsOneWidget);
          expect(strip, findsOneWidget);
          expect(
            find.descendant(of: strip, matching: find.byType(ChoiceChip)),
            findsNWidgets(7),
          );
          expect(find.byType(SegmentedButton<String>), findsNothing);
          expect(
            tester.getSize(strip).width,
            lessThanOrEqualTo(size.width - 24),
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(
            tester.takeException(),
            isNull,
            reason: '${locale.languageCode} at ${size.width}px',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }

      await database.close();
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets('Activity review keeps the complete desktop segmented control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appSettingsProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ActivityReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-activity-filter-strip')),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-activity-filter-strip')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await database.close();
  });
}
