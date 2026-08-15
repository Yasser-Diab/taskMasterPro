import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';

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
          final records = snapshot.data ?? const [];
          if (records.isEmpty) {
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
          final latest = [...records]
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          final source =
              entities.decode(latest.first)['source'] as String? ??
              context.l10n.text('health_android_phone');
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: Text(context.l10n.text('health_updated_from_android')),
                  subtitle: Text(
                    '$source · ${DateFormat.yMMMd(context.l10n.locale.toLanguageTag()).add_jm().format(latest.first.updatedAt.toLocal())}',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: MediaQuery.sizeOf(context).width >= 760
                    ? 3
                    : MediaQuery.sizeOf(context).width >= 520
                    ? 2
                    : 1,
                childAspectRatio: 1.55,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (final record in latest.take(6))
                    _Metric(record: record, entities: entities),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    context.l10n.text('health_windows_privacy_detail'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.record, required this.entities});

  final LocalEntityRecord record;
  final EntityRecordRepository entities;

  @override
  Widget build(BuildContext context) {
    final data = entities.decode(record);
    final type = data['summary_type'] as String? ?? record.title;
    final value = data['value'];
    final unit = data['unit'] as String? ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon(type), color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(
              '$value $unit',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              context.l10n.text(switch (type) {
                'steps' => 'health_steps',
                'sleep_duration' => 'health_sleep',
                'distance' => 'health_distance',
                'active_calories' => 'health_active_energy',
                'exercise_sessions' => 'health_workouts',
                'average_heart_rate' => 'health_average_heart_rate',
                _ => 'health_data',
              }),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(String type) => switch (type) {
    'steps' => Icons.directions_walk,
    'sleep_duration' => Icons.bedtime_outlined,
    'distance' => Icons.route_outlined,
    'active_calories' => Icons.local_fire_department_outlined,
    'exercise_sessions' => Icons.fitness_center_outlined,
    'average_heart_rate' => Icons.favorite_border,
    _ => Icons.health_and_safety_outlined,
  };
}
