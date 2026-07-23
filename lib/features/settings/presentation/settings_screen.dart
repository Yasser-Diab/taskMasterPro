// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart';

import '../../../app/app_services.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/config/supabase_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/platform/app_lifecycle_service.dart';
import '../../../core/platform/external_url_launcher.dart';
import '../../../core/platform/health_data_service.dart';
import '../../../core/platform/task_browser_surface_controller.dart';
import '../../../core/platform/task_reminder_scheduler.dart';
import '../../../core/widgets/app_controls.dart';
import '../../pomodoro/domain/pomodoro_controller.dart';
import '../../pomodoro/domain/pomodoro_models.dart';
import '../../tasks/application/task_action_controller.dart';
import 'account_profile_screen.dart';
import 'about_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    this.taskController,
    this.pomodoroController,
    super.key,
  });

  final TaskActionController? taskController;
  final PomodoroController? pomodoroController;
  static const _privacyUrl =
      'https://yasser-diab.github.io/taskMasterPro/privacy-policy/';
  static const _termsUrl = 'https://yasser-diab.github.io/taskMasterPro/terms/';

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final config = services.config;

    return _TaskBrowserHidden(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(context.text('settings')),
          actions: [
            if (services.supabaseService.isSignedIn)
              AppIconButton(
                tooltip: context.text('signOut'),
                onPressed: () => _confirmAndSignOut(context),
                icon: const Icon(Icons.logout_outlined),
              ),
          ],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                children: [
                  _SettingsGroup(
                    title: context.text('accountSecurity'),
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(context.text('profileTitle')),
                        subtitle: Text(
                          services
                                      .supabaseService
                                      .profile
                                      ?.displayName
                                      .isNotEmpty ==
                                  true
                              ? services.supabaseService.profile!.displayName
                              : services.supabaseService.profile?.email ??
                                    context.text('notSignedIn'),
                        ),
                        onTap: services.supabaseService.isSignedIn
                            ? () {
                                services.feedbackService.playUiClick();
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AccountProfileScreen(
                                      taskController: taskController,
                                      pomodoroController: pomodoroController,
                                      onOpenDeleteAccount: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const DeleteAccountScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              }
                            : null,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.password_outlined),
                        title: Text(context.text('changePassword')),
                        subtitle: Text(context.text('changePasswordHelp')),
                        onTap:
                            services.supabaseService.currentUser?.email == null
                            ? null
                            : () => _requestPasswordReset(context),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.devices_outlined),
                        title: Text(context.text('activeSessions')),
                        subtitle: Text(context.text('activeSessionsHelp')),
                        onTap: () => showAccountDevicesDialog(context),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.download_outlined),
                        title: Text(context.text('exportMyData')),
                        subtitle: Text(context.text('exportMyDataHelp')),
                        onTap: services.supabaseService.isSignedIn
                            ? () => _exportMyData(context)
                            : null,
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.logout_outlined),
                        title: Text(context.text('logoutThisDevice')),
                        onTap: services.supabaseService.isSignedIn
                            ? () => _confirmAndSignOut(context)
                            : null,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.logout),
                        title: Text(context.text('logoutAllDevices')),
                        subtitle: Text(context.text('logoutAllDevicesHelp')),
                        onTap: services.supabaseService.isSignedIn
                            ? () =>
                                  _confirmAndSignOut(context, allDevices: true)
                            : null,
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.delete_forever_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(context.text('deleteAccount')),
                        subtitle: Text(context.text('deleteAccountHelp')),
                        onTap: services.supabaseService.isSignedIn
                            ? () {
                                services.feedbackService.playUiClick();
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const DeleteAccountScreen(),
                                  ),
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    title: context.text('language'),
                    children: [
                      DropdownButtonFormField<Locale>(
                        initialValue: config.locale,
                        items: [
                          DropdownMenuItem(
                            value: const Locale('en'),
                            child: Text(context.text('english')),
                          ),
                          DropdownMenuItem(
                            value: const Locale('ar'),
                            child: Text(context.text('arabic')),
                          ),
                          DropdownMenuItem(
                            value: const Locale('de'),
                            child: Text(context.text('german')),
                          ),
                        ],
                        onChanged: (locale) {
                          if (locale == null) {
                            return;
                          }
                          services.feedbackService.playUiClick();
                          services.updateConfig(
                            config.copyWith(locale: locale),
                          );
                        },
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    title: context.text('theme'),
                    children: [
                      DropdownButtonFormField<AppThemeChoice>(
                        initialValue: config.themeChoice,
                        items: [
                          DropdownMenuItem(
                            value: AppThemeChoice.darkBlue,
                            child: Text(context.text('darkBlue')),
                          ),
                          DropdownMenuItem(
                            value: AppThemeChoice.blackGold,
                            child: Text(context.text('blackGold')),
                          ),
                          DropdownMenuItem(
                            value: AppThemeChoice.light,
                            child: Text(context.text('lightTheme')),
                          ),
                        ],
                        onChanged: (choice) {
                          if (choice == null) {
                            return;
                          }
                          services.feedbackService.playUiClick();
                          services.updateConfig(
                            config.copyWith(themeChoice: choice),
                          );
                        },
                      ),
                      AppSwitchListTile(
                        value: config.compactDesktop,
                        title: Text(context.text('compactDesktop')),
                        onChanged: (value) {
                          services.updateConfig(
                            config.copyWith(compactDesktop: value),
                          );
                        },
                      ),
                      AppSwitchListTile(
                        value: config.reducedMotion,
                        title: Text(context.text('reducedMotion')),
                        onChanged: (value) {
                          services.updateConfig(
                            config.copyWith(reducedMotion: value),
                          );
                        },
                      ),
                      AppSwitchListTile(
                        value: config.highContrast,
                        title: Text(context.text('highContrast')),
                        onChanged: (value) {
                          services.updateConfig(
                            config.copyWith(highContrast: value),
                          );
                        },
                      ),
                    ],
                  ),
                  _ApplicationSettingsGroup(config: config),
                  _ScheduleSettingsGroup(config: config),
                  _TimeZoneSettingsGroup(config: config),
                  _CoachingSettingsGroup(config: config),
                  if (Platform.isAndroid) ...[
                    _AndroidNotificationSettingsGroup(
                      config: config,
                      taskController: taskController,
                    ),
                    _HealthSettingsGroup(config: config),
                  ],
                  _CycleWellbeingSettingsGroup(
                    onOpenProfile: services.supabaseService.isSignedIn
                        ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AccountProfileScreen(
                                  taskController: taskController,
                                  pomodoroController: pomodoroController,
                                ),
                              ),
                            );
                          }
                        : null,
                  ),
                  if (Platform.isWindows)
                    _WindowsRuntimeSettingsGroup(config: config),
                  _SettingsGroup(
                    title: context.text('synchronization'),
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: Text(context.text('downloadLatestAccountData')),
                        subtitle: Text(
                          context.text('downloadLatestAccountDataHelp'),
                        ),
                        onTap: services.supabaseService.isSignedIn
                            ? () => _fullAccountRefresh(context)
                            : null,
                      ),
                    ],
                  ),
                  _SoundsSettingsGroup(config: config),
                  _BrowserPrivacySettingsGroup(config: config),
                  if (services.supabaseService.isOwner)
                    _SettingsGroup(
                      title: context.text('administration'),
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.admin_panel_settings_outlined,
                          ),
                          title: Text(context.text('backendSupabase')),
                          subtitle: Text(context.text('ownerOnly')),
                          onTap: () {
                            services.feedbackService.playUiClick();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const BackendAdministrationScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.refresh_outlined),
                          title: Text(context.text('clearCacheReload')),
                          subtitle: Text(context.text('clearCacheReloadHelp')),
                          onTap: () => _fullAccountRefresh(context),
                        ),
                      ],
                    ),
                  _SettingsGroup(
                    title: context.text('about'),
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline),
                        title: Text(context.text('about')),
                        subtitle: Text(context.text('aboutText')),
                        onTap: () {
                          services.feedbackService.playUiClick();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AboutScreen(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: Text(context.text('privacyPolicy')),
                        onTap: () => ExternalUrlLauncher.open(_privacyUrl),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(context.text('termsOfService')),
                        onTap: () => ExternalUrlLauncher.open(_termsUrl),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestPasswordReset(BuildContext context) async {
    final services = AppServices.of(context);
    services.feedbackService.playUiClick();
    final email = services.supabaseService.currentUser?.email;
    if (email == null) {
      return;
    }
    final error = await services.supabaseService.resetPasswordForEmail(email);
    if (!context.mounted) {
      return;
    }
    if (error == null) {
      services.notificationService.showSuccess(
        context.text('resetPasswordSent'),
      );
    } else {
      services.notificationService.showError(error);
    }
  }

  Future<void> _fullAccountRefresh(BuildContext context) async {
    final services = AppServices.of(context);
    services.feedbackService.playUiClick();
    try {
      await services.supabaseService.fullRemoteRefresh();
      await taskController?.load();
      if (!context.mounted) {
        return;
      }
      services.notificationService.showSuccess(
        context.text('accountDataRefreshed'),
      );
    } on Object {
      if (!context.mounted) {
        return;
      }
      services.notificationService.showError(
        context.text('accountDataRefreshFailed'),
      );
    }
  }

  Future<void> _exportMyData(BuildContext context) async {
    final services = AppServices.of(context);
    services.feedbackService.playUiClick();
    try {
      final export = await services.supabaseService.exportMyData();
      if (export == null) {
        if (!context.mounted) {
          return;
        }
        services.notificationService.showError(context.text('exportFailed'));
        return;
      }
      final directory = await _exportDirectory();
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}${Platform.pathSeparator}${export.fileName}',
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(export.data),
      );
      if (!context.mounted) {
        return;
      }
      services.notificationService.showSuccess(
        '${context.text('exportReady')}: ${file.path}',
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      services.notificationService.showError(
        '${context.text('exportFailed')}: $error',
      );
    }
  }

  Future<void> _confirmAndSignOut(
    BuildContext context, {
    bool allDevices = false,
  }) async {
    final services = AppServices.of(context);
    services.feedbackService.playUiClick();
    final action = await _resolveActiveSessionBeforeLogout(context);
    if (action == _LogoutSessionAction.cancel) {
      return;
    }

    await services.lifecycleService.updateActiveSession(
      const ActiveSessionStatus.inactive(),
    );
    await services.supabaseService.signOut(allDevices: allDevices);
  }

  Future<_LogoutSessionAction> _resolveActiveSessionBeforeLogout(
    BuildContext context,
  ) async {
    final activeTask = taskController?.activeSession;
    final hasPomodoro =
        pomodoroController != null && !pomodoroController!.state.isInactive;
    if (activeTask == null && !hasPomodoro) {
      return _LogoutSessionAction.none;
    }

    final action = await showDialog<_LogoutSessionAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.text('activeSessionRunning')),
        content: Text(context.text('activeSessionLogoutHelp')),
        actions: [
          AppButton.text(
            onPressed: () =>
                Navigator.of(context).pop(_LogoutSessionAction.cancel),
            label: Text(context.text('cancel')),
          ),
          AppButton.outlined(
            onPressed: () =>
                Navigator.of(context).pop(_LogoutSessionAction.discard),
            label: Text(context.text('discardSession')),
          ),
          AppButton.outlined(
            onPressed: () =>
                Navigator.of(context).pop(_LogoutSessionAction.pause),
            label: Text(context.text('pauseSessionAndLogout')),
          ),
          AppButton.filled(
            onPressed: () =>
                Navigator.of(context).pop(_LogoutSessionAction.end),
            label: Text(context.text('saveEndSession')),
          ),
        ],
      ),
    );

    final selected = action ?? _LogoutSessionAction.cancel;
    final controller = taskController;
    final task = activeTask?.task;
    if (selected == _LogoutSessionAction.end &&
        controller != null &&
        task != null) {
      await controller.completeTask(task);
    } else if (selected == _LogoutSessionAction.pause &&
        controller != null &&
        task != null) {
      await controller.pauseTask(task);
    } else if (selected == _LogoutSessionAction.discard &&
        controller != null &&
        task != null) {
      await controller.cancelTask(task);
    }

    if (selected == _LogoutSessionAction.end) {
      pomodoroController?.stopAndSave();
    } else if (selected == _LogoutSessionAction.discard) {
      pomodoroController?.stopWithoutSaving();
    } else if (selected == _LogoutSessionAction.pause &&
        pomodoroController?.state.isRunning == true) {
      pomodoroController?.pause();
    }

    return selected;
  }

  Future<Directory> _exportDirectory() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home${Platform.pathSeparator}Downloads');
      }
    }
    return Directory.systemTemp.createTemp('taskmaster-pro-export-');
  }
}

