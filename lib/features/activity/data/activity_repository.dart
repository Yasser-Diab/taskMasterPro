import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/data/entity_record_repository.dart';
import '../../../core/learning/application_system_learning.dart';
import '../../../core/platform/device_identity.dart';
import '../../tasks/data/installed_application_service.dart';
import '../../tasks/data/website_rule_service.dart';
import '../domain/activity_reporting_policy.dart';
import 'activity_privacy_policy.dart';

export 'activity_privacy_policy.dart'
    show
        breakActivityClassifications,
        breakActivityReviewReason,
        manualBreakActivitySourceType;

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
  required int expectedReviewRevision,
  required String classification,
  required String? targetTaskId,
  required String? contributionType,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/activity-review/$reviewItemId/'
  'revision/$expectedReviewRevision/'
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

String manualBreakActivitySegmentIdFor({
  required String userId,
  required String sessionId,
  required DateTime startedAt,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/session/$sessionId/'
  'break/${startedAt.toUtc().microsecondsSinceEpoch}/manual-activity',
);

String manualBreakActivityReviewIdFor(String segmentId) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/activity-segment/$segmentId/break-review',
);

bool isManualBreakActivity(LocalActivitySegment segment) =>
    segment.sourceType == manualBreakActivitySourceType;

String? _sanitizeManualActivityLabel(String? value) {
  final normalized = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) return null;
  return normalized.length <= 120 ? normalized : normalized.substring(0, 120);
}

/// A break prompt is only useful when capture found no real device usage.
/// Technical idle rows, TaskMaster Pro itself and confirmed operating-system
/// activity are collection noise rather than evidence that the user spent the
/// break on a device.
bool hasMeaningfulDeviceActivityDuringBreak({
  required Iterable<LocalActivitySegment> segments,
  required Iterable<LocalAttribution> attributions,
  required DateTime startedAt,
  required DateTime endedAt,
}) {
  final latest = latestActivityAttributionBySegment(attributions);
  const systemClassifications = {'system_activity', 'possible_system_activity'};
  final startUtc = startedAt.toUtc();
  final endUtc = endedAt.toUtc();
  return segments.any((segment) {
    if (segment.deletedAt != null ||
        isManualBreakActivity(segment) ||
        isTaskMasterSelfActivity(segment) ||
        !segment.endedAt.toUtc().isAfter(startUtc) ||
        !segment.startedAt.toUtc().isBefore(endUtc)) {
      return false;
    }
    final idleState = segment.idleState?.trim().toLowerCase();
    if (isInactiveActivityState(idleState)) return false;
    final classification = latest[segment.id]?.classification
        .trim()
        .toLowerCase();
    return classification == null ||
        !systemClassifications.contains(classification);
  });
}

class ActivityReviewEntry {
  const ActivityReviewEntry({required this.review, required this.segment});

  final LocalActivityReview review;
  final LocalActivitySegment segment;

  Duration get duration => segment.endedAt.difference(segment.startedAt);
}

enum ActivityAttentionKind { crossTask, inactive, other }

const _inactiveActivityStates = <String>{
  'technical_idle',
  'idle',
  'confirmed_idle',
  'inactive',
  'unknown_idle',
  'uncertain',
};

/// Whether an Activity capture is genuinely inactive or uncertain.
///
/// Capture also persists the explicit state `active`. Treating every non-null
/// state as inactive made the dashboard count every unresolved application
/// period as idle and produced ever-growing values such as 1036.
bool isInactiveActivityState(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized != null && _inactiveActivityStates.contains(normalized);
}

Map<String, Object?> _activityMetadata(LocalActivitySegment segment) {
  try {
    final decoded = jsonDecode(segment.rawMetadataJson);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : const <String, Object?>{};
  } catch (_) {
    return const <String, Object?>{};
  }
}

bool isCrossTaskActivityReview(ActivityReviewEntry entry) {
  final reason = entry.review.reviewReason.trim().toLowerCase().replaceAll(
    '-',
    '_',
  );
  if (reason.contains('cross_task')) return true;
  if (entry.review.suggestedTargetType != 'task_occurrence') return false;
  final sourceTaskId =
      _activityMetadata(entry.segment)['source_task_id'] as String?;
  final suggestedTaskId = entry.review.suggestedTargetId;
  return sourceTaskId != null &&
      sourceTaskId.isNotEmpty &&
      suggestedTaskId != null &&
      suggestedTaskId.isNotEmpty &&
      sourceTaskId != suggestedTaskId;
}

ActivityAttentionKind activityAttentionKind(ActivityReviewEntry entry) {
  if (isCrossTaskActivityReview(entry)) {
    return ActivityAttentionKind.crossTask;
  }
  if (entry.review.reviewReason.trim().toLowerCase() == 'idle' ||
      isInactiveActivityState(entry.segment.idleState)) {
    return ActivityAttentionKind.inactive;
  }
  return ActivityAttentionKind.other;
}

/// Stable visual group identity for dashboard review counts.
///
/// The review queue deliberately preserves every physical period, while the
/// Activity screen presents those periods as one application/site/document
/// group. Dashboard counts must use the same user-facing unit.
String activityAttentionGroupKey(ActivityReviewEntry entry) {
  final segment = entry.segment;
  final domain = segment.domain?.trim().toLowerCase();
  if (domain != null && domain.isNotEmpty) return 'domain:$domain';
  final metadata = _activityMetadata(segment);
  for (final key in const [
    'package_name',
    'application_identifier',
    'document_path',
    'resource_name',
  ]) {
    final value = (metadata[key] as String?)?.trim().toLowerCase();
    if (value != null && value.isNotEmpty) return '$key:$value';
  }
  final process = segment.processName?.trim().toLowerCase();
  if (process != null && process.isNotEmpty) {
    final executable = process.split(RegExp(r'[\\/]')).last;
    return 'application:$executable';
  }
  return 'source:${segment.sourceType.trim().toLowerCase()}';
}

class ActivityAttentionSummary {
  const ActivityAttentionSummary({
    required this.crossTaskGroups,
    required this.inactiveGroups,
    required this.otherGroups,
  });

  final int crossTaskGroups;
  final int inactiveGroups;
  final int otherGroups;

  int get totalGroups => crossTaskGroups + inactiveGroups + otherGroups;
}

