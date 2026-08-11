import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installed-app resource handoff is bounded and deterministic', () {
    final source = File(
      'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/'
      'MainActivity.kt',
    ).readAsStringSync();

    final exact = source.indexOf('resolution = "exact_deep_link"');
    final origin = source.indexOf('resolution = "origin_deep_link"');
    final linked = source.indexOf('resolution = "task_linked_application"');
    final launcher = source.indexOf('resolution = "launcher_domain_token"');

    expect(exact, greaterThanOrEqualTo(0));
    expect(origin, greaterThan(exact));
    expect(linked, greaterThan(origin));
    expect(launcher, greaterThan(linked));
    expect(source, contains('handlers.singleOrNull()'));
    expect(source, contains('matches.singleOrNull()'));
  });

  test('installed application picker is backed by launcher applications', () {
    final source = File(
      'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('"listInstalledApplications"'));
    expect(source, contains('installedLauncherApplications()'));
    expect(source, contains('Intent.ACTION_MAIN'));
    expect(source, contains('Intent.CATEGORY_LAUNCHER'));
    expect(
      source,
      contains('queryIntentHandlers(launcherIntent, defaultOnly = false)'),
    );
    expect(source, contains('"identifier" to activity.packageName'));
    expect(source, contains('handler.loadLabel(packageManager)'));
  });

  test(
    'manifest exposes web and launcher handlers without broad visibility',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.intent.action.VIEW'));
      expect(manifest, contains('android.intent.action.MAIN'));
      expect(manifest, contains('android.intent.category.LAUNCHER'));
      expect(
        manifest,
        isNot(contains('android.permission.QUERY_ALL_PACKAGES')),
      );
    },
  );
}
