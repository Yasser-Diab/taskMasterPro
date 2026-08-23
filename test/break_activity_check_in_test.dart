import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/activity/data/activity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ActivityRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    repository = ActivityRepository(
      database,
      SupabaseClient('https://example.supabase.co', 'sb_publishable_test_key'),
    );
  });

  tearDown(() => database.close());

  test(
    'one no-device break creates one deterministic pending check-in',
    () async {
      final startedAt = DateTime.utc(2026, 8, 23, 8);
      final endedAt = startedAt.add(const Duration(minutes: 5));

      final first = await repository.prepareBreakActivityReviewIfNeeded(
        taskId: 'task-a',
        sessionId: 'session-a',
        startedAt: startedAt,
        endedAt: endedAt,
      );
      final retry = await repository.prepareBreakActivityReviewIfNeeded(
        taskId: 'task-a',
        sessionId: 'session-a',
        startedAt: startedAt,
        endedAt: endedAt,
      );

      expect(first, isNotNull);
      expect(retry?.segment.id, first?.segment.id);
      expect(retry?.review.id, first?.review.id);
      expect(first?.segment.sourceType, manualBreakActivitySourceType);
      expect(first?.review.reviewReason, breakActivityReviewReason);
      expect(
        await database.select(database.localActivitySegments).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.localActivityReviews).get(),
        hasLength(1),
      );
    },
  );

  test('real device use suppresses the off-device break prompt', () async {
    final startedAt = DateTime.utc(2026, 8, 23, 8);
    final endedAt = startedAt.add(const Duration(minutes: 5));
    await repository.captureRawSegment(
      startedAt: startedAt.add(const Duration(minutes: 1)),
      endedAt: startedAt.add(const Duration(minutes: 4)),
      sourceType: 'windows_foreground',
      processName: 'reader.exe',
      idleState: 'active',
    );

    final entry = await repository.prepareBreakActivityReviewIfNeeded(
      taskId: 'task-a',
      sessionId: 'session-a',
      startedAt: startedAt,
      endedAt: endedAt,
    );

    expect(entry, isNull);
  });

  test('technical idle capture still allows an off-device check-in', () async {
    final startedAt = DateTime.utc(2026, 8, 23, 8);
    final endedAt = startedAt.add(const Duration(minutes: 5));
    await repository.captureRawSegment(
      startedAt: startedAt,
      endedAt: endedAt,
      sourceType: 'windows_foreground',
      processName: 'background.exe',
      idleState: 'technical_idle',
    );

    final entry = await repository.prepareBreakActivityReviewIfNeeded(
      taskId: 'task-a',
      sessionId: 'session-a',
      startedAt: startedAt,
      endedAt: endedAt,
    );

    expect(entry, isNotNull);
  });

  test(
    'sport can be assigned to a task and synchronizes privacy-safe evidence',
    () async {
      final startedAt = DateTime.utc(2026, 8, 23, 8);
      final endedAt = startedAt.add(const Duration(minutes: 12));
      final now = DateTime.now().toUtc();
      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: 'workout-task',
              userId: 'local',
              title: 'Workout',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final entry = await repository.prepareBreakActivityReviewIfNeeded(
        taskId: 'source-task',
        sessionId: 'session-sport',
        startedAt: startedAt,
        endedAt: endedAt,
      );
      expect(entry, isNotNull);

      await repository.resolve(
        entry!,
        const ActivityResolution(
          status: 'confirmed',
          classification: 'break_activity_sport',
          contributionType: 'active_work_seconds',
          taskAllocations: [
            ActivityTaskAllocation(
              targetTaskId: 'workout-task',
              percentage: 100,
            ),
          ],
        ),
      );

      final storedSegment = await database
          .select(database.localActivitySegments)
          .getSingle();
      final metadata = jsonDecode(storedSegment.rawMetadataJson) as Map;
      expect(storedSegment.idleState, 'active');
      expect(metadata['manual_break_category'], 'break_activity_sport');
      final attribution = await database
          .select(database.localAttributions)
          .getSingle();
      expect(attribution.classification, 'break_activity_sport');
      expect(attribution.targetId, 'workout-task');
      final contribution = await database
          .select(database.localContributions)
          .getSingle();
      expect(
        contribution.creditedDurationMs,
        const Duration(minutes: 12).inMilliseconds,
      );
      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(
        commands.map((command) => command.entityType),
        containsAll(['activity_segments', 'activity_review_classifications']),
      );
    },
  );

  test(
    'unassigned sport still queues its privacy-safe parent before classification',
    () async {
      final startedAt = DateTime.utc(2026, 8, 23, 8);
      final entry = await repository.prepareBreakActivityReviewIfNeeded(
        taskId: 'source-task',
        sessionId: 'session-unassigned-sport',
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(minutes: 5)),
      );
      expect(entry, isNotNull);

      await repository.resolve(
        entry!,
        const ActivityResolution(
          status: 'confirmed',
          classification: 'break_activity_sport',
        ),
      );

      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      commands.sort(
        (left, right) => left.deviceSequence.compareTo(right.deviceSequence),
      );
      expect(commands, hasLength(2));
      expect(commands.first.entityType, 'activity_segments');
      expect(commands.last.entityType, 'activity_review_classifications');
      final segmentPayload =
          jsonDecode(commands.first.payloadJson) as Map<String, dynamic>;
      final rawMetadata = segmentPayload['raw_metadata'] as Map;
      expect(rawMetadata['manual_break_check_in'], isTrue);
      expect(rawMetadata['manual_break_category'], 'break_activity_sport');
      expect(
        (segmentPayload['data'] as Map).containsKey('approved_contribution'),
        isFalse,
      );
    },
  );

  test('server privacy guard accepts only normalized manual break fields', () {
    final migration = File(
      'supabase/migrations/20260823110000_v0035_manual_break_activity.sql',
    ).readAsStringSync();

    expect(migration, contains("new.source_type = 'manual_break'"));
    expect(migration, contains("'manual_break_check_in'"));
    expect(migration, contains("'manual_break_category'"));
    expect(migration, contains("'manual_break_label'"));
    expect(migration, contains('pg_catalog.length('));
    expect(migration, contains('new.process_name is null'));
    expect(migration, contains('new.window_title is null'));
    expect(migration, contains('new.url is null'));
  });
}
