import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase/supabase.dart';

import '../core/config/app_config.dart';
import '../core/config/app_settings_store.dart';
import '../core/config/supabase_service.dart';
import '../core/localization/app_localizations.dart';
import '../core/platform/app_lifecycle_service.dart';
import '../core/platform/app_notification_service.dart';
import '../core/platform/interaction_feedback_service.dart';
import '../core/platform/health_data_service.dart';
import '../core/theme/app_brand.dart';
import '../core/time/time_zone_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_notifications.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/tasks/data/task_local_store.dart';
import 'app_services.dart';

class TaskMasterApp extends StatefulWidget {
  const TaskMasterApp({
    required this.initialConfig,
    required this.feedbackService,
    required this.initialLinks,
    required this.lifecycleService,
    required this.notificationService,
    required this.settingsStore,
    required this.supabaseService,
    required this.timeZoneService,
    required this.healthDataService,
    super.key,
  });

  final AppConfig initialConfig;
  final InteractionFeedbackService feedbackService;
  final List<String> initialLinks;
  final AppLifecycleService lifecycleService;
  final AppNotificationService notificationService;
  final AppSettingsStore settingsStore;
  final SupabaseService supabaseService;
  final TimeZoneService timeZoneService;
  final HealthDataService healthDataService;

  @override
  State<TaskMasterApp> createState() => _TaskMasterAppState();
}