enum _LogoutSessionAction { none, end, pause, discard, cancel }

class _ApplicationSettingsGroup extends StatelessWidget {
  const _ApplicationSettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return _SettingsGroup(
      title: context.text('applicationSettings'),
      children: [
        AppSwitchListTile(
          value: config.restoreWindowGeometry,
          title: Text(context.text('restoreWindowGeometry')),
          onChanged: (value) {
            services.updateConfig(
              config.copyWith(restoreWindowGeometry: value),
            );
          },
        ),
        AppSwitchListTile(
          value: config.restoreWindowMaximized,
          title: Text(context.text('restoreWindowMaximized')),
          onChanged: config.restoreWindowGeometry
              ? (value) {
                  services.updateConfig(
                    config.copyWith(restoreWindowMaximized: value),
                  );
                }
              : null,
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.fit_screen_outlined),
          title: Text(context.text('resetWindowPosition')),
          onTap: () async {
            services.feedbackService.playUiClick();
            await services.lifecycleService.resetWindowPosition();
            if (!context.mounted) {
              return;
            }
            services.notificationService.showSuccess(
              context.text('windowPositionReset'),
            );
          },
        ),
      ],
    );
  }
}

class _ScheduleSettingsGroup extends StatelessWidget {
  const _ScheduleSettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return _SettingsGroup(
      title: context.text('scheduleAvailability'),
      compact: true,
      children: [
        _TimeGrid(
          children: [
            _SettingTimeField(
              label: context.text('wakeUpTime'),
              value: config.wakeUpTime,
              onChanged: (value) {
                services.updateConfig(config.copyWith(wakeUpTime: value));
              },
            ),
            _SettingTimeField(
              label: context.text('bedtime'),
              value: config.bedtime,
              onChanged: (value) {
                services.updateConfig(config.copyWith(bedtime: value));
              },
            ),
            _SettingTimeField(
              label: context.text('workStartTime'),
              value: config.workStartTime,
              onChanged: (value) {
                services.updateConfig(config.copyWith(workStartTime: value));
              },
            ),
            _SettingTimeField(
              label: context.text('workEndTime'),
              value: config.workEndTime,
              onChanged: (value) {
                services.updateConfig(config.copyWith(workEndTime: value));
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(context.text('workdays')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final day in _dayOptions)
              FilterChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selected: config.workdays.contains(day.value),
                label: Text(context.text(day.labelKey)),
                onSelected: (selected) {
                  services.feedbackService.playUiClick();
                  final next = [...config.workdays];
                  if (selected) {
                    next.add(day.value);
                  } else {
                    next.remove(day.value);
                  }
                  next.sort();
                  services.updateConfig(config.copyWith(workdays: next));
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        _NumberGrid(
          children: [
            _SettingNumberField(
              label: context.text('lunchDuration'),
              value: config.lunchDurationMinutes,
              onChanged: (value) {
                services.updateConfig(
                  config.copyWith(lunchDurationMinutes: value),
                );
              },
            ),
            _SettingNumberField(
              label: context.text('commuteToWork'),
              value: config.commuteToWorkMinutes,
              onChanged: (value) {
                services.updateConfig(
                  config.copyWith(commuteToWorkMinutes: value),
                );
              },
            ),
            _SettingNumberField(
              label: context.text('commuteHome'),
              value: config.commuteHomeMinutes,
              onChanged: (value) {
                services.updateConfig(
                  config.copyWith(commuteHomeMinutes: value),
                );
              },
            ),
            _SettingNumberField(
              label: context.text('maxDailyStudy'),
              value: config.maxDailyStudyMinutes,
              onChanged: (value) {
                services.updateConfig(
                  config.copyWith(maxDailyStudyMinutes: value),
                );
              },
            ),
            _SettingNumberField(
              label: context.text('maxWeeklyStudy'),
              value: config.maxWeeklyStudyMinutes,
              onChanged: (value) {
                services.updateConfig(
                  config.copyWith(maxWeeklyStudyMinutes: value),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        _WeeklyReviewTimeField(
          label: context.text('weeklyReviewTime'),
          value: config.weeklyReviewTime,
          onChanged: (value) {
            services.updateConfig(config.copyWith(weeklyReviewTime: value));
          },
        ),
        const SizedBox(height: 10),
        _TimeGrid(
          children: [
            _SettingTimeField(
              label: context.text('quietHoursStart'),
              value: config.quietHoursStart,
              onChanged: (value) {
                services.updateConfig(config.copyWith(quietHoursStart: value));
              },
            ),
            _SettingTimeField(
              label: context.text('quietHoursEnd'),
              value: config.quietHoursEnd,
              onChanged: (value) {
                services.updateConfig(config.copyWith(quietHoursEnd: value));
              },
            ),
          ],
        ),
        if (_sleepMinutes(config) < 420) ...[
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.nights_stay_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(context.text('sleepWarningTitle')),
            subtitle: Text(context.text('sleepWarningText')),
          ),
        ],
        const Divider(),
        AppSwitchListTile(
          value: config.askBreakActivityReview,
          title: Text(context.text('askBreakActivityReview')),
          subtitle: Text(context.text('askBreakActivityReviewHelp')),
          onChanged: (value) => services.updateConfig(
            config.copyWith(askBreakActivityReview: value),
          ),
        ),
      ],
    );
  }
}

class _TimeZoneSettingsGroup extends StatelessWidget {
  const _TimeZoneSettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final zoneService = services.timeZoneService;
    final effectiveZone = zoneService.effectiveZoneId(config);
    return _SettingsGroup(
      title: context.text('timeZoneSettings'),
      children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'device',
              label: Text(context.text('followDeviceTimeZone')),
              icon: const Icon(Icons.phone_android_outlined),
            ),
            ButtonSegment(
              value: 'fixed',
              label: Text(context.text('useFixedTimeZone')),
              icon: const Icon(Icons.public_outlined),
            ),
          ],
          selected: {config.timeZoneMode},
          onSelectionChanged: (selection) {
            services.updateConfig(
              config.copyWith(timeZoneMode: selection.first),
            );
          },
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(
            config.timeZoneMode == 'device'
                ? context.text('currentDeviceTimeZone')
                : context.text('selectedTimeZone'),
          ),
          subtitle: Text(
            '$effectiveZone · ${zoneService.offsetLabel(effectiveZone)}',
          ),
        ),
        if (config.timeZoneMode == 'fixed')
          _TimeZonePickerTile(
            value: config.fixedTimeZoneId,
            zoneIds: zoneService.availableZoneIds(),
            onChanged: (value) {
              services.updateConfig(config.copyWith(fixedTimeZoneId: value));
            },
          ),
        AppSwitchListTile(
          value: config.askBeforeAdjustingTimeZone,
          title: Text(context.text('askBeforeTimeZoneAdjustment')),
          onChanged: (value) => services.updateConfig(
            config.copyWith(askBeforeAdjustingTimeZone: value),
          ),
        ),
        AppSwitchListTile(
          value: config.keepHomeTimeZoneWhileTravelling,
          title: Text(context.text('keepHomeTimeZoneTravelling')),
          onChanged: (value) => services.updateConfig(
            config.copyWith(keepHomeTimeZoneWhileTravelling: value),
          ),
        ),
      ],
    );
  }
}

class _TimeZonePickerTile extends StatelessWidget {
  const _TimeZonePickerTile({
    required this.value,
    required this.zoneIds,
    required this.onChanged,
  });

  final String value;
  final List<String> zoneIds;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.travel_explore_outlined),
      title: Text(context.text('chooseTimeZone')),
      subtitle: Text(value),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (context) =>
              _TimeZoneSearchDialog(zoneIds: zoneIds, selected: value),
        );
        if (selected != null) onChanged(selected);
      },
    );
  }
}

