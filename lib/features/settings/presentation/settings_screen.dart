import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/account_export_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/database/app_database.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';
import '../../../core/updates/app_update_service.dart';
import '../../../core/updates/update_prompt.dart';
import '../../calendar/presentation/planning_calendar_screen.dart';
import '../../health/presentation/health_connect_screen.dart';
import '../data/profile_media_service.dart';

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
  String _version = '0.0.25';

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

  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final release = await _updates.checkForUpdate();
      if (!mounted) return;
      if (release == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('TaskMaster Pro $_version is up to date')),
        );
        return;
      }
      await showAppUpdateDialog(context, service: _updates, release: release);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Updates could not be checked right now. Try again when online',
          ),
        ),
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
                ? 'Account data exported successfully'
                : 'Account data exported to ${result.path}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Account export failed: $error')));
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
        title: const Text('Allow Android usage access?'),
        content: const Text(
          'Android can provide recent application usage and screen activity '
          'after you enable TaskMaster Pro in the system Usage Access page. '
          'It does not provide the same window-title detail available on Windows.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Android settings'),
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final themeKey = TaskMasterThemeKey.fromKey(settings.themeKey);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
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
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                StreamBuilder(
                  stream: ref
                      .watch(settingsRepositoryProvider)
                      .watchProfile(widget.user.id),
                  builder: (context, snapshot) => _ProfileCard(
                    user: widget.user,
                    profile: snapshot.data,
                    themeKey: themeKey,
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: context.l10n.text('appearance'),
                  icon: Icons.palette_outlined,
                  child: Column(
                    children: [
                      _ThemeSelector(selected: settings.themeKey),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.text('language'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'en', label: Text('EN')),
                              ButtonSegment(value: 'ar', label: Text('ع')),
                              ButtonSegment(value: 'de', label: Text('DE')),
                            ],
                            selected: {settings.localeCode},
                            onSelectionChanged: (values) => ref
                                .read(settingsRepositoryProvider)
                                .updateLocale(values.first),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: 'Health and cycle',
                  icon: Icons.favorite_outline,
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.health_and_safety_outlined),
                        title: const Text('Health Connect'),
                        subtitle: Text(
                          settings.healthConnectEnabled
                              ? 'Connected health summaries are available'
                              : 'Connect steps, exercise, distance, heart rate, and sleep',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HealthConnectScreen(),
                          ),
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.cycleTrackingEnabled,
                        title: const Text('Optional cycle tracking'),
                        subtitle: const Text(
                          'Disabled by default and never inferred from gender',
                        ),
                        onChanged: (value) => ref
                            .read(settingsRepositoryProvider)
                            .updateCyclePreferences(enabled: value),
                      ),
                      if (settings.cycleTrackingEnabled) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: settings.cycleStorageMode,
                          decoration: const InputDecoration(
                            labelText: 'Cycle data storage',
                            prefixIcon: Icon(
                              Icons.enhanced_encryption_outlined,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'local_only',
                              child: Text('This device only'),
                            ),
                            DropdownMenuItem(
                              value: 'encrypted_sync',
                              child: Text('Encrypted synchronization'),
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
                            label: const Text('Open cycle calendar'),
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
                                            Text(choice.label),
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
                            tooltip: 'Preview selected sound',
                            onPressed: () => _preview.play(
                              NotificationSounds.byKey(
                                settings.notificationSoundKey,
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Send a test notification',
                            onPressed: !_notificationReady
                                ? null
                                : () async {
                                    await _notifications.requestPermission();
                                    await _notifications.showTest(
                                      NotificationSounds.byKey(
                                        settings.notificationSoundKey,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.notification_add_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '“System default” uses the Android sound selected by the '
                        'device. Custom sounds are packaged for offline reminders.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (Platform.isAndroid &&
                          settings.notificationSoundKey == 'system') ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            onPressed:
                                _notifications.openAndroidSystemSoundSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('Choose Android system sound'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: context.l10n.text('activity_attribution'),
                  icon: Icons.account_tree_outlined,
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.applicationTrackingEnabled,
                        title: Text(
                          Platform.isAndroid
                              ? 'Android application usage'
                              : 'Windows foreground applications',
                        ),
                        subtitle: Text(
                          Platform.isAndroid
                              ? 'Requires Usage Access and provides only Android-permitted history'
                              : 'Stores compact foreground segments, not per-second database rows',
                        ),
                        onChanged: _toggleApplicationTracking,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.windowTitleTrackingEnabled,
                        title: const Text('Include window titles'),
                        subtitle: const Text(
                          'Optional; disable this to retain application names only',
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
                        title: const Text('Technical idle detection'),
                        subtitle: Text(
                          'Threshold: ${settings.idleThresholdSeconds} seconds. '
                          'Idle-looking activity stays reviewable.',
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
                        title: Text(context.l10n.text('detect_break_activity')),
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
                        subtitle: const Text(
                          'Only explicit user rules can credit automatically.',
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
                        title: const Text('Synchronize activity history'),
                        subtitle: Text(
                          settings.activitySyncEnabled
                              ? 'Activity evidence can follow this account to your other devices'
                              : 'New activity evidence remains only on this device',
                        ),
                        onChanged: (value) => ref
                            .read(settingsRepositoryProvider)
                            .updateAttributionSetting(
                              activitySyncEnabled: value,
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
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.lock_outline),
                        title: Text('Password vault'),
                        subtitle: Text(
                          'Locked subsystem — production implementation waits '
                          'for sync recovery and external security review.',
                        ),
                        trailing: Icon(Icons.chevron_right),
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.download_outlined),
                        title: const Text('Export account data'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _exportAccountData,
                      ),
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
                const SizedBox(height: 16),
                _SettingsSection(
                  title: context.l10n.text('offline_first'),
                  icon: Icons.offline_bolt_outlined,
                  child: Text(
                    context.l10n.text('offline_first_detail'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SettingsSection(
                  title: 'App updates',
                  icon: Icons.system_update_alt_rounded,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('TaskMaster Pro $_version'),
                    subtitle: const Text(
                      'Secure releases are checked on GitHub and verified before opening',
                    ),
                    trailing: FilledButton.tonalIcon(
                      onPressed: _checkingUpdate ? null : _checkForUpdates,
                      icon: _checkingUpdate
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Check now'),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: profile == null
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (_) =>
                    _ProfileEditorDialog(user: user, profile: profile!),
              ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              _ProfileAvatar(name: name, imagePath: imagePath, radius: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      user.email ?? '',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (profile?.genderIdentity != null)
                      Text(
                        _genderLabel(profile!.genderIdentity!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit profile',
                onPressed: profile == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            _ProfileEditorDialog(user: user, profile: profile!),
                      ),
                icon: const Icon(Icons.edit_outlined),
              ),
              BrandLogo(themeKey: themeKey, height: 44),
            ],
          ),
        ),
      ),
    );
  }

  static String _genderLabel(String value) => switch (value) {
    'woman' => 'Woman',
    'man' => 'Man',
    'non_binary' => 'Non-binary',
    'self_described' => 'Self-described',
    'prefer_not_to_say' => 'Prefer not to say',
    _ => value,
  };
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
  String? _gender;
  ProfileImageSelection? _selection;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.displayName);
    _gender = widget.profile.genderIdentity;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final selection = await ProfileMediaService(
        Supabase.instance.client,
      ).chooseAndStore(widget.user.id);
      if (selection != null && mounted) {
        setState(() => _selection = selection);
      }
    } on FileSystemException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      String? remoteImagePath;
      if (_selection != null) {
        try {
          remoteImagePath = await ProfileMediaService(
            Supabase.instance.client,
          ).upload(_selection!);
        } catch (_) {
          // The selected local image is retained. Its upload is retried by sync.
        }
      }
      await ref
          .read(settingsRepositoryProvider)
          .updateProfile(
            userId: widget.user.id,
            displayName: name,
            genderIdentity: _gender,
            localImagePath: _selection?.localPath,
            remoteImagePath: remoteImagePath,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _selection?.localPath ?? widget.profile.imagePath;
    return AlertDialog(
      title: const Text('Edit profile'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _ProfileAvatar(
                    name: _name.text,
                    imagePath: imagePath,
                    radius: 48,
                  ),
                  PositionedDirectional(
                    end: -8,
                    bottom: -8,
                    child: IconButton.filled(
                      tooltip: 'Choose profile picture',
                      onPressed: _busy ? null : _choosePhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _name,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  prefixIcon: Icon(Icons.person_outline),
                  helperText:
                      'Used only for your profile. Cycle tracking is controlled separately.',
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Not set')),
                  DropdownMenuItem(value: 'woman', child: Text('Woman')),
                  DropdownMenuItem(value: 'man', child: Text('Man')),
                  DropdownMenuItem(
                    value: 'non_binary',
                    child: Text('Non-binary'),
                  ),
                  DropdownMenuItem(
                    value: 'self_described',
                    child: Text('Self-described'),
                  ),
                  DropdownMenuItem(
                    value: 'prefer_not_to_say',
                    child: Text('Prefer not to say'),
                  ),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save profile'),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.name,
    required this.imagePath,
    required this.radius,
  });

  final String name;
  final String? imagePath;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    ImageProvider<Object>? provider;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        provider = NetworkImage(path);
      } else if (File(path).existsSync()) {
        provider = FileImage(File(path));
      }
    }
    return CircleAvatar(
      radius: radius,
      foregroundImage: provider,
      child: provider == null
          ? Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge,
            )
          : null,
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
                    : (constraints.maxWidth - 10) / 2,
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
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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
