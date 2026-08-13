import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/providers.dart';
import 'package:taskmaster_pro/features/tasks/presentation/tasks_screen.dart';

void main() {
  testWidgets('a pushed Tasks/Pomodoro shortcut exposes explicit Back', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allTasksProvider.overrideWith(
            (ref) => Stream.value(const <LocalTask>[]),
          ),
          taskDomainsProvider.overrideWith(
            (ref) => Stream.value(const <LocalDomain>[]),
          ),
          taskRoadmapsProvider.overrideWith(
            (ref) => Stream.value(const <LocalRoadmap>[]),
          ),
          appSettingsProvider.overrideWith((ref) => Stream.value(null)),
          supabaseClientProvider.overrideWithValue(
            SupabaseClient(
              'https://example.supabase.co',
              'sb_publishable_test_key',
              authOptions: const AuthClientOptions(autoRefreshToken: false),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TasksScreen(showRouteAppBar: true),
                ),
              ),
              child: const Text('Open Pomodoro tasks'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Pomodoro tasks'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open Pomodoro tasks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