class _TimeZoneSearchDialog extends StatefulWidget {
  const _TimeZoneSearchDialog({required this.zoneIds, required this.selected});

  final List<String> zoneIds;
  final String selected;

  @override
  State<_TimeZoneSearchDialog> createState() => _TimeZoneSearchDialogState();
}

class _TimeZoneSearchDialogState extends State<_TimeZoneSearchDialog> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.zoneIds
        : widget.zoneIds
              .where((zone) => zone.toLowerCase().contains(query))
              .toList();
    return AlertDialog(
      title: Text(context.text('chooseTimeZone')),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.text('searchTimeZones'),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final zone = filtered[index];
                  return ListTile(
                    selected: zone == widget.selected,
                    title: Text(zone, textDirection: TextDirection.ltr),
                    onTap: () => Navigator.of(context).pop(zone),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: Text(context.text('cancel')),
        ),
      ],
    );
  }
}

class _CoachingSettingsGroup extends StatelessWidget {
  const _CoachingSettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return _SettingsGroup(
      title: context.text('coaching'),
      children: [
        DropdownButtonFormField<String>(
          value: config.coachingIntensity,
          decoration: InputDecoration(
            labelText: context.text('coachingIntensity'),
          ),
          items: [
            _coachingItem(context, 'quiet', 'quiet'),
            _coachingItem(context, 'standard', 'standard'),
            _coachingItem(context, 'active', 'activeCoach'),
            _coachingItem(context, 'persistent', 'persistentCoach'),
            _coachingItem(context, 'custom', 'custom'),
          ],
          onChanged: (value) {
            if (value == null) return;
            AppServices.of(
              context,
            ).updateConfig(config.copyWith(coachingIntensity: value));
          },
        ),
      ],
    );
  }

  DropdownMenuItem<String> _coachingItem(
    BuildContext context,
    String value,
    String key,
  ) {
    return DropdownMenuItem(value: value, child: Text(context.text(key)));
  }
}

class _AndroidNotificationSettingsGroup extends StatefulWidget {
  const _AndroidNotificationSettingsGroup({
    required this.config,
    this.taskController,
  });

  final AppConfig config;
  final TaskActionController? taskController;

  @override
  State<_AndroidNotificationSettingsGroup> createState() =>
      _AndroidNotificationSettingsGroupState();
}

