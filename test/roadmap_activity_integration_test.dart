import 'package:drift/native.dart';
import 'package:drift/drift.dart';
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

  tearDown(() => database.close());

  test('task relationships remain visible from the linked roadmap', () async {
    final roadmapId = await roadmaps.createRoadmap(
      RoadmapDraft(
        title: 'Ship TaskMaster Pro',
        targetDate: DateTime(2026, 10, 1),
      ),
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

  test('starting another task preserves the context switch', () async {
    final firstId = await tasks.createTask(
      TaskDraft(title: 'Prepare invoice', scheduledDate: DateTime(2026, 7, 25)),
    );
    final secondId = await tasks.createTask(
      TaskDraft(title: 'CAD work', scheduledDate: DateTime(2026, 7, 25)),
    );
    final first = (await tasks.getTask(firstId))!;
    final second = (await tasks.getTask(secondId))!;

    await tasks.start(first);
    await tasks.start(second);

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

  test(
    'device-only activity creates no activity synchronization command',
    () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.localAppSettings)
          .insert(
            LocalAppSettingsCompanion.insert(
              id: 'app',
              activitySyncEnabled: const Value(false),
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

      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(
        commands.where(
          (command) =>
              command.entityType.startsWith('activity_') ||
              command.entityType == 'contribution_roadmap_effects',
        ),
        isEmpty,
      );
      expect(
        await database.select(database.localActivitySegments).get(),
        hasLength(1),
      );
    },
  );
}
