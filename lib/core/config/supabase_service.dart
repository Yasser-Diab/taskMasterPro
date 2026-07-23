import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../security/supabase_key_guard.dart';
import '../theme/app_brand.dart';
import 'app_config.dart';
import 'app_environment.dart';

enum AppRole { owner, admin, support, user }

enum UserSex { male, female, preferNotToSay, custom }

extension UserSexX on UserSex {
  String get storageValue => switch (this) {
    UserSex.preferNotToSay => 'prefer_not_to_say',
    UserSex.male => 'male',
    UserSex.female => 'female',
    UserSex.custom => 'custom',
  };

  static UserSex? fromStorage(String? value) {
    return switch (value) {
      'male' => UserSex.male,
      'female' => UserSex.female,
      'prefer_not_to_say' => UserSex.preferNotToSay,
      'custom' => UserSex.custom,
      _ => null,
    };
  }
}

enum AppStartupStatus {
  initializing,
  signedOut,
  loadingAccount,
  needsOnboarding,
  ready,
  recoverableError,
}

class AppStartupState {
  const AppStartupState({
    required this.status,
    this.userId,
    this.error,
    this.remoteState,
  });

  final AppStartupStatus status;
  final String? userId;
  final Object? error;
  final Map<String, dynamic>? remoteState;
}

extension AppRoleX on AppRole {
  static AppRole fromStorage(String? value) {
    return switch (value) {
      'owner' => AppRole.owner,
      'admin' => AppRole.admin,
      'support' => AppRole.support,
      _ => AppRole.user,
    };
  }
}

class AppUserProfile {
  const AppUserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.username,
    required this.locale,
    required this.role,
    required this.onboardingCompleted,
    this.sex,
    this.cycleTrackingEnabled = false,
    this.cycleDataSyncEnabled = false,
    this.pendingEmail,
    this.avatarPath,
    this.avatarSignedUrl,
  });

  final String id;
  final String email;
  final String displayName;
  final String? username;
  final String locale;
  final AppRole role;
  final bool onboardingCompleted;
  final UserSex? sex;
  final bool cycleTrackingEnabled;
  final bool cycleDataSyncEnabled;
  final String? pendingEmail;
  final String? avatarPath;
  final String? avatarSignedUrl;

  bool get isOwner => role == AppRole.owner;

  String get preferredName {
    final name = displayName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) {
      return handle;
    }
    return email.split('@').first;
  }

  String get initials {
    final source = preferredName.trim();
    if (source.isEmpty) {
      return '?';
    }
    final words = source
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return '${String.fromCharCode(words.first.runes.first)}${String.fromCharCode(words.last.runes.first)}'
          .toUpperCase();
    }
    final runes = source.runes.take(2).toList();
    return String.fromCharCodes(runes).toUpperCase();
  }

  AppUserProfile copyWith({
    String? email,
    String? displayName,
    String? username,
    String? locale,
    AppRole? role,
    bool? onboardingCompleted,
    UserSex? sex,
    bool? cycleTrackingEnabled,
    bool? cycleDataSyncEnabled,
    String? pendingEmail,
    String? avatarPath,
    String? avatarSignedUrl,
    bool clearUsername = false,
    bool clearSex = false,
    bool clearPendingEmail = false,
    bool clearAvatarPath = false,
    bool clearAvatarSignedUrl = false,
  }) {
    return AppUserProfile(
      id: id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      username: clearUsername ? null : username ?? this.username,
      locale: locale ?? this.locale,
      role: role ?? this.role,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      sex: clearSex ? null : sex ?? this.sex,
      cycleTrackingEnabled: cycleTrackingEnabled ?? this.cycleTrackingEnabled,
      cycleDataSyncEnabled: cycleDataSyncEnabled ?? this.cycleDataSyncEnabled,
      pendingEmail: clearPendingEmail
          ? null
          : pendingEmail ?? this.pendingEmail,
      avatarPath: clearAvatarPath ? null : avatarPath ?? this.avatarPath,
      avatarSignedUrl: clearAvatarSignedUrl
          ? null
          : avatarSignedUrl ?? this.avatarSignedUrl,
    );
  }
}

class AccountExportResult {
  const AccountExportResult({required this.data, required this.generatedAt});

  final Map<String, dynamic> data;
  final DateTime generatedAt;

  String get fileName =>
      'taskmaster-pro-export-${generatedAt.toIso8601String().replaceAll(':', '-')}.json';
}

class AppDeviceSession {
  const AppDeviceSession({
    required this.id,
    required this.userId,
    required this.deviceName,
    required this.platform,
    required this.platformVersion,
    required this.appVersion,
    required this.buildNumber,
    required this.lastSeenAt,
    required this.notificationEnabled,
    this.logoutRequestedAt,
  });

