import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/roadmaps/presentation/roadmaps_screen.dart';

void main() {
  final roadmap = LocalRoadmap(
    id: 'roadmap-mobile',
    userId: 'user',
    title: 'A deliberately long roadmap title that remains readable',
    description: 'A clear outcome with enough detail to wrap on a phone.',
    status: 'active',
    finalOutcome: 'Finish the complete learning plan.',
    progress: 0.42,
    requiredEffortMs: const Duration(hours: 24).inMilliseconds,
    completedEffortMs: const Duration(hours: 10).inMilliseconds,
    riskLevel: 'low',
    forecastConfidence: 'early',
    revision: 1,
    createdAt: DateTime.utc(2026, 8, 10),
    updatedAt: DateTime.utc(2026, 8, 10),
  );

  Future<void> pumpRoadmaps(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roadmapsProvider.overrideWith((ref) => Stream.value([roadmap])),
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
          home: const RoadmapsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone roadmaps use content-sized cards without overflow', (
    tester,
  ) async {
    await pumpRoadmaps(tester, size: const Size(360, 800), textScale: 1.3);

    expect(find.byKey(const ValueKey('mobile-roadmap-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-roadmap-add')), findsNothing);
    expect(find.byType(SliverList), findsWidgets);
    expect(find.byType(SliverGrid), findsNothing);
    expect(find.textContaining('deliberately long'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop roadmaps retain the width-aware grid', (tester) async {
    await pumpRoadmaps(tester, size: const Size(1200, 800));

    expect(find.byKey(const ValueKey('desktop-roadmap-add')), findsOneWidget);
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
