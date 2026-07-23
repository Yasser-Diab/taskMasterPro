import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_config.dart';

class AppSettingsStore {
  AppSettingsStore({File? settingsFile}) : _settingsFile = settingsFile;

  static const _localeCodeKey = 'settings.locale_code';
  static const _themeModeKey = 'settings.theme_mode';
  static const _themeChoiceKey = 'settings.theme_choice';
  static const _rememberSessionKey = 'settings.remember_session';
  static const _restoreWindowGeometryKey = 'window.restore_geometry';
  static const _restoreWindowMaximizedKey = 'window.restore_maximized';
  static const _compactDesktopKey = 'settings.compact_desktop';
  static const _reducedMotionKey = 'settings.reduced_motion';
  static const _highContrastKey = 'settings.high_contrast';
  static const _uiClickSoundsKey = 'settings.ui_click_sounds';
  static const _uiClickVolumeKey = 'settings.ui_click_volume';
  static const _notificationSoundsKey = 'settings.notification_sounds';
  static const _pomodoroSoundsKey = 'settings.pomodoro_sounds';
  static const _completionSoundsKey = 'settings.completion_sounds';
  static const _errorSoundsKey = 'settings.error_sounds';
  static const _hapticFeedbackKey = 'settings.haptic_feedback';
  static const _saveWebsitePasswordsKey = 'browser.save_website_passwords';
  static const _passwordAutofillKey = 'browser.password_autofill';
  static const _formAutofillKey = 'browser.form_autofill';
  static const _saveCookiesAndSessionsKey = 'browser.save_cookies_and_sessions';
  static const _syncBrowserTabsAndUrlsKey =
      'browser.sync_task_browser_tabs_and_urls';
  static const _trackBrowserActivityKey = 'activity.track_browser';
  static const _trackFullUrlsKey = 'activity.track_full_urls';
  static const _trackPageTitlesKey = 'activity.track_page_titles';
  static const _trackSearchQueriesKey = 'activity.track_search_queries';
  static const _trackExternalApplicationsKey =
      'activity.track_external_applications';
  static const _pauseTrackingInPrivateModeKey =
      'activity.pause_in_private_mode';
  static const _defaultSearchEngineKey = 'browser.default_search_engine';
  static const _customSearchUrlKey = 'browser.custom_search_url';
  static const _excludedActivityDomainsKey = 'activity.excluded_domains';
  static const _excludedActivityApplicationsKey =
      'activity.excluded_applications';
  static const _wakeUpTimeKey = 'schedule.wake_up_time';
  static const _bedtimeKey = 'schedule.bedtime';
  static const _workStartTimeKey = 'schedule.work_start_time';
  static const _workEndTimeKey = 'schedule.work_end_time';
  static const _workdaysKey = 'schedule.workdays';
  static const _lunchDurationKey = 'schedule.lunch_duration_minutes';
  static const _commuteToWorkKey = 'schedule.commute_to_work_minutes';
  static const _commuteHomeKey = 'schedule.commute_home_minutes';
  static const _maxDailyStudyKey = 'schedule.max_daily_study_minutes';
  static const _maxWeeklyStudyKey = 'schedule.max_weekly_study_minutes';
  static const _weeklyReviewTimeKey = 'schedule.weekly_review_time';
  static const _quietHoursStartKey = 'schedule.quiet_hours_start';
  static const _quietHoursEndKey = 'schedule.quiet_hours_end';
  static const _timeZoneModeKey = 'timezone.mode';
  static const _fixedTimeZoneIdKey = 'timezone.fixed_zone_id';
  static const _homeTimeZoneIdKey = 'timezone.home_zone_id';
  static const _travelTimeZoneBehaviorKey = 'timezone.travel_behavior';
  static const _askBeforeAdjustingTimeZoneKey = 'timezone.ask_before_adjusting';
  static const _keepHomeTimeZoneWhileTravellingKey =
      'timezone.keep_home_while_travelling';
  static const _healthDataLocalOnlyKey = 'health.keep_data_local';
  static const _coachingIntensityKey = 'coaching.intensity';
  static const _askBreakActivityReviewKey = 'break.ask_for_activity_review';
  static const _autoCreditTrustedBreakActivityKey =
      'break.auto_credit_trusted_activity';
  static const _startWithWindowsKey = 'windows.start_with_windows';
  static const _startMinimizedKey = 'windows.start_minimized';
  static const _minimizeToTrayKey = 'windows.minimize_to_tray';
  static const _continueTimersAfterCloseKey =
      'windows.continue_timers_after_close';
  static const _resumeAfterWindowsSignInKey = 'windows.resume_after_sign_in';
  static const _allowWakeTimersKey = 'windows.allow_wake_timers';
  static const _runReminderServiceInBackgroundKey =
      'windows.run_reminder_service_background';
  static const _androidForegroundTimerServiceKey =
      'android.foreground_timer_service';
  static const _androidExactAlarmGuidanceKey = 'android.exact_alarm_guidance';
  static const _androidBatteryOptimizationGuidanceKey =
      'android.battery_optimization_guidance';

