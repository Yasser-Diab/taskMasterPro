import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
      shouldDeferCanonicalRuntimeApply(const ['execution_runtime']),
      isTrue,
    );
    expect(
      shouldDeferCanonicalRuntimeApply(const ['execution_runtime_switch']),
      isTrue,
    );
    expect(
      shouldDeferCanonicalRuntimeApply(const ['task_occurrences']),
      isFalse,
    );
    expect(shouldDeferCanonicalRuntimeApply(const []), isFalse);
  });

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
    expect(source, contains('realtimeGapExpired: firstFallbackForOutage'));
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

  test('an active recovery is syncing, not false attention', () {
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
      SyncHealth.syncing,
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
      SyncHealth.syncing,
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
      SyncHealth.syncing,
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
}
