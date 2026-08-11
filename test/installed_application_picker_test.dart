import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/tasks/data/installed_application_service.dart';
import 'package:taskmaster_pro/features/tasks/presentation/installed_application_picker_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('taskmasterpro/resources'),
          null,
        );
  });

  test('installed applications are searchable, sorted, and de-duplicated', () {
    const applications = [
      InstalledApplication(
        identifier: 'com.duolingo',
        displayName: 'Duolingo',
        platform: 'android',
      ),
      InstalledApplication(
        identifier: 'org.freecodecamp',
        displayName: 'freeCodeCamp',
        platform: 'android',
      ),
      InstalledApplication(
        identifier: 'COM.DUOLINGO',
        displayName: 'Duplicate Duolingo',
        platform: 'android',
      ),
    ];

    expect(
      filterInstalledApplications(
        applications,
        '',
      ).map((application) => application.displayName),
      ['Duolingo', 'freeCodeCamp'],
    );
    expect(
      filterInstalledApplications(applications, 'free').single.identifier,
      'org.freecodecamp',
    );
    expect(
      filterInstalledApplications(applications, 'duolingo').single.identifier,
      'com.duolingo',
    );
  });

  test('catalog and task-rule matching use stable natural identities', () {
    expect(
      applicationCatalogMatches(
        const {'platform': 'Android', 'application_identifier': 'COM.DUOLINGO'},
        platform: 'android',
        identifier: 'com.duolingo',
      ),
      isTrue,
    );
    expect(
      applicationRuleMatchesTask(
        const {
          'application_id': 'app-1',
          'scope_type': 'task',
          'scope_id': 'task-1',
          'target_type': 'task_occurrence',
          'target_id': 'task-1',
        },
        applicationId: 'app-1',
        taskId: 'task-1',
      ),
      isTrue,
    );
  });

  test('task application identities are stable across device discoveries', () {
    final firstApplication = applicationCatalogIdForTaskConnection(
      userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
      platform: 'Android',
      applicationIdentifier: ' COM.DUOLINGO ',
    );
    final secondApplication = applicationCatalogIdForTaskConnection(
      userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
      platform: 'android',
      applicationIdentifier: 'com.duolingo',
    );
    expect(firstApplication, secondApplication);
    expect(
      taskApplicationLinkIdFor(
        userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
        taskOccurrenceId: '47b83ebf-2163-48d3-a1bc-c568167a7b29',
        applicationId: firstApplication,
      ),
      taskApplicationLinkIdFor(
        userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
        taskOccurrenceId: '47b83ebf-2163-48d3-a1bc-c568167a7b29',
        applicationId: secondApplication,
      ),
    );
  });

  test('application label fallback never returns an empty chip', () {
    expect(
      resolvedApplicationDisplayName(
        userOverride: 'My language practice',
        normalizedName: 'Duolingo',
        displayNameSnapshot: 'Old name',
        rawIdentifier: 'com.duolingo',
        unknownLabel: 'Unknown application',
      ),
      'My language practice',
    );
    expect(
      resolvedApplicationDisplayName(
        displayNameSnapshot: ' ',
        rawIdentifier: 'com.openai.chatgpt',
        unknownLabel: 'Unknown application',
      ),
      'Chatgpt',
    );
    expect(
      resolvedApplicationDisplayName(unknownLabel: 'Unknown application'),
      'Unknown application',
    );
  });

  test('Android package is recovered from plain and activity identifiers', () {
    expect(
      androidPackageNameFromApplicationIdentifier('com.duolingo'),
      'com.duolingo',
    );
    expect(
      androidPackageNameFromApplicationIdentifier(
        'android|foreground_user_surface|com.duolingo',
      ),
      'com.duolingo',
    );
    expect(androidPackageNameFromApplicationIdentifier('Code.exe'), isNull);
  });

  test(
    'Android service reads launcher applications from the native channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('taskmasterpro/resources'),
            (call) async {
              expect(call.method, 'listInstalledApplications');
              return [
                {
                  'identifier': 'com.duolingo',
                  'displayName': 'Duolingo',
                  'platform': 'android',
                },
                {
                  'identifier': 'org.freecodecamp',
                  'displayName': 'freeCodeCamp',
                  'platform': 'android',
                },
              ];
            },
          );

      final applications = await const InstalledApplicationService()
          .listInstalledApplications();

      expect(applications, hasLength(2));
      expect(applications.first.displayName, 'Duolingo');
      expect(applications.first.identifier, 'com.duolingo');
    },
  );

  testWidgets(
    'picker filters installed apps and returns the selected package',
    (tester) async {
      InstalledApplication? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  selected = await showInstalledApplicationPicker(
                    context,
                    applications: Future.value(const [
                      InstalledApplication(
                        identifier: 'com.duolingo',
                        displayName: 'Duolingo',
                        platform: 'android',
                      ),
                      InstalledApplication(
                        identifier: 'org.freecodecamp',
                        displayName: 'freeCodeCamp',
                        platform: 'android',
                      ),
                    ]),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Duolingo'), findsOneWidget);
      expect(find.text('freeCodeCamp'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'duo');
      await tester.pump();
      expect(find.text('Duolingo'), findsOneWidget);
      expect(find.text('freeCodeCamp'), findsNothing);

      await tester.tap(find.text('Duolingo'));
      await tester.pumpAndSettle();
      expect(selected?.identifier, 'com.duolingo');
    },
  );
}
