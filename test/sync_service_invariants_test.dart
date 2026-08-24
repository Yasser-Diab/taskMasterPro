import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/sync/sync_service.dart';
import 'package:taskmaster_pro/features/activity/data/activity_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/installed_application_service.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_domain_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authoritative snapshot advances only when every entity applied', () {
    expect(authoritativeSnapshotCanAdvanceCursor(const []), isTrue);
    expect(authoritativeSnapshotCanAdvanceCursor(const {'roadmaps'}), isFalse);
  });

  test('atomic runtime commands defer every canonical row they project', () {
    const switchPayload = <String, dynamic>{
      'task_occurrence_id': 'task-new',
      'expected_active_task_id': 'task-old',
      'expected_active_session_id': 'session-old',
    };

    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'execution_sessions',
        canonicalEntityId: 'session-new',
        commandEntityType: 'execution_runtime_switch',
        commandEntityId: 'session-new',
        payload: switchPayload,
      ),
      isTrue,
    );
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'execution_sessions',
        canonicalEntityId: 'session-old',
        commandEntityType: 'execution_runtime_switch',
        commandEntityId: 'session-new',
        payload: switchPayload,
      ),
      isTrue,
    );
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'task_occurrences',
        canonicalEntityId: 'task-new',
        commandEntityType: 'execution_runtime_switch',
        commandEntityId: 'session-new',
        payload: switchPayload,
      ),
      isTrue,
    );
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'task_occurrences',
        canonicalEntityId: 'task-old',
        commandEntityType: 'execution_runtime_switch',
        commandEntityId: 'session-new',
        payload: switchPayload,
      ),
      isTrue,
    );
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'user_runtime_state',
        canonicalEntityId: 'runtime-owner',
        commandEntityType: 'execution_runtime_switch',
        commandEntityId: 'session-new',
        payload: switchPayload,
      ),
      isTrue,
    );
    const stalePausePayload = <String, dynamic>{
      'session_id': 'session-stale',
      'decision': 'require_again',
      'expected_runtime_revision': 14,
    };
    for (final canonicalRow in const [
      ('task_occurrences', 'task-stale'),
      ('execution_sessions', 'session-stale'),
      ('user_runtime_state', 'runtime-owner'),
    ]) {
      expect(
        pendingCommandProjectsCanonicalRow(
          canonicalEntityType: canonicalRow.$1,
          canonicalEntityId: canonicalRow.$2,
          commandEntityType: 'execution_runtime_stale_pause',
          commandEntityId: 'task-stale',
          payload: stalePausePayload,
        ),
        isTrue,
        reason:
            'The stale-pause command owns its task, session, and runtime projection.',
      );
    }
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'execution_sessions',
        canonicalEntityId: 'unrelated-session',
        commandEntityType: 'execution_runtime_stale_pause',
        commandEntityId: 'task-stale',
        payload: stalePausePayload,
      ),
      isFalse,
    );
    const breakExtensionPayload = <String, dynamic>{
      'task_occurrence_id': 'task-break',
      'session_id': 'session-break',
    };
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'task_occurrences',
        canonicalEntityId: 'task-break',
        commandEntityType: 'execution_break_extension',
        commandEntityId: 'session-break',
        payload: breakExtensionPayload,
      ),
      isTrue,
      reason: 'A break extension owns only its optimistic task projection.',
    );
    for (final unrelatedType in const [
      'execution_sessions',
      'user_runtime_state',
    ]) {
      expect(
        pendingCommandProjectsCanonicalRow(
          canonicalEntityType: unrelatedType,
          canonicalEntityId: 'session-break',
          commandEntityType: 'execution_break_extension',
          commandEntityId: 'session-break',
          payload: breakExtensionPayload,
        ),
        isFalse,
      );
    }
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'task_occurrences',
        canonicalEntityId: 'unrelated-task',
        commandEntityType: 'execution_runtime_stale_pause',
        commandEntityId: 'task-stale',
        payload: stalePausePayload,
      ),
      isFalse,
    );
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'execution_sessions',
        canonicalEntityId: 'unrelated-session',
        commandEntityType: 'execution_runtime_switch',
        commandEntityId: 'session-new',
        payload: switchPayload,
      ),
      isFalse,
    );
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'roadmaps',
        canonicalEntityId: 'roadmap-1',
        commandEntityType: 'roadmaps',
        commandEntityId: 'roadmap-1',
        payload: const {},
      ),
      isTrue,
    );
    expect(
      pendingCommandProjectsCanonicalRow(
        canonicalEntityType: 'health_summaries',
        canonicalEntityId: 'health-1',
        commandEntityType: 'task_health_summaries',
        commandEntityId: 'health-1',
        payload: const {},
      ),
      isTrue,
    );
  });

  test('incremental sync retains its cursor before a deferred row', () {
    expect(incrementalCursorAfterPage(pageLastSequence: 250), 250);
    expect(
      incrementalCursorAfterPage(
        pageLastSequence: 250,
        firstDeferredSequence: 117,
      ),
      116,
      reason:
          'the bounded change page must replay after its owner command settles',
    );
  });

  test('a durable cursor always uses incremental synchronization', () {
    expect(
      shouldRunAuthoritativeSnapshot(
        hasDurableCursor: true,
        snapshotRetryRequired: false,
      ),
      isFalse,
    );
    expect(
      shouldRunAuthoritativeSnapshot(
        hasDurableCursor: false,
        snapshotRetryRequired: false,
      ),
      isTrue,
    );
    expect(
      shouldRunAuthoritativeSnapshot(
        hasDurableCursor: true,
        snapshotRetryRequired: true,
      ),
      isTrue,
    );
    expect(hasUsableDurableSyncCursor(null), isFalse);
    expect(hasUsableDurableSyncCursor(0), isFalse);
    expect(hasUsableDurableSyncCursor(42), isTrue);
  });

  test('local pending work wakes synchronization without polling', () {
    final now = DateTime.utc(2026, 8, 16, 1);

    expect(
      shouldAutoDrainPendingOutbox(
        startedForUserId: 'owner-1',
        observedUserId: 'owner-1',
        nextAttemptAt: const [null],
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldAutoDrainPendingOutbox(
        startedForUserId: 'owner-1',
        observedUserId: 'owner-1',
        nextAttemptAt: [now.subtract(const Duration(seconds: 1))],
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldAutoDrainPendingOutbox(
        startedForUserId: 'owner-1',
        observedUserId: 'owner-1',
        nextAttemptAt: [now.add(const Duration(minutes: 5))],
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldAutoDrainPendingOutbox(
        startedForUserId: 'owner-2',
        observedUserId: 'owner-1',
        nextAttemptAt: const [null],
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldAutoDrainPendingOutbox(
        startedForUserId: 'owner-1',
        observedUserId: 'owner-1',
        nextAttemptAt: const [],
        now: now,
      ),
      isFalse,
    );
  });

  test(
    'first-device snapshot includes task URL resources and website links',
    () {
      expect(authoritativeSnapshotEntityTypes, contains('task_resources'));
      expect(authoritativeSnapshotEntityTypes, contains('website_rules'));
      expect(authoritativeSnapshotEntityTypes, contains('recurrence_rules'));
      expect(authoritativeSnapshotEntityTypes, contains('vacation_periods'));
      expect(authoritativeSnapshotEntityTypes, contains('task_templates'));
      expect(authoritativeSnapshotEntityTypes, contains('task_reminders'));
      expect(
        authoritativeSnapshotEntityTypes.indexOf('recurrence_rules'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('vacation_periods')),
      );
      expect(
        authoritativeSnapshotEntityTypes.indexOf('vacation_periods'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('task_templates')),
      );
      expect(
        authoritativeSnapshotEntityTypes.indexOf('task_templates'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('task_occurrences')),
      );
      expect(
        authoritativeSnapshotEntityTypes.indexOf('task_occurrences'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('task_resources')),
      );
      expect(
        authoritativeSnapshotEntityTypes.indexOf('task_occurrences'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('website_rules')),
      );
      expect(
        authoritativeSnapshotEntityTypes.indexOf('task_occurrences'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('task_reminders')),
      );
      expect(authoritativeSnapshotEntityTypes, contains('execution_sessions'));
      expect(authoritativeSnapshotEntityTypes, contains('session_events'));
      expect(
        authoritativeSnapshotEntityTypes.indexOf('execution_sessions'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('session_events')),
      );
      expect(authoritativeSnapshotStateId('user-1'), 'sync:v7:user-1');
    },
  );

  test('vacation changes use their revision-checked atomic endpoint', () {
    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    expect(source, contains("'vacation_periods' ||"));
    expect(source, contains("command.entityType == 'vacation_periods'"));
    expect(source, contains("'apply_vacation_period_command'"));
    expect(source, contains("'p_base_revision': command.baseRevision"));
  });

  test('privacy-safe Activity classifications get one bounded v2 retry', () {
    expect(
      nextActivityClassifierTransportRepairVersion(
        reason: 'permission_denied',
        message: 'activity_privacy_local_only',
        currentVersion: 1,
      ),
      2,
    );
    expect(
      nextActivityClassifierTransportRepairVersion(
        reason: 'permission_denied',
        message: 'device_not_registered',
        currentVersion: 1,
      ),
      isNull,
      reason: 'a revoked device must remain visible rather than be retried',
    );
    expect(
      nextActivityClassifierTransportRepairVersion(
        reason: 'permission_denied',
        message: 'activity_privacy_local_only',
        currentVersion: 2,
      ),
      isNull,
      reason: 'the privacy repair must never become an infinite retry loop',
    );
  });

  test('task application permission conflicts get one bounded retry', () {
    expect(
      shouldRetryTaskApplicationLinkPermissionConflict(
        reason: 'permission_denied',
        currentVersion: 0,
      ),
      isTrue,
    );
    expect(
      shouldRetryTaskApplicationLinkPermissionConflict(
        reason: 'permission_denied',
        currentVersion: 1,
      ),
      isFalse,
      reason: 'a failed repair must remain visible instead of looping',
    );
    expect(
      shouldRetryTaskApplicationLinkPermissionConflict(
        reason: 'device_not_registered',
        currentVersion: 0,
      ),
      isFalse,
      reason: 'revoked devices must never be silently retried',
    );
  });

  test(
    'a missing Activity review retries once only with a complete approved aggregate',
    () {
      expect(
        shouldRetryMissingApprovedActivityClassification(
          reason: 'missing_entity',
          currentVersion: 0,
          hasCompleteApprovedLocalAggregate: true,
        ),
        isTrue,
      );
      expect(
        shouldRetryMissingApprovedActivityClassification(
          reason: 'missing_entity',
          currentVersion: 0,
          hasCompleteApprovedLocalAggregate: false,
        ),
        isFalse,
        reason: 'an incomplete local Activity record must remain visible',
      );
      expect(
        shouldRetryMissingApprovedActivityClassification(
          reason: 'missing_entity',
          currentVersion: 1,
          hasCompleteApprovedLocalAggregate: true,
        ),
        isFalse,
        reason: 'a second server rejection must not become a retry storm',
      );
      expect(
        shouldRetryMissingApprovedActivityClassification(
          reason: 'revision_mismatch',
          currentVersion: 0,
          hasCompleteApprovedLocalAggregate: true,
        ),
        isFalse,
      );

      final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
      expect(source, contains("review.status != 'confirmed'"));
      expect(source, contains('row.confirmedByUser'));
      expect(source, contains('row.attributionId.equals(attribution.id)'));
      expect(source, contains("'approved_contribution': true"));
      expect(source, contains('manualBreakMetadataBySegmentId'));
      expect(source, contains("targetType == 'unassigned_activity'"));
      expect(source, contains('isApprovedPrivacySafeManualBreak'));
      expect(source, contains("'missing_entity_repair_version': 1"));
      expect(
        source,
        contains("'missing_entity_rebuilt_from_approved_local_aggregate'"),
      );
    },
  );

  test('malformed legacy Activity creates migrate once, not forever', () {
    expect(
      shouldMigrateLegacyActivityConflict(
        status: 'conflict',
        entityType: 'activity_contributions',
        commandType: 'create',
        reason: 'invalid_command_payload',
      ),
      isTrue,
    );
    expect(
      shouldMigrateLegacyActivityConflict(
        status: 'conflict',
        entityType: 'activity_segments',
        commandType: 'create',
        reason: 'missing_entity',
      ),
      isTrue,
    );
    expect(
      shouldMigrateLegacyActivityConflict(
        status: 'pending',
        entityType: 'activity_segments',
        commandType: 'create',
        reason: 'invalid_command_payload',
      ),
      isFalse,
    );
    expect(
      shouldMigrateLegacyActivityConflict(
        status: 'conflict',
        entityType: 'tasks',
        commandType: 'create',
        reason: 'invalid_command_payload',
      ),
      isFalse,
    );
  });

  test('conflict categories hide transport vocabulary from normal UI', () {
    expect(
      syncConflictCategoryForReason('already_applied'),
      SyncConflictCategory.alreadyApplied,
    );
    expect(
      syncConflictCategoryForReason('unique_constraint'),
      SyncConflictCategory.duplicate,
    );
    expect(
      syncConflictCategoryForReason('revision_mismatch'),
      SyncConflictCategory.revisionConflict,
    );
    expect(
      syncConflictCategoryForReason(
        'invalid_command_payload',
        errorText: 'invalid input syntax for type uuid',
      ),
      SyncConflictCategory.permanentFailure,
    );
  });

  test('readable legacy Activity keys become stable owner-scoped UUIDs', () {
    const owner = '4bd3e32d-1dcd-48ed-9f64-9099675047f1';
    const legacy =
        'android-history-com.android.launcher-1785272869737-1785272870852';
    final first = canonicalActivitySegmentSyncId(
      userId: owner,
      localSegmentId: legacy,
    );
    final second = canonicalActivitySegmentSyncId(
      userId: owner,
      localSegmentId: legacy,
    );

    expect(first, second);
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(
      canonicalActivitySegmentSyncId(
        userId: '75f78e6c-0ba8-48a7-a06e-45a6fb256b9d',
        localSegmentId: legacy,
      ),
      isNot(first),
    );
    expect(
      canonicalActivitySegmentSyncId(
        userId: owner,
        localSegmentId: '1d310e80-61a0-48c2-96f9-cc1c21466913',
      ),
      '1d310e80-61a0-48c2-96f9-cc1c21466913',
    );
  });

  test('Activity decision identities ignore names and translated labels', () {
    final attribution = activityAttributionIdFor(
      userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
      reviewItemId: '018fcbf3-9f27-7b19-88bf-21962e132499',
      classification: 'research_or_learning',
      targetTaskId: '9f51108d-0725-4a74-8ead-3017beef5854',
    );
    final contribution = activityContributionIdFor(
      userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
      activitySegmentId: '1d310e80-61a0-48c2-96f9-cc1c21466913',
      targetTaskId: '9f51108d-0725-4a74-8ead-3017beef5854',
      contributionType: 'active_work_seconds',
    );
    final command = activityClassificationCommandIdFor(
      userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
      reviewItemId: '018fcbf3-9f27-7b19-88bf-21962e132499',
      expectedReviewRevision: 1,
      classification: 'research_or_learning',
      targetTaskId: '9f51108d-0725-4a74-8ead-3017beef5854',
      contributionType: 'active_work_seconds',
    );

    expect(
      activityAttributionIdFor(
        userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
        reviewItemId: '018fcbf3-9f27-7b19-88bf-21962e132499',
        classification: 'research_or_learning',
        targetTaskId: '9f51108d-0725-4a74-8ead-3017beef5854',
      ),
      attribution,
    );
    expect(attribution, isNot(contribution));
    expect(contribution, isNot(command));
    expect(
      activityClassificationCommandIdFor(
        userId: '4bd3e32d-1dcd-48ed-9f64-9099675047f1',
        reviewItemId: '018fcbf3-9f27-7b19-88bf-21962e132499',
        expectedReviewRevision: 2,
        classification: 'research_or_learning',
        targetTaskId: '9f51108d-0725-4a74-8ead-3017beef5854',
        contributionType: 'active_work_seconds',
      ),
      isNot(command),
      reason: 'a real reclassification must not collide with the prior command',
    );
    expect(
      activityContributionIdFor(
        userId: '75f78e6c-0ba8-48a7-a06e-45a6fb256b9d',
        activitySegmentId: '1d310e80-61a0-48c2-96f9-cc1c21466913',
        targetTaskId: '9f51108d-0725-4a74-8ead-3017beef5854',
        contributionType: 'active_work_seconds',
      ),
      isNot(contribution),
    );
  });

  test('canonical Activity aggregate responses retire stale commands', () {
    const canonical = <String, dynamic>{
      'status': 'conflict',
      'reason': 'revision_mismatch',
      'canonical_review': <String, dynamic>{'id': 'review-1'},
      'canonical_attributions': <Object?>[],
      'canonical_contributions': <Object?>[],
    };
    expect(
      isCanonicalActivityClassificationResponse(
        entityType: 'activity_review_classifications',
        result: canonical,
      ),
      isTrue,
    );
    expect(
      isCanonicalActivityClassificationResponse(
        entityType: 'activity_review_classifications',
        result: const <String, dynamic>{
          'status': 'conflict',
          'reason': 'revision_mismatch',
        },
      ),
      isFalse,
    );
    expect(
      isCanonicalActivityClassificationResponse(
        entityType: 'task_occurrences',
        result: canonical,
      ),
      isFalse,
    );
  });

  test('Activity classification is one owner-scoped server transaction', () {
    final migration = File(
      'supabase/migrations/'
      '20260730010000_v0027_atomic_activity_classification.sql',
    ).readAsStringSync();

    expect(migration, contains('classify_activity_review_v0027'));
    expect(migration, contains('owner_id uuid := (select auth.uid())'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains('activity_contributions_semantic_unique_idx'));
    expect(migration, contains('application_rules_scope_unique_v0027_idx'));
    expect(migration, contains("'activity_review_classifications'"));
    expect(migration, contains('public.processed_commands'));
    expect(migration, contains("'already_applied'"));
    expect(migration, contains("'canonical_review_already_resolved'"));
    expect(migration, contains('on conflict (id) do update'));
    expect(
      migration,
      contains('grant execute on function public.classify_activity_review('),
    );
  });

  test(
    'Activity reclassification is revision guarded and returns full canonical state',
    () {
      final migration = File(
        'supabase/migrations/'
        '20260815155607_v0029_activity_reclassification_convergence.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final processedReplayIndex = migration.indexOf('into processed_row');
      final deviceValidationIndex = migration.indexOf(
        "raise exception 'device_not_registered'",
      );
      final reclassificationBranch = migration.substring(
        migration.indexOf('  if is_reclassification then'),
        migration.indexOf(
          '  raw_result := taskmaster_internal.classify_activity_review_v0027(',
        ),
      );

      expect(migration, contains('classify_activity_review_v0029'));
      expect(migration, contains('security definer'));
      expect(
        migration,
        contains(
          'if p_expected_revision is null or p_expected_revision < 0 then',
        ),
      );
      expect(processedReplayIndex, greaterThan(0));
      expect(
        deviceValidationIndex,
        greaterThan(processedReplayIndex),
        reason: 'an already-processed command must replay after revocation',
      );
      expect(migration, contains('review_row.revision <> p_expected_revision'));
      expect(migration, contains("'revision_mismatch'"));
      expect(
        migration,
        contains("is_reclassification := review_row.status <> 'pending'"),
      );
      expect(migration, contains("'already_applied'"));
      expect(
        migration,
        contains('and id <> existing_attribution.id'),
        reason: 'A+B is not already applied when the requested set is only A',
      );
      expect(
        migration,
        contains('and id <> existing_contribution.id'),
        reason: 'extra live task credit must force canonical reclassification',
      );
      expect(migration, contains("'canonical_review'"));
      expect(migration, contains("'canonical_attributions'"));
      expect(migration, contains("'canonical_contributions'"));
      expect(migration, contains("':activity-rule:'"));
      expect(migration, contains('private.normalize_application_key('));
      expect(migration, isNot(contains('pg_catalog.regexp_replace(')));
      expect(
        migration,
        contains(
          'processed_row.base_revision is distinct from p_expected_revision',
        ),
      );
      expect(
        migration,
        contains(
          "processed_row.entity_type is distinct from\n"
          "         'activity_review_classifications'",
        ),
      );
      expect(reclassificationBranch, isNot(contains("set status = 'pending'")));
      expect(
        reclassificationBranch,
        contains(
          'and id = p_review_item_id\n'
          '      and revision = p_expected_revision',
        ),
      );
      expect(reclassificationBranch, contains('canonical revision N + 1'));
      expect(
        RegExp(
          'update public\\.activity_review_queue',
        ).allMatches(reclassificationBranch).length,
        2,
        reason: 'one current review update plus one sibling-review cleanup',
      );
      expect(reclassificationBranch, contains('and id <> p_review_item_id'));
      expect(
        migration,
        contains('select taskmaster_internal.classify_activity_review_v0029('),
      );
    },
  );

  test(
    'historical Activity classifier repairs no-op on the clean definition',
    () {
      final canonicalClassifier = File(
        'supabase/migrations/'
        '20260730010000_v0027_atomic_activity_classification.sql',
      ).readAsStringSync();

      expect(canonicalClassifier, contains('<<activity_classifier>>'));
      expect(
        canonicalClassifier,
        contains('from public.application_catalog as catalog'),
      );
      expect(
        canonicalClassifier,
        contains('activity_classifier.application_identifier'),
      );

      const repairFiles = <String>[
        '20260730113000_v0027_activity_classifier_identifier_fix.sql',
        '20260730114000_v0027_activity_classifier_variable_fix.sql',
        '20260730115000_v0027_activity_classifier_block_label.sql',
      ];
      for (final repairFile in repairFiles) {
        final repair = File(
          'supabase/migrations/$repairFile',
        ).readAsStringSync();
        expect(repair, contains('canonical_definition boolean'));
        expect(repair, contains("position('<<activity_classifier>>'"));
        expect(
          repair,
          contains("position('from public.application_catalog as catalog'"),
        );
        expect(
          repair,
          contains("position('activity_classifier.application_identifier'"),
        );
        expect(repair, contains('if not canonical_definition then'));
      }
    },
  );

  test('task application links are atomic, normalized, and owner scoped', () {
    final migration = File(
      'supabase/migrations/'
      '20260730210000_v0027_normalized_task_application_links.sql',
    ).readAsStringSync();

    expect(migration, contains('public.task_application_links'));
    expect(migration, contains('public.user_application_overrides'));
    expect(migration, contains('connect_application_to_task'));
    expect(migration, contains('remove_application_from_task'));
    expect(migration, contains('public.processed_commands'));
    expect(migration, contains('display_name_snapshot'));
    expect(migration, contains('raw_identifier_snapshot'));
    expect(migration, contains('task_application_links_identity_v0027_idx'));
    expect(migration, contains('(select auth.uid()) = user_id'));
    expect(
      localParentIdForRemoteRow('task_application_links', const {
        'task_occurrence_id': 'task-1',
        'application_id': 'app-1',
      }),
      'task-1',
    );
  });

  test('task linking and Activity share one canonical application UUID', () {
    const userId = '4bd3e32d-1dcd-48ed-9f64-9099675047f1';
    expect(
      applicationCatalogIdForTaskConnection(
        userId: userId,
        platform: 'Android',
        applicationIdentifier: 'COM.DUOLINGO',
      ),
      applicationCatalogIdFor(
        userId: userId,
        platform: 'android',
        applicationIdentifier: 'com.duolingo',
      ),
    );
  });

  test('canonical active duration wins and legacy fallback is bounded', () {
    expect(
      canonicalTaskActiveDurationMs(const {
        'active_duration_ms': 42000,
        'actual_duration_ms': 1,
      }, existingValue: 7),
      42000,
    );
    expect(
      canonicalTaskActiveDurationMs(const {
        'actual_duration_ms': 18000,
      }, existingValue: 7),
      18000,
    );
    expect(canonicalTaskActiveDurationMs(const {}, existingValue: 7000), 7000);
  });

  test('task health summaries share the protected remote health table', () {
    expect(
      remoteEntityTypeForCommand('task_health_summaries'),
      'health_summaries',
    );
    expect(
      localEntityTypeForRemoteRow('health_summaries', const {
        'task_occurrence_id': 'task-1',
      }),
      'task_health_summaries',
    );
    expect(
      localEntityTypeForRemoteRow('health_summaries', const {
        'task_occurrence_id': null,
      }),
      'health_summaries',
    );
  });

  test('Health wire payload excludes device-only source timestamps', () {
    final payload = canonicalHealthSummaryPayload(const <String, dynamic>{
      'summary_date': '2026-08-24',
      'source': 'Health Connect',
      'summary_type': 'steps',
      'value': 723,
      'unit': 'count',
      'record_count': 3,
      'source_applications': <String>['com.example.health'],
      'source_record_counts': <String, int>{'com.example.health': 3},
      'source_latest_record_at': <String, String>{
        'com.example.health': '2026-08-24T12:00:00Z',
      },
      'latest_record_at': '2026-08-24T12:00:00Z',
      'imported_at': '2026-08-24T12:01:00Z',
    }, taskScoped: false);

    expect(payload['summary_type'], 'steps');
    expect(payload['value'], 723);
    expect(payload, isNot(contains('source_latest_record_at')));
    expect(payload, isNot(contains('latest_record_at')));
    expect(payload, isNot(contains('imported_at')));
  });

  test('Health convergence follows source-record freshness', () {
    expect(
      localHealthSummaryIsNewer(
        localPayload: const {'last_updated_at': '2026-08-24T12:01:00Z'},
        serverRow: const {
          'last_updated_at': '2026-08-24T12:00:00Z',
          'updated_at': '2026-08-24T12:02:00Z',
        },
      ),
      isTrue,
      reason: 'Database arrival time must not override newer sensor evidence.',
    );
    expect(
      localHealthSummaryIsNewer(
        localPayload: const {'last_updated_at': '2026-08-24T12:00:00Z'},
        serverRow: const {'last_updated_at': '2026-08-24T12:00:00Z'},
      ),
      isFalse,
      reason: 'Equal evidence must settle on the existing canonical row.',
    );
  });

  test('task resources stay parented to their concrete task after pull', () {
    expect(
      localParentIdForRemoteRow('task_resources', const {
        'roadmap_id': 'roadmap-1',
        'task_template_id': 'template-1',
        'task_occurrence_id': 'task-1',
      }),
      'task-1',
    );
    expect(
      localParentIdForRemoteRow('roadmap_phases', const {
        'roadmap_id': 'roadmap-1',
      }),
      'roadmap-1',
    );
  });

  test('task health rows are owner-bound and semantically deduplicated', () {
    final migration = File(
      'supabase/migrations/20260728170000_task_health_context.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        'foreign key (user_id, task_occurrence_id, execution_session_id)',
      ),
    );
    expect(
      migration,
      contains(
        'references public.execution_sessions '
        '(user_id, task_occurrence_id, id)',
      ),
    );
    expect(
      migration,
      contains('health_summaries_user_task_session_metric_live_idx'),
    );
    expect(migration, contains('resolve_health_summary_duplicate'));
    expect(migration, contains('pg_advisory_xact_lock'));
  });

  test('conflict diagnostics resolve only through an owner-scoped RPC', () {
    final migration = File(
      'supabase/migrations/20260728234500_sync_conflict_convergence.sql',
    ).readAsStringSync();

    expect(migration, contains('security definer'));
    expect(migration, contains("set search_path = ''"));
    expect(migration, contains('owner_id uuid := (select auth.uid())'));
    expect(migration, contains('and user_id = owner_id'));
    expect(migration, contains('pg_catalog.jsonb_build_object'));
    expect(migration, contains('unsupported_resolution_strategy'));
    expect(
      migration,
      contains(
        'grant execute on function '
        'public.resolve_sync_conflict_v0026(uuid, text)',
      ),
    );
    expect(migration, isNot(contains('grant update on public.sync_conflicts')));
  });

  test(
    'v0028 hides elevated conflict resolution behind an invoker wrapper',
    () {
      final migration = File(
        'supabase/migrations/'
        '20260810133337_v0028_conflict_rpc_surface_hardening.sql',
      ).readAsStringSync();

      expect(
        migration,
        contains('taskmaster_internal.resolve_sync_conflict_v0028'),
      );
      expect(migration, contains('security definer'));
      expect(migration, contains('security invoker'));
      expect(migration, contains("set search_path = ''"));
      expect(migration, contains('owner_id uuid := (select auth.uid())'));
      expect(
        migration,
        contains('p_strategy is null or p_strategy not in'),
        reason:
            'A null strategy must never auto-resolve a user-visible conflict.',
      );
      expect(
        migration,
        contains('and user_id = owner_id'),
        reason:
            'The definer implementation still derives scope from auth.uid().',
      );
      expect(
        migration,
        contains('revoke all on function public.resolve_sync_conflict_v0026'),
      );
    },
  );

  test('local-only Activity policy blocks metadata leaks but permits cleanup', () {
    final migration = File(
      'supabase/migrations/'
      '20260810044246_activity_privacy_local_only_policy.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        "tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null",
      ),
      reason:
          'A legacy raw record must be able to converge to a soft delete rather than remain a permanent sync error.',
    );
    expect(migration, contains('"raw_samples_included": false'));
    expect(migration, contains('pg_catalog.jsonb_object_keys'));
    expect(migration, contains("'source_runtime_state'"));
    expect(
      migration,
      contains('new.raw_metadata := old.raw_metadata'),
      reason: 'The cleanup escape must be a pure tombstone, not a raw update.',
    );
    expect(
      migration,
      contains("coalesce(new.suggested_targets, '[]'::jsonb) = '[]'::jsonb"),
      reason: 'Review suggestions must not carry a raw URL or window title.',
    );

    final syncSource = File(
      'lib/core/sync/sync_service.dart',
    ).readAsStringSync();
    expect(
      syncSource,
      contains("'domain': null"),
      reason:
          'The legacy outbox sanitizer must strip host identity alongside URL and window details.',
    );
  });

  test(
    'approved Activity contributions allow only privacy-safe review metadata',
    () {
      final migration = File(
        'supabase/migrations/'
        '20260816091500_v0030_privacy_safe_activity_reviews.sql',
      ).readAsStringSync();

      expect(migration, contains('approved_contribution'));
      expect(migration, contains('safe_review_metadata'));
      expect(migration, contains('pg_catalog.jsonb_object_keys'));
      expect(migration, contains("'classification_command_id'"));
      expect(migration, contains("'resolved_with_review_item_id'"));
      expect(migration, contains("new.data ->> 'capture_state' = 'finalized'"));
      expect(migration, contains('segment.process_name is null'));
      expect(migration, contains('segment.window_title is null'));
      expect(migration, contains('segment.domain is null'));
      expect(migration, contains('segment.url is null'));
      expect(migration, contains('segment.page_title is null'));
      expect(migration, contains('"raw_samples_included": false'));
      expect(
        RegExp(
          r"jsonb_object_keys\([\s\S]*?segment\.raw_metadata[\s\S]*?metadata_key not in",
        ).hasMatch(migration),
        isTrue,
      );
      expect(
        migration,
        contains(
          "raise exception 'activity_privacy_local_only' using errcode = '42501'",
        ),
      );
    },
  );

  test('only canonical runtime mismatches can be auto-superseded', () {
    expect(
      shouldSupersedeOnlineCanonicalMismatch(
        'execution_runtime',
        'revision_mismatch',
      ),
      isTrue,
    );
    expect(
      shouldSupersedeOnlineCanonicalMismatch(
        'task_occurrences',
        'revision_mismatch',
      ),
      isFalse,
    );
    expect(
      shouldSupersedeOnlineCanonicalMismatch(
        'execution_runtime',
        'permission_denied',
      ),
      isFalse,
    );
  });

  test('a proven same-ID create is idempotent, not a visible conflict', () {
    expect(
      isIdempotentDuplicateCreateConflict(
        commandType: 'create',
        reason: 'revision_mismatch',
        serverRevision: 1,
      ),
      isTrue,
    );
    expect(
      isIdempotentDuplicateCreateConflict(
        commandType: 'update',
        reason: 'revision_mismatch',
        serverRevision: 2,
      ),
      isFalse,
    );
    expect(
      isIdempotentDuplicateCreateConflict(
        commandType: 'create',
        reason: 'permission_denied',
        serverRevision: 1,
      ),
      isFalse,
    );
    expect(
      isIdempotentDuplicateCreateConflict(
        commandType: 'create',
        reason: 'unique_constraint',
        serverRevision: null,
      ),
      isTrue,
    );
  });

  test('only a live same-owner canonical create is auto-retired', () {
    const owner = '5b4fd021-1342-4d0b-a8e0-04ff1b8d1abc';
    const domainId = '4a509309-2aa4-4577-a20d-923bdd2e61ef';
    final canonical = <String, dynamic>{
      'id': domainId,
      'user_id': owner,
      'deleted_at': null,
      'revision': 1,
      'name': 'Learning',
    };

    expect(
      isProvenCanonicalDuplicateCreate(
        commandType: 'create',
        reason: 'revision_mismatch',
        // PostgREST JSON can be decoded either as a number or a string.
        serverRevision: '1',
        commandEntityId: domainId,
        userId: owner,
        canonicalRow: canonical,
      ),
      isTrue,
    );
    expect(
      isProvenCanonicalDuplicateCreate(
        commandType: 'create',
        reason: 'revision_mismatch',
        serverRevision: 1,
        commandEntityId: domainId,
        userId: '$owner-other',
        canonicalRow: canonical,
      ),
      isFalse,
      reason: 'A row from another account is never an automatic match.',
    );
    expect(
      isProvenCanonicalDuplicateCreate(
        commandType: 'create',
        reason: 'revision_mismatch',
        serverRevision: 1,
        commandEntityId: domainId,
        userId: owner,
        canonicalRow: {...canonical, 'deleted_at': '2026-08-11T00:00:00Z'},
      ),
      isFalse,
      reason: 'A deleted record must not erase a new create intent.',
    );
    expect(
      isProvenCanonicalDuplicateCreate(
        commandType: 'update',
        reason: 'revision_mismatch',
        serverRevision: 1,
        commandEntityId: domainId,
        userId: owner,
        canonicalRow: canonical,
      ),
      isFalse,
    );
    expect(
      isProvenCanonicalDuplicateCreate(
        commandType: 'create',
        reason: 'revision_mismatch',
        serverRevision: 2,
        commandEntityId: domainId,
        userId: owner,
        canonicalRow: canonical,
      ),
      isFalse,
      reason: 'The canonical row must prove the reported server revision.',
    );
  });

  test('any durable Area delivery history prevents command recreation', () {
    for (final hasHistory in const [true, false]) {
      expect(
        shouldRestoreMissingParentCreate(
          hasCanonicalCommandIdentity: false,
          hasDurableDeliveryHistory: hasHistory,
          isKnownRemoteRow: false,
        ),
        !hasHistory,
      );
    }
    expect(
      shouldRestoreMissingParentCreate(
        hasCanonicalCommandIdentity: true,
        hasDurableDeliveryHistory: false,
        isKnownRemoteRow: false,
      ),
      isFalse,
    );
    expect(
      shouldRestoreMissingParentCreate(
        hasCanonicalCommandIdentity: false,
        hasDurableDeliveryHistory: false,
        isKnownRemoteRow: true,
      ),
      isFalse,
    );
  });

  test(
    'history-less deterministic Area reconstruction keeps built-in data',
    () {
      const owner = '5b4fd021-1342-4d0b-a8e0-04ff1b8d1abc';
      final learning = TaskDomainCatalog.idFor(owner, 'learning');
      expect(restoredTaskDomainData(userId: owner, domainId: learning), const {
        'built_in': true,
        'domain_key': 'learning',
      });
      expect(
        restoredTaskDomainData(
          userId: owner,
          domainId: '4a509309-2aa4-4577-a20d-923bdd2e61ef',
        ),
        isEmpty,
      );
    },
  );

  test(
    'same-ID Area conflicts retire only when create intent is identical',
    () {
      const owner = '5b4fd021-1342-4d0b-a8e0-04ff1b8d1abc';
      final learning = TaskDomainCatalog.idFor(owner, 'learning');
      final canonical = <String, dynamic>{
        'id': learning,
        'user_id': owner,
        'name': 'Learning',
        'icon_name': 'school',
        'color_value': 4280289423,
        'position': 1.0,
        'data': const {'built_in': true, 'domain_key': 'learning'},
      };
      expect(
        isSameTaskDomainCreateIntent(
          userId: owner,
          entityId: learning,
          localPayload: const {
            'name': 'Learning',
            'icon_name': 'school',
            'color_value': 4280289423,
            'position': 1,
            // This is the legacy payload that caused the real retry loop.
            'data': <String, Object?>{},
          },
          canonicalRow: canonical,
        ),
        isTrue,
      );
      expect(
        isSameTaskDomainCreateIntent(
          userId: owner,
          entityId: learning,
          localPayload: const {
            'name': 'Renamed learning',
            'icon_name': 'school',
            'color_value': 4280289423,
            'position': 1,
            'data': <String, Object?>{},
          },
          canonicalRow: canonical,
        ),
        isFalse,
        reason: 'A user-visible Area edit remains a genuine conflict.',
      );
    },
  );

  test('application-rule convergence requires identical behavior intent', () {
    const canonical = <String, dynamic>{
      'application_id': '11111111-1111-4111-8111-111111111111',
      'scope_type': 'task',
      'scope_id': '22222222-2222-4222-8222-222222222222',
      'classification': 'direct_task_work',
      'target_type': 'task_occurrence',
      'target_id': '22222222-2222-4222-8222-222222222222',
      'contribution_type': 'productive',
      'automatic_credit': true,
      'priority': 200,
    };
    expect(
      isSameApplicationRuleIntent(
        localPayload: canonical,
        canonicalRow: canonical,
      ),
      isTrue,
    );
    expect(
      isSameApplicationRuleIntent(
        localPayload: {...canonical, 'classification': 'distraction'},
        canonicalRow: canonical,
      ),
      isFalse,
      reason: 'A different classification is a genuine user edit.',
    );
    expect(
      isSameApplicationRuleIntent(
        localPayload: {...canonical, 'automatic_credit': false},
        canonicalRow: canonical,
      ),
      isFalse,
    );
  });

  test(
    'legacy Amazon task-application aliases converge only for identical intent',
    () {
      const canonical = <String, dynamic>{
        'id': '33333333-3333-4333-8333-333333333333',
        'user_id': '5b4fd021-1342-4d0b-a8e0-04ff1b8d1abc',
        'task_occurrence_id': '11111111-1111-4111-8111-111111111111',
        'application_id': '22222222-2222-4222-8222-222222222222',
        'relationship_type': 'supporting',
        'raw_identifier_snapshot': 'com.amazon.mShop.android.shopping',
        'normalized_application_key_snapshot':
            'com.amazon.mshop.android.shopping',
        'data': {
          'classification': 'direct_task_work',
          'automatic_credit': true,
        },
      };
      const legacyAmazonPayload = <String, dynamic>{
        'task_occurrence_id': '11111111-1111-4111-8111-111111111111',
        'application_id': '22222222-2222-4222-8222-222222222222',
        'platform': 'android',
        'raw_identifier_snapshot': 'com.amazon.mShop.android.shopping',
        'normalized_application_key_snapshot':
            'com.amazon.mshop.android.shopping',
        'relationship_type': 'supporting',
        'classification': 'direct_task_work',
        'automatic_credit': true,
      };

      expect(
        isSameTaskApplicationLinkIntent(
          localPayload: legacyAmazonPayload,
          canonicalRow: canonical,
        ),
        isTrue,
        reason:
            'The Huawei v29 alias is the same active relationship even though its link UUID differs.',
      );
      expect(
        isSameTaskApplicationLinkIntent(
          localPayload: {
            ...legacyAmazonPayload,
            'classification': 'distraction',
          },
          canonicalRow: canonical,
        ),
        isFalse,
        reason: 'A different classification must remain a user conflict.',
      );
      expect(
        isSameTaskApplicationLinkIntent(
          localPayload: {
            ...legacyAmazonPayload,
            'task_occurrence_id': '44444444-4444-4444-8444-444444444444',
          },
          canonicalRow: canonical,
        ),
        isFalse,
        reason: 'A different task must never be merged by application name.',
      );
    },
  );

  test('atomic Activity classifier has owner-scoped definer privileges', () {
    final migration = File(
      'supabase/migrations/'
      '20260730121000_v0027_activity_classifier_security.sql',
    ).readAsStringSync();

    expect(migration, contains('security definer'));
    expect(migration, contains("set search_path = ''"));
    expect(migration, contains('to authenticated, service_role'));
    expect(migration, contains('registered-device-scoped'));
  });

  test(
    'application catalog natural-key collisions are recoverable aliases',
    () {
      expect(
        classifySyncDeliveryFailure(
          entityType: 'application_catalog',
          commandType: 'create',
          errorCode: '23505',
          errorMessage:
              'duplicate key violates application_catalog_identifier_idx '
              '(platform, application_identifier)',
        ),
        SyncDeliveryFailureKind.applicationCatalogAlias,
      );
      expect(
        classifySyncDeliveryFailure(
          entityType: 'task_occurrences',
          commandType: 'create',
          errorCode: '23505',
          errorMessage: 'another unique constraint',
        ),
        SyncDeliveryFailureKind.permanent,
      );
      expect(
        isLegacyPendingApplicationCatalogAlias(
          entityType: 'application_catalog',
          commandType: 'create',
          lastError:
              'PostgrestException(code: 23505, '
              'application_catalog_identifier_idx, '
              'platform, application_identifier)',
        ),
        isTrue,
      );
    },
  );

  test('legacy catalog schema failures replay one normalized create', () {
    const legacyError =
        '{"reason":"invalid_command_payload","code":"23502",'
        '"message":"null value in column normalized_application_key"}';
    expect(
      isLegacyApplicationCatalogContractFailure(
        entityType: 'application_catalog',
        commandType: 'create',
        status: 'conflict',
        lastError: legacyError,
      ),
      isTrue,
    );
    expect(
      isLegacyApplicationCatalogContractFailure(
        entityType: 'application_catalog',
        commandType: 'create',
        status: 'pending',
        lastError: legacyError,
      ),
      isFalse,
    );
    expect(
      normalizedApplicationCatalogCreatePayload(const {
        'platform': 'Windows',
        'application_identifier': 'windows|foreground_user_surface|chrome.exe',
        'display_name': 'Google Chrome',
      }),
      containsPair(
        'normalized_application_key',
        'windows_foreground_user_surface_chrome_exe',
      ),
    );
    expect(
      normalizedApplicationCatalogCreatePayload(const {'platform': 'windows'}),
      isNull,
      reason: 'Malformed history must remain diagnostic instead of guessed.',
    );
  });

  test('legacy vacation metadata is repaired once without changing intent', () {
    const legacyPayload = <String, dynamic>{
      'title': 'Summer holiday',
      'start_date': '2026-08-10',
      'end_date': '2026-08-12',
      'schema_version': 1,
      'data': <String, dynamic>{'source': 'routine_settings'},
    };
    final repaired = normalizedVacationCommandPayload(legacyPayload);

    expect(repaired, isNot(contains('schema_version')));
    expect(repaired['data'], {
      'source': 'routine_settings',
      'schema_version': 1,
    });
    expect(
      isLegacyVacationContractFailure(
        entityType: 'vacation_periods',
        commandType: 'create',
        status: 'conflict',
        payload: legacyPayload,
        lastError:
            '{"reason":"invalid_command_contract",'
            '"message":"invalid_payload_columns: {schema_version}"}',
      ),
      isTrue,
    );
    expect(
      isLegacyVacationContractFailure(
        entityType: 'vacation_periods',
        commandType: 'create',
        status: 'conflict',
        payload: repaired,
        lastError: 'invalid_payload_columns: {schema_version}',
      ),
      isFalse,
    );
    final firstId = repairedVacationCommandId(
      userId: 'owner-1',
      originalCommandId: 'command-1',
    );
    expect(
      repairedVacationCommandId(
        userId: 'owner-1',
        originalCommandId: 'command-1',
      ),
      firstId,
    );
    expect(
      repairedVacationCommandId(
        userId: 'owner-1',
        originalCommandId: 'command-2',
      ),
      isNot(firstId),
    );
  });

  test('occurrence identity collision requires two distinct owner rows', () {
    const payload = <String, dynamic>{
      'template_id': 'template-1',
      'occurrence_key': '2026-08-22',
    };
    const canonical = <String, dynamic>{
      'id': 'task-23',
      'user_id': 'owner-1',
      'template_id': 'template-1',
      'occurrence_key': '2026-08-23',
      'last_command_id': 'accepted-command',
      'deleted_at': null,
    };
    const collision = <String, dynamic>{
      'id': 'task-22',
      'user_id': 'owner-1',
      'template_id': 'template-1',
      'occurrence_key': '2026-08-22',
      'deleted_at': null,
    };

    expect(
      isProvenRejectedTaskOccurrenceIdentityCollision(
        userId: 'owner-1',
        commandId: 'rejected-command',
        commandEntityId: 'task-23',
        commandPayload: payload,
        canonicalRow: canonical,
        collisionRow: collision,
      ),
      isTrue,
    );
    expect(
      isProvenRejectedTaskOccurrenceIdentityCollision(
        userId: 'owner-1',
        commandId: 'rejected-command',
        commandEntityId: 'task-23',
        commandPayload: payload,
        canonicalRow: canonical,
        collisionRow: {...collision, 'user_id': 'owner-2'},
      ),
      isFalse,
      reason: 'RLS ownership proof must be explicit before auto-repair.',
    );
    expect(
      isProvenRejectedTaskOccurrenceIdentityCollision(
        userId: 'owner-1',
        commandId: 'rejected-command',
        commandEntityId: 'task-23',
        commandPayload: payload,
        canonicalRow: canonical,
        collisionRow: {...collision, 'deleted_at': '2026-08-22T12:00:00Z'},
      ),
      isFalse,
    );
  });

  test('legacy vacation repair is durable and restart-idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'owner-vacation';
    const entityId = 'vacation-1';
    const commandId = 'vacation-command-1';
    final now = DateTime.utc(2026, 8, 22, 12);
    const payload = <String, dynamic>{
      'title': 'Summer holiday',
      'start_date': '2026-08-24',
      'end_date': '2026-08-28',
      'schema_version': 1,
      'data': <String, dynamic>{},
    };
    await database
        .into(database.localEntityRecords)
        .insert(
          LocalEntityRecordsCompanion.insert(
            id: entityId,
            userId: userId,
            entityType: 'vacation_periods',
            title: const Value('Summer holiday'),
            dataJson: const Value('{"schema_version":1}'),
            revision: const Value(1),
            createdAt: now,
            updatedAt: now,
            lastCommandId: const Value(commandId),
          ),
        );
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: commandId,
            userId: userId,
            deviceId: 'legacy-device',
            deviceSequence: 1,
            entityType: 'vacation_periods',
            entityId: entityId,
            commandType: 'create',
            baseRevision: 0,
            payloadJson: jsonEncode(payload),
            status: const Value('conflict'),
            lastError: const Value(
              '{"reason":"invalid_command_contract",'
              '"message":"invalid_payload_columns: {schema_version}"}',
            ),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
    final service = SyncService(
      database: database,
      client: SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
      ),
    );

    await service.repairLegacyVacationContractFailuresForTesting(userId);
    await service.repairLegacyVacationContractFailuresForTesting(userId);

    final commands = await database.select(database.localOutboxCommands).get();
    final replacementId = repairedVacationCommandId(
      userId: userId,
      originalCommandId: commandId,
    );
    expect(commands, hasLength(2));
    expect(
      commands.singleWhere((item) => item.commandId == commandId).status,
      'superseded',
    );
    final replacement = commands.singleWhere(
      (item) => item.commandId == replacementId,
    );
    expect(replacement.status, 'pending');
    final repairedPayload = jsonDecode(replacement.payloadJson) as Map;
    expect(repairedPayload, isNot(contains('schema_version')));
    expect(repairedPayload['data'], {'schema_version': 1});
    final record = await database
        .select(database.localEntityRecords)
        .getSingle();
    expect(record.lastCommandId, replacementId);
  });

  test(
    'invalid Health uploads collapse to one sanitized latest intent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const userId = 'owner-health';
      const entityId = 'health-steps-2026-08-24';
      final now = DateTime.utc(2026, 8, 24, 12);
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: entityId,
              userId: userId,
              entityType: 'health_summaries',
              title: const Value('steps'),
              dataJson: const Value('{"summary_type":"steps","value":700}'),
              revision: const Value(8),
              createdAt: now,
              updatedAt: now,
              lastCommandId: const Value('health-command-2'),
            ),
          );
      for (final command in const [
        (id: 'health-command-1', sequence: 1, baseRevision: 1, value: 500),
        (id: 'health-command-2', sequence: 2, baseRevision: 2, value: 700),
      ]) {
        await database
            .into(database.localOutboxCommands)
            .insert(
              LocalOutboxCommandsCompanion.insert(
                commandId: command.id,
                userId: userId,
                deviceId: 'health-device',
                deviceSequence: command.sequence,
                entityType: 'health_summaries',
                entityId: entityId,
                commandType: 'update',
                baseRevision: command.baseRevision,
                payloadJson: jsonEncode({
                  'summary_date': '2026-08-24',
                  'source': 'Health Connect',
                  'summary_type': 'steps',
                  'value': command.value,
                  'unit': 'count',
                  'record_count': 2,
                  'source_latest_record_at': {
                    'com.example.health': '2026-08-24T12:00:00Z',
                  },
                }),
                status: const Value('conflict'),
                lastError: const Value(
                  '{"reason":"invalid_command_contract",'
                  '"message":"invalid_payload_columns: '
                  '{source_latest_record_at}"}',
                ),
                clientTimestamp: now,
                createdAt: now,
              ),
            );
      }
      final service = SyncService(
        database: database,
        client: SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test_key',
        ),
      );

      await service.repairInvalidHealthSummaryWireConflictsForTesting(userId);
      await service.repairInvalidHealthSummaryWireConflictsForTesting(userId);

      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      final repaired = commands.singleWhere(
        (command) => command.commandId == 'health-command-1',
      );
      expect(repaired.status, 'pending');
      expect(repaired.baseRevision, 1);
      expect(repaired.attemptCount, 0);
      final repairedPayload = jsonDecode(repaired.payloadJson) as Map;
      expect(repairedPayload['value'], 700);
      expect(repairedPayload, isNot(contains('source_latest_record_at')));
      expect(
        commands
            .singleWhere((command) => command.commandId == 'health-command-2')
            .status,
        'superseded',
      );
      final record = await database
          .select(database.localEntityRecords)
          .getSingle();
      expect(record.revision, 2);
      expect(record.lastCommandId, 'health-command-1');
    },
  );

  test(
    'occurrence repair rebases identity without losing task edits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      const userId = 'owner-task';
      const entityId = 'task-23';
      const commandId = 'rejected-task-update';
      final now = DateTime.utc(2026, 8, 22, 13);
      const rejectedPayload = <String, dynamic>{
        'title': 'Edited routine title',
        'description': 'Keep this detailed note',
        'domain_id': null,
        'priority': 3,
        'execution_mode': 'pomodoro',
        'scheduled_date': '2026-08-22',
        'planned_start': '2026-08-22T07:00:00.000Z',
        'planned_end': '2026-08-22T07:45:00.000Z',
        'due_at': null,
        'estimated_duration_ms': 2700000,
        'roadmap_id': null,
        'roadmap_phase_id': null,
        'template_id': 'template-1',
        'occurrence_key': '2026-08-22',
        'data': <String, dynamic>{'note': 'Do not discard this'},
      };
      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: entityId,
              userId: userId,
              title: 'Canonical routine title',
              description: const Value('Canonical note'),
              priority: const Value(2),
              executionMode: const Value('manual'),
              scheduledDate: Value(DateTime(2026, 8, 23)),
              plannedStart: Value(DateTime.utc(2026, 8, 23, 7)),
              plannedEnd: Value(DateTime.utc(2026, 8, 23, 7, 45)),
              estimatedDurationMs: const Value(2700000),
              templateId: const Value('template-1'),
              occurrenceKey: const Value('2026-08-23'),
              dataJson: const Value(
                '{"note":"canonical","time_zone":"Africa/Cairo"}',
              ),
              revision: const Value(4),
              createdAt: now.subtract(const Duration(days: 1)),
              updatedAt: now,
              lastCommandId: const Value('accepted-command'),
            ),
          );
      await database
          .into(database.localOutboxCommands)
          .insert(
            LocalOutboxCommandsCompanion.insert(
              commandId: commandId,
              userId: userId,
              deviceId: 'legacy-device',
              deviceSequence: 1,
              entityType: 'task_occurrences',
              entityId: entityId,
              commandType: 'update',
              baseRevision: 4,
              payloadJson: jsonEncode(rejectedPayload),
              status: const Value('conflict'),
              lastError: const Value(
                '{"reason":"unique_constraint","code":"23505"}',
              ),
              clientTimestamp: now,
              createdAt: now,
            ),
          );
      final service = SyncService(
        database: database,
        client: SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test_key',
        ),
      );
      const canonical = <String, dynamic>{
        'id': entityId,
        'user_id': userId,
        'template_id': 'template-1',
        'occurrence_key': '2026-08-23',
        'title': 'Canonical routine title',
        'description': 'Canonical note',
        'domain_id': null,
        'priority': 2,
        'execution_mode': 'manual',
        'scheduled_date': '2026-08-23',
        'planned_start': '2026-08-23T07:00:00.000Z',
        'planned_end': '2026-08-23T07:45:00.000Z',
        'due_at': null,
        'estimated_duration_ms': 2700000,
        'roadmap_id': null,
        'roadmap_phase_id': null,
        'data': <String, dynamic>{
          'note': 'canonical',
          'time_zone': 'Africa/Cairo',
        },
        'last_command_id': 'accepted-command',
        'revision': 4,
        'deleted_at': null,
      };
      const collision = <String, dynamic>{
        'id': 'task-22',
        'user_id': userId,
        'template_id': 'template-1',
        'occurrence_key': '2026-08-22',
        'deleted_at': null,
      };

      expect(
        await service.rebaseRejectedTaskOccurrenceIdentityUpdateForTesting(
          commandId: commandId,
          canonical: canonical,
          collision: collision,
        ),
        isTrue,
      );
      expect(
        await service.rebaseRejectedTaskOccurrenceIdentityUpdateForTesting(
          commandId: commandId,
          canonical: canonical,
          collision: collision,
        ),
        isFalse,
        reason:
            'The rejected command is retired after exactly one replacement.',
      );

      final replacementId = repairedTaskOccurrenceIdentityCommandId(
        userId: userId,
        originalCommandId: commandId,
      );
      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(commands, hasLength(2));
      expect(
        commands.singleWhere((item) => item.commandId == commandId).status,
        'superseded',
      );
      final replacement = commands.singleWhere(
        (item) => item.commandId == replacementId,
      );
      final payload = jsonDecode(replacement.payloadJson) as Map;
      expect(payload['title'], rejectedPayload['title']);
      expect(payload['description'], rejectedPayload['description']);
      expect(payload['scheduled_date'], rejectedPayload['scheduled_date']);
      expect(payload['planned_start'], rejectedPayload['planned_start']);
      expect(payload['estimated_duration_ms'], 2700000);
      expect(payload['data'], rejectedPayload['data']);
      expect(payload['template_id'], 'template-1');
      expect(payload['occurrence_key'], '2026-08-23');
      expect(replacement.baseRevision, 4);

      final task = await database.select(database.localTasks).getSingle();
      expect(task.title, 'Edited routine title');
      expect(task.description, 'Keep this detailed note');
      expect(task.scheduledDate, DateTime(2026, 8, 22));
      expect(task.estimatedDurationMs, 2700000);
      expect(jsonDecode(task.dataJson), {
        'note': 'Do not discard this',
        'time_zone': 'Africa/Cairo',
      });
      expect(task.occurrenceKey, '2026-08-23');
      expect(task.revision, 5);
      expect(task.lastCommandId, replacementId);
    },
  );

  test(
    'only a 23505 canonical built-in Area collision is an automatic alias',
    () {
      const payload = <String, Object?>{
        'name': 'Learning',
        'data': <String, Object?>{'built_in': true, 'domain_key': 'learning'},
      };
      expect(
        isBuiltInTaskDomainUniqueConflict(
          entityType: 'task_domains',
          commandType: 'create',
          errorCode: '23505',
          errorMessage:
              'duplicate key violates task_domains_user_builtin_key_unique '
              '(user_id, domain_key)',
          payload: payload,
        ),
        isTrue,
      );
      expect(
        isBuiltInTaskDomainUniqueConflict(
          entityType: 'task_domains',
          commandType: 'create',
          errorCode: '23505',
          errorMessage:
              'duplicate key violates task_domains_user_builtin_key_unique',
          payload: const {
            'name': 'My work',
            'data': <String, Object?>{'built_in': false},
          },
        ),
        isFalse,
        reason: 'A custom Area collision remains genuine user intent.',
      );
      expect(
        isBuiltInTaskDomainUniqueConflict(
          entityType: 'task_domains',
          commandType: 'create',
          errorCode: '42501',
          errorMessage: 'permission denied',
          payload: payload,
        ),
        isFalse,
      );
    },
  );

  test(
    'transient delivery stays pending while real rejection is diagnostic',
    () {
      expect(
        classifySyncDeliveryFailure(
          entityType: 'activity_segments',
          commandType: 'update',
          errorCode: '23503',
          errorMessage: 'parent command has not arrived yet',
        ),
        SyncDeliveryFailureKind.retryable,
      );
      expect(
        classifySyncDeliveryFailure(
          entityType: 'task_occurrences',
          commandType: 'update',
          errorCode: '42501',
          errorMessage: 'permission denied',
        ),
        SyncDeliveryFailureKind.permanent,
      );
      expect(
        classifySyncDeliveryFailure(
          entityType: 'execution_runtime_start_cleanup',
          commandType: 'retire',
          errorCode: 'PGRST202',
          errorMessage: 'RPC was not found in the schema cache',
        ),
        SyncDeliveryFailureKind.permanent,
      );
      expect(syncRetryDelay(1), const Duration(seconds: 5));
      expect(syncRetryDelay(6), const Duration(seconds: 160));
      expect(syncRetryDelay(20), const Duration(seconds: 160));
      expect(
        isPermanentSyncInfrastructureFailure(
          errorCode: null,
          errorMessage: 'SocketException: connection reset',
        ),
        isFalse,
      );
      expect(
        isPermanentSyncInfrastructureFailure(
          errorCode: '42501',
          errorMessage: 'permission denied',
        ),
        isTrue,
      );
    },
  );

  test('missing approved segment update can become its first create', () {
    expect(
      shouldRecreateMissingActivitySegment(
        commandType: 'update',
        hasAcceptedCreate: false,
        hasLocalSegment: true,
      ),
      isTrue,
    );
    expect(
      shouldRecreateMissingActivitySegment(
        commandType: 'update',
        hasAcceptedCreate: true,
        hasLocalSegment: true,
      ),
      isFalse,
    );
    expect(
      shouldRecreateMissingActivitySegment(
        commandType: 'update',
        hasAcceptedCreate: false,
        hasLocalSegment: false,
      ),
      isFalse,
    );
  });

  test('a 30-command missing Activity chain becomes one create', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const userId = 'account-a';
    const segmentId = 'segment-a';
    final now = DateTime.utc(2026, 7, 28, 20);
    await database
        .into(database.localActivitySegments)
        .insert(
          LocalActivitySegmentsCompanion.insert(
            id: segmentId,
            userId: userId,
            deviceId: 'device-a',
            deviceEventId: 'event-a',
            startedAt: now,
            endedAt: now.add(const Duration(minutes: 12)),
            sourceType: 'android_usage',
            createdAt: now,
            updatedAt: now,
          ),
        );
    for (var index = 0; index < 30; index++) {
      await database
          .into(database.localOutboxCommands)
          .insert(
            LocalOutboxCommandsCompanion.insert(
              commandId: 'command-$index',
              userId: userId,
              deviceId: 'device-a',
              deviceSequence: index + 1,
              entityType: 'activity_segments',
              entityId: segmentId,
              commandType: 'update',
              baseRevision: 1,
              payloadJson:
                  '{"started_at":"2026-07-28T20:00:00.000Z",'
                  '"ended_at":"2026-07-28T20:${index.toString().padLeft(2, '0')}:00.000Z"}',
              status: const Value('conflict'),
              lastError: const Value(
                '{"status":"conflict","reason":"missing_entity"}',
              ),
              clientTimestamp: now.add(Duration(seconds: index)),
              createdAt: now.add(Duration(seconds: index)),
            ),
          );
    }

    final service = SyncService(
      database: database,
      client: SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
      ),
    );
    await service.repairResolvedConflictsForTesting(userId);

    final commands = await database.select(database.localOutboxCommands).get();
    final pending = commands.where((command) => command.status == 'pending');
    expect(pending, hasLength(1));
    expect(pending.single.commandId, 'command-29');
    expect(pending.single.commandType, 'create');
    expect(pending.single.baseRevision, 0);
    expect(pending.single.lastError, isNull);
    expect(
      commands.where((command) => command.status == 'superseded'),
      hasLength(29),
    );
  });

  test('application catalog identity is stable across devices', () {
    final first = applicationCatalogIdFor(
      userId: 'account-a',
      platform: 'Android',
      applicationIdentifier: 'Com.Duolingo',
    );
    final second = applicationCatalogIdFor(
      userId: 'account-a',
      platform: 'android',
      applicationIdentifier: 'com.duolingo',
    );
    expect(first, second);
    expect(
      applicationCatalogIdFor(
        userId: 'account-b',
        platform: 'android',
        applicationIdentifier: 'com.duolingo',
      ),
      isNot(first),
    );
    expect(
      applicationCatalogIdFor(
        userId: 'account-a',
        platform: 'windows',
        applicationIdentifier: 'com.duolingo',
      ),
      isNot(first),
    );
  });

  test('canonical runtime waits for transitions and cross-task switches', () {
    expect(
      shouldDeferCanonicalRuntimeApply(const [
        (entityType: 'execution_runtime', payload: <String, dynamic>{}),
      ]),
      isTrue,
    );
    expect(
      shouldDeferCanonicalRuntimeApply(const [
        (entityType: 'execution_runtime_switch', payload: <String, dynamic>{}),
      ]),
      isTrue,
    );
    expect(
      shouldDeferCanonicalRuntimeApply(const [
        (entityType: 'task_occurrences', payload: <String, dynamic>{}),
      ]),
      isFalse,
    );
    expect(shouldDeferCanonicalRuntimeApply(const []), isFalse);
    expect(
      shouldDeferCanonicalRuntimeApply(const [
        (
          entityType: 'execution_runtime_stale_pause',
          payload: <String, dynamic>{'expected_runtime_revision': 8},
        ),
      ]),
      isTrue,
      reason: 'A stale-pause command only owns the runtime it actually paused.',
    );
    expect(
      shouldDeferCanonicalRuntimeApply(const [
        (
          entityType: 'execution_runtime_stale_pause',
          payload: <String, dynamic>{'expected_runtime_revision': null},
        ),
      ]),
      isFalse,
      reason:
          'Resolving an old paused task must not block a newer running task.',
    );
  });

  test(
    'stale-pause acknowledgements never overwrite later optimistic work',
    () {
      expect(
        shouldApplyAcknowledgedCanonicalAggregate(
          localRevision: 4,
          localCommandId: 'stale-pause-command',
          incomingRevision: 5,
          incomingCommandId: 'stale-pause-command',
          acknowledgedCommandId: 'stale-pause-command',
          hasPendingProjection: false,
        ),
        isTrue,
      );
      expect(
        shouldApplyAcknowledgedCanonicalAggregate(
          localRevision: 6,
          localCommandId: 'later-edit',
          incomingRevision: 5,
          incomingCommandId: 'stale-pause-command',
          acknowledgedCommandId: 'stale-pause-command',
          hasPendingProjection: true,
          allowAcknowledgedRollback: true,
        ),
        isFalse,
        reason: 'A later queued edit owns the visible projection.',
      );
      expect(
        shouldApplyAcknowledgedCanonicalAggregate(
          localRevision: 6,
          localCommandId: 'later-edit',
          incomingRevision: 5,
          incomingCommandId: 'stale-pause-command',
          acknowledgedCommandId: 'stale-pause-command',
          hasPendingProjection: false,
          allowAcknowledgedRollback: true,
        ),
        isFalse,
        reason: 'A delayed acknowledgement cannot roll back another command.',
      );
      expect(
        shouldApplyAcknowledgedCanonicalAggregate(
          localRevision: 6,
          localCommandId: 'stale-pause-command',
          incomingRevision: 5,
          incomingCommandId: 'previous-server-command',
          acknowledgedCommandId: 'stale-pause-command',
          hasPendingProjection: false,
          allowAcknowledgedRollback: true,
        ),
        isTrue,
        reason: 'A canonical-only result may roll back its own optimistic row.',
      );
    },
  );

  test('canonical runtime applies only forward revisions', () {
    expect(
      canonicalRuntimeApplyDecision(
        localRevision: null,
        localCommandId: null,
        incomingRevision: 1,
        incomingCommandId: 'first',
      ),
      CanonicalRuntimeApplyDecision.apply,
    );
    expect(
      canonicalRuntimeApplyDecision(
        localRevision: 8,
        localCommandId: 'local-8',
        incomingRevision: 9,
        incomingCommandId: 'remote-9',
      ),
      CanonicalRuntimeApplyDecision.apply,
    );
    expect(
      canonicalRuntimeApplyDecision(
        localRevision: 8,
        localCommandId: 'local-8',
        incomingRevision: 7,
        incomingCommandId: 'remote-7',
      ),
      CanonicalRuntimeApplyDecision.staleOrInconsistent,
    );
    expect(
      canonicalRuntimeApplyDecision(
        localRevision: 8,
        localCommandId: 'same-command',
        incomingRevision: 8,
        incomingCommandId: 'same-command',
      ),
      CanonicalRuntimeApplyDecision.duplicate,
    );
    expect(
      canonicalRuntimeApplyDecision(
        localRevision: 8,
        localCommandId: 'local-8',
        incomingRevision: 8,
        incomingCommandId: 'different-command',
      ),
      CanonicalRuntimeApplyDecision.staleOrInconsistent,
    );
  });

  test('an execution acknowledgement corrects only its own equal revision', () {
    expect(
      shouldApplyAcknowledgedCanonicalRuntime(
        localRevision: 8,
        localCommandId: 'command-8',
        incomingRevision: 8,
        incomingCommandId: 'command-8',
        acknowledgedCommandId: 'command-8',
      ),
      isTrue,
      reason:
          'The canonical RPC row must replace its matching optimistic snapshot.',
    );
    expect(
      shouldApplyAcknowledgedCanonicalRuntime(
        localRevision: 8,
        localCommandId: 'newer-local-command',
        incomingRevision: 8,
        incomingCommandId: 'acknowledged-command',
        acknowledgedCommandId: 'acknowledged-command',
      ),
      isFalse,
      reason:
          'A different equal-revision command is not ordered after local state.',
    );
    expect(
      shouldApplyAcknowledgedCanonicalRuntime(
        localRevision: 9,
        localCommandId: 'newer-command',
        incomingRevision: 8,
        incomingCommandId: 'acknowledged-command',
        acknowledgedCommandId: 'acknowledged-command',
      ),
      isFalse,
      reason: 'An acknowledged response must never roll back a newer revision.',
    );
    expect(
      shouldApplyAcknowledgedCanonicalRuntime(
        localRevision: 9,
        localCommandId: 'superseded-command',
        incomingRevision: 8,
        incomingCommandId: 'previous-server-command',
        acknowledgedCommandId: 'superseded-command',
        superseded: true,
      ),
      isTrue,
      reason:
          'A canonical-only result must remove its own rejected optimistic transition.',
    );
    expect(
      shouldApplyAcknowledgedCanonicalRuntime(
        localRevision: 9,
        localCommandId: 'later-local-command',
        incomingRevision: 8,
        incomingCommandId: 'previous-server-command',
        acknowledgedCommandId: 'superseded-command',
        superseded: true,
      ),
      isFalse,
      reason:
          'A superseded response cannot roll back a different local command.',
    );
  });

  test(
    'a stale runtime command retires silently and uses its returned canonical state',
    () {
      expect(
        isCanonicalOnlyRuntimeResponse(
          entityType: 'execution_runtime',
          result: const {
            'status': 'accepted',
            'canonical_only': true,
            'superseded': true,
            'canonical_runtime': {'revision': 12},
          },
        ),
        isTrue,
      );
      expect(
        isCanonicalOnlyRuntimeResponse(
          entityType: 'execution_runtime_stale_pause',
          result: const {
            'status': 'accepted',
            'canonical_only': true,
            'canonical_task': {'revision': 9},
            'canonical_session': {'revision': 6},
            'canonical_runtime': {'revision': 15},
          },
        ),
        isTrue,
        reason:
            'A revision-losing stale-pause decision already carries the canonical aggregate.',
      );
      expect(
        isCanonicalOnlyRuntimeResponse(
          entityType: 'execution_break_extension',
          result: const {
            'status': 'accepted',
            'superseded': true,
            'canonical_task': {'revision': 11},
            'canonical_runtime': {'revision': 15},
          },
        ),
        isTrue,
        reason:
            'A stale notification action already carries the break interval which replaced it.',
      );
      expect(
        isCanonicalOnlyRuntimeResponse(
          entityType: 'execution_break_extension',
          result: const {
            'status': 'accepted',
            'canonical_only': true,
            'canonical_task': {'revision': 12},
          },
        ),
        isTrue,
        reason:
            'A stale break action owns only the task projection and does not require a live runtime row.',
      );
      expect(
        isCanonicalOnlyRuntimeResponse(
          entityType: 'task_occurrences',
          result: const {
            'status': 'accepted',
            'canonical_only': true,
            'canonical_runtime': {'revision': 12},
          },
        ),
        isFalse,
      );
      expect(
        isCanonicalOnlyRuntimeResponse(
          entityType: 'execution_runtime_switch',
          result: const {'status': 'accepted', 'canonical_only': true},
        ),
        isFalse,
        reason:
            'A server response without canonical state must not erase local runtime.',
      );
    },
  );

  test('stale-pause RPC and canonical aggregate application stay complete', () {
    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    final rpcMatch = RegExp(
      r": command\.entityType == 'execution_runtime_stale_pause'"
      r'(?<body>[\s\S]*?)'
      r": command\.entityType == 'vacation_periods'",
    ).firstMatch(source);
    expect(rpcMatch, isNotNull);
    final rpc = rpcMatch!.namedGroup('body')!;
    expect(rpc, contains("'resolve_stale_paused_task_v0034_command'"));
    for (final parameter in const [
      "'p_command_id': command.commandId",
      "'p_device_id': command.deviceId",
      "'p_device_sequence': command.deviceSequence",
      "'p_task_occurrence_id': command.entityId",
      "'p_session_id': payload['session_id']",
      "'p_decision': payload['decision']",
      "'p_expected_task_revision': command.baseRevision",
      "'p_expected_runtime_revision':",
      "payload['expected_runtime_revision']",
      "'p_resolved_at': payload['resolved_at']",
    ]) {
      expect(rpc, contains(parameter), reason: 'Missing RPC input: $parameter');
    }

    final applyMatch = RegExp(
      r"if \(command\.entityType == 'execution_runtime_stale_pause'\) \{"
      r'(?<body>[\s\S]*?)'
      r'\n    \}\n    if \(const \{',
    ).firstMatch(source);
    expect(applyMatch, isNotNull);
    final apply = applyMatch!.namedGroup('body')!;
    final taskIndex = apply.indexOf('if (canonicalTask != null');
    final sessionIndex = apply.indexOf('if (canonicalSession != null');
    final runtimeIndex = apply.indexOf('if (canonicalRuntime is Map)');
    expect(taskIndex, greaterThanOrEqualTo(0));
    expect(sessionIndex, greaterThan(taskIndex));
    expect(runtimeIndex, greaterThan(sessionIndex));
    expect(apply, contains('await _applyTask('));
    expect(apply, contains("'execution_sessions'"));
    expect(apply, contains('await _applyGeneric('));
    expect(apply, contains('await _applyRemoteRuntime('));
    expect(apply, contains('acknowledgedCommandId: command.commandId'));
    expect(apply, contains('excludingCommandId: command.commandId'));
    expect(apply, contains('shouldApplyAcknowledgedCanonicalAggregate('));
    expect(
      apply,
      contains(
        "result['canonical_only'] == true || result['superseded'] == true",
      ),
    );
  });

  test('break extension delivery uses the dedicated v0036 aggregate RPC', () {
    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    final rpcMatch = RegExp(
      r": command\.entityType == 'execution_break_extension'"
      r'(?<body>[\s\S]*?)'
      r": command\.entityType == 'vacation_periods'",
    ).firstMatch(source);
    expect(rpcMatch, isNotNull);
    final rpc = rpcMatch!.namedGroup('body')!;
    expect(rpc, contains("'extend_active_break_v0036_command'"));
    for (final parameter in const [
      "'p_command_id': command.commandId",
      "'p_device_id': command.deviceId",
      "'p_device_sequence': command.deviceSequence",
      "'p_session_id': command.entityId",
      "'p_task_occurrence_id': payload['task_occurrence_id']",
      "'p_expected_task_revision': command.baseRevision",
      "'p_break_started_at': payload['break_started_at']",
      "'p_boundary_at': payload['boundary_at']",
      "'p_extension_ms': payload['extension_ms']",
      "'p_requested_at': payload['requested_at']",
    ]) {
      expect(rpc, contains(parameter), reason: 'Missing RPC input: $parameter');
    }

    final applyMatch = RegExp(
      r"if \(command\.entityType == 'execution_break_extension'\) \{"
      r'(?<body>[\s\S]*?)'
      r"\n    \}\n    if \(command\.entityType == 'execution_runtime_stale_pause'\)",
    ).firstMatch(source);
    expect(applyMatch, isNotNull);
    final apply = applyMatch!.namedGroup('body')!;
    expect(apply, contains("result['canonical_task']"));
    expect(apply, contains('excludingCommandId: command.commandId'));
    expect(apply, contains('shouldApplyAcknowledgedCanonicalAggregate('));
    expect(apply, contains('await _applyTask(canonicalTask)'));
  });

  test('healthy idle Realtime performs no timer-driven remote recovery', () {
    for (var resume = 0; resume < 22; resume++) {
      expect(
        shouldReuseStartedSyncService(
          startedForUserId: 'account-a',
          requestedUserId: 'account-a',
        ),
        isTrue,
        reason: 'Resume $resume must reuse workers without a REST pull.',
      );
    }
    expect(
      shouldReuseStartedSyncService(
        startedForUserId: 'account-a',
        requestedUserId: 'account-b',
      ),
      isFalse,
    );
    expect(
      shouldRunRemoteRecovery(
        connectivityRestored: false,
        realtimeRecovered: false,
        realtimeGapExpired: false,
        snapshotInvalidated: false,
        explicitlyRequested: false,
      ),
      isFalse,
      reason:
          'Five idle minutes (or any idle duration) must create zero fallback reads.',
    );
    for (final recovery in const [
      (true, false, false, false, false),
      (false, true, false, false, false),
      (false, false, true, false, false),
      (false, false, false, true, false),
      (false, false, false, false, true),
    ]) {
      expect(
        shouldRunRemoteRecovery(
          connectivityRestored: recovery.$1,
          realtimeRecovered: recovery.$2,
          realtimeGapExpired: recovery.$3,
          snapshotInvalidated: recovery.$4,
          explicitlyRequested: recovery.$5,
        ),
        isTrue,
      );
    }

    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    final emptyOutboxBlock = RegExp(
      r'if \(commands\.isEmpty\) \{(?<body>[\s\S]*?)\n    \}',
    ).firstMatch(source);

    expect(emptyOutboxBlock, isNotNull);
    expect(
      emptyOutboxBlock!.namedGroup('body'),
      isNot(contains('pullChanges')),
    );
    expect(source, isNot(contains('Timer.periodic(')));
    expect(
      source,
      contains('const _deviceAuthorizationTtl = Duration(minutes: 30)'),
    );
    expect(source, contains('realtimeGapExpired: true'));
    expect(
      source,
      isNot(contains('_synchronizeOperation.inFlight == null')),
      reason:
          'A successful join during recovery must replay one final cursor catch-up.',
    );
    expect(source, isNot(contains('_realtimeRecoveryAttemptedForGap')));
    expect(realtimeReconnectDelay(0), const Duration(seconds: 20));
    expect(realtimeReconnectDelay(1), const Duration(seconds: 40));
    expect(realtimeReconnectDelay(4), const Duration(seconds: 320));
    expect(realtimeReconnectDelay(40), const Duration(seconds: 320));
    final shell = File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsStringSync();
    expect(
      shell,
      contains('getSnapshot(checkRemoteDevices: false)'),
      reason:
          'The 15-second Windows tray tick must use cached sync health rather than poll account devices.',
    );
  });

  test(
    'duplicate Realtime handlers are derived from measured channel state',
    () {
      expect(
        duplicateRealtimeHandlerCount(
          activeAccountChannels: 1,
          registeredEventHandlers: 1,
        ),
        0,
      );
      expect(
        duplicateRealtimeHandlerCount(
          activeAccountChannels: 1,
          registeredEventHandlers: 3,
        ),
        2,
      );
      expect(
        duplicateRealtimeHandlerCount(
          activeAccountChannels: 0,
          registeredEventHandlers: 1,
        ),
        1,
      );
    },
  );

  test('an overlapping sync wake-up replays after the current pass', () async {
    final operation = ReplayableSyncOperation();
    final firstPass = Completer<void>();
    var passCount = 0;

    Future<void> pass() async {
      passCount += 1;
      if (passCount == 1) await firstPass.future;
    }

    final first = operation.run(pass);
    await Future<void>.delayed(Duration.zero);
    final overlapping = operation.run(pass);

    expect(identical(first, overlapping), isTrue);
    expect(passCount, 1);
    firstPass.complete();
    await first;
    expect(passCount, 2);
    expect(operation.inFlight, isNull);
  });

  test('Realtime recovery finishes with one cursor catch-up per outage', () {
    expect(
      shouldRunFinalRealtimeCatchUp(
        recoveredFromGap: true,
        initialSyncComplete: true,
        recoveredGeneration: 8,
        lastCatchUpGeneration: 7,
      ),
      isTrue,
    );
    expect(
      shouldRunFinalRealtimeCatchUp(
        recoveredFromGap: true,
        initialSyncComplete: true,
        recoveredGeneration: 8,
        lastCatchUpGeneration: 8,
      ),
      isFalse,
    );
    expect(
      shouldRunFinalRealtimeCatchUp(
        recoveredFromGap: false,
        initialSyncComplete: true,
        recoveredGeneration: 8,
        lastCatchUpGeneration: 7,
      ),
      isFalse,
    );
  });

  test('internal cleanup remains diagnostic but not user-pending work', () {
    expect(
      isUserVisiblePendingSyncCommand('execution_runtime_start_cleanup'),
      isFalse,
    );
    expect(isUserVisiblePendingSyncCommand('task_occurrences'), isTrue);

    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    expect(
      source,
      contains(".equals('execution_runtime_start_cleanup')"),
      reason: 'The visible pending count must exclude maintenance cleanup.',
    );
    expect(
      source,
      contains("row.status.isIn(const ['pending', 'conflict'])"),
      reason: 'Technical diagnostics must retain internal cleanup failures.',
    );
    expect(
      RegExp(
        r"row\.entityType\s*\.equals\('execution_runtime_start_cleanup'\)\s*\.not\(\)",
      ).allMatches(source).length,
      greaterThanOrEqualTo(1),
      reason: 'Maintenance cleanup must not create user conflict cards.',
    );
  });

  test('incremental cursor consumes change pages oldest first', () {
    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    expect(
      source,
      contains(".order('change_sequence', ascending: true)"),
      reason:
          'PostgREST order defaults to descending; cursor pages must opt in to ascending order.',
    );
    expect(
      source,
      contains(
        'await _pullOperation.run(() => _pullChangesTracked(generation, userId))',
      ),
      reason:
          'A pull requested during an in-flight pass must replay after an optimistic command settles.',
    );
  });

  test('sync health settles only after operation markers clear', () {
    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    expect(
      RegExp(
        r'await _synchronizeOperation\.run\([\s\S]*?'
        r'if \(_isCurrentOperation\(generation, userId\)\) \{\s*'
        r'await _settleHealth\(\);',
      ).hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(
        r'await _drainOperation\.run\([\s\S]*?'
        r'if \(_isCurrentOperation\(generation, userId\)\) \{\s*'
        r'await _settleHealth\(\);',
      ).hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(
        r'await _pullOperation\.run\([\s\S]*?await _settleHealth\(\);',
      ).hasMatch(source),
      isTrue,
    );
  });

  test('only active work spins while queued recovery waits', () {
    expect(
      deriveSyncHealth(
        online: true,
        operationInFlight: false,
        canonicalSnapshotIncomplete: true,
        pendingChanges: 0,
        failedChanges: 0,
        conflicts: 0,
        recoveryConnectionAvailable: true,
      ),
      SyncHealth.waiting,
    );
    expect(
      deriveSyncHealth(
        online: true,
        operationInFlight: true,
        pendingChanges: 0,
        failedChanges: 0,
        conflicts: 0,
        recoveryConnectionAvailable: false,
      ),
      SyncHealth.syncing,
    );
    expect(
      deriveSyncHealth(
        online: true,
        operationInFlight: false,
        pendingChanges: 0,
        failedChanges: 0,
        conflicts: 0,
        recoveryConnectionAvailable: false,
      ),
      SyncHealth.waiting,
    );
    expect(
      deriveSyncHealth(
        online: true,
        operationInFlight: false,
        pendingChanges: 4,
        failedChanges: 0,
        conflicts: 0,
        recoveryConnectionAvailable: false,
      ),
      SyncHealth.waiting,
    );
    expect(
      deriveSyncHealth(
        online: true,
        operationInFlight: false,
        pendingChanges: 4,
        failedChanges: 1,
        conflicts: 1,
        recoveryConnectionAvailable: true,
      ),
      SyncHealth.attention,
    );
  });

  test('canonical snapshot retries back off and remain bounded', () {
    expect(canonicalSnapshotRetryDelay(-1), const Duration(seconds: 20));
    expect(canonicalSnapshotRetryDelay(0), const Duration(seconds: 20));
    expect(canonicalSnapshotRetryDelay(1), const Duration(seconds: 40));
    expect(canonicalSnapshotRetryDelay(2), const Duration(seconds: 80));
    expect(canonicalSnapshotRetryDelay(3), const Duration(seconds: 160));
    expect(canonicalSnapshotRetryDelay(4), const Duration(seconds: 320));
    expect(canonicalSnapshotRetryDelay(99), const Duration(seconds: 320));
  });

  test('lifecycle reconciliation rejects payloads with independent edits', () {
    expect(
      isSemanticLifecyclePayload('task_occurrences', const {
        'status': 'paused',
        'active_duration_ms': 25000,
      }),
      isTrue,
    );
    expect(
      isSemanticLifecyclePayload('task_occurrences', const {
        'status': 'paused',
        'title': 'Keep this user edit',
      }),
      isFalse,
    );
    expect(
      isSemanticLifecyclePayload('roadmaps', const {'status': 'active'}),
      isFalse,
    );
  });

  test('legacy generic break extension retires only its transient field', () {
    final localPayload = <String, dynamic>{
      'title': 'Programming study',
      'description': 'Recurring routine',
      'domain_id': 'domain-1',
      'priority': 2,
      'execution_mode': 'pomodoro',
      'scheduled_date': '2026-08-23',
      'planned_start': '2026-08-23T16:30:00.000Z',
      'planned_end': '2026-08-23T18:00:00.000Z',
      'due_at': null,
      'estimated_duration_ms': 5400000,
      'roadmap_id': 'roadmap-1',
      'roadmap_phase_id': 'phase-1',
      'template_id': 'template-1',
      'occurrence_key': '2026-08-23',
      'data': <String, dynamic>{
        'time_zone': 'Africa/Cairo',
        'completion_method': 'duration',
        'active_break_extension_ms': 1200000,
      },
    };
    final canonical = <String, dynamic>{
      ...localPayload,
      'planned_start': '2026-08-23T16:30:00+00:00',
      'planned_end': '2026-08-23T18:00:00+00:00',
      'data': <String, dynamic>{
        'time_zone': 'Africa/Cairo',
        'completion_method': 'duration',
        'active_break_extension_ms': 300000,
      },
      'revision': 18,
    };

    expect(
      isLegacyBreakExtensionOnlyTaskConflict(
        localPayload: localPayload,
        canonicalRow: canonical,
      ),
      isTrue,
    );
    expect(
      isLegacyBreakExtensionOnlyTaskConflict(
        localPayload: {...localPayload, 'title': 'Independent edit'},
        canonicalRow: canonical,
      ),
      isFalse,
    );
    expect(
      isLegacyBreakExtensionOnlyTaskConflict(
        localPayload: {
          ...localPayload,
          'data': <String, dynamic>{
            ...(localPayload['data'] as Map<String, dynamic>),
            'completion_method': 'manual',
          },
        },
        canonicalRow: canonical,
      ),
      isFalse,
    );
    expect(
      isLegacyBreakExtensionOnlyTaskConflict(
        localPayload: {...localPayload, 'status': 'completed'},
        canonicalRow: canonical,
      ),
      isFalse,
      reason: 'A merged independent lifecycle edit must remain reviewable.',
    );
  });

  test('account generation rejects delayed work from the previous owner', () {
    expect(
      isCurrentSyncOperation(
        capturedGeneration: 4,
        currentGeneration: 4,
        expectedUserId: 'account-b',
        currentUserId: 'account-b',
        startedForUserId: 'account-b',
      ),
      isTrue,
    );
    expect(
      isCurrentSyncOperation(
        capturedGeneration: 3,
        currentGeneration: 4,
        expectedUserId: 'account-a',
        currentUserId: 'account-b',
        startedForUserId: 'account-b',
      ),
      isFalse,
    );
  });

  test('stop barrier waits for pull and drain operations to settle', () async {
    final pull = Completer<void>();
    final drain = Completer<void>();
    var settled = false;

    final barrier = waitForInFlightSyncOperations([
      pull.future,
      drain.future,
      null,
    ]).then((_) => settled = true);

    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    pull.complete();
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    drain.complete();
    await barrier;
    expect(settled, isTrue);
  });

  test('runtime commands rebase only on the exact canonical identity', () {
    final migration = File(
      'supabase/migrations/'
      '20260823190000_v0037_execution_identity_rebase.sql',
    ).readAsStringSync();

    expect(migration, contains('taskmaster.identity_rebase_command'));
    expect(
      migration,
      contains('runtime.active_session_id is not distinct from p_session_id'),
    );
    expect(
      migration,
      contains(
        'runtime.active_task_occurrence_id is not distinct from\n'
        '        p_task_occurrence_id',
      ),
    );
    expect(
      migration,
      contains(
        'runtime.active_session_id is not distinct from\n'
        '        p_expected_active_session_id',
      ),
    );
    expect(
      migration,
      contains("runtime.state in ('running', 'paused', 'break')"),
    );
    expect(
      migration,
      contains('identity_rebase_command is distinct from p_command_id::text'),
    );
    expect(
      migration,
      isNot(
        contains("set_config('taskmaster.identity_rebase_command', 'true'"),
      ),
    );
  });

  test('task-link permissions and completion projection converge safely', () {
    final migration = File(
      'supabase/migrations/'
      '20260823232000_v0038_task_link_permissions_and_execution_convergence.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        'alter function public.connect_application_to_task(\n'
        '  uuid, uuid, bigint, uuid, uuid, uuid, text, text, text, text\n'
        ') security definer',
      ),
    );
    expect(
      migration,
      contains(
        'alter function public.remove_application_from_task(\n'
        '  uuid, uuid, bigint, uuid, bigint\n'
        ') security definer',
      ),
    );
    expect(
      migration,
      contains('greatest(old.accumulated_active_ms, projected_active_ms)'),
    );
    expect(
      migration,
      contains('safe_boundary_at - old.active_segment_started_at'),
    );
    expect(
      migration,
      contains("raise exception 'invalid_projected_boundary_at'"),
      reason: 'malformed commands must still fail closed',
    );
  });
}