  final String id;
  final String userId;
  final String deviceName;
  final String platform;
  final String platformVersion;
  final String appVersion;
  final String buildNumber;
  final DateTime? lastSeenAt;
  final bool notificationEnabled;
  final DateTime? logoutRequestedAt;

  String get displayName {
    final trimmed = deviceName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return platform == 'android' ? 'Android device' : 'Windows device';
  }

  factory AppDeviceSession.fromMap(Map<String, dynamic> row) {
    return AppDeviceSession(
      id: row['id']?.toString() ?? '',
      userId: row['user_id']?.toString() ?? '',
      deviceName: row['device_name']?.toString() ?? '',
      platform: row['platform']?.toString() ?? '',
      platformVersion: row['platform_version']?.toString() ?? '',
      appVersion: row['app_version']?.toString() ?? '',
      buildNumber: row['build_number']?.toString() ?? '',
      lastSeenAt: DateTime.tryParse(row['last_seen_at']?.toString() ?? ''),
      notificationEnabled: row['notification_enabled'] as bool? ?? false,
      logoutRequestedAt: DateTime.tryParse(
        row['logout_requested_at']?.toString() ?? '',
      ),
    );
  }
}

class SupabaseService extends ChangeNotifier {
  static const _startupOperationTimeout = Duration(seconds: 8);
  static const _startupRefreshTimeout = Duration(seconds: 15);

  bool _initialized = false;
  String? _fingerprint;
  String? _statusMessage;
  SupabaseClient? _client;
  bool _passwordRecoveryPending = false;
  AppUserProfile? _profile;
  AppStartupState _startupState = const AppStartupState(
    status: AppStartupStatus.initializing,
  );
  String? _bootstrappedUserId;
  Future<void>? _currentBootstrap;
  Map<String, dynamic>? _startupDiagnostics;
  DateTime? _lastFullRemoteRefreshAt;
  bool _rememberSession = true;

  bool get isInitialized => _initialized;
  String? get statusMessage => _statusMessage;
  String get connectionStatusLabel =>
      _initialized ? 'Server connected' : 'Connection unavailable';

  SupabaseClient? get clientOrNull => _client;

  User? get currentUser => clientOrNull?.auth.currentUser;
  bool get isSignedIn => clientOrNull?.auth.currentSession != null;
  bool get isPasswordRecoveryPending => _passwordRecoveryPending;
  AppUserProfile? get profile => _profile;
  AppStartupState get startupState => _startupState;
  Map<String, dynamic>? get startupDiagnostics => _startupDiagnostics;
  DateTime? get lastFullRemoteRefreshAt => _lastFullRemoteRefreshAt;
  bool get isOwner => _profile?.isOwner ?? false;
  bool get onboardingCompleted => _profile?.onboardingCompleted ?? false;
  Stream<AuthState>? get onAuthStateChange =>
      clientOrNull?.auth.onAuthStateChange;

  Future<String?> initialize(AppConfig config) async {
    final target = AppEnvironment.supabaseTarget;
    if (target == null || !target.isComplete) {
      _statusMessage =
          'Connection unavailable. Supabase build environment is missing.';
      _startupState = const AppStartupState(status: AppStartupStatus.signedOut);
      notifyListeners();
      return _statusMessage;
    }

    final urlError = SupabaseKeyGuard.validateUrl(target.url);
    if (urlError != null) {
      _statusMessage = urlError;
      _startupState = AppStartupState(
        status: AppStartupStatus.recoverableError,
        error: urlError,
      );
      notifyListeners();
      return urlError;
    }

    final keyError = SupabaseKeyGuard.validatePublicClientKey(target.publicKey);
    if (keyError != null) {
      _statusMessage = keyError;
      _startupState = AppStartupState(
        status: AppStartupStatus.recoverableError,
        error: keyError,
      );
      notifyListeners();
      return keyError;
    }

    final nextFingerprint =
        '${target.url.trim()}|${target.publicKey.trim().hashCode}';

    if (_initialized) {
      if (nextFingerprint != _fingerprint) {
        _statusMessage =
            'Server configuration changed. Restart the app to switch projects.';
        notifyListeners();
        return _statusMessage;
      }
      await _applyRememberSessionPreference(config.rememberSession);
      return null;
    }

    try {
      _rememberSession = config.rememberSession;
      _startupState = const AppStartupState(
        status: AppStartupStatus.initializing,
      );
      notifyListeners();
      _client = SupabaseClient(
        target.url.trim(),
        target.publicKey.trim(),
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      _initialized = true;
      _fingerprint = nextFingerprint;
      _statusMessage = null;
      await _restorePersistedSession(config.rememberSession);
      await resolveStartupState();
      notifyListeners();
      return null;
    } on Object catch (_) {
      _statusMessage =
          'Connection unavailable. Check your network and try again.';
      _startupState = AppStartupState(
        status: AppStartupStatus.recoverableError,
        error: _statusMessage,
      );
      notifyListeners();
      return _statusMessage;
    }
  }

  Future<String?> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final client = clientOrNull;
    if (client == null) {
      return 'Connection unavailable. Retry before signing in.';
    }

    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _persistCurrentSessionIfAllowed();
      await resolveStartupState(force: true);
      notifyListeners();
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object catch (_) {
      return 'Sign-in failed. Check your connection and try again.';
    }
  }

