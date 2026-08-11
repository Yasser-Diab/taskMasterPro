import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';

class TaskHealthEvidenceSummary {
  const TaskHealthEvidenceSummary({
    this.steps,
    this.distanceMeters,
    this.averageHeartRate,
    this.activeCalories,
    this.sources = const {},
    this.updatedAt,
    this.hasEstimatedValues = false,
  });

  final int? steps;
  final double? distanceMeters;
  final double? averageHeartRate;
  final double? activeCalories;
  final Set<String> sources;
  final DateTime? updatedAt;
  final bool hasEstimatedValues;

  bool get hasData =>
      steps != null ||
      distanceMeters != null ||
      averageHeartRate != null ||
      activeCalories != null;

  factory TaskHealthEvidenceSummary.fromRecords(
    Iterable<LocalEntityRecord> records,
  ) {
    final latestBySessionMetric =
        <String, (LocalEntityRecord, Map<String, Object?>)>{};
    for (final record in records) {
      if (record.deletedAt != null ||
          record.entityType != 'task_health_summaries') {
        continue;
      }
      final data = _decode(record.dataJson);
      final metric =
          data['metric_type'] as String? ?? data['summary_type'] as String?;
      if (metric == null) continue;
      final recordCount = (data['record_count'] as num?)?.toInt();
      final value = (data['value'] as num?)?.toDouble();
      if ((recordCount != null && recordCount <= 0) ||
          value == null ||
          value <= 0) {
        continue;
      }
      final session =
          data['execution_session_id'] as String? ??
          record.secondaryParentId ??
          record.id;
      final key = '$session:$metric';
      final existing = latestBySessionMetric[key];
      if (existing == null || record.updatedAt.isAfter(existing.$1.updatedAt)) {
        latestBySessionMetric[key] = (record, data);
      }
    }

    var steps = 0.0;
    var distance = 0.0;
    var calories = 0.0;
    var heartRateTotal = 0.0;
    var heartRateWeight = 0;
    var hasSteps = false;
    var hasDistance = false;
    var hasCalories = false;
    var hasHeartRate = false;
    var estimated = false;
    DateTime? updatedAt;
    final sources = <String>{};

    for (final entry in latestBySessionMetric.values) {
      final record = entry.$1;
      final data = entry.$2;
      final metric =
          data['metric_type'] as String? ?? data['summary_type'] as String?;
      final value = (data['value'] as num).toDouble();
      final count = ((data['record_count'] as num?)?.toInt() ?? 1).clamp(
        1,
        1 << 30,
      );
      switch (metric) {
        case 'steps':
          steps += value;
          hasSteps = true;
        case 'distance':
          distance += value;
          hasDistance = true;
        case 'active_calories':
          calories += value;
          hasCalories = true;
        case 'average_heart_rate':
          heartRateTotal += value * count;
          heartRateWeight += count;
          hasHeartRate = true;
      }
      estimated = estimated || data['estimated'] == true;
      final applications = data['source_applications'];
      if (applications is List) {
        sources.addAll(
          applications
              .whereType<String>()
              .map((source) => source.trim())
              .where((source) => source.isNotEmpty),
        );
      }
      final source = data['source'] as String?;
      if (source != null && source.trim().isNotEmpty) {
        sources.addAll(
          source
              .split(',')
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty),
        );
      }
      final dataUpdatedAt = DateTime.tryParse(
        data['last_updated_at'] as String? ?? '',
      );
      final candidate = dataUpdatedAt ?? record.updatedAt;
      if (updatedAt == null || candidate.isAfter(updatedAt)) {
        updatedAt = candidate;
      }
    }

    return TaskHealthEvidenceSummary(
      steps: hasSteps ? steps.round() : null,
      distanceMeters: hasDistance ? distance : null,
      averageHeartRate: hasHeartRate && heartRateWeight > 0
          ? heartRateTotal / heartRateWeight
          : null,
      activeCalories: hasCalories ? calories : null,
      sources: Set.unmodifiable(sources),
      updatedAt: updatedAt,
      hasEstimatedValues: estimated,
    );
  }
}

class TaskHealthEvidenceStrip extends ConsumerWidget {
  const TaskHealthEvidenceStrip({
    required this.taskId,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final String taskId;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: ref
          .watch(entityRecordRepositoryProvider)
          .watch(entityType: 'task_health_summaries', parentId: taskId),
      builder: (context, snapshot) {
        final summary = TaskHealthEvidenceSummary.fromRecords(
          snapshot.data ?? const <LocalEntityRecord>[],
        );
        if (!summary.hasData) return const SizedBox.shrink();
        final locale = Localizations.localeOf(context).toLanguageTag();
        final number = NumberFormat.decimalPattern(locale);
        final compact = NumberFormat.compact(locale: locale);
        final metrics = <(IconData, String, String)>[
          if (summary.steps case final steps?)
            (
              Icons.directions_walk,
              context.l10n.text('health_steps'),
              compact.format(steps),
            ),
          if (summary.distanceMeters case final meters?)
            (
              Icons.route_outlined,
              context.l10n.text('health_distance'),
              _distance(meters, number, summary.hasEstimatedValues),
            ),
          if (summary.averageHeartRate case final heartRate?)
            (
              Icons.favorite_border,
              context.l10n.text('health_average_heart_rate'),
              '${number.format(heartRate.round())} bpm',
            ),
          if (summary.activeCalories case final calories?)
            (
              Icons.local_fire_department_outlined,
              context.l10n.text('health_active_energy'),
              '${number.format(calories.round())} kcal',
            ),
        ];
        final sourceText = summary.sources.take(3).join(' · ');
        return Semantics(
          container: true,
          label: [
            context.l10n.text('health_recent_context'),
            for (final metric in metrics) '${metric.$2}: ${metric.$3}',
            if (sourceText.isNotEmpty) sourceText,
          ].join('. '),
          child: Container(
            margin: margin,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .54),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .72),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.health_and_safety_outlined,
                      size: 17,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.l10n.text('health_recent_context'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final metric in metrics)
                      Tooltip(
                        message: metric.$2,
                        child: Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(metric.$1, size: 15),
                          label: Text(metric.$3),
                        ),
                      ),
                  ],
                ),
                if (sourceText.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    sourceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

String _distance(double meters, NumberFormat number, bool estimated) {
  final prefix = estimated ? '~' : '';
  if (meters < 1000) return '$prefix${number.format(meters.round())} m';
  return '$prefix${(meters / 1000).toStringAsFixed(2)} km';
}

Map<String, Object?> _decode(String raw) {
  try {
    final value = jsonDecode(raw);
    return value is Map
        ? value.map((key, item) => MapEntry('$key', item))
        : const <String, Object?>{};
  } catch (_) {
    return const <String, Object?>{};
  }
}