ActivityAttentionSummary summarizeActivityAttention(
  Iterable<ActivityReviewEntry> entries,
) {
  final groups = <ActivityAttentionKind, Set<String>>{
    for (final kind in ActivityAttentionKind.values) kind: <String>{},
  };
  for (final entry in entries) {
    if (entry.review.status != 'pending' ||
        entry.review.deletedAt != null ||
        entry.segment.deletedAt != null ||
        isTaskMasterSelfActivity(entry.segment)) {
      continue;
    }
    final kind = activityAttentionKind(entry);
    groups[kind]!.add(activityAttentionGroupKey(entry));
  }
  return ActivityAttentionSummary(
    crossTaskGroups: groups[ActivityAttentionKind.crossTask]!.length,
    inactiveGroups: groups[ActivityAttentionKind.inactive]!.length,
    otherGroups: groups[ActivityAttentionKind.other]!.length,
  );
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
    this.taskAllocations = const [],
    this.manualLabel,
  });

  final String status;
  final String classification;
  final String targetType;
  final String? targetId;
  final String? contributionType;
  final Duration? creditedDuration;
  final bool rememberRule;
  final bool isAutomatic;
  final List<ActivityTaskAllocation> taskAllocations;
  final String? manualLabel;
}

class ActivityTaskAllocation {
  const ActivityTaskAllocation({
    required this.targetTaskId,
    required this.percentage,
  });

  final String targetTaskId;
  final int percentage;
}

/// A percentage split across several tasks is a one-off attribution decision.
///
/// Remembering it as an application rule would silently collapse the rule to
/// the first task in the list, because an application rule has one target.
/// Keep the choice available for a single task, and enforce the same invariant
/// in [ActivityRepository.resolve] for callers which bypass the UI.
bool activityResolutionCanRememberForFuture(ActivityResolution resolution) =>
    resolution.taskAllocations.length < 2;

/// Selects the canonical live Activity rule deterministically.
///
/// Canonical revision is authoritative across devices. Timestamps are only a
/// tie-break for equal revisions because device clocks can be skewed. The
/// stable ID tie-break makes the result independent from database row order.
LocalEntityRecord? selectCanonicalActivityRule(
  Iterable<LocalEntityRecord> rules, {
  required bool Function(LocalEntityRecord rule) matches,
}) {
  final candidates = rules.where(matches).toList(growable: false)
    ..sort((left, right) {
      final revision = right.revision.compareTo(left.revision);
      if (revision != 0) return revision;
      final updated = right.updatedAt.compareTo(left.updatedAt);
      if (updated != 0) return updated;
      final created = right.createdAt.compareTo(left.createdAt);
      if (created != 0) return created;
      return left.id.compareTo(right.id);
    });
  return candidates.isEmpty ? null : candidates.first;
}

/// Validates one physical Activity interval's explicit task allocation.
///
/// Unallocated time is allowed, but duplicate task targets, non-positive
/// percentages, and totals above the physical interval are rejected.
List<ActivityTaskAllocation> validateActivityTaskAllocations(
  Iterable<ActivityTaskAllocation> allocations,
) {
  final result = allocations.toList(growable: false);
  if (result.isEmpty) {
    throw ArgumentError.value(
      result,
      'allocations',
      'Select at least one task',
    );
  }
  final seen = <String>{};
  var total = 0;
  for (final allocation in result) {
    if (allocation.targetTaskId.trim().isEmpty ||
        !seen.add(allocation.targetTaskId)) {
      throw ArgumentError.value(
        allocation.targetTaskId,
        'allocations',
        'Each selected task must be unique',
      );
    }
    if (allocation.percentage <= 0 || allocation.percentage > 100) {
      throw ArgumentError.value(
        allocation.percentage,
        'allocations',
        'Each allocation must be between 1 and 100 percent',
      );
    }
    total += allocation.percentage;
  }
  if (total > 100) {
    throw ArgumentError.value(
      total,
      'allocations',
      'Allocated time cannot exceed 100 percent',
    );
  }
  return result;
}

