import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/coaching/data/adaptive_coaching_service.dart';
import 'package:taskmaster_pro/features/coaching/presentation/coaching_expression_visual.dart';

void main() {
  const coachingCopyKeys = <String>[
    'coaching_learning_title',
    'coaching_learning_body',
    'coaching_learning_body_child',
    'coaching_learning_body_teen',
    'coaching_learning_body_adult',
    'coaching_learning_body_older_adult',
    'coaching_day_two_active_title',
    'coaching_day_two_active_body',
    'coaching_day_two_attention_title',
    'coaching_day_two_attention_body',
    'coaching_day_two_paused_title',
    'coaching_day_two_paused_body',
    'coaching_day_two_ready_title',
    'coaching_day_two_ready_body',
    'coaching_day_two_momentum_title',
    'coaching_day_two_momentum_body',
    'coaching_adaptive_space_title',
    'coaching_adaptive_space_body',
    'coaching_adaptive_late_title',
    'coaching_adaptive_late_body',
    'coaching_adaptive_late_body_with_summary',
    'coaching_adaptive_late_body_youth',
    'coaching_adaptive_late_body_older_adult',
    'coaching_adaptive_roadmap_risk_title',
    'coaching_adaptive_roadmap_risk_body',
    'coaching_adaptive_overdue_title',
    'coaching_adaptive_overdue_body',
    'coaching_adaptive_active_title',
    'coaching_adaptive_active_body',
    'coaching_adaptive_paused_title',
    'coaching_adaptive_paused_body',
    'coaching_adaptive_roadmap_title',
    'coaching_adaptive_roadmap_body',
    'coaching_adaptive_focus_title',
    'coaching_adaptive_focus_body',
    'coaching_adaptive_rest_title',
    'coaching_adaptive_rest_body',
    'coaching_adaptive_schedule_title',
    'coaching_adaptive_schedule_body',
    'coaching_adaptive_baseline_title',
    'coaching_adaptive_baseline_body',
  ];

  test('every coaching mood has a lightweight registered SVG reaction', () {
    for (final mood in CoachingMood.values) {
      final asset = File(mood.assetPath);
      expect(asset.existsSync(), isTrue, reason: mood.assetPath);
      expect(asset.lengthSync(), lessThan(16 * 1024), reason: mood.assetPath);
      final markup = asset.readAsStringSync();
      expect(markup, contains('<svg'));
      expect(markup, contains('viewBox="0 0 240 180"'));
      expect(markup, isNot(contains('<text')));
    }
  });

  test(
    'the mature expression pack has consistent lightweight SVG geometry',
    () {
      for (final expression in CoachingExpression.values) {
        final asset = File(expression.assetPath);
        expect(asset.existsSync(), isTrue, reason: expression.assetPath);
        expect(
          asset.lengthSync(),
          lessThan(8 * 1024),
          reason: expression.assetPath,
        );
        final markup = asset.readAsStringSync();
        expect(markup, contains('<svg'));
        expect(markup, contains('viewBox="0 0 240 180"'));
        expect(markup, isNot(contains('<text')));
        expect(markup, isNot(contains('marker-end')));
      }
    },
  );

  testWidgets(
    'every mood reaction renders through the application asset bundle',
    (tester) async {
      for (final mood in CoachingMood.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 240,
                height: 180,
                child: SvgPicture.asset(mood.assetPath),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: mood.assetPath);
      }
    },
  );

  testWidgets('every coaching expression is theme-aware and accessible', (
    tester,
  ) async {
    for (final expression in CoachingExpression.values) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: Center(
            child: CoachingExpressionVisual(
              expression: expression,
              semanticLabel: expression.name,
              accent: Colors.teal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(expression.name), findsOneWidget);
      expect(tester.takeException(), isNull, reason: expression.assetPath);
      semantics.dispose();
    }
  });

  test('mood labels and semantic descriptions are localized', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final localizations = AppLocalizations(locale);
      for (final mood in CoachingMood.values) {
        expect(
          localizations.text(mood.labelKey),
          isNot(startsWith('⟦')),
          reason: '${locale.languageCode}.${mood.labelKey}',
        );
        expect(
          localizations.text(mood.semanticLabelKey),
          isNot(startsWith('⟦')),
          reason: '${locale.languageCode}.${mood.semanticLabelKey}',
        );
      }
      for (final expression in CoachingExpression.values) {
        expect(
          localizations.text(expression.labelKey),
          isNot(startsWith('⟦')),
          reason: '${locale.languageCode}.${expression.labelKey}',
        );
        expect(
          localizations.text(expression.semanticLabelKey),
          isNot(startsWith('⟦')),
          reason: '${locale.languageCode}.${expression.semanticLabelKey}',
        );
      }
    }
    expect(AppLocalizations.translationsComplete, isTrue);
  });

  test('coaching copy uses the SVG reactions instead of emoji decoration', () {
    final emoji = RegExp(
      r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]',
      unicode: true,
    );
    for (final locale in const [Locale('en'), Locale('ar'), Locale('de')]) {
      final localizations = AppLocalizations(locale);
      for (final key in coachingCopyKeys) {
        final copy = localizations.text(key);
        expect(
          copy,
          isNot(startsWith('⟦')),
          reason: '${locale.languageCode}.$key',
        );
        expect(
          emoji.hasMatch(copy),
          isFalse,
          reason: '${locale.languageCode}.$key contains $copy',
        );
      }
    }
  });
}
