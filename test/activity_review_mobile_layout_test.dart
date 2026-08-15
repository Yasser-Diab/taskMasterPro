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

  testWidgets('Activity review remains usable on a 320px phone in every locale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

      expect(find.byType(ActivityReviewScreen), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull, reason: locale.languageCode);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    await database.close();
    await tester.pump();
    await tester.pump();
  });
}
