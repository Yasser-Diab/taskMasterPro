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
  late final String _settingsDeviceId;
  bool _loadingRemoteSettings = false;
  bool _applyingRemoteSettings = false;
  Timer? _settingsRefreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _config = widget.initialConfig;
    _settingsDeviceId =
        '${Platform.operatingSystem}:${Platform.localHostname}:settings';
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
          (_) => widget.timeZoneService.configure(
            _config,
            locale: _config.locale,
          ),
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
    _settingsUserId = user.id;
    final channel = client.channel('taskmaster-settings-${user.id}');
    _settingsChannel = channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sync_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record['entity_type']?.toString() != 'settings') return;
            if (record['device_id']?.toString() == _settingsDeviceId) return;
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
      final common = await client
          .from('common_settings')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      Map<String, dynamic>? platform;
      final platformTable = _platformSettingsTable();
      if (platformTable != null) {
        platform = await client
            .from(platformTable)
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
      }
      if (common == null && platform == null) return;
      final next = _configWithRemoteSettings(
        _config,
        common == null ? null : Map<String, dynamic>.from(common),
        platform,
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
      await client.from('common_settings').upsert({
        'user_id': user.id,
        'updated_by_device': _settingsDeviceId,
        ..._commonSettingsRow(config),
      }, onConflict: 'user_id');
      final platformTable = _platformSettingsTable();
      final platformRow = _platformSettingsRow(config);
      if (platformTable != null && platformRow.isNotEmpty) {
        await client.from(platformTable).upsert({
          'user_id': user.id,
          'updated_by_device': _settingsDeviceId,
          ...platformRow,
        }, onConflict: 'user_id');
      }
      await client.from('sync_events').insert({
        'user_id': user.id,
        'entity_type': 'settings',
        'entity_id': user.id,
        'event_type': 'settings_changed',
        'device_id': _settingsDeviceId,
        'payload': {'platform': Platform.operatingSystem},
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object {
      // Local settings stay authoritative until the next explicit save.
    }
  }

  Future<void> _syncTimeZoneSettings(AppConfig config) async {
    final client = widget.supabaseService.clientOrNull;
    final user = widget.supabaseService.currentUser;
    if (client == null || user == null) return;
    try {
      await client.from('user_time_zone_settings').upsert({
        'user_id': user.id,
        'mode': config.timeZoneMode,
        'home_time_zone_id': config.homeTimeZoneId,
        'current_time_zone_id': widget.timeZoneService.effectiveZoneId(config),
        'travel_behavior': config.travelTimeZoneBehavior,
        'ask_before_adjusting': config.askBeforeAdjustingTimeZone,
        'keep_home_while_travelling': config.keepHomeTimeZoneWhileTravelling,
        'last_detected_time_zone_id': widget.timeZoneService.deviceZoneId,
        'last_time_zone_change_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } on Object {
      // The device-local settings remain authoritative until sync retries.
    }
  }

  String? _platformSettingsTable() {
    if (Platform.isAndroid) return 'android_settings';
    if (Platform.isWindows) return 'windows_settings';
    return null;
  }

  Map<String, Object?> _commonSettingsRow(AppConfig config) {
    return {
      'language': config.locale.languageCode,
      'theme': config.themeChoice.storageValue,
      'coaching_intensity': config.coachingIntensity,
      'time_zone_mode': config.timeZoneMode,
      'fixed_time_zone_id': config.fixedTimeZoneId,
      'home_time_zone_id': config.homeTimeZoneId,
      'travel_time_zone_behavior': config.travelTimeZoneBehavior,
      'quiet_hours_start': config.quietHoursStart,
      'quiet_hours_end': config.quietHoursEnd,
      'browser_preferences': {
        'save_cookies_and_sessions': config.saveCookiesAndSessions,
        'sync_browser_tabs_and_urls': config.syncBrowserTabsAndUrls,
        'save_website_passwords': config.saveWebsitePasswords,
        'password_autofill': config.passwordAutofill,
        'form_autofill': config.formAutofill,
      },
      'search_engine': config.defaultSearchEngine,
      'custom_search_url': config.customSearchUrl,
      'activity_tracking_preferences': {
        'track_browser_activity': config.trackBrowserActivity,
        'track_full_urls': config.trackFullUrls,
        'track_page_titles': config.trackPageTitles,
        'track_search_queries': config.trackSearchQueries,
        'track_external_applications': config.trackExternalApplications,
        'pause_tracking_in_private_mode': config.pauseTrackingInPrivateMode,
        'excluded_domains': config.excludedActivityDomains,
        'excluded_applications': config.excludedActivityApplications,
      },
      'health_sync_preferences': {
        'keep_data_local': config.healthDataLocalOnly,
      },
      'password_manager_preferences': {
        'save_website_passwords': config.saveWebsitePasswords,
        'password_autofill': config.passwordAutofill,
      },
      'privacy_options': {
        'remember_session': config.rememberSession,
        'reduced_motion': config.reducedMotion,
        'high_contrast': config.highContrast,
        'ui_click_sounds': config.uiClickSounds,
        'ui_click_volume': config.uiClickVolume,
        'notification_sounds': config.notificationSounds,
        'pomodoro_sounds': config.pomodoroSounds,
        'completion_sounds': config.completionSounds,
        'error_sounds': config.errorSounds,
        'haptic_feedback': config.hapticFeedback,
        'ask_break_activity_review': config.askBreakActivityReview,
        'auto_credit_trusted_break_activity':
            config.autoCreditTrustedBreakActivity,
        'wake_up_time': config.wakeUpTime,
        'bedtime': config.bedtime,
        'work_start_time': config.workStartTime,
        'work_end_time': config.workEndTime,
        'workdays': config.workdays,
        'lunch_duration_minutes': config.lunchDurationMinutes,
        'commute_to_work_minutes': config.commuteToWorkMinutes,
        'commute_home_minutes': config.commuteHomeMinutes,
        'max_daily_study_minutes': config.maxDailyStudyMinutes,
        'max_weekly_study_minutes': config.maxWeeklyStudyMinutes,
        'weekly_review_time': config.weeklyReviewTime,
        'ask_before_adjusting_time_zone': config.askBeforeAdjustingTimeZone,
        'keep_home_time_zone_while_travelling':
            config.keepHomeTimeZoneWhileTravelling,
      },
    };
  }

  Map<String, Object?> _platformSettingsRow(AppConfig config) {
    if (Platform.isAndroid) {
      return {
        'foreground_timer_service': config.androidForegroundTimerService,
        'exact_alarm_guidance': config.androidExactAlarmGuidance,
        'battery_optimization_guidance':
            config.androidBatteryOptimizationGuidance,
        'background_health_access': false,
      };
    }
    if (Platform.isWindows) {
      return {
        'start_with_windows': config.startWithWindows,
        'start_minimized': config.startMinimized,
        'minimize_to_tray': config.minimizeToTray,
        'continue_timers_after_close': config.continueTimersAfterClose,
        'resume_after_windows_sign_in': config.resumeAfterWindowsSignIn,
        'allow_wake_timers': config.allowWakeTimers,
        'run_reminder_service_in_background':
            config.runReminderServiceInBackground,
      };
    }
    return const {};
  }

  AppConfig _configWithRemoteSettings(
    AppConfig base,
    Map<String, dynamic>? common,
    Map<String, dynamic>? platform,
  ) {
    final browser = _jsonMap(common?['browser_preferences']);
    final activity = _jsonMap(common?['activity_tracking_preferences']);
    final health = _jsonMap(common?['health_sync_preferences']);
    final privacy = _jsonMap(common?['privacy_options']);
    final language = common?['language']?.toString();
    return base.copyWith(
      locale: language == null ? null : Locale(_normalizeLanguage(language)),
      themeChoice: common?['theme'] == null
          ? null
          : AppThemeChoiceLabel.fromStorage(common?['theme']?.toString()),
      coachingIntensity:
          common?['coaching_intensity']?.toString() ?? base.coachingIntensity,
      timeZoneMode: common?['time_zone_mode']?.toString(),
      fixedTimeZoneId: common?['fixed_time_zone_id']?.toString(),
      homeTimeZoneId: common?['home_time_zone_id']?.toString(),
      travelTimeZoneBehavior: common?['travel_time_zone_behavior']?.toString(),
      quietHoursStart: common?['quiet_hours_start']?.toString(),
      quietHoursEnd: common?['quiet_hours_end']?.toString(),
      saveCookiesAndSessions: _boolSetting(
        browser['save_cookies_and_sessions'],
        base.saveCookiesAndSessions,
      ),
      syncBrowserTabsAndUrls: _boolSetting(
        browser['sync_browser_tabs_and_urls'],
        base.syncBrowserTabsAndUrls,
      ),
      saveWebsitePasswords: _boolSetting(
        browser['save_website_passwords'],
        base.saveWebsitePasswords,
      ),
      passwordAutofill: _boolSetting(
        browser['password_autofill'],
        base.passwordAutofill,
      ),
      formAutofill: _boolSetting(browser['form_autofill'], base.formAutofill),
      defaultSearchEngine:
          common?['search_engine']?.toString() ?? base.defaultSearchEngine,
      customSearchUrl:
          common?['custom_search_url']?.toString() ?? base.customSearchUrl,
      trackBrowserActivity: _boolSetting(
        activity['track_browser_activity'],
        base.trackBrowserActivity,
      ),
      trackFullUrls: _boolSetting(
        activity['track_full_urls'],
        base.trackFullUrls,
      ),
      trackPageTitles: _boolSetting(
        activity['track_page_titles'],
        base.trackPageTitles,
      ),
      trackSearchQueries: _boolSetting(
        activity['track_search_queries'],
        base.trackSearchQueries,
      ),
      trackExternalApplications: _boolSetting(
        activity['track_external_applications'],
        base.trackExternalApplications,
      ),
      pauseTrackingInPrivateMode: _boolSetting(
        activity['pause_tracking_in_private_mode'],
        base.pauseTrackingInPrivateMode,
      ),
      excludedActivityDomains: _stringListSetting(
        activity['excluded_domains'],
        base.excludedActivityDomains,
      ),
      excludedActivityApplications: _stringListSetting(
        activity['excluded_applications'],
        base.excludedActivityApplications,
      ),
      healthDataLocalOnly: _boolSetting(
        health['keep_data_local'],
        base.healthDataLocalOnly,
      ),
      rememberSession: _boolSetting(
        privacy['remember_session'],
        base.rememberSession,
      ),
      reducedMotion: _boolSetting(
        privacy['reduced_motion'],
        base.reducedMotion,
      ),
      highContrast: _boolSetting(privacy['high_contrast'], base.highContrast),
      uiClickSounds: _boolSetting(
        privacy['ui_click_sounds'],
        base.uiClickSounds,
      ),
      uiClickVolume: _doubleSetting(
        privacy['ui_click_volume'],
        base.uiClickVolume,
      ),
      notificationSounds: _boolSetting(
        privacy['notification_sounds'],
        base.notificationSounds,
      ),
      pomodoroSounds: _boolSetting(
        privacy['pomodoro_sounds'],
        base.pomodoroSounds,
      ),
      completionSounds: _boolSetting(
        privacy['completion_sounds'],
        base.completionSounds,
      ),
      errorSounds: _boolSetting(privacy['error_sounds'], base.errorSounds),
      hapticFeedback: _boolSetting(
        privacy['haptic_feedback'],
        base.hapticFeedback,
      ),
      askBreakActivityReview: _boolSetting(
        privacy['ask_break_activity_review'],
        base.askBreakActivityReview,
      ),
      autoCreditTrustedBreakActivity: _boolSetting(
        privacy['auto_credit_trusted_break_activity'],
        base.autoCreditTrustedBreakActivity,
      ),
      wakeUpTime: privacy['wake_up_time']?.toString() ?? base.wakeUpTime,
      bedtime: privacy['bedtime']?.toString() ?? base.bedtime,
      workStartTime:
          privacy['work_start_time']?.toString() ?? base.workStartTime,
      workEndTime: privacy['work_end_time']?.toString() ?? base.workEndTime,
      workdays: _intListSetting(privacy['workdays'], base.workdays),
      lunchDurationMinutes: _intSetting(
        privacy['lunch_duration_minutes'],
        base.lunchDurationMinutes,
      ),
      commuteToWorkMinutes: _intSetting(
        privacy['commute_to_work_minutes'],
        base.commuteToWorkMinutes,
      ),
      commuteHomeMinutes: _intSetting(
        privacy['commute_home_minutes'],
        base.commuteHomeMinutes,
      ),
      maxDailyStudyMinutes: _intSetting(
        privacy['max_daily_study_minutes'],
        base.maxDailyStudyMinutes,
      ),
      maxWeeklyStudyMinutes: _intSetting(
        privacy['max_weekly_study_minutes'],
        base.maxWeeklyStudyMinutes,
      ),
      weeklyReviewTime:
          privacy['weekly_review_time']?.toString() ?? base.weeklyReviewTime,
      askBeforeAdjustingTimeZone: _boolSetting(
        privacy['ask_before_adjusting_time_zone'],
        base.askBeforeAdjustingTimeZone,
      ),
      keepHomeTimeZoneWhileTravelling: _boolSetting(
        privacy['keep_home_time_zone_while_travelling'],
        base.keepHomeTimeZoneWhileTravelling,
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
        platform?['minimize_to_tray'],
        base.minimizeToTray,
      ),
      continueTimersAfterClose: _boolSetting(
        platform?['continue_timers_after_close'],
        base.continueTimersAfterClose,
      ),
      resumeAfterWindowsSignIn: _boolSetting(
        platform?['resume_after_windows_sign_in'],
        base.resumeAfterWindowsSignIn,
      ),
      allowWakeTimers: _boolSetting(
        platform?['allow_wake_timers'],
        base.allowWakeTimers,
      ),
      runReminderServiceInBackground: _boolSetting(
        platform?['run_reminder_service_in_background'],
        base.runReminderServiceInBackground,
      ),
      androidForegroundTimerService: _boolSetting(
        platform?['foreground_timer_service'],
        base.androidForegroundTimerService,
      ),
      androidExactAlarmGuidance: _boolSetting(
        platform?['exact_alarm_guidance'],
        base.androidExactAlarmGuidance,
      ),
      androidBatteryOptimizationGuidance: _boolSetting(
        platform?['battery_optimization_guidance'],
        base.androidBatteryOptimizationGuidance,
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

  int _intSetting(Object? value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _doubleSetting(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<String> _stringListSetting(Object? value, List<String> fallback) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    }
    return fallback;
  }

  List<int> _intListSetting(Object? value, List<int> fallback) {
    if (value is List) {
      final items = value
          .map((item) => item is num ? item.toInt() : int.tryParse('$item'))
          .whereType<int>()
          .toList(growable: false);
      return items.isEmpty ? fallback : items;
    }
    return fallback;
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
