import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import 'schedule_wellbeing_screen.dart';

@immutable
class NotificationPlatformCapabilities {
  const NotificationPlatformCapabilities({
    required this.supportsVibration,
    required this.supportsDeviceSoundPicker,
    required this.supportsNotificationSettings,
  });

  final bool supportsVibration;
  final bool supportsDeviceSoundPicker;
  final bool supportsNotificationSettings;
}

@visibleForTesting
NotificationPlatformCapabilities notificationPlatformCapabilities(
  TargetPlatform platform,
) => switch (platform) {
  TargetPlatform.android => const NotificationPlatformCapabilities(
    supportsVibration: true,
    supportsDeviceSoundPicker: true,
    supportsNotificationSettings: true,
  ),
  TargetPlatform.windows => const NotificationPlatformCapabilities(
    supportsVibration: false,
    supportsDeviceSoundPicker: false,
    supportsNotificationSettings: true,
  ),
  _ => const NotificationPlatformCapabilities(
    supportsVibration: false,
    supportsDeviceSoundPicker: false,
    supportsNotificationSettings: false,
  ),
};

class NotificationsSoundsScreen extends ConsumerStatefulWidget {
  const NotificationsSoundsScreen({super.key});

  @override
  ConsumerState<NotificationsSoundsScreen> createState() =>
      _NotificationsSoundsScreenState();
}

