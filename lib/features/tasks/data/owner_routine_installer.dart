import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/time/time_zone_service.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/owner_routine_catalog.dart';
import '../domain/task_domain_catalog.dart';
import '../domain/task_schedule_policy.dart';
import 'task_repository.dart';

class OwnerRoutineInstallResult {
  const OwnerRoutineInstallResult({
    required this.templatesCreated,
    required this.rulesCreated,
    this.templatesUpdated = 0,
    this.rulesUpdated = 0,
    this.occurrencesUpdated = 0,
    this.settingsUpdated = 0,
  });

  final int templatesCreated;
  final int rulesCreated;
  final int templatesUpdated;
  final int rulesUpdated;
  final int occurrencesUpdated;
  final int settingsUpdated;

  bool get changed =>
      templatesCreated > 0 ||
      rulesCreated > 0 ||
      templatesUpdated > 0 ||
      rulesUpdated > 0 ||
      occurrencesUpdated > 0 ||
      settingsUpdated > 0;
}

/// Installs the owner's source-backed routine into the local-first model.
///
/// This does not infer an owner from an email address. The caller must already
/// be operating inside an authenticated, account-scoped database. Every
/// identity is deterministic, so a second device creates the same canonical
/// rows and retries do not multiply the routine.
class OwnerRoutineInstaller {
  OwnerRoutineInstaller({
    required this.database,
    required this.entities,
    required this.settings,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase database;
  final EntityRecordRepository entities;
  final SettingsRepository settings;
  final DateTime Function() _now;

  String get _userId => entities.userId;

  Future<bool> isEligible() async {
    if (_userId == 'local') return false;
    final roadmaps = await _roadmapsByTitle();
    const expectedImports = {
      'Full-Stack Development': 'full_stack_development:',
      'German Professional Fluency': 'german_professional_fluency:',
      'English Professional Fluency': 'english_professional_fluency:',
    };
    if (!expectedImports.keys.every(roadmaps.containsKey)) {
      return false;
    }
    final phases = await entities.list(entityType: 'roadmap_phases');
    const expectedPhasePrefixes = {
      'Full-Stack Development': 'P0',
      'German Professional Fluency': 'G0',
      'English Professional Fluency': 'E0',
    };
    // The private owner import stores this immutable, cryptographic source
    // provenance directly on every imported occurrence. Requiring a correctly
    // prefixed match inside every expected roadmap is the explicit opt-in: an
    // ordinary account with similarly named roadmaps cannot trigger it, while
    // a packaged build does not depend on an easily omitted dart-define.
    for (final entry in expectedImports.entries) {
      final title = entry.key;
      final roadmapId = roadmaps[title]!.id;
      if (!phases.any(
        (phase) =>
            phase.parentId == roadmapId &&
            phase.title.startsWith(expectedPhasePrefixes[title]!),
      )) {
        return false;
      }
      final candidates =
          await (database.select(database.localTasks)..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.roadmapId.equals(roadmapId) &
                    row.deletedAt.isNull(),
              ))
              .get();
      final hasMarker = candidates.any((task) {
        Object? decoded;
        try {
          decoded = jsonDecode(task.dataJson);
        } catch (_) {
          return false;
        }
        if (decoded is! Map) return false;
        final data = Map<String, Object?>.from(decoded);
        final importKey = data['roadmap_import_key'];
        return data['source_fingerprint'] ==
                OwnerRoutineCatalog.sourceFingerprint &&
            data['schedule_provenance'] ==
                OwnerRoutineCatalog.scheduleProvenance &&
            importKey is String &&
            importKey.startsWith(entry.value);
      });
      if (!hasMarker) return false;
    }
    return true;
  }

  Future<OwnerRoutineInstallResult> ensureInstalled() async {
    if (!await isEligible()) {
      return const OwnerRoutineInstallResult(
        templatesCreated: 0,
        rulesCreated: 0,
      );
    }

    final roadmaps = await _roadmapsByTitle();
    final settingsUpdated = await _repairLegacyWorkScheduleSettings();
    final timeZone = await _effectiveTimeZone();
    final phases = await entities.list(entityType: 'roadmap_phases');
    final phaseByRoutine = <String, String?>{};
    for (final routine in OwnerRoutineCatalog.routines) {
      final roadmapId = routine.roadmapTitle == null
          ? null
          : roadmaps[routine.roadmapTitle!]?.id;
      phaseByRoutine[routine.key] = roadmapId == null
          ? null
          : phases
                .where(
                  (phase) =>
                      phase.parentId == roadmapId &&
                      phase.title.startsWith(routine.phaseTitlePrefix ?? ''),
                )
                .firstOrNull
                ?.id;
    }

    var templatesCreated = 0;
    var rulesCreated = 0;
    var templatesUpdated = 0;
    var rulesUpdated = 0;
    for (final routine in OwnerRoutineCatalog.routines) {
      final roadmapId = routine.roadmapTitle == null
          ? null
          : roadmaps[routine.roadmapTitle!]?.id;
      final phaseId = phaseByRoutine[routine.key];
      final templateId = OwnerRoutineCatalog.stableId(
        userId: _userId,
        routineKey: routine.key,
        recordKind: 'template',
      );
      final ruleId = OwnerRoutineCatalog.stableId(
        userId: _userId,
        routineKey: routine.key,
        recordKind: 'rule',
      );
      final domainId = TaskDomainCatalog.idFor(_userId, routine.domainKey);
      // Recurrence rules carry the template UUID in JSON but no foreign key,
      // while task_templates points at recurrence_rules. Enqueueing the rule
      // first preserves dependency order when both share the same priority.
      final rule = await entities.getIncludingDeleted(ruleId);
      final template = await entities.getIncludingDeleted(templateId);
      // A tombstone is an explicit series-level user decision. Restoring these
      // deterministic records on every launch made built-in routines
      // impossible to delete permanently.
      if (rule?.deletedAt != null || template?.deletedAt != null) continue;
      final desiredRuleData = _ruleLocalData(routine, templateId, timeZone);
      final desiredRulePayload = _rulePayload(routine, templateId, timeZone);
      if (rule == null) {
        await entities.create(
          EntityRecordDraft(
            id: ruleId,
            entityType: 'recurrence_rules',
            parentId: templateId,
            title: '${routine.title} recurrence',
            data: desiredRuleData,
            syncPayload: desiredRulePayload,
          ),
        );
        rulesCreated++;
      } else if (_ruleNeedsRepair(entities.decode(rule), routine, timeZone)) {
        await entities.update(
          rule,
          title: '${routine.title} recurrence',
          parentId: templateId,
          data: desiredRuleData,
          syncPayload: desiredRulePayload,
        );
        rulesUpdated++;
      }

      final desiredTemplateData = _templateLocalData(
        routine: routine,
        roadmapId: roadmapId,
        phaseId: phaseId,
        domainId: domainId,
        ruleId: ruleId,
        timeZone: timeZone,
      );
      final desiredTemplatePayload = _templatePayload(
        routine: routine,
        roadmapId: roadmapId,
        phaseId: phaseId,
        domainId: domainId,
        ruleId: ruleId,
        timeZone: timeZone,
      );
      if (template == null) {
        await entities.create(
          EntityRecordDraft(
            id: templateId,
            entityType: 'task_templates',
            parentId: roadmapId,
            secondaryParentId: phaseId,
            title: routine.title,
            data: desiredTemplateData,
            syncPayload: desiredTemplatePayload,
          ),
        );
        templatesCreated++;
      } else if (_templateNeedsRepair(
        entities.decode(template),
        routine,
        timeZone,
      )) {
        await entities.update(
          template,
          title: routine.title,
          data: desiredTemplateData,
          syncPayload: desiredTemplatePayload,
        );
        templatesUpdated++;
      }
    }
    final occurrencesUpdated = await _repairWorkOccurrences(timeZone);
    return OwnerRoutineInstallResult(
      templatesCreated: templatesCreated,
      rulesCreated: rulesCreated,
      templatesUpdated: templatesUpdated,
      rulesUpdated: rulesUpdated,
      occurrencesUpdated: occurrencesUpdated,
      settingsUpdated: settingsUpdated,
    );
  }

  /// Starter routines are scheduled in the account/device's own local IANA
  /// zone. Existing imported Cairo rows are therefore repaired on automatic
  /// accounts outside Cairo, while a manual timezone choice remains intact.
  Future<String> _effectiveTimeZone() async {
    final current =
        await (database.select(database.localAppSettings)..where(
              (row) =>
                  row.id.equals(localAppSettingsId(_userId)) &
                  row.userId.equals(_userId),
            ))
            .getSingleOrNull();
    if (current == null) return 'UTC';
    final detected = current.useDeviceTimeZone
        ? await TimeZoneService.detectDeviceIanaZone()
        : null;
    return TimeZoneService.resolveStoredIanaZone(
      deviceZone: detected,
      storedZone: current.timeZone,
      useDeviceTimeZone: current.useDeviceTimeZone,
    );
  }

  /// Repairs the one known bad schedule produced by the private owner import.
  ///
  /// `00:09` to `17:30` is the exact legacy signature. Limiting the migration
  /// to that signature means the bootstrap cannot keep overwriting a schedule
  /// the owner later edits. [SettingsRepository] performs the canonical local
  /// revision and emits one normal `user_settings` outbox command.
  Future<int> _repairLegacyWorkScheduleSettings() async {
    final current =
        await (database.select(database.localAppSettings)..where(
              (row) =>
                  row.id.equals(localAppSettingsId(_userId)) &
                  row.userId.equals(_userId),
            ))
            .getSingleOrNull();
    if (current == null ||
        current.workStartMinutes != 9 ||
        current.workEndMinutes != 1050) {
      return 0;
    }
    await settings.updateScheduleAndWellbeing(
      workingDays: const [1, 2, 3, 4, 6, 7],
      workStartMinutes: 540,
      workEndMinutes: 1050,
    );
    return 1;
  }

  bool _ruleNeedsRepair(
    Map<String, Object?> actual,
    OwnerRoutineDefinition routine,
    String timeZone,
  ) {
    final nested = actual['rule_data'] is Map
        ? Map<String, Object?>.from(actual['rule_data'] as Map)
        : const <String, Object?>{};
    if (actual['user_managed'] == true || nested['user_managed'] == true) {
      return false;
    }
    return actual['frequency'] != routine.frequency ||
        (actual['interval_value'] as num?)?.toInt() != 1 ||
        !_sameIntegerList(actual['weekdays'], routine.weekdays) ||
        nested['local_time'] != routine.localTime ||
        nested['time_zone'] != timeZone ||
        !_sameIntegerList(nested['weekdays'], routine.weekdays);
  }

  bool _templateNeedsRepair(
    Map<String, Object?> actual,
    OwnerRoutineDefinition routine,
    String timeZone,
  ) {
    final settings = actual['execution_settings'] is Map
        ? Map<String, Object?>.from(actual['execution_settings'] as Map)
        : const <String, Object?>{};
    final nested = actual['data'] is Map
        ? Map<String, Object?>.from(actual['data'] as Map)
        : const <String, Object?>{};
    if (actual['user_managed'] == true || nested['user_managed'] == true) {
      return false;
    }
    return actual['title'] != routine.title ||
        actual['execution_mode'] != routine.executionMode ||
        (actual['default_duration_ms'] as num?)?.toInt() !=
            routine.duration.inMilliseconds ||
        !_containsCanonicalSettings(
          settings,
          routine.executionSettingsFor(timeZone),
        );
  }

  bool _sameIntegerList(Object? actual, List<int> expected) {
    final values = switch (actual) {
      Iterable<Object?> items =>
        items.whereType<num>().map((item) => item.toInt()).toList(),
      String value =>
        value
            .replaceAll(RegExp(r'[{}\[\]\s]'), '')
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toList(),
      _ => const <int>[],
    };
    if (values.length != expected.length) return false;
    for (var index = 0; index < values.length; index++) {
      if (values[index] != expected[index]) return false;
    }
    return true;
  }

  bool _containsCanonicalSettings(
    Map<String, Object?> actual,
    Map<String, Object?> expected,
  ) {
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<int> _repairWorkOccurrences(String timeZone) async {
    final routine = OwnerRoutineCatalog.routines.singleWhere(
      (item) => item.key == 'work_non_friday',
    );
    final templateId = OwnerRoutineCatalog.stableId(
      userId: _userId,
      routineKey: routine.key,
      recordKind: 'template',
    );
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final occurrences =
        await (database.select(database.localTasks)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.templateId.equals(templateId) &
                  row.deletedAt.isNull(),
            ))
            .get();
    final tasks = TaskRepository(database, entities.client);
    var updated = 0;
    for (final task in occurrences) {
      final scheduled = task.scheduledDate;
      if (scheduled == null ||
          DateTime(
            scheduled.year,
            scheduled.month,
            scheduled.day,
          ).isBefore(today) ||
          task.actualStart != null ||
          task.actualFinish != null ||
          const {
            'in_progress',
            'completed',
            'cancelled',
            'archived',
          }.contains(task.status)) {
        continue;
      }
      final plannedStart = DateTime(
        scheduled.year,
        scheduled.month,
        scheduled.day,
        routine.hour,
        routine.minute,
      );
      final settings = <String, Object?>{
        ..._taskConfiguration(task),
        ...routine.executionSettingsFor(timeZone),
      };
      final plannedEnd = plannedStart.add(
        TaskSchedulePolicy.occupiedDurationFor(
          workDuration: routine.duration,
          plannedRest: TaskSchedulePolicy.plannedRestDuration(settings),
        ),
      );
      if (task.title == routine.title &&
          task.executionMode == routine.executionMode &&
          task.plannedStart == plannedStart &&
          task.plannedEnd == plannedEnd &&
          task.estimatedDurationMs == routine.duration.inMilliseconds &&
          _containsCanonicalSettings(_taskConfiguration(task), settings)) {
        continue;
      }
      await tasks.updateTask(
        task,
        TaskDraft(
          title: routine.title,
          description: task.description,
          domainId: task.domainId,
          priority: task.priority,
          executionMode: routine.executionMode,
          scheduledDate: scheduled,
          plannedStart: plannedStart,
          plannedEnd: plannedEnd,
          dueAt: task.dueAt,
          estimatedDuration: routine.duration,
          roadmapId: task.roadmapId,
          roadmapPhaseId: task.roadmapPhaseId,
          templateId: task.templateId,
          occurrenceKey: task.occurrenceKey,
          configuration: settings,
        ),
      );
      updated++;
    }
    return updated;
  }

  Map<String, Object?> _taskConfiguration(LocalTask task) {
    try {
      final decoded = jsonDecode(task.dataJson);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  Future<Map<String, LocalRoadmap>> _roadmapsByTitle() async {
    final rows =
        await (database.select(database.localRoadmaps)..where(
              (row) => row.userId.equals(_userId) & row.deletedAt.isNull(),
            ))
            .get();
    return {for (final roadmap in rows) roadmap.title: roadmap};
  }

  Map<String, Object?> _templateLocalData({
    required OwnerRoutineDefinition routine,
    required String? roadmapId,
    required String? phaseId,
    required String domainId,
    required String ruleId,
    required String timeZone,
  }) => {
    ..._templatePayload(
      routine: routine,
      roadmapId: roadmapId,
      phaseId: phaseId,
      domainId: domainId,
      ruleId: ruleId,
      timeZone: timeZone,
    ),
    'data': {
      'owner_routine_key': routine.key,
      'source_fingerprint': OwnerRoutineCatalog.sourceFingerprint,
      if (routine.resourceUrl != null) 'resource_url': routine.resourceUrl,
      if (routine.resourceName != null) 'resource_name': routine.resourceName,
      'time_zone': timeZone,
    },
  };

  Map<String, Object?> _templatePayload({
    required OwnerRoutineDefinition routine,
    required String? roadmapId,
    required String? phaseId,
    required String domainId,
    required String ruleId,
    required String timeZone,
  }) => {
    'title': routine.title,
    'description': 'Recurring routine from the supplied roadmap plan.',
    'domain_id': domainId,
    'priority': 2,
    'execution_mode': routine.executionMode,
    'default_duration_ms': routine.duration.inMilliseconds,
    'minimum_duration_ms': null,
    'maximum_duration_ms': null,
    'recurrence_rule_id': ruleId,
    'roadmap_id': roadmapId,
    'roadmap_phase_id': phaseId,
    'reminder_defaults': [
      {
        'reminder_type': 'scheduled_start',
        'offset_ms': routine.reminderOffset.inMilliseconds,
        'sound_key': 'selected',
        'enabled': true,
      },
    ],
    'execution_settings': routine.executionSettingsFor(timeZone),
    'progress_settings': {'completion_method': 'duration'},
    'data': {
      'owner_routine_key': routine.key,
      'source_fingerprint': OwnerRoutineCatalog.sourceFingerprint,
      if (routine.resourceUrl != null) 'resource_url': routine.resourceUrl,
      if (routine.resourceName != null) 'resource_name': routine.resourceName,
      'time_zone': timeZone,
    },
  };

  Map<String, Object?> _ruleLocalData(
    OwnerRoutineDefinition routine,
    String templateId,
    String timeZone,
  ) => {
    ..._rulePayload(routine, templateId, timeZone),
    'rule_data': {
      'template_id': templateId,
      'frequency': routine.frequency,
      'interval_value': 1,
      'weekdays': routine.weekdays,
      'starts_on': OwnerRoutineCatalog.routineStart,
      'local_time': routine.localTime,
      'time_zone': timeZone,
      'owner_routine_key': routine.key,
    },
    'data': {
      'owner_routine_key': routine.key,
      'source_fingerprint': OwnerRoutineCatalog.sourceFingerprint,
    },
  };

  Map<String, Object?> _rulePayload(
    OwnerRoutineDefinition routine,
    String templateId,
    String timeZone,
  ) => {
    'frequency': routine.frequency,
    'interval_value': 1,
    'weekdays': routine.weekdays,
    'starts_on': OwnerRoutineCatalog.routineStart,
    'ends_on': null,
    'maximum_occurrences': null,
    'paused_at': null,
    'rule_data': {
      'template_id': templateId,
      'frequency': routine.frequency,
      'interval_value': 1,
      'weekdays': routine.weekdays,
      'starts_on': OwnerRoutineCatalog.routineStart,
      'local_time': routine.localTime,
      'time_zone': timeZone,
      'owner_routine_key': routine.key,
    },
    'data': {
      'owner_routine_key': routine.key,
      'source_fingerprint': OwnerRoutineCatalog.sourceFingerprint,
    },
  };
}