class _AndroidNotificationSettingsGroupState
    extends State<_AndroidNotificationSettingsGroup> {
  final TaskReminderScheduler _scheduler = const TaskReminderScheduler();
  NotificationPlatformStatus? _status;
  bool _loading = false;
  bool _openingSystemSettings = false;
  String? _systemSettingsError;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    final status = await _scheduler.status();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return _SettingsGroup(
      title: context.text('androidNotifications'),
      children: [
        AppSwitchListTile(
          value: widget.config.androidForegroundTimerService,
          title: Text(context.text('foregroundTimerService')),
          onChanged: (value) => AppServices.of(context).updateConfig(
            widget.config.copyWith(androidForegroundTimerService: value),
          ),
        ),
        AppSwitchListTile(
          value: widget.config.androidExactAlarmGuidance,
          title: Text(context.text('exactAlarmCapability')),
          onChanged: (value) => AppServices.of(context).updateConfig(
            widget.config.copyWith(androidExactAlarmGuidance: value),
          ),
        ),
        AppSwitchListTile(
          value: widget.config.androidBatteryOptimizationGuidance,
          title: Text(context.text('batteryOptimizationStatus')),
          onChanged: (value) => AppServices.of(context).updateConfig(
            widget.config.copyWith(androidBatteryOptimizationGuidance: value),
          ),
        ),
        _NotificationStatusRow(
          label: context.text('systemNotifications'),
          value: status == null
              ? context.text('notAvailable')
              : status.notificationsAllowed
              ? context.text('allowed')
              : context.text('notAllowed'),
          icon: status?.notificationsAllowed == true
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('taskReminders'),
          value: status?.notificationsAllowed == true
              ? context.text('operational')
              : context.text('notOperational'),
          icon: Icons.event_available_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('pomodoroTransitions'),
          value: status?.notificationsAllowed == true
              ? context.text('operational')
              : context.text('notOperational'),
          icon: Icons.timer_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('exactScheduling'),
          value: status?.exactSchedulingAvailable == true
              ? context.text('available')
              : context.text('notAvailable'),
          icon: Icons.alarm_on_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('activeTimerService'),
          value: status?.activeTimerRunning == true
              ? context.text('running')
              : context.text('stopped'),
          icon: Icons.play_circle_outline,
        ),
        _NotificationStatusRow(
          label: context.text('lastNotification'),
          value: _formatPlatformDateTime(context, status?.lastNotificationAt),
          icon: Icons.history_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('nextScheduledNotification'),
          value: _formatPlatformDateTime(context, status?.nextScheduledAt),
          icon: Icons.schedule_outlined,
        ),
        _NotificationSoundSummary(
          status: status,
          onOpenSystemSettings: _openingSystemSettings
              ? null
              : () => _openSystemNotificationSettings(context),
          onPreviewTaskReminder: _loading
              ? null
              : () => _sendTest(
                  context,
                  context.text('taskReminderSound'),
                  context.text('testNotificationBody'),
                  'task_reminders',
                ),
          onPreviewFocusAlarm: _loading
              ? null
              : () => _sendTest(
                  context,
                  context.text('focusAlarmSound'),
                  context.text('testPomodoroCompletionBody'),
                  'focus_alarm',
                ),
          onPreviewBreakAlarm: _loading
              ? null
              : () => _sendTest(
                  context,
                  context.text('breakAlarmSound'),
                  context.text('testPomodoroCompletionBody'),
                  'break_alarm',
                ),
        ),
        _NotificationAdvancedDetails(status: status),
        if (_systemSettingsError != null) ...[
          const SizedBox(height: 8),
          _InlineSettingsError(
            message: _systemSettingsError!,
            onRetry: () => _openSystemNotificationSettings(context),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton.outlined(
              onPressed: _loading
                  ? null
                  : () => _sendTest(
                      context,
                      context.text('sendTestNotification'),
                      context.text('testNotificationBody'),
                      'task_reminders',
                    ),
              icon: const Icon(Icons.notifications_outlined),
              label: Text(context.text('sendTestNotification')),
            ),
            AppButton.outlined(
              onPressed: _loading
                  ? null
                  : () => _sendTest(
                      context,
                      context.text('testTaskReminder'),
                      context.text('testTaskReminderBody'),
                      'task_reminders',
                    ),
              icon: const Icon(Icons.event_note_outlined),
              label: Text(context.text('testTaskReminder')),
            ),
            AppButton.outlined(
              onPressed: _loading
                  ? null
                  : () => _sendTest(
                      context,
                      context.text('testPomodoroCompletion'),
                      context.text('testPomodoroCompletionBody'),
                      'focus_alarm',
                    ),
              icon: const Icon(Icons.timer_outlined),
              label: Text(context.text('testPomodoroCompletion')),
            ),
            AppButton.outlined(
              onPressed: _loading
                  ? null
                  : () async {
                      await widget.taskController
                          ?.rescheduleRemindersForTimeZoneChange();
                      await _loadStatus();
                    },
              icon: const Icon(Icons.refresh_outlined),
              label: Text(context.text('rebuildScheduledNotifications')),
            ),
            AppButton.text(
              onPressed: _openingSystemSettings
                  ? null
                  : () => _openSystemNotificationSettings(context),
              icon: const Icon(Icons.settings_outlined),
              label: Text(context.text('openNotificationSettings')),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _sendTest(
    BuildContext context,
    String title,
    String body,
    String channel,
  ) async {
    await _scheduler.sendTestNotification(
      title: title,
      body: body,
      channel: channel,
    );
    await _loadStatus();
  }

  Future<void> _openSystemNotificationSettings(BuildContext context) async {
    if (_openingSystemSettings) return;
    setState(() {
      _openingSystemSettings = true;
      _systemSettingsError = null;
    });
    final opened = await _scheduler.openSystemNotificationSettings();
    if (!mounted) return;
    setState(() {
      _openingSystemSettings = false;
      _systemSettingsError = opened
          ? null
          : context.text('notificationSettingsOpenFailed');
    });
    await _loadStatus();
  }
}

class _WindowsRuntimeSettingsGroup extends StatelessWidget {
  const _WindowsRuntimeSettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return _SettingsGroup(
      title: context.text('windowsRuntime'),
      children: [
        AppSwitchListTile(
          value: config.startWithWindows,
          title: Text(context.text('startWithWindows')),
          onChanged: (value) =>
              services.updateConfig(config.copyWith(startWithWindows: value)),
        ),
        AppSwitchListTile(
          value: config.startMinimized,
          title: Text(context.text('startMinimized')),
          onChanged: (value) =>
              services.updateConfig(config.copyWith(startMinimized: value)),
        ),
        AppSwitchListTile(
          value: config.minimizeToTray,
          title: Text(context.text('minimizeToTray')),
          onChanged: (value) =>
              services.updateConfig(config.copyWith(minimizeToTray: value)),
        ),
        AppSwitchListTile(
          value: config.continueTimersAfterClose,
          title: Text(context.text('continueTimersAfterClose')),
          onChanged: (value) => services.updateConfig(
            config.copyWith(continueTimersAfterClose: value),
          ),
        ),
        AppSwitchListTile(
          value: config.runReminderServiceInBackground,
          title: Text(context.text('runReminderServiceInBackground')),
          onChanged: (value) => services.updateConfig(
            config.copyWith(runReminderServiceInBackground: value),
          ),
        ),
        AppSwitchListTile(
          value: config.resumeAfterWindowsSignIn,
          title: Text(context.text('resumeAfterWindowsSignIn')),
          onChanged: (value) => services.updateConfig(
            config.copyWith(resumeAfterWindowsSignIn: value),
          ),
        ),
        AppSwitchListTile(
          value: config.allowWakeTimers,
          title: Text(context.text('allowWakeTimers')),
          onChanged: (value) =>
              services.updateConfig(config.copyWith(allowWakeTimers: value)),
        ),
        AppButton.outlined(
          onPressed: () => const TaskReminderScheduler().sendTestNotification(
            title: context.text('sendTestNotification'),
            body: context.text('testNotificationBody'),
            channel: 'task_reminders',
          ),
          icon: const Icon(Icons.notifications_active_outlined),
          label: Text(context.text('testWindowsNotificationAudio')),
        ),
      ],
    );
  }
}

class _NotificationStatusRow extends StatelessWidget {
  const _NotificationStatusRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(value, textAlign: TextAlign.end),
    );
  }
}

class _NotificationSoundSummary extends StatelessWidget {
  const _NotificationSoundSummary({
    required this.status,
    required this.onOpenSystemSettings,
    required this.onPreviewTaskReminder,
    required this.onPreviewFocusAlarm,
    required this.onPreviewBreakAlarm,
  });

  final NotificationPlatformStatus? status;
  final VoidCallback? onOpenSystemSettings;
  final VoidCallback? onPreviewTaskReminder;
  final VoidCallback? onPreviewFocusAlarm;
  final VoidCallback? onPreviewBreakAlarm;

  @override
  Widget build(BuildContext context) {
    final soundReady = status?.channelSoundEnabled != false;
    final volume = status?.alarmVolume;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                soundReady
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
              ),
              title: Text(context.text('notificationSoundsReady')),
              subtitle: Text(
                volume == null
                    ? context.text('notificationSoundsHelp')
                    : '${context.text('alarmVolume')}: $volume',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton.outlined(
                  onPressed: onPreviewTaskReminder,
                  icon: const Icon(Icons.event_note_outlined),
                  label: Text(context.text('previewTaskReminderSound')),
                ),
                AppButton.outlined(
                  onPressed: onPreviewFocusAlarm,
                  icon: const Icon(Icons.timer_outlined),
                  label: Text(context.text('previewFocusAlarmSound')),
                ),
                AppButton.outlined(
                  onPressed: onPreviewBreakAlarm,
                  icon: const Icon(Icons.free_breakfast_outlined),
                  label: Text(context.text('previewBreakAlarmSound')),
                ),
                AppButton.text(
                  onPressed: onOpenSystemSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(context.text('chooseSystemSound')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineSettingsError extends StatelessWidget {
  const _InlineSettingsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(
              onPressed: onRetry,
              child: Text(context.text('tryAgain')),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationAdvancedDetails extends StatelessWidget {
  const _NotificationAdvancedDetails({required this.status});

  final NotificationPlatformStatus? status;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(context.text('notificationDetails')),
      subtitle: Text(context.text('notificationDetailsHelp')),
      children: [
        _NotificationStatusRow(
          label: context.text('channelId'),
          value: status?.channelId ?? context.text('notAvailable'),
          icon: Icons.tag_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('selectedSound'),
          value: status?.selectedSound ?? context.text('notAvailable'),
          icon: Icons.music_note_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('soundAssetExists'),
          value: status?.soundAssetExists == true
              ? context.text('yes')
              : context.text('no'),
          icon: Icons.library_music_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('channelSoundEnabled'),
          value: status?.channelSoundEnabled == true
              ? context.text('yes')
              : context.text('no'),
          icon: Icons.volume_up_outlined,
        ),
        _NotificationStatusRow(
          label: context.text('vibrationEnabled'),
          value: status?.vibrationEnabled == true
              ? context.text('yes')
              : context.text('no'),
          icon: Icons.vibration_outlined,
        ),
      ],
    );
  }
}

String _formatPlatformDateTime(BuildContext context, DateTime? value) {
  if (value == null) return context.text('none');
  return AppServices.of(
    context,
  ).timeZoneService.formatTaskDateTime(context, value.toUtc());
}

class _HealthSettingsGroup extends StatelessWidget {
  const _HealthSettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).healthDataService;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final connected = service.healthConnectStatus.hasConnection;
        final canRequest = _canRequestHealthPermissions(
          service.healthConnectStatus,
        );
        final summary = service.summary;
        return _SettingsGroup(
          title: context.text('healthAndActivity'),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text(context.text('healthConnect')),
              subtitle: Text(
                _healthStatusText(context, service.healthConnectStatus),
              ),
              trailing: connected
                  ? AppButton.text(
                      onPressed: service.readLatestSummary,
                      label: Text(context.text('refresh')),
                    )
                  : canRequest
                  ? AppButton.filled(
                      onPressed: service.loading
                          ? null
                          : () => _requestHealthPermissions(context),
                      label: Text(context.text('connect')),
                    )
                  : null,
            ),
            if (connected) ...[
              const Divider(),
              if (service.grantedTypes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${context.text('grantedHealthData')}: '
                    '${service.grantedTypes.map((type) => context.text('healthType_$type')).join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (summary != null)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _HealthMetric(
                      label: context.text('steps'),
                      value: '${summary.steps}',
                    ),
                    _HealthMetric(
                      label: context.text('activeMinutes'),
                      value: '${summary.activeMinutes} min',
                    ),
                    _HealthMetric(
                      label: context.text('exercise'),
                      value: '${summary.exerciseMinutes} min',
                    ),
                    _HealthMetric(
                      label: context.text('distance'),
                      value:
                          '${summary.distanceKilometers.toStringAsFixed(1)} km',
                    ),
                    if (summary.lastSleepMinutes != null)
                      _HealthMetric(
                        label: context.text('lastSleep'),
                        value: _formatHealthMinutes(summary.lastSleepMinutes!),
                      ),
                    if (summary.latestHeartRate != null)
                      _HealthMetric(
                        label: context.text('latestHeartRate'),
                        value: '${summary.latestHeartRate} bpm',
                      ),
                    _HealthMetric(
                      label: context.text('lastSuccessfulRead'),
                      value: _formatPlatformDateTime(
                        context,
                        summary.lastReadAt,
                      ),
                    ),
                  ],
                ),
              if (summary == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(context.text('healthNoRecordsYet')),
                ),
              _HealthSourcesSummary(summary: summary),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton.outlined(
                    onPressed: service.readLatestSummary,
                    label: Text(context.text('refreshNow')),
                  ),
                  AppButton.outlined(
                    onPressed: service.openAccessManagement,
                    label: Text(context.text('managePermissions')),
                  ),
                  AppButton.text(
                    onPressed: service.disconnectHealthConnect,
                    label: Text(context.text('disconnect')),
                  ),
                ],
              ),
            ],
            AppSwitchListTile(
              value: config.healthDataLocalOnly,
              title: Text(context.text('keepHealthDataLocal')),
              onChanged: (value) => AppServices.of(
                context,
              ).updateConfig(config.copyWith(healthDataLocalOnly: value)),
            ),
            if (service.error != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline),
                title: Text(context.text('healthReadFailed')),
                subtitle: Text(service.error!),
              ),
            _HealthDiagnostics(service: service),
          ],
        );
      },
    );
  }

  Future<void> _requestHealthPermissions(BuildContext context) async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) => const _HealthPermissionDialog(),
    );
    if (selected == null || selected.isEmpty || !context.mounted) return;
    await AppServices.of(
      context,
    ).healthDataService.connectHealthConnect(selected);
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _HealthSourcesSummary extends StatelessWidget {
  const _HealthSourcesSummary({required this.summary});

  final HealthDataSummary? summary;

  @override
  Widget build(BuildContext context) {
    final sources = summary?.dataSources.toList() ?? const <String>[];
    sources.sort();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.hub_outlined),
              title: Text(context.text('healthSources')),
              subtitle: Text(
                sources.isEmpty
                    ? context.text('healthSourcesEmpty')
                    : context.text('healthSourcesDetected'),
              ),
            ),
            if (sources.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final source in sources)
                    Chip(
                      avatar: const Icon(Icons.watch_outlined, size: 18),
                      label: Text(
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              )
            else
              Text(
                context.text('healthSourcesEmptyHelp'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

bool _canRequestHealthPermissions(HealthProviderStatus status) {
  return switch (status) {
    HealthProviderStatus.available ||
    HealthProviderStatus.notConnected ||
    HealthProviderStatus.permissionDeclined ||
    HealthProviderStatus.permissionRevoked ||
    HealthProviderStatus.readFailed => true,
    HealthProviderStatus.unsupported ||
    HealthProviderStatus.unavailable ||
    HealthProviderStatus.updateRequired ||
    HealthProviderStatus.permissionRequestInProgress ||
    HealthProviderStatus.partiallyConnected ||
    HealthProviderStatus.connected ||
    HealthProviderStatus.connectedNoRecords ||
    HealthProviderStatus.connectedDataAvailable => false,
  };
}

String _healthStatusText(BuildContext context, HealthProviderStatus status) {
  return switch (status) {
    HealthProviderStatus.connectedDataAvailable => context.text('connected'),
    HealthProviderStatus.connectedNoRecords => context.text(
      'healthConnectedNoRecords',
    ),
    HealthProviderStatus.connected => context.text('connected'),
    HealthProviderStatus.permissionRequestInProgress => context.text(
      'healthPermissionInProgress',
    ),
    HealthProviderStatus.permissionDeclined => context.text(
      'healthPermissionDeclined',
    ),
    HealthProviderStatus.permissionRevoked => context.text(
      'healthPermissionRevoked',
    ),
    HealthProviderStatus.partiallyConnected => context.text(
      'healthPartiallyConnected',
    ),
    HealthProviderStatus.readFailed => context.text('healthReadFailed'),
    HealthProviderStatus.unavailable => context.text('healthUnavailable'),
    HealthProviderStatus.updateRequired => context.text('healthUpdateRequired'),
    HealthProviderStatus.available => context.text('healthAvailable'),
    HealthProviderStatus.notConnected => context.text('notConnected'),
    HealthProviderStatus.unsupported => context.text('healthUnsupported'),
  };
}

class _HealthDiagnostics extends StatelessWidget {
  const _HealthDiagnostics({required this.service});

  final HealthDataService service;

  @override
  Widget build(BuildContext context) {
    final requested = _joinHealthValues(context, service.requestedTypes);
    final granted = _joinHealthValues(context, service.grantedTypes);
    final permissions = service.grantedPermissions.isEmpty
        ? context.text('none')
        : service.grantedPermissions.join('\n');
    final manifest = service.manifestDeclaredPermissions.isEmpty
        ? context.text('none')
        : service.manifestDeclaredPermissions.join('\n');
    final sources = service.summary?.dataSources.isEmpty ?? true
        ? context.text('none')
        : service.summary!.dataSources.join(', ');

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(context.text('healthDiagnostics')),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        _HealthDiagnosticRow(
          label: context.text('requestedHealthData'),
          value: requested,
        ),
        _HealthDiagnosticRow(
          label: context.text('grantedHealthData'),
          value: granted,
        ),
        _HealthDiagnosticRow(
          label: context.text('grantedHealthPermissions'),
          value: permissions,
        ),
        _HealthDiagnosticRow(
          label: context.text('manifestDeclaredPermissions'),
          value: manifest,
        ),
        _HealthDiagnosticRow(
          label: context.text('lastPermissionResult'),
          value: service.lastPermissionResult ?? context.text('none'),
        ),
        _HealthDiagnosticRow(
          label: context.text('lastReadAttempt'),
          value: service.lastReadAttempt ?? context.text('none'),
        ),
        _HealthDiagnosticRow(
          label: context.text('recordsFound'),
          value: '${service.lastRecordCount}',
        ),
        _HealthDiagnosticRow(
          label: context.text('dataSources'),
          value: sources,
        ),
      ],
    );
  }
}

class _HealthDiagnosticRow extends StatelessWidget {
  const _HealthDiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }
}

