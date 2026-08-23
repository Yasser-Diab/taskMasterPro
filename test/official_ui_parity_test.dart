import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/sync/sync_service.dart';
import 'package:taskmaster_pro/features/activity/presentation/activity_badges.dart';
import 'package:taskmaster_pro/features/shell/presentation/home_shell.dart';

void main() {
  test('official Activity states keep distinct mature chip tones', () {
    expect(activityBadgeTone('direct_task_work'), ActivityBadgeTone.productive);
    expect(activityBadgeTone('research'), ActivityBadgeTone.research);
    expect(activityBadgeTone('communication'), ActivityBadgeTone.communication);
    expect(activityBadgeTone('unclassified'), ActivityBadgeTone.needsReview);
  });

  test('dashboard Activity attention copy names grouped today scope', () {
    const english = AppLocalizations(Locale('en'));
    const arabic = AppLocalizations(Locale('ar'));
    const german = AppLocalizations(Locale('de'));

    expect(
      english.count('dashboard_item_review', 'dashboard_items_review', 3),
      '3 groups need review today',
    );
    expect(
      arabic.text('dashboard_other_activity_review'),
      'نشاط آخر يحتاج إلى مراجعة',
    );
    expect(
      german.text('dashboard_nothing_review'),
      'Heute muss nichts geprüft werden',
    );
  });

  test(
    'Activity classification labels are localized without backend enums',
    () {
      const english = AppLocalizations(Locale('en'));
      const arabic = AppLocalizations(Locale('ar'));
      const german = AppLocalizations(Locale('de'));

      expect(
        activityClassificationLabel(english, 'direct_task_work'),
        'Productive',
      );
      expect(activityClassificationLabel(english, 'research'), 'Research');
      expect(
        activityClassificationLabel(english, 'communication'),
        'Communication',
      );
      expect(
        activityClassificationLabel(english, 'unclassified'),
        'Needs review',
      );
      expect(activityClassificationLabel(arabic, 'direct_task_work'), 'منتج');
      expect(
        activityClassificationLabel(german, 'direct_task_work'),
        'Produktiv',
      );
      expect(
        activitySuggestionLabel(english, 'learned_from_usage'),
        'Learned from your usage',
      );
      expect(activitySuggestionLabel(english, 'user_confirmed'), isNull);
    },
  );

  test('shell sync semantics map to the four official visible states', () {
    const english = AppLocalizations(Locale('en'));
    const arabic = AppLocalizations(Locale('ar'));
    const german = AppLocalizations(Locale('de'));
    expect(english.text('sync_offline_compact'), 'Offline');
    expect(arabic.text('sync_offline_compact'), 'غير متصل');
    expect(german.text('sync_offline_compact'), 'Offline');
    expect(
      shellSyncVisualState(SyncHealth.offline),
      ShellSyncVisualState.offline,
    );
    expect(
      shellSyncVisualState(SyncHealth.syncing),
      ShellSyncVisualState.syncing,
    );
    expect(
      shellSyncVisualState(SyncHealth.waiting),
      ShellSyncVisualState.waiting,
    );
    expect(shellSyncVisualState(SyncHealth.idle), ShellSyncVisualState.synced);
    expect(
      shellSyncVisualState(SyncHealth.attention),
      ShellSyncVisualState.attention,
    );
  });

  testWidgets('classification badge remains compact on a narrow card', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: ActivityClassificationBadge(classification: 'communication'),
          ),
        ),
      ),
    );

    expect(find.text('Communication'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ActivityClassificationBadge)).height,
      lessThanOrEqualTo(24),
    );
    expect(tester.takeException(), isNull);
  });
}