  final File? _settingsFile;

  Future<AppConfig> load() async {
    final defaults = AppConfig.defaults();
    final values = await _readSettings();

    final localeCode = values[_localeCodeKey]?.toString();
    final themeMode = values[_themeModeKey]?.toString();
    final themeChoice = values[_themeChoiceKey]?.toString();
    final rememberSession = values[_rememberSessionKey] as bool?;
    final restoreWindowGeometry = values[_restoreWindowGeometryKey] as bool?;
    final restoreWindowMaximized = values[_restoreWindowMaximizedKey] as bool?;
    final compactDesktop = values[_compactDesktopKey] as bool?;
    final reducedMotion = values[_reducedMotionKey] as bool?;
    final highContrast = values[_highContrastKey] as bool?;
    final uiClickSounds = values[_uiClickSoundsKey] as bool?;
    final uiClickVolume = _doubleFromStorage(values[_uiClickVolumeKey]);
    final notificationSounds = values[_notificationSoundsKey] as bool?;
    final pomodoroSounds = values[_pomodoroSoundsKey] as bool?;
    final completionSounds = values[_completionSoundsKey] as bool?;
    final errorSounds = values[_errorSoundsKey] as bool?;
    final hapticFeedback = values[_hapticFeedbackKey] as bool?;
    final saveWebsitePasswords = values[_saveWebsitePasswordsKey] as bool?;
    final passwordAutofill = values[_passwordAutofillKey] as bool?;
    final formAutofill = values[_formAutofillKey] as bool?;
    final saveCookiesAndSessions = values[_saveCookiesAndSessionsKey] as bool?;
    final syncBrowserTabsAndUrls = values[_syncBrowserTabsAndUrlsKey] as bool?;
    final excludedDomains = _stringListFromStorage(
      values[_excludedActivityDomainsKey],
    );
    final excludedApplications = _stringListFromStorage(
      values[_excludedActivityApplicationsKey],
    );
    final workdays = _intListFromStorage(values[_workdaysKey]);

    return defaults.copyWith(
      locale: Locale(
        _normalizeLocale(localeCode ?? defaults.locale.languageCode),
      ),
      themeMode: _themeModeFromStorage(themeMode),
      themeChoice: AppThemeChoiceLabel.fromStorage(themeChoice),
      rememberSession: rememberSession ?? defaults.rememberSession,
      restoreWindowGeometry:
          restoreWindowGeometry ?? defaults.restoreWindowGeometry,
      restoreWindowMaximized:
          restoreWindowMaximized ?? defaults.restoreWindowMaximized,
      compactDesktop: compactDesktop ?? defaults.compactDesktop,
      reducedMotion: reducedMotion ?? defaults.reducedMotion,
      highContrast: highContrast ?? defaults.highContrast,
      uiClickSounds: uiClickSounds ?? defaults.uiClickSounds,
      uiClickVolume: uiClickVolume ?? defaults.uiClickVolume,
      notificationSounds: notificationSounds ?? defaults.notificationSounds,
      pomodoroSounds: pomodoroSounds ?? defaults.pomodoroSounds,
      completionSounds: completionSounds ?? defaults.completionSounds,
      errorSounds: errorSounds ?? defaults.errorSounds,
      hapticFeedback: hapticFeedback ?? defaults.hapticFeedback,
      saveWebsitePasswords:
          saveWebsitePasswords ?? defaults.saveWebsitePasswords,
      passwordAutofill: passwordAutofill ?? defaults.passwordAutofill,
      formAutofill: formAutofill ?? defaults.formAutofill,
      saveCookiesAndSessions:
          saveCookiesAndSessions ?? defaults.saveCookiesAndSessions,
      syncBrowserTabsAndUrls:
          syncBrowserTabsAndUrls ?? defaults.syncBrowserTabsAndUrls,
      trackBrowserActivity:
          values[_trackBrowserActivityKey] as bool? ??
          defaults.trackBrowserActivity,
      trackFullUrls:
          values[_trackFullUrlsKey] as bool? ?? defaults.trackFullUrls,
      trackPageTitles:
          values[_trackPageTitlesKey] as bool? ?? defaults.trackPageTitles,
      trackSearchQueries:
          values[_trackSearchQueriesKey] as bool? ??
          defaults.trackSearchQueries,
      trackExternalApplications:
          values[_trackExternalApplicationsKey] as bool? ??
          defaults.trackExternalApplications,
      pauseTrackingInPrivateMode:
          values[_pauseTrackingInPrivateModeKey] as bool? ??
          defaults.pauseTrackingInPrivateMode,
      defaultSearchEngine:
          values[_defaultSearchEngineKey]?.toString() ??
          defaults.defaultSearchEngine,
      customSearchUrl:
          values[_customSearchUrlKey]?.toString() ?? defaults.customSearchUrl,
      excludedActivityDomains: excludedDomains,
      excludedActivityApplications: excludedApplications,
      wakeUpTime: values[_wakeUpTimeKey]?.toString() ?? defaults.wakeUpTime,
      bedtime: values[_bedtimeKey]?.toString() ?? defaults.bedtime,
      workStartTime:
          values[_workStartTimeKey]?.toString() ?? defaults.workStartTime,
      workEndTime: values[_workEndTimeKey]?.toString() ?? defaults.workEndTime,
      workdays: workdays.isEmpty ? defaults.workdays : workdays,
      lunchDurationMinutes: _intFromStorage(
        values[_lunchDurationKey],
        defaults.lunchDurationMinutes,
      ),
      commuteToWorkMinutes: _intFromStorage(
        values[_commuteToWorkKey],
        defaults.commuteToWorkMinutes,
      ),
      commuteHomeMinutes: _intFromStorage(
        values[_commuteHomeKey],
        defaults.commuteHomeMinutes,
      ),
      maxDailyStudyMinutes: _intFromStorage(
        values[_maxDailyStudyKey],
        defaults.maxDailyStudyMinutes,
      ),
      maxWeeklyStudyMinutes: _intFromStorage(
        values[_maxWeeklyStudyKey],
        defaults.maxWeeklyStudyMinutes,
      ),
      weeklyReviewTime:
          values[_weeklyReviewTimeKey]?.toString() ?? defaults.weeklyReviewTime,
      quietHoursStart:
          values[_quietHoursStartKey]?.toString() ?? defaults.quietHoursStart,
      quietHoursEnd:
          values[_quietHoursEndKey]?.toString() ?? defaults.quietHoursEnd,
      timeZoneMode:
          values[_timeZoneModeKey]?.toString() ?? defaults.timeZoneMode,
      fixedTimeZoneId:
          values[_fixedTimeZoneIdKey]?.toString() ?? defaults.fixedTimeZoneId,
      homeTimeZoneId:
          values[_homeTimeZoneIdKey]?.toString() ?? defaults.homeTimeZoneId,
      travelTimeZoneBehavior:
          values[_travelTimeZoneBehaviorKey]?.toString() ??
          defaults.travelTimeZoneBehavior,
      askBeforeAdjustingTimeZone:
          values[_askBeforeAdjustingTimeZoneKey] as bool? ??
          defaults.askBeforeAdjustingTimeZone,
      keepHomeTimeZoneWhileTravelling:
          values[_keepHomeTimeZoneWhileTravellingKey] as bool? ??
          defaults.keepHomeTimeZoneWhileTravelling,
      healthDataLocalOnly:
          values[_healthDataLocalOnlyKey] as bool? ??
          defaults.healthDataLocalOnly,
      coachingIntensity:
          values[_coachingIntensityKey]?.toString() ??
          defaults.coachingIntensity,
      askBreakActivityReview:
          values[_askBreakActivityReviewKey] as bool? ??
          defaults.askBreakActivityReview,
      autoCreditTrustedBreakActivity:
          values[_autoCreditTrustedBreakActivityKey] as bool? ??
          defaults.autoCreditTrustedBreakActivity,
      startWithWindows:
          values[_startWithWindowsKey] as bool? ?? defaults.startWithWindows,
      startMinimized:
          values[_startMinimizedKey] as bool? ?? defaults.startMinimized,
      minimizeToTray:
          values[_minimizeToTrayKey] as bool? ?? defaults.minimizeToTray,
      continueTimersAfterClose:
          values[_continueTimersAfterCloseKey] as bool? ??
          defaults.continueTimersAfterClose,
      resumeAfterWindowsSignIn:
          values[_resumeAfterWindowsSignInKey] as bool? ??
          defaults.resumeAfterWindowsSignIn,
      allowWakeTimers:
          values[_allowWakeTimersKey] as bool? ?? defaults.allowWakeTimers,
      runReminderServiceInBackground:
          values[_runReminderServiceInBackgroundKey] as bool? ??
          defaults.runReminderServiceInBackground,
      androidForegroundTimerService:
          values[_androidForegroundTimerServiceKey] as bool? ??
          defaults.androidForegroundTimerService,
      androidExactAlarmGuidance:
          values[_androidExactAlarmGuidanceKey] as bool? ??
          defaults.androidExactAlarmGuidance,
      androidBatteryOptimizationGuidance:
          values[_androidBatteryOptimizationGuidanceKey] as bool? ??
          defaults.androidBatteryOptimizationGuidance,
    );
  }