String _joinHealthValues(BuildContext context, Set<String> values) {
  if (values.isEmpty) return context.text('none');
  return values.map((value) => context.text('healthType_$value')).join(', ');
}

class _HealthPermissionDialog extends StatefulWidget {
  const _HealthPermissionDialog();

  @override
  State<_HealthPermissionDialog> createState() =>
      _HealthPermissionDialogState();
}

class _HealthPermissionDialogState extends State<_HealthPermissionDialog> {
  final Set<String> _selected = {
    'steps',
    'exercise',
    'distance',
    'heart_rate',
    'sleep',
    'calories',
  };

  @override
  Widget build(BuildContext context) {
    const types = [
      'steps',
      'exercise',
      'distance',
      'heart_rate',
      'sleep',
      'calories',
    ];
    return AlertDialog(
      title: Text(context.text('healthPermissionTitle')),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final type in types)
              CheckboxListTile(
                value: _selected.contains(type),
                title: Text(context.text('healthType_$type')),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(type);
                  } else {
                    _selected.remove(type);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        AppButton.text(
          onPressed: () => Navigator.pop(context),
          label: Text(context.text('cancel')),
        ),
        AppButton.filled(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, Set<String>.of(_selected)),
          label: Text(context.text('continueButton')),
        ),
      ],
    );
  }
}

String _formatHealthMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

class _TaskBrowserHidden extends StatefulWidget {
  const _TaskBrowserHidden({required this.child});

  final Widget child;

  @override
  State<_TaskBrowserHidden> createState() => _TaskBrowserHiddenState();
}

