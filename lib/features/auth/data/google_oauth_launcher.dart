import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The browser surface chosen for a Google OAuth request.
///
/// Google requires a real browser context on Android.  A Custom Tab preserves
/// the provider's browser cookies and hands the `pro.taskmaster.app` callback
/// straight back to the application without putting the authentication page in
/// the task workspace browser.
@immutable
class GoogleOAuthLaunchPlan {
  const GoogleOAuthLaunchPlan({
    required this.mode,
    required this.fallbackMode,
    required this.usesTemporaryBrowserSurface,
    required this.appCanForceCloseBrowserSurface,
  });

  /// Preferred URL-launcher mode for this platform.
  final LaunchMode mode;

  /// The safe browser fallback when the preferred surface is unavailable.
  final LaunchMode fallbackMode;

  /// Whether this opens a browser surface that is separate from the app UI.
  final bool usesTemporaryBrowserSurface;

  /// Whether the application owns a closeable browser surface.
  ///
  /// Android Custom Tabs and Windows' system browser are owned by the browser,
  /// so the deep link foregrounds DayVector but the app must not attempt
  /// to close a browser process it does not own.
  final bool appCanForceCloseBrowserSurface;
}

/// Selects the Google OAuth surface without involving the task browser.
///
/// This is intentionally separate from Supabase's `signInWithOAuth` helper:
/// the helper force-selects a full external browser for Google on Android,
/// even if the caller asks for a Custom Tab.
GoogleOAuthLaunchPlan googleOAuthLaunchPlan({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) {
    return const GoogleOAuthLaunchPlan(
      mode: LaunchMode.platformDefault,
      fallbackMode: LaunchMode.platformDefault,
      usesTemporaryBrowserSurface: false,
      appCanForceCloseBrowserSurface: false,
    );
  }

  if (platform == TargetPlatform.android) {
    return const GoogleOAuthLaunchPlan(
      mode: LaunchMode.inAppBrowserView,
      fallbackMode: LaunchMode.externalApplication,
      usesTemporaryBrowserSurface: true,
      appCanForceCloseBrowserSurface: false,
    );
  }

  return const GoogleOAuthLaunchPlan(
    mode: LaunchMode.externalApplication,
    fallbackMode: LaunchMode.externalApplication,
    usesTemporaryBrowserSurface: true,
    appCanForceCloseBrowserSurface: false,
  );
}

GoogleOAuthLaunchPlan currentGoogleOAuthLaunchPlan() {
  return googleOAuthLaunchPlan(isWeb: kIsWeb, platform: defaultTargetPlatform);
}

typedef OAuthLaunchModeSupport = Future<bool> Function(LaunchMode mode);
typedef OAuthUrlLaunch = Future<bool> Function(Uri url, LaunchMode mode);

/// Opens a Supabase-generated Google OAuth URL in the platform's best surface.
///
/// On Android this first asks for a Chrome/compatible Custom Tab.  The return
/// URL is the registered app link, so Android returns to DayVector after
/// authentication.  If a device has no Custom Tabs provider, it falls back to
/// the system browser rather than embedding Google in an app WebView.
Future<bool> launchGoogleOAuthUrl(
  Uri authorizationUrl, {
  GoogleOAuthLaunchPlan? plan,
  OAuthLaunchModeSupport? supportsMode,
  OAuthUrlLaunch? launch,
}) async {
  if (!authorizationUrl.isScheme('https')) {
    throw ArgumentError.value(
      authorizationUrl,
      'authorizationUrl',
      'Google OAuth must start from an HTTPS authorization URL.',
    );
  }

  final selectedPlan = plan ?? currentGoogleOAuthLaunchPlan();
  final isPreferredModeSupported = await (supportsMode ?? supportsLaunchMode)(
    selectedPlan.mode,
  );
  final mode = isPreferredModeSupported
      ? selectedPlan.mode
      : selectedPlan.fallbackMode;
  final open =
      launch ??
      (Uri url, LaunchMode launchMode) =>
          launchUrl(url, mode: launchMode, webOnlyWindowName: '_self');
  return open(authorizationUrl, mode);
}
