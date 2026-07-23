import 'package:flutter/material.dart';

enum AppThemeChoice { darkBlue, blackGold, light }

extension AppThemeChoiceLabel on AppThemeChoice {
  String get storageValue => switch (this) {
    AppThemeChoice.darkBlue => 'dark_blue',
    AppThemeChoice.blackGold => 'black_gold',
    AppThemeChoice.light => 'light',
  };

  static AppThemeChoice fromStorage(String? value) {
    return switch (value) {
      'black_gold' => AppThemeChoice.blackGold,
      'light' => AppThemeChoice.light,
      _ => AppThemeChoice.darkBlue,
    };
  }
}

class SupabaseTarget {
  const SupabaseTarget({required this.url, required this.publicKey});

  final String url;
  final String publicKey;

  bool get isComplete => url.trim().isNotEmpty && publicKey.trim().isNotEmpty;

  SupabaseTarget copyWith({String? url, String? publicKey}) {
    return SupabaseTarget(
      url: url ?? this.url,
      publicKey: publicKey ?? this.publicKey,
    );
  }
}

class AppConfig {
  const AppConfig({
    required this.locale,
    required this.themeMode,
    required this.themeChoice,
    required this.rememberSession,
    required this.restoreWindowGeometry,
    required this.restoreWindowMaximized,
    required this.compactDesktop,
    required this.reducedMotion,
    required this.highContrast,
    required this.uiClickSounds,
    required this.uiClickVolume,
    required this.notificationSounds,
    required this.pomodoroSounds,
    required this.completionSounds,
    required this.errorSounds,
    required this.hapticFeedback,
    required this.saveWebsitePasswords,
    required this.passwordAutofill,
    required this.formAutofill,
    required this.saveCookiesAndSessions,
    required this.syncBrowserTabsAndUrls,
    required this.trackBrowserActivity,
    required this.trackFullUrls,
    required this.trackPageTitles,
    required this.trackSearchQueries,
    required this.trackExternalApplications,
    required this.pauseTrackingInPrivateMode,
    required this.defaultSearchEngine,
    required this.customSearchUrl,
    required this.excludedActivityDomains,
    required this.excludedActivityApplications,
    required this.wakeUpTime,
    required this.bedtime,
    required this.workStartTime,
    required this.workEndTime,
    required this.workdays,
    required this.lunchDurationMinutes,
    required this.commuteToWorkMinutes,
    required this.commuteHomeMinutes,
    required this.maxDailyStudyMinutes,
    required this.maxWeeklyStudyMinutes,
    required this.weeklyReviewTime,
    required this.quietHoursStart,
    required this.quietHoursEnd,
    required this.timeZoneMode,
    required this.fixedTimeZoneId,
    required this.homeTimeZoneId,
    required this.travelTimeZoneBehavior,
    required this.askBeforeAdjustingTimeZone,
    required this.keepHomeTimeZoneWhileTravelling,
    required this.healthDataLocalOnly,
    required this.coachingIntensity,
    required this.askBreakActivityReview,
    required this.autoCreditTrustedBreakActivity,
    required this.startWithWindows,
    required this.startMinimized,
    required this.minimizeToTray,
    required this.continueTimersAfterClose,
    required this.resumeAfterWindowsSignIn,
    required this.allowWakeTimers,
    required this.runReminderServiceInBackground,
    required this.androidForegroundTimerService,
    required this.androidExactAlarmGuidance,
    required this.androidBatteryOptimizationGuidance,
  });