class _TaskBrowserHiddenState extends State<_TaskBrowserHidden> {
  @override
  void initState() {
    super.initState();
    unawaited(TaskBrowserSurfaceController.destroyAll());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CycleWellbeingSettingsGroup extends StatefulWidget {
  const _CycleWellbeingSettingsGroup({this.onOpenProfile});

  final VoidCallback? onOpenProfile;

  @override
  State<_CycleWellbeingSettingsGroup> createState() =>
      _CycleWellbeingSettingsGroupState();
}

class _CycleWellbeingSettingsGroupState
    extends State<_CycleWellbeingSettingsGroup> {
  final _store = _CycleSettingsStore();
  CycleSettings _settings = const CycleSettings();
  bool _loaded = false;
  String? _loadedForUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AppServices.of(context).supabaseService.currentUser?.id;
    if (_loadedForUserId == userId) return;
    _loadedForUserId = userId;
    _loaded = false;
    unawaited(_load(userId));
  }

  Future<void> _load(String? userId) async {
    final service = AppServices.of(context).supabaseService;
    final loaded = await _store.load(
      userId: userId,
      client: service.clientOrNull,
      syncEnabled: service.profile?.cycleDataSyncEnabled == true,
    );
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _loaded = true;
    });
  }

  Future<void> _save(CycleSettings settings) async {
    final service = AppServices.of(context).supabaseService;
    final userId = service.currentUser?.id;
    setState(() => _settings = settings);
    await _store.save(
      settings,
      userId: userId,
      client: service.clientOrNull,
      syncEnabled: service.profile?.cycleDataSyncEnabled == true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = AppServices.of(context).supabaseService.profile;
    final enabled = profile?.cycleTrackingEnabled == true;
    final sexAllowsPrompt = profile?.sex == UserSex.female || enabled;
    final nextPeriod = _settings.estimatedNextPeriod;
    final tolerance = _settings.toleranceWindow;
    final hasCycleDates =
        _settings.lastPeriodStart != null || _settings.lastPeriodEnd != null;
    final today = DateTime.now();
    final inTolerance =
        tolerance != null &&
        !today.isBefore(tolerance.start) &&
        !today.isAfter(tolerance.end);

    return _SettingsGroup(
      title: context.text('cycleWellbeing'),
      children: [
        if (!sexAllowsPrompt)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(context.text('cycleTrackingOff')),
            subtitle: Text(context.text('cycleTrackingProfileHint')),
            trailing: widget.onOpenProfile == null
                ? null
                : TextButton(
                    onPressed: widget.onOpenProfile,
                    child: Text(context.text('openProfile')),
                  ),
          )
        else if (!enabled)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(context.text('cycleTrackingOff')),
            subtitle: Text(context.text('enableCycleTrackingHelp')),
            trailing: widget.onOpenProfile == null
                ? null
                : TextButton(
                    onPressed: widget.onOpenProfile,
                    child: Text(context.text('openProfile')),
                  ),
          )
        else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              inTolerance ? Icons.spa_outlined : Icons.calendar_month_outlined,
            ),
            title: Text(
              inTolerance
                  ? context.text('gentleWorkloadActive')
                  : hasCycleDates
                  ? context.text('cycleCalendarReady')
                  : context.text('lastPeriodStart'),
            ),
            subtitle: Text(
              inTolerance
                  ? context.text('gentleWorkloadActiveHelp')
                  : hasCycleDates
                  ? context.text('cycleCalendarHelp')
                  : context.text('enableCycleTrackingHelp'),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CyclePill(
                label: context.text('lastPeriodStart'),
                value: _formatCycleDate(context, _settings.lastPeriodStart),
                onTap: () => _pickDate(
                  context,
                  _settings.lastPeriodStart,
                  (date) => _save(_settings.copyWith(lastPeriodStart: date)),
                ),
              ),
              _CyclePill(
                label: context.text('periodEnd'),
                value: _formatCycleDate(context, _settings.lastPeriodEnd),
                onTap: () => _pickDate(
                  context,
                  _settings.lastPeriodEnd,
                  (date) => _save(_settings.copyWith(lastPeriodEnd: date)),
                ),
              ),
              _CyclePill(
                label: context.text('typicalCycleLength'),
                value: '${_settings.cycleLengthDays} ${context.text('days')}',
                onTap: () => _pickInteger(
                  context,
                  title: context.text('typicalCycleLength'),
                  value: _settings.cycleLengthDays,
                  min: 18,
                  max: 45,
                  onChanged: (value) =>
                      _save(_settings.copyWith(cycleLengthDays: value)),
                ),
              ),
              _CyclePill(
                label: context.text('typicalPeriodLength'),
                value: '${_settings.periodLengthDays} ${context.text('days')}',
                onTap: () => _pickInteger(
                  context,
                  title: context.text('typicalPeriodLength'),
                  value: _settings.periodLengthDays,
                  min: 1,
                  max: 12,
                  onChanged: (value) =>
                      _save(_settings.copyWith(periodLengthDays: value)),
                ),
              ),
              if (nextPeriod != null)
                _CyclePill(
                  label: context.text('expectedNextPeriod'),
                  value: _formatCycleDate(context, nextPeriod),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AppSwitchListTile(
            value: _settings.reduceBeforePeriod,
            title: Text(context.text('reduceWorkloadBeforePeriod')),
            subtitle: Text(context.text('reduceWorkloadBeforePeriodHelp')),
            onChanged: _loaded
                ? (value) =>
                      _save(_settings.copyWith(reduceBeforePeriod: value))
                : null,
          ),
          AppSwitchListTile(
            value: _settings.reduceFirstDays,
            title: Text(context.text('reduceWorkloadFirstCycleDays')),
            subtitle: Text(context.text('reduceWorkloadFirstCycleDaysHelp')),
            onChanged: _loaded
                ? (value) => _save(_settings.copyWith(reduceFirstDays: value))
                : null,
          ),
          AppSwitchListTile(
            value: _settings.gentleCoaching,
            title: Text(context.text('gentleCycleCoaching')),
            subtitle: Text(context.text('gentleCycleCoachingHelp')),
            onChanged: _loaded
                ? (value) => _save(_settings.copyWith(gentleCoaching: value))
                : null,
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    DateTime? current,
    ValueChanged<DateTime> onChanged,
  ) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (selected != null) onChanged(selected);
  }

  Future<void> _pickInteger(
    BuildContext context, {
    required String title,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) async {
    var selected = value;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$selected ${context.text('days')}'),
              Slider(
                value: selected.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                label: '$selected',
                onChanged: (value) =>
                    setDialogState(() => selected = value.round()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: Text(context.text('saveChanges')),
          ),
        ],
      ),
    );
    if (result != null) onChanged(result);
  }
}

class _CyclePill extends StatelessWidget {
  const _CyclePill({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.event_outlined, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text('$label: $value', overflow: TextOverflow.ellipsis),
      ),
      onPressed: onTap,
    );
  }
}

String _formatCycleDate(BuildContext context, DateTime? date) {
  if (date == null) return context.text('notSet');
  return MaterialLocalizations.of(context).formatMediumDate(date);
}

class CycleSettings {
  const CycleSettings({
    this.lastPeriodStart,
    this.lastPeriodEnd,
    this.cycleLengthDays = 28,
    this.periodLengthDays = 5,
    this.reduceBeforePeriod = true,
    this.reduceFirstDays = true,
    this.gentleCoaching = true,
  });

  final DateTime? lastPeriodStart;
  final DateTime? lastPeriodEnd;
  final int cycleLengthDays;
  final int periodLengthDays;
  final bool reduceBeforePeriod;
  final bool reduceFirstDays;
  final bool gentleCoaching;

  DateTime? get estimatedNextPeriod =>
      lastPeriodStart?.add(Duration(days: cycleLengthDays));

  DateTimeRange? get toleranceWindow {
    final next = estimatedNextPeriod;
    if (next == null) return null;
    final start = reduceBeforePeriod
        ? next.subtract(const Duration(days: 2))
        : next;
    final end = reduceFirstDays
        ? next.add(Duration(days: (periodLengthDays - 1).clamp(0, 12)))
        : next;
    return DateTimeRange(start: start, end: end);
  }

  CycleSettings copyWith({
    DateTime? lastPeriodStart,
    DateTime? lastPeriodEnd,
    int? cycleLengthDays,
    int? periodLengthDays,
    bool? reduceBeforePeriod,
    bool? reduceFirstDays,
    bool? gentleCoaching,
  }) {
    return CycleSettings(
      lastPeriodStart: lastPeriodStart ?? this.lastPeriodStart,
      lastPeriodEnd: lastPeriodEnd ?? this.lastPeriodEnd,
      cycleLengthDays: cycleLengthDays ?? this.cycleLengthDays,
      periodLengthDays: periodLengthDays ?? this.periodLengthDays,
      reduceBeforePeriod: reduceBeforePeriod ?? this.reduceBeforePeriod,
      reduceFirstDays: reduceFirstDays ?? this.reduceFirstDays,
      gentleCoaching: gentleCoaching ?? this.gentleCoaching,
    );
  }

