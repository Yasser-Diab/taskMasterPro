import 'dart:convert';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../domain/recurring_occurrence_identity.dart';
import '../domain/vacation_period.dart';
import 'task_repository.dart';
import 'vacation_repository.dart';
import 'vacation_scheduling_service.dart';

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
                          ?.add(Duration(milliseconds: durationMs))
                          .toIso8601String(),
                      'original_due_at': null,
                      'applied_status': 'ready',
                      'applied_scheduled_date': dateOnlyText(plannedDate),
                      'applied_planned_start': plannedStart?.toIso8601String(),
                      'applied_planned_end': plannedStart
                          ?.add(Duration(milliseconds: durationMs))
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
