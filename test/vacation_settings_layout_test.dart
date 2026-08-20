import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/providers.dart';
import 'package:taskmaster_pro/features/tasks/presentation/vacation_settings_screen.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      'vacation settings fits a narrow ${locale.languageCode} phone',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 760);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final database = AppDatabase(NativeDatabase.memory());
        final client = SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test_key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(database),
              supabaseClientProvider.overrideWithValue(client),
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
              home: const VacationSettingsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('vacation-add')), findsOneWidget);
        expect(find.text(contextText(locale)), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        await database.close();
        await tester.pump();
      },
    );
  }
}

String contextText(Locale locale) => switch (locale.languageCode) {
  'ar' => 'الإجازات',
  'de' => 'Urlaub',
  _ => 'Vacations',
};