  Future<void> save(AppConfig config) async {
    final values = <String, Object?>{
      _localeCodeKey: config.locale.languageCode,
      _themeModeKey: _themeModeToStorage(config.themeMode),
      _themeChoiceKey: config.themeChoice.storageValue,
      _rememberSessionKey: config.rememberSession,
      _restoreWindowGeometryKey: config.restoreWindowGeometry,
      _restoreWindowMaximizedKey: config.restoreWindowMaximized,
      _compactDesktopKey: config.compactDesktop,
      _reducedMotionKey: config.reducedMotion,
      _highContrastKey: config.highContrast,
      _uiClickSoundsKey: config.uiClickSounds,
      _uiClickVolumeKey: config.uiClickVolume,
      _notificationSoundsKey: config.notificationSounds,
      _pomodoroSoundsKey: config.pomodoroSounds,
      _completionSoundsKey: config.completionSounds,
      _errorSoundsKey: config.errorSounds,
      _hapticFeedbackKey: config.hapticFeedback,
      _saveWebsitePasswordsKey: config.saveWebsitePasswords,
      _passwordAutofillKey: config.passwordAutofill,
      _formAutofillKey: config.formAutofill,
      _saveCookiesAndSessionsKey: config.saveCookiesAndSessions,
      _syncBrowserTabsAndUrlsKey: config.syncBrowserTabsAndUrls,
      _trackBrowserActivityKey: config.trackBrowserActivity,
      _trackFullUrlsKey: config.trackFullUrls,
      _trackPageTitlesKey: config.trackPageTitles,
      _trackSearchQueriesKey: config.trackSearchQueries,
      _trackExternalApplicationsKey: config.trackExternalApplications,
      _pauseTrackingInPrivateModeKey: config.pauseTrackingInPrivateMode,
      _defaultSearchEngineKey: config.defaultSearchEngine,
      _customSearchUrlKey: config.customSearchUrl,
      _excludedActivityDomainsKey: config.excludedActivityDomains,
      _excludedActivityApplicationsKey: config.excludedActivityApplications,
      _wakeUpTimeKey: config.wakeUpTime,
      _bedtimeKey: config.bedtime,
      _workStartTimeKey: config.workStartTime,
      _workEndTimeKey: config.workEndTime,
      _workdaysKey: config.workdays,
      _lunchDurationKey: config.lunchDurationMinutes,
      _commuteToWorkKey: config.commuteToWorkMinutes,
      _commuteHomeKey: config.commuteHomeMinutes,
      _maxDailyStudyKey: config.maxDailyStudyMinutes,
      _maxWeeklyStudyKey: config.maxWeeklyStudyMinutes,
      _weeklyReviewTimeKey: config.weeklyReviewTime,
      _quietHoursStartKey: config.quietHoursStart,
      _quietHoursEndKey: config.quietHoursEnd,
      _timeZoneModeKey: config.timeZoneMode,
      _fixedTimeZoneIdKey: config.fixedTimeZoneId,
      _homeTimeZoneIdKey: config.homeTimeZoneId,
      _travelTimeZoneBehaviorKey: config.travelTimeZoneBehavior,
      _askBeforeAdjustingTimeZoneKey: config.askBeforeAdjustingTimeZone,
      _keepHomeTimeZoneWhileTravellingKey:
          config.keepHomeTimeZoneWhileTravelling,
      _healthDataLocalOnlyKey: config.healthDataLocalOnly,
      _coachingIntensityKey: config.coachingIntensity,
      _askBreakActivityReviewKey: config.askBreakActivityReview,
      _autoCreditTrustedBreakActivityKey: config.autoCreditTrustedBreakActivity,
      _startWithWindowsKey: config.startWithWindows,
      _startMinimizedKey: config.startMinimized,
      _minimizeToTrayKey: config.minimizeToTray,
      _continueTimersAfterCloseKey: config.continueTimersAfterClose,
      _resumeAfterWindowsSignInKey: config.resumeAfterWindowsSignIn,
      _allowWakeTimersKey: config.allowWakeTimers,
      _runReminderServiceInBackgroundKey: config.runReminderServiceInBackground,
      _androidForegroundTimerServiceKey: config.androidForegroundTimerService,
      _androidExactAlarmGuidanceKey: config.androidExactAlarmGuidance,
      _androidBatteryOptimizationGuidanceKey:
          config.androidBatteryOptimizationGuidance,
    };

    await _writeSettings(values);
  }

