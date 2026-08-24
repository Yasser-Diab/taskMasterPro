import 'package:intl/intl.dart';

class SyncedHealthEntry {
  const SyncedHealthEntry({
    required this.summaryDate,
    required this.updatedAt,
    required this.type,
    required this.value,
    required this.source,
  });

  final DateTime summaryDate;
  final DateTime updatedAt;
  final String type;
  final num value;
  final String source;
}

class SyncedHealthOverview {
  const SyncedHealthOverview({
    required this.date,
    required this.updatedAt,
    required this.metrics,
    required this.weeklySteps,
    required this.source,
  });

  final DateTime date;
  final DateTime updatedAt;
  final Map<String, SyncedHealthEntry> metrics;
  final List<SyncedHealthEntry> weeklySteps;
  final String source;

  static SyncedHealthOverview? fromEntries(
    Iterable<SyncedHealthEntry> entries,
  ) {
    final all = entries.toList(growable: false);
    if (all.isEmpty) return null;

    final newestDate = all
        .map((entry) => _dateOnly(entry.summaryDate))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final currentMetrics = <String, SyncedHealthEntry>{};
    for (final entry in all.where(
      (entry) => _sameDay(entry.summaryDate, newestDate),
    )) {
      final existing = currentMetrics[entry.type];
      if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
        currentMetrics[entry.type] = entry;
      }
    }

    final stepsByDate = <DateTime, SyncedHealthEntry>{};
    for (final entry in all.where((entry) => entry.type == 'steps')) {
      final day = _dateOnly(entry.summaryDate);
      final existing = stepsByDate[day];
      if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
        stepsByDate[day] = entry;
      }
    }
    final firstVisibleDay = newestDate.subtract(const Duration(days: 6));
    final weeklySteps =
        stepsByDate.entries
            .where(
              (entry) =>
                  !entry.key.isBefore(firstVisibleDay) &&
                  !entry.key.isAfter(newestDate),
            )
            .map((entry) => entry.value)
            .toList(growable: false)
          ..sort((a, b) => a.summaryDate.compareTo(b.summaryDate));

    final updatedAt = currentMetrics.values
        .map((entry) => entry.updatedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final source = currentMetrics.values
        .map((entry) => entry.source.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    return SyncedHealthOverview(
      date: newestDate,
      updatedAt: updatedAt,
      metrics: Map.unmodifiable(currentMetrics),
      weeklySteps: List.unmodifiable(weeklySteps),
      source: source,
    );
  }

  num? value(String type) => metrics[type]?.value;
}

String formatSyncedHealthNumber(
  String type,
  num? value, {
  required String locale,
}) {
  if (value == null) return '—';
  return switch (type) {
    'steps' || 'exercise_sessions' => NumberFormat.decimalPattern(
      locale,
    ).format(value.round()),
    'distance' =>
      '${NumberFormat.decimalPattern(locale).format(value.round())} m',
    'active_calories' => '${NumberFormat('0', locale).format(value)} kcal',
    'average_heart_rate' => '${NumberFormat('0', locale).format(value)} bpm',
    _ => NumberFormat('0.#', locale).format(value),
  };
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