class _NotificationsSoundsScreenState
    extends ConsumerState<NotificationsSoundsScreen> {
  final _preview = NotificationSoundPreview();
  final _notifications = localNotificationService;
  bool _ready = false;

  static const _categories = <(String, IconData)>[
    ('task_reminders', Icons.event_note_outlined),
    ('scheduled_starts', Icons.schedule_outlined),
    ('overdue_tasks', Icons.notification_important_outlined),
    ('focus_completed', Icons.timer_outlined),
    ('short_break_completed', Icons.free_breakfast_outlined),
    ('long_break_completed', Icons.self_improvement_outlined),
    ('roadmaps', Icons.route_outlined),
    ('activity_review', Icons.insights_outlined),
    ('coaching', Icons.psychology_outlined),
    ('sleep_health', Icons.health_and_safety_outlined),
    ('synchronization', Icons.sync_outlined),
    ('security', Icons.security_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _notifications.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Map<String, Object?> _preferences(String encoded) {
    try {
      return Map<String, Object?>.from(jsonDecode(encoded) as Map);
    } catch (_) {
      return {for (final category in _categories) category.$1: true};
    }
  }

  Future<void> _update(Map<String, Object?> current, String key, Object value) {
    return ref.read(settingsRepositoryProvider).updateNotificationPreferences({
      ...current,
      key: value,
    });
  }

  Future<void> _openSystemSettings(
    String localeCode, {
    String category = 'task_reminders',
    NotificationSoundChoice sound = const NotificationSoundChoice(
      key: 'system',
    ),
    bool vibration = true,
  }) async {
    if (Platform.isAndroid) {
      await _notifications.openAndroidSystemSoundSettings(
        category: category,
        sound: sound,
        vibration: vibration,
        localeCode: localeCode,
      );
      return;
    }
    if (Platform.isWindows) {
      await Process.start('explorer.exe', const ['ms-settings:notifications']);
    }
  }

  Future<void> _pickDeviceSound({
    required Map<String, Object?> preferences,
    required String category,
    required String type,
  }) async {
    final sound = await _notifications.pickAndroidSystemSound(type: type);
    if (sound == null) return;
    await _update(preferences, '${category}_sound', sound.key);
    await _preview.play(sound);
  }

  String _soundLabel(BuildContext context, NotificationSoundChoice choice) {
    if (choice.deviceLabel != null) {
      return context.l10n.format('sound_device_selected', {
        'name': choice.deviceLabel!,
      });
    }
    return context.l10n.text('sound_${choice.key}');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final preferences = _preferences(settings.notificationPreferencesJson);
    final capabilities = notificationPlatformCapabilities(
      Theme.of(context).platform,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('notifications_and_sounds')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('notification_sound'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<NotificationSoundChoice>(
                          isExpanded: true,
                          initialValue: NotificationSounds.byKey(
                            settings.notificationSoundKey,
                          ),
                          items: [
                            for (final choice in NotificationSounds.choices)
                              DropdownMenuItem(
                                value: choice,
                                child: Text(
                                  context.l10n.text('sound_${choice.key}'),
                                  overflow: TextOverflow.ellipsis,
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
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: context.l10n.text('preview_sound'),
                        onPressed: () => _preview.play(
                          NotificationSounds.byKey(
                            settings.notificationSoundKey,
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow),
                      ),
                      IconButton.outlined(
                        tooltip: context.l10n.text('stop_sound_preview'),
                        onPressed: _preview.stop,
                        icon: const Icon(Icons.stop),
                      ),
                    ],
                  ),
                  if (capabilities.supportsVibration)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: preferences['vibration'] as bool? ?? true,
                      title: Text(context.l10n.text('vibration')),
                      onChanged: (value) =>
                          _update(preferences, 'vibration', value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final category in _categories) ...[
            _CategoryCard(
              category: category.$1,
              icon: category.$2,
              enabled: NotificationSounds.categoryEnabled(
                preferencesJson: settings.notificationPreferencesJson,
                category: category.$1,
              ),
              vibration: NotificationSounds.vibrationForCategory(
                preferencesJson: settings.notificationPreferencesJson,
                category: category.$1,
              ),
              selectedSound: NotificationSounds.forCategory(
                preferencesJson: settings.notificationPreferencesJson,
                category: category.$1,
                fallbackKey: settings.notificationSoundKey,
              ),
              ready: _ready,
              showVibration: capabilities.supportsVibration,
              soundLabel: (choice) => _soundLabel(context, choice),
              onEnabledChanged: (value) =>
                  _update(preferences, category.$1, value),
              onVibrationChanged: (value) =>
                  _update(preferences, '${category.$1}_vibration', value),
              onSoundChanged: (choice) async {
                await _update(preferences, '${category.$1}_sound', choice.key);
                await _preview.play(choice);
              },
              onPickDeviceSound: capabilities.supportsDeviceSoundPicker
                  ? (type) => _pickDeviceSound(
                      preferences: preferences,
                      category: category.$1,
                      type: type,
                    )
                  : null,
              onPreview: _preview.play,
              onStopPreview: _preview.stop,
              onTest: () async {
                try {
                  await _notifications.requestPermission();
                  final selected = NotificationSounds.forCategory(
                    preferencesJson: settings.notificationPreferencesJson,
                    category: category.$1,
                    fallbackKey: settings.notificationSoundKey,
                  );
                  final vibration = NotificationSounds.vibrationForCategory(
                    preferencesJson: settings.notificationPreferencesJson,
                    category: category.$1,
                  );
                  final verification = await _notifications.showTest(
                    selected,
                    category: category.$1,
                    vibration: vibration,
                    localeCode: settings.localeCode,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.l10n.text(
                          verification.matches
                              ? 'notification_test_verified'
                              : 'notification_test_sound_mismatch',
                        ),
                      ),
                    ),
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.l10n.text('notification_test_failed'),
                      ),
                    ),
                  );
                }
              },
              onOpenSystemSettings: () => _openSystemSettings(
                settings.localeCode,
                category: category.$1,
                sound: NotificationSounds.forCategory(
                  preferencesJson: settings.notificationPreferencesJson,
                  category: category.$1,
                  fallbackKey: settings.notificationSoundKey,
                ),
                vibration: NotificationSounds.vibrationForCategory(
                  preferencesJson: settings.notificationPreferencesJson,
                  category: category.$1,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            child: ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(context.l10n.text('quiet_hours')),
              subtitle: Text(
                context.l10n.format('quiet_hours_value', {
                  'start': _time(settings.quietStartMinutes),
                  'end': _time(settings.quietEndMinutes),
                }),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ScheduleWellbeingScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (capabilities.supportsNotificationSettings)
            OutlinedButton.icon(
              onPressed: () => _openSystemSettings(
                settings.localeCode,
                sound: NotificationSounds.byKey(settings.notificationSoundKey),
                vibration: preferences['vibration'] as bool? ?? true,
              ),
              icon: Icon(
                capabilities.supportsDeviceSoundPicker
                    ? Icons.android
                    : Icons.desktop_windows,
              ),
              label: Text(context.l10n.text('open_system_settings')),
            ),
        ],
      ),
    );
  }

  String _time(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.icon,
    required this.enabled,
    required this.vibration,
    required this.selectedSound,
    required this.ready,
    required this.showVibration,
    required this.soundLabel,
    required this.onEnabledChanged,
    required this.onVibrationChanged,
    required this.onSoundChanged,
    required this.onPreview,
    required this.onStopPreview,
    required this.onTest,
    required this.onOpenSystemSettings,
    this.onPickDeviceSound,
  });

  final String category;
  final IconData icon;
  final bool enabled;
  final bool vibration;
  final NotificationSoundChoice selectedSound;
  final bool ready;
  final bool showVibration;
  final String Function(NotificationSoundChoice) soundLabel;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onVibrationChanged;
  final ValueChanged<NotificationSoundChoice> onSoundChanged;
  final Future<void> Function(String type)? onPickDeviceSound;
  final ValueChanged<NotificationSoundChoice> onPreview;
  final VoidCallback onStopPreview;
  final Future<void> Function() onTest;
  final Future<void> Function() onOpenSystemSettings;

  @override
  Widget build(BuildContext context) {
    final sounds = <NotificationSoundChoice>[
      if (selectedSound.isDeviceSound) selectedSound,
      ...NotificationSounds.choices,
    ];
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(context.l10n.text('notification_category_$category')),
        subtitle: Text(
          enabled
              ? context.l10n.text('enabled')
              : context.l10n.text('disabled'),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            title: Text(context.l10n.text('notifications')),
            onChanged: onEnabledChanged,
          ),
          if (showVibration)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: vibration,
              title: Text(context.l10n.text('vibration')),
              onChanged: onVibrationChanged,
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<NotificationSoundChoice>(
            isExpanded: true,
            initialValue: selectedSound,
            decoration: InputDecoration(
              labelText: context.l10n.text('notification_sound'),
            ),
            items: [
              for (final choice in sounds)
                DropdownMenuItem(
                  value: choice,
                  child: Text(
                    soundLabel(choice),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (choice) {
              if (choice != null) onSoundChanged(choice);
            },
          ),
          if (onPickDeviceSound != null) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.text('device_sound_sources'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onPickDeviceSound!('notification'),
                  child: Text(context.l10n.text('device_notification_sounds')),
                ),
                OutlinedButton(
                  onPressed: () => onPickDeviceSound!('alarm'),
                  child: Text(context.l10n.text('device_alarm_sounds')),
                ),
                OutlinedButton(
                  onPressed: () => onPickDeviceSound!('ringtone'),
                  child: Text(context.l10n.text('device_ringtone_sounds')),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onPreview(selectedSound),
                icon: const Icon(Icons.play_arrow),
                label: Text(context.l10n.text('preview_sound')),
              ),
              OutlinedButton.icon(
                onPressed: onStopPreview,
                icon: const Icon(Icons.stop),
                label: Text(context.l10n.text('stop_sound_preview')),
              ),
              FilledButton.tonalIcon(
                onPressed: ready ? onTest : null,
                icon: const Icon(Icons.notification_add_outlined),
                label: Text(context.l10n.text('send_test_notification')),
              ),
              OutlinedButton.icon(
                onPressed: onOpenSystemSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(context.l10n.text('open_system_settings')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
