import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity.dart';

class RoadmapDraft {
  const RoadmapDraft({
    required this.title,
    this.description = '',
    this.finalOutcome = '',
    this.plannedStart,
    this.targetDate,
    this.requiredEffort = const Duration(hours: 40),
  });

  final String title;
  final String description;
  final String finalOutcome;
  final DateTime? plannedStart;
  final DateTime? targetDate;
  final Duration requiredEffort;
}

class RoadmapRepository {
  RoadmapRepository(this.database, this.client)
    : entities = EntityRecordRepository(database, client);

  final AppDatabase database;
  final SupabaseClient client;
  final EntityRecordRepository entities;
  static const _uuid = Uuid();

  String get _userId => client.auth.currentUser?.id ?? 'local';

  Stream<List<LocalRoadmap>> watchRoadmaps() {
    final query = database.select(database.localRoadmaps)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.status),
        (row) => OrderingTerm.asc(row.forecastTargetDate),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch();
  }

  Stream<LocalRoadmap?> watchRoadmap(String roadmapId) {
    return (database.select(database.localRoadmaps)
          ..where((row) => row.id.equals(roadmapId) & row.deletedAt.isNull()))
        .watchSingleOrNull();
  }

  Stream<List<LocalTask>> watchLinkedTasks(String roadmapId) {
    final query = database.select(database.localTasks)
      ..where((row) => row.roadmapId.equals(roadmapId) & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.roadmapPhaseId),
        (row) => OrderingTerm.asc(row.scheduledDate),
      ]);
    return query.watch();
  }

  Stream<List<LocalEntityRecord>> watchPhases(String roadmapId) {
    return entities.watch(entityType: 'roadmap_phases', parentId: roadmapId);
  }

  Stream<List<LocalEntityRecord>> watchMilestones(String roadmapId) {
    return entities.watch(
      entityType: 'roadmap_milestones',
      parentId: roadmapId,
    );
  }

  Stream<List<LocalEntityRecord>> watchCheckpoints(String roadmapId) {
    return entities.watch(
      entityType: 'roadmap_checkpoints',
      parentId: roadmapId,
    );
  }

  Future<String> createRoadmap(RoadmapDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError('Roadmap title is required');
    final now = DateTime.now().toUtc();
    final localStart =
        draft.plannedStart ??
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final target = draft.targetDate ?? localStart.add(const Duration(days: 90));
    final id = _uuid.v4();
    final commandId = _uuid.v4();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final payload = <String, Object?>{
      'title': title,
      'description': draft.description.trim(),
      'status': 'active',
      'planned_start': _dateOnly(localStart),
      'original_target_date': _dateOnly(target),
      'forecast_target_date': _dateOnly(target),
      'final_outcome': draft.finalOutcome.trim(),
      'progress': 0,
      'required_effort_ms': draft.requiredEffort.inMilliseconds,
      'completed_effort_ms': 0,
      'risk_level': 'low',
      'forecast_confidence': 'low',
      'data': {'forecast_reasons': <String>[], 'forecast_evidence_count': 0},
    };

    await database.transaction(() async {
      await database
          .into(database.localRoadmaps)
          .insert(
            LocalRoadmapsCompanion.insert(
              id: id,
              userId: _userId,
              title: title,
              description: Value(draft.description.trim()),
              plannedStart: Value(localStart),
              originalTargetDate: Value(target),
              forecastTargetDate: Value(target),
              finalOutcome: Value(draft.finalOutcome.trim()),
              requiredEffortMs: Value(draft.requiredEffort.inMilliseconds),
              createdAt: now,
              updatedAt: now,
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: id,
        commandType: 'create',
        baseRevision: 0,
        payload: payload,
        now: now,
      );
    });
    for (final contributionType in const [
      'active_work_seconds',
      'practice_seconds',
      'reading_time',
      'research_time',
    ]) {
      await entities.create(
        EntityRecordDraft(
          entityType: 'roadmap_progress_rules',
          parentId: id,
          title: 'Approved ${contributionType.replaceAll('_', ' ')}',
          data: {
            'contribution_type': contributionType,
            'weight': 1,
            'automatic_credit_allowed': false,
            'accepted_contribution_types': [contributionType],
            'rule_config': {
              'requires_approved_attribution': true,
              'source': 'roadmap_default',
            },
          },
          syncPayload: {
            'roadmap_id': id,
            'roadmap_phase_id': null,
            'contribution_type': contributionType,
            'weight': 1,
            'automatic_credit_allowed': false,
            'rule_config': {
              'requires_approved_attribution': true,
              'source': 'roadmap_default',
            },
          },
        ),
      );
    }
    return id;
  }

  Future<void> createStarterRoadmap({
    required String userId,
    required String title,
  }) async {
    final existing =
        await (database.select(
              database.localRoadmaps,
            )..where((row) => row.title.equals(title) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (existing != null) return;
    final id = await createRoadmap(
      RoadmapDraft(
        title: title,
        description:
            'Starter roadmap created from onboarding. Every field is editable.',
        finalOutcome: 'Complete the goal with measurable evidence',
        requiredEffort: const Duration(hours: 60),
      ),
    );
    final start = DateTime.now();
    final phase1 = await addPhase(
      roadmapId: id,
      title: 'Foundation',
      description: 'Define the baseline, resources, and first repeatable steps',
      position: 0,
      plannedStart: start,
      plannedFinish: start.add(const Duration(days: 30)),
      requiredEffort: const Duration(hours: 15),
    );
    final phase2 = await addPhase(
      roadmapId: id,
      title: 'Core progress',
      description: 'Build consistent execution and complete the main work',
      position: 1,
      plannedStart: start.add(const Duration(days: 31)),
      plannedFinish: start.add(const Duration(days: 65)),
      requiredEffort: const Duration(hours: 30),
    );
    await addMilestone(
      roadmapId: id,
      phaseId: phase1,
      title: 'Foundation review',
      targetDate: start.add(const Duration(days: 30)),
    );
    await addCheckpoint(
      roadmapId: id,
      phaseId: phase2,
      title: 'Demonstrate measurable progress',
      objective: 'Provide a result that can be reviewed',
      targetDate: start.add(const Duration(days: 55)),
      estimatedEffort: const Duration(hours: 5),
    );
  }

  Future<void> updateRoadmap(
    LocalRoadmap roadmap, {
    required RoadmapDraft draft,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence();
    final start = draft.plannedStart ?? roadmap.plannedStart;
    final target = draft.targetDate ?? roadmap.originalTargetDate;
    final payload = <String, Object?>{
      'title': draft.title.trim(),
      'description': draft.description.trim(),
      'planned_start': start == null ? null : _dateOnly(start),
      'original_target_date': target == null ? null : _dateOnly(target),
      'final_outcome': draft.finalOutcome.trim(),
      'required_effort_ms': draft.requiredEffort.inMilliseconds,
    };
    await database.transaction(() async {
      await (database.update(
        database.localRoadmaps,
      )..where((row) => row.id.equals(roadmap.id))).write(
        LocalRoadmapsCompanion(
          title: Value(draft.title.trim()),
          description: Value(draft.description.trim()),
          plannedStart: Value(start),
          originalTargetDate: Value(target),
          finalOutcome: Value(draft.finalOutcome.trim()),
          requiredEffortMs: Value(draft.requiredEffort.inMilliseconds),
          revision: Value(roadmap.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: roadmap.id,
        commandType: 'update',
        baseRevision: roadmap.revision,
        payload: payload,
        now: now,
      );
    });
  }

  Future<void> setStatus(LocalRoadmap roadmap, String status) async {
    await _updateFields(roadmap, {'status': status});
  }

  Future<void> softDelete(LocalRoadmap roadmap) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence();
    await database.transaction(() async {
      await (database.update(
        database.localRoadmaps,
      )..where((row) => row.id.equals(roadmap.id))).write(
        LocalRoadmapsCompanion(
          deletedAt: Value(now),
          revision: Value(roadmap.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: roadmap.id,
        commandType: 'delete',
        baseRevision: roadmap.revision,
        payload: const {},
        now: now,
      );
    });
  }

  Future<String> addPhase({
    required String roadmapId,
    required String title,
    String description = '',
    required double position,
    DateTime? plannedStart,
    DateTime? plannedFinish,
    Duration? requiredEffort,
  }) {
    final data = <String, Object?>{
      'description': description.trim(),
      'planned_start': plannedStart == null ? null : _dateOnly(plannedStart),
      'planned_finish': plannedFinish == null ? null : _dateOnly(plannedFinish),
      'forecast_finish': plannedFinish == null
          ? null
          : _dateOnly(plannedFinish),
      'required_effort_ms': requiredEffort?.inMilliseconds,
      'progress': 0,
      'risk_level': 'low',
      'completion_rules': <Object?>[],
    };
    return entities.create(
      EntityRecordDraft(
        entityType: 'roadmap_phases',
        parentId: roadmapId,
        title: title,
        status: 'planned',
        position: position,
        data: data,
        syncPayload: {
          'roadmap_id': roadmapId,
          'title': title.trim(),
          'description': description.trim(),
          'position': position,
          ...data,
        },
      ),
    );
  }

  Future<String> addMilestone({
    required String roadmapId,
    String? phaseId,
    required String title,
    String description = '',
    DateTime? targetDate,
    double position = 0,
    double weight = 1,
  }) {
    final data = <String, Object?>{
      'description': description.trim(),
      'target_date': targetDate == null ? null : _dateOnly(targetDate),
      'weight': weight,
      'completed_at': null,
    };
    return entities.create(
      EntityRecordDraft(
        entityType: 'roadmap_milestones',
        parentId: roadmapId,
        secondaryParentId: phaseId,
        title: title,
        status: 'planned',
        position: position,
        data: data,
        syncPayload: {
          'roadmap_id': roadmapId,
          'phase_id': phaseId,
          'title': title.trim(),
          'description': description.trim(),
          'target_date': data['target_date'],
          'position': position,
          'weight': weight,
          'status': 'planned',
        },
      ),
    );
  }

  Future<String> addCheckpoint({
    required String roadmapId,
    String? phaseId,
    required String title,
    String objective = '',
    DateTime? targetDate,
    Duration estimatedEffort = Duration.zero,
    double weight = 1,
  }) {
    final data = <String, Object?>{
      'objective': objective.trim(),
      'target_date': targetDate == null ? null : _dateOnly(targetDate),
      'estimated_effort_ms': estimatedEffort.inMilliseconds,
      'actual_effort_ms': 0,
      'weight': weight,
      'completion_criteria': <Object?>[],
      'evidence': <Object?>[],
    };
    return entities.create(
      EntityRecordDraft(
        entityType: 'roadmap_checkpoints',
        parentId: roadmapId,
        secondaryParentId: phaseId,
        title: title,
        status: 'planned',
        data: data,
        syncPayload: {
          'roadmap_id': roadmapId,
          'phase_id': phaseId,
          'title': title.trim(),
          'objective': objective.trim(),
          'target_date': data['target_date'],
          'estimated_effort_ms': estimatedEffort.inMilliseconds,
          'actual_effort_ms': 0,
          'completion_criteria': <Object?>[],
          'evidence': <Object?>[],
          'status': 'planned',
          'weight': weight,
        },
      ),
    );
  }

  Future<void> setChildStatus(LocalEntityRecord record, String status) async {
    final data = entities.decode(record);
    if (status == 'completed') {
      data['completed_at'] = DateTime.now().toUtc().toIso8601String();
      data['progress'] = 1;
    } else {
      data['completed_at'] = null;
      data['progress'] = 0;
    }
    await entities.update(
      record,
      status: status,
      data: data,
      syncPayload: {
        'status': status,
        if (record.entityType == 'roadmap_milestones')
          'completed_at': data['completed_at'],
        if (record.entityType == 'roadmap_phases') 'progress': data['progress'],
      },
    );
    if (record.parentId != null) {
      await recalculateProgress(record.parentId!);
    }
  }

  Future<void> reorderPhases(
    List<LocalEntityRecord> phases,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = [...phases];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    for (var index = 0; index < reordered.length; index++) {
      final phase = reordered[index];
      if (phase.position == index.toDouble()) continue;
      await entities.update(
        phase,
        position: index.toDouble(),
        syncPayload: {'position': index.toDouble()},
      );
    }
  }

  Future<void> recalculateProgress(String roadmapId) async {
    final roadmap = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.id.equals(roadmapId))).getSingleOrNull();
    if (roadmap == null) return;
    final phases = await entities.list(
      entityType: 'roadmap_phases',
      parentId: roadmapId,
    );
    final milestones = await entities.list(
      entityType: 'roadmap_milestones',
      parentId: roadmapId,
    );
    final checkpoints = await entities.list(
      entityType: 'roadmap_checkpoints',
      parentId: roadmapId,
    );
    final tasks =
        await (database.select(database.localTasks)..where(
              (row) => row.roadmapId.equals(roadmapId) & row.deletedAt.isNull(),
            ))
            .get();
    final taskIds = tasks.map((task) => task.id).toSet();
    final contributions = taskIds.isEmpty
        ? const <LocalContribution>[]
        : await (database.select(database.localContributions)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    row.targetType.equals('task_occurrence') &
                    row.targetId.isIn(taskIds),
              ))
              .get();

    final weightedValues = <(double, double)>[];
    for (final phase in phases) {
      final data = entities.decode(phase);
      weightedValues.add((
        (data['progress'] as num?)?.toDouble() ??
            (phase.status == 'completed' ? 1 : 0),
        2,
      ));
    }
    for (final milestone in milestones) {
      final weight =
          (entities.decode(milestone)['weight'] as num?)?.toDouble() ?? 1;
      weightedValues.add((milestone.status == 'completed' ? 1 : 0, weight));
    }
    for (final checkpoint in checkpoints) {
      final weight =
          (entities.decode(checkpoint)['weight'] as num?)?.toDouble() ?? 1;
      weightedValues.add((checkpoint.status == 'completed' ? 1 : 0, weight));
    }
    for (final task in tasks) {
      weightedValues.add((task.progress.clamp(0, 1), 1));
    }
    final directEffort = tasks.fold<int>(
      0,
      (sum, task) => sum + task.activeDurationMs,
    );
    // The task timer already includes direct activity from its own session.
    // Only additional accepted work is added here, preserving one physical
    // timeline while still crediting cross-task and off-schedule progress.
    final attributedEffort = contributions
        .where(
          (item) =>
              item.isUnscheduled || item.isCrossTask || item.isIdleDerived,
        )
        .fold<int>(0, (sum, item) => sum + item.creditedDurationMs);
    final completedEffort = directEffort + attributedEffort;
    if (roadmap.requiredEffortMs != null && roadmap.requiredEffortMs! > 0) {
      weightedValues.add((
        (completedEffort / roadmap.requiredEffortMs!).clamp(0, 1),
        2,
      ));
    }
    final totalWeight = weightedValues.fold<double>(
      0,
      (sum, item) => sum + item.$2,
    );
    final progress = totalWeight == 0
        ? 0.0
        : weightedValues.fold<double>(
                0,
                (sum, item) => sum + item.$1 * item.$2,
              ) /
              totalWeight;
    final target = roadmap.originalTargetDate;
    DateTime? forecast = target;
    var risk = 'low';
    var confidence = weightedValues.length >= 10
        ? 'high'
        : weightedValues.length >= 4
        ? 'medium'
        : 'low';
    if (target != null && roadmap.plannedStart != null && progress > 0) {
      final elapsedDays = DateTime.now()
          .difference(roadmap.plannedStart!)
          .inDays
          .clamp(1, 36500);
      final expectedTotalDays = (elapsedDays / progress).round().clamp(
        elapsedDays,
        36500,
      );
      forecast = roadmap.plannedStart!.add(Duration(days: expectedTotalDays));
      final slip = forecast.difference(target).inDays;
      risk = slip > 14
          ? 'high'
          : slip > 3
          ? 'medium'
          : 'low';
    }
    await _updateFields(roadmap, {
      'progress': progress.clamp(0, 1),
      'completed_effort_ms': completedEffort,
      'forecast_target_date': forecast == null ? null : _dateOnly(forecast),
      'risk_level': risk,
      'forecast_confidence': confidence,
      'data': {
        'forecast_evidence_count': weightedValues.length,
        'forecast_reasons': [
          '${tasks.where((task) => task.status == 'completed').length} linked tasks completed',
          '${milestones.where((item) => item.status == 'completed').length} milestones completed',
          '${checkpoints.where((item) => item.status == 'completed').length} checkpoints completed',
          '$directEffort milliseconds of direct task effort recorded',
          '$attributedEffort milliseconds of approved additional activity credited',
        ],
      },
    });
  }

  Future<void> _updateFields(
    LocalRoadmap roadmap,
    Map<String, Object?> payload,
  ) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence();
    await database.transaction(() async {
      await (database.update(
        database.localRoadmaps,
      )..where((row) => row.id.equals(roadmap.id))).write(
        LocalRoadmapsCompanion(
          status: payload.containsKey('status')
              ? Value(payload['status']! as String)
              : const Value.absent(),
          progress: payload.containsKey('progress')
              ? Value((payload['progress']! as num).toDouble())
              : const Value.absent(),
          completedEffortMs: payload.containsKey('completed_effort_ms')
              ? Value((payload['completed_effort_ms']! as num).toInt())
              : const Value.absent(),
          forecastTargetDate: payload.containsKey('forecast_target_date')
              ? Value(_date(payload['forecast_target_date']))
              : const Value.absent(),
          riskLevel: payload.containsKey('risk_level')
              ? Value(payload['risk_level']! as String)
              : const Value.absent(),
          forecastConfidence: payload.containsKey('forecast_confidence')
              ? Value(payload['forecast_confidence']! as String)
              : const Value.absent(),
          revision: Value(roadmap.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: roadmap.id,
        commandType: 'update',
        baseRevision: roadmap.revision,
        payload: payload,
        now: now,
      );
    });
  }

  Future<void> _enqueue({
    required String commandId,
    required String deviceId,
    required int sequence,
    required String entityId,
    required String commandType,
    required int baseRevision,
    required Map<String, Object?> payload,
    required DateTime now,
  }) {
    return database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: commandId,
            userId: _userId,
            deviceId: deviceId,
            deviceSequence: sequence,
            entityType: 'roadmaps',
            entityId: entityId,
            commandType: commandType,
            baseRevision: baseRevision,
            payloadJson: jsonEncode(payload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  String _dateOnly(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
}
