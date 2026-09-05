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
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app({required Locale locale, required Size mediaSize}) {
    return ProviderScope(
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
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: mediaSize),
          child: child!,
        ),
        home: const TasksScreen(),
      ),
    );
  }

  testWidgets('phone uses compact filters and only one Add task action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      app(locale: const Locale('en'), mediaSize: const Size(360, 800)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-task-filter-header')), findsOne);
    expect(find.byKey(const ValueKey('mobile-task-status-strip')), findsOne);
    expect(_dropdowns(), findsNothing);
    expect(find.text('Add task'), findsOneWidget);
    expect(find.text('Your local plan is clear.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final button = find.byKey(const ValueKey('mobile-task-filter-button'));
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-filter-sheet')), findsOneWidget);
    expect(find.text('Filter tasks'), findsOneWidget);
    expect(_dropdowns(), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps the complete inline filter workspace', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      app(locale: const Locale('en'), mediaSize: const Size(1100, 800)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-task-filter-header')),
      findsNothing,
    );
    expect(_dropdowns(), findsNWidgets(5));
    expect(find.text('Add task'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('mobile filter copy is translated in every supported locale', () {
    const expected = {
      'en': 'Filter tasks',
      'ar': 'تصفية المهام',
      'de': 'Aufgaben filtern',
      'pl': 'Filtruj zadania',
    };
    for (final locale in AppLocalizations.supportedLocales) {
      expect(
        AppLocalizations(locale).text('task_filters'),
        expected[locale.languageCode],
      );
    }
  });
}

Finder _dropdowns() => find.byWidgetPredicate(
  (widget) =>
      widget.runtimeType.toString().startsWith('DropdownButtonFormField<'),
  description: 'DropdownButtonFormField of any value type',
);
