import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/data/entity_record_repository.dart';
import '../../../core/platform/device_identity.dart';

class ActivityReviewEntry {
  const ActivityReviewEntry({required this.review, required this.segment});

  final LocalActivityReview review;
  final LocalActivitySegment segment;

  Duration get duration => segment.endedAt.difference(segment.startedAt);
}

class ActivityResolution {
  const ActivityResolution({
    required this.status,
    required this.classification,
    this.targetType = 'unassigned_activity',
    this.targetId,
    this.contributionType,
    this.creditedDuration,
    this.rememberRule = false,
    this.isAutomatic = false,
  });

  final String status;
  final String classification;
  final String targetType;
  final String? targetId;
  final String? contributionType;
  final Duration? creditedDuration;
  final bool rememberRule;
  final bool isAutomatic;
}

class ActivityRepository {
  ActivityRepository(this.database, this.client);

  final AppDatabase database;
  final SupabaseClient client;
  static const _uuid = Uuid();

  String get _userId => client.auth.currentUser?.id ?? 'local';

  Future<String> captureRawSegment({
    required DateTime startedAt,
    required DateTime endedAt,
    required String sourceType,
    String? processName,
    String? windowTitle,
    String? idleState,
    String? packageName,
    double confidence = 0.9,
    bool createReview = true,
  }) async {
    if (!endedAt.isAfter(startedAt)) {
      throw ArgumentError('Activity segment must have a positive duration');
    }
    final id = _uuid.v4();
    final deviceId = await DeviceIdentity.id();
    final deviceEventId =
        '$deviceId:${startedAt.microsecondsSinceEpoch}:'
        '${endedAt.microsecondsSinceEpoch}';
    final now = DateTime.now().toUtc();
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals('app'))).getSingleOrNull();
    final synchronizeActivity = settings?.activitySyncEnabled ?? true;
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence();
    final runtime = await (database.select(
      database.localRuntimeStates,
    )..where((row) => row.userId.equals(_userId))).getSingleOrNull();
    final metadata = <String, Object?>{'captured_compactly': true};
    if (packageName != null) metadata['package_name'] = packageName;
    if (runtime?.activeTaskId != null) {
      metadata['source_task_id'] = runtime!.activeTaskId;
    }
    if (runtime?.sessionId != null) {
      metadata['source_session_id'] = runtime!.sessionId;
    }
    if (runtime != null) metadata['source_runtime_state'] = runtime.state;
    await database.transaction(() async {
      await database
          .into(database.localActivitySegments)
          .insert(
            LocalActivitySegmentsCompanion.insert(
              id: id,
              userId: _userId,
              deviceId: deviceId,
              deviceEventId: deviceEventId,
              startedAt: startedAt.toUtc(),
              endedAt: endedAt.toUtc(),
              sourceType: sourceType,
              processName: Value(processName),
              windowTitle: Value(windowTitle),
              idleState: Value(idleState),
              captureConfidence: Value(confidence),
              rawMetadataJson: Value(jsonEncode(metadata)),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (synchronizeActivity) {
        await _enqueue(
          commandId: commandId,
          deviceId: deviceId,
          sequence: sequence,
          entityType: 'activity_segments',
          entityId: id,
          payload: {
            'device_id': deviceId,
            'device_event_id': deviceEventId,
            'started_at': startedAt.toUtc().toIso8601String(),
            'ended_at': endedAt.toUtc().toIso8601String(),
            'source_type': sourceType,
            'application_id': null,
            'website_rule_id': null,
            'resource_id': null,
            'process_name': processName,
            'window_title': windowTitle,
            'domain': null,
            'url': null,
            'page_title': null,
            'input_state': idleState == 'technical_idle' ? 'idle' : 'active',
            'idle_state': idleState,
            'screen_state': 'unlocked',
            'capture_confidence': confidence,
            'raw_metadata': metadata,
            'data': <String, Object?>{},
          },
          now: now,
        );
      }
      if (createReview) {
        final reviewId = _uuid.v4();
        final reviewCommandId = _uuid.v4();
        final reviewSequence = await DeviceIdentity.nextSequence();
        final reason = idleState == 'technical_idle'
            ? 'idle'
            : 'unknown_application';
        await database
            .into(database.localActivityReviews)
            .insert(
              LocalActivityReviewsCompanion.insert(
                id: reviewId,
                userId: _userId,
                activitySegmentId: id,
                reviewReason: reason,
                priority: Value(idleState == 'technical_idle' ? 3 : 2),
                suggestedClassification: Value(
                  idleState == 'technical_idle' ? 'requires_review' : 'unknown',
                ),
                confidence: Value(confidence),
                createdAt: now,
                updatedAt: now,
              ),
            );
        if (synchronizeActivity) {
          await _enqueue(
            commandId: reviewCommandId,
            deviceId: deviceId,
            sequence: reviewSequence,
            entityType: 'activity_review_queue',
            entityId: reviewId,
            payload: {
              'activity_segment_id': id,
              'review_reason': reason,
              'priority': idleState == 'technical_idle' ? 3 : 2,
              'suggested_targets': <Object?>[],
              'suggested_classification': idleState == 'technical_idle'
                  ? 'requires_review'
                  : 'unknown',
              'confidence': confidence,
              'status': 'pending',
              'data': <String, Object?>{},
            },
            now: now,
          );
        }
      }
    });
    if (createReview && settings?.automaticTrustedRules == true) {
      await _applyTrustedRuleIfAvailable(id);
    }
    return id;
  }

  Future<List<LocalTask>> listTaskTargets() {
    final query = database.select(database.localTasks)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.status.isNotIn(['cancelled', 'archived']),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.status),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.get();
  }

  Stream<List<ActivityReviewEntry>> watchReviewQueue() {
    final query =
        database.select(database.localActivityReviews).join([
            innerJoin(
              database.localActivitySegments,
              database.localActivitySegments.id.equalsExp(
                database.localActivityReviews.activitySegmentId,
              ),
            ),
          ])
          ..where(
            database.localActivityReviews.deletedAt.isNull() &
                database.localActivityReviews.status.equals('pending'),
          )
          ..orderBy([
            OrderingTerm.desc(database.localActivityReviews.priority),
            OrderingTerm.desc(database.localActivityReviews.createdAt),
          ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ActivityReviewEntry(
            review: row.readTable(database.localActivityReviews),
            segment: row.readTable(database.localActivitySegments),
          ),
      ],
    );
  }

  Future<void> resolve(
    ActivityReviewEntry entry,
    ActivityResolution resolution,
  ) async {
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals('app'))).getSingleOrNull();
    final synchronizeActivity = settings?.activitySyncEnabled ?? true;
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final reviewCommandId = _uuid.v4();
    final reviewSequence = await DeviceIdentity.nextSequence();
    final attributionId = _uuid.v4();
    final attributionCommandId = _uuid.v4();
    final attributionSequence = await DeviceIdentity.nextSequence();
    final shouldCredit =
        resolution.status == 'confirmed' &&
        resolution.targetId != null &&
        resolution.contributionType != null;
    final contributionId = shouldCredit ? _uuid.v4() : null;
    final contributionCommandId = shouldCredit ? _uuid.v4() : null;
    final contributionSequence = shouldCredit
        ? await DeviceIdentity.nextSequence()
        : null;
    final metadataValue = jsonDecode(entry.segment.rawMetadataJson);
    final metadata = metadataValue is Map
        ? Map<String, Object?>.from(metadataValue)
        : <String, Object?>{};
    final sourceTaskId = metadata['source_task_id'] as String?;
    final sourceSessionId = metadata['source_session_id'] as String?;
    final physicalDurationMs = entry.duration.inMilliseconds;
    final creditedDurationMs = (resolution.creditedDuration ?? entry.duration)
        .inMilliseconds
        .clamp(0, physicalDurationMs);

    await database.transaction(() async {
      await (database.update(
        database.localActivityReviews,
      )..where((row) => row.id.equals(entry.review.id))).write(
        LocalActivityReviewsCompanion(
          status: Value(resolution.status),
          reviewedAt: Value(now),
          revision: Value(entry.review.revision + 1),
          updatedAt: Value(now),
        ),
      );
      if (synchronizeActivity) {
        await _enqueue(
          commandId: reviewCommandId,
          deviceId: deviceId,
          sequence: reviewSequence,
          entityType: 'activity_review_queue',
          entityId: entry.review.id,
          commandType: 'update',
          baseRevision: entry.review.revision,
          payload: {
            'status': resolution.status,
            'reviewed_at': now.toIso8601String(),
          },
          now: now,
        );
      }

      await database
          .into(database.localAttributions)
          .insert(
            LocalAttributionsCompanion.insert(
              id: attributionId,
              userId: _userId,
              activitySegmentId: entry.segment.id,
              targetType: resolution.targetType,
              targetId: Value(resolution.targetId),
              classification: resolution.classification,
              confidence: entry.review.confidence ?? 1,
              attributionStatus: Value(
                resolution.isAutomatic
                    ? 'automatic'
                    : resolution.status == 'confirmed'
                    ? 'confirmed'
                    : resolution.status,
              ),
              confirmedByUser: Value(!resolution.isAutomatic),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (synchronizeActivity) {
        await _enqueue(
          commandId: attributionCommandId,
          deviceId: deviceId,
          sequence: attributionSequence,
          entityType: 'activity_attributions',
          entityId: attributionId,
          payload: {
            'activity_segment_id': entry.segment.id,
            'target_type': resolution.targetType,
            'target_id': resolution.targetId,
            'classification': resolution.classification,
            'confidence': entry.review.confidence ?? 1,
            'attribution_status': resolution.isAutomatic
                ? 'automatic'
                : resolution.status == 'confirmed'
                ? 'confirmed'
                : resolution.status,
            'suggested_by': resolution.isAutomatic
                ? 'trusted_rule'
                : 'user_review',
            'confirmed_by_user': !resolution.isAutomatic,
            'data': <String, Object?>{
              'remember_rule_requested': resolution.rememberRule,
            },
          },
          now: now,
        );
      }

      if (shouldCredit) {
        final isCrossTask =
            sourceTaskId != null && sourceTaskId != resolution.targetId;
        await database
            .into(database.localContributions)
            .insert(
              LocalContributionsCompanion.insert(
                id: contributionId!,
                userId: _userId,
                activitySegmentId: entry.segment.id,
                attributionId: attributionId,
                targetType: resolution.targetType,
                targetId: Value(resolution.targetId),
                contributionType: resolution.contributionType!,
                physicalDurationMs: physicalDurationMs,
                creditedDurationMs: creditedDurationMs,
                isUnscheduled: Value(sourceTaskId != resolution.targetId),
                isCrossTask: Value(isCrossTask),
                isIdleDerived: Value(
                  entry.segment.idleState == 'technical_idle',
                ),
                isAutomatic: Value(resolution.isAutomatic),
                createdAt: now,
                updatedAt: now,
              ),
            );
        if (synchronizeActivity) {
          await _enqueue(
            commandId: contributionCommandId!,
            deviceId: deviceId,
            sequence: contributionSequence!,
            entityType: 'activity_contributions',
            entityId: contributionId,
            payload: {
              'activity_segment_id': entry.segment.id,
              'activity_attribution_id': attributionId,
              'target_type': resolution.targetType,
              'target_id': resolution.targetId,
              'contribution_type': resolution.contributionType,
              'physical_duration_ms': physicalDurationMs,
              'credited_duration_ms': creditedDurationMs,
              'progress_value': creditedDurationMs.toDouble(),
              'source_task_id': sourceTaskId,
              'source_session_id': sourceSessionId,
              'source_break_id': null,
              'is_unscheduled': sourceTaskId != resolution.targetId,
              'is_cross_task': isCrossTask,
              'is_idle_derived': entry.segment.idleState == 'technical_idle',
              'is_automatic': resolution.isAutomatic,
              'data': <String, Object?>{},
            },
            now: now,
          );
        }
        await database
            .into(database.localEntityRecords)
            .insert(
              LocalEntityRecordsCompanion.insert(
                id: contributionId,
                userId: _userId,
                entityType: 'activity_contributions',
                parentId: Value(resolution.targetId),
                title: Value(
                  '${_readableClassification(resolution.classification)} '
                  'contribution',
                ),
                status: const Value('confirmed'),
                dataJson: Value(
                  jsonEncode({
                    'activity_segment_id': entry.segment.id,
                    'contribution_type': resolution.contributionType,
                    'physical_duration_ms': physicalDurationMs,
                    'credited_duration_ms': creditedDurationMs,
                    'source_task_id': sourceTaskId,
                    'is_cross_task': isCrossTask,
                    'is_idle_derived':
                        entry.segment.idleState == 'technical_idle',
                  }),
                ),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });

    await _recordClassificationFeedback(
      entry: entry,
      resolution: resolution,
      synchronize: synchronizeActivity,
    );
    if (resolution.rememberRule &&
        shouldCredit &&
        resolution.targetType == 'task_occurrence') {
      await _rememberApplicationRule(
        entry: entry,
        resolution: resolution,
        synchronize: synchronizeActivity,
      );
    }
    if (shouldCredit && resolution.targetType == 'task_occurrence') {
      await _applyPermittedRoadmapEffects(
        taskId: resolution.targetId!,
        contributionId: contributionId!,
        contributionType: resolution.contributionType!,
        creditedDurationMs: creditedDurationMs,
        synchronize: synchronizeActivity,
      );
    }
  }

  Future<void> _applyPermittedRoadmapEffects({
    required String taskId,
    required String contributionId,
    required String contributionType,
    required int creditedDurationMs,
    required bool synchronize,
  }) async {
    final task =
        await (database.select(database.localTasks)
              ..where((row) => row.id.equals(taskId) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (task?.roadmapId == null) return;
    final rules =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.entityType.equals('roadmap_progress_rules') &
                  row.parentId.equals(task!.roadmapId!) &
                  row.deletedAt.isNull() &
                  row.status.equals('active'),
            ))
            .get();
    final permitted = rules.any((rule) {
      final value = jsonDecode(rule.dataJson);
      if (value is! Map) return false;
      final data = Map<String, Object?>.from(value);
      final accepted = data['accepted_contribution_types'];
      return accepted is List && accepted.contains(contributionType);
    });
    if (!permitted) return;

    final roadmap = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.id.equals(task!.roadmapId!))).getSingleOrNull();
    if (roadmap == null) return;
    final roadmapPhaseId = task!.roadmapPhaseId;
    final effectId = _uuid.v4();
    final commandId = _uuid.v4();
    final roadmapCommandId = _uuid.v4();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final roadmapSequence = await DeviceIdentity.nextSequence();
    final now = DateTime.now().toUtc();
    final before =
        roadmap.requiredEffortMs == null || roadmap.requiredEffortMs == 0
        ? roadmap.progress
        : (roadmap.completedEffortMs / roadmap.requiredEffortMs!).clamp(0, 1);
    final afterEffort = roadmap.completedEffortMs + creditedDurationMs;
    final after =
        (roadmap.requiredEffortMs == null || roadmap.requiredEffortMs == 0
                ? roadmap.progress
                : (afterEffort / roadmap.requiredEffortMs!).clamp(0, 1))
            .toDouble();
    await database.transaction(() async {
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: effectId,
              userId: _userId,
              entityType: 'contribution_roadmap_effects',
              parentId: Value(roadmap.id),
              secondaryParentId: Value(contributionId),
              title: const Value('Approved activity contribution'),
              dataJson: Value(
                jsonEncode({
                  'contribution_id': contributionId,
                  'roadmap_id': roadmap.id,
                  'roadmap_phase_id': roadmapPhaseId,
                  'effect_type': contributionType,
                  'effect_value': creditedDurationMs.toDouble(),
                  'progress_before': before,
                  'progress_after': after,
                  'forecast_before': roadmap.forecastTargetDate
                      ?.toIso8601String(),
                  'forecast_after': roadmap.forecastTargetDate
                      ?.toIso8601String(),
                }),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (synchronize) {
        await _enqueue(
          commandId: commandId,
          deviceId: deviceId,
          sequence: sequence,
          entityType: 'contribution_roadmap_effects',
          entityId: effectId,
          payload: {
            'contribution_id': contributionId,
            'roadmap_id': roadmap.id,
            'roadmap_phase_id': roadmapPhaseId,
            'checkpoint_id': null,
            'effect_type': contributionType,
            'effect_value': creditedDurationMs.toDouble(),
            'progress_before': before,
            'progress_after': after,
            'forecast_before': roadmap.forecastTargetDate == null
                ? null
                : _dateOnly(roadmap.forecastTargetDate!),
            'forecast_after': roadmap.forecastTargetDate == null
                ? null
                : _dateOnly(roadmap.forecastTargetDate!),
            'data': <String, Object?>{},
          },
          now: now,
        );
      }
      await (database.update(
        database.localRoadmaps,
      )..where((row) => row.id.equals(roadmap.id))).write(
        LocalRoadmapsCompanion(
          completedEffortMs: Value(afterEffort),
          progress: Value(after),
          revision: Value(roadmap.revision + 1),
          updatedAt: Value(now),
        ),
      );
      if (synchronize) {
        await _enqueue(
          commandId: roadmapCommandId,
          deviceId: deviceId,
          sequence: roadmapSequence,
          entityType: 'roadmaps',
          entityId: roadmap.id,
          commandType: 'update',
          baseRevision: roadmap.revision,
          payload: {'completed_effort_ms': afterEffort, 'progress': after},
          now: now,
        );
      }
    });
  }

  Future<void> _recordClassificationFeedback({
    required ActivityReviewEntry entry,
    required ActivityResolution resolution,
    required bool synchronize,
  }) async {
    final entities = EntityRecordRepository(database, client);
    await entities.create(
      EntityRecordDraft(
        entityType: 'classification_feedback',
        title: _readableClassification(resolution.classification),
        parentId: entry.segment.id,
        status: resolution.status,
        synchronize: synchronize,
        data: {
          'activity_segment_id': entry.segment.id,
          'domain': entry.segment.domain,
          'suggested_classification': entry.review.suggestedClassification,
          'chosen_classification': resolution.classification,
          'suggested_target_type': entry.review.suggestedTargetType,
          'suggested_target_id': entry.review.suggestedTargetId,
          'chosen_target_type': resolution.targetType,
          'chosen_target_id': resolution.targetId,
          'feedback_type': resolution.rememberRule
              ? 'confirmed_and_remembered'
              : resolution.status,
        },
        syncPayload: {
          'activity_segment_id': entry.segment.id,
          'application_id': null,
          'domain': entry.segment.domain,
          'suggested_classification': entry.review.suggestedClassification,
          'chosen_classification': resolution.classification,
          'suggested_target_type': entry.review.suggestedTargetType,
          'suggested_target_id': entry.review.suggestedTargetId,
          'chosen_target_type': resolution.targetType,
          'chosen_target_id': resolution.targetId,
          'feedback_type': resolution.rememberRule
              ? 'confirmed_and_remembered'
              : resolution.status,
        },
      ),
    );
  }

  Future<void> _rememberApplicationRule({
    required ActivityReviewEntry entry,
    required ActivityResolution resolution,
    required bool synchronize,
  }) async {
    final identifier = _activityIdentifier(entry.segment);
    if (identifier == null || resolution.targetId == null) return;
    final entities = EntityRecordRepository(database, client);
    final catalogs = await entities.list(entityType: 'application_catalog');
    LocalEntityRecord? catalog;
    for (final candidate in catalogs) {
      final data = entities.decode(candidate);
      if ((data['application_identifier'] as String?)?.toLowerCase() ==
          identifier.toLowerCase()) {
        catalog = candidate;
        break;
      }
    }
    final applicationId =
        catalog?.id ??
        await entities.create(
          EntityRecordDraft(
            entityType: 'application_catalog',
            title: identifier,
            status: 'known',
            synchronize: synchronize,
            data: {
              'platform': entry.segment.sourceType.startsWith('android')
                  ? 'android'
                  : 'windows',
              'application_identifier': identifier,
              'display_name': entry.segment.processName ?? identifier,
              'classification': resolution.classification,
            },
            syncPayload: {
              'platform': entry.segment.sourceType.startsWith('android')
                  ? 'android'
                  : 'windows',
              'application_identifier': identifier,
              'display_name': entry.segment.processName ?? identifier,
              'publisher': null,
              'icon_path': null,
              'classification': resolution.classification,
              'first_seen_at': entry.segment.startedAt.toIso8601String(),
              'last_seen_at': entry.segment.endedAt.toIso8601String(),
            },
          ),
        );
    final existingRules = await entities.list(
      entityType: 'application_rules',
      parentId: resolution.targetId,
    );
    final duplicate = existingRules.any((rule) {
      final data = entities.decode(rule);
      return data['application_id'] == applicationId &&
          data['target_id'] == resolution.targetId &&
          data['contribution_type'] == resolution.contributionType &&
          data['automatic_credit'] == true;
    });
    if (duplicate) return;
    await entities.create(
      EntityRecordDraft(
        entityType: 'application_rules',
        parentId: resolution.targetId,
        secondaryParentId: applicationId,
        title: entry.segment.processName ?? identifier,
        status: 'active',
        synchronize: synchronize,
        data: {
          'application_id': applicationId,
          'scope_type': 'task',
          'scope_id': resolution.targetId,
          'classification': resolution.classification,
          'target_type': 'task_occurrence',
          'target_id': resolution.targetId,
          'contribution_type': resolution.contributionType,
          'automatic_credit': true,
          'priority': 200,
        },
        syncPayload: {
          'application_id': applicationId,
          'scope_type': 'task',
          'scope_id': resolution.targetId,
          'classification': resolution.classification,
          'target_type': 'task_occurrence',
          'target_id': resolution.targetId,
          'contribution_type': resolution.contributionType,
          'automatic_credit': true,
          'priority': 200,
        },
      ),
    );
  }

  Future<void> _applyTrustedRuleIfAvailable(String segmentId) async {
    final segment = await (database.select(
      database.localActivitySegments,
    )..where((row) => row.id.equals(segmentId))).getSingleOrNull();
    if (segment == null) return;
    final identifier = _activityIdentifier(segment);
    if (identifier == null) return;
    final entities = EntityRecordRepository(database, client);
    final catalogs = await entities.list(entityType: 'application_catalog');
    String? applicationId;
    for (final candidate in catalogs) {
      final data = entities.decode(candidate);
      if ((data['application_identifier'] as String?)?.toLowerCase() ==
          identifier.toLowerCase()) {
        applicationId = candidate.id;
        break;
      }
    }
    if (applicationId == null) return;
    final rules = await entities.list(entityType: 'application_rules');
    LocalEntityRecord? matchedRule;
    for (final candidate in rules) {
      final data = entities.decode(candidate);
      if (candidate.status == 'active' &&
          data['application_id'] == applicationId &&
          data['automatic_credit'] == true &&
          data['target_id'] is String &&
          data['contribution_type'] is String) {
        matchedRule = candidate;
        break;
      }
    }
    if (matchedRule == null) return;
    final review =
        await (database.select(database.localActivityReviews)..where(
              (row) =>
                  row.activitySegmentId.equals(segmentId) &
                  row.status.equals('pending'),
            ))
            .getSingleOrNull();
    if (review == null) return;
    final ruleData = entities.decode(matchedRule);
    await resolve(
      ActivityReviewEntry(review: review, segment: segment),
      ActivityResolution(
        status: 'confirmed',
        classification:
            ruleData['classification'] as String? ?? 'direct_task_work',
        targetType: ruleData['target_type'] as String? ?? 'task_occurrence',
        targetId: ruleData['target_id'] as String,
        contributionType:
            ruleData['contribution_type'] as String? ?? 'active_work_seconds',
        isAutomatic: true,
      ),
    );
  }

  String? _activityIdentifier(LocalActivitySegment segment) {
    final value = jsonDecode(segment.rawMetadataJson);
    final metadata = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    final packageName = metadata['package_name'] as String?;
    final identifier = packageName ?? segment.processName;
    return identifier == null || identifier.trim().isEmpty
        ? null
        : identifier.trim();
  }

  String _readableClassification(String value) => value.replaceAll('_', ' ');

  String _dateOnly(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _enqueue({
    required String commandId,
    required String deviceId,
    required int sequence,
    required String entityType,
    required String entityId,
    String commandType = 'create',
    int baseRevision = 0,
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
            entityType: entityType,
            entityId: entityId,
            commandType: commandType,
            baseRevision: baseRevision,
            payloadJson: jsonEncode(payload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }
}