int activityAllocatedDurationMs({
  required int physicalDurationMs,
  required int percentage,
}) {
  if (physicalDurationMs < 0 || percentage < 0 || percentage > 100) {
    throw ArgumentError('Invalid Activity allocation');
  }
  // Integer division deliberately rounds down, so several allocations can
  // never exceed the source interval due to rounding.
  return (physicalDurationMs * percentage) ~/ 100;
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
  ActivityRepository(
    this.database,
    this.client, {
    Future<ApplicationSystemLearningService?>? communityLearning,
  }) : _communityLearning =
           communityLearning ??
           Future<ApplicationSystemLearningService?>.value(),
       _userId = client.auth.currentUser?.id ?? 'local';

  final AppDatabase database;
  final SupabaseClient client;
  final Future<ApplicationSystemLearningService?> _communityLearning;
  final String _userId;
  Future<void> _captureTail = Future<void>.value();
  static const _uuid = Uuid();

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
  }) {
    return _serializeCapture(
      () => _captureRawSegment(
        segmentId: segmentId,
        startedAt: startedAt,
        endedAt: endedAt,
        sourceType: sourceType,
        processName: processName,
        windowTitle: windowTitle,
        idleState: idleState,
        packageName: packageName,
        domain: domain,
        url: url,
        pageTitle: pageTitle,
        confidence: confidence,
        createReview: createReview,
        isFinalized: isFinalized,
      ),
    );
  }

  Future<T> _serializeCapture<T>(Future<T> Function() operation) {
    final result = _captureTail.then((_) => operation());
    // A failed capture is returned to its caller, but must not poison the
    // repository's serialization tail and prevent every later sample.
    _captureTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<String> _captureRawSegment({
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
    final requestedId = segmentId ?? _uuid.v4();
    final existing = segmentId == null
        ? null
        : await (database.select(database.localActivitySegments)..where(
                (row) => row.id.equals(segmentId) & row.userId.equals(_userId),
              ))
              .getSingleOrNull();
    if (existing != null &&
        (existing.startedAt.toUtc().millisecondsSinceEpoch ~/ 1000 !=
                startedAt.toUtc().millisecondsSinceEpoch ~/ 1000 ||
            existing.sourceType != sourceType ||
            existing.processName != processName)) {
      throw StateError(
        'Activity segment identity cannot be reused for different data',
      );
    }
    final id = existing?.id ?? requestedId;
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
              // Android history and final collector flushes can report the exact
              // same immutable segment more than once. Primary-key identity makes
              // that retry idempotent; serialization above ensures a conflicting
              // payload never races through this path and remains observable.
              mode: InsertMode.insertOrIgnore,
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

  /// Creates one durable, deterministic check-in for a break where capture
  /// found no meaningful device activity. A pending response remains in the
  /// Activity review queue when the user chooses "Not now"; a resolved break
  /// is never prompted again after a restart or another device refresh.
  Future<ActivityReviewEntry?> prepareBreakActivityReviewIfNeeded({
    required String taskId,
    required String sessionId,
    required DateTime startedAt,
    DateTime? endedAt,
  }) async {
    final startUtc = startedAt.toUtc();
    final endUtc = (endedAt ?? DateTime.now()).toUtc();
    if (!endUtc.isAfter(startUtc)) return null;
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(settingsId))).getSingleOrNull();
    if (settings?.detectBreakActivity == false) return null;

    final overlapping =
        await (database.select(database.localActivitySegments)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.deletedAt.isNull() &
                  row.startedAt.isSmallerThanValue(endUtc) &
                  row.endedAt.isBiggerThanValue(startUtc),
            ))
            .get();
    final overlappingIds = overlapping.map((segment) => segment.id).toSet();
    final attributions = overlappingIds.isEmpty
        ? const <LocalAttribution>[]
        : await (database.select(database.localAttributions)..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.deletedAt.isNull() &
                    row.activitySegmentId.isIn(overlappingIds),
              ))
              .get();
    if (hasMeaningfulDeviceActivityDuringBreak(
      segments: overlapping,
      attributions: attributions,
      startedAt: startUtc,
      endedAt: endUtc,
    )) {
      return null;
    }

    final segmentId = manualBreakActivitySegmentIdFor(
      userId: _userId,
      sessionId: sessionId,
      startedAt: startUtc,
    );
    final reviewId = manualBreakActivityReviewIdFor(segmentId);
    final existingSegment =
        await (database.select(database.localActivitySegments)..where(
              (row) => row.userId.equals(_userId) & row.id.equals(segmentId),
            ))
            .getSingleOrNull();
    final existingReview =
        await (database.select(database.localActivityReviews)..where(
              (row) => row.userId.equals(_userId) & row.id.equals(reviewId),
            ))
            .getSingleOrNull();
    if (existingSegment != null && existingReview != null) {
      if (existingReview.status != 'pending' ||
          existingReview.deletedAt != null ||
          existingSegment.deletedAt != null) {
        return null;
      }
      return ActivityReviewEntry(
        review: existingReview,
        segment: existingSegment,
      );
    }

    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final metadata = <String, Object?>{
      'manual_break_check_in': true,
      'prompt_version': 1,
      'source_task_id': taskId,
      'source_session_id': sessionId,
      'source_runtime_state': 'break',
    };
    late LocalActivitySegment segment;
    late LocalActivityReview review;
    await database.transaction(() async {
      segment =
          existingSegment ??
          LocalActivitySegment(
            id: segmentId,
            userId: _userId,
            deviceId: deviceId,
            deviceEventId:
                '$deviceId:manual-break:$sessionId:'
                '${startUtc.microsecondsSinceEpoch}',
            startedAt: startUtc,
            endedAt: endUtc,
            sourceType: manualBreakActivitySourceType,
            processName: null,
            windowTitle: null,
            domain: null,
            url: null,
            pageTitle: null,
            idleState: 'uncertain',
            captureConfidence: 1,
            rawMetadataJson: jsonEncode(metadata),
            revision: 1,
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
          );
      if (existingSegment == null) {
        await database.into(database.localActivitySegments).insert(segment);
      }
      review =
          existingReview ??
          LocalActivityReview(
            id: reviewId,
            userId: _userId,
            activitySegmentId: segmentId,
            reviewReason: breakActivityReviewReason,
            priority: 3,
            suggestedTargetType: 'unassigned_activity',
            suggestedTargetId: null,
            suggestedTargetTitle: null,
            suggestedClassification: 'requires_review',
            confidence: 1,
            status: 'pending',
            reviewedAt: null,
            revision: 1,
            createdAt: now,
            updatedAt: now,
            deletedAt: null,
          );
      if (existingReview == null) {
        await database.into(database.localActivityReviews).insert(review);
      }
    });
    return ActivityReviewEntry(review: review, segment: segment);
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
            database.localActivityReviews.userId.equals(_userId) &
                database.localActivitySegments.userId.equals(_userId) &
                database.localActivityReviews.deletedAt.isNull() &
                database.localActivityReviews.status.equals('pending') &
                database.localActivitySegments.deletedAt.isNull(),
          )
          ..orderBy([
            OrderingTerm.desc(database.localActivityReviews.priority),
            OrderingTerm.desc(database.localActivityReviews.createdAt),
          ]);
    return query.watch().map((rows) {
      final result = <ActivityReviewEntry>[];
      for (final row in rows) {
        final segment = row.readTable(database.localActivitySegments);
        if (isTaskMasterSelfActivity(segment)) continue;
        result.add(
          ActivityReviewEntry(
            review: row.readTable(database.localActivityReviews),
            segment: segment,
          ),
        );
      }
      return result;
    });
  }

  Future<ActivityReviewEntry?> reviewEntryForSegment(String segmentId) async {
    final segment =
        await (database.select(database.localActivitySegments)..where(
              (row) => row.id.equals(segmentId) & row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (segment == null || isTaskMasterSelfActivity(segment)) return null;
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
    final requestedAllocations = resolution.taskAllocations;
    if (requestedAllocations.isNotEmpty) {
      final allocations = validateActivityTaskAllocations(requestedAllocations);
      final primary = allocations.first;
      final physicalDurationMs = entry.duration.inMilliseconds;
      final rememberSingleTaskRule =
          resolution.rememberRule && allocations.length == 1;
      await _resolveSingle(
        entry,
        ActivityResolution(
          status: resolution.status,
          classification: resolution.classification,
          targetType: 'task_occurrence',
          targetId: primary.targetTaskId,
          contributionType:
              resolution.contributionType ?? 'active_work_seconds',
          creditedDuration: Duration(
            milliseconds: activityAllocatedDurationMs(
              physicalDurationMs: physicalDurationMs,
              percentage: primary.percentage,
            ),
          ),
          rememberRule: rememberSingleTaskRule,
          isAutomatic: resolution.isAutomatic,
          manualLabel: resolution.manualLabel,
        ),
      );
      for (final allocation in allocations.skip(1)) {
        await _addAllocatedTaskContribution(
          entry: entry,
          classification: resolution.classification,
          contributionType:
              resolution.contributionType ?? 'active_work_seconds',
          allocation: allocation,
        );
      }
      return;
    }
    await _resolveSingle(entry, resolution);
  }

  Future<void> _resolveSingle(
    ActivityReviewEntry entry,
    ActivityResolution resolution,
  ) async {
    final currentReview =
        await (database.select(database.localActivityReviews)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.id.equals(entry.review.id) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (currentReview == null) return;
    entry = ActivityReviewEntry(review: currentReview, segment: entry.segment);
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(settingsId))).getSingleOrNull();
    final privacyPolicy = await ActivityPrivacyPolicy.load(database, _userId);
    final manualBreak = isManualBreakActivity(entry.segment);
    final synchronizeContributions = privacyPolicy
        .allowsApprovedContributionUpload(settings);
    final synchronizeRules = settings?.activityRuleSyncEnabled ?? true;
    final synchronizeDetailedActivity = privacyPolicy
        .allowsDetailedActivityUpload(settings);
    final shouldCredit =
        activityClassificationAllowsCredit(resolution.classification) &&
        resolution.status == 'confirmed' &&
        resolution.targetId != null &&
        resolution.contributionType != null;
    // A reviewed device-usage period becomes shared only when it has a
    // concrete task contribution.  Otherwise its review remains local, while
    // an optional remembered rule is synchronized separately below.
    final synchronizeActivity =
        manualBreak ||
        synchronizeDetailedActivity ||
        (synchronizeContributions && shouldCredit);
    if (await _resolutionAlreadyApplied(
      entry: entry,
      resolution: resolution,
      shouldCredit: shouldCredit,
    )) {
      return;
    }
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
      expectedReviewRevision: entry.review.revision,
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
    final manualLabel = _sanitizeManualActivityLabel(resolution.manualLabel);
    if (manualBreak) {
      metadata['manual_break_check_in'] = true;
      metadata['manual_break_category'] = resolution.classification;
      if (manualLabel == null) {
        metadata.remove('manual_break_label');
      } else {
        metadata['manual_break_label'] = manualLabel;
      }
      entry = ActivityReviewEntry(
        review: entry.review,
        segment: entry.segment.copyWith(
          idleState: const Value('active'),
          rawMetadataJson: jsonEncode(metadata),
          updatedAt: now,
        ),
      );
    }
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
      if (manualBreak) {
        await (database.update(
          database.localActivitySegments,
        )..where((row) => row.id.equals(entry.segment.id))).write(
          LocalActivitySegmentsCompanion(
            idleState: const Value('active'),
            rawMetadataJson: Value(entry.segment.rawMetadataJson),
            updatedAt: Value(now),
          ),
        );
      }
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
      final previousContributions =
          await (database.select(database.localContributions)..where(
                (row) =>
                    row.activitySegmentId.equals(entry.segment.id) &
                    row.deletedAt.isNull(),
              ))
              .get();
      await (database.update(database.localAttributions)..where(
            (row) =>
                row.activitySegmentId.equals(entry.segment.id) &
                row.id.equals(attributionId).not() &
                row.deletedAt.isNull(),
          ))
          .write(
            LocalAttributionsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      for (final previous in previousContributions) {
        if (contributionId != null && previous.id == contributionId) continue;
        await (database.update(
          database.localContributions,
        )..where((row) => row.id.equals(previous.id))).write(
          LocalContributionsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await (database.update(
          database.localEntityRecords,
        )..where((row) => row.id.equals(previous.id))).write(
          LocalEntityRecordsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
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
      await (database.update(
        database.localAttributions,
      )..where((row) => row.id.equals(attributionId))).write(
        LocalAttributionsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
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
        await (database.update(
          database.localContributions,
        )..where((row) => row.id.equals(contributionId))).write(
          LocalContributionsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
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
      } else {
        await _rememberApplicationClassificationRule(
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
        synchronize: synchronizeContributions || manualBreak,
      );
    }
  }

  Future<bool> _resolutionAlreadyApplied({
    required ActivityReviewEntry entry,
    required ActivityResolution resolution,
    required bool shouldCredit,
  }) async {
    if (entry.review.status == 'pending' ||
        entry.review.status != resolution.status) {
      return false;
    }
    final attributions =
        await (database.select(database.localAttributions)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.activitySegmentId.equals(entry.segment.id) &
                  row.deletedAt.isNull(),
            ))
            .get();
    // A single-target intent is exact, not a subset match. In particular,
    // A+B must not be treated as already-applied when the new intent is A.
    if (attributions.length != 1) return false;
    final attribution = attributions.single;
    if (attribution.classification != resolution.classification ||
        attribution.targetType != resolution.targetType ||
        attribution.targetId != resolution.targetId) {
      return false;
    }

    final liveContributions =
        await (database.select(database.localContributions)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.activitySegmentId.equals(entry.segment.id) &
                  row.deletedAt.isNull(),
            ))
            .get();
    if (shouldCredit) {
      if (liveContributions.length != 1) return false;
      final expectedDurationMs = (resolution.creditedDuration ?? entry.duration)
          .inMilliseconds
          .clamp(0, entry.duration.inMilliseconds);
      final matching = liveContributions.where(
        (item) =>
            item.attributionId == attribution.id &&
            item.targetType == resolution.targetType &&
            item.targetId == resolution.targetId &&
            item.contributionType == resolution.contributionType &&
            item.creditedDurationMs == expectedDurationMs,
      );
      if (matching.length != 1) return false;
    } else if (liveContributions.isNotEmpty) {
      return false;
    }

    if (!resolution.rememberRule) return true;
    return _hasRememberedApplicationRuleIntent(
      entry: entry,
      resolution: resolution,
    );
  }

  Future<bool> _hasRememberedApplicationRuleIntent({
    required ActivityReviewEntry entry,
    required ActivityResolution resolution,
  }) async {
    final identifier = _activityRuleIdentifier(entry.segment);
    if (identifier == null) return false;
    final platform = entry.segment.sourceType.startsWith('android')
        ? 'android'
        : 'windows';
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
    if (scopeId == null) return false;

    final entities = EntityRecordRepository(database, client);
    final catalogs = await entities.list(entityType: 'application_catalog');
    bool matchesApplication(LocalEntityRecord candidate) {
      final data = _entityData(entities, candidate);
      return candidate.status == 'known' &&
          (data['application_identifier'] as String?)?.toLowerCase() ==
              identifier.toLowerCase() &&
          (data['platform'] as String?)?.toLowerCase() == platform;
    }

    final matchingCatalogs = catalogs.where(matchesApplication).toList();
    final catalog = selectCanonicalActivityRule(
      matchingCatalogs,
      matches: (_) => true,
    );
    if (catalog == null) return false;
    final applicationIds = matchingCatalogs
        .map((candidate) => candidate.id)
        .toSet();
    final rules = await entities.list(entityType: 'application_rules');
    final matchingRules = rules.where((candidate) {
      final data = _entityData(entities, candidate);
      return candidate.status == 'active' &&
          applicationIds.contains(data['application_id']) &&
          data['scope_type'] == scopeType &&
          data['scope_id'] == scopeId;
    }).toList();
    if (matchingRules.length != 1) return false;
    final rule = selectCanonicalActivityRule(
      matchingRules,
      matches: (_) => true,
    );
    if (rule == null) return false;
    final data = _entityData(entities, rule);
    final shouldCredit =
        resolution.status == 'confirmed' &&
        resolution.targetId != null &&
        resolution.contributionType != null &&
        activityClassificationAllowsCredit(resolution.classification);
    return data['classification'] == resolution.classification &&
        data['target_type'] == (shouldCredit ? resolution.targetType : null) &&
        data['target_id'] == (shouldCredit ? resolution.targetId : null) &&
        data['contribution_type'] ==
            (shouldCredit ? resolution.contributionType : null) &&
        data['automatic_credit'] == shouldCredit;
  }

  Future<void> _addAllocatedTaskContribution({
    required ActivityReviewEntry entry,
    required String classification,
    required String contributionType,
    required ActivityTaskAllocation allocation,
  }) async {
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(settingsId))).getSingleOrNull();
    final privacyPolicy = await ActivityPrivacyPolicy.load(database, _userId);
    final synchronize = privacyPolicy.allowsApprovedContributionUpload(
      settings,
    );
    final task =
        await (database.select(database.localTasks)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.id.equals(allocation.targetTaskId) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (task == null) {
      throw ArgumentError.value(
        allocation.targetTaskId,
        'allocation.targetTaskId',
        'Task is not available',
      );
    }

    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final metadataValue = jsonDecode(entry.segment.rawMetadataJson);
    final metadata = metadataValue is Map
        ? Map<String, Object?>.from(metadataValue)
        : const <String, Object?>{};
    final sourceTaskId = metadata['source_task_id'] as String?;
    final sourceSessionId = metadata['source_session_id'] as String?;
    final physicalDurationMs = entry.duration.inMilliseconds;
    final creditedDurationMs = activityAllocatedDurationMs(
      physicalDurationMs: physicalDurationMs,
      percentage: allocation.percentage,
    );
    final deterministicAttributionId = activityAttributionIdFor(
      userId: _userId,
      reviewItemId: entry.review.id,
      classification: classification,
      targetTaskId: allocation.targetTaskId,
    );
    final deterministicContributionId = activityContributionIdFor(
      userId: _userId,
      activitySegmentId: entry.segment.id,
      targetTaskId: allocation.targetTaskId,
      contributionType: contributionType,
    );
    final liveAttribution =
        await (database.select(database.localAttributions)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.activitySegmentId.equals(entry.segment.id) &
                    row.classification.equals(classification) &
                    row.targetType.equals('task_occurrence') &
                    row.targetId.equals(allocation.targetTaskId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    final deterministicAttribution = liveAttribution == null
        ? await (database.select(database.localAttributions)..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.id.equals(deterministicAttributionId),
              ))
              .getSingleOrNull()
        : null;
    final attributionId =
        liveAttribution?.id ??
        (deterministicAttribution == null
            ? deterministicAttributionId
            : _uuid.v4());

    final liveContribution =
        await (database.select(database.localContributions)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.activitySegmentId.equals(entry.segment.id) &
                    row.targetType.equals('task_occurrence') &
                    row.targetId.equals(allocation.targetTaskId) &
                    row.contributionType.equals(contributionType) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    final deterministicContribution = liveContribution == null
        ? await (database.select(database.localContributions)..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.id.equals(deterministicContributionId),
              ))
              .getSingleOrNull()
        : null;
    final contributionId =
        liveContribution?.id ??
        (deterministicContribution == null
            ? deterministicContributionId
            : _uuid.v4());
    final attributionCommandType = liveAttribution == null
        ? 'create'
        : 'update';
    final contributionCommandType = liveContribution == null
        ? 'create'
        : 'update';
    final attributionBaseRevision = liveAttribution?.revision ?? 0;
    final contributionBaseRevision = liveContribution?.revision ?? 0;
    final attributionCommandId = _uuid.v4();
    final contributionCommandId = _uuid.v4();

    await database.transaction(() async {
      await database
          .into(database.localAttributions)
          .insertOnConflictUpdate(
            LocalAttributionsCompanion.insert(
              id: attributionId,
              userId: _userId,
              activitySegmentId: entry.segment.id,
              targetType: 'task_occurrence',
              targetId: Value(allocation.targetTaskId),
              classification: classification,
              confidence: entry.review.confidence ?? 1,
              attributionStatus: const Value('confirmed'),
              confirmedByUser: const Value(true),
              createdAt: now,
              updatedAt: now,
              deletedAt: const Value(null),
            ),
          );
      await database
          .into(database.localContributions)
          .insertOnConflictUpdate(
            LocalContributionsCompanion.insert(
              id: contributionId,
              userId: _userId,
              activitySegmentId: entry.segment.id,
              attributionId: attributionId,
              targetType: 'task_occurrence',
              targetId: Value(allocation.targetTaskId),
              contributionType: contributionType,
              physicalDurationMs: physicalDurationMs,
              creditedDurationMs: creditedDurationMs,
              isUnscheduled: Value(sourceTaskId != allocation.targetTaskId),
              isCrossTask: Value(
                sourceTaskId != null && sourceTaskId != allocation.targetTaskId,
              ),
              isIdleDerived: Value(entry.segment.idleState == 'technical_idle'),
              createdAt: now,
              updatedAt: now,
              deletedAt: const Value(null),
            ),
          );
      if (synchronize) {
        await _enqueue(
          commandId: attributionCommandId,
          deviceId: deviceId,
          sequence: await DeviceIdentity.nextSequence(_userId),
          entityType: 'activity_attributions',
          entityId: attributionId,
          commandType: attributionCommandType,
          baseRevision: attributionBaseRevision,
          payload: {
            'activity_segment_id': entry.segment.id,
            'target_type': 'task_occurrence',
            'target_id': allocation.targetTaskId,
            'classification': classification,
            'confidence': entry.review.confidence ?? 1,
            'attribution_status': 'confirmed',
            'suggested_by': 'user_review',
            'confirmed_by_user': true,
            'data': {
              'review_item_id': entry.review.id,
              'allocation_percentage': allocation.percentage,
            },
          },
          now: now,
        );
        await _enqueue(
          commandId: contributionCommandId,
          deviceId: deviceId,
          sequence: await DeviceIdentity.nextSequence(_userId),
          entityType: 'activity_contributions',
          entityId: contributionId,
          commandType: contributionCommandType,
          baseRevision: contributionBaseRevision,
          payload: {
            'activity_segment_id': entry.segment.id,
            'activity_attribution_id': attributionId,
            'target_type': 'task_occurrence',
            'target_id': allocation.targetTaskId,
            'contribution_type': contributionType,
            'physical_duration_ms': physicalDurationMs,
            'credited_duration_ms': creditedDurationMs,
            'source_task_id': sourceTaskId,
            'source_session_id': sourceSessionId,
            'is_unscheduled': sourceTaskId != allocation.targetTaskId,
            'is_cross_task':
                sourceTaskId != null && sourceTaskId != allocation.targetTaskId,
            'is_idle_derived': entry.segment.idleState == 'technical_idle',
            'is_automatic': false,
            'data': {
              'allocation_percentage': allocation.percentage,
              'classification_source': 'user',
            },
          },
          now: now,
        );
      }
    });
    await _applyPermittedRoadmapEffects(
      taskId: allocation.targetTaskId,
      contributionId: contributionId,
      contributionType: contributionType,
      creditedDurationMs: creditedDurationMs,
      synchronize: synchronize,
    );
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
    final data = <String, Object?>{
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
    };
    final existing = await entities.getIncludingDeleted(id);
    if (existing == null) {
      await entities.create(
        EntityRecordDraft(
          id: id,
          entityType: 'classification_feedback',
          title: _readableClassification(resolution.classification),
          parentId: entry.segment.id,
          status: resolution.status,
          synchronize: synchronize,
          data: data,
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
      return;
    }
    // The feedback ID is deliberately deterministic. Re-reviewing a period
    // updates its projection instead of failing on a duplicate primary key
    // after the Activity decision has already committed.
    await (database.update(
      database.localEntityRecords,
    )..where((row) => row.id.equals(id) & row.userId.equals(_userId))).write(
      LocalEntityRecordsCompanion(
        title: Value(_readableClassification(resolution.classification)),
        parentId: Value(entry.segment.id),
        status: Value(resolution.status),
        dataJson: Value(jsonEncode(data)),
        revision: Value(existing.revision + 1),
        updatedAt: Value(DateTime.now().toUtc()),
        deletedAt: const Value(null),
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
    bool matchesApplication(LocalEntityRecord candidate) {
      final data = _entityData(entities, candidate);
      return (data['application_identifier'] as String?)?.toLowerCase() ==
              identifier.toLowerCase() &&
          (data['platform'] as String?)?.toLowerCase() == platform;
    }

    final matchingCatalogs = catalogs.where(matchesApplication).toList();
    final catalog = selectCanonicalActivityRule(
      matchingCatalogs,
      matches: (_) => true,
    );
    final stableApplicationId = applicationCatalogIdFor(
      userId: _userId,
      platform: platform,
      applicationIdentifier: identifier,
    );
    final deletedStableCatalog = catalog == null
        ? await entities.getIncludingDeleted(stableApplicationId)
        : null;
    final applicationId =
        catalog?.id ??
        (deletedStableCatalog == null ? stableApplicationId : _uuid.v4());
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
    final matchingApplicationIds = <String>{
      applicationId,
      ...matchingCatalogs.map((candidate) => candidate.id),
    };
    bool matchesScope(LocalEntityRecord candidate) {
      final data = _entityData(entities, candidate);
      return matchingApplicationIds.contains(data['application_id']) &&
          data['scope_type'] == scopeType &&
          data['scope_id'] == scopeId;
    }

    final existingRule = selectCanonicalActivityRule(
      rules,
      matches: matchesScope,
    );
    for (final duplicate in rules.where(matchesScope)) {
      if (duplicate.id == existingRule?.id) continue;
      await entities.softDelete(duplicate, synchronize: true);
    }
    final stableRuleId = activityRuleIdFor(
      userId: _userId,
      applicationId: applicationId,
      scopeType: scopeType,
      scopeId: scopeId,
    );
    final deletedStableRule = existingRule == null
        ? await entities.getIncludingDeleted(stableRuleId)
        : null;
    final ruleId =
        existingRule?.id ??
        (deletedStableRule == null ? stableRuleId : _uuid.v4());
    final deviceId = await DeviceIdentity.accountId(_userId);
    final displayName = _privacySafeLabel(entry.segment);
    final normalizedKey = normalizedApplicationKey(identifier);
    final catalogData = <String, Object?>{
      'platform': platform,
      'application_identifier': identifier.toLowerCase(),
      'normalized_application_key': normalizedKey,
      'display_name': displayName,
      'default_display_name': displayName,
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
    const catalogSemanticKeys = <String>{
      'platform',
      'application_identifier',
      'normalized_application_key',
      'display_name',
      'default_display_name',
      'classification',
    };
    const ruleSemanticKeys = <String>{
      'application_id',
      'platform',
      'application_identifier',
      'scope_type',
      'scope_id',
      'classification',
      'target_type',
      'target_id',
      'contribution_type',
      'automatic_credit',
      'priority',
      'rule_origin',
    };
    bool semanticMatch(
      LocalEntityRecord record,
      Map<String, Object?> desired,
      Set<String> keys,
    ) {
      final current = _entityData(entities, record);
      return keys.every((key) => current[key] == desired[key]);
    }

    final catalogMatches =
        catalog != null &&
        catalog.status == 'known' &&
        catalog.title == displayName &&
        semanticMatch(catalog, catalogData, catalogSemanticKeys);
    final ruleMatches =
        existingRule != null &&
        existingRule.status == 'active' &&
        existingRule.parentId == scopeId &&
        existingRule.secondaryParentId == applicationId &&
        existingRule.title == displayName &&
        semanticMatch(existingRule, ruleData, ruleSemanticKeys);
    await database.transaction(() async {
      if (!catalogMatches) {
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
                revision: Value(catalog == null ? 1 : catalog.revision + 1),
                createdAt: catalog?.createdAt ?? now,
                updatedAt: now,
                createdByDeviceId: Value(
                  catalog?.createdByDeviceId ?? deviceId,
                ),
                updatedByDeviceId: Value(deviceId),
                lastCommandId: Value(commandId),
                deletedAt: const Value(null),
              ),
            );
      }
      if (!ruleMatches) {
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
                revision: Value(
                  existingRule == null ? 1 : existingRule.revision + 1,
                ),
                createdAt: existingRule?.createdAt ?? now,
                updatedAt: now,
                createdByDeviceId: Value(
                  existingRule?.createdByDeviceId ?? deviceId,
                ),
                updatedByDeviceId: Value(deviceId),
                lastCommandId: Value(commandId),
                deletedAt: const Value(null),
              ),
            );
      }
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
    final identifier = _activityRuleIdentifier(entry.segment);
    if (identifier == null || resolution.targetId == null) return;
    final platform = entry.segment.sourceType.startsWith('android')
        ? 'android'
        : 'windows';
    final displayName = _privacySafeLabel(entry.segment);
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
            title: displayName,
            status: 'known',
            synchronize: synchronize,
            data: {
              'platform': platform,
              'application_identifier': identifier.toLowerCase(),
              'normalized_application_key': normalizedApplicationKey(
                identifier,
              ),
              'display_name': displayName,
              'default_display_name': displayName,
              'classification': resolution.classification,
            },
            syncPayload: {
              'platform': platform,
              'application_identifier': identifier.toLowerCase(),
              'normalized_application_key': normalizedApplicationKey(
                identifier,
              ),
              'display_name': displayName,
              'default_display_name': displayName,
              'publisher': null,
              'icon_path': null,
              'classification': resolution.classification,
              'first_seen_at': entry.segment.startedAt.toIso8601String(),
              'last_seen_at': entry.segment.endedAt.toIso8601String(),
            },
          ),
        );
    final ruleData = <String, Object?>{
      'application_id': applicationId,
      'platform': platform,
      'application_identifier': identifier.toLowerCase(),
      'scope_type': 'task',
      'scope_id': resolution.targetId,
      'classification': resolution.classification,
      'target_type': 'task_occurrence',
      'target_id': resolution.targetId,
      'contribution_type': resolution.contributionType,
      'automatic_credit': true,
      'priority': 200,
      'rule_origin': 'user_confirmed',
    };
    await _upsertRememberedApplicationRule(
      entities: entities,
      applicationId: applicationId,
      scopeType: 'task',
      scopeId: resolution.targetId!,
      title: displayName,
      ruleData: ruleData,
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
        'data': {
          'platform': platform,
          'application_identifier': identifier.toLowerCase(),
          'rule_origin': 'user_confirmed',
        },
      },
      synchronize: synchronize,
    );
  }

  Future<void> _rememberApplicationClassificationRule({
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
              'normalized_application_key': normalizedApplicationKey(
                identifier,
              ),
              'display_name': _privacySafeLabel(entry.segment),
              'default_display_name': _privacySafeLabel(entry.segment),
              'classification': resolution.classification,
            },
            syncPayload: {
              'platform': platform,
              'application_identifier': identifier.toLowerCase(),
              'normalized_application_key': normalizedApplicationKey(
                identifier,
              ),
              'display_name': _privacySafeLabel(entry.segment),
              'default_display_name': _privacySafeLabel(entry.segment),
              'publisher': null,
              'icon_path': null,
              'classification': resolution.classification,
              'first_seen_at': entry.segment.startedAt.toIso8601String(),
              'last_seen_at': entry.segment.endedAt.toIso8601String(),
            },
          ),
        );
    final ruleData = <String, Object?>{
      'application_id': applicationId,
      'platform': platform,
      'application_identifier': identifier.toLowerCase(),
      'scope_type': scopeType,
      'scope_id': scopeId,
      'classification': resolution.classification,
      'target_type': null,
      'target_id': null,
      'contribution_type': null,
      'automatic_credit': false,
      'priority': 300,
      'rule_origin': 'user_confirmed',
    };
    await _upsertRememberedApplicationRule(
      entities: entities,
      applicationId: applicationId,
      scopeType: scopeType,
      scopeId: scopeId!,
      title: _privacySafeLabel(entry.segment),
      ruleData: ruleData,
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
          'platform': platform,
          'application_identifier': identifier.toLowerCase(),
          'rule_origin': 'user_confirmed',
        },
      },
      synchronize: synchronize,
    );
  }

  Future<void> _upsertRememberedApplicationRule({
    required EntityRecordRepository entities,
    required String applicationId,
    required String scopeType,
    required String scopeId,
    required String title,
    required Map<String, Object?> ruleData,
    required Map<String, Object?> syncPayload,
    required bool synchronize,
  }) async {
    final rules = await entities.list(entityType: 'application_rules');
    bool matchesScope(LocalEntityRecord rule) {
      final data = _entityData(entities, rule);
      return data['application_id'] == applicationId &&
          data['scope_type'] == scopeType &&
          data['scope_id'] == scopeId;
    }

    final canonical = selectCanonicalActivityRule(rules, matches: matchesScope);
    for (final duplicate in rules.where(matchesScope)) {
      if (duplicate.id == canonical?.id) continue;
      await entities.softDelete(duplicate, synchronize: synchronize);
    }

    if (canonical == null) {
      final stableId = activityRuleIdFor(
        userId: _userId,
        applicationId: applicationId,
        scopeType: scopeType,
        scopeId: scopeId,
      );
      final existingStable = await entities.getIncludingDeleted(stableId);
      await entities.create(
        EntityRecordDraft(
          id: existingStable == null ? stableId : _uuid.v4(),
          entityType: 'application_rules',
          parentId: scopeId,
          secondaryParentId: applicationId,
          title: title,
          status: 'active',
          synchronize: synchronize,
          data: ruleData,
          syncPayload: syncPayload,
        ),
      );
      return;
    }

    final existingData = _entityData(entities, canonical);
    const semanticKeys = <String>{
      'application_id',
      'platform',
      'application_identifier',
      'scope_type',
      'scope_id',
      'classification',
      'target_type',
      'target_id',
      'contribution_type',
      'automatic_credit',
      'priority',
      'rule_origin',
    };
    final semanticMatch = semanticKeys.every(
      (key) => existingData[key] == ruleData[key],
    );
    if (canonical.status == 'active' &&
        canonical.parentId == scopeId &&
        canonical.secondaryParentId == applicationId &&
        canonical.title == title &&
        semanticMatch) {
      return;
    }

    final nextData = <String, Object?>{
      ...entities.decode(canonical),
      ...ruleData,
    };
    final nested = nextData['data'];
    if (nested is Map) {
      nextData['data'] = <String, Object?>{
        ...Map<String, Object?>.from(nested),
        ...ruleData,
      };
    }
    await entities.update(
      canonical,
      title: title,
      status: 'active',
      parentId: scopeId,
      secondaryParentId: applicationId,
      data: nextData,
      syncPayload: syncPayload,
      synchronize: synchronize,
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
    final matchedRule = selectCanonicalActivityRule(
      rules,
      matches: (candidate) {
        final data = _entityData(entities, candidate);
        return candidate.status == 'active' &&
            data['application_identifier'] == identifier &&
            data['scope_type'] == 'user' &&
            data['scope_id'] == _userId &&
            data['automatic_credit'] == false &&
            data['classification'] is String;
      },
    );
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
          status: switch (classification) {
            'system_activity' || 'unrelated' => 'ignored',
            'generally_unrelated' || 'distraction' => 'rejected',
            _ => 'confirmed',
          },
          classification: classification,
          isAutomatic: true,
        ),
      );
      return true;
    }
    final localSuggestion = _isPossibleSystemActivity(segment);
    final communitySuggestion = localSuggestion
        ? null
        : await _communitySystemSuggestion(segment);
    if (localSuggestion || communitySuggestion != null) {
      await _insertLocalAttribution(
        segment: segment,
        classification: 'possible_system_activity',
        status: 'proposed',
        confirmedByUser: false,
        confidence: communitySuggestion?.confidenceLowerBound ?? 0.95,
      );
    }
    return false;
  }

  Future<ApplicationSystemConsensus?> _communitySystemSuggestion(
    LocalActivitySegment segment,
  ) async {
    final source = applicationLearningSourceForCapture(
      sourceType: segment.sourceType,
      processName: segment.processName,
      rawMetadataJson: segment.rawMetadataJson,
    );
    if (source == null) return null;
    try {
      final service = await _communityLearning;
      if (service == null) return null;
      return service.possibleSystemSuggestion(
        platform: source.platform,
        applicationIdentifier: source.applicationIdentifier,
        // This method is reached only after canonical local-rule lookup found
        // no remembered decision, so community evidence cannot override one.
        hasLocalRememberedRule: false,
      );
    } catch (_) {
      return null;
    }
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
    final taskScopeRule = sourceTaskId == null
        ? null
        : selectCanonicalActivityRule(
            allRules,
            matches: (candidate) {
              final data = _entityData(entities, candidate);
              return candidate.status == 'active' &&
                  data['application_identifier'] == identifier.toLowerCase() &&
                  data['scope_type'] == 'task' &&
                  data['scope_id'] == sourceTaskId;
            },
          );
    final userScopeRule = selectCanonicalActivityRule(
      allRules,
      matches: (candidate) {
        final data = _entityData(entities, candidate);
        return candidate.status == 'active' &&
            data['application_identifier'] == identifier.toLowerCase() &&
            data['scope_type'] == 'user' &&
            data['scope_id'] == _userId &&
            data['automatic_credit'] == false;
      },
    );
    final taskClassification = taskScopeRule == null
        ? null
        : _entityData(entities, taskScopeRule)['classification'];
    final userClassification = userScopeRule == null
        ? null
        : _entityData(entities, userScopeRule)['classification'];
    if (taskClassification == 'unrelated' ||
        userClassification == 'system_activity' ||
        userClassification == 'generally_unrelated') {
      return;
    }
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
    final eligibleRules = allRules
        .where((candidate) {
          final data = _entityData(entities, candidate);
          return candidate.status == 'active' &&
              data['application_id'] == applicationId &&
              data['scope_type'] == 'task' &&
              data['automatic_credit'] == true &&
              data['target_id'] is String &&
              data['contribution_type'] is String &&
              (sourceTaskId == null || data['scope_id'] == sourceTaskId);
        })
        .toList(growable: false);
    if (sourceTaskId == null) {
      final targets = eligibleRules
          .map((rule) => _entityData(entities, rule)['target_id'])
          .whereType<String>()
          .toSet();
      // Without an active task, several task-specific application rules are
      // ambiguous. Leave the period for review instead of crediting whichever
      // row happened to be returned first.
      if (targets.length != 1) return;
    }
    final matchedRule = selectCanonicalActivityRule(
      eligibleRules,
      matches: (_) => true,
    );
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
      if (localMetadata['manual_break_check_in'] == true)
        'manual_break_check_in': true,
      if (localMetadata['manual_break_category'] != null)
        'manual_break_category': localMetadata['manual_break_category'],
      if (localMetadata['manual_break_label'] != null)
        'manual_break_label': localMetadata['manual_break_label'],
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