class _TaskMasterAppState extends State<TaskMasterApp>
    with WidgetsBindingObserver {
  late AppConfig _config;
  RealtimeChannel? _settingsChannel;
  String? _settingsUserId;
  String? _settingsDeviceId;
  final TaskLocalStore _settingsLocalStore = TaskLocalStore();
  bool _loadingRemoteSettings = false;
  bool _applyingRemoteSettings = false;
  Timer? _settingsRefreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _config = widget.initialConfig;
    widget.timeZoneService.configure(_config, locale: _config.locale);
    widget.supabaseService.addListener(_handleSupabaseStateChanged);
    unawaited(_handleSupabaseStateChanged());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.supabaseService.removeListener(_handleSupabaseStateChanged);
    _settingsRefreshDebounce?.cancel();
    unawaited(_removeSettingsSubscription());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        widget.timeZoneService.refreshDeviceZone().then(
          (_) =>
              widget.timeZoneService.configure(_config, locale: _config.locale),
        ),
      );
    }
  }

  Future<String?> _updateConfig(AppConfig config) async {
    final timeZoneChanged =
        config.timeZoneMode != _config.timeZoneMode ||
        config.fixedTimeZoneId != _config.fixedTimeZoneId ||
        config.homeTimeZoneId != _config.homeTimeZoneId ||
        config.travelTimeZoneBehavior != _config.travelTimeZoneBehavior ||
        config.askBeforeAdjustingTimeZone !=
            _config.askBeforeAdjustingTimeZone ||
        config.keepHomeTimeZoneWhileTravelling !=
            _config.keepHomeTimeZoneWhileTravelling;
    await widget.settingsStore.save(config);
    await widget.feedbackService.updateConfig(config);
    await widget.lifecycleService.applyWindowPreferences(config);
    widget.healthDataService.keepDataLocal = config.healthDataLocalOnly;
    widget.timeZoneService.configure(config, locale: config.locale);
    if (mounted) {
      setState(() => _config = config);
    }
    if (!_applyingRemoteSettings) {
      unawaited(_syncRemoteSettings(config));
    }
    if (timeZoneChanged) unawaited(_syncTimeZoneSettings(config));
    return null;
  }

  Future<void> _handleSupabaseStateChanged() async {
    final user = widget.supabaseService.currentUser;
    final client = widget.supabaseService.clientOrNull;
    if (client == null || user == null) {
      await _removeSettingsSubscription();
      return;
    }
    unawaited(_ensureSettingsSubscription());
    unawaited(_loadRemoteSettings());
  }

  Future<void> _ensureSettingsSubscription() async {
    final client = widget.supabaseService.clientOrNull;
    final user = widget.supabaseService.currentUser;
    if (client == null || user == null) return;
    if (_settingsChannel != null && _settingsUserId == user.id) return;
    await _removeSettingsSubscription();
    final deviceId = await _ensureRemoteDeviceRow(client: client, user: user);
    if (deviceId == null) return;
    _settingsUserId = user.id;
    final channel = client.channel(
      'taskmaster:user:${user.id}:runtime',
      opts: const RealtimeChannelConfig(private: true),
    );
    _settingsChannel = channel
        .onBroadcast(
          event: 'settings_changed',
          callback: (payload) {
            final body = _jsonMap(payload['payload']);
            final sourceDeviceId =
                body['device_id']?.toString() ??
                payload['device_id']?.toString();
            if (sourceDeviceId == deviceId) return;
            _settingsRefreshDebounce?.cancel();
            _settingsRefreshDebounce = Timer(
              const Duration(milliseconds: 350),
              () => unawaited(_loadRemoteSettings(force: true)),
            );
          },
        )
        .subscribe();
  }

  Future<void> _removeSettingsSubscription() async {
    final channel = _settingsChannel;
    _settingsChannel = null;
    _settingsUserId = null;
    if (channel == null) return;
    try {
      await widget.supabaseService.clientOrNull?.removeChannel(channel);
    } on Object {
      // A stale channel is harmless; a fresh one is created after reconnect.
    }
  }

  Future<void> _loadRemoteSettings({bool force = false}) async {
    if (_loadingRemoteSettings) return;
    final client = widget.supabaseService.clientOrNull;
    final user = widget.supabaseService.currentUser;
    if (client == null || user == null) return;
    _loadingRemoteSettings = true;
    try {
      final deviceId = await _ensureRemoteDeviceRow(client: client, user: user);
      if (deviceId == null) return;
      final results = await Future.wait<Object?>([
        client
            .from('user_settings')
            .select()
            .eq('user_id', user.id)
            .maybeSingle(),
        client
            .from('device_settings')
            .select()
            .eq('user_id', user.id)
            .eq('device_id', deviceId)
            .maybeSingle(),
      ]);
      final userSettings = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : null;
      final deviceSettings = results[1] is Map
          ? Map<String, dynamic>.from(results[1] as Map)
          : null;
      if (userSettings == null && deviceSettings == null) return;
      final next = _configWithRemoteSettings(
        _config,
        userSettings,
        deviceSettings,
      );
      if (_settingsSignature(next) == _settingsSignature(_config)) return;
      _applyingRemoteSettings = true;
      await widget.settingsStore.save(next);
      await widget.feedbackService.updateConfig(next);
      await widget.lifecycleService.applyWindowPreferences(next);
      widget.healthDataService.keepDataLocal = next.healthDataLocalOnly;
      if (mounted) {
        setState(() => _config = next);
      }
    } on Object {
      // Keep the current local settings visible and retry through realtime or
      // the next app resume.
    } finally {
      _applyingRemoteSettings = false;
      _loadingRemoteSettings = false;
    }
  }

  Future<void> _syncRemoteSettings(AppConfig config) async {
    final client = widget.supabaseService.clientOrNull;
    final user = widget.supabaseService.currentUser;
    if (client == null || user == null) return;
    try {
      final deviceId = await _ensureRemoteDeviceRow(client: client, user: user);
      if (deviceId == null) return;
      await client.from('user_settings').upsert({
        'user_id': user.id,
        ..._commonSettingsRow(config),
      }, onConflict: 'user_id');
      final platformRow = _platformSettingsRow(config);
      if (platformRow.isNotEmpty) {
        await client.from('device_settings').upsert({
          'user_id': user.id,
          'device_id': deviceId,
          ...platformRow,
        }, onConflict: 'user_id,device_id');
      }
      await _broadcastSettingsChanged(deviceId);
    } on Object {
      // Local settings stay authoritative until the next explicit save.
    }
  }

  Future<void> _syncTimeZoneSettings(AppConfig config) async {
    final client = widget.supabaseService.clientOrNull;
    final user = widget.supabaseService.currentUser;
    if (client == null || user == null) return;
    try {
      final row = {
        'time_zone_mode': config.timeZoneMode == 'fixed' ? 'fixed' : 'device',
        'fixed_time_zone_id': config.fixedTimeZoneId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await client.from('profiles').update(row).eq('id', user.id);
      await client.from('user_settings').upsert({
        'user_id': user.id,
        ...row,
      }, onConflict: 'user_id');
    } on Object {
      // The device-local settings remain authoritative until sync retries.
    }
  }

  Future<String?> _ensureRemoteDeviceRow({
    required SupabaseClient client,
    required User user,
  }) async {
    try {
      final deviceId =
          _settingsDeviceId ?? await _settingsLocalStore.loadDeviceId();
      _settingsDeviceId = deviceId;
      await client.from('devices').upsert({
        'id': deviceId,
        'user_id': user.id,
        'device_name': Platform.localHostname,
        'platform': _settingsPlatform,
        'platform_version': Platform.operatingSystemVersion,
        'app_version': '',
        'build_number': '',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'notification_enabled': _config.notificationSounds,
      }, onConflict: 'id');
      return deviceId;
    } on Object {
      return null;
    }
  }

  Future<void> _broadcastSettingsChanged(String deviceId) async {
    try {
      await _settingsChannel?.sendBroadcastMessage(
        event: 'settings_changed',
        payload: {'device_id': deviceId, 'platform': _settingsPlatform},
      );
    } on Object {
      // Settings are already saved remotely; realtime is an optimization.
    }
  }

  String get _settingsPlatform {
    if (Platform.isAndroid) return 'android';
    return 'windows';
  }

  Map<String, Object?> _commonSettingsRow(AppConfig config) {
    return {
      'language': config.locale.languageCode,
      'theme': config.themeChoice.storageValue,
      'coaching_intensity': config.coachingIntensity,
      'focus_duration_seconds': 1500,
      'short_break_duration_seconds': 300,
      'long_break_duration_seconds': 900,
      'long_break_after_focus_count': 4,
      'auto_start_break': false,
      'auto_start_focus': false,
      'ask_break_activity': config.askBreakActivityReview,
      'idle_threshold_seconds': 30,
      'default_search_engine': _cleanSearchEngine(config.defaultSearchEngine),
      'browser_sync_enabled': config.syncBrowserTabsAndUrls,
      'bookmark_sync_enabled': true,
      'health_sync_enabled': !config.healthDataLocalOnly,
      'cycle_sync_enabled':
          widget.supabaseService.profile?.cycleDataSyncEnabled ?? false,
      'time_zone_mode': config.timeZoneMode,
      'fixed_time_zone_id': config.fixedTimeZoneId,
      'clock_format': 'system',
      'quiet_hours_start_minutes': _clockToMinutes(config.quietHoursStart),
      'quiet_hours_end_minutes': _clockToMinutes(config.quietHoursEnd),
    };
  }

  Map<String, Object?> _platformSettingsRow(AppConfig config) {
    return {
      'start_with_windows': Platform.isWindows && config.startWithWindows,
      'start_minimized': Platform.isWindows && config.startMinimized,
      'keep_running_in_tray': config.minimizeToTray,
      'notify_on_device': config.notificationSounds,
      'health_background_reading':
          Platform.isAndroid && !config.healthDataLocalOnly,
      'widget_enabled':
          Platform.isAndroid && config.androidForegroundTimerService,
      'window_maximized': config.restoreWindowMaximized,
    };
  }

  AppConfig _configWithRemoteSettings(
    AppConfig base,
    Map<String, dynamic>? common,
    Map<String, dynamic>? platform,
  ) {
    final language = common?['language']?.toString();
    final quietStart = _minutesToClock(common?['quiet_hours_start_minutes']);
    final quietEnd = _minutesToClock(common?['quiet_hours_end_minutes']);
    return base.copyWith(
      locale: language == null ? null : Locale(_normalizeLanguage(language)),
      themeChoice: common?['theme'] == null
          ? null
          : AppThemeChoiceLabel.fromStorage(common?['theme']?.toString()),
      coachingIntensity:
          common?['coaching_intensity']?.toString() ?? base.coachingIntensity,
      timeZoneMode: common?['time_zone_mode']?.toString(),
      fixedTimeZoneId: common?['fixed_time_zone_id']?.toString(),
      quietHoursStart: quietStart,
      quietHoursEnd: quietEnd,
      syncBrowserTabsAndUrls: _boolSetting(
        common?['browser_sync_enabled'],
        base.syncBrowserTabsAndUrls,
      ),
      defaultSearchEngine:
          common?['default_search_engine']?.toString() ??
          base.defaultSearchEngine,
      healthDataLocalOnly: common?['health_sync_enabled'] is bool
          ? !(common!['health_sync_enabled'] as bool)
          : base.healthDataLocalOnly,
      notificationSounds: _boolSetting(
        platform?['notify_on_device'],
        base.notificationSounds,
      ),
      askBreakActivityReview: _boolSetting(
        common?['ask_break_activity'],
        base.askBreakActivityReview,
      ),
      startWithWindows: _boolSetting(
        platform?['start_with_windows'],
        base.startWithWindows,
      ),
      startMinimized: _boolSetting(
        platform?['start_minimized'],
        base.startMinimized,
      ),
      minimizeToTray: _boolSetting(
        platform?['keep_running_in_tray'],
        base.minimizeToTray,
      ),
      androidForegroundTimerService: _boolSetting(
        platform?['widget_enabled'],
        base.androidForegroundTimerService,
      ),
    );
  }

  String _settingsSignature(AppConfig config) =>
      _commonSettingsRow(config).toString() +
      _platformSettingsRow(config).toString();

  String _normalizeLanguage(String value) {
    return switch (value) {
      'ar' => 'ar',
      'de' => 'de',
      _ => 'en',
    };
  }

  Map<String, dynamic> _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  bool _boolSetting(Object? value, bool fallback) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true' ? true : fallback;
  }

  String _cleanSearchEngine(String value) {
    return switch (value) {
      'bing' => 'bing',
      'duckduckgo' => 'duckduckgo',
      'brave' => 'brave',
      _ => 'google',
    };
  }

  int? _clockToMinutes(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
    return hours * 60 + minutes;
  }

  String? _minutesToClock(Object? value) {
    final total = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (total == null || total < 0 || total > 1439) return null;
    final hours = total ~/ 60;
    final minutes = total % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = switch (_config.themeChoice) {
      AppThemeChoice.blackGold => AppTheme.blackGold(
        highContrast: _config.highContrast,
      ),
      _ => AppTheme.darkBlue(highContrast: _config.highContrast),
    };

    final lightTheme = AppTheme.light(highContrast: _config.highContrast);
    final effectiveMode = switch (_config.themeChoice) {
      AppThemeChoice.light => ThemeMode.light,
      AppThemeChoice.darkBlue || AppThemeChoice.blackGold => ThemeMode.dark,
    };

    return AppServices(
      config: _config,
      feedbackService: widget.feedbackService,
      lifecycleService: widget.lifecycleService,
      notificationService: widget.notificationService,
      updateConfig: _updateConfig,
      supabaseService: widget.supabaseService,
      timeZoneService: widget.timeZoneService,
      healthDataService: widget.healthDataService,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: AppBrand.name,
        locale: _config.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: effectiveMode,
        scrollBehavior: const _TaskMasterScrollBehavior(),
        builder: (context, child) {
          return AppNotificationHost(
            service: widget.notificationService,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: _LifecycleLocalizationBridge(
          lifecycleService: widget.lifecycleService,
          child: AuthGate(
            supabaseService: widget.supabaseService,
            initialLinks: widget.initialLinks,
          ),
        ),
      ),
    );
  }
}

class _TaskMasterScrollBehavior extends MaterialScrollBehavior {
  const _TaskMasterScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

class _LifecycleLocalizationBridge extends StatefulWidget {
  const _LifecycleLocalizationBridge({
    required this.lifecycleService,
    required this.child,
  });

  final AppLifecycleService lifecycleService;
  final Widget child;

  @override
  State<_LifecycleLocalizationBridge> createState() =>
      _LifecycleLocalizationBridgeState();
}

class _LifecycleLocalizationBridgeState
    extends State<_LifecycleLocalizationBridge> {
  Locale? _lastLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_lastLocale == locale) {
      return;
    }
    _lastLocale = locale;
    widget.lifecycleService.updateMenuLabels(
      AppTrayMenuLabels(
        tasks: context.text('trayTasks'),
        pomodoro: context.text('trayPomodoro'),
        workSession: context.text('trayWorkSession'),
        learningSession: context.text('trayLearningSession'),
        notifications: context.text('trayNotifications'),
        synchronization: context.text('traySynchronization'),
        settings: context.text('traySettings'),
        exit: context.text('trayExit'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
