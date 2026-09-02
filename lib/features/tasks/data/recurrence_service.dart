import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../domain/recurring_occurrence_identity.dart';
import '../domain/task_occurrence_policy.dart';
import '../domain/task_schedule_policy.dart';
import '../domain/vacation_period.dart';
import 'task_repository.dart';
import 'vacation_repository.dart';
import 'vacation_scheduling_service.dart';

class TaskRecurrenceDefinition {
  const TaskRecurrenceDefinition({
    required this.templateId,
    required this.ruleId,
    required this.frequency,
    required this.intervalValue,
    required this.weekdays,
    required this.startsOn,
    required this.endsOn,
    required this.localTime,
  });

  final String templateId;
  final String ruleId;
  final String frequency;
  final int intervalValue;
  final Set<int> weekdays;
  final DateTime startsOn;
  final DateTime? endsOn;
  final String? localTime;
}

class RecurrenceService {
  RecurrenceService({
    required this.database,
    required this.entities,
    required this.tasks,
    this.vacations,
    this.now,
  });

  final AppDatabase database;
  final EntityRecordRepository entities;
  final TaskRepository tasks;
  final VacationRepository? vacations;
  final DateTime Function()? now;
  Future<void> _generationTail = Future<void>.value();

  Future<TaskRecurrenceDefinition?> definitionForTask(LocalTask task) async {
    final templateId = task.templateId;
    if (templateId == null || templateId.isEmpty) return null;
    final template = await entities.get(templateId);
    if (template == null) return null;
    final templateData = entities.decode(template);
    final rule = await _ruleForTemplate(templateId, templateData);
    if (rule == null) return null;
    final data = entities.decode(rule);
    final nested = _map(data['rule_data']);
    final startsOn = _date(data['starts_on'] ?? nested['starts_on']);
    if (startsOn == null) return null;
    return TaskRecurrenceDefinition(
      templateId: templateId,
      ruleId: rule.id,
      frequency:
          data['frequency']?.toString() ??
          nested['frequency']?.toString() ??
          'daily',
      intervalValue:
          (data['interval_value'] as num?)?.toInt() ??
          (nested['interval_value'] as num?)?.toInt() ??
          1,
      weekdays: {
        ..._integerList(data['weekdays']),
        ..._integerList(nested['weekdays']),
      },
      startsOn: startsOn,
      endsOn: _date(data['ends_on'] ?? nested['ends_on']),
      localTime:
          nested['local_time']?.toString() ?? data['local_time']?.toString(),
    );
  }

