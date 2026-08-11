import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/data/entity_record_repository.dart';
import '../../../core/platform/device_identity.dart';
import '../../tasks/data/installed_application_service.dart';
import '../../tasks/data/website_rule_service.dart';
import 'activity_privacy_policy.dart';

/// Stable per-account identity for an observed application.
///
/// Two devices can discover the same application before either has pulled the
/// other's catalog row. A random UUID makes those legitimate offline creates
/// collide with the server's `(user_id, platform, application_identifier)`
/// uniqueness rule. UUID v5 makes the create idempotent on every device.
String applicationCatalogIdFor({
  required String userId,
  required String platform,
  required String applicationIdentifier,
}) {
  final normalizedPlatform = platform.trim().toLowerCase();
  final normalizedIdentifier = applicationIdentifier.trim().toLowerCase();
  return const Uuid().v5(
    Namespace.url.value,
    'https://taskmasterpro.app/account/$userId/application/'
    '$normalizedPlatform/$normalizedIdentifier',
  );
}

/// Permanent identities for the records created by one Activity decision.
///
/// These UUIDs depend only on authenticated IDs and stable record IDs. Human
/// names, translated labels, app display names, and list positions never
/// participate in synchronization identity.
String activityAttributionIdFor({
  required String userId,
  required String reviewItemId,
  required String classification,
  required String? targetTaskId,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/activity-review/$reviewItemId/'
  'attribution/$classification/${targetTaskId ?? 'none'}',
);

String activityContributionIdFor({
  required String userId,
  required String activitySegmentId,
  required String targetTaskId,
  required String contributionType,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/activity-segment/'
  '$activitySegmentId/task/$targetTaskId/contribution/$contributionType',
);

String activityClassificationCommandIdFor({
  required String userId,
  required String reviewItemId,
  required String classification,
  required String? targetTaskId,
  required String? contributionType,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/activity-review/$reviewItemId/'
  'classify/$classification/${targetTaskId ?? 'none'}/'
  '${contributionType ?? 'none'}',
);

String activityClassificationFeedbackIdFor({
  required String userId,
  required String reviewItemId,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/activity-review/$reviewItemId/'
  'classification-feedback',
);

String activityRuleIdFor({
  required String userId,
  required String applicationId,
  required String scopeType,
  required String scopeId,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/application/$applicationId/'
  'rule/$scopeType/$scopeId',
);

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

class _AtomicActivityRule {
  const _AtomicActivityRule({
    required this.id,
    required this.applicationId,
    required this.applicationPlatform,
    required this.applicationIdentifier,
    required this.applicationDisplayName,
    required this.scopeType,
    required this.scopeId,
  });

  final String id;
  final String applicationId;
  final String applicationPlatform;
  final String applicationIdentifier;
  final String applicationDisplayName;
  final String scopeType;
  final String scopeId;
}

class ActivityRepository {
  ActivityRepository(this.database, this.client);

  final AppDatabase database;
  final SupabaseClient client;
  static const _uuid = Uuid();

  String get _userId => client.auth.currentUser?.id ?? 'local';
  String get currentUserId => _userId;
  String get settingsId => localAppSettingsId(_userId);

  Future<String> captureRawSegment({
    String? segmentId,
    required DateTime startedAt,
    required DateTime endedAt,
    required String sourceType,
    String? processName,
    String? windowTitle,
    String? idleState,
    String? packageName,
    String? domain,
    String? url,
    String? pageTitle,
    double confidence = 0.9,
    bool createReview = true,
    bool isFinalized = true,
  }) async {
    if (!endedAt.isAfter(startedAt)) {
      throw ArgumentError('Activity segment must have a positive duration');
    }
    final existing = segmentId == null
        ? null
        : await (database.select(database.localActivitySegments)..where(
                (row) => row.id.equals(segmentId) & row.userId.equals(_userId),
              ))
              .getSingleOrNull();
    final id = existing?.id ?? segmentId ?? _uuid.v4();
    final deviceId =
        existing?.deviceId ?? await DeviceIdentity.accountId(_userId);
    final deviceEventId =
        existing?.deviceEventId ??
        '$deviceId:${startedAt.microsecondsSinceEpoch}:'
            '${endedAt.microsecondsSinceEpoch}';
    final now = DateTime.now().toUtc();
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(settingsId))).getSingleOrNull();
    final privacyPolicy = await ActivityPrivacyPolicy.load(database, _userId);
    // Device usage outside a tracked task is private to this device by
    // default.  A user can explicitly enable detailed Activity history sync;
    // otherwise a segment is only queued later when it is approved as a task
    // contribution or a trusted rule uses it.
    final synchronizeDetailedActivity = privacyPolicy
        .allowsDetailedActivityUpload(settings);
    final includeSensitiveDetails = synchronizeDetailedActivity;
    final runtime = await (database.select(
      database.localRuntimeStates,
    )..where((row) => row.userId.equals(_userId))).getSingleOrNull();
    final metadata = <String, Object?>{'captured_compactly': true};
    if (packageName != null) metadata['package_name'] = packageName;
    final website =
        NormalizedWebsiteAddress.tryParse(url) ??
        NormalizedWebsiteAddress.tryParse(domain);
    if (website != null) {
      metadata['registrable_domain'] = website.registrableDomain;
      metadata['host'] = website.host;
      metadata['normalized_path'] = website.normalizedPath;
    }
    metadata['source_task_id'] = runtime?.activeTaskId;
    metadata['source_session_id'] = runtime?.sessionId;
    metadata['source_runtime_state'] = runtime?.state;
    final synchronizedMetadata = <String, Object?>{
      'normalized': true,
      'raw_samples_included': false,
    };
    if (includeSensitiveDetails && packageName != null) {
      synchronizedMetadata['package_name'] = packageName;
    }
    final activeTaskId = runtime?.activeTaskId;
    final sessionId = runtime?.sessionId;
    final runtimeState = runtime?.state;
    if (activeTaskId != null) {
      synchronizedMetadata['source_task_id'] = activeTaskId;
    }
    if (sessionId != null) {
      synchronizedMetadata['source_session_id'] = sessionId;
    }
    if (runtimeState != null) {
      synchronizedMetadata['source_runtime_state'] = runtimeState;
    }
    await database.transaction(() async {
      if (existing == null) {
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
                domain: Value(website?.host ?? domain),
                url: Value(url),
                pageTitle: Value(pageTitle),
                idleState: Value(idleState),
                captureConfidence: Value(confidence),
                rawMetadataJson: Value(jsonEncode(metadata)),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (database.update(
          database.localActivitySegments,
        )..where((row) => row.id.equals(id))).write(
          LocalActivitySegmentsCompanion(
            endedAt: Value(endedAt.toUtc()),
            processName: Value(processName),
            windowTitle: Value(windowTitle),
            domain: Value(website?.host ?? domain),
            url: Value(url),
            pageTitle: Value(pageTitle),
            idleState: Value(idleState),
            captureConfidence: Value(confidence),
            rawMetadataJson: Value(jsonEncode(metadata)),
            // `revision` is the server's canonical revision.  A local
            // extension is optimistic data, not a new remote revision; the
            // synchronization service advances it only after an accepted
            // command.  Incrementing it here made an active segment race
            // ahead of Supabase and caused every later extension to conflict.
            revision: Value(existing.revision),
            updatedAt: Value(now),
          ),
        );
      }
      if (synchronizeDetailedActivity && isFinalized) {
        final payload = <String, Object?>{
          'device_id': deviceId,
          'device_event_id': deviceEventId,
          'started_at': startedAt.toUtc().toIso8601String(),
          'ended_at': endedAt.toUtc().toIso8601String(),
          'source_type': sourceType,
          'application_id': null,
          'website_rule_id': null,
          'resource_id': null,
          'process_name': includeSensitiveDetails ? processName : null,
          'window_title': includeSensitiveDetails ? windowTitle : null,
          // The registrable/host identity is enough to reconcile an explicit
          // task rule. Full URL and page title stay opt-in detailed Activity
          // data and are never needed for a whole-site match.
          'domain': website?.host,
          'url': includeSensitiveDetails ? url : null,
          'page_title': includeSensitiveDetails ? pageTitle : null,
          'input_state': idleState == 'technical_idle' ? 'idle' : 'active',
          'idle_state': idleState,
          'screen_state': 'unlocked',
          'capture_confidence': confidence,
          'raw_metadata': synchronizedMetadata,
          'data': <String, Object?>{
            'normalization_version': 1,
            'capture_state': 'finalized',
            'detail_level': includeSensitiveDetails
                ? 'sensitive_details_enabled'
                : 'privacy_safe',
          },
        };
        await _coalesceSegmentCommand(
          existing: existing,
          entityId: id,
          deviceId: deviceId,
          payload: payload,
          now: now,
        );
      }
      if (createReview && existing == null) {
        final reviewId = _uuid.v4();
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
      }
      if (synchronizeDetailedActivity && isFinalized) {
        final review =
            await (database.select(database.localActivityReviews)
                  ..where(
                    (row) =>
                        row.userId.equals(_userId) &
                        row.activitySegmentId.equals(id) &
                        row.deletedAt.isNull(),
                  )
                  ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
                  ..limit(1))
                .getSingleOrNull();
        if (review != null) {
          await _enqueueDetailedReviewSync(
            review: review,
            deviceId: deviceId,
            now: now,
          );
        }
      }
    });
    if (createReview) {
      final handledBySystemRule = await _applyLocalSystemClassification(id);
      if (!handledBySystemRule && settings?.automaticTrustedRules == true) {
        await _applyTrustedRuleIfAvailable(id);
      }
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

  Future<List<Map<String, Object?>>> exportLocalActivity() async {
    final segments =
        await (database.select(database.localActivitySegments)
              ..where(
                (row) => row.userId.equals(_userId) & row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]))
            .get();
    return [
      for (final segment in segments)
        {
          'id': segment.id,
          'device_id': segment.deviceId,
          'started_at': segment.startedAt.toIso8601String(),
          'ended_at': segment.endedAt.toIso8601String(),
          'source_type': segment.sourceType,
          'application': segment.processName,
          'window_title': segment.windowTitle,
          'domain': segment.domain,
          'page_title': segment.pageTitle,
          'idle_state': segment.idleState,
          'metadata': jsonDecode(segment.rawMetadataJson),
        },
    ];
  }

  Future<int> purgeExpiredLocalActivity({int? retentionDays}) async {
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(settingsId))).getSingleOrNull();
    final days = retentionDays ?? settings?.localActivityRetentionDays ?? 30;
    if (days <= 0) return 0;
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: days));
    final expired =
        await (database.select(database.localActivitySegments)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.endedAt.isSmallerThanValue(cutoff),
            ))
            .get();
    return _deleteRawSegments(expired.map((item) => item.id).toSet());
  }

  Future<int> clearUnclassifiedLocalActivity() async {
    final segments = await (database.select(
      database.localActivitySegments,
    )..where((row) => row.userId.equals(_userId))).get();
    final contributions = await (database.select(
      database.localContributions,
    )..where((row) => row.userId.equals(_userId))).get();
    final protected = contributions
        .map((item) => item.activitySegmentId)
        .toSet();
    return _deleteRawSegments(
      segments
          .where((segment) => !protected.contains(segment.id))
          .map((segment) => segment.id)
          .toSet(),
    );
  }

  Future<int> clearSystemLocalActivity() async {
    final attributions =
        await (database.select(database.localAttributions)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.classification.isIn(const [
                    'system_activity',
                    'possible_system_activity',
                  ]),
            ))
            .get();
    return _deleteRawSegments(
      attributions.map((item) => item.activitySegmentId).toSet(),
    );
  }

  Future<int> clearAllLocalActivityDetails() async {
    final segments = await (database.select(
      database.localActivitySegments,
    )..where((row) => row.userId.equals(_userId))).get();
    return _deleteRawSegments(segments.map((item) => item.id).toSet());
  }

  Future<int> _deleteRawSegments(Set<String> ids) async {
    if (ids.isEmpty) return 0;
    await database.transaction(() async {
      await (database.delete(
        database.localActivityReviews,
      )..where((row) => row.activitySegmentId.isIn(ids))).go();
      await (database.delete(
        database.localAttributions,
      )..where((row) => row.activitySegmentId.isIn(ids))).go();
      await (database.delete(
        database.localActivitySegments,
      )..where((row) => row.id.isIn(ids))).go();
    });
    return ids.length;
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

  Future<ActivityReviewEntry?> reviewEntryForSegment(String segmentId) async {
    final segment =
        await (database.select(database.localActivitySegments)..where(
              (row) => row.id.equals(segmentId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (segment == null) return null;
    final existing =
        await (database.select(database.localActivityReviews)
              ..where(
                (row) =>
                    row.activitySegmentId.equals(segmentId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      return ActivityReviewEntry(review: existing, segment: segment);
    }

    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(settingsId))).getSingleOrNull();
    final privacyPolicy = await ActivityPrivacyPolicy.load(database, _userId);
    final synchronizeDetailedActivity = privacyPolicy
        .allowsDetailedActivityUpload(settings);
    final now = DateTime.now().toUtc();
    final reviewId = _uuid.v4();
    final review = LocalActivityReview(
      id: reviewId,
      userId: _userId,
      activitySegmentId: segmentId,
      reviewReason: 'manual_review',
      priority: 2,
      suggestedTargetType: null,
      suggestedTargetId: null,
      suggestedTargetTitle: null,
      suggestedClassification: 'requires_review',
      confidence: segment.captureConfidence,
      status: 'pending',
      reviewedAt: null,
      revision: 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    await database.into(database.localActivityReviews).insert(review);
    if (synchronizeDetailedActivity) {
      final deviceId = await DeviceIdentity.accountId(_userId);
      await _enqueueDetailedReviewSync(
        review: review,
        deviceId: deviceId,
        now: now,
      );
    }
    return ActivityReviewEntry(review: review, segment: segment);
  }

  Future<void> resolve(
    ActivityReviewEntry entry,
    ActivityResolution resolution,
  ) async {
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(settingsId))).getSingleOrNull();
    final privacyPolicy = await ActivityPrivacyPolicy.load(database, _userId);
    final synchronizeContributions = privacyPolicy
        .allowsApprovedContributionUpload(settings);
    final synchronizeRules = settings?.activityRuleSyncEnabled ?? true;
    final synchronizeDetailedActivity = privacyPolicy
        .allowsDetailedActivityUpload(settings);
    final shouldCredit =
        resolution.status == 'confirmed' &&
        resolution.targetId != null &&
        resolution.contributionType != null;
    // A reviewed device-usage period becomes shared only when it has a
    // concrete task contribution.  Otherwise its review remains local, while
    // an optional remembered rule is synchronized separately below.
    final synchronizeActivity =
        synchronizeDetailedActivity ||
        (synchronizeContributions && shouldCredit);
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final segmentCommandId = synchronizeActivity ? _uuid.v4() : null;
    final segmentSequence = synchronizeActivity
        ? await DeviceIdentity.nextSequence(_userId)
        : null;
    final attributionId = activityAttributionIdFor(
      userId: _userId,
      reviewItemId: entry.review.id,
      classification: resolution.classification,
      targetTaskId: resolution.targetId,
    );
    final contributionId = shouldCredit
        ? activityContributionIdFor(
            userId: _userId,
            activitySegmentId: entry.segment.id,
            targetTaskId: resolution.targetId!,
            contributionType: resolution.contributionType!,
          )
        : null;
    final classificationCommandId = activityClassificationCommandIdFor(
      userId: _userId,
      reviewItemId: entry.review.id,
      classification: resolution.classification,
      targetTaskId: resolution.targetId,
      contributionType: resolution.contributionType,
    );
    final classificationFeedbackId = activityClassificationFeedbackIdFor(
      userId: _userId,
      reviewItemId: entry.review.id,
    );
    final classificationSequence = synchronizeActivity
        ? await DeviceIdentity.nextSequence(_userId)
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
    final atomicRule =
        synchronizeActivity && synchronizeRules && resolution.rememberRule
        ? await _prepareAtomicRule(
            entry: entry,
            resolution: resolution,
            commandId: classificationCommandId,
            now: now,
          )
        : null;

    await database.transaction(() async {
      if (synchronizeActivity) {
        await _enqueueApprovedSegmentSync(
          segment: entry.segment,
          currentDeviceId: deviceId,
          includeSensitiveDetails: synchronizeDetailedActivity,
          approvedContribution: shouldCredit,
          commandId: segmentCommandId!,
          sequence: segmentSequence!,
          now: now,
        );
      }
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
      await database
          .into(database.localAttributions)
          .insertOnConflictUpdate(
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

      if (shouldCredit) {
        final isCrossTask =
            sourceTaskId != null && sourceTaskId != resolution.targetId;
        await database
            .into(database.localContributions)
            .insertOnConflictUpdate(
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
        await database
            .into(database.localEntityRecords)
            .insertOnConflictUpdate(
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

      if (synchronizeActivity) {
        final localStartedAt = entry.segment.startedAt.toLocal();
        await _enqueue(
          commandId: classificationCommandId,
          deviceId: deviceId,
          sequence: classificationSequence!,
          entityType: 'activity_review_classifications',
          entityId: entry.review.id,
          commandType: 'classify',
          baseRevision: entry.review.revision,
          payload: {
            'activity_segment_id': entry.segment.id,
            'review_reason': entry.review.reviewReason,
            'priority': entry.review.priority,
            'status': resolution.status,
            'classification': resolution.classification,
            'target_type': resolution.targetType,
            'target_task_id': resolution.targetId,
            'contribution_type': resolution.contributionType,
            'physical_duration_ms': physicalDurationMs,
            'credited_duration_ms': creditedDurationMs,
            'source_task_id': sourceTaskId,
            'source_session_id': sourceSessionId,
            'is_idle_derived': entry.segment.idleState == 'technical_idle',
            'is_automatic': resolution.isAutomatic,
            'confidence': entry.review.confidence ?? 1,
            'attribution_id': attributionId,
            'contribution_id': contributionId,
            'classification_feedback_id': classificationFeedbackId,
            'suggested_classification': entry.review.suggestedClassification,
            'suggested_target_type': entry.review.suggestedTargetType,
            'suggested_target_id': entry.review.suggestedTargetId,
            'feedback_type': resolution.rememberRule
                ? 'confirmed_and_remembered'
                : resolution.status,
            'rule_scope': atomicRule?.scopeType,
            'rule_scope_id': atomicRule?.scopeId,
            'rule_id': atomicRule?.id,
            'application_id': atomicRule?.applicationId,
            'application_platform': atomicRule?.applicationPlatform,
            'application_identifier': atomicRule?.applicationIdentifier,
            'application_display_name': atomicRule?.applicationDisplayName,
            'rule_priority': resolution.targetId == null ? 300 : 200,
            'contribution_data': <String, Object?>{
              'source_device_id': deviceId,
              'local_calendar_date':
                  '${localStartedAt.year.toString().padLeft(4, '0')}-'
                  '${localStartedAt.month.toString().padLeft(2, '0')}-'
                  '${localStartedAt.day.toString().padLeft(2, '0')}',
              'utc_started_at': entry.segment.startedAt.toIso8601String(),
              'utc_ended_at': entry.segment.endedAt.toIso8601String(),
              'activity_category': resolution.classification,
              'source_type': entry.segment.sourceType,
              'classification_source': resolution.isAutomatic
                  ? 'approved_rule'
                  : 'user',
              'confidence': entry.review.confidence ?? 1,
              'privacy_safe_source_label': _privacySafeLabel(entry.segment),
              'raw_details_included': false,
            },
          },
          now: now,
        );
      }
    });

    await _recordClassificationFeedback(
      entry: entry,
      resolution: resolution,
      id: classificationFeedbackId,
      // The classification RPC stores the synchronized feedback in the same
      // transaction. This local insert remains the offline-first projection.
      synchronize: false,
    );
    if (resolution.rememberRule && atomicRule == null) {
      if (shouldCredit && resolution.targetType == 'task_occurrence') {
        await _rememberApplicationRule(
          entry: entry,
          resolution: resolution,
          synchronize: synchronizeRules,
        );
      } else if (resolution.classification == 'system_activity' ||
          resolution.classification == 'user_application' ||
          resolution.classification == 'generally_unrelated' ||
          resolution.classification == 'unrelated') {
        await _rememberNegativeOrSystemRule(
          entry: entry,
          resolution: resolution,
          synchronize: synchronizeRules,
        );
      }
    }
    if (shouldCredit && resolution.targetType == 'task_occurrence') {
      await _applyPermittedRoadmapEffects(
        taskId: resolution.targetId!,
        contributionId: contributionId!,
        contributionType: resolution.contributionType!,
        creditedDurationMs: creditedDurationMs,
        synchronize: synchronizeContributions,
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
    final deviceId = await DeviceIdentity.accountId(_userId);
    final sequence = await DeviceIdentity.nextSequence(_userId);
    final roadmapSequence = await DeviceIdentity.nextSequence(_userId);
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
    required String id,
    required bool synchronize,
  }) async {
    final entities = EntityRecordRepository(database, client);
    await entities.create(
      EntityRecordDraft(
        id: id,
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

  Future<_AtomicActivityRule?> _prepareAtomicRule({
    required ActivityReviewEntry entry,
    required ActivityResolution resolution,
    required String commandId,
    required DateTime now,
  }) async {
    final identifier = _activityRuleIdentifier(entry.segment);
    if (identifier == null) return null;
    final platform = entry.segment.sourceType.startsWith('android')
        ? 'android'
        : 'windows';
    final entities = EntityRecordRepository(database, client);
    final catalogs = await entities.list(entityType: 'application_catalog');
    LocalEntityRecord? catalog;
    for (final candidate in catalogs) {
      final data = _entityData(entities, candidate);
      if ((data['application_identifier'] as String?)?.toLowerCase() ==
              identifier.toLowerCase() &&
          (data['platform'] as String?)?.toLowerCase() == platform) {
        catalog = candidate;
        break;
      }
    }
    final applicationId =
        catalog?.id ??
        applicationCatalogIdFor(
          userId: _userId,
          platform: platform,
          applicationIdentifier: identifier,
        );
    final metadataValue = jsonDecode(entry.segment.rawMetadataJson);
    final metadata = metadataValue is Map
        ? Map<String, Object?>.from(metadataValue)
        : const <String, Object?>{};
    final sourceTaskId = metadata['source_task_id'] as String?;
    final scopeType =
        resolution.targetId != null ||
            (resolution.classification == 'unrelated' && sourceTaskId != null)
        ? 'task'
        : 'user';
    final scopeId =
        resolution.targetId ?? (scopeType == 'task' ? sourceTaskId : _userId);
    if (scopeId == null) return null;
    final rules = await entities.list(entityType: 'application_rules');
    LocalEntityRecord? existingRule;
    for (final candidate in rules) {
      final data = _entityData(entities, candidate);
      if (data['application_id'] == applicationId &&
          data['scope_type'] == scopeType &&
          data['scope_id'] == scopeId) {
        existingRule = candidate;
        break;
      }
    }
    final ruleId =
        existingRule?.id ??
        activityRuleIdFor(
          userId: _userId,
          applicationId: applicationId,
          scopeType: scopeType,
          scopeId: scopeId,
        );
    final deviceId = await DeviceIdentity.accountId(_userId);
    final displayName = _privacySafeLabel(entry.segment);
    final catalogData = <String, Object?>{
      'platform': platform,
      'application_identifier': identifier.toLowerCase(),
      'display_name': displayName,
      'classification': resolution.classification,
    };
    final ruleData = <String, Object?>{
      'application_id': applicationId,
      'platform': platform,
      'application_identifier': identifier.toLowerCase(),
      'scope_type': scopeType,
      'scope_id': scopeId,
      'classification': resolution.classification,
      'target_type': resolution.targetId == null ? null : resolution.targetType,
      'target_id': resolution.targetId,
      'contribution_type': resolution.contributionType,
      'automatic_credit':
          resolution.targetId != null && resolution.contributionType != null,
      'priority': resolution.targetId == null ? 300 : 200,
      'rule_origin': 'user_confirmed',
    };
    await database.transaction(() async {
      await database
          .into(database.localEntityRecords)
          .insertOnConflictUpdate(
            LocalEntityRecordsCompanion.insert(
              id: applicationId,
              userId: _userId,
              entityType: 'application_catalog',
              title: Value(displayName),
              status: const Value('known'),
              dataJson: Value(jsonEncode(catalogData)),
              createdAt: catalog?.createdAt ?? now,
              updatedAt: now,
              createdByDeviceId: Value(catalog?.createdByDeviceId ?? deviceId),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await database
          .into(database.localEntityRecords)
          .insertOnConflictUpdate(
            LocalEntityRecordsCompanion.insert(
              id: ruleId,
              userId: _userId,
              entityType: 'application_rules',
              parentId: Value(scopeId),
              secondaryParentId: Value(applicationId),
              title: Value(displayName),
              status: const Value('active'),
              dataJson: Value(jsonEncode(ruleData)),
              createdAt: existingRule?.createdAt ?? now,
              updatedAt: now,
              createdByDeviceId: Value(
                existingRule?.createdByDeviceId ?? deviceId,
              ),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
    });
    return _AtomicActivityRule(
      id: ruleId,
      applicationId: applicationId,
      applicationPlatform: platform,
      applicationIdentifier: identifier.toLowerCase(),
      applicationDisplayName: displayName,
      scopeType: scopeType,
      scopeId: scopeId,
    );
  }

  Future<void> _rememberApplicationRule({
    required ActivityReviewEntry entry,
    required ActivityResolution resolution,
    required bool synchronize,
  }) async {
    final identifier = _activityIdentifier(entry.segment);
    if (identifier == null || resolution.targetId == null) return;
    final platform = entry.segment.sourceType.startsWith('android')
        ? 'android'
        : 'windows';
    final entities = EntityRecordRepository(database, client);
    final catalogs = await entities.list(entityType: 'application_catalog');
    LocalEntityRecord? catalog;
    for (final candidate in catalogs) {
      final data = _entityData(entities, candidate);
      if ((data['application_identifier'] as String?)?.toLowerCase() ==
              identifier.toLowerCase() &&
          (data['platform'] as String?)?.toLowerCase() == platform) {
        catalog = candidate;
        break;
      }
    }
    final applicationId =
        catalog?.id ??
        await entities.create(
          EntityRecordDraft(
            id: applicationCatalogIdFor(
              userId: _userId,
              platform: platform,
              applicationIdentifier: identifier,
            ),
            entityType: 'application_catalog',
            title: identifier,
            status: 'known',
            synchronize: synchronize,
            data: {
              'platform': platform,
              'application_identifier': identifier,
              'display_name': entry.segment.processName ?? identifier,
              'classification': resolution.classification,
            },
            syncPayload: {
              'platform': platform,
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
      final data = _entityData(entities, rule);
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

  Future<void> _rememberNegativeOrSystemRule({
    required ActivityReviewEntry entry,
    required ActivityResolution resolution,
    required bool synchronize,
  }) async {
    final identifier = _activityRuleIdentifier(entry.segment);
    if (identifier == null) return;
    final platform = entry.segment.sourceType.startsWith('android')
        ? 'android'
        : 'windows';
    final metadataValue = jsonDecode(entry.segment.rawMetadataJson);
    final metadata = metadataValue is Map
        ? Map<String, Object?>.from(metadataValue)
        : const <String, Object?>{};
    final sourceTaskId = metadata['source_task_id'] as String?;
    final scopeType =
        resolution.classification == 'unrelated' && sourceTaskId != null
        ? 'task'
        : 'user';
    final scopeId = scopeType == 'task' ? sourceTaskId : _userId;
    final entities = EntityRecordRepository(database, client);
    final catalogs = await entities.list(entityType: 'application_catalog');
    LocalEntityRecord? catalog;
    for (final candidate in catalogs) {
      final data = _entityData(entities, candidate);
      if ((data['application_identifier'] as String?)?.toLowerCase() ==
              identifier.toLowerCase() &&
          (data['platform'] as String?)?.toLowerCase() == platform) {
        catalog = candidate;
        break;
      }
    }
    final applicationId =
        catalog?.id ??
        await entities.create(
          EntityRecordDraft(
            id: applicationCatalogIdFor(
              userId: _userId,
              platform: platform,
              applicationIdentifier: identifier,
            ),
            entityType: 'application_catalog',
            title: _privacySafeLabel(entry.segment),
            status: 'known',
            synchronize: synchronize,
            data: {
              'platform': platform,
              'application_identifier': identifier.toLowerCase(),
              'display_name': _privacySafeLabel(entry.segment),
              'classification': resolution.classification,
            },
            syncPayload: {
              'platform': platform,
              'application_identifier': identifier.toLowerCase(),
              'display_name': _privacySafeLabel(entry.segment),
              'publisher': null,
              'icon_path': null,
              'classification': resolution.classification,
              'first_seen_at': entry.segment.startedAt.toIso8601String(),
              'last_seen_at': entry.segment.endedAt.toIso8601String(),
            },
          ),
        );
    final rules = await entities.list(entityType: 'application_rules');
    for (final rule in rules) {
      final data = _entityData(entities, rule);
      if (rule.status == 'active' &&
          data['application_id'] == applicationId &&
          data['scope_type'] == scopeType &&
          data['scope_id'] == scopeId &&
          data['classification'] == resolution.classification) {
        return;
      }
    }
    await entities.create(
      EntityRecordDraft(
        entityType: 'application_rules',
        parentId: scopeId,
        title: _privacySafeLabel(entry.segment),
        status: 'active',
        synchronize: synchronize,
        data: {
          'application_id': applicationId,
          'platform': entry.segment.sourceType.startsWith('android')
              ? 'android'
              : 'windows',
          'application_identifier': identifier.toLowerCase(),
          'scope_type': scopeType,
          'scope_id': scopeId,
          'classification': resolution.classification,
          'automatic_credit': false,
          'rule_origin': 'user_confirmed',
        },
        syncPayload: {
          'application_id': applicationId,
          'scope_type': scopeType,
          'scope_id': scopeId,
          'classification': resolution.classification,
          'target_type': null,
          'target_id': null,
          'contribution_type': null,
          'automatic_credit': false,
          'priority': 300,
          'data': {
            'platform': entry.segment.sourceType.startsWith('android')
                ? 'android'
                : 'windows',
            'application_identifier': identifier.toLowerCase(),
            'rule_origin': 'user_confirmed',
          },
        },
      ),
    );
  }

  Future<bool> _applyLocalSystemClassification(String segmentId) async {
    final segment = await (database.select(
      database.localActivitySegments,
    )..where((row) => row.id.equals(segmentId))).getSingleOrNull();
    if (segment == null) return false;
    final identifier = _activityRuleIdentifier(segment)?.toLowerCase();
    if (identifier == null) return false;
    final entities = EntityRecordRepository(database, client);
    final rules = await entities.list(entityType: 'application_rules');
    LocalEntityRecord? matchedRule;
    for (final candidate in rules) {
      final data = _entityData(entities, candidate);
      if (candidate.status == 'active' &&
          data['application_identifier'] == identifier &&
          data['scope_type'] == 'user' &&
          data['scope_id'] == _userId &&
          const {
            'system_activity',
            'user_application',
            'generally_unrelated',
          }.contains(data['classification'])) {
        matchedRule = candidate;
        break;
      }
    }
    final review =
        await (database.select(database.localActivityReviews)..where(
              (row) =>
                  row.activitySegmentId.equals(segmentId) &
                  row.status.equals('pending'),
            ))
            .getSingleOrNull();
    if (review == null) return false;
    if (matchedRule != null) {
      final data = _entityData(entities, matchedRule);
      final classification = data['classification'] as String;
      if (classification == 'user_application') {
        await _insertLocalAttribution(
          segment: segment,
          classification: classification,
          status: 'confirmed',
          confirmedByUser: true,
          confidence: 1,
        );
        return false;
      }
      await resolve(
        ActivityReviewEntry(review: review, segment: segment),
        ActivityResolution(
          status: classification == 'system_activity' ? 'ignored' : 'rejected',
          classification: classification,
          isAutomatic: true,
        ),
      );
      return true;
    }
    if (_isPossibleSystemActivity(segment)) {
      await _insertLocalAttribution(
        segment: segment,
        classification: 'possible_system_activity',
        status: 'proposed',
        confirmedByUser: false,
        confidence: 0.95,
      );
    }
    return false;
  }

  Future<void> _insertLocalAttribution({
    required LocalActivitySegment segment,
    required String classification,
    required String status,
    required bool confirmedByUser,
    required double confidence,
  }) async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.localAttributions)
        .insert(
          LocalAttributionsCompanion.insert(
            id: _uuid.v4(),
            userId: _userId,
            activitySegmentId: segment.id,
            targetType: 'unassigned_activity',
            classification: classification,
            confidence: confidence,
            attributionStatus: Value(status),
            confirmedByUser: Value(confirmedByUser),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  bool _isPossibleSystemActivity(LocalActivitySegment segment) {
    final identifier = _activityIdentifier(segment)?.toLowerCase();
    if (identifier == null) return false;
    if (segment.sourceType.startsWith('android')) {
      if (segment.sourceType != 'android_usage') return false;
      return const {
        'com.android.systemui',
        'com.google.android.permissioncontroller',
        'com.android.permissioncontroller',
        'com.android.launcher3',
        'com.google.android.inputmethod.latin',
      }.contains(identifier);
    }
    if (segment.sourceType != 'windows_foreground') return false;
    // Deliberately exclude ambiguous interactive tools such as explorer.exe,
    // powershell.exe, cmd.exe, node.exe, python.exe, java.exe, and adb.exe.
    return const {
      'shellexperiencehost.exe',
      'startmenuexperiencehost.exe',
      'searchhost.exe',
      'lockapp.exe',
      'securityhealthsystray.exe',
      'systemsettings.exe',
      'applicationframehost.exe',
      'consent.exe',
      'werfault.exe',
    }.contains(identifier);
  }

  Future<void> _applyTrustedRuleIfAvailable(String segmentId) async {
    final segment = await (database.select(
      database.localActivitySegments,
    )..where((row) => row.id.equals(segmentId))).getSingleOrNull();
    if (segment == null) return;
    final entities = EntityRecordRepository(database, client);
    final metadataValue = jsonDecode(segment.rawMetadataJson);
    final metadata = metadataValue is Map
        ? Map<String, Object?>.from(metadataValue)
        : const <String, Object?>{};
    final sourceTaskId = metadata['source_task_id'] as String?;
    // Website rules are task relationships, not one-time page strings. Match
    // the normalized host/site/path before falling back to an application
    // rule. When a site belongs to several tasks without a currently running
    // task, the selector returns null so one physical interval is never
    // credited twice.
    final websiteRules = await entities.list(entityType: 'website_rules');
    final matchingWebsiteRule = selectWebsiteRuleForActivity(
      [
        for (final rule in websiteRules)
          <String, Object?>{
            ..._entityData(entities, rule),
            'status': rule.status,
          },
      ],
      url: segment.url,
      domain: segment.domain,
      sourceTaskId: sourceTaskId,
    );
    if (matchingWebsiteRule != null) {
      final review =
          await (database.select(database.localActivityReviews)..where(
                (row) =>
                    row.activitySegmentId.equals(segmentId) &
                    row.status.equals('pending'),
              ))
              .getSingleOrNull();
      if (review != null) {
        await resolve(
          ActivityReviewEntry(review: review, segment: segment),
          ActivityResolution(
            status: 'confirmed',
            classification:
                matchingWebsiteRule['classification'] as String? ??
                'direct_task_work',
            targetType:
                matchingWebsiteRule['target_type'] as String? ??
                'task_occurrence',
            targetId: matchingWebsiteRule['target_id'] as String,
            contributionType:
                matchingWebsiteRule['contribution_type'] as String? ??
                'active_work_seconds',
            isAutomatic: true,
          ),
        );
      }
      return;
    }

    // Trusted application rules use the stable platform/role/application
    // identity stored on the first confirmation. Comparing a raw executable
    // alone left later periods waiting for review.
    final identifier = _activityRuleIdentifier(segment);
    if (identifier == null) return;
    final allRules = await entities.list(entityType: 'application_rules');
    final blocked = allRules.any((candidate) {
      final data = _entityData(entities, candidate);
      return candidate.status == 'active' &&
          data['application_identifier'] == identifier.toLowerCase() &&
          ((data['classification'] == 'unrelated' &&
                  data['scope_type'] == 'task' &&
                  data['scope_id'] == sourceTaskId) ||
              data['classification'] == 'system_activity' ||
              data['classification'] == 'generally_unrelated');
    });
    if (blocked) return;
    final catalogs = await entities.list(entityType: 'application_catalog');
    final platform = segment.sourceType.startsWith('android')
        ? 'android'
        : 'windows';
    String? applicationId;
    for (final candidate in catalogs) {
      final data = _entityData(entities, candidate);
      if ((data['application_identifier'] as String?)?.toLowerCase() ==
              identifier.toLowerCase() &&
          (data['platform'] as String?)?.toLowerCase() == platform) {
        applicationId = candidate.id;
        break;
      }
    }
    if (applicationId == null) return;
    final rules = allRules;
    LocalEntityRecord? matchedRule;
    for (final candidate in rules) {
      final data = _entityData(entities, candidate);
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
    final ruleData = _entityData(entities, matchedRule);
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

  String? _activityRuleIdentifier(LocalActivitySegment segment) {
    final identifier = _activityIdentifier(segment)?.toLowerCase();
    if (identifier == null) return null;
    final platform = segment.sourceType.startsWith('android')
        ? 'android'
        : 'windows';
    final role =
        segment.sourceType == 'windows_foreground' ||
            segment.sourceType == 'android_usage'
        ? 'foreground_user_surface'
        : 'unknown_role';
    return '$platform|$role|$identifier';
  }

  String _privacySafeLabel(LocalActivitySegment segment) {
    final website =
        NormalizedWebsiteAddress.tryParse(segment.url) ??
        NormalizedWebsiteAddress.tryParse(segment.domain);
    if (website != null) return website.registrableDomain;
    final identifier = _activityIdentifier(segment) ?? 'activity';
    return normalizedApplicationDisplayName(identifier);
  }

  Map<String, Object?> _entityData(
    EntityRecordRepository entities,
    LocalEntityRecord record,
  ) {
    final value = entities.decode(record);
    final nested = value['data'];
    return nested is Map
        ? <String, Object?>{...value, ...Map<String, Object?>.from(nested)}
        : value;
  }

  String _readableClassification(String value) => value.replaceAll('_', ' ');

  String _dateOnly(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// Detailed history uses the same finalization boundary as its segment.
  /// Replacing a pending review command avoids a second remote review when a
  /// foreground interval is extended locally before it is delivered.
  Future<void> _enqueueDetailedReviewSync({
    required LocalActivityReview review,
    required String deviceId,
    required DateTime now,
  }) async {
    final existing =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.entityType.equals('activity_review_queue') &
                    row.entityId.equals(review.id) &
                    row.status.isIn(const ['pending', 'accepted']),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.deviceSequence)])
              ..limit(1))
            .getSingleOrNull();
    if (existing?.status == 'accepted') return;
    final payload = <String, Object?>{
      'activity_segment_id': review.activitySegmentId,
      'review_reason': review.reviewReason,
      'priority': review.priority,
      'suggested_targets': <Object?>[],
      'suggested_classification': review.suggestedClassification,
      'confidence': review.confidence,
      'status': review.status,
      'data': const <String, Object?>{'capture_state': 'finalized'},
    };
    if (existing != null) {
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(existing.commandId))).write(
        LocalOutboxCommandsCompanion(
          payloadJson: Value(jsonEncode(payload)),
          clientTimestamp: Value(now),
          lastError: const Value(null),
        ),
      );
      return;
    }
    await _enqueue(
      commandId: _uuid.v4(),
      deviceId: deviceId,
      sequence: await DeviceIdentity.nextSequence(_userId),
      entityType: 'activity_review_queue',
      entityId: review.id,
      payload: payload,
      now: now,
    );
  }

  /// Keeps a single durable command for an active normalized segment.
  ///
  /// Capture polling can extend one foreground segment several times before
  /// the next network drain.  Replacing the pending payload means the server
  /// receives the newest normalized interval once, rather than a stream of
  /// stale updates that each carry the same base revision.
  Future<void> _coalesceSegmentCommand({
    required LocalActivitySegment? existing,
    required String entityId,
    required String deviceId,
    required Map<String, Object?> payload,
    required DateTime now,
  }) async {
    final pending =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.entityType.equals('activity_segments') &
                    row.entityId.equals(entityId) &
                    row.status.equals('pending'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.deviceSequence)])
              ..limit(1))
            .getSingleOrNull();
    if (pending != null) {
      // Keep an unaccepted create as a create.  Otherwise rebase the one
      // pending update on the last canonical revision known locally.
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(pending.commandId))).write(
        LocalOutboxCommandsCompanion(
          baseRevision: pending.commandType == 'create'
              ? const Value(0)
              : Value(existing?.revision ?? pending.baseRevision),
          payloadJson: Value(jsonEncode(payload)),
          clientTimestamp: Value(now),
          lastError: const Value(null),
        ),
      );
      return;
    }

    final acceptedCreate =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.entityType.equals('activity_segments') &
                    row.entityId.equals(entityId) &
                    row.commandType.equals('create') &
                    row.status.equals('accepted'),
              )
              ..limit(1))
            .getSingleOrNull();

    await _enqueue(
      commandId: _uuid.v4(),
      deviceId: deviceId,
      sequence: await DeviceIdentity.nextSequence(_userId),
      entityType: 'activity_segments',
      entityId: entityId,
      // An interval may have been extended locally for minutes before it is
      // finalized. A local row is not proof that the server has seen a create.
      commandType: acceptedCreate == null ? 'create' : 'update',
      baseRevision: acceptedCreate == null ? 0 : (existing?.revision ?? 0),
      payload: payload,
      now: now,
    );
  }

  /// Queues the privacy-safe normalized segment only when it has become a
  /// shared task contribution (or the user explicitly enabled detailed
  /// Activity history).  The raw sampling stream is never used here.
  Future<void> _enqueueApprovedSegmentSync({
    required LocalActivitySegment segment,
    required String currentDeviceId,
    required bool includeSensitiveDetails,
    required bool approvedContribution,
    required String commandId,
    required int sequence,
    required DateTime now,
  }) async {
    // A segment received from another device already exists remotely; a local
    // classification should not create a second copy of it.
    if (segment.deviceId != currentDeviceId) return;
    final payload = _synchronizedSegmentPayload(
      segment,
      includeSensitiveDetails: includeSensitiveDetails,
      approvedContribution: approvedContribution,
    );
    final pending =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.entityType.equals('activity_segments') &
                    row.entityId.equals(segment.id) &
                    row.status.equals('pending'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.deviceSequence)])
              ..limit(1))
            .getSingleOrNull();
    if (pending != null) {
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(pending.commandId))).write(
        LocalOutboxCommandsCompanion(
          payloadJson: Value(jsonEncode(payload)),
          clientTimestamp: Value(now),
          lastError: const Value(null),
        ),
      );
      return;
    }

    final remoteCreate =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.entityType.equals('activity_segments') &
                    row.entityId.equals(segment.id) &
                    row.commandType.equals('create') &
                    row.status.equals('accepted'),
              )
              ..limit(1))
            .getSingleOrNull();
    await _enqueue(
      commandId: commandId,
      deviceId: currentDeviceId,
      sequence: sequence,
      entityType: 'activity_segments',
      entityId: segment.id,
      commandType: remoteCreate == null ? 'create' : 'update',
      baseRevision: remoteCreate == null ? 0 : segment.revision,
      payload: payload,
      now: now,
    );
  }

  Map<String, Object?> _synchronizedSegmentPayload(
    LocalActivitySegment segment, {
    required bool includeSensitiveDetails,
    required bool approvedContribution,
  }) {
    final metadataValue = jsonDecode(segment.rawMetadataJson);
    final localMetadata = metadataValue is Map
        ? Map<String, Object?>.from(metadataValue)
        : const <String, Object?>{};
    final safeMetadata = <String, Object?>{
      'normalized': true,
      'raw_samples_included': false,
      if (localMetadata['source_task_id'] != null)
        'source_task_id': localMetadata['source_task_id'],
      if (localMetadata['source_session_id'] != null)
        'source_session_id': localMetadata['source_session_id'],
      if (localMetadata['source_runtime_state'] != null)
        'source_runtime_state': localMetadata['source_runtime_state'],
    };
    return {
      'device_id': segment.deviceId,
      'device_event_id': segment.deviceEventId,
      'started_at': segment.startedAt.toUtc().toIso8601String(),
      'ended_at': segment.endedAt.toUtc().toIso8601String(),
      'source_type': segment.sourceType,
      'application_id': null,
      'website_rule_id': null,
      'resource_id': null,
      'process_name': includeSensitiveDetails ? segment.processName : null,
      'window_title': includeSensitiveDetails ? segment.windowTitle : null,
      'domain': includeSensitiveDetails ? segment.domain : null,
      'url': includeSensitiveDetails ? segment.url : null,
      'page_title': includeSensitiveDetails ? segment.pageTitle : null,
      'input_state': segment.idleState == 'technical_idle' ? 'idle' : 'active',
      'idle_state': segment.idleState,
      'screen_state': 'unlocked',
      'capture_confidence': segment.captureConfidence,
      'raw_metadata': safeMetadata,
      'data': <String, Object?>{
        'normalization_version': 1,
        'capture_state': 'finalized',
        if (approvedContribution) 'approved_contribution': true,
        'detail_level': includeSensitiveDetails
            ? 'sensitive_details_enabled'
            : 'privacy_safe',
      },
    };
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
