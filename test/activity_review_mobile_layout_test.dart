import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/providers.dart';
import 'package:taskmaster_pro/features/activity/data/activity_repository.dart';
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

  testWidgets('task allocation dialog lays out without viewport assertions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase(NativeDatabase.memory());
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final repository = ActivityRepository(database, client);
    final now = DateTime.now().toUtc();
    await database
        .into(database.localTasks)
        .insert(
          LocalTasksCompanion.insert(
            id: 'allocation-target',
            userId: 'local',
            title: 'A task with a deliberately long allocation title',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.localActivitySegments)
        .insert(
          LocalActivitySegmentsCompanion.insert(
            id: 'pending-activity',
            userId: 'local',
            deviceId: 'windows-device',
            deviceEventId: 'pending-event',
            startedAt: now.subtract(const Duration(minutes: 5)),
            endedAt: now.subtract(const Duration(minutes: 4)),
            sourceType: 'windows_foreground',
            processName: const Value('Code.exe'),
            windowTitle: const Value('DayVector development'),
            idleState: const Value('active'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.localActivityReviews)
        .insert(
          LocalActivityReviewsCompanion.insert(
            id: 'pending-review',
            userId: 'local',
            activitySegmentId: 'pending-activity',
            reviewReason: 'unknown_application',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final segment = await database
        .select(database.localActivitySegments)
        .getSingle();
    final review = await database
        .select(database.localActivityReviews)
        .getSingle();
    final entry = ActivityReviewEntry(review: review, segment: segment);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activityRepositoryProvider.overrideWithValue(repository),
          activityReviewProvider.overrideWith((ref) => Stream.value([entry])),
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
    for (var frame = 0; frame < 40; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ExpansionTile).evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }

    await tester.tap(find.byType(ExpansionTile));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Review activity'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Review activity'));
    for (var frame = 0; frame < 40; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Assign to another task').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Productive'), findsOneWidget);
    expect(find.text('Supporting work'), findsOneWidget);
    await tester.ensureVisible(find.text('Assign to another task'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Assign to another task'));
    for (var frame = 0; frame < 40; frame += 1) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Credit to tasks').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Credit to tasks'),
      ),
      findsOneWidget,
    );
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    await database.close();
  });
}
