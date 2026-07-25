import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({required this.user, super.key});

  final User user;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _preview = NotificationSoundPreview();
  final _notifications = LocalNotificationService();
  bool _notificationReady = false;

  @override
  void initState() {
    super.initState();
    _notifications.initialize().then((_) {
      if (mounted) setState(() => _notificationReady = true);
    });
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
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
                _ProfileCard(user: widget.user, themeKey: themeKey),
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
                        onTap: () {},
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
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.themeKey});

  final User user;
  final TaskMasterThemeKey themeKey;

  @override
  Widget build(BuildContext context) {
    final name =
        user.userMetadata?['display_name'] as String? ??
        user.userMetadata?['full_name'] as String? ??
        user.email?.split('@').first ??
        '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
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
                ],
              ),
            ),
            BrandLogo(themeKey: themeKey, height: 48),
          ],
        ),
      ),
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