  factory AppConfig.defaults() {
    return const AppConfig(
      locale: Locale('en'),
      themeMode: ThemeMode.system,
      themeChoice: AppThemeChoice.darkBlue,
      rememberSession: true,
      restoreWindowGeometry: true,
      restoreWindowMaximized: true,
      compactDesktop: false,
      reducedMotion: false,
      highContrast: false,
      uiClickSounds: true,
      uiClickVolume: 0.65,
      notificationSounds: true,
      pomodoroSounds: true,
      completionSounds: true,
      errorSounds: true,
      hapticFeedback: true,
      saveWebsitePasswords: false,
      passwordAutofill: true,
      formAutofill: true,
      saveCookiesAndSessions: true,
      syncBrowserTabsAndUrls: false,
      trackBrowserActivity: true,
      trackFullUrls: false,
      trackPageTitles: true,
      trackSearchQueries: false,
      trackExternalApplications: false,
      pauseTrackingInPrivateMode: true,
      defaultSearchEngine: 'google',
      customSearchUrl: '',
      excludedActivityDomains: [],
      excludedActivityApplications: [],
      wakeUpTime: '05:00',
      bedtime: '23:30',
      workStartTime: '09:00',
      workEndTime: '17:30',
      workdays: [6, 7, 1, 2, 3, 4],
      lunchDurationMinutes: 45,
      commuteToWorkMinutes: 30,
      commuteHomeMinutes: 30,
      maxDailyStudyMinutes: 120,
      maxWeeklyStudyMinutes: 780,
      weeklyReviewTime: 'Friday 07:00',
      quietHoursStart: '22:30',
      quietHoursEnd: '05:00',
      timeZoneMode: 'device',
      fixedTimeZoneId: 'Africa/Cairo',
      homeTimeZoneId: 'Africa/Cairo',
      travelTimeZoneBehavior: 'ask',
      askBeforeAdjustingTimeZone: true,
      keepHomeTimeZoneWhileTravelling: false,
      healthDataLocalOnly: false,
      coachingIntensity: 'active',
      askBreakActivityReview: true,
      autoCreditTrustedBreakActivity: false,
      startWithWindows: false,
      startMinimized: false,
      minimizeToTray: true,
      continueTimersAfterClose: true,
      resumeAfterWindowsSignIn: true,
      allowWakeTimers: false,
      runReminderServiceInBackground: true,
      androidForegroundTimerService: true,
      androidExactAlarmGuidance: true,
      androidBatteryOptimizationGuidance: true,
    );
  }

  final Locale locale;
  final ThemeMode themeMode;
  final AppThemeChoice themeChoice;
  final bool rememberSession;
  final bool restoreWindowGeometry;
  final bool restoreWindowMaximized;
  final bool compactDesktop;
  final bool reducedMotion;
  final bool highContrast;
  final bool uiClickSounds;
  final double uiClickVolume;
  final bool notificationSounds;
  final bool pomodoroSounds;
  final bool completionSounds;
  final bool errorSounds;
  final bool hapticFeedback;
  final bool saveWebsitePasswords;
  final bool passwordAutofill;
  final bool formAutofill;
  final bool saveCookiesAndSessions;
  final bool syncBrowserTabsAndUrls;
  final bool trackBrowserActivity;
  final bool trackFullUrls;
  final bool trackPageTitles;
  final bool trackSearchQueries;
  final bool trackExternalApplications;
  final bool pauseTrackingInPrivateMode;
  final String defaultSearchEngine;
  final String customSearchUrl;
  final List<String> excludedActivityDomains;
  final List<String> excludedActivityApplications;
  final String wakeUpTime;
  final String bedtime;
  final String workStartTime;
  final String workEndTime;
  final List<int> workdays;
  final int lunchDurationMinutes;
  final int commuteToWorkMinutes;
  final int commuteHomeMinutes;
  final int maxDailyStudyMinutes;
  final int maxWeeklyStudyMinutes;
  final String weeklyReviewTime;
  final String quietHoursStart;
  final String quietHoursEnd;
  final String timeZoneMode;
  final String fixedTimeZoneId;
  final String homeTimeZoneId;
  final String travelTimeZoneBehavior;
  final bool askBeforeAdjustingTimeZone;
  final bool keepHomeTimeZoneWhileTravelling;
  final bool healthDataLocalOnly;
  final String coachingIntensity;
  final bool askBreakActivityReview;
  final bool autoCreditTrustedBreakActivity;
  final bool startWithWindows;
  final bool startMinimized;
  final bool minimizeToTray;
  final bool continueTimersAfterClose;
  final bool resumeAfterWindowsSignIn;
  final bool allowWakeTimers;
  final bool runReminderServiceInBackground;
  final bool androidForegroundTimerService;
  final bool androidExactAlarmGuidance;
  final bool androidBatteryOptimizationGuidance;

