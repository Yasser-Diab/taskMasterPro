import 'dart:convert';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import 'task_repository.dart';

class RecurrenceService {
  RecurrenceService({
    required this.database,
    required this.entities,
    required this.tasks,
  });

  final AppDatabase database;
  final EntityRecordRepository entities;
  final TaskRepository tasks;

  Future<int> generateUpcoming({int horizonDays = 60}) async {
    final rules = await entities.list(entityType: 'recurrence_rules');
    if (rules.isEmpty) return 0;
    final existing = await (database.select(
      database.localTasks,
    )..where((row) => row.deletedAt.isNull())).get();
    final knownKeys = <String>{
      for (final task in existing)
        if (task.templateId != null && task.occurrenceKey != null)
          '${task.templateId}:${task.occurrenceKey}',
    };
    final todayValue = DateTime.now();
    final today = DateTime(todayValue.year, todayValue.month, todayValue.day);
    final horizon = today.add(Duration(days: horizonDays));
    var generated = 0;

    for (final rule in rules) {
      if (rule.status == 'paused' || rule.status == 'archived') continue;
      final ruleRow = entities.decode(rule);
      final nestedRule = ruleRow['rule_data'] is Map
          ? Map<String, Object?>.from(ruleRow['rule_data'] as Map)
          : <String, Object?>{};
      final templateId =
          rule.parentId ??
          nestedRule['template_id'] as String? ??
          ruleRow['template_id'] as String?;
      if (templateId == null) continue;
      final template = await entities.get(templateId);
      if (template == null) continue;
      final templateRow = entities.decode(template);
      final sourceTaskId =
          nestedRule['source_task_occurrence_id'] as String? ??
          templateRow['source_task_occurrence_id'] as String? ??
          (templateRow['data'] is Map
              ? (templateRow['data'] as Map)['source_task_occurrence_id']
                    as String?
              : null);
      final source = sourceTaskId == null
          ? null
          : await tasks.getTask(sourceTaskId);
      final frequency =
          ruleRow['frequency'] as String? ??
          nestedRule['frequency'] as String? ??
          'daily';
      final interval =
          (ruleRow['interval_value'] as num?)?.toInt() ??
          (nestedRule['interval_value'] as num?)?.toInt() ??
          1;
      final startsOn = _date(ruleRow['starts_on'] ?? nestedRule['starts_on']);
      if (startsOn == null) continue;
      final endsOn = _date(ruleRow['ends_on'] ?? nestedRule['ends_on']);
      final weekdays = <int>{
        ..._integerList(ruleRow['weekdays']),
        ..._integerList(nestedRule['weekdays']),
      };
      final localTime =
          nestedRule['local_time'] as String? ??
          ruleRow['local_time'] as String?;
      var cursor = startsOn.isAfter(today) ? startsOn : today;
      while (!cursor.isAfter(horizon) &&
          (endsOn == null || !cursor.isAfter(endsOn))) {
        if (_matches(
          date: cursor,
          startsOn: startsOn,
          frequency: frequency,
          interval: interval,
          weekdays: weekdays,
        )) {
          final occurrenceKey = _dateOnly(cursor);
          final dedupeKey = '$templateId:$occurrenceKey';
          if (!knownKeys.contains(dedupeKey)) {
            final durationMs =
                (templateRow['default_duration_ms'] as num?)?.toInt() ??
                source?.estimatedDurationMs ??
                1800000;
            final plannedStart = _combine(cursor, localTime);
            final executionSettings = templateRow['execution_settings'] is Map
                ? Map<String, Object?>.from(
                    templateRow['execution_settings'] as Map,
                  )
                : source == null
                ? <String, Object?>{}
                : _configuration(source.dataJson);
            await tasks.createTask(
              TaskDraft(
                title:
                    templateRow['title'] as String? ??
                    source?.title ??
                    template.title,
                description:
                    templateRow['description'] as String? ??
                    source?.description ??
                    '',
                domainId:
                    templateRow['domain_id'] as String? ?? source?.domainId,
                priority:
                    (templateRow['priority'] as num?)?.toInt() ??
                    source?.priority ??
                    2,
                executionMode:
                    templateRow['execution_mode'] as String? ??
                    source?.executionMode ??
                    'manual',
                scheduledDate: cursor,
                plannedStart: plannedStart,
                plannedEnd: plannedStart?.add(
                  Duration(milliseconds: durationMs),
                ),
                estimatedDuration: Duration(milliseconds: durationMs),
                roadmapId:
                    templateRow['roadmap_id'] as String? ?? source?.roadmapId,
                roadmapPhaseId:
                    templateRow['roadmap_phase_id'] as String? ??
                    source?.roadmapPhaseId,
                templateId: templateId,
                occurrenceKey: occurrenceKey,
                configuration: executionSettings,
              ),
            );
            knownKeys.add(dedupeKey);
            generated++;
          }
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return generated;
  }

  bool _matches({
    required DateTime date,
    required DateTime startsOn,
    required String frequency,
    required int interval,
    required Set<int> weekdays,
  }) {
    final safeInterval = interval < 1 ? 1 : interval;
    final days = date.difference(startsOn).inDays;
    return switch (frequency) {
      'daily' => days >= 0 && days % safeInterval == 0,
      'weekly' =>
        days >= 0 &&
            ((days ~/ 7) % safeInterval == 0) &&
            (weekdays.isEmpty
                ? date.weekday == startsOn.weekday
                : weekdays.contains(date.weekday)),
      'monthly' =>
        date.day == startsOn.day &&
            (((date.year - startsOn.year) * 12 + date.month - startsOn.month) %
                    safeInterval ==
                0),
      _ => false,
    };
  }

  DateTime? _date(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  List<int> _integerList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<num>().map((item) => item.toInt()).toList();
  }

  DateTime? _combine(DateTime day, String? localTime) {
    if (localTime == null) return null;
    final parts = localTime.split(':');
    if (parts.length != 2) return null;
    return DateTime(
      day.year,
      day.month,
      day.day,
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
    );
  }

  String _dateOnly(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  Map<String, Object?> _configuration(String value) {
    final decoded = jsonDecode(value);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{};
  }
}
