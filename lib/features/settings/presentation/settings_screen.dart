import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/account_export_service.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/database/app_database.dart';
import '../../../core/learning/application_system_learning.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/profile/profile_avatar.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';
import '../../../core/time/time_zone_service.dart';
import '../../../core/updates/app_update_service.dart';
import '../../../core/updates/update_prompt.dart';
import '../../calendar/presentation/planning_calendar_screen.dart';
import '../../account/presentation/account_deletion_screen.dart';
import '../../activity/presentation/activity_review_screen.dart';
import '../../health/presentation/health_connect_screen.dart';
import '../../health/presentation/windows_health_summary_screen.dart';
import '../../health/data/health_source_discovery.dart';
import '../../reports/presentation/performance_report_screen.dart';
import '../../sync/presentation/synchronization_panel.dart';
import '../../tasks/presentation/tasks_screen.dart';
import '../../tasks/presentation/standalone_pomodoro_screen.dart';
import '../../tasks/presentation/vacation_settings_screen.dart';
import '../../vault/presentation/password_vault_screen.dart';
import '../data/profile_media_service.dart';
import '../data/settings_section_catalog.dart';
import 'connected_devices_screen.dart';
import 'notifications_sounds_screen.dart';
import 'schedule_wellbeing_screen.dart';
import 'settings_section_directory.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({required this.user, super.key});

  final User user;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _preview = NotificationSoundPreview();
  final _notifications = localNotificationService;
  final _updates = AppUpdateService();
  bool _notificationReady = false;
  bool _checkingUpdate = false;
  bool _showAllSettings = false;
  String _version = '0.0.29';
  final _profileSectionKey = GlobalKey();
  final _appearanceSectionKey = GlobalKey();
  final _helpSectionKey = GlobalKey();
  final _aboutSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _notifications.initialize().then((_) {
      if (mounted) setState(() => _notificationReady = true);
    });
    _updates.currentVersion().then((value) {
      if (mounted) setState(() => _version = value);
    });
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _toggleDetailedActivitySync(bool enabled) async {
    if (enabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.text('detailed_activity_sync_question')),
          content: Text(context.l10n.text('detailed_activity_sync_warning')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('review_privacy_settings')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.text('enable_sync')),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    await ref
        .read(settingsRepositoryProvider)
        .updateAttributionSetting(detailedActivitySyncEnabled: enabled);
  }

  Future<void> _clearLocalActivity(String kind) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('clear_local_activity_question')),
        content: Text(context.l10n.text('clear_local_activity_explanation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = ref.read(activityRepositoryProvider);
    final count = switch (kind) {
      'unclassified' => await repository.clearUnclassifiedLocalActivity(),
      'system' => await repository.clearSystemLocalActivity(),
      _ => await repository.clearAllLocalActivityDetails(),
    };
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.format('local_activity_cleared', {'count': count}),
        ),
      ),
    );
  }

  Future<void> _exportLocalActivity() async {
    final dialogTitle = context.l10n.text('export_local_activity');
    final records = await ref
        .read(activityRepositoryProvider)
        .exportLocalActivity();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: 'taskmaster-local-activity.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path == null) return;
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'device_local_activity': records,
      }),
      flush: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('local_activity_exported'))),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final release = await _updates.checkForUpdate();
      if (!mounted) return;
      if (release == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.format('update_up_to_date', {'version': _version}),
            ),
          ),
        );
        return;
      }
      await showAppUpdateDialog(context, service: _updates, release: release);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('update_check_failed'))),
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _exportAccountData() async {
    try {
      final result = await AccountExportService(
        ref.read(databaseProvider),
        Supabase.instance.client,
      ).export();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.usedPicker
                ? context.l10n.text('account_export_success')
                : context.l10n.format('account_export_path', {
                    'path': result.path,
                  }),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('account_export_failed'))),
      );
    }
  }

  Future<void> _toggleApplicationTracking(bool enabled) async {
    if (!enabled || !Platform.isAndroid) {
      await ref
          .read(settingsRepositoryProvider)
          .updateTrackingSettings(applications: enabled);
      return;
    }
    final understood = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('usage_access_title')),
        content: Text(context.l10n.text('usage_access_description')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('not_now')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('usage_open_settings')),
          ),
        ],
      ),
    );
    if (understood != true) return;
    await ref.read(activityCaptureServiceProvider).openAndroidUsageAccess();
    await ref
        .read(settingsRepositoryProvider)
        .updateTrackingSettings(applications: true);
  }

  Future<void> _openSettingsSection(
    String key,
    LocalAppSetting settings,
    TaskMasterThemeKey themeKey,
  ) async {
    switch (settingsSectionDestination(key)) {
      case SettingsSectionDestination.scheduleAndWellbeing:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ScheduleWellbeingScreen(),
          ),
        );
      case SettingsSectionDestination.routineAndVacations:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const VacationSettingsScreen(),
          ),
        );
      case SettingsSectionDestination.coachingPreferences:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ScheduleWellbeingScreen(coachingOnly: true),
          ),
        );
      case SettingsSectionDestination.notificationsAndSounds:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationsSoundsScreen(),
          ),
        );
      case SettingsSectionDestination.health:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Platform.isAndroid
                ? const HealthConnectScreen()
                : const WindowsHealthSummaryScreen(),
          ),
        );
      case SettingsSectionDestination.vault:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PasswordVaultScreen()),
        );
      case SettingsSectionDestination.connectedDevices:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ConnectedDevicesScreen(),
          ),
        );
      case SettingsSectionDestination.categoryPage:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SettingsCategoryPage(
              categoryKey: key,
              user: widget.user,
              settings: settings,
              themeKey: themeKey,
              onToggleApplicationTracking: _toggleApplicationTracking,
              onExportAccountData: _exportAccountData,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final themeKey = TaskMasterThemeKey.fromKey(settings.themeKey);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              compact ? 16 : 24,
              compact ? 16 : 24,
              12,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                context.l10n.text('settings'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              8,
              compact ? 16 : 24,
              32,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                KeyedSubtree(
                  key: _profileSectionKey,
                  child: StreamBuilder(
                    stream: ref
                        .watch(settingsRepositoryProvider)
                        .watchProfile(widget.user.id),
                    builder: (context, snapshot) => _ProfileCard(
                      user: widget.user,
                      profile: snapshot.data,
                      themeKey: themeKey,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SettingsSectionDirectory(
                  onSelected: (key) =>
                      _openSettingsSection(key, settings, themeKey),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showAllSettings = !_showAllSettings),
                    icon: Icon(
                      _showAllSettings
                          ? Icons.unfold_less_outlined
                          : Icons.unfold_more_outlined,
                    ),
                    label: Text(
                      context.l10n.text(
                        _showAllSettings
                            ? 'hide_all_settings'
                            : 'show_all_settings',
                      ),
                    ),
                  ),
                ),
                if (_showAllSettings) ...[
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: context.l10n.text('profile_and_account'),
                    icon: Icons.manage_accounts_outlined,
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.logout,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(context.l10n.text('sign_out')),
                          onTap: () => Supabase.instance.client.auth.signOut(),
                        ),
                      ],
                    ),
                  ),
                  if (Platform.isWindows) ...[
                    const SizedBox(height: 16),
                    const _WindowsHealthSection(),
                  ],
                  const SizedBox(height: 16),
                  _SettingsSection(
                    key: _appearanceSectionKey,
                    title: context.l10n.text('appearance'),
                    icon: Icons.palette_outlined,
                    child: Column(
                      children: [
                        _ThemeSelector(selected: settings.themeKey),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final label = Text(
                              context.l10n.text('language'),
                              style: Theme.of(context).textTheme.titleSmall,
                            );
                            final selector = SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'en',
                                  label: Text(
                                    'EN',
                                  ), // localization-audit: allow
                                ),
                                ButtonSegment(
                                  value: 'ar',
                                  label: Text('ع'), // localization-audit: allow
                                ),
                                ButtonSegment(
                                  value: 'de',
                                  label: Text(
                                    'DE',
                                  ), // localization-audit: allow
                                ),
                              ],
                              selected: {settings.localeCode},
                              onSelectionChanged: (values) => ref
                                  .read(settingsRepositoryProvider)
                                  .updateLocale(values.first),
                            );
                            if (constraints.maxWidth < 420) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  label,
                                  const SizedBox(height: 8),
                                  selector,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: label),
                                const SizedBox(width: 12),
                                selector,
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        _TimeZoneSettings(settings: settings),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: context.l10n.text('schedule_wellbeing'),
                    icon: Icons.bedtime_outlined,
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_month_outlined),
                          title: Text(context.l10n.text('schedule_wellbeing')),
                          subtitle: Text(
                            context.l10n.text('schedule_wellbeing_description'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ScheduleWellbeingScreen(),
                            ),
                          ),
                        ),
                        const Divider(),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.cycleTrackingEnabled,
                          title: Text(context.l10n.text('cycle_optional')),
                          subtitle: Text(
                            context.l10n.text('cycle_optional_description'),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateCyclePreferences(enabled: value),
                        ),
                        if (settings.cycleTrackingEnabled) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: settings.cycleStorageMode,
                            decoration: InputDecoration(
                              labelText: context.l10n.text('cycle_storage'),
                              prefixIcon: const Icon(
                                Icons.enhanced_encryption_outlined,
                              ),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'local_only',
                                child: Text(
                                  context.l10n.text('cycle_local_only'),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'encrypted_sync',
                                child: Text(
                                  context.l10n.text('cycle_encrypted_sync'),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                ref
                                    .read(settingsRepositoryProvider)
                                    .updateCyclePreferences(storageMode: value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FilledButton.tonalIcon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      PlanningCalendarScreen(user: widget.user),
                                ),
                              ),
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text(
                                context.l10n.text('cycle_open_calendar'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: context.l10n.text('notifications'),
                    icon: Icons.notifications_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.tune_outlined),
                          title: Text(
                            context.l10n.text('notifications_and_sounds'),
                          ),
                          subtitle: Text(
                            context.l10n.text(
                              'notifications_and_sounds_description',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const NotificationsSoundsScreen(),
                            ),
                          ),
                        ),
                        const Divider(),
                        Text(
                          context.l10n.text('notification_sound'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child:
                                  DropdownButtonFormField<
                                    NotificationSoundChoice
                                  >(
                                    initialValue: NotificationSounds.byKey(
                                      settings.notificationSoundKey,
                                    ),
                                    items: [
                                      for (final choice
                                          in NotificationSounds.choices)
                                        DropdownMenuItem(
                                          value: choice,
                                          child: Row(
                                            children: [
                                              Icon(
                                                choice.key == 'system'
                                                    ? Icons.phone_android
                                                    : Icons.music_note,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                context.l10n.text(
                                                  'sound_${choice.key}',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                    onChanged: (choice) async {
                                      if (choice == null) return;
                                      await ref
                                          .read(settingsRepositoryProvider)
                                          .updateNotificationSound(choice.key);
                                      await _preview.play(choice);
                                    },
                                  ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.outlined(
                              tooltip: context.l10n.text('preview_sound'),
                              onPressed: () => _preview.play(
                                NotificationSounds.byKey(
                                  settings.notificationSoundKey,
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: context.l10n.text(
                                'send_test_notification',
                              ),
                              onPressed: !_notificationReady
                                  ? null
                                  : () async {
                                      await _notifications.requestPermission();
                                      await _notifications.showTest(
                                        NotificationSounds.byKey(
                                          settings.notificationSoundKey,
                                        ),
                                        localeCode: settings.localeCode,
                                      );
                                    },
                              icon: const Icon(Icons.notification_add_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.l10n.text('notification_sound_description'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (Platform.isAndroid &&
                            settings.notificationSoundKey == 'system') ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _notifications.openAndroidSystemSoundSettings(
                                    localeCode: settings.localeCode,
                                  ),
                              icon: const Icon(Icons.settings_outlined),
                              label: Text(
                                context.l10n.text('choose_android_sound'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: context.l10n.text('activity_and_privacy'),
                    icon: Icons.account_tree_outlined,
                    child: Column(
                      children: [
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.phonelink_lock_outlined),
                            title: Text(
                              context.l10n.text('activity_stays_on_device'),
                            ),
                            subtitle: Text(
                              context.l10n.text(
                                'activity_stays_on_device_description',
                              ),
                            ),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.applicationTrackingEnabled,
                          title: Text(
                            context.l10n.text(
                              Platform.isAndroid
                                  ? 'tracking_android_apps'
                                  : 'tracking_active_windows',
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.text(
                              Platform.isAndroid
                                  ? 'tracking_android_apps_description'
                                  : 'tracking_active_windows_description',
                            ),
                          ),
                          onChanged: _toggleApplicationTracking,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.windowTitleTrackingEnabled,
                          title: Text(
                            context.l10n.text('tracking_window_titles'),
                          ),
                          subtitle: Text(
                            context.l10n.text(
                              'tracking_window_titles_description',
                            ),
                          ),
                          onChanged: settings.applicationTrackingEnabled
                              ? (value) => ref
                                    .read(settingsRepositoryProvider)
                                    .updateTrackingSettings(windowTitles: value)
                              : null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.idleDetectionEnabled,
                          title: Text(context.l10n.text('tracking_inactive')),
                          subtitle: Text(
                            context.l10n.format(
                              'tracking_inactive_description',
                              {'seconds': settings.idleThresholdSeconds},
                            ),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateTrackingSettings(idleDetection: value),
                        ),
                        if (settings.idleDetectionEnabled)
                          Slider(
                            value: settings.idleThresholdSeconds
                                .clamp(15, 300)
                                .toDouble(),
                            min: 15,
                            max: 300,
                            divisions: 19,
                            label: '${settings.idleThresholdSeconds}s',
                            onChanged: (value) => ref
                                .read(settingsRepositoryProvider)
                                .updateTrackingSettings(
                                  idleThresholdSeconds: value.round(),
                                ),
                          ),
                        const Divider(),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.detectBreakActivity,
                          title: Text(
                            context.l10n.text('detect_break_activity'),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                detectBreakActivity: value,
                              ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.detectCrossTaskActivity,
                          title: Text(context.l10n.text('detect_cross_task')),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                detectCrossTaskActivity: value,
                              ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.automaticTrustedRules,
                          title: Text(
                            context.l10n.text('automatic_trusted_rules'),
                          ),
                          subtitle: Text(
                            context.l10n.text('tracking_rule_description'),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                automaticTrustedRules: value,
                              ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.retainUnclassifiedActivity,
                          title: Text(context.l10n.text('retain_unclassified')),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                retainUnclassifiedActivity: value,
                              ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.retainTechnicalIdle,
                          title: Text(context.l10n.text('retain_idle')),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                retainTechnicalIdle: value,
                              ),
                        ),
                        const Divider(),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.activitySyncEnabled,
                          title: Text(
                            context.l10n.text(
                              'synchronize_confirmed_contributions',
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.text(
                              'synchronize_confirmed_contributions_description',
                            ),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                activitySyncEnabled: value,
                              ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.activityRuleSyncEnabled,
                          title: Text(
                            context.l10n.text(
                              'synchronize_classification_rules',
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.text(
                              'synchronize_classification_rules_description',
                            ),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                activityRuleSyncEnabled: value,
                              ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.detailedActivitySyncEnabled,
                          title: Text(
                            context.l10n.text('synchronize_detailed_activity'),
                          ),
                          subtitle: Text(
                            context.l10n.text(
                              'synchronize_detailed_activity_description',
                            ),
                          ),
                          onChanged: _toggleDetailedActivitySync,
                        ),
                        const _CommunityLearningSwitch(),
                        const Divider(),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final picker = DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: settings.localActivityRetentionDays,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final days in const [7, 14, 30, 90, 0])
                                  DropdownMenuItem(
                                    value: days,
                                    child: Text(
                                      days == 0
                                          ? context.l10n.text(
                                              'retention_until_deleted',
                                            )
                                          : context.l10n.format(
                                              'retention_days',
                                              {'days': days},
                                            ),
                                    ),
                                  ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                await ref
                                    .read(settingsRepositoryProvider)
                                    .updateAttributionSetting(
                                      localActivityRetentionDays: value,
                                    );
                                await ref
                                    .read(activityRepositoryProvider)
                                    .purgeExpiredLocalActivity(
                                      retentionDays: value,
                                    );
                              },
                            );
                            if (constraints.maxWidth < 560) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.l10n.text(
                                        'local_activity_retention',
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      context.l10n.text(
                                        'local_activity_retention_description',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: picker,
                                    ),
                                  ],
                                ),
                              );
                            }
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                context.l10n.text('local_activity_retention'),
                              ),
                              subtitle: Text(
                                context.l10n.text(
                                  'local_activity_retention_description',
                                ),
                              ),
                              trailing: SizedBox(width: 180, child: picker),
                            );
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.hideConfirmedSystemActivity,
                          title: Text(
                            context.l10n.text('hide_confirmed_system_activity'),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                hideConfirmedSystemActivity: value,
                              ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: settings.showPossibleSystemActivity,
                          title: Text(
                            context.l10n.text('show_possible_system_activity'),
                          ),
                          onChanged: (value) => ref
                              .read(settingsRepositoryProvider)
                              .updateAttributionSetting(
                                showPossibleSystemActivity: value,
                              ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.visibility_off_outlined),
                          title: Text(
                            context.l10n.text('review_hidden_system_activity'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ActivityReviewScreen(
                                initialFilter: 'hidden_system',
                              ),
                            ),
                          ),
                        ),
                        const Divider(),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  _clearLocalActivity('unclassified'),
                              child: Text(
                                context.l10n.text(
                                  'clear_local_unclassified_activity',
                                ),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () => _clearLocalActivity('system'),
                              child: Text(
                                context.l10n.text(
                                  'clear_local_system_activity',
                                ),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () => _clearLocalActivity('all'),
                              child: Text(
                                context.l10n.text(
                                  'clear_all_local_activity_details',
                                ),
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _exportLocalActivity,
                              icon: const Icon(Icons.download_outlined),
                              label: Text(
                                context.l10n.text('export_local_activity'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: context.l10n.text('reports_and_data'),
                    icon: Icons.assessment_outlined,
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey(settings.healthReportPrivacy),
                          initialValue: settings.healthReportPrivacy,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: context.l10n.text(
                              'include_health_summaries',
                            ),
                            prefixIcon: const Icon(
                              Icons.health_and_safety_outlined,
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'never',
                              child: Text(
                                context.l10n.text('health_reports_never'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'ask',
                              child: Text(
                                context.l10n.text('health_reports_ask'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'private',
                              child: Text(
                                context.l10n.text('health_reports_private'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'selected',
                              child: Text(
                                context.l10n.text('health_reports_selected'),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              ref
                                  .read(settingsRepositoryProvider)
                                  .updateHealthReportPrivacy(value);
                            }
                          },
                        ),
                        const Divider(height: 26),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.picture_as_pdf_outlined),
                          title: Text(
                            context.l10n.text('overall_performance_report'),
                          ),
                          subtitle: Text(
                            context.l10n.text(
                              'overall_performance_report_detail',
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PerformanceReportScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    title: context.l10n.text('privacy'),
                    icon: Icons.shield_outlined,
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.lock_outline),
                          title: Text(context.l10n.text('vault_title')),
                          subtitle: Text(
                            context.l10n.text('vault_not_configured_body'),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PasswordVaultScreen(),
                            ),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.download_outlined),
                          title: Text(context.l10n.text('export_account_data')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _exportAccountData,
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_forever_outlined,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(context.l10n.text('delete_account')),
                          subtitle: Text(context.l10n.text('recovery_30_days')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AccountDeletionScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SyncSettingsSummary(),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    key: _helpSectionKey,
                    title: context.l10n.text('app_updates'),
                    icon: Icons.system_update_alt_rounded,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              context.l10n.format('app_version', {
                                'version': _version,
                              }),
                            ),
                            subtitle: Text(
                              context.l10n.text('app_update_security_detail'),
                            ),
                            trailing: FilledButton.tonalIcon(
                              onPressed: _checkingUpdate
                                  ? null
                                  : _checkForUpdates,
                              icon: _checkingUpdate
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                              label: Text(context.l10n.text('check_now')),
                            ),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.new_releases_outlined),
                            title: Text(context.l10n.text('whats_new')),
                            subtitle: Text(
                              context.l10n.format('release_notes_for', {
                                'version': _version,
                              }),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                showWhatsNewDialog(context, service: _updates),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SettingsSection(
                    key: _aboutSectionKey,
                    title: context.l10n.text('about_and_legal'),
                    icon: Icons.policy_outlined,
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: Text(context.l10n.text('view_privacy_policy')),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://yasserdiab.site/privacy-policy/',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.gavel_outlined),
                          title: Text(context.l10n.text('view_terms_of_use')),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: () => launchUrl(
                            Uri.parse('https://yasserdiab.site/terms/'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCategoryPage extends ConsumerWidget {
  const _SettingsCategoryPage({
    required this.categoryKey,
    required this.user,
    required this.settings,
    required this.themeKey,
    required this.onToggleApplicationTracking,
    required this.onExportAccountData,
  });

  final String categoryKey;
  final User user;
  final LocalAppSetting settings;
  final TaskMasterThemeKey themeKey;
  final Future<void> Function(bool enabled) onToggleApplicationTracking;
  final Future<void> Function() onExportAccountData;

  void _openTasks(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TasksScreen(showRouteAppBar: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appSettingsProvider).value ?? settings;
    final repository = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text(categoryKey))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: switch (categoryKey) {
          'profile_and_account' => [
            StreamBuilder(
              stream: repository.watchProfile(user.id),
              builder: (context, snapshot) => _ProfileCard(
                user: user,
                profile: snapshot.data,
                themeKey: themeKey,
              ),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: context.l10n.text('profile_and_account'),
              icon: Icons.manage_accounts_outlined,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download_outlined),
                    title: Text(context.l10n.text('export_account_data')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onExportAccountData,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(context.l10n.text('delete_account')),
                    subtitle: Text(context.l10n.text('recovery_30_days')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountDeletionScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.logout,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(context.l10n.text('sign_out')),
                    onTap: () => Supabase.instance.client.auth.signOut(),
                  ),
                ],
              ),
            ),
          ],
          'tasks_and_execution' => [
            _SettingsCategoryIntro(
              icon: Icons.task_alt_outlined,
              description: context.l10n.text(
                'settings_tasks_execution_description',
              ),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: context.l10n.text('tasks_and_execution'),
              icon: Icons.tune_outlined,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_calendar_outlined),
                title: Text(context.l10n.text('manage_task_settings')),
                subtitle: Text(
                  context.l10n.text('task_settings_per_task_description'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openTasks(context),
              ),
            ),
          ],
          'pomodoro' => [
            _SettingsCategoryIntro(
              icon: Icons.timer_outlined,
              description: context.l10n.text('settings_pomodoro_description'),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: context.l10n.text('pomodoro'),
              icon: Icons.timer_outlined,
              child: Column(
                children: [
                  ListTile(
                    key: const ValueKey('open-standalone-pomodoro'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(context.l10n.text('standalone_pomodoro')),
                    subtitle: Text(
                      context.l10n.text('standalone_pomodoro_description'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StandalonePomodoroScreen(),
                      ),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.edit_note_outlined),
                    title: Text(context.l10n.text('manage_pomodoro_settings')),
                    subtitle: Text(
                      context.l10n.text(
                        'pomodoro_settings_per_task_description',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTasks(context),
                  ),
                ],
              ),
            ),
          ],
          'activity_and_privacy' => [
            _SettingsCategoryIntro(
              icon: Icons.shield_outlined,
              description: context.l10n.text(
                'settings_activity_privacy_description',
              ),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: context.l10n.text('activity_and_privacy'),
              icon: Icons.shield_outlined,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: current.applicationTrackingEnabled,
                    title: Text(
                      context.l10n.text(
                        Platform.isAndroid
                            ? 'tracking_android_apps'
                            : 'tracking_active_windows',
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.text(
                        Platform.isAndroid
                            ? 'tracking_android_apps_description'
                            : 'tracking_active_windows_description',
                      ),
                    ),
                    onChanged: onToggleApplicationTracking,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: current.windowTitleTrackingEnabled,
                    title: Text(context.l10n.text('tracking_window_titles')),
                    subtitle: Text(
                      context.l10n.text('tracking_window_titles_description'),
                    ),
                    onChanged: (value) =>
                        repository.updateTrackingSettings(windowTitles: value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: current.idleDetectionEnabled,
                    title: Text(context.l10n.text('tracking_inactive')),
                    subtitle: Text(
                      context.l10n.format('tracking_inactive_description', {
                        'seconds': current.idleThresholdSeconds,
                      }),
                    ),
                    onChanged: (value) =>
                        repository.updateTrackingSettings(idleDetection: value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: current.activitySyncEnabled,
                    title: Text(
                      context.l10n.text('synchronize_confirmed_contributions'),
                    ),
                    subtitle: Text(
                      context.l10n.text(
                        'synchronize_confirmed_contributions_description',
                      ),
                    ),
                    onChanged: (value) => repository.updateAttributionSetting(
                      activitySyncEnabled: value,
                    ),
                  ),
                  const _CommunityLearningSwitch(),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(context.l10n.text('activity_review')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ActivityReviewScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          'reports' => [
            _SettingsCategoryIntro(
              icon: Icons.assessment_outlined,
              description: context.l10n.text('settings_reports_description'),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: context.l10n.text('reports'),
              icon: Icons.assessment_outlined,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: current.healthReportPrivacy,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('include_health_summaries'),
                      prefixIcon: const Icon(Icons.health_and_safety_outlined),
                    ),
                    items: [
                      for (final value in const [
                        'never',
                        'ask',
                        'private',
                        'selected',
                      ])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            context.l10n.text('health_reports_$value'),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        repository.updateHealthReportPrivacy(value);
                      }
                    },
                  ),
                  const Divider(height: 26),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(
                      context.l10n.text('overall_performance_report'),
                    ),
                    subtitle: Text(
                      context.l10n.text('overall_performance_report_detail'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PerformanceReportScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          'appearance' => [
            _SettingsCategoryIntro(
              icon: Icons.palette_outlined,
              description: context.l10n.text('settings_appearance_description'),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: context.l10n.text('appearance'),
              icon: Icons.palette_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ThemeSelector(selected: current.themeKey),
                  const SizedBox(height: 18),
                  Text(
                    context.l10n.text('language'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'en',
                          label: Text('EN'), // localization-audit: allow
                        ),
                        ButtonSegment(
                          value: 'ar',
                          label: Text('ع'), // localization-audit: allow
                        ),
                        ButtonSegment(
                          value: 'de',
                          label: Text('DE'), // localization-audit: allow
                        ),
                      ],
                      selected: {current.localeCode},
                      onSelectionChanged: (values) =>
                          repository.updateLocale(values.first),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _TimeZoneSettings(settings: current),
                ],
              ),
            ),
          ],
          'synchronization' => [
            _SettingsCategoryIntro(
              icon: Icons.sync_outlined,
              description: context.l10n.text('settings_sync_description'),
            ),
            const SizedBox(height: 14),
            const _SyncSettingsSummary(),
          ],
          'help_and_diagnostics' => [
            _SettingsCategoryIntro(
              icon: Icons.help_outline,
              description: context.l10n.text(
                'settings_help_diagnostics_description',
              ),
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: context.l10n.text('help_and_diagnostics'),
              icon: Icons.help_outline,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sync_problem_outlined),
                    title: Text(context.l10n.text('review_sync_status')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => SynchronizationDiagnosticsPanel.show(context),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.help_center_outlined),
                    title: Text(context.l10n.text('installation_help')),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => launchUrl(
                      Uri.parse('https://yasserdiab.site/installation-help/'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ),
          ],
          'about_and_legal' => [const _AboutLegalCategory()],
          _ => [
            _SettingsCategoryIntro(
              icon: Icons.settings_outlined,
              description: context.l10n.text('settings_sections_description'),
            ),
          ],
        },
      ),
    );
  }
}

class _SettingsCategoryIntro extends StatelessWidget {
  const _SettingsCategoryIntro({required this.icon, required this.description});

  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(description)),
          ],
        ),
      ),
    );
  }
}

class _AboutLegalCategory extends StatefulWidget {
  const _AboutLegalCategory();

  @override
  State<_AboutLegalCategory> createState() => _AboutLegalCategoryState();
}

class _AboutLegalCategoryState extends State<_AboutLegalCategory> {
  final _updates = AppUpdateService();
  String _version = '0.0.29';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _updates.currentVersion().then((value) {
      if (mounted) setState(() => _version = value);
    });
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final release = await _updates.checkForUpdate();
      if (!mounted) return;
      if (release == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.format('update_up_to_date', {'version': _version}),
            ),
          ),
        );
      } else {
        await showAppUpdateDialog(context, service: _updates, release: release);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('update_check_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingsCategoryIntro(
          icon: Icons.info_outline,
          description: context.l10n.text('settings_about_legal_description'),
        ),
        const SizedBox(height: 14),
        _SettingsSection(
          title: context.l10n.text('about_and_legal'),
          icon: Icons.info_outline,
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.apps_outlined),
                title: Text(
                  context.l10n.format('app_version', {'version': _version}),
                ),
                subtitle: Text(context.l10n.text('app_update_security_detail')),
                trailing: IconButton.filledTonal(
                  tooltip: context.l10n.text('check_now'),
                  onPressed: _checking ? null : _check,
                  icon: _checking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.new_releases_outlined),
                title: Text(context.l10n.text('whats_new')),
                subtitle: Text(
                  context.l10n.format('release_notes_for', {
                    'version': _version,
                  }),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showWhatsNewDialog(context, service: _updates),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(context.l10n.text('view_privacy_policy')),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => launchUrl(
                  Uri.parse('https://yasserdiab.site/privacy-policy/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.gavel_outlined),
                title: Text(context.l10n.text('view_terms_of_use')),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => launchUrl(
                  Uri.parse('https://yasserdiab.site/terms/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({
    required this.user,
    required this.profile,
    required this.themeKey,
  });

  final User user;
  final LocalProfile? profile;
  final TaskMasterThemeKey themeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        profile?.displayName ??
        user.userMetadata?['display_name'] as String? ??
        user.userMetadata?['full_name'] as String? ??
        user.email?.split('@').first ??
        '';
    final imagePath = profile?.imagePath;
    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final editProfile = profile == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      _ProfileEditorDialog(user: user, profile: profile!),
                );

          if (compact) {
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: editProfile,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfileAvatar(name: name, imagePath: imagePath, radius: 42),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (user.newEmail?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.format('email_change_pending_compact', {
                          'email': user.newEmail,
                        }),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: editProfile,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  ProfileAvatar(name: name, imagePath: imagePath, radius: 34),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          user.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  BrandLogo(themeKey: themeKey, height: 44),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmailChangeDialog extends StatefulWidget {
  const _EmailChangeDialog({required this.user});

  final User user;

  @override
  State<_EmailChangeDialog> createState() => _EmailChangeDialogState();
}

class _EmailChangeDialogState extends State<_EmailChangeDialog> {
  late final TextEditingController _newEmail;
  final _nonce = TextEditingController();
  bool _reauthenticationSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newEmail = TextEditingController(text: widget.user.newEmail ?? '');
  }

  @override
  void dispose() {
    _newEmail.dispose();
    _nonce.dispose();
    super.dispose();
  }

  bool get _hasPendingRequest => widget.user.newEmail?.isNotEmpty == true;

  Future<void> _begin() async {
    final email = _newEmail.text.trim();
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!valid || email.toLowerCase() == widget.user.email?.toLowerCase()) {
      setState(() => _error = context.l10n.text('email_change_invalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.reauthenticate();
      if (!mounted) return;
      setState(() => _reauthenticationSent = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.text('email_change_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final nonce = _nonce.text.trim();
    if (nonce.length < 6) {
      setState(() => _error = context.l10n.text('email_reauth_code_required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: _newEmail.text.trim(), nonce: nonce),
        emailRedirectTo: SupabaseConfig.authCallback,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.format('email_change_confirmation_sent', {
              'email': _newEmail.text.trim(),
            }),
          ),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _error =
            error.code == 'email_exists' ||
                error.code == 'email_address_not_authorized'
            ? context.l10n.text('email_change_already_used')
            : context.l10n.text('email_change_failed'),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.text('email_change_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.emailChange,
        email: widget.user.newEmail ?? _newEmail.text.trim(),
        emailRedirectTo: SupabaseConfig.authCallback,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('email_confirmation_resent'))),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.text('email_change_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelPending() async {
    final currentEmail = widget.user.email;
    if (currentEmail == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: currentEmail),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('email_change_cancelled'))),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.text('email_change_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingEmail = widget.user.newEmail;
    return AlertDialog(
      title: Text(
        context.l10n.text(
          _hasPendingRequest
              ? 'email_change_awaiting_confirmation'
              : 'change_email_address',
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.text('current_email')),
              SelectableText(
                widget.user.email ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (_hasPendingRequest) ...[
                Text(context.l10n.text('requested_email')),
                SelectableText(
                  pendingEmail!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(context.l10n.text('email_current_remains_active')),
              ] else ...[
                TextField(
                  controller: _newEmail,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.newUsername],
                  enabled: !_busy && !_reauthenticationSent,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('new_email'),
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 10),
                Text(context.l10n.text('email_change_security_explanation')),
                if (_reauthenticationSent) ...[
                  const SizedBox(height: 16),
                  Text(context.l10n.text('email_reauth_code_sent')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nonce,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: InputDecoration(
                      labelText: context.l10n.text('email_verification_code'),
                      prefixIcon: const Icon(Icons.verified_user_outlined),
                    ),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_hasPendingRequest)
          TextButton(
            onPressed: _busy ? null : _cancelPending,
            child: Text(context.l10n.text('cancel_email_change')),
          ),
        if (_hasPendingRequest)
          TextButton(
            onPressed: _busy ? null : _resend,
            child: Text(context.l10n.text('resend_confirmation')),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.text('close')),
        ),
        if (!_hasPendingRequest)
          FilledButton(
            onPressed: _busy
                ? null
                : _reauthenticationSent
                ? _confirm
                : _begin,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.l10n.text(
                      _reauthenticationSent ? 'confirm_new_email' : 'continue',
                    ),
                  ),
          ),
      ],
    );
  }
}

class _ProfileEditorDialog extends ConsumerStatefulWidget {
  const _ProfileEditorDialog({required this.user, required this.profile});

  final User user;
  final LocalProfile profile;

  @override
  ConsumerState<_ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<_ProfileEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _height;
  String? _gender;
  DateTime? _dateOfBirth;
  ProfileImageSelection? _selection;
  bool _busy = false;
  String? _progressMessage;
  String? _heightError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.displayName);
    final height = widget.profile.heightCm;
    _height = TextEditingController(
      text: height == null
          ? ''
          : height == height.roundToDouble()
          ? height.toStringAsFixed(0)
          : height.toStringAsFixed(1),
    );
    _gender = widget.profile.genderIdentity;
    _dateOfBirth = widget.profile.dateOfBirth?.toLocal();
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final dialogTitle = context.l10n.text('profile_choose_picture');
      final useCamera = Platform.isAndroid
          ? await showModalBottomSheet<bool>(
              context: context,
              builder: (context) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(context.l10n.text('choose_device_photo')),
                      onTap: () => Navigator.pop(context, false),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: Text(context.l10n.text('take_photo')),
                      onTap: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ),
            )
          : false;
      if (useCamera == null) return;
      final selection = await ProfileMediaService(Supabase.instance.client)
          .chooseAndStore(
            widget.user.id,
            useCamera: useCamera,
            dialogTitle: dialogTitle,
          );
      if (selection != null && mounted) {
        setState(() => _selection = selection);
      }
    } on FileSystemException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('profile_picture_select_failed')),
        ),
      );
    }
  }

  Future<void> _chooseDateOfBirth() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 30, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(now.year - 120),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: context.l10n.text('date_of_birth'),
    );
    if (selected != null && mounted) {
      setState(() => _dateOfBirth = selected);
    }
  }

  int? get _age {
    final birth = _dateOfBirth;
    if (birth == null) return null;
    final today = DateTime.now();
    var age = today.year - birth.year;
    if (today.month < birth.month ||
        (today.month == birth.month && today.day < birth.day)) {
      age--;
    }
    return age;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    final heightText = _height.text.trim().replaceAll(',', '.');
    final height = double.tryParse(heightText);
    if (heightText.isEmpty || height == null || height < 50 || height > 250) {
      setState(
        () => _heightError = context.l10n.text(
          heightText.isEmpty ? 'height_required' : 'height_invalid',
        ),
      );
      return;
    }
    setState(() => _heightError = null);
    setState(() => _busy = true);
    try {
      String? remoteImagePath;
      if (_selection != null) {
        setState(
          () =>
              _progressMessage = context.l10n.text('profile_uploading_picture'),
        );
        try {
          remoteImagePath = await ProfileMediaService(
            Supabase.instance.client,
          ).upload(_selection!);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.text('profile_picture_update_failed')),
            ),
          );
          return;
        }
      }
      if (mounted) {
        setState(() => _progressMessage = context.l10n.text('profile_saving'));
      }
      await ref
          .read(settingsRepositoryProvider)
          .updateProfile(
            userId: widget.user.id,
            displayName: name,
            genderIdentity: _gender,
            dateOfBirth: _dateOfBirth,
            heightCm: height,
            localImagePath: _selection?.localPath,
            remoteImagePath: remoteImagePath,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selection == null
                  ? context.l10n.text('profile_updated')
                  : context.l10n.text('profile_picture_updated'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progressMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _selection?.localPath ?? widget.profile.imagePath;
    return AlertDialog(
      title: Text(context.l10n.text('edit_profile')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatar(
                    name: _name.text,
                    imagePath: imagePath,
                    radius: 48,
                  ),
                  PositionedDirectional(
                    end: -8,
                    bottom: -8,
                    child: IconButton.filled(
                      tooltip: context.l10n.text('profile_choose_picture'),
                      onPressed: _busy ? null : _choosePhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (_progressMessage != null) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_progressMessage!),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.l10n.text('display_name'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alternate_email),
                title: Text(widget.user.email ?? ''),
                subtitle: Text(context.l10n.text('edit_email')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _EmailChangeDialog(user: widget.user),
                      ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _height,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_heightError != null) {
                    setState(() => _heightError = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: context.l10n.text('height_cm'),
                  prefixIcon: const Icon(Icons.height),
                  errorText: _heightError,
                  helperText: context.l10n.text('height_required'),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: _gender,
                decoration: InputDecoration(
                  labelText: context.l10n.text('gender'),
                  prefixIcon: const Icon(Icons.person_outline),
                  helperText: context.l10n.text('gender_profile_only'),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.text('gender_not_set')),
                  ),
                  DropdownMenuItem(
                    value: 'woman',
                    child: Text(context.l10n.text('gender_woman')),
                  ),
                  DropdownMenuItem(
                    value: 'man',
                    child: Text(context.l10n.text('gender_man')),
                  ),
                  DropdownMenuItem(
                    value: 'non_binary',
                    child: Text(context.l10n.text('gender_non_binary')),
                  ),
                  DropdownMenuItem(
                    value: 'self_described',
                    child: Text(context.l10n.text('gender_self_described')),
                  ),
                  DropdownMenuItem(
                    value: 'prefer_not_to_say',
                    child: Text(context.l10n.text('gender_prefer_not')),
                  ),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cake_outlined),
                title: Text(context.l10n.text('date_of_birth')),
                subtitle: Text(
                  _dateOfBirth == null
                      ? context.l10n.text('date_of_birth_not_set')
                      : MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(_dateOfBirth!),
                ),
                trailing: _age == null
                    ? const Icon(Icons.chevron_right)
                    : Text(
                        context.l10n.format('age_value', {'age': _age}),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                onTap: _busy ? null : _chooseDateOfBirth,
              ),
              if (_dateOfBirth != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _dateOfBirth = null),
                    child: Text(context.l10n.text('remove_date_of_birth')),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.text('profile_save')),
        ),
      ],
    );
  }
}

class _ThemeSelector extends ConsumerWidget {
  const _ThemeSelector({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final theme in TaskMasterThemeKey.values)
              SizedBox(
                width: constraints.maxWidth >= 600
                    ? (constraints.maxWidth - 30) / 4
                    : constraints.maxWidth >= 360
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth,
                child: ChoiceChip(
                  selected: selected == theme.name,
                  onSelected: (_) => ref
                      .read(settingsRepositoryProvider)
                      .updateTheme(theme.name),
                  avatar: Icon(switch (theme) {
                    TaskMasterThemeKey.system => Icons.brightness_auto,
                    TaskMasterThemeKey.light => Icons.light_mode,
                    TaskMasterThemeKey.dark => Icons.dark_mode,
                    TaskMasterThemeKey.golden => Icons.workspace_premium,
                  }, size: 18),
                  label: SizedBox(
                    width: double.infinity,
                    child: Text(
                      context.l10n.text(theme.name),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SyncSettingsSummary extends ConsumerWidget {
  const _SyncSettingsSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref
          .watch(syncServiceProvider)
          .getSnapshot(checkRemoteDevices: false),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final synced = data?.isTruthfullySynced == true;
        final offline = data?.connectionAvailable == false;
        return _SettingsSection(
          title: synced
              ? context.l10n.text('sync_all_changes')
              : offline
              ? context.l10n.text('sync_working_offline')
              : context.l10n.text('synchronization'),
          icon: synced
              ? Icons.cloud_done_outlined
              : offline
              ? Icons.cloud_off_outlined
              : Icons.sync_problem,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              synced
                  ? context.l10n.text('sync_latest_available')
                  : offline
                  ? context.l10n.text('sync_offline_reconnect')
                  : context.l10n.text('sync_review_detail'),
            ),
            subtitle: data?.lastSuccessfulSync == null
                ? null
                : Text(
                    context.l10n.format('sync_last_synced_value', {
                      'time': MaterialLocalizations.of(context).formatTimeOfDay(
                        TimeOfDay.fromDateTime(
                          data!.lastSuccessfulSync!.toLocal(),
                        ),
                      ),
                    }),
                  ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => SynchronizationPanel.show(context),
          ),
        );
      },
    );
  }
}

class _WindowsHealthSection extends ConsumerWidget {
  const _WindowsHealthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: entities.watch(entityType: 'health_summaries'),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const [];
        if (records.isEmpty) return const SizedBox.shrink();
        final latest = [...records]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final source = healthSourceSummaryLabel(
          entities.decode(latest.first)['source'] as String? ?? '',
          fallback: context.l10n.text('health_android_phone'),
        );
        return _SettingsSection(
          title: context.l10n.text('health_and_rest'),
          icon: Icons.health_and_safety_outlined,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.text('health_android_summaries')),
            subtitle: Text(
              context.l10n.format('health_source_updated', {
                'source': source,
                'time': MaterialLocalizations.of(context).formatTimeOfDay(
                  TimeOfDay.fromDateTime(latest.first.updatedAt.toLocal()),
                ),
              }),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WindowsHealthSummaryScreen(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimeZoneSettings extends ConsumerWidget {
  const _TimeZoneSettings({required this.settings});

  final LocalAppSetting settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = TimeZoneService.describe(settings.timeZone);
    final repository = ref.read(settingsRepositoryProvider);
    return Column(
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.useDeviceTimeZone,
          title: Text(context.l10n.text('time_zone_auto')),
          subtitle: FutureBuilder<String>(
            future: TimeZoneService.detectDeviceIanaZone(),
            builder: (context, snapshot) {
              final detected = snapshot.data;
              return Text(
                detected == null
                    ? context.l10n.text('time_zone_detected')
                    : '${context.l10n.text('time_zone_detected')}: $detected',
              );
            },
          ),
          onChanged: (enabled) async {
            if (!enabled) {
              await repository.updateRegionalSettings(useDeviceTimeZone: false);
              return;
            }
            final detected = await TimeZoneService.detectDeviceIanaZone();
            await repository.updateRegionalSettings(
              timeZone: detected,
              useDeviceTimeZone: true,
            );
          },
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.public_outlined),
          title: Text(context.l10n.text('time_zone_manual')),
          subtitle: Text('${choice.displayLabel}\n${choice.ianaId}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final selected = await showDialog<TimeZoneChoice>(
              context: context,
              builder: (_) => _TimeZonePicker(initial: choice),
            );
            if (selected == null) return;
            await repository.updateRegionalSettings(
              timeZone: selected.ianaId,
              useDeviceTimeZone: false,
            );
          },
        ),
      ],
    );
  }
}

class _TimeZonePicker extends StatefulWidget {
  const _TimeZonePicker({required this.initial});

  final TimeZoneChoice initial;

  @override
  State<_TimeZonePicker> createState() => _TimeZonePickerState();
}

class _TimeZonePickerState extends State<_TimeZonePicker> {
  final _search = TextEditingController();
  late final List<TimeZoneChoice> _choices = TimeZoneService.allChoices();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(TimeZoneChoice choice, String needle) {
    final searchable = '${choice.city} ${choice.ianaId} ${choice.offsetLabel}'
        .toLowerCase();
    return searchable.contains(needle.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final needle = _search.text.trim();
    final matches = needle.isEmpty
        ? _choices
        : _choices.where((choice) => _matches(choice, needle)).toList();
    final byOffset = <int, List<TimeZoneChoice>>{};
    for (final choice in matches) {
      byOffset.putIfAbsent(choice.offset.inMinutes, () => []).add(choice);
    }
    return AlertDialog(
      title: Text(context.l10n.text('time_zone_manual')),
      content: SizedBox(
        width: 520,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.l10n.text('time_zone_search'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(context.l10n.text('time_zone_no_results')),
                    )
                  : ListView(
                      children: [
                        for (final group in byOffset.entries)
                          _TimeZoneOffsetGroup(
                            choices: group.value,
                            initialId: widget.initial.ianaId,
                            onSelected: (choice) =>
                                Navigator.of(context).pop(choice),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.text('cancel')),
        ),
      ],
    );
  }
}

class _TimeZoneOffsetGroup extends StatelessWidget {
  const _TimeZoneOffsetGroup({
    required this.choices,
    required this.initialId,
    required this.onSelected,
  });

  final List<TimeZoneChoice> choices;
  final String initialId;
  final ValueChanged<TimeZoneChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final primary = choices.first;
    final hasSelected = choices.any((choice) => choice.ianaId == initialId);
    return ExpansionTile(
      initiallyExpanded: hasSelected,
      title: Text(primary.displayLabel),
      subtitle: Text(
        choices.length == 1
            ? primary.ianaId
            : context.l10n.text('time_zone_all_cities'),
      ),
      children: [
        for (final choice in choices)
          ListTile(
            selected: choice.ianaId == initialId,
            title: Text(choice.city),
            subtitle: Text(choice.ianaId),
            trailing: Text(choice.offsetLabel),
            onTap: () => onSelected(choice),
          ),
      ],
    );
  }
}

class _CommunityLearningSwitch extends StatefulWidget {
  const _CommunityLearningSwitch();

  @override
  State<_CommunityLearningSwitch> createState() =>
      _CommunityLearningSwitchState();
}

class _CommunityLearningSwitchState extends State<_CommunityLearningSwitch> {
  SharedPreferencesApplicationSystemLearningPreferences? _preferences;
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shared = await SharedPreferences.getInstance();
    final preferences = SharedPreferencesApplicationSystemLearningPreferences(
      shared,
    );
    final enabled = await preferences.isOptedIn();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _change(bool value) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.text('community_system_learning')),
          content: Text(context.l10n.text('community_system_learning_consent')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.text('share_anonymous_votes')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _preferences?.setOptedIn(value);
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const ValueKey('community-system-learning-switch'),
    contentPadding: EdgeInsets.zero,
    value: _enabled,
    title: Text(context.l10n.text('community_system_learning')),
    subtitle: Text(context.l10n.text('community_system_learning_description')),
    onChanged: _loading ? null : _change,
  );
}