  factory CycleSettings.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        DateTime.tryParse(json[key]?.toString() ?? '');
    return CycleSettings(
      lastPeriodStart: date('lastPeriodStart'),
      lastPeriodEnd: date('lastPeriodEnd'),
      cycleLengthDays: (json['cycleLengthDays'] as num?)?.round() ?? 28,
      periodLengthDays: (json['periodLengthDays'] as num?)?.round() ?? 5,
      reduceBeforePeriod: json['reduceBeforePeriod'] as bool? ?? true,
      reduceFirstDays: json['reduceFirstDays'] as bool? ?? true,
      gentleCoaching: json['gentleCoaching'] as bool? ?? true,
    );
  }

  factory CycleSettings.fromRemote(Map<String, dynamic> row) {
    DateTime? date(String key) => DateTime.tryParse(row[key]?.toString() ?? '');
    return CycleSettings(
      lastPeriodStart: date('last_period_start'),
      lastPeriodEnd: date('last_period_end'),
      cycleLengthDays: (row['cycle_length_days'] as num?)?.round() ?? 28,
      periodLengthDays: (row['period_length_days'] as num?)?.round() ?? 5,
      reduceBeforePeriod: row['reduce_before_period'] as bool? ?? true,
      reduceFirstDays: row['reduce_first_days'] as bool? ?? true,
      gentleCoaching: row['gentle_coaching'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'lastPeriodStart': lastPeriodStart?.toIso8601String(),
    'lastPeriodEnd': lastPeriodEnd?.toIso8601String(),
    'cycleLengthDays': cycleLengthDays,
    'periodLengthDays': periodLengthDays,
    'reduceBeforePeriod': reduceBeforePeriod,
    'reduceFirstDays': reduceFirstDays,
    'gentleCoaching': gentleCoaching,
  };

  Map<String, Object?> toRemoteJson(String userId) => {
    'user_id': userId,
    'last_period_start': _dateOnly(lastPeriodStart),
    'last_period_end': _dateOnly(lastPeriodEnd),
    'cycle_length_days': cycleLengthDays,
    'period_length_days': periodLengthDays,
    'reduce_before_period': reduceBeforePeriod,
    'reduce_first_days': reduceFirstDays,
    'gentle_coaching': gentleCoaching,
  };

  static String? _dateOnly(DateTime? value) {
    if (value == null) return null;
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

class _CycleSettingsStore {
  Future<CycleSettings> load({
    required String? userId,
    required SupabaseClient? client,
    required bool syncEnabled,
  }) async {
    if (syncEnabled && client != null && userId != null) {
      try {
        final row = await client
            .from('cycle_preferences')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        if (row != null) {
          return CycleSettings.fromRemote(Map<String, dynamic>.from(row));
        }
      } on Object {
        // Fall back to the per-user local cache while offline or migrating.
      }
    }
    try {
      final file = await _file(userId);
      if (!await file.exists()) return const CycleSettings();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return CycleSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return CycleSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on Object {
      return const CycleSettings();
    }
    return const CycleSettings();
  }

  Future<void> save(
    CycleSettings settings, {
    required String? userId,
    required SupabaseClient? client,
    required bool syncEnabled,
  }) async {
    final file = await _file(userId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(settings.toJson()));
    if (!syncEnabled || client == null || userId == null) return;
    try {
      await client
          .from('cycle_preferences')
          .upsert(settings.toRemoteJson(userId), onConflict: 'user_id');
    } on Object {
      // The local copy is authoritative until the next edit after reconnect.
    }
  }

  Future<File> _file(String? userId) async {
    final base = Platform.isWindows
        ? (Platform.environment['APPDATA'] ?? Directory.systemTemp.path)
        : Directory.systemTemp.path;
    final owner = (userId == null || userId.isEmpty)
        ? 'local'
        : userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File(
      '$base${Platform.pathSeparator}TaskMasterPro'
      '${Platform.pathSeparator}cycle'
      '${Platform.pathSeparator}$owner.json',
    );
  }
}

class _SoundsSettingsGroup extends StatelessWidget {
  const _SoundsSettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return _SettingsGroup(
      title: context.text('soundsFeedback'),
      children: [
        AppSwitchListTile(
          value: config.uiClickSounds,
          title: Text(context.text('uiClickSounds')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(uiClickSounds: value));
          },
        ),
        Slider(
          value: config.uiClickVolume,
          onChanged: config.uiClickSounds
              ? (value) {
                  services.updateConfig(config.copyWith(uiClickVolume: value));
                }
              : null,
        ),
        AppButton.outlined(
          onPressed: config.uiClickSounds
              ? services.feedbackService.playUiClick
              : null,
          icon: const Icon(Icons.volume_up_outlined),
          label: Text(context.text('previewSound')),
        ),
        AppSwitchListTile(
          value: config.notificationSounds,
          title: Text(context.text('notificationSounds')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(notificationSounds: value));
          },
        ),
        AppSwitchListTile(
          value: config.pomodoroSounds,
          title: Text(context.text('pomodoroSounds')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(pomodoroSounds: value));
          },
        ),
        AppSwitchListTile(
          value: config.completionSounds,
          title: Text(context.text('completionSounds')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(completionSounds: value));
          },
        ),
        AppSwitchListTile(
          value: config.errorSounds,
          title: Text(context.text('errorSounds')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(errorSounds: value));
          },
        ),
        AppSwitchListTile(
          value: config.hapticFeedback,
          title: Text(context.text('hapticFeedback')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(hapticFeedback: value));
          },
        ),
        AppButton.text(
          onPressed: () {
            services.updateConfig(
              config.copyWith(
                uiClickSounds: true,
                uiClickVolume: 0.65,
                notificationSounds: true,
                pomodoroSounds: true,
                completionSounds: true,
                errorSounds: true,
                hapticFeedback: true,
              ),
            );
          },
          icon: const Icon(Icons.restore_outlined),
          label: Text(context.text('restoreSoundDefaults')),
        ),
      ],
    );
  }
}

