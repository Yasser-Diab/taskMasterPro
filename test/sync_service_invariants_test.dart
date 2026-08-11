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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('authoritative snapshot advances only when every entity applied', () {
    expect(authoritativeSnapshotCanAdvanceCursor(const []), isTrue);
    expect(authoritativeSnapshotCanAdvanceCursor(const {'roadmaps'}), isFalse);
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

  test(
    'first-device snapshot includes task URL resources and website links',
    () {
      expect(authoritativeSnapshotEntityTypes, contains('task_resources'));
      expect(authoritativeSnapshotEntityTypes, contains('website_rules'));
      expect(
        authoritativeSnapshotEntityTypes.indexOf('task_occurrences'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('task_resources')),
      );
      expect(
        authoritativeSnapshotEntityTypes.indexOf('task_occurrences'),
        lessThan(authoritativeSnapshotEntityTypes.indexOf('website_rules')),
      );
      expect(authoritativeSnapshotStateId('user-1'), 'sync:v3:user-1');
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
      activityContributionIdFor(
        userId: '75f78e6c-0ba8-48a7-a06e-45a6fb256b9d',
        activitySegmentId: '1d310e80-61a0-48c2-96f9-cc1c21466913',
        targetTaskId: '9f51108d-0725-4a74-8ead-3017beef5854',
        contributionType: 'active_work_seconds',
      ),
      isNot(contribution),
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
  });

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

  test('an idle outbox never turns the maintenance tick into a pull loop', () {
    final source = File('lib/core/sync/sync_service.dart').readAsStringSync();
    final emptyOutboxBlock = RegExp(
      r'if \(commands\.isEmpty\) \{(?<body>[\s\S]*?)\n    \}',
    ).firstMatch(source);

    expect(emptyOutboxBlock, isNotNull);
    expect(
      emptyOutboxBlock!.namedGroup('body'),
      isNot(contains('pullChanges')),
    );
    expect(source, contains('const Duration(minutes: 2)'));
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
      SyncHealth.attention,
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
