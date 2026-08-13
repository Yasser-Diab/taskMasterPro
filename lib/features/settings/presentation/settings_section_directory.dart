import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../data/settings_section_catalog.dart';

class SettingsSectionDirectory extends StatelessWidget {
  const SettingsSectionDirectory({required this.onSelected, super.key});

  final ValueChanged<String> onSelected;

  static IconData iconFor(String key) => switch (key) {
    'profile_and_account' => Icons.manage_accounts_outlined,
    'schedule_wellbeing' => Icons.bedtime_outlined,
    'tasks_and_execution' => Icons.task_alt_outlined,
    'pomodoro' => Icons.timer_outlined,
    'activity_and_privacy' => Icons.shield_outlined,
    'privacy_and_vault' => Icons.password_outlined,
    'notifications_and_sounds' => Icons.notifications_outlined,
    'health' => Icons.health_and_safety_outlined,
    'coaching' => Icons.explore_outlined,
    'reports' => Icons.assessment_outlined,
    'appearance' => Icons.palette_outlined,
    'synchronization' => Icons.sync_outlined,
    'connected_devices' => Icons.devices_outlined,
    'help_and_diagnostics' => Icons.help_outline,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.text('settings_sections'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(context.l10n.text('settings_sections_description')),
            const SizedBox(height: 8),
            for (
              var index = 0;
              index < settingsSectionOrderKeys.length;
              index++
            ) ...[
              if (index > 0) const Divider(height: 1),
              ListTile(
                key: ValueKey(
                  'settings-section-${settingsSectionOrderKeys[index]}',
                ),
                contentPadding: EdgeInsets.zero,
                minTileHeight: 48,
                leading: Icon(iconFor(settingsSectionOrderKeys[index])),
                title: Text(context.l10n.text(settingsSectionOrderKeys[index])),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onSelected(settingsSectionOrderKeys[index]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
