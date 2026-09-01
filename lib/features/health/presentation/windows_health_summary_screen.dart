import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/synced_health_overview.dart';

class WindowsHealthSummaryScreen extends ConsumerWidget {
  const WindowsHealthSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('health_and_rest'))),
      body: StreamBuilder<List<LocalEntityRecord>>(
        stream: entities.watch(entityType: 'health_summaries'),
        builder: (context, snapshot) {
          final overview = SyncedHealthOverview.fromEntries(
            (snapshot.data ?? const <LocalEntityRecord>[]).map((record) {
              final data = entities.decode(record);
              return _entryFromRecord(record, data);
            }).whereType<SyncedHealthEntry>(),
          );
          if (overview == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.l10n.text('health_stale'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _WindowsHealthDashboard(overview: overview);
        },
      ),
    );
  }

  SyncedHealthEntry? _entryFromRecord(
    LocalEntityRecord record,
    Map<String, dynamic> data,
  ) {
    final type = data['summary_type'] as String?;
    final value = data['value'];
    final summaryDate = DateTime.tryParse(
      data['summary_date'] as String? ?? '',
    );
    if (type == null || value is! num || summaryDate == null) return null;
    final sourceUpdatedAt = DateTime.tryParse(
      data['last_updated_at'] as String? ?? '',
    );
    return SyncedHealthEntry(
      summaryDate: summaryDate.toLocal(),
      updatedAt: (sourceUpdatedAt ?? record.updatedAt).toLocal(),
      type: type,
      value: value,
      source: data['source'] as String? ?? '',
    );
  }
}

class _WindowsHealthDashboard extends StatelessWidget {
  const _WindowsHealthDashboard({required this.overview});

  final SyncedHealthOverview overview;

  @override
  Widget build(BuildContext context) {
    final locale = context.l10n.locale.toLanguageTag();
    final source = overview.source.isEmpty
        ? context.l10n.text('health_android_phone')
        : overview.source;
    final latest = DateFormat.yMMMd(
      locale,
    ).add_jm().format(overview.updatedAt.toLocal());
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _SyncedStatusCard(source: source, latest: latest),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final hero = _TodayHealthCard(overview: overview, locale: locale);
            final weekly = _WindowsWeeklyStepsCard(
              overview: overview,
              locale: locale,
            );
            if (!wide) {
              return Column(
                children: [hero, const SizedBox(height: 14), weekly],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: hero),
                  const SizedBox(width: 14),
                  Expanded(child: weekly),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 920
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: width,
                  child: _WindowsMetricCard(
                    icon: Icons.favorite_rounded,
                    accent: Colors.redAccent,
                    label: context.l10n.text('health_average_heart_rate'),
                    value: formatSyncedHealthNumber(
                      'average_heart_rate',
                      overview.value('average_heart_rate'),
                      locale: locale,
                    ),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _WindowsMetricCard(
                    icon: Icons.bedtime_rounded,
                    accent: Colors.deepPurpleAccent,
                    label: context.l10n.text('health_sleep'),
                    value: _sleepValue(context),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _WindowsMetricCard(
                    icon: Icons.update_rounded,
                    accent: Theme.of(context).colorScheme.primary,
                    label: context.l10n.text('health_latest_record'),
                    value: DateFormat.Hm(locale).format(overview.updatedAt),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.text('health_windows_privacy_detail'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _sleepValue(BuildContext context) {
    final value = overview.value('sleep_duration');
    if (value == null) return '—';
    return context.l10n.duration(Duration(minutes: value.round()));
  }
}

class _SyncedStatusCard extends StatelessWidget {
  const _SyncedStatusCard({required this.source, required this.latest});

  final String source;
  final String latest;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer.withValues(alpha: 0.42),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.14),
              ),
              child: Icon(Icons.phone_android_rounded, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('health_updated_from_android'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('$source · $latest'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayHealthCard extends StatelessWidget {
  const _TodayHealthCard({required this.overview, required this.locale});

  final SyncedHealthOverview overview;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final steps = overview.value('steps');
    final todayWorkouts = overview.value('exercise_sessions');
    final workoutValue =
        todayWorkouts ??
        (overview.weeklyWorkoutCount > 0 ? overview.weeklyWorkoutCount : null);
    final workoutText = workoutValue == null
        ? '—'
        : '${formatSyncedHealthNumber('exercise_sessions', workoutValue, locale: locale)}${todayWorkouts == null ? ' ${context.l10n.text('health_this_week')}' : ''}';
    return Card(
      clipBehavior: Clip.antiAlias,
      color: colors.primaryContainer.withValues(alpha: 0.62),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.text('health_recent_context'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.75),
                      width: 9,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_walk_rounded,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatSyncedHealthNumber(
                          'steps',
                          steps,
                          locale: locale,
                        ),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(context.l10n.text('health_steps')),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      _CompactMetricRow(
                        icon: Icons.route_rounded,
                        label: context.l10n.text('health_distance'),
                        value: formatSyncedHealthNumber(
                          'distance',
                          overview.value('distance'),
                          locale: locale,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CompactMetricRow(
                        icon: Icons.local_fire_department_rounded,
                        label: context.l10n.text('health_active_energy'),
                        value: formatSyncedHealthNumber(
                          'active_calories',
                          overview.value('active_calories'),
                          locale: locale,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CompactMetricRow(
                        icon: Icons.fitness_center_rounded,
                        label: context.l10n.text('health_workouts'),
                        value: workoutText,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactMetricRow extends StatelessWidget {
  const _CompactMetricRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _WindowsWeeklyStepsCard extends StatelessWidget {
  const _WindowsWeeklyStepsCard({required this.overview, required this.locale});

  final SyncedHealthOverview overview;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final byDay = {
      for (final entry in overview.weeklySteps)
        DateFormat('yyyy-MM-dd').format(entry.summaryDate): entry.value,
    };
    final days = List.generate(
      7,
      (index) => overview.date.subtract(Duration(days: 6 - index)),
    );
    final values = [
      for (final day in days)
        (byDay[DateFormat('yyyy-MM-dd').format(day)] ?? 0).toDouble(),
    ];
    final maxValue = math.max(1.0, values.fold<double>(0, math.max));
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.text('health_weekly_steps'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(context.l10n.text('health_weekly_steps_detail')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NumberFormat.compact(locale: locale).format(total),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(context.l10n.text('health_steps')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 148,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < days.length; index++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: values[index] == 0
                                      ? 0.035
                                      : math.max(
                                          0.12,
                                          values[index] / maxValue,
                                        ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: index == days.length - 1
                                          ? colors.tertiary
                                          : colors.primary.withValues(
                                              alpha: 0.72,
                                            ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(DateFormat.E(locale).format(days[index])),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowsMetricCard extends StatelessWidget {
  const _WindowsMetricCard({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(label),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
