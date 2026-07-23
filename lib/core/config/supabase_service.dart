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
      return (url: response.url, error: null);
    } on AuthException catch (error) {
      return (url: null, error: error.message);
    } on Object catch (_) {
      return (
        url: null,
        error:
            'Could not open Google sign-in. Check your connection and try again.',
      );
    }
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
      final profileRow = await client
          .from('profiles')
          .select(
            'id,email,display_name,username,locale,onboarding_completed,avatar_path,pending_email,sex,cycle_tracking_enabled,cycle_data_sync_enabled',
          )
          .eq('id', user.id)
          .maybeSingle();
      final roleRow = await client
          .from('user_roles')
          .select('role')
          .eq('user_id', user.id)
          .maybeSingle();

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
        email: profileRow?['email']?.toString() ?? user.email ?? '',
        displayName: profileRow?['display_name']?.toString() ?? '',
        username: profileRow?['username']?.toString(),
        locale: profileRow?['locale']?.toString() ?? 'en',
        role: AppRoleX.fromStorage(roleRow?['role']?.toString()),
        onboardingCompleted:
            profileRow?['onboarding_completed'] as bool? ?? false,
        sex: UserSexX.fromStorage(profileRow?['sex']?.toString()),
        cycleTrackingEnabled:
            profileRow?['cycle_tracking_enabled'] as bool? ?? false,
        cycleDataSyncEnabled:
            profileRow?['cycle_data_sync_enabled'] as bool? ?? false,
        pendingEmail: profileRow?['pending_email']?.toString(),
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
      if (installOwnerTemplates) {
        await installOwnerTemplateIfNeeded();
      }
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
      // Older databases may not have the login bootstrap yet. The app keeps
      // running, and owner diagnostics will report the missing function.
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
      if (remoteState['role'] == 'owner') {
        unawaited(_repairOwnerTemplateInBackground());
      }
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
      final rawState = await _withTimeout(
        client.rpc('get_my_startup_state'),
        _startupOperationTimeout,
        'We could not load your account status in time.',
      );
      return rawState is Map<String, dynamic>
          ? rawState
          : rawState is Map
          ? Map<String, dynamic>.from(rawState)
          : <String, dynamic>{};
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('STARTUP STATE RPC FAILED: $error');
      }

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
              .from('user_roles')
              .select('role')
              .eq('user_id', user.id)
              .maybeSingle(),
          _startupOperationTimeout,
          'We could not load your account role in time.',
        ),
      ]);

      final profileRow = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : null;
      final roleRow = results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
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
        'role': roleRow?['role']?.toString() ?? 'user',
        'onboarding_completed': profileRow['onboarding_completed'] == true,
        'roadmap_count': null,
        'roadmap_phase_count': null,
        'roadmap_item_count': null,
        'task_count': null,
        'recurring_template_count': null,
        'startup_state_source': 'profile_fallback',
        'startup_state_error': error.toString(),
      };
    }
  }

  Future<void> _repairOwnerTemplateInBackground() async {
    try {
      await installOwnerTemplateIfNeeded();
    } on Object {
      // Startup must stay responsive; diagnostics can surface template repair
      // failures later.
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
      client.from('user_roles').select().eq('user_id', userId).single(),
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
          .order('phase_number'),
      client
          .from('roadmap_items')
          .select()
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('planned_start', nullsFirst: false),
      client
          .from('tasks')
          .select()
          .eq('user_id', userId)
          .eq('is_recurring_template', false)
          .isFilter('deleted_at', null)
          .order('scheduled_start_at', nullsFirst: false)
          .limit(1000),
    ]);

    final roadmaps = results[2] is List ? results[2] as List : const [];
    final phases = results[3] is List ? results[3] as List : const [];
    final items = results[4] is List ? results[4] as List : const [];
    final tasks = results[5] is List ? results[5] as List : const [];
    _lastFullRemoteRefreshAt = DateTime.now();
    final snapshot = <String, dynamic>{
      'profile_loaded': results[0] != null,
      'role_loaded': results[1] != null,
      'remote_roadmap_count': roadmaps.length,
      'remote_roadmap_phase_count': phases.length,
      'remote_roadmap_item_count': items.length,
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
      if (cycleTrackingEnabled != null) {
        updates['cycle_tracking_enabled'] = cycleTrackingEnabled;
      }
      if (cycleDataSyncEnabled != null) {
        updates['cycle_data_sync_enabled'] = cycleDataSyncEnabled;
      }
      await client.from('profiles').update(updates).eq('id', user.id);
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
      await client
          .from('profiles')
          .update({
            'pending_email': cleanEmail,
            'email_change_requested_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
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
    final client = clientOrNull;
    if (client == null) {
      return;
    }
    try {
      await client.rpc('install_owner_template_if_needed');
      await client.rpc('install_owner_daily_schedule_if_needed');
    } on Object {
      // Backend diagnostics will surface this. Sign-in must not fail just
      // because private template installation is temporarily unavailable.
    }
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