  Future<({String? url, String? error})> googleOAuthSignInUrl() async {
    final client = clientOrNull;
    if (client == null) {
      return (
        url: null,
        error: 'Connection unavailable. Retry before signing in.',
      );
    }

    try {
      final response = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: AppBrand.authCallbackUri,
        scopes: 'email profile',
      );
      final providerError = await _oauthProviderConfigurationError(
        response.url,
      );
      if (providerError != null) {
        return (url: null, error: providerError);
      }
      return (url: response.url, error: null);
    } on AuthException catch (error) {
      return (
        url: null,
        error: _friendlyGoogleOAuthError(error.message),
      );
    } on Object catch (_) {
      return (
        url: null,
        error:
            'Could not open Google sign-in. Check your connection and try again.',
      );
    }
  }

  Future<String?> _oauthProviderConfigurationError(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await httpClient.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode < HttpStatus.badRequest) {
        await response.drain<void>();
        return null;
      }
      final body = await utf8.decoder.bind(response).join();
      return _friendlyGoogleOAuthError(body);
    } on Object {
      return null;
    } finally {
      httpClient.close(force: true);
    }
  }

  String _friendlyGoogleOAuthError(String rawMessage) {
    final lowered = rawMessage.toLowerCase();
    if (lowered.contains('unsupported provider') ||
        lowered.contains('provider is not enabled')) {
      return 'Google sign-in is not enabled for this Supabase project yet. Enable the Google provider in Supabase Auth, then try again.';
    }
    return rawMessage;
  }

  Future<String?> signUpWithPassword({
    required String fullName,
    required String email,
    required String password,
    required String preferredLanguage,
  }) async {
    final client = clientOrNull;
    if (client == null) {
      return 'Connection unavailable. Retry before creating an account.';
    }

    try {
      await client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: AppBrand.authCallbackUri,
        data: {
          'full_name': fullName.trim(),
          'preferred_language': preferredLanguage,
        },
      );
      await _persistCurrentSessionIfAllowed();
      await resolveStartupState(force: true);
      return null;
    } on AuthException catch (error) {
      final lowered = error.message.toLowerCase();
      if (lowered.contains('already') || lowered.contains('registered')) {
        return 'An account with this email already exists.';
      }
      return error.message;
    } on Object catch (_) {
      return 'Could not create the account right now.';
    }
  }

  Future<String?> resendVerificationEmail(String email) async {
    final client = clientOrNull;
    if (client == null) {
      return 'Connection unavailable. Retry before resending verification.';
    }

    try {
      await client.auth.resend(
        email: email.trim(),
        type: OtpType.signup,
        emailRedirectTo: AppBrand.authCallbackUri,
      );
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object catch (_) {
      return 'Could not resend the verification email right now.';
    }
  }

  Future<String?> resetPasswordForEmail(String email) async {
    final client = clientOrNull;
    if (client == null) {
      return 'Connection unavailable. Retry before requesting a reset.';
    }

    try {
      await client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: AppBrand.authCallbackUri,
      );
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object catch (_) {
      return 'Could not request a password reset right now.';
    }
  }

  Future<void> signOut({bool allDevices = false}) async {
    final client = clientOrNull;
    if (client == null) {
      return;
    }
    await client.auth.signOut(
      scope: allDevices ? SignOutScope.global : SignOutScope.local,
    );
    await _removePersistedSession();
    _passwordRecoveryPending = false;
    _profile = null;
    _bootstrappedUserId = null;
    _startupDiagnostics = null;
    _startupState = const AppStartupState(status: AppStartupStatus.signedOut);
    notifyListeners();
  }

  Future<List<AppDeviceSession>> listDeviceSessions() async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return const [];
    }
    try {
      final rows = await client
          .from('devices')
          .select(
            'id,user_id,device_name,platform,platform_version,app_version,'
            'build_number,last_seen_at,notification_enabled,'
            'logout_requested_at',
          )
          .eq('user_id', user.id)
          .order('last_seen_at', ascending: false);
      return rows
          .whereType<Map>()
          .map((row) => AppDeviceSession.fromMap(Map<String, dynamic>.from(row)))
          .where((device) => device.id.isNotEmpty)
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<String?> requestDeviceLogout(String deviceId) async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return 'Connection unavailable. Retry while signed in.';
    }
    final targetId = deviceId.trim();
    if (targetId.isEmpty) {
      return 'Device not found.';
    }
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await client
          .from('devices')
          .update({
            'logout_requested_at': now,
            'updated_at': now,
          })
          .eq('id', targetId)
          .eq('user_id', user.id);
      try {
        final channel = client.channel(
          'taskmaster:user:${user.id}:runtime',
          opts: const RealtimeChannelConfig(private: true),
        );
        channel.subscribe();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await channel.sendBroadcastMessage(
          event: 'device_logout_requested',
          payload: {'device_id': targetId},
        );
        await client.removeChannel(channel);
      } on Object {
        // The target device also checks its row on reconnect/resubscribe.
      }
      return null;
    } on Object catch (error) {
      return error.toString();
    }
  }

  Future<String?> handleAuthDeepLink(String link) async {
    final client = clientOrNull;
    if (client == null) {
      return 'Connection unavailable. Retry before opening this link.';
    }

    final uri = Uri.tryParse(link);
    if (uri == null || !_isAuthUri(uri)) {
      return null;
    }

    try {
      final response = await client.auth.getSessionFromUrl(uri);
      if (response.redirectType == 'recovery') {
        markPasswordRecoveryPending();
      } else {
        await _persistCurrentSessionIfAllowed();
        await resolveStartupState(force: true);
      }
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object catch (_) {
      return 'Could not open the authentication link.';
    }
  }

  Future<String?> updatePassword(String password) async {
    final client = clientOrNull;
    if (client == null) {
      return 'Connection unavailable. Retry before updating your password.';
    }

    try {
      await client.auth.updateUser(UserAttributes(password: password));
      _passwordRecoveryPending = false;
      notifyListeners();
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object catch (_) {
      return 'Could not update the password right now.';
    }
  }

  Future<void> refreshProfile() async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      _profile = null;
      return;
    }

    try {
      final results = await Future.wait<Object?>([
        client
            .from('profiles')
            .select(
              'id,display_name,username,preferred_language,onboarding_completed,avatar_path,sex,time_zone_mode,fixed_time_zone_id,clock_format',
            )
            .eq('id', user.id)
            .maybeSingle(),
        client
            .from('user_settings')
            .select('language,cycle_sync_enabled')
            .eq('user_id', user.id)
            .maybeSingle(),
      ]);
      final profileRow = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : null;
      final settingsRow = results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
          : null;
      final metadata = user.userMetadata ?? const <String, dynamic>{};
      final metadataDisplayName =
          _metadataString(metadata, 'full_name') ??
          _metadataString(metadata, 'name');
      final metadataLanguage = _normalizeProfileLanguage(
        _metadataString(metadata, 'preferred_language'),
      );
      final rowDisplayName = profileRow?['display_name']?.toString().trim();
      final emailPrefix = user.email?.split('@').first.trim() ?? '';
      final displayName =
          metadataDisplayName != null &&
              metadataDisplayName.isNotEmpty &&
              (rowDisplayName == null ||
                  rowDisplayName.isEmpty ||
                  rowDisplayName == emailPrefix)
          ? metadataDisplayName
          : rowDisplayName ?? '';
      final locale = _normalizeProfileLanguage(
        profileRow?['preferred_language']?.toString() ??
            settingsRow?['language']?.toString() ??
            metadataLanguage,
      );
      if (metadataDisplayName != null &&
          metadataDisplayName.isNotEmpty &&
          metadataDisplayName != rowDisplayName &&
          (rowDisplayName == null ||
              rowDisplayName.isEmpty ||
              rowDisplayName == emailPrefix)) {
        unawaited(
          _repairProfileFromMetadata(
            user.id,
            displayName: metadataDisplayName,
            language: locale,
          ),
        );
      }

      final avatarPath = profileRow?['avatar_path']?.toString();
      String? avatarSignedUrl;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        try {
          avatarSignedUrl = await client.storage
              .from('avatars')
              .createSignedUrl(avatarPath, 3600);
        } on Object {
          avatarSignedUrl = null;
        }
      }

      _profile = AppUserProfile(
        id: user.id,
        email: user.email ?? '',
        displayName: displayName,
        username: profileRow?['username']?.toString(),
        locale: locale,
        role: AppRole.user,
        onboardingCompleted:
            profileRow?['onboarding_completed'] as bool? ?? false,
        sex: UserSexX.fromStorage(profileRow?['sex']?.toString()),
        cycleTrackingEnabled:
            settingsRow?['cycle_sync_enabled'] as bool? ?? false,
        cycleDataSyncEnabled:
            settingsRow?['cycle_sync_enabled'] as bool? ?? false,
        pendingEmail: null,
        avatarPath: avatarPath,
        avatarSignedUrl: avatarSignedUrl,
      );
    } on Object {
      _profile = AppUserProfile(
        id: user.id,
        email: user.email ?? '',
        displayName: '',
        username: null,
        locale: 'en',
        role: AppRole.user,
        onboardingCompleted: false,
        sex: null,
        cycleTrackingEnabled: false,
        cycleDataSyncEnabled: false,
      );
    }
  }

  String? _metadataString(Map<String, dynamic> metadata, String key) {
    final value = metadata[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _normalizeProfileLanguage(String? value) {
    return switch (value) {
      'ar' => 'ar',
      'de' => 'de',
      _ => 'en',
    };
  }

  Future<void> _repairProfileFromMetadata(
    String userId, {
    required String displayName,
    required String language,
  }) async {
    final client = clientOrNull;
    if (client == null) return;
    try {
      await client
          .from('profiles')
          .update({
            'display_name': displayName,
            'preferred_language': language,
          })
          .eq('id', userId);
      await client.from('user_settings').upsert({
        'user_id': userId,
        'language': language,
      }, onConflict: 'user_id');
    } on Object {
      // The in-memory profile already uses metadata; repair can retry later.
    }
  }

  Future<Map<String, dynamic>?> bootstrapCurrentUser({
    bool strict = false,
    bool installOwnerTemplates = true,
  }) async {
    final client = clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      return null;
    }
    try {
      final result = await client.rpc('bootstrap_current_user');
      if (result is Map<String, dynamic>) {
        return result;
      }
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } on Object {
      if (strict) {
        rethrow;
      }
      // Older or unreachable databases should not block the cached app shell.
    }
    return null;
  }

  Future<void> resolveStartupState({bool force = false}) async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null) {
      _startupState = const AppStartupState(
        status: AppStartupStatus.recoverableError,
        error: 'Connection unavailable.',
      );
      notifyListeners();
      return;
    }
    if (user == null || client.auth.currentSession == null) {
      _profile = null;
      _bootstrappedUserId = null;
      _startupDiagnostics = null;
      _startupState = const AppStartupState(status: AppStartupStatus.signedOut);
      notifyListeners();
      return;
    }

    if (!force &&
        _bootstrappedUserId == user.id &&
        _startupState.status == AppStartupStatus.ready) {
      return;
    }

    if (_currentBootstrap != null) {
      return _currentBootstrap!;
    }

    final operation = _performStartupBootstrap(user.id);
    _currentBootstrap = operation;
    try {
      await operation;
    } finally {
      _currentBootstrap = null;
    }
  }

  Future<void> _performStartupBootstrap(String userId) async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      _startupState = const AppStartupState(status: AppStartupStatus.signedOut);
      notifyListeners();
      return;
    }

    _startupState = AppStartupState(
      status: AppStartupStatus.loadingAccount,
      userId: userId,
    );
    notifyListeners();

    if (kDebugMode) {
      debugPrint('AUTH USER ID: ${user.id}');
      debugPrint('AUTH EMAIL: ${user.email}');
    }

    Object? bootstrapError;
    try {
      await _withTimeout(
        bootstrapCurrentUser(strict: true, installOwnerTemplates: false),
        _startupOperationTimeout,
        'We could not prepare your account in time.',
      );
    } on Object catch (error) {
      bootstrapError = error;
      if (kDebugMode) {
        debugPrint('STARTUP BOOTSTRAP FAILED: $error');
      }
    }

    try {
      final remoteState = await _loadStartupState(
        client: client,
        user: user,
        bootstrapError: bootstrapError,
      );
      if (kDebugMode) {
        debugPrint('STARTUP STATE: $remoteState');
      }

      await refreshProfile();
      _startupDiagnostics = {
        ...remoteState,
        'authenticated_uuid': user.id,
        'authenticated_email': user.email,
        'loaded_profile_uuid': _profile?.id,
        if (bootstrapError != null)
          'bootstrap_error': bootstrapError.toString(),
      };

      final completed =
          remoteState['onboarding_completed'] == true ||
          _profile?.onboardingCompleted == true;
      _bootstrappedUserId = userId;
      _startupState = AppStartupState(
        status: completed
            ? AppStartupStatus.ready
            : AppStartupStatus.needsOnboarding,
        userId: userId,
        remoteState: _startupDiagnostics,
      );
      notifyListeners();
      unawaited(_refreshWorkspaceInBackground());
    } on Object catch (error) {
      _startupState = AppStartupState(
        status: AppStartupStatus.recoverableError,
        userId: userId,
        error: error,
      );
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _loadStartupState({
    required SupabaseClient client,
    required User user,
    required Object? bootstrapError,
  }) async {
    try {
      final results = await Future.wait<Object?>([
        _withTimeout(
          client
              .from('profiles')
              .select('id,onboarding_completed')
              .eq('id', user.id)
              .maybeSingle(),
          _startupOperationTimeout,
          'We could not load your profile in time.',
        ),
        _withTimeout(
          client
              .from('roadmaps')
              .select('id')
              .eq('user_id', user.id)
              .isFilter('deleted_at', null),
          _startupOperationTimeout,
          'We could not load your roadmaps in time.',
        ),
        _withTimeout(
          client
              .from('roadmap_phases')
              .select('id')
              .eq('user_id', user.id)
              .isFilter('deleted_at', null),
          _startupOperationTimeout,
          'We could not load your roadmap phases in time.',
        ),
        _withTimeout(
          client
              .from('tasks')
              .select('id')
              .eq('user_id', user.id)
              .isFilter('deleted_at', null),
          _startupOperationTimeout,
          'We could not load your tasks in time.',
        ),
        _withTimeout(
          client.from('task_domains').select('id').eq('user_id', user.id),
          _startupOperationTimeout,
          'We could not load your task domains in time.',
        ),
      ]);

      final profileRow = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : null;
      if (profileRow == null) {
        if (bootstrapError != null) {
          throw bootstrapError;
        }
        throw StateError('The user profile could not be loaded.');
      }

      return {
        'user_id': user.id,
        'email': user.email?.toLowerCase(),
        'role': 'user',
        'onboarding_completed': profileRow['onboarding_completed'] == true,
        'roadmap_count': _listLength(results[1]),
        'roadmap_phase_count': _listLength(results[2]),
        'roadmap_item_count': null,
        'task_count': _listLength(results[3]),
        'recurring_template_count': null,
        'task_domain_count': _listLength(results[4]),
        'startup_state_source': 'clean_baseline',
      };
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('STARTUP STATE LOAD FAILED: $error');
      }

      if (bootstrapError != null) throw bootstrapError;
      rethrow;
    }
  }

  Future<void> _refreshWorkspaceInBackground() async {
    try {
      final snapshot = await _withTimeout(
        fullRemoteRefresh(),
        _startupRefreshTimeout,
        'We could not download your workspace in time.',
      );
      _startupDiagnostics = {...?_startupDiagnostics, ...snapshot};
      notifyListeners();
    } on Object catch (error) {
      _startupDiagnostics = {
        ...?_startupDiagnostics,
        'last_synchronization_error': error.toString(),
      };
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> fullRemoteRefresh() async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('You need to sign in first.');
    }

    final userId = user.id;
    final results = await Future.wait<Object?>([
      client.from('profiles').select().eq('id', userId).single(),
      client.from('user_settings').select().eq('user_id', userId).maybeSingle(),
      client
          .from('roadmaps')
          .select()
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('created_at'),
      client
          .from('roadmap_phases')
          .select()
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('phase_order'),
      client
          .from('roadmap_milestones')
          .select()
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('created_at'),
      client
          .from('tasks')
          .select()
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('planned_start_at_utc', nullsFirst: false)
          .limit(1000),
    ]);

    final roadmaps = results[2] is List ? results[2] as List : const [];
    final phases = results[3] is List ? results[3] as List : const [];
    final items = results[4] is List ? results[4] as List : const [];
    final tasks = results[5] is List ? results[5] as List : const [];
    _lastFullRemoteRefreshAt = DateTime.now();
    final snapshot = <String, dynamic>{
      'profile_loaded': results[0] != null,
      'settings_loaded': results[1] != null,
      'remote_roadmap_count': roadmaps.length,
      'remote_roadmap_phase_count': phases.length,
      'remote_roadmap_milestone_count': items.length,
      'remote_task_count': tasks.length,
      'last_successful_full_refresh': _lastFullRemoteRefreshAt!
          .toIso8601String(),
    };
    _startupDiagnostics = {...?_startupDiagnostics, ...snapshot};
    notifyListeners();
    return snapshot;
  }

  Future<T> _withTimeout<T>(
    Future<T> operation,
    Duration timeout,
    String message,
  ) {
    return operation.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(message, timeout),
    );
  }

  int _listLength(Object? value) => value is List ? value.length : 0;

  void markSignedOutFromAuthEvent() {
    _profile = null;
    _bootstrappedUserId = null;
    _startupDiagnostics = null;
    _startupState = const AppStartupState(status: AppStartupStatus.signedOut);
    notifyListeners();
  }

  void markStartupError(Object error) {
    _startupState = AppStartupState(
      status: AppStartupStatus.recoverableError,
      userId: currentUser?.id,
      error: error,
    );
    notifyListeners();
  }

  Future<String?> markOnboardingComplete() async {
    final client = clientOrNull;
    final user = currentUser;
    if (client == null || user == null) {
      return 'Sign in before saving onboarding.';
    }

    try {
      await client
          .from('profiles')
          .update({'onboarding_completed': true})
          .eq('id', user.id);
      await refreshProfile();
      _bootstrappedUserId = user.id;
      _startupState = AppStartupState(
        status: AppStartupStatus.ready,
        userId: user.id,
        remoteState: _startupDiagnostics,
      );
      notifyListeners();
      return null;
    } on Object {
      return 'Could not save onboarding progress.';
    }
  }

  Future<String?> updateProfileIdentity({
    required String displayName,
    required String? username,
    UserSex? sex,
    bool? cycleTrackingEnabled,
    bool? cycleDataSyncEnabled,
    bool clearSex = false,
  }) async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return 'You need to sign in first.';
    }

    final cleanName = displayName.trim();
    final cleanUsername = username?.trim();
    if (cleanName.isEmpty || cleanName.length > 80) {
      return 'Use a display name between 1 and 80 characters.';
    }
    if (cleanUsername != null && cleanUsername.isNotEmpty) {
      if (cleanUsername.length < 3 || cleanUsername.length > 30) {
        return 'Use a username between 3 and 30 characters.';
      }
      if (RegExp(r'\s').hasMatch(cleanUsername)) {
        return 'Usernames cannot contain spaces.';
      }
    }

    try {
      final previous = _profile;
      if (previous != null && previous.id == user.id) {
        _profile = previous.copyWith(
          displayName: cleanName,
          username: cleanUsername == null || cleanUsername.isEmpty
              ? null
              : cleanUsername,
          clearUsername: cleanUsername == null || cleanUsername.isEmpty,
          sex: sex,
          clearSex: clearSex,
          cycleTrackingEnabled: cycleTrackingEnabled,
          cycleDataSyncEnabled: cycleDataSyncEnabled,
        );
        notifyListeners();
      }
      final updates = <String, Object?>{
        'display_name': cleanName,
        'username': cleanUsername == null || cleanUsername.isEmpty
            ? null
            : cleanUsername,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (clearSex || sex != null) {
        updates['sex'] = clearSex ? null : sex!.storageValue;
      }
      await client.from('profiles').update(updates).eq('id', user.id);
      if (cycleTrackingEnabled != null || cycleDataSyncEnabled != null) {
        final cycleSyncEnabled =
            cycleDataSyncEnabled ?? cycleTrackingEnabled ?? false;
        await client.from('user_settings').upsert({
          'user_id': user.id,
          'cycle_sync_enabled': cycleSyncEnabled,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id');
      }
      await client.auth.updateUser(
        UserAttributes(data: {'full_name': cleanName}),
      );
      await refreshProfile();
      notifyListeners();
      return null;
    } on PostgrestException catch (error) {
      await refreshProfile();
      notifyListeners();
      final message = error.message.toLowerCase();
      if (error.code == '23505' || message.contains('username')) {
        return 'This username is already in use.';
      }
      return 'Could not save your profile. Check your connection and try again.';
    } on AuthException catch (error) {
      await refreshProfile();
      notifyListeners();
      return error.message;
    } on Object {
      await refreshProfile();
      notifyListeners();
      return 'Could not save your profile. Check your connection and try again.';
    }
  }

  Future<String?> requestEmailChange(String email) async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return 'You need to sign in first.';
    }

    final cleanEmail = email.trim();
    if (!cleanEmail.contains('@')) {
      return 'Enter a valid email address.';
    }

    try {
      await client.auth.updateUser(
        UserAttributes(email: cleanEmail),
        emailRedirectTo: AppBrand.authCallbackUri,
      );
      await refreshProfile();
      notifyListeners();
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object {
      return 'Could not request the email change. Check your connection and try again.';
    }
  }

  Future<String?> uploadAvatarBytes({
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return 'You need to sign in first.';
    }

    final previousPath = _profile?.avatarPath;
    final path =
        '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
    try {
      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              cacheControl: '3600',
              upsert: false,
            ),
          );
      await client
          .from('profiles')
          .update({
            'avatar_path': path,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id);
      final signedUrl = await client.storage
          .from('avatars')
          .createSignedUrl(path, 3600);
      if (_profile != null && _profile!.id == user.id) {
        _profile = _profile!.copyWith(
          avatarPath: path,
          avatarSignedUrl: signedUrl,
        );
        notifyListeners();
      }
      if (previousPath != null && previousPath != path) {
        await client.storage.from('avatars').remove([previousPath]);
      }
      return null;
    } on Object {
      await refreshProfile();
      notifyListeners();
      return 'Could not upload the profile picture. Try a smaller JPEG, PNG or WebP image.';
    }
  }

  Future<String?> removeAvatar() async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return 'You need to sign in first.';
    }

    final previousPath = _profile?.avatarPath;
    try {
      final previous = _profile;
      if (previous != null && previous.id == user.id) {
        _profile = previous.copyWith(
          clearAvatarPath: true,
          clearAvatarSignedUrl: true,
        );
        notifyListeners();
      }
      await client
          .from('profiles')
          .update({
            'avatar_path': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id);
      if (previousPath != null && previousPath.isNotEmpty) {
        await client.storage.from('avatars').remove([previousPath]);
      }
      return null;
    } on Object {
      await refreshProfile();
      notifyListeners();
      return 'Could not remove the profile picture. Check your connection and try again.';
    }
  }

  Future<void> installOwnerTemplateIfNeeded() async {
    return;
  }

  Future<AccountExportResult?> exportMyData() async {
    final client = clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      return null;
    }
    final result = await client.rpc('export_my_data');
    final data = result is Map<String, dynamic>
        ? result
        : result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{'data': result};
    return AccountExportResult(data: data, generatedAt: DateTime.now());
  }

  Future<String?> requestAccountDeletion({
    required String password,
    required String confirmation,
  }) async {
    final client = clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return 'Sign in before deleting your account.';
    }
    if (password.trim().isEmpty) {
      return 'Confirm your password before deleting your account.';
    }

    try {
      await client.auth.signInWithPassword(
        email: user.email ?? '',
        password: password,
      );
      await client.rpc(
        'request_account_deletion',
        params: {'confirmation_text': confirmation.trim()},
      );
      await signOut(allDevices: true);
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object catch (error) {
      return error.toString();
    }
  }

  Future<String?> cancelAccountDeletion() async {
    final client = clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      return 'Sign in before cancelling account deletion.';
    }
    try {
      await client.rpc('cancel_account_deletion');
      return null;
    } on Object catch (error) {
      return error.toString();
    }
  }

  Future<Map<String, dynamic>> backendDiagnostics() async {
    final client = clientOrNull;
    if (client == null || !isOwner) {
      return const {'status': 'unavailable'};
    }
    try {
      final result = await client.rpc('owner_backend_diagnostics');
      if (result is Map<String, dynamic>) {
        return result;
      }
      return {'status': 'ok', 'result': result};
    } on Object catch (error) {
      return {'status': 'error', 'message': error.toString()};
    }
  }

  void markPasswordRecoveryPending() {
    if (_passwordRecoveryPending) {
      return;
    }
    _passwordRecoveryPending = true;
    notifyListeners();
  }

  static bool _isAuthUri(Uri uri) {
    return uri.scheme == 'taskmasterpro' &&
        uri.host == 'auth' &&
        uri.path == '/callback';
  }

  Future<void> _applyRememberSessionPreference(bool remember) async {
    _rememberSession = remember;
    if (!remember) {
      await _removePersistedSession();
      return;
    }
    await _persistCurrentSessionIfAllowed();
  }

  Future<void> _restorePersistedSession(bool remember) async {
    _rememberSession = remember;
    if (!remember) {
      await _removePersistedSession();
      return;
    }
    final client = clientOrNull;
    if (client == null || client.auth.currentSession != null) {
      return;
    }
    try {
      final file = _authSessionFile();
      if (!await file.exists()) {
        return;
      }
      final sessionString = await file.readAsString();
      if (sessionString.trim().isEmpty) {
        return;
      }
      await client.auth.recoverSession(sessionString);
      await _persistCurrentSessionIfAllowed();
    } on Object catch (error) {
      await _removePersistedSession();
      if (kDebugMode) {
        debugPrint('REMEMBERED SESSION RESTORE FAILED: $error');
      }
    }
  }

  Future<void> _persistCurrentSessionIfAllowed() async {
    if (!_rememberSession) {
      await _removePersistedSession();
      return;
    }
    final session = clientOrNull?.auth.currentSession;
    if (session == null) {
      return;
    }
    try {
      final file = _authSessionFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(session.toJson()));
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('REMEMBERED SESSION SAVE FAILED: $error');
      }
    }
  }

  Future<void> _removePersistedSession() async {
    try {
      final file = _authSessionFile();
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // A failed cleanup should not trap the user inside the app.
    }
  }

  File _authSessionFile() {
    final basePath = Platform.isWindows
        ? Platform.environment['APPDATA']
        : Platform.environment['HOME'];
    final base = basePath != null && basePath.trim().isNotEmpty
        ? Directory(basePath)
        : Directory.systemTemp;
    return File(
      '${base.path}${Platform.pathSeparator}TaskMasterPro'
      '${Platform.pathSeparator}auth_session.json',
    );
  }
}