  Future<Map<String, dynamic>> _readSettings() async {
    final file = _resolveSettingsFile();
    if (!await file.exists()) {
      return const {};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on Object {
      return const {};
    }
    return const {};
  }

  Future<void> _writeSettings(Map<String, Object?> values) async {
    final file = _resolveSettingsFile();
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(values));
  }

  File _resolveSettingsFile() {
    final explicit = _settingsFile;
    if (explicit != null) {
      return explicit;
    }

    final basePath = Platform.isWindows
        ? Platform.environment['APPDATA']
        : Platform.environment['HOME'];
    final base = basePath != null && basePath.trim().isNotEmpty
        ? Directory(basePath)
        : Directory.systemTemp;

    return File(
      '${base.path}${Platform.pathSeparator}TaskMasterPro'
      '${Platform.pathSeparator}settings.json',
    );
  }

  static String _normalizeLocale(String localeCode) {
    return switch (localeCode) {
      'ar' => 'ar',
      'de' => 'de',
      _ => 'en',
    };
  }

  static ThemeMode _themeModeFromStorage(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String _themeModeToStorage(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  static double? _doubleFromStorage(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static int _intFromStorage(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<int> _intListFromStorage(Object? value) {
    if (value is List) {
      final result = <int>[];
      for (final item in value) {
        if (item is int) {
          result.add(item);
          continue;
        }
        final parsed = int.tryParse(item.toString());
        if (parsed != null) {
          result.add(parsed);
        }
      }
      return result;
    }
    return const [];
  }

  static List<String> _stringListFromStorage(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
