import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../health/presentation/health_connect_screen.dart';

class ScheduleWellbeingScreen extends ConsumerWidget {
  const ScheduleWellbeingScreen({this.coachingOnly = false, super.key});

  final bool coachingOnly;

  TimeOfDay _time(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required int initial,
    required void Function(int value) save,
  }) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _time(initial),
    );
    if (selected != null) save(selected.hour * 60 + selected.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repository = ref.read(settingsRepositoryProvider);
    final workingDays =
        ((jsonDecode(settings.workingDaysJson) as List?) ??
                const [1, 2, 3, 4, 5])
            .whereType<num>()
            .map((value) => value.toInt())
            .toSet();
    final dayLabels = [
      context.l10n.text('weekday_mon'),
      context.l10n.text('weekday_tue'),
      context.l10n.text('weekday_wed'),
      context.l10n.text('weekday_thu'),
      context.l10n.text('weekday_fri'),
      context.l10n.text('weekday_sat'),
      context.l10n.text('weekday_sun'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.text(coachingOnly ? 'coaching' : 'schedule_wellbeing'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!coachingOnly)
            _Section(
              title: context.l10n.text('schedule_daily_rhythm'),
              icon: Icons.wb_twilight_outlined,
              children: [
                _TimeTile(
                  title: context.l10n.text('schedule_wake_time'),
                  value: _time(settings.wakeTimeMinutes).format(context),
                  onTap: () => _pick(
                    context,
                    ref,
                    initial: settings.wakeTimeMinutes,
                    save: (value) => repository.updateScheduleAndWellbeing(
                      wakeTimeMinutes: value,
                    ),
                  ),
                ),
                _TimeTile(
                  title: context.l10n.text('schedule_sleep_time'),
                  value: _time(settings.sleepTimeMinutes).format(context),
                  onTap: () => _pick(
                    context,
                    ref,
                    initial: settings.sleepTimeMinutes,
                    save: (value) => repository.updateScheduleAndWellbeing(
                      sleepTimeMinutes: value,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.text('schedule_working_days'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (var index = 0; index < dayLabels.length; index++)
                      FilterChip(
                        selected: workingDays.contains(index + 1),
                        label: Text(dayLabels[index]),
                        onSelected: (selected) {
                          final next = {...workingDays};
                          selected
                              ? next.add(index + 1)
                              : next.remove(index + 1);
                          repository.updateScheduleAndWellbeing(
                            workingDays: next.toList()..sort(),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _TimeTile(
                  title: context.l10n.text('schedule_work_starts'),
                  value: _time(settings.workStartMinutes).format(context),
                  onTap: () => _pick(
                    context,
                    ref,
                    initial: settings.workStartMinutes,
                    save: (value) => repository.updateScheduleAndWellbeing(
                      workStartMinutes: value,
                    ),
                  ),
                ),
                _TimeTile(
                  title: context.l10n.text('schedule_work_ends'),
                  value: _time(settings.workEndMinutes).format(context),
                  onTap: () => _pick(
                    context,
                    ref,
                    initial: settings.workEndMinutes,
                    save: (value) => repository.updateScheduleAndWellbeing(
                      workEndMinutes: value,
                    ),
                  ),
                ),
                _TimeTile(
                  title: context.l10n.text('schedule_quiet_starts'),
                  value: _time(settings.quietStartMinutes).format(context),
                  onTap: () => _pick(
                    context,
                    ref,
                    initial: settings.quietStartMinutes,
                    save: (value) => repository.updateScheduleAndWellbeing(
                      quietStartMinutes: value,
                    ),
                  ),
                ),
                _TimeTile(
                  title: context.l10n.text('schedule_quiet_ends'),
                  value: _time(settings.quietEndMinutes).format(context),
                  onTap: () => _pick(
                    context,
                    ref,
                    initial: settings.quietEndMinutes,
                    save: (value) => repository.updateScheduleAndWellbeing(
                      quietEndMinutes: value,
                    ),
                  ),
                ),
              ],
            ),
          if (!coachingOnly) const SizedBox(height: 16),
          _Section(
            title: context.l10n.text('schedule_rest_coaching'),
            icon: Icons.bedtime_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.sleepReminderEnabled,
                title: Text(context.l10n.text('schedule_sleep_reminder')),
                subtitle: Text(
                  context.l10n.text('schedule_sleep_reminder_description'),
                ),
                onChanged: (value) => repository.updateScheduleAndWellbeing(
                  sleepReminderEnabled: value,
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: settings.sleepReminderOffsetMinutes,
                decoration: InputDecoration(
                  labelText: context.l10n.text('schedule_reminder_offset'),
                ),
                items: [
                  for (final minutes in const [15, 30, 45])
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(
                        context.l10n.format('duration_minutes', {
                          'count': minutes,
                        }),
                      ),
                    ),
                  DropdownMenuItem(
                    value: 60,
                    child: Text(context.l10n.text('duration_hour')),
                  ),
                ],
                onChanged: (value) => repository.updateScheduleAndWellbeing(
                  sleepReminderOffsetMinutes: value,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.phoneUsageAnalysisEnabled,
                title: Text(context.l10n.text('schedule_phone_analysis')),
                subtitle: Text(
                  context.l10n.text('schedule_phone_analysis_description'),
                ),
                onChanged: (value) => repository.updateScheduleAndWellbeing(
                  phoneUsageAnalysisEnabled: value,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: settings.coachingTone,
                decoration: InputDecoration(
                  labelText: context.l10n.text('coaching_tone'),
                  prefixIcon: const Icon(Icons.record_voice_over_outlined),
                ),
                items: [
                  for (final tone in const [
                    'gentle',
                    'balanced',
                    'direct',
                    'detailed',
                  ])
                    DropdownMenuItem(
                      value: tone,
                      child: Text(context.l10n.text('coaching_tone_$tone')),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) repository.updateCoachingTone(value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: settings.coachingSensitivity,
                decoration: InputDecoration(
                  labelText: context.l10n.text('schedule_coaching_sensitivity'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'quiet',
                    child: Text(context.l10n.text('coaching_quiet')),
                  ),
                  DropdownMenuItem(
                    value: 'standard',
                    child: Text(context.l10n.text('coaching_standard')),
                  ),
                  DropdownMenuItem(
                    value: 'active',
                    child: Text(context.l10n.text('coaching_active')),
                  ),
                  DropdownMenuItem(
                    value: 'persistent',
                    child: Text(context.l10n.text('coaching_persistent')),
                  ),
                ],
                onChanged: (value) => repository.updateScheduleAndWellbeing(
                  coachingSensitivity: value,
                ),
              ),
            ],
          ),
          if (!coachingOnly && Platform.isAndroid) ...[
            const SizedBox(height: 16),
            _Section(
              title: context.l10n.text('health_data'),
              icon: Icons.health_and_safety_outlined,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.text('health_connected_sources')),
                  subtitle: Text(
                    context.l10n.text('health_connected_sources_description'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const HealthConnectScreen(),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.healthSummarySyncEnabled,
                  title: Text(context.l10n.text('health_sync_summaries')),
                  subtitle: Text(
                    context.l10n.text('health_sync_summaries_description'),
                  ),
                  onChanged: (value) => repository.updateScheduleAndWellbeing(
                    healthSummarySyncEnabled: value,
                  ),
                ),
              ],
            ),
          ],
          if (!coachingOnly) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(context.l10n.text('schedule_health_disclaimer')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

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
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: TextButton(onPressed: onTap, child: Text(value)),
      onTap: onTap,
    );
  }
}
