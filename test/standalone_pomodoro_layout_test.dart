import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/providers.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/presentation/standalone_pomodoro_screen.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('ar'), Locale('de')]) {
    testWidgets(
      'standalone task-style timer fits a narrow ${locale.languageCode} phone',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final repository = TaskRepository(
          database,
          SupabaseClient(
            'https://example.supabase.co',
            'sb_publishable_test_key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );
        await tester.binding.setSurfaceSize(const Size(320, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(database),
              taskRepositoryProvider.overrideWithValue(repository),
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const StandalonePomodoroScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('standalone-pomodoro-state-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('holographic-execution-timer')),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('standalone-pomodoro-state-card')),
              )
              .width,
          lessThanOrEqualTo(288),
        );
        expect(
          Directionality.of(
            tester.element(
              find.byKey(const ValueKey('standalone-pomodoro-state-card')),
            ),
          ),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
