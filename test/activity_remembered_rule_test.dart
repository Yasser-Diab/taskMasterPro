import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/activity/data/activity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ActivityRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    repository = ActivityRepository(
      database,
      SupabaseClient('https://example.supabase.co', 'sb_publishable_test_key'),
    );
  });

  tearDown(() => database.close());

  Future<void> insertSettings({
    bool automatic = false,
    bool synchronized = false,
  }) async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.localAppSettings)
        .insert(
          LocalAppSettingsCompanion.insert(
            id: 'app',
            automaticTrustedRules: Value(automatic),
            activityRuleSyncEnabled: Value(synchronized),
            detailedActivitySyncEnabled: Value(synchronized),
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (synchronized) {
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: 'privacy-local',
              userId: 'local',
              entityType: 'privacy_settings',
              dataJson: Value(
                jsonEncode({
                  'activity_storage': 'synchronized',
                  'data': {'detailed_activity_sync_opt_in': true},
                }),
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  Future<ActivityReviewEntry> captureReview({
    required String id,
    required String processName,
  }) async {
    final startedAt = DateTime.utc(
      2026,
      8,
      15,
      9,
    ).add(Duration(minutes: int.parse(id.replaceAll(RegExp(r'\D'), ''))));
    final segmentId = await repository.captureRawSegment(
      segmentId: id,
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 2)),
      sourceType: 'windows_foreground',
      processName: processName,
    );
    return (await repository.reviewEntryForSegment(segmentId))!;
  }

  Map<String, Object?> ruleData(LocalEntityRecord rule) {
    final decoded = jsonDecode(rule.dataJson);
    final data = decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{};
    final nested = data['data'];
    return nested is Map
        ? <String, Object?>{...data, ...Map<String, Object?>.from(nested)}
        : data;
  }

  Future<List<LocalEntityRecord>> allRules() {
    return (database.select(database.localEntityRecords)..where(
          (row) =>
              row.userId.equals('local') &
              row.entityType.equals('application_rules'),
        ))
        .get();
  }

  test(
    'System and useful reclassification updates one semantic rule idempotently',
    () async {
      await insertSettings();
      final entry = await captureReview(
        id: 'segment-1',
        processName: 'Code.exe',
      );

      await repository.resolve(
        entry,
        const ActivityResolution(
          status: 'ignored',
          classification: 'system_activity',
          rememberRule: true,
        ),
      );

      var live = (await allRules())
          .where((rule) => rule.deletedAt == null)
          .toList();
      expect(live, hasLength(1));
      expect(ruleData(live.single)['classification'], 'system_activity');

      // Simulate a legacy duplicate from an older build. Its higher canonical
      // revision must win even though its wall clock is older.
      final applicationId = ruleData(live.single)['application_id'] as String;
      final oldClock = DateTime.utc(2026, 8, 14);
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: 'legacy-duplicate-rule',
              userId: 'local',
              entityType: 'application_rules',
              parentId: const Value('local'),
              secondaryParentId: Value(applicationId),
              title: const Value('Code'),
              status: const Value('active'),
              dataJson: Value(
                jsonEncode({
                  'application_id': applicationId,
                  'platform': 'windows',
                  'application_identifier':
                      'windows|foreground_user_surface|code.exe',
                  'scope_type': 'user',
                  'scope_id': 'local',
                  'classification': 'system_activity',
                  'target_type': null,
                  'target_id': null,
                  'contribution_type': null,
                  'automatic_credit': false,
                  'priority': 300,
                  'rule_origin': 'user_confirmed',
                }),
              ),
              revision: const Value(7),
              createdAt: oldClock,
              updatedAt: oldClock,
            ),
          );

      await repository.resolve(
        entry,
        const ActivityResolution(
          status: 'confirmed',
          classification: 'supporting_work',
          rememberRule: true,
        ),
      );

      var rules = await allRules();
      live = rules.where((rule) => rule.deletedAt == null).toList();
      expect(live, hasLength(1));
      expect(live.single.id, 'legacy-duplicate-rule');
      expect(live.single.revision, 8);
      expect(ruleData(live.single)['classification'], 'supporting_work');
      expect(rules.where((rule) => rule.deletedAt != null), hasLength(1));

      await repository.resolve(
        entry,
        const ActivityResolution(
          status: 'ignored',
          classification: 'system_activity',
          rememberRule: true,
        ),
      );
      live = (await allRules())
          .where((rule) => rule.deletedAt == null)
          .toList();
      expect(live, hasLength(1));
      expect(live.single.revision, 9);
      expect(ruleData(live.single)['classification'], 'system_activity');

      await repository.resolve(
        entry,
        const ActivityResolution(
          status: 'ignored',
          classification: 'system_activity',
          rememberRule: true,
        ),
      );
      final repeated = (await allRules())
          .where((rule) => rule.deletedAt == null)
          .single;
      expect(repeated.id, live.single.id);
      expect(repeated.revision, 9, reason: 'an identical rule is a no-op');
    },
  );

  test('remembered app category is independent from task credit', () async {
    await insertSettings();
    final entry = await captureReview(
      id: 'segment-30',
      processName: 'MusicPlayer.exe',
    );

    await repository.resolve(
      entry,
      const ActivityResolution(
        status: 'confirmed',
        classification: 'passive_useful_activity',
        rememberRule: true,
        applicationCategory: 'music_audio',
        applicationIsUseful: true,
      ),
    );

    final rule = (await allRules()).singleWhere(
      (candidate) => candidate.deletedAt == null,
    );
    expect(ruleData(rule)['classification'], 'passive_useful_activity');
    expect(ruleData(rule)['application_category'], 'music_audio');
    expect(ruleData(rule)['application_is_useful'], isTrue);
  });

  test(
    'automatic classification uses revision before a skewed updatedAt',
    () async {
      await insertSettings(automatic: true);
      final futureClock = DateTime.utc(2035);
      final canonicalClock = DateTime.utc(2026);
      const identifier = 'windows|foreground_user_surface|chatgpt.exe';
      Future<void> insertRule({
        required String id,
        required String classification,
        required int revision,
        required DateTime updatedAt,
      }) {
        return database
            .into(database.localEntityRecords)
            .insert(
              LocalEntityRecordsCompanion.insert(
                id: id,
                userId: 'local',
                entityType: 'application_rules',
                parentId: const Value('local'),
                title: const Value('ChatGPT'),
                status: const Value('active'),
                dataJson: Value(
                  jsonEncode({
                    'application_identifier': identifier,
                    'scope_type': 'user',
                    'scope_id': 'local',
                    'classification': classification,
                    'automatic_credit': false,
                  }),
                ),
                revision: Value(revision),
                createdAt: canonicalClock,
                updatedAt: updatedAt,
              ),
            );
      }

      await insertRule(
        id: 'stale-future-clock',
        classification: 'system_activity',
        revision: 2,
        updatedAt: futureClock,
      );
      await insertRule(
        id: 'canonical-revision',
        classification: 'supporting_work',
        revision: 3,
        updatedAt: canonicalClock,
      );

      await captureReview(id: 'segment-2', processName: 'ChatGPT.exe');

      expect(await repository.watchReviewQueue().first, isEmpty);
      final attributions = await database
          .select(database.localAttributions)
          .get();
      expect(attributions.single.classification, 'supporting_work');
    },
  );

  test(
    'synchronized repeated intent is a no-op and reclassification gets a new command identity',
    () async {
      await insertSettings(synchronized: true);
      final entry = await captureReview(
        id: 'segment-4',
        processName: 'Terminal.exe',
      );
      const system = ActivityResolution(
        status: 'ignored',
        classification: 'system_activity',
        rememberRule: true,
      );

      await repository.resolve(entry, system);
      final firstReview = (await repository.reviewEntryForSegment(
        entry.segment.id,
      ))!;
      final firstRule = (await allRules())
          .where((rule) => rule.deletedAt == null)
          .single;
      final firstCommands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('activity_review_classifications'),
              ))
              .get();
      expect(firstCommands, hasLength(1));
      expect(firstCommands.single.baseRevision, entry.review.revision);
      expect(
        firstReview.review.revision,
        entry.review.revision + 1,
        reason: 'an accepted classification advances exactly N to N + 1',
      );

      await repository.resolve(firstReview, system);
      final repeatedReview = (await repository.reviewEntryForSegment(
        entry.segment.id,
      ))!;
      final repeatedRule = (await allRules())
          .where((rule) => rule.deletedAt == null)
          .single;
      final repeatedCommands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('activity_review_classifications'),
              ))
              .get();
      expect(repeatedReview.review.revision, firstReview.review.revision);
      expect(repeatedRule.revision, firstRule.revision);
      expect(repeatedCommands, hasLength(1));

      await repository.resolve(
        repeatedReview,
        const ActivityResolution(
          status: 'confirmed',
          classification: 'supporting_work',
          rememberRule: true,
        ),
      );
      final reclassified = (await allRules())
          .where((rule) => rule.deletedAt == null)
          .single;
      final reclassificationCommands =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.entityType.equals('activity_review_classifications'),
              ))
              .get();
      expect(ruleData(reclassified)['classification'], 'supporting_work');
      expect(reclassified.id, firstRule.id);
      expect(reclassificationCommands, hasLength(2));
      expect(
        reclassificationCommands.map((command) => command.commandId).toSet(),
        hasLength(2),
      );
      expect(
        reclassificationCommands.map((command) => command.baseRevision).toSet(),
        {entry.review.revision, firstReview.review.revision},
      );
      final commandsBySequence = [...reclassificationCommands]
        ..sort(
          (left, right) => left.deviceSequence.compareTo(right.deviceSequence),
        );
      expect(
        commandsBySequence.map((command) => command.baseRevision).toList(),
        [entry.review.revision, entry.review.revision + 1],
        reason:
            'the next offline intent must use canonical base revision N + 1',
      );
    },
  );

  test(
    'multi-task allocation is selected-only and never creates a rule',
    () async {
      await insertSettings();
      final now = DateTime.now().toUtc();
      for (final id in const ['task-a', 'task-b']) {
        await database
            .into(database.localTasks)
            .insert(
              LocalTasksCompanion.insert(
                id: id,
                userId: 'local',
                title: 'Task $id',
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      final entry = await captureReview(
        id: 'segment-3',
        processName: 'Code.exe',
      );
      const resolution = ActivityResolution(
        status: 'confirmed',
        classification: 'direct_task_work',
        contributionType: 'active_work_seconds',
        rememberRule: true,
        taskAllocations: [
          ActivityTaskAllocation(targetTaskId: 'task-a', percentage: 40),
          ActivityTaskAllocation(targetTaskId: 'task-b', percentage: 60),
        ],
      );

      expect(activityResolutionCanRememberForFuture(resolution), isFalse);
      await repository.resolve(entry, resolution);

      final contributions = await database
          .select(database.localContributions)
          .get();
      expect(contributions, hasLength(2));
      expect(contributions.map((item) => item.targetId).toSet(), {
        'task-a',
        'task-b',
      });
      expect(await allRules(), isEmpty);

      await repository.resolve(entry, resolution);
      final repeatedContributions = await database
          .select(database.localContributions)
          .get();
      expect(
        repeatedContributions.where((item) => item.deletedAt == null),
        hasLength(2),
      );
      expect(await allRules(), isEmpty);

      final beforeSingle = (await repository.reviewEntryForSegment(
        entry.segment.id,
      ))!;
      await repository.resolve(
        beforeSingle,
        const ActivityResolution(
          status: 'confirmed',
          classification: 'direct_task_work',
          targetId: 'task-a',
          contributionType: 'active_work_seconds',
          creditedDuration: Duration(seconds: 48),
        ),
      );
      final singleContributions =
          await (database.select(database.localContributions)..where(
                (row) =>
                    row.activitySegmentId.equals(entry.segment.id) &
                    row.deletedAt.isNull(),
              ))
              .get();
      final singleAttributions =
          await (database.select(database.localAttributions)..where(
                (row) =>
                    row.activitySegmentId.equals(entry.segment.id) &
                    row.deletedAt.isNull(),
              ))
              .get();
      expect(singleContributions, hasLength(1));
      expect(singleContributions.single.targetId, 'task-a');
      expect(singleAttributions, hasLength(1));
      expect(singleAttributions.single.targetId, 'task-a');
      final afterSingle = (await repository.reviewEntryForSegment(
        entry.segment.id,
      ))!;
      expect(afterSingle.review.revision, beforeSingle.review.revision + 1);
    },
  );

  test(
    'reallocated secondary task uses fresh create identities after tombstones',
    () async {
      await insertSettings(synchronized: true);
      final now = DateTime.now().toUtc();
      for (final id in const ['task-a', 'task-b']) {
        await database
            .into(database.localTasks)
            .insert(
              LocalTasksCompanion.insert(
                id: id,
                userId: 'local',
                title: 'Task $id',
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      final entry = await captureReview(
        id: 'segment-5',
        processName: 'Code.exe',
      );
      const allocations = ActivityResolution(
        status: 'confirmed',
        classification: 'direct_task_work',
        contributionType: 'active_work_seconds',
        taskAllocations: [
          ActivityTaskAllocation(targetTaskId: 'task-a', percentage: 40),
          ActivityTaskAllocation(targetTaskId: 'task-b', percentage: 60),
        ],
      );

      await repository.resolve(entry, allocations);
      final afterMultiple = (await repository.reviewEntryForSegment(
        entry.segment.id,
      ))!;
      await repository.resolve(
        afterMultiple,
        const ActivityResolution(
          status: 'confirmed',
          classification: 'direct_task_work',
          targetId: 'task-a',
          contributionType: 'active_work_seconds',
          creditedDuration: Duration(seconds: 48),
        ),
      );

      final tombstonedAttributionIds =
          (await database.select(database.localAttributions).get())
              .where(
                (row) =>
                    row.activitySegmentId == entry.segment.id &&
                    row.targetId == 'task-b' &&
                    row.deletedAt != null,
              )
              .map((row) => row.id)
              .toSet();
      final tombstonedContributionIds =
          (await database.select(database.localContributions).get())
              .where(
                (row) =>
                    row.activitySegmentId == entry.segment.id &&
                    row.targetId == 'task-b' &&
                    row.deletedAt != null,
              )
              .map((row) => row.id)
              .toSet();
      expect(tombstonedAttributionIds, isNotEmpty);
      expect(tombstonedContributionIds, isNotEmpty);

      final afterSingle = (await repository.reviewEntryForSegment(
        entry.segment.id,
      ))!;
      await repository.resolve(afterSingle, allocations);

      final liveAttribution =
          (await database.select(database.localAttributions).get())
              .where(
                (row) =>
                    row.activitySegmentId == entry.segment.id &&
                    row.targetId == 'task-b' &&
                    row.deletedAt == null,
              )
              .single;
      final liveContribution =
          (await database.select(database.localContributions).get())
              .where(
                (row) =>
                    row.activitySegmentId == entry.segment.id &&
                    row.targetId == 'task-b' &&
                    row.deletedAt == null,
              )
              .single;
      expect(tombstonedAttributionIds, isNot(contains(liveAttribution.id)));
      expect(tombstonedContributionIds, isNot(contains(liveContribution.id)));
      expect(liveContribution.attributionId, liveAttribution.id);

      final queued = await database.select(database.localOutboxCommands).get();
      final attributionCommand = queued.singleWhere(
        (command) =>
            command.entityType == 'activity_attributions' &&
            command.entityId == liveAttribution.id,
      );
      final contributionCommand = queued.singleWhere(
        (command) =>
            command.entityType == 'activity_contributions' &&
            command.entityId == liveContribution.id,
      );
      expect(attributionCommand.commandType, 'create');
      expect(attributionCommand.baseRevision, 0);
      expect(contributionCommand.commandType, 'create');
      expect(contributionCommand.baseRevision, 0);
      expect(
        contributionCommand.deviceSequence,
        greaterThan(attributionCommand.deviceSequence),
      );
      final contributionPayload =
          jsonDecode(contributionCommand.payloadJson) as Map<String, dynamic>;
      expect(
        contributionPayload['activity_attribution_id'],
        liveAttribution.id,
      );
    },
  );

  test('multi-task selected-only explanation exists in every locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final copy = AppLocalizations(
        locale,
      ).text('activity_multi_task_selected_only');
      expect(copy, isNotEmpty, reason: locale.languageCode);
      expect(copy, isNot(contains('activity_multi_task_selected_only')));
    }
  });
}