class _BrowserPrivacySettingsGroup extends StatelessWidget {
  const _BrowserPrivacySettingsGroup({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return _SettingsGroup(
      title: context.text('browserPrivacy'),
      children: [
        AppSwitchListTile(
          value: config.saveCookiesAndSessions,
          title: Text(context.text('saveCookiesSessions')),
          onChanged: (value) {
            services.updateConfig(
              config.copyWith(saveCookiesAndSessions: value),
            );
          },
        ),
        AppSwitchListTile(
          value: config.formAutofill,
          title: Text(context.text('generalFormAutofill')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(formAutofill: value));
          },
        ),
        AppSwitchListTile(
          value: config.passwordAutofill,
          title: Text(context.text('passwordAutofill')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(passwordAutofill: value));
          },
        ),
        AppSwitchListTile(
          value: config.saveWebsitePasswords,
          title: Text(context.text('saveWebsitePasswords')),
          subtitle: Text(context.text('passwordStorageSafety')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(saveWebsitePasswords: value));
          },
        ),
        AppSwitchListTile(
          value: config.syncBrowserTabsAndUrls,
          title: Text(context.text('syncBrowserTabsUrls')),
          subtitle: Text(context.text('urlSyncPrivacy')),
          onChanged: (value) {
            services.updateConfig(
              config.copyWith(syncBrowserTabsAndUrls: value),
            );
          },
        ),
        const Divider(),
        Text(
          context.text('browserActivityPrivacy'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: config.defaultSearchEngine,
          decoration: InputDecoration(
            labelText: context.text('defaultSearchEngine'),
          ),
          items: [
            for (final engine in const [
              'google',
              'bing',
              'duckduckgo',
              'custom',
            ])
              DropdownMenuItem(
                value: engine,
                child: Text(context.text('searchEngine_$engine')),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              services.updateConfig(
                config.copyWith(defaultSearchEngine: value),
              );
            }
          },
        ),
        if (config.defaultSearchEngine == 'custom') ...[
          const SizedBox(height: 8),
          _SettingTextField(
            label: context.text('customSearchUrl'),
            value: config.customSearchUrl,
            onChanged: (value) {
              services.updateConfig(config.copyWith(customSearchUrl: value));
            },
          ),
        ],
        AppSwitchListTile(
          value: config.trackBrowserActivity,
          title: Text(context.text('trackBrowserActivity')),
          subtitle: Text(context.text('trackBrowserActivityHelp')),
          onChanged: (value) {
            services.updateConfig(config.copyWith(trackBrowserActivity: value));
          },
        ),
        AppSwitchListTile(
          value: config.trackFullUrls,
          title: Text(context.text('trackFullUrls')),
          onChanged: config.trackBrowserActivity
              ? (value) {
                  services.updateConfig(config.copyWith(trackFullUrls: value));
                }
              : null,
        ),
        AppSwitchListTile(
          value: config.trackPageTitles,
          title: Text(context.text('trackPageTitles')),
          onChanged: config.trackBrowserActivity
              ? (value) {
                  services.updateConfig(
                    config.copyWith(trackPageTitles: value),
                  );
                }
              : null,
        ),
        AppSwitchListTile(
          value: config.trackSearchQueries,
          title: Text(context.text('trackSearchQueries')),
          onChanged: config.trackBrowserActivity
              ? (value) {
                  services.updateConfig(
                    config.copyWith(trackSearchQueries: value),
                  );
                }
              : null,
        ),
        AppSwitchListTile(
          value: config.trackExternalApplications,
          title: Text(context.text('trackExternalApplications')),
          onChanged: (value) {
            services.updateConfig(
              config.copyWith(trackExternalApplications: value),
            );
          },
        ),
        AppSwitchListTile(
          value: config.pauseTrackingInPrivateMode,
          title: Text(context.text('pauseTrackingInPrivateMode')),
          onChanged: (value) {
            services.updateConfig(
              config.copyWith(pauseTrackingInPrivateMode: value),
            );
          },
        ),
        _SettingTextField(
          label: context.text('excludedDomains'),
          value: config.excludedActivityDomains.join(', '),
          onChanged: (value) {
            services.updateConfig(
              config.copyWith(
                excludedActivityDomains: _commaSeparatedValues(value),
              ),
            );
          },
        ),
        _SettingTextField(
          label: context.text('excludedApplications'),
          value: config.excludedActivityApplications.join(', '),
          onChanged: (value) {
            services.updateConfig(
              config.copyWith(
                excludedActivityApplications: _commaSeparatedValues(value),
              ),
            );
          },
        ),
        const Divider(),
        AppButton.outlined(
          onPressed: () => _confirmClearBrowserData(context),
          icon: const Icon(Icons.cleaning_services_outlined),
          label: Text(context.text('clearBrowsingData')),
        ),
      ],
    );
  }

  Future<void> _confirmClearBrowserData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.text('clearBrowsingData')),
        content: Text(context.text('clearBrowsingDataWarning')),
        actions: [
          AppButton.text(
            onPressed: () => Navigator.of(context).pop(false),
            label: Text(context.text('cancel')),
          ),
          AppButton.filled(
            onPressed: () => Navigator.of(context).pop(true),
            label: Text(context.text('clearBrowsingData')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _deleteLocalBrowserData();
    if (!context.mounted) {
      return;
    }
    AppServices.of(
      context,
    ).notificationService.showSuccess(context.text('browserDataCleared'));
  }

  Future<void> _deleteLocalBrowserData() async {
    if (!Platform.isWindows) {
      return;
    }
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.isEmpty) {
      return;
    }
    final roots = [
      Directory(
        '$base${Platform.pathSeparator}TaskMasterPro'
        '${Platform.pathSeparator}BrowserData',
      ),
      Directory(
        '$base${Platform.pathSeparator}TaskMaster Pro'
        '${Platform.pathSeparator}Browser',
      ),
    ];
    for (final root in roots) {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  }
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _deleting = false;
  String? _status;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  bool get _confirmationValid =>
      _confirmationController.text.trim() == 'DELETE MY ACCOUNT';

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.text('deleteAccount'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SettingsGroup(
              title: context.text('dangerZone'),
              children: [
                Text(context.text('deleteAccountConsequences')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in const [
                      'tasks',
                      'projects',
                      'sessions',
                      'calendar',
                      'notes',
                      'interruptions',
                      'roadmap',
                      'settings',
                    ])
                      Chip(label: Text(context.text(key))),
                  ],
                ),
                const SizedBox(height: 12),
                AppButton.outlined(
                  onPressed: _deleting
                      ? null
                      : () => _exportBeforeDeletion(context),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(context.text('exportMyDataBeforeDeletion')),
                ),
              ],
            ),
            _SettingsGroup(
              title: context.text('verifyIdentity'),
              children: [
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.text('password'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(context.text('typeDeleteMyAccount')),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmationController,
                  decoration: const InputDecoration(
                    labelText: 'DELETE MY ACCOUNT',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            _SettingsGroup(
              title: context.text('finalWarning'),
              children: [
                Text(context.text('deleteRecoveryPeriodWarning')),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _status!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                AppButton.filled(
                  onPressed: _deleting || !_confirmationValid
                      ? null
                      : () => _deleteAccount(context),
                  icon: _deleting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_forever_outlined),
                  label: Text(context.text('deleteMyAccount')),
                ),
                const SizedBox(height: 8),
                AppButton.text(
                  onPressed: _deleting
                      ? null
                      : () => Navigator.of(context).pop(),
                  label: Text(context.text('cancel')),
                ),
              ],
            ),
            if (services.supabaseService.profile?.isOwner ?? false)
              _SettingsGroup(
                title: context.text('ownerProtection'),
                children: [Text(context.text('ownerDeletionProtection'))],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBeforeDeletion(BuildContext context) async {
    final settings = SettingsScreen();
    await settings._exportMyData(context);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    setState(() {
      _deleting = true;
      _status = null;
    });
    final error = await AppServices.of(context).supabaseService
        .requestAccountDeletion(
          password: _passwordController.text,
          confirmation: _confirmationController.text,
        );
    if (!mounted || !context.mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _deleting = false;
      _status = error;
    });
  }
}

class BackendAdministrationScreen extends StatefulWidget {
  const BackendAdministrationScreen({super.key});

  @override
  State<BackendAdministrationScreen> createState() =>
      _BackendAdministrationScreenState();
}

class _BackendAdministrationScreenState
    extends State<BackendAdministrationScreen> {
  late Future<Map<String, dynamic>> _diagnostics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _diagnostics = AppServices.of(context).supabaseService.backendDiagnostics();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.text('backendSupabase'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SettingsGroup(
              title: context.text('backendStatus'),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text(context.text('serverConnected')),
                  subtitle: Text(
                    AppEnvironment.projectRef.isEmpty
                        ? AppEnvironment.environmentName
                        : '${AppEnvironment.environmentName} / ${AppEnvironment.projectRef}',
                  ),
                ),
                AppButton.outlined(
                  onPressed: () {
                    setState(() {
                      _diagnostics = services.supabaseService
                          .backendDiagnostics();
                    });
                  },
                  icon: const Icon(Icons.network_check_outlined),
                  label: Text(context.text('runConnectionTest')),
                ),
              ],
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: _diagnostics,
              builder: (context, snapshot) {
                final data = snapshot.data ?? const <String, dynamic>{};
                return _SettingsGroup(
                  title: context.text('diagnostics'),
                  children: [
                    for (final entry in data.entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.key),
                        subtitle: Text(_redact(entry.value)),
                      ),
                    if (!snapshot.hasData)
                      const Center(child: CircularProgressIndicator()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _redact(Object? value) {
    final text = value?.toString() ?? '';
    if (text.length > 80) {
      return '${text.substring(0, 30)}...${text.substring(text.length - 10)}';
    }
    return text;
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.compact = false,
  });

  final String title;
  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 18),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: compact ? 8 : 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingTextField extends StatelessWidget {
  const _SettingTextField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    );
  }
}

class _SettingTimeField extends StatelessWidget {
  const _SettingTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('time-field-$label-$value'),
      readOnly: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: const Icon(Icons.schedule_outlined),
      ),
      onTap: () => _pickTime(context),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final initial = _timeOfDayFromStorage(value);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    onChanged(_formatTimeStorage(picked));
  }
}

class _WeeklyReviewTimeField extends StatelessWidget {
  const _WeeklyReviewTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('weekly-review-$value'),
      readOnly: true,
      initialValue: _localizedWeeklyValue(context),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: const Icon(Icons.event_outlined),
      ),
      onTap: () => _pick(context),
    );
  }

  String _localizedWeeklyValue(BuildContext context) {
    final parsed = _parseWeeklyReview(value);
    final day = _dayOptions
        .where((option) => option.value == parsed.day)
        .firstOrNull;
    final dayText = day == null ? parsed.dayName : context.text(day.labelKey);
    return '$dayText ${_formatTimeStorage(parsed.time)}';
  }

  Future<void> _pick(BuildContext context) async {
    final parsed = _parseWeeklyReview(value);
    final day = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final option in _dayOptions)
              RadioListTile<int>(
                value: option.value,
                groupValue: parsed.day,
                title: Text(context.text(option.labelKey)),
                onChanged: (value) => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: parsed.time,
    );
    if (time == null) return;
    final dayName = _dayNameStorage(day);
    onChanged('$dayName ${_formatTimeStorage(time)}');
  }
}

class _SettingNumberField extends StatelessWidget {
  const _SettingNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('number-field-$label-$value'),
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (value) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          onChanged(parsed);
        }
      },
    );
  }
}

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveGrid(children: children);
  }
}

class _NumberGrid extends StatelessWidget {
  const _NumberGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveGrid(children: children);
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 4
            : width >= 760
            ? 3
            : width >= 520
            ? 2
            : 1;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children)
              SizedBox(
                width: columns == 1
                    ? width
                    : (width - (10 * (columns - 1))) / columns,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _DayOption {
  const _DayOption(this.value, this.labelKey);

  final int value;
  final String labelKey;
}

const _dayOptions = [
  _DayOption(1, 'monday'),
  _DayOption(2, 'tuesday'),
  _DayOption(3, 'wednesday'),
  _DayOption(4, 'thursday'),
  _DayOption(5, 'friday'),
  _DayOption(6, 'saturday'),
  _DayOption(7, 'sunday'),
];

int _sleepMinutes(AppConfig config) {
  final start = _minutesFromTime(config.bedtime);
  final end = _minutesFromTime(config.wakeUpTime);
  if (start == null || end == null) {
    return 999;
  }
  return end >= start ? end - start : (24 * 60 - start) + end;
}

List<String> _commaSeparatedValues(String value) {
  return value
      .split(',')
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

int? _minutesFromTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  return hour * 60 + minute;
}

TimeOfDay _timeOfDayFromStorage(String value) {
  final parts = value.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
  return TimeOfDay(
    hour: (hour ?? 9).clamp(0, 23),
    minute: (minute ?? 0).clamp(0, 59),
  );
}

String _formatTimeStorage(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

({int day, String dayName, TimeOfDay time}) _parseWeeklyReview(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  final dayName = parts.isNotEmpty ? parts.first : 'Friday';
  final day = switch (dayName.toLowerCase()) {
    'monday' => 1,
    'tuesday' => 2,
    'wednesday' => 3,
    'thursday' => 4,
    'friday' => 5,
    'saturday' => 6,
    'sunday' => 7,
    _ => 5,
  };
  final time = parts.length > 1
      ? _timeOfDayFromStorage(parts[1])
      : const TimeOfDay(hour: 7, minute: 0);
  return (day: day, dayName: dayName, time: time);
}

String _dayNameStorage(int day) {
  return switch (day) {
    1 => 'Monday',
    2 => 'Tuesday',
    3 => 'Wednesday',
    4 => 'Thursday',
    5 => 'Friday',
    6 => 'Saturday',
    7 => 'Sunday',
    _ => 'Friday',
  };
}