  bool get isRtl => locale.languageCode == 'ar';

  AppConfig copyWith({
    Locale? locale,
    ThemeMode? themeMode,
    AppThemeChoice? themeChoice,
    bool? rememberSession,
    bool? restoreWindowGeometry,
    bool? restoreWindowMaximized,
    bool? compactDesktop,
    bool? reducedMotion,
    bool? highContrast,
    bool? uiClickSounds,
    double? uiClickVolume,
    bool? notificationSounds,
    bool? pomodoroSounds,
    bool? completionSounds,
    bool? errorSounds,
    bool? hapticFeedback,
    bool? saveWebsitePasswords,
    bool? passwordAutofill,
    bool? formAutofill,
    bool? saveCookiesAndSessions,
    bool? syncBrowserTabsAndUrls,
    bool? trackBrowserActivity,
    bool? trackFullUrls,
    bool? trackPageTitles,
    bool? trackSearchQueries,
    bool? trackExternalApplications,
    bool? pauseTrackingInPrivateMode,
    String? defaultSearchEngine,
    String? customSearchUrl,
    List<String>? excludedActivityDomains,
    List<String>? excludedActivityApplications,
    String? wakeUpTime,
    String? bedtime,
    String? workStartTime,
    String? workEndTime,
    List<int>? workdays,
    int? lunchDurationMinutes,
    int? commuteToWorkMinutes,
    int? commuteHomeMinutes,
    int? maxDailyStudyMinutes,
    int? maxWeeklyStudyMinutes,
    String? weeklyReviewTime,
    String? quietHoursStart,
    String? quietHoursEnd,
    String? timeZoneMode,
    String? fixedTimeZoneId,
    String? homeTimeZoneId,
    String? travelTimeZoneBehavior,
    bool? askBeforeAdjustingTimeZone,
    bool? keepHomeTimeZoneWhileTravelling,
    bool? healthDataLocalOnly,
    String? coachingIntensity,
    bool? askBreakActivityReview,
    bool? autoCreditTrustedBreakActivity,
    bool? startWithWindows,
    bool? startMinimized,
    bool? minimizeToTray,
    bool? continueTimersAfterClose,
    bool? resumeAfterWindowsSignIn,
    bool? allowWakeTimers,
    bool? runReminderServiceInBackground,
    bool? androidForegroundTimerService,
    bool? androidExactAlarmGuidance,
    bool? androidBatteryOptimizationGuidance,
  }) {
    return AppConfig(
      locale: locale ?? this.locale,
      themeMode: themeMode ?? this.themeMode,
      themeChoice: themeChoice ?? this.themeChoice,
      rememberSession: rememberSession ?? this.rememberSession,
      restoreWindowGeometry:
          restoreWindowGeometry ?? this.restoreWindowGeometry,
      restoreWindowMaximized:
          restoreWindowMaximized ?? this.restoreWindowMaximized,
      compactDesktop: compactDesktop ?? this.compactDesktop,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      highContrast: highContrast ?? this.highContrast,
      uiClickSounds: uiClickSounds ?? this.uiClickSounds,
      uiClickVolume: uiClickVolume ?? this.uiClickVolume,
      notificationSounds: notificationSounds ?? this.notificationSounds,
      pomodoroSounds: pomodoroSounds ?? this.pomodoroSounds,
      completionSounds: completionSounds ?? this.completionSounds,
      errorSounds: errorSounds ?? this.errorSounds,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      saveWebsitePasswords: saveWebsitePasswords ?? this.saveWebsitePasswords,
      passwordAutofill: passwordAutofill ?? this.passwordAutofill,
      formAutofill: formAutofill ?? this.formAutofill,
      saveCookiesAndSessions:
          saveCookiesAndSessions ?? this.saveCookiesAndSessions,
      syncBrowserTabsAndUrls:
          syncBrowserTabsAndUrls ?? this.syncBrowserTabsAndUrls,
      trackBrowserActivity: trackBrowserActivity ?? this.trackBrowserActivity,
      trackFullUrls: trackFullUrls ?? this.trackFullUrls,
      trackPageTitles: trackPageTitles ?? this.trackPageTitles,
      trackSearchQueries: trackSearchQueries ?? this.trackSearchQueries,
      trackExternalApplications:
          trackExternalApplications ?? this.trackExternalApplications,
      pauseTrackingInPrivateMode:
          pauseTrackingInPrivateMode ?? this.pauseTrackingInPrivateMode,
      defaultSearchEngine: defaultSearchEngine ?? this.defaultSearchEngine,
      customSearchUrl: customSearchUrl ?? this.customSearchUrl,
      excludedActivityDomains:
          excludedActivityDomains ?? this.excludedActivityDomains,
      excludedActivityApplications:
          excludedActivityApplications ?? this.excludedActivityApplications,
      wakeUpTime: wakeUpTime ?? this.wakeUpTime,
      bedtime: bedtime ?? this.bedtime,
      workStartTime: workStartTime ?? this.workStartTime,
      workEndTime: workEndTime ?? this.workEndTime,
      workdays: workdays ?? this.workdays,
      lunchDurationMinutes: lunchDurationMinutes ?? this.lunchDurationMinutes,
      commuteToWorkMinutes: commuteToWorkMinutes ?? this.commuteToWorkMinutes,
      commuteHomeMinutes: commuteHomeMinutes ?? this.commuteHomeMinutes,
      maxDailyStudyMinutes: maxDailyStudyMinutes ?? this.maxDailyStudyMinutes,
      maxWeeklyStudyMinutes:
          maxWeeklyStudyMinutes ?? this.maxWeeklyStudyMinutes,
      weeklyReviewTime: weeklyReviewTime ?? this.weeklyReviewTime,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      timeZoneMode: timeZoneMode ?? this.timeZoneMode,
      fixedTimeZoneId: fixedTimeZoneId ?? this.fixedTimeZoneId,
      homeTimeZoneId: homeTimeZoneId ?? this.homeTimeZoneId,
      travelTimeZoneBehavior:
          travelTimeZoneBehavior ?? this.travelTimeZoneBehavior,
      askBeforeAdjustingTimeZone:
          askBeforeAdjustingTimeZone ?? this.askBeforeAdjustingTimeZone,
      keepHomeTimeZoneWhileTravelling:
          keepHomeTimeZoneWhileTravelling ??
          this.keepHomeTimeZoneWhileTravelling,
      healthDataLocalOnly: healthDataLocalOnly ?? this.healthDataLocalOnly,
      coachingIntensity: coachingIntensity ?? this.coachingIntensity,
      askBreakActivityReview:
          askBreakActivityReview ?? this.askBreakActivityReview,
      autoCreditTrustedBreakActivity:
          autoCreditTrustedBreakActivity ?? this.autoCreditTrustedBreakActivity,
      startWithWindows: startWithWindows ?? this.startWithWindows,
      startMinimized: startMinimized ?? this.startMinimized,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      continueTimersAfterClose:
          continueTimersAfterClose ?? this.continueTimersAfterClose,
      resumeAfterWindowsSignIn:
          resumeAfterWindowsSignIn ?? this.resumeAfterWindowsSignIn,
      allowWakeTimers: allowWakeTimers ?? this.allowWakeTimers,
      runReminderServiceInBackground:
          runReminderServiceInBackground ?? this.runReminderServiceInBackground,
      androidForegroundTimerService:
          androidForegroundTimerService ?? this.androidForegroundTimerService,
      androidExactAlarmGuidance:
          androidExactAlarmGuidance ?? this.androidExactAlarmGuidance,
      androidBatteryOptimizationGuidance:
          androidBatteryOptimizationGuidance ??
          this.androidBatteryOptimizationGuidance,
    );
  }
}
