import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/auth/data/google_oauth_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  const authorizationUrl = 'https://example.supabase.co/auth/v1/authorize';

  test('Android Google OAuth prefers a Custom Tab, not the task browser', () {
    final plan = googleOAuthLaunchPlan(
      isWeb: false,
      platform: TargetPlatform.android,
    );

    expect(plan.mode, LaunchMode.inAppBrowserView);
    expect(plan.mode, isNot(LaunchMode.inAppWebView));
    expect(plan.fallbackMode, LaunchMode.externalApplication);
    expect(plan.usesTemporaryBrowserSurface, isTrue);
    expect(plan.appCanForceCloseBrowserSurface, isFalse);
  });

  test(
    'Windows Google OAuth uses the system browser and does not claim close',
    () {
      final plan = googleOAuthLaunchPlan(
        isWeb: false,
        platform: TargetPlatform.windows,
      );

      expect(plan.mode, LaunchMode.externalApplication);
      expect(plan.fallbackMode, LaunchMode.externalApplication);
      expect(plan.appCanForceCloseBrowserSurface, isFalse);
    },
  );

  test(
    'falls back to the system browser when Custom Tabs are unavailable',
    () async {
      LaunchMode? launchedMode;
      final launched = await launchGoogleOAuthUrl(
        Uri.parse(authorizationUrl),
        plan: googleOAuthLaunchPlan(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        supportsMode: (_) async => false,
        launch: (_, mode) async {
          launchedMode = mode;
          return true;
        },
      );

      expect(launched, isTrue);
      expect(launchedMode, LaunchMode.externalApplication);
    },
  );

  test('only launches HTTPS authorization URLs', () async {
    await expectLater(
      launchGoogleOAuthUrl(
        Uri.parse('http://example.supabase.co/auth/v1/authorize'),
        plan: googleOAuthLaunchPlan(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('auth screen requests the URL before selecting the browser surface', () {
    final source = File(
      'lib/features/auth/presentation/auth_screen.dart',
    ).readAsStringSync();

    expect(source, contains('getOAuthSignInUrl('));
    expect(source, contains('launchGoogleOAuthUrl('));
    expect(source, isNot(contains('authScreenLaunchMode:')));
    expect(source, isNot(contains('signInWithOAuth(')));
    expect(source, contains('_googlePending = true'));
    expect(source, contains("text('auth_google_browser_opened')"));
    expect(source, contains('Timer(const Duration(minutes: 2)'));
  });

  test('DayVector owns one visible callback exchange path', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final backgroundSource = File(
      'lib/core/platform/background_execution_action_service.dart',
    ).readAsStringSync();

    expect(mainSource, contains('detectSessionInUri: false'));
    expect(
      mainSource,
      contains(
        'AuthCallbackService.instance.start(Supabase.instance.client.auth)',
      ),
    );
    expect(backgroundSource, contains('detectSessionInUri: false'));
  });

  test('Android and Windows both route the OAuth callback back to the app', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final installer = File('installer/taskmaster-pro.iss').readAsStringSync();

    expect(manifest, contains('android:scheme="pro.taskmaster.app"'));
    expect(manifest, contains('android:host="auth-callback"'));
    expect(manifest, contains('android:launchMode="singleTop"'));
    expect(
      manifest,
      contains('android.support.customtabs.action.CustomTabsService'),
    );
    expect(installer, contains('Software\\Classes\\pro.taskmaster.app'));
    expect(installer, contains('"%1"'));

    final windowsRunner = File(
      'windows/runner/win32_window.cpp',
    ).readAsStringSync();
    expect(windowsRunner, contains('SendAppLinkToInstance()'));

    final windowsMain = File('windows/runner/main.cpp').readAsStringSync();
    expect(
      windowsMain,
      contains('#include <app_links/app_links_plugin_c_api.h>'),
    );
    expect(windowsMain, contains('SendAppLinkToInstance()'));
  });
}
