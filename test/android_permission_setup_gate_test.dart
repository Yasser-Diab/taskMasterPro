import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/onboarding/data/android_permission_setup_store.dart';
import 'package:taskmaster_pro/features/onboarding/presentation/android_permission_setup_gate.dart';

void main() {
  testWidgets('Android requires an explicit permission review before home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final originalTargetPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: AndroidPermissionSetupGate(
              userId: 'permission-review-user',
              child: const Text('Home shell'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set up Android access'), findsOneWidget);
      expect(find.text('Home shell'), findsNothing);

      final skip = find.text('Not now');
      await tester.scrollUntilVisible(skip, 300);
      await tester.tap(skip);
      await tester.pumpAndSettle();

      expect(find.text('Home shell'), findsOneWidget);
      final preferences = await SharedPreferences.getInstance();
      final record = AndroidPermissionSetupRecord.tryParse(
        preferences.getString(
          SharedPreferencesAndroidPermissionSetupStore.storageKeyFor(
            userId: 'permission-review-user',
          ),
        ),
      );
      expect(record?.outcome, AndroidPermissionSetupOutcome.skipped);
    } finally {
      debugDefaultTargetPlatformOverride = originalTargetPlatform;
    }
  });
}
