import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/activity/data/activity_repository.dart';
import 'package:taskmaster_pro/features/roadmaps/data/roadmap_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late SupabaseClient client;
  late TaskRepository tasks;
  late RoadmapRepository roadmaps;
  late ActivityRepository activity;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
    );
    tasks = TaskRepository(database, client);
    roadmaps = RoadmapRepository(database, client);
    activity = ActivityRepository(database, client);
  });

  Future<void> setCanonicalActivityPrivacy({
    required String storage,
    required bool detailedOptIn,
  }) async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.localEntityRecords)
        .insert(
          LocalEntityRecordsCompanion.insert(
            id: 'privacy-local',
            userId: 'local',
            entityType: 'privacy_settings',
            title: const Value('Activity privacy'),
            status: Value(storage),
            dataJson: Value(
              jsonEncode({
                'id': 'privacy-local',
                'user_id': 'local',
                'activity_storage': storage,
                'data': {'detailed_activity_sync_opt_in': detailedOptIn},
                'revision': 1,
              }),
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  tearDown(() => database.close());

  test('task relationships remain visible from the linked roadmap', () async {
    final roadmapId = await roadmaps.createRoadmap(
      RoadmapDraft(title: 'Ship DayVector', targetDate: DateTime(2026, 10, 1)),
    );
    final phaseId = await roadmaps.addPhase(
      roadmapId: roadmapId,
      title: 'Core architecture',
      position: 0,
    );
    final taskId = await tasks.createTask(
      TaskDraft(
        title: 'Build synchronization engine',
        roadmapId: roadmapId,
        roadmapPhaseId: phaseId,
        scheduledDate: DateTime(2026, 7, 25),
      ),
    );

    final linked = await roadmaps.watchLinkedTasks(roadmapId).first;
    expect(linked.single.id, taskId);
    expect(linked.single.roadmapPhaseId, phaseId);

    final ruleRecords = await roadmaps.entities.list(
      entityType: 'roadmap_progress_rules',
      parentId: roadmapId,
    );
    expect(ruleRecords, hasLength(4));
  });

  test('roadmap projection refresh is local-only by default', () async {
    final roadmapId = await roadmaps.createRoadmap(
      const RoadmapDraft(title: 'Canonical roadmap'),
    );
    final before = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.id.equals(roadmapId))).getSingle();
    final commandsBefore = await database
        .select(database.localOutboxCommands)
        .get();

    await roadmaps.recalculateProgress(roadmapId);

    final after = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.id.equals(roadmapId))).getSingle();
    final commandsAfter = await database
        .select(database.localOutboxCommands)
        .get();
    expect(after.revision, before.revision);
    expect(after.lastCommandId, before.lastCommandId);
    expect(after.updatedByDeviceId, before.updatedByDeviceId);
    expect(commandsAfter, hasLength(commandsBefore.length));
  });

  test(
    'nine-phase programming plan persists complete connected content once',
    () async {
      final roadmapId = await roadmaps.createRoadmap(
        RoadmapDraft(
          title: 'Programming from zero to hero',
          targetDate: DateTime(2027, 2, 1),
        ),
      );
      for (var index = 0; index < 9; index++) {
        await roadmaps.addPhase(
          roadmapId: roadmapId,
          title: 'Learning phase ${index + 1}',
          position: index.toDouble(),
        );
      }

      final first = await roadmaps.populateProgrammingLearningPlan(roadmapId);
      final second = await roadmaps.populateProgrammingLearningPlan(roadmapId);
      final phases = await roadmaps.entities.list(
        entityType: 'roadmap_phases',
        parentId: roadmapId,
      );
      final milestones = await roadmaps.entities.list(
        entityType: 'roadmap_milestones',
        parentId: roadmapId,
      );
      final checkpoints = await roadmaps.entities.list(
        entityType: 'roadmap_checkpoints',
        parentId: roadmapId,
      );
      final linkedTasks = await roadmaps.watchLinkedTasks(roadmapId).first;
      final links = await roadmaps.entities.list(
        entityType: 'roadmap_task_links',
        parentId: roadmapId,
      );
      final resources = await roadmaps.entities.list(
        entityType: 'task_resources',
      );
      final checklist = await roadmaps.entities.list(
        entityType: 'checklist_items',
      );

      expect(first.phases, 9);
      expect(first.milestones, 10);
      expect(first.checkpoints, 10);
      expect(first.tasks, 10);
      expect(second.milestones, 0);
      expect(second.checkpoints, 0);
      expect(second.tasks, 0);
      expect(phases, hasLength(9));
      expect(milestones, hasLength(10));
      expect(checkpoints, hasLength(10));
      expect(linkedTasks, hasLength(10));
      expect(links, hasLength(10));
      expect(resources, hasLength(9));
      expect(checklist, hasLength(27));
      expect(
        linkedTasks.where((task) => task.roadmapPhaseId == null),
        hasLength(1),
      );
      expect(
        linkedTasks.where((task) => task.status == 'completed'),
        hasLength(1),
      );
      expect(
        linkedTasks.where((task) => task.status == 'paused'),
        hasLength(1),
      );
      expect(
        checkpoints.where((item) => item.status == 'completed'),
        hasLength(1),
      );
    },
  );

  test('approved activity credits a task and permitted roadmap once', () async {
    final roadmapId = await roadmaps.createRoadmap(
      const RoadmapDraft(title: 'Reach German B1'),
    );
    final taskId = await tasks.createTask(
      TaskDraft(
        title: 'German daily practice',
        roadmapId: roadmapId,
        scheduledDate: DateTime(2026, 7, 25),
      ),
    );
    final startedAt = DateTime.utc(2026, 7, 25, 10);
    await activity.captureRawSegment(
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 5)),
      sourceType: 'test_application',
      processName: 'language-app',
    );
    final entry = (await activity.watchReviewQueue().first).single;

    await activity.resolve(
      entry,
      ActivityResolution(
        status: 'confirmed',
        classification: 'learning',
        targetType: 'task_occurrence',
        targetId: taskId,
        contributionType: 'practice_seconds',
        creditedDuration: const Duration(minutes: 4, seconds: 12),
      ),
    );

    final segments = await database
        .select(database.localActivitySegments)
        .get();
    final contributions = await database
        .select(database.localContributions)
        .get();
    final roadmap = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.id.equals(roadmapId))).getSingle();
    final effects = await roadmaps.entities.list(
      entityType: 'contribution_roadmap_effects',
      parentId: roadmapId,
    );

    expect(segments, hasLength(1));
    expect(contributions, hasLength(1));
    expect(contributions.single.physicalDurationMs, 300000);
    expect(contributions.single.creditedDurationMs, 252000);
    expect(roadmap.completedEffortMs, 252000);
    expect(effects, hasLength(1));
  });

  test('starting another task requires an explicit context switch', () async {
    final firstId = await tasks.createTask(
      TaskDraft(title: 'Prepare invoice', scheduledDate: DateTime(2026, 7, 25)),
    );
    final secondId = await tasks.createTask(
      TaskDraft(title: 'CAD work', scheduledDate: DateTime(2026, 7, 25)),
    );
    final first = (await tasks.getTask(firstId))!;
    final second = (await tasks.getTask(secondId))!;

    await tasks.start(first);
    final startResult = await tasks.start(second);

    final beforeSwitchFirst = (await tasks.getTask(firstId))!;
    final beforeSwitchSecond = (await tasks.getTask(secondId))!;
    final beforeSwitchRuntime = await database
        .select(database.localRuntimeStates)
        .getSingle();

    expect(startResult.requiresSwitch, isTrue);
    expect(startResult.activeTaskId, firstId);
    expect(beforeSwitchFirst.status, 'in_progress');
    expect(beforeSwitchSecond.status, isNot('in_progress'));
    expect(beforeSwitchRuntime.activeTaskId, firstId);

    await tasks.switchActiveTask(
      second,
      action: ActiveTaskSwitchAction.pauseCurrent,
    );

    final firstAfter = (await tasks.getTask(firstId))!;
    final secondAfter = (await tasks.getTask(secondId))!;
    final runtime = await database
        .select(database.localRuntimeStates)
        .getSingle();
    final interruptions = await tasks.entities.list(
      entityType: 'interruptions',
      parentId: firstId,
    );

    expect(firstAfter.status, 'paused');
    expect(secondAfter.status, 'in_progress');
    expect(runtime.activeTaskId, secondId);
    expect(interruptions, hasLength(1));
    expect(interruptions.single.secondaryParentId, secondId);
  });

  test(
    'remembered application rules credit later activity automatically',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              automaticTrustedRules: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final taskId = await tasks.createTask(
        const TaskDraft(title: 'German practice'),
      );
      final firstStart = DateTime.utc(2026, 7, 25, 12);
      await activity.captureRawSegment(
        startedAt: firstStart,
        endedAt: firstStart.add(const Duration(minutes: 4)),
        sourceType: 'windows_foreground',
        processName: 'duolingo.exe',
      );
      final firstReview = (await activity.watchReviewQueue().first).single;
      await activity.resolve(
        firstReview,
        ActivityResolution(
          status: 'confirmed',
          classification: 'learning',
          targetType: 'task_occurrence',
          targetId: taskId,
          contributionType: 'practice_seconds',
          rememberRule: true,
        ),
      );

      final secondStart = firstStart.add(const Duration(hours: 1));
      await activity.captureRawSegment(
        startedAt: secondStart,
        endedAt: secondStart.add(const Duration(minutes: 3)),
        sourceType: 'windows_foreground',
        processName: 'duolingo.exe',
      );

      final reviews = await activity.watchReviewQueue().first;
      final contributions = await database
          .select(database.localContributions)
          .get();
      final rules = await roadmaps.entities.list(
        entityType: 'application_rules',
        parentId: taskId,
      );
      expect(reviews, isEmpty);
      expect(rules, hasLength(1));
      expect(contributions, hasLength(2));
      expect(contributions.last.isAutomatic, isTrue);
    },
  );

  test('unapproved device Activity stays local by default', () async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.localAppSettings)
        .insert(
          LocalAppSettingsCompanion.insert(
            id: 'app',
            activitySyncEnabled: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await activity.captureRawSegment(
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 2)),
      sourceType: 'android_usage',
      processName: 'com.example.local',
    );

    final commands = await database.select(database.localOutboxCommands).get();
    expect(commands, isEmpty);
    expect(
      await database.select(database.localActivitySegments).get(),
      hasLength(1),
    );
  });

  test('an active normalized segment is extended with its stable ID', () async {
    final now = DateTime.now().toUtc();
    await setCanonicalActivityPrivacy(
      storage: 'synchronized',
      detailedOptIn: true,
    );
    await database
        .into(database.localAppSettings)
        .insert(
          LocalAppSettingsCompanion.insert(
            id: 'app',
            activitySyncEnabled: const Value(true),
            detailedActivitySyncEnabled: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final segmentId = await activity.captureRawSegment(
      startedAt: now,
      endedAt: now.add(const Duration(seconds: 15)),
      sourceType: 'windows_foreground',
      processName: 'chrome.exe',
    );
    await activity.captureRawSegment(
      segmentId: segmentId,
      startedAt: now,
      endedAt: now.add(const Duration(seconds: 45)),
      sourceType: 'windows_foreground',
      processName: 'chrome.exe',
      createReview: false,
    );

    final segments = await database
        .select(database.localActivitySegments)
        .get();
    final commands = await database.select(database.localOutboxCommands).get();
    final segmentCommands = commands
        .where((command) => command.entityType == 'activity_segments')
        .toList();
    expect(segments, hasLength(1));
    expect(segments.single.id, segmentId);
    expect(
      segmentCommands.map((command) => command.entityId),
      everyElement(segmentId),
    );
    expect(segmentCommands, hasLength(1));
    expect(segmentCommands.single.commandType, 'create');
  });

  test(
    'normalized Activity and contribution sync exclude private raw details',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              activitySyncEnabled: const Value(true),
              detailedActivitySyncEnabled: const Value(false),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final taskId = await tasks.createTask(
        const TaskDraft(title: 'Privacy-safe contribution'),
      );
      await activity.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 3)),
        sourceType: 'windows_foreground',
        processName: r'C:\Private\Project\code.exe',
        windowTitle: 'Secret client project',
      );
      final review = (await activity.watchReviewQueue().first).single;
      await activity.resolve(
        review,
        ActivityResolution(
          status: 'confirmed',
          classification: 'direct_task_work',
          targetType: 'task_occurrence',
          targetId: taskId,
          contributionType: 'active_work_seconds',
        ),
      );

      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      final activityCommands = commands.where(
        (command) => command.entityType.startsWith('activity_'),
      );
      expect(
        activityCommands.map((command) => command.entityType),
        containsAll(['activity_segments', 'activity_review_classifications']),
      );
      final segmentPayload =
          jsonDecode(
                activityCommands
                    .firstWhere(
                      (command) => command.entityType == 'activity_segments',
                    )
                    .payloadJson,
              )
              as Map;
      expect(segmentPayload['window_title'], isNull);
      expect(segmentPayload['url'], isNull);
      expect(segmentPayload['process_name'], isNull);
      expect(
        (segmentPayload['raw_metadata'] as Map)['raw_samples_included'],
        isFalse,
      );
      final classificationPayload =
          jsonDecode(
                activityCommands
                    .firstWhere(
                      (command) =>
                          command.entityType ==
                          'activity_review_classifications',
                    )
                    .payloadJson,
              )
              as Map;
      final data = classificationPayload['contribution_data'] as Map;
      expect(data['privacy_safe_source_label'], 'Visual Studio Code');
      expect(data['raw_details_included'], isFalse);
    },
  );

  test('sensitive normalized fields require explicit opt-in', () async {
    final now = DateTime.now().toUtc();
    await setCanonicalActivityPrivacy(
      storage: 'synchronized',
      detailedOptIn: true,
    );
    await database
        .into(database.localAppSettings)
        .insert(
          LocalAppSettingsCompanion.insert(
            id: 'app',
            detailedActivitySyncEnabled: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await activity.captureRawSegment(
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 1)),
      sourceType: 'windows_foreground',
      processName: 'code.exe',
      windowTitle: 'Visible only with explicit opt-in',
    );
    final commands = await database.select(database.localOutboxCommands).get();
    expect(
      commands.map((command) => command.entityType),
      containsAll(['activity_segments', 'activity_review_queue']),
    );
    final segmentPayload =
        jsonDecode(
              commands
                  .firstWhere(
                    (command) => command.entityType == 'activity_segments',
                  )
                  .payloadJson,
            )
            as Map;
    expect(segmentPayload['window_title'], 'Visible only with explicit opt-in');
  });

  test(
    'a stale detailed preference cannot bypass local-only privacy',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              detailedActivitySyncEnabled: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await activity.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 1)),
        sourceType: 'windows_foreground',
        processName: 'code.exe',
        windowTitle: 'Must remain local',
      );

      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(commands, isEmpty);
    },
  );

  test(
    'detailed Activity waits for a finalized segment before one upload',
    () async {
      final now = DateTime.now().toUtc();
      await setCanonicalActivityPrivacy(
        storage: 'synchronized',
        detailedOptIn: true,
      );
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              detailedActivitySyncEnabled: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final segmentId = await activity.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(seconds: 15)),
        sourceType: 'windows_foreground',
        processName: 'code.exe',
        isFinalized: false,
      );
      expect(
        await database.select(database.localOutboxCommands).get(),
        isEmpty,
      );

      await activity.captureRawSegment(
        segmentId: segmentId,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 2)),
        sourceType: 'windows_foreground',
        processName: 'code.exe',
        isFinalized: true,
        createReview: false,
      );
      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      final segmentCommands = commands
          .where((command) => command.entityType == 'activity_segments')
          .toList();
      expect(segmentCommands, hasLength(1));
      expect(segmentCommands.single.commandType, 'create');
      final payload = jsonDecode(segmentCommands.single.payloadJson) as Map;
      expect((payload['data'] as Map)['capture_state'], 'finalized');
    },
  );

  test('retention removes raw details but preserves contributions', () async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.localAppSettings)
        .insert(
          LocalAppSettingsCompanion.insert(
            id: 'app',
            localActivityRetentionDays: const Value(7),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final taskId = await tasks.createTask(
      const TaskDraft(title: 'Retained task total'),
    );
    final oldStart = now.subtract(const Duration(days: 10));
    await activity.captureRawSegment(
      startedAt: oldStart,
      endedAt: oldStart.add(const Duration(minutes: 5)),
      sourceType: 'windows_foreground',
      processName: 'code.exe',
    );
    final review = (await activity.watchReviewQueue().first).single;
    await activity.resolve(
      review,
      ActivityResolution(
        status: 'confirmed',
        classification: 'direct_task_work',
        targetType: 'task_occurrence',
        targetId: taskId,
        contributionType: 'active_work_seconds',
      ),
    );

    expect(await activity.purgeExpiredLocalActivity(), 1);
    expect(
      await database.select(database.localActivitySegments).get(),
      isEmpty,
    );
    expect(
      await database.select(database.localContributions).get(),
      hasLength(1),
    );
  });

  test(
    'possible system Activity remains local until the user approves it',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await activity.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(seconds: 20)),
        sourceType: 'windows_foreground',
        processName: 'SearchHost.exe',
      );
      final attribution = await database
          .select(database.localAttributions)
          .getSingle();
      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(attribution.classification, 'possible_system_activity');
      expect(commands, isEmpty);
    },
  );

  test(
    'user-confirmed system rule hides later matching observations',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await activity.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(seconds: 20)),
        sourceType: 'windows_foreground',
        processName: 'SearchHost.exe',
      );
      final first = (await activity.watchReviewQueue().first).single;
      await activity.resolve(
        first,
        const ActivityResolution(
          status: 'ignored',
          classification: 'system_activity',
          rememberRule: true,
        ),
      );
      final secondStart = now.add(const Duration(minutes: 1));
      await activity.captureRawSegment(
        startedAt: secondStart,
        endedAt: secondStart.add(const Duration(seconds: 15)),
        sourceType: 'windows_foreground',
        processName: 'SearchHost.exe',
      );

      expect(await activity.watchReviewQueue().first, isEmpty);
      final attributions = await database
          .select(database.localAttributions)
          .get();
      expect(
        attributions.where((item) => item.classification == 'system_activity'),
        hasLength(2),
      );
      final activityCommands =
          (await database.select(database.localOutboxCommands).get()).where(
            (command) => command.entityType.startsWith('activity_'),
          );
      expect(activityCommands, isEmpty);
    },
  );

  test(
    'supporting-work decisions can be remembered for future activity',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await activity.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(seconds: 20)),
        sourceType: 'windows_foreground',
        processName: 'ChatGPT.exe',
      );
      final first = (await activity.watchReviewQueue().first).single;
      await activity.resolve(
        first,
        const ActivityResolution(
          status: 'confirmed',
          classification: 'supporting_work',
          rememberRule: true,
        ),
      );

      final nextStart = now.add(const Duration(minutes: 1));
      await activity.captureRawSegment(
        startedAt: nextStart,
        endedAt: nextStart.add(const Duration(seconds: 15)),
        sourceType: 'windows_foreground',
        processName: 'ChatGPT.exe',
      );

      expect(await activity.watchReviewQueue().first, isEmpty);
      final rules =
          await (database.select(database.localEntityRecords)..where(
                (row) =>
                    row.entityType.equals('application_rules') &
                    row.deletedAt.isNull(),
              ))
              .get();
      expect(
        rules.where((rule) {
          final decoded = jsonDecode(rule.dataJson);
          final data = decoded is Map
              ? Map<String, Object?>.from(decoded)
              : const <String, Object?>{};
          return data['classification'] == 'supporting_work' &&
              data['scope_type'] == 'user';
        }),
        hasLength(1),
      );
    },
  );

  test(
    'interactive terminal names are not auto-classified as system',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await activity.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 2)),
        sourceType: 'windows_foreground',
        processName: 'powershell.exe',
        windowTitle: 'PowerShell',
      );
      expect(await database.select(database.localAttributions).get(), isEmpty);
      expect(await activity.watchReviewQueue().first, hasLength(1));
    },
  );

  test('System-labelled contributions do not inflate roadmap effort', () async {
    final now = DateTime.now().toUtc();
    final roadmapId = await roadmaps.createRoadmap(
      const RoadmapDraft(
        title: 'System exclusion',
        requiredEffort: Duration(hours: 1),
      ),
    );
    final taskId = await tasks.createTask(
      TaskDraft(title: 'Real work', roadmapId: roadmapId),
    );
    final task = await (database.select(
      database.localTasks,
    )..where((row) => row.id.equals(taskId))).getSingle();
    final segment = LocalActivitySegment(
      id: 'legacy-system-segment',
      userId: task.userId,
      deviceId: 'windows',
      deviceEventId: 'legacy-system-segment',
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 10)),
      sourceType: 'windows_foreground',
      processName: 'SearchHost.exe',
      rawMetadataJson: '{}',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    final attribution = LocalAttribution(
      id: 'legacy-system-attribution',
      userId: task.userId,
      activitySegmentId: segment.id,
      targetType: 'unassigned_activity',
      classification: 'system_activity',
      confidence: 1,
      attributionStatus: 'confirmed',
      confirmedByUser: true,
      revision: 2,
      createdAt: now,
      updatedAt: now,
    );
    await database.into(database.localActivitySegments).insert(segment);
    await database.into(database.localAttributions).insert(attribution);
    await database
        .into(database.localContributions)
        .insert(
          LocalContribution(
            id: 'legacy-system-contribution',
            userId: task.userId,
            activitySegmentId: segment.id,
            attributionId: attribution.id,
            targetType: 'task_occurrence',
            targetId: taskId,
            contributionType: 'active_work_seconds',
            physicalDurationMs: const Duration(minutes: 10).inMilliseconds,
            creditedDurationMs: const Duration(minutes: 10).inMilliseconds,
            isUnscheduled: true,
            isCrossTask: true,
            isIdleDerived: false,
            isAutomatic: false,
            revision: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await roadmaps.recalculateProgress(roadmapId, synchronize: false);

    final roadmap = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.id.equals(roadmapId))).getSingle();
    expect(roadmap.completedEffortMs, 0);
  });
}