  Future<void> saveSeries({
    required String taskId,
    required String frequency,
    required Set<int> weekdays,
    required DateTime startsOn,
    required DateTime? endsOn,
    required String? localTime,
  }) {
    final operation = _generationTail.then(
      (_) => _saveSeries(
        taskId: taskId,
        frequency: frequency,
        weekdays: weekdays,
        startsOn: startsOn,
        endsOn: endsOn,
        localTime: localTime,
      ),
    );
    _generationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _saveSeries({
    required String taskId,
    required String frequency,
    required Set<int> weekdays,
    required DateTime startsOn,
    required DateTime? endsOn,
    required String? localTime,
  }) async {
    var task = await tasks.getTask(taskId);
    if (task == null) return;
    var templateId = task.templateId;
    LocalEntityRecord? template;
    if (templateId != null) {
      template = await entities.get(templateId);
      if (template == null) templateId = null;
    }
    final taskConfiguration = _configuration(task.dataJson);
    if (template == null) {
      templateId = await entities.create(
        EntityRecordDraft(
          entityType: 'task_templates',
          parentId: taskId,
          title: task.title,
          data: _templateData(
            task: task,
            configuration: taskConfiguration,
            ruleId: null,
            previous: const {},
          ),
          syncPayload: _templatePayload(
            task: task,
            configuration: taskConfiguration,
            ruleId: null,
            previous: const {},
          ),
        ),
      );
      template = await entities.get(templateId);
    }
    if (template == null || templateId == null) return;

    final previousTemplateData = entities.decode(template);
    var rule = await _ruleForTemplate(templateId, previousTemplateData);
    final orderedWeekdays = weekdays.toList()..sort();
    final ruleData = <String, Object?>{
      if (rule != null) ...entities.decode(rule),
      'template_id': templateId,
      'source_task_occurrence_id': taskId,
      'frequency': frequency,
      'interval_value': 1,
      'weekdays': orderedWeekdays,
      'starts_on': _dateOnly(startsOn),
      'ends_on': endsOn == null ? null : _dateOnly(endsOn),
      'created_from_occurrence': true,
      'local_time': localTime,
      'user_managed': true,
      'rule_data': {
        ..._map(rule == null ? null : entities.decode(rule)['rule_data']),
        'template_id': templateId,
        'source_task_occurrence_id': taskId,
        'frequency': frequency,
        'interval_value': 1,
        'weekdays': orderedWeekdays,
        'starts_on': _dateOnly(startsOn),
        'ends_on': endsOn == null ? null : _dateOnly(endsOn),
        'created_from_occurrence': true,
        'local_time': localTime,
        'user_managed': true,
      },
    };
    final rulePayload = <String, Object?>{
      'frequency': frequency,
      'interval_value': 1,
      'weekdays': orderedWeekdays,
      'starts_on': _dateOnly(startsOn),
      'ends_on': endsOn == null ? null : _dateOnly(endsOn),
      'maximum_occurrences': null,
      'paused_at': null,
      'rule_data': ruleData['rule_data'],
    };
    late final String ruleId;
    if (rule == null) {
      ruleId = await entities.create(
        EntityRecordDraft(
          entityType: 'recurrence_rules',
          parentId: templateId,
          secondaryParentId: taskId,
          title: '${_titleCase(frequency)} recurrence',
          data: ruleData,
          syncPayload: rulePayload,
        ),
      );
      rule = await entities.get(ruleId);
    } else {
      ruleId = rule.id;
      await entities.update(
        rule,
        title: '${_titleCase(frequency)} recurrence',
        status: 'active',
        data: ruleData,
        syncPayload: rulePayload,
      );
    }

    final templateData = _templateData(
      task: task,
      configuration: taskConfiguration,
      ruleId: ruleId,
      previous: previousTemplateData,
    );
    await entities.update(
      template,
      title: task.title,
      status: 'active',
      data: templateData,
      syncPayload: _templatePayload(
        task: task,
        configuration: taskConfiguration,
        ruleId: ruleId,
        previous: previousTemplateData,
      ),
    );
    await tasks.attachTemplate(
      taskId: taskId,
      templateId: templateId,
      occurrenceKey: _dateOnly(startsOn),
    );
    task = (await tasks.getTask(taskId)) ?? task;
    await _reconcileMaterializedOccurrences(
      source: task,
      templateId: templateId,
      startsOn: startsOn,
      endsOn: endsOn,
      frequency: frequency,
      interval: 1,
      weekdays: weekdays,
      localTime: localTime,
      configuration: taskConfiguration,
    );
    await _generateUpcoming(horizonDays: 7);
  }

  Future<void> stopSeriesKeepingTask(LocalTask task) {
    final operation = _generationTail.then((_) => _stopSeriesKeepingTask(task));
    _generationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _stopSeriesKeepingTask(LocalTask task) async {
    final latest = await tasks.getTask(task.id);
    final templateId = latest?.templateId;
    if (latest == null || templateId == null) return;
    final template = await entities.get(templateId);
    final templateData = template == null
        ? const <String, Object?>{}
        : entities.decode(template);
    final rule = await _ruleForTemplate(templateId, templateData);
    if (rule != null) await entities.softDelete(rule);
    final occurrences = await _activeOccurrences(templateId);
    final removedIds = <String>{};
    for (final occurrence in occurrences) {
      if (occurrence.id == latest.id ||
          TaskOccurrencePolicy.terminalStatuses.contains(occurrence.status)) {
        continue;
      }
      removedIds.add(occurrence.id);
    }
    await _deleteRelationshipsForTasks(removedIds);
    for (final occurrence in occurrences) {
      if (removedIds.contains(occurrence.id)) {
        await tasks.softDelete(occurrence);
      }
    }
    await tasks.detachTemplate(latest.id);
    if (template != null) await entities.softDelete(template);
  }

  Future<void> deleteSeries(LocalTask task) {
    final operation = _generationTail.then((_) => _deleteSeries(task));
    _generationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _deleteSeries(LocalTask task) async {
    final latest = await tasks.getTask(task.id);
    final templateId = latest?.templateId;
    if (latest == null) return;
    if (templateId == null) {
      await tasks.softDelete(latest);
      return;
    }
    final template = await entities.get(templateId);
    final templateData = template == null
        ? const <String, Object?>{}
        : entities.decode(template);
    final rule = await _ruleForTemplate(templateId, templateData);
    // Stop local generation before deleting any materialized occurrence.
    if (rule != null) await entities.softDelete(rule);
    final occurrences = await _activeOccurrences(templateId);
    final occurrenceIds = occurrences.map((item) => item.id).toSet();
    await _deleteRelationshipsForTasks(occurrenceIds, templateId: templateId);
    for (final occurrence in occurrences) {
      await tasks.softDelete(occurrence);
    }
    if (template != null) await entities.softDelete(template);
  }

  /// Materializes a rolling near-term window. Seven days keeps daily/weekly
  /// work available offline without uploading months of child rows on every
  /// newly connected device; the idempotent pass advances on launch/resume.
  Future<int> generateUpcoming({int horizonDays = 7}) {
    final operation = _generationTail.then(
      (_) => _generateUpcoming(horizonDays: horizonDays),
    );
    _generationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<int> _generateUpcoming({required int horizonDays}) async {
    final rules = await entities.list(entityType: 'recurrence_rules');
    if (rules.isEmpty) return 0;
    final vacationPlanner = vacations == null
        ? VacationPlanner(const [])
        : VacationPlanner(await vacations!.list());
    final existing = await (database.select(
      database.localTasks,
    )..where((row) => row.userId.equals(entities.userId))).get();
    final knownKeys = <String>{
      for (final task in existing)
        if (task.templateId != null && task.occurrenceKey != null)
          '${task.templateId}:${task.occurrenceKey}',
    };
    final todayValue = now?.call() ?? DateTime.now();
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
            final vacation = vacationPlanner.dispositionFor(
              occurrenceDate: cursor,
              templateId: templateId,
            );
            if (vacation.isSkipped) {
              cursor = cursor.add(const Duration(days: 1));
              continue;
            }
            final durationMs =
                (templateRow['default_duration_ms'] as num?)?.toInt() ??
                source?.estimatedDurationMs ??
                1800000;
            final originalPlannedStart = _combine(cursor, localTime);
            final plannedDate = vacation.scheduledDate;
            final plannedStart = _combine(plannedDate, localTime);
            final inheritedExecutionSettings =
                templateRow['execution_settings'] is Map
                ? Map<String, Object?>.from(
                    templateRow['execution_settings'] as Map,
                  )
                : source == null
                ? <String, Object?>{}
                : _configuration(source.dataJson);
            // A source occurrence may itself have been postponed by a
            // vacation. That marker describes only that occurrence; carrying
            // it into a newly materialized recurrence would make later
            // reconciliation restore or move the wrong dates.
            final baseExecutionSettings = <String, Object?>{
              ...inheritedExecutionSettings,
            }..remove(vacationAdjustmentKey);
            final plannedRest = TaskSchedulePolicy.plannedRestDuration(
              baseExecutionSettings,
            );
            final occupiedDuration = TaskSchedulePolicy.occupiedDurationFor(
              workDuration: Duration(milliseconds: durationMs),
              plannedRest: plannedRest,
            );
            final executionSettings = vacation.isAdjusted
                ? <String, Object?>{
                    ...baseExecutionSettings,
                    vacationAdjustmentKey: {
                      'schema_version': 1,
                      'vacation_id': vacation.vacationId,
                      'policy': vacation.policy!.name,
                      'original_status': 'ready',
                      'original_scheduled_date': dateOnlyText(cursor),
                      'original_planned_start': originalPlannedStart
                          ?.toIso8601String(),
                      'original_planned_end': originalPlannedStart
                          ?.add(occupiedDuration)
                          .toIso8601String(),
                      'original_due_at': null,
                      'applied_status': 'ready',
                      'applied_scheduled_date': dateOnlyText(plannedDate),
                      'applied_planned_start': plannedStart?.toIso8601String(),
                      'applied_planned_end': plannedStart
                          ?.add(occupiedDuration)
                          .toIso8601String(),
                      'applied_due_at': null,
                    },
                  }
                : baseExecutionSettings;
            final taskId = await tasks.createTask(
              TaskDraft(
                id: recurringOccurrenceId(
                  userId: entities.userId,
                  templateId: templateId,
                  occurrenceKey: occurrenceKey,
                ),
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
                scheduledDate: plannedDate,
                plannedStart: plannedStart,
                plannedEnd: plannedStart?.add(occupiedDuration),
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
            await _createGeneratedRelationships(
              taskId: taskId,
              templateId: templateId,
              roadmapId:
                  templateRow['roadmap_id'] as String? ?? source?.roadmapId,
              phaseId:
                  templateRow['roadmap_phase_id'] as String? ??
                  source?.roadmapPhaseId,
              plannedStart: plannedStart,
              templateRow: templateRow,
              ruleRow: ruleRow,
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

  Future<LocalEntityRecord?> _ruleForTemplate(
    String templateId,
    Map<String, Object?> templateData,
  ) async {
    final directId = templateData['recurrence_rule_id']?.toString();
    if (directId != null && directId.isNotEmpty) {
      final direct = await entities.get(directId);
      if (direct != null) return direct;
    }
    final rules = await entities.list(entityType: 'recurrence_rules');
    return rules.where((record) {
      final data = entities.decode(record);
      final nested = _map(data['rule_data']);
      return record.parentId == templateId ||
          data['template_id'] == templateId ||
          nested['template_id'] == templateId;
    }).firstOrNull;
  }

  Map<String, Object?> _templateData({
    required LocalTask task,
    required Map<String, Object?> configuration,
    required String? ruleId,
    required Map<String, Object?> previous,
  }) {
    final nestedData = _map(previous['data']);
    final progressSettings = _map(previous['progress_settings']);
    return <String, Object?>{
      ...previous,
      'source_task_occurrence_id': task.id,
      'title': task.title,
      'description': task.description,
      'domain_id': task.domainId,
      'priority': task.priority,
      'execution_mode': task.executionMode,
      'default_duration_ms': task.estimatedDurationMs,
      'roadmap_id': task.roadmapId,
      'roadmap_phase_id': task.roadmapPhaseId,
      'recurrence_rule_id': ruleId,
      'reminder_defaults': previous['reminder_defaults'] is Iterable
          ? previous['reminder_defaults']
          : <Object?>[],
      'execution_settings': configuration,
      'progress_settings': {
        ...progressSettings,
        'completion_method': configuration['completion_method'] ?? 'manual',
      },
      'user_managed': true,
      'data': {
        ...nestedData,
        'source_task_occurrence_id': task.id,
        'user_managed': true,
      },
    };
  }

  Map<String, Object?> _templatePayload({
    required LocalTask task,
    required Map<String, Object?> configuration,
    required String? ruleId,
    required Map<String, Object?> previous,
  }) {
    final data = _templateData(
      task: task,
      configuration: configuration,
      ruleId: ruleId,
      previous: previous,
    );
    return <String, Object?>{
      'title': task.title,
      'description': task.description,
      'domain_id': task.domainId,
      'category_id': previous['category_id'],
      'priority': task.priority,
      'execution_mode': task.executionMode,
      'default_duration_ms': task.estimatedDurationMs,
      'minimum_duration_ms':
          previous['minimum_duration_ms'] ??
          configuration['minimum_useful_duration_ms'],
      'maximum_duration_ms':
          previous['maximum_duration_ms'] ??
          configuration['maximum_intended_duration_ms'],
      'recurrence_rule_id': ruleId,
      'roadmap_id': task.roadmapId,
      'roadmap_phase_id': task.roadmapPhaseId,
      'reminder_defaults': data['reminder_defaults'],
      'execution_settings': configuration,
      'progress_settings': data['progress_settings'],
      'data': data['data'],
    };
  }

  Future<List<LocalTask>> _activeOccurrences(String templateId) {
    return (database.select(database.localTasks)..where(
          (row) =>
              row.userId.equals(entities.userId) &
              row.templateId.equals(templateId) &
              row.deletedAt.isNull(),
        ))
        .get();
  }

  Future<void> _reconcileMaterializedOccurrences({
    required LocalTask source,
    required String templateId,
    required DateTime startsOn,
    required DateTime? endsOn,
    required String frequency,
    required int interval,
    required Set<int> weekdays,
    required String? localTime,
    required Map<String, Object?> configuration,
  }) async {
    final occurrences = await _activeOccurrences(templateId);
    final removedIds = <String>{};
    final duration = Duration(milliseconds: source.estimatedDurationMs);
    final occupiedDuration = TaskSchedulePolicy.occupiedDurationFor(
      workDuration: duration,
      plannedRest: TaskSchedulePolicy.plannedRestDuration(configuration),
    );
    for (final occurrence in occurrences) {
      if (occurrence.id == source.id ||
          TaskOccurrencePolicy.terminalStatuses.contains(occurrence.status) ||
          occurrence.actualStart != null) {
        continue;
      }
      final occurrenceDate =
          _date(occurrence.occurrenceKey) ??
          occurrence.scheduledDate ??
          occurrence.plannedStart;
      if (occurrenceDate == null ||
          occurrenceDate.isBefore(startsOn) ||
          (endsOn != null && occurrenceDate.isAfter(endsOn)) ||
          !_matches(
            date: occurrenceDate,
            startsOn: startsOn,
            frequency: frequency,
            interval: interval,
            weekdays: weekdays,
          )) {
        removedIds.add(occurrence.id);
        continue;
      }
      final scheduledDate = occurrence.scheduledDate ?? occurrenceDate;
      final plannedStart = _combine(scheduledDate, localTime);
      await tasks.updateTask(
        occurrence,
        TaskDraft(
          title: source.title,
          description: source.description,
          domainId: source.domainId,
          priority: source.priority,
          executionMode: source.executionMode,
          scheduledDate: scheduledDate,
          plannedStart: plannedStart,
          plannedEnd: plannedStart?.add(occupiedDuration),
          dueAt: occurrence.dueAt,
          estimatedDuration: duration,
          roadmapId: source.roadmapId,
          roadmapPhaseId: source.roadmapPhaseId,
          templateId: templateId,
          occurrenceKey: occurrence.occurrenceKey,
          configuration: configuration,
        ),
      );
    }
    await _deleteRelationshipsForTasks(removedIds);
    for (final occurrence in occurrences) {
      if (removedIds.contains(occurrence.id)) {
        await tasks.softDelete(occurrence);
      }
    }
  }

  Future<void> _deleteRelationshipsForTasks(
    Set<String> taskIds, {
    String? templateId,
  }) async {
    if (taskIds.isEmpty && templateId == null) return;
    for (final entityType in const [
      'task_reminders',
      'task_resources',
      'roadmap_task_links',
    ]) {
      final records = await entities.list(entityType: entityType);
      for (final record in records) {
        final data = entities.decode(record);
        final belongsToTask =
            taskIds.contains(record.parentId) ||
            taskIds.contains(record.secondaryParentId) ||
            taskIds.contains(data['task_id']) ||
            taskIds.contains(data['task_occurrence_id']);
        final belongsToTemplate =
            templateId != null &&
            (record.parentId == templateId ||
                record.secondaryParentId == templateId ||
                data['task_template_id'] == templateId ||
                data['template_id'] == templateId);
        if (belongsToTask || belongsToTemplate) {
          await entities.softDelete(record);
        }
      }
    }
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
    final parsed = value is DateTime
        ? value
        : value is String
        ? DateTime.tryParse(value)
        : null;
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  List<int> _integerList(Object? value) {
    return switch (value) {
      Iterable<Object?> items =>
        items.whereType<num>().map((item) => item.toInt()).toList(),
      String text =>
        text
            .replaceAll(RegExp(r'[{}\[\]\s]'), '')
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toList(),
      _ => const [],
    };
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
    try {
      final decoded = jsonDecode(value);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Map<String, Object?> _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

  String _titleCase(String value) => value.isEmpty
      ? value
      : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

  Future<void> _createGeneratedRelationships({
    required String taskId,
    required String templateId,
    required String? roadmapId,
    required String? phaseId,
    required DateTime? plannedStart,
    required Map<String, Object?> templateRow,
    required Map<String, Object?> ruleRow,
  }) async {
    if (roadmapId != null) {
      final links = await entities.list(
        entityType: 'roadmap_task_links',
        parentId: roadmapId,
      );
      final linked = links.any((record) {
        final data = entities.decode(record);
        return record.secondaryParentId == taskId || data['task_id'] == taskId;
      });
      if (!linked) {
        await entities.create(
          EntityRecordDraft(
            id: recurringRelationshipId(
              userId: entities.userId,
              taskId: taskId,
              relationshipKind: 'roadmap-link',
            ),
            entityType: 'roadmap_task_links',
            parentId: roadmapId,
            secondaryParentId: taskId,
            title: 'Recurring timetable connection',
            data: {
              'roadmap_id': roadmapId,
              'task_id': taskId,
              'phase_id': phaseId,
              'relationship_type': 'primary',
              'contribution_rule': 'completion_only',
              'progress_weight': 1,
            },
            syncPayload: {
              'roadmap_id': roadmapId,
              'task_id': taskId,
              'phase_id': phaseId,
              'milestone_id': null,
              'checkpoint_id': null,
              'relationship_type': 'primary',
              'contribution_rule': 'completion_only',
              'progress_weight': 1,
              'title': 'Recurring timetable connection',
              'status': 'active',
              'position': 0,
            },
          ),
        );
      }
    }

    final nestedData = templateRow['data'] is Map
        ? Map<String, Object?>.from(templateRow['data'] as Map)
        : const <String, Object?>{};
    final executionSettings = templateRow['execution_settings'] is Map
        ? Map<String, Object?>.from(templateRow['execution_settings'] as Map)
        : const <String, Object?>{};
    final resourceUrl =
        nestedData['resource_url']?.toString() ??
        executionSettings['suggested_resource']?.toString();
    if (resourceUrl != null && resourceUrl.trim().isNotEmpty) {
      final resourceName =
          nestedData['resource_name']?.toString() ??
          templateRow['title']?.toString() ??
          'Study resource';
      await entities.create(
        EntityRecordDraft(
          id: recurringRelationshipId(
            userId: entities.userId,
            taskId: taskId,
            relationshipKind: 'resource',
          ),
          entityType: 'task_resources',
          parentId: taskId,
          secondaryParentId: templateId,
          title: resourceName,
          data: {
            'task_occurrence_id': taskId,
            'task_template_id': templateId,
            'roadmap_id': roadmapId,
            'name': resourceName,
            'resource_type': 'url',
            'storage_location': 'url',
            'storage_path': resourceUrl,
            'privacy_state': 'private',
          },
          syncPayload: {
            'task_occurrence_id': taskId,
            'task_template_id': templateId,
            'roadmap_id': roadmapId,
            'name': resourceName,
            'resource_type': 'url',
            'description': 'Recurring timetable resource',
            'storage_location': 'url',
            'storage_path': resourceUrl,
            'local_path': null,
            'privacy_state': 'private',
            'last_opened_at': null,
            'open_count': 0,
          },
        ),
      );
    }

    if (plannedStart == null) return;
    final defaults = templateRow['reminder_defaults'];
    if (defaults is! Iterable) return;
    var position = 0;
    for (final rawDefault in defaults) {
      if (rawDefault is! Map) continue;
      final reminder = Map<String, Object?>.from(rawDefault);
      if (reminder['enabled'] == false) continue;
      final offsetMs =
          (reminder['offset_ms'] as num?)?.toInt() ??
          const Duration(minutes: 10).inMilliseconds;
      final reminderType =
          reminder['reminder_type']?.toString() ?? 'scheduled_start';
      final scheduledAt = plannedStart.subtract(
        Duration(milliseconds: offsetMs),
      );
      await entities.create(
        EntityRecordDraft(
          id: recurringRelationshipId(
            userId: entities.userId,
            taskId: taskId,
            relationshipKind: 'reminder',
            position: position,
          ),
          entityType: 'task_reminders',
          parentId: taskId,
          secondaryParentId: templateId,
          title: reminderType,
          status: 'enabled',
          position: position.toDouble(),
          data: {
            'task_template_id': templateId,
            'task_occurrence_id': taskId,
            'reminder_type': reminderType,
            'scheduled_at': scheduledAt.toUtc().toIso8601String(),
            'offset_ms': offsetMs,
            'sound_key': reminder['sound_key']?.toString() ?? 'selected',
            'enabled': true,
          },
          syncPayload: {
            'task_template_id': templateId,
            'task_occurrence_id': taskId,
            'reminder_type': reminderType,
            'scheduled_at': scheduledAt.toUtc().toIso8601String(),
            'offset_ms': offsetMs,
            'repeat_rule': {
              'frequency': ruleRow['frequency'],
              'weekdays': ruleRow['weekdays'],
            },
            'sound_key': reminder['sound_key']?.toString() ?? 'selected',
            'enabled': true,
          },
        ),
      );
      position++;
    }
  }
}
