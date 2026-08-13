import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
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

  Future<void> insertSettings({required bool detailed}) async {
    final now = DateTime.now().toUtc();
    await database
        .into(database.localAppSettings)
        .insert(
          LocalAppSettingsCompanion.insert(
            id: 'app',
            detailedActivitySyncEnabled: Value(detailed),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> insertPrivacy({
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
              }),
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test(
    'legacy detailed flag cannot queue raw Activity without privacy consent',
    () async {
      final now = DateTime.now().toUtc();
      await insertSettings(detailed: true);

      await repository.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 1)),
        sourceType: 'windows_foreground',
        processName: 'code.exe',
        windowTitle: 'Private workspace',
      );

      expect(
        await database.select(database.localOutboxCommands).get(),
        isEmpty,
      );
    },
  );

  test(
    'explicit consent uploads one finalized detailed segment and review',
    () async {
      final now = DateTime.now().toUtc();
      await insertSettings(detailed: true);
      await insertPrivacy(storage: 'synchronized', detailedOptIn: true);

      final id = await repository.captureRawSegment(
        startedAt: now,
        endedAt: now.add(const Duration(seconds: 15)),
        sourceType: 'windows_foreground',
        processName: 'code.exe',
        windowTitle: 'Visible after consent',
        isFinalized: false,
      );
      expect(
        await database.select(database.localOutboxCommands).get(),
        isEmpty,
      );

      await repository.captureRawSegment(
        segmentId: id,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 2)),
        sourceType: 'windows_foreground',
        processName: 'code.exe',
        windowTitle: 'Visible after consent',
        createReview: false,
        isFinalized: true,
      );

      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(
        commands.map((command) => command.entityType),
        containsAll(['activity_segments', 'activity_review_queue']),
      );
      final segment = commands.firstWhere(
        (command) => command.entityType == 'activity_segments',
      );
      final payload = jsonDecode(segment.payloadJson) as Map;
      expect(payload['window_title'], 'Visible after consent');
      expect((payload['data'] as Map)['capture_state'], 'finalized');
    },
  );

  test('duplicate immutable capture is idempotent', () async {
    final now = DateTime.now().toUtc();
    const segmentId = 'android-history-com.example-1000-2000';

    final results = await Future.wait([
      repository.captureRawSegment(
        segmentId: segmentId,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 1)),
        sourceType: 'android_usage_history',
        processName: 'com.example',
      ),
      repository.captureRawSegment(
        segmentId: segmentId,
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 1)),
        sourceType: 'android_usage_history',
        processName: 'com.example',
      ),
    ]);

    expect(results, everyElement(segmentId));
    final segments = await database
        .select(database.localActivitySegments)
        .get();
    expect(segments, hasLength(1));
    expect(segments.single.id, segmentId);
    final reviews = await database.select(database.localActivityReviews).get();
    expect(reviews, hasLength(1));
  });

  test('segment identity reuse with different data is rejected', () async {
    final now = DateTime.now().toUtc();
    await repository.captureRawSegment(
      segmentId: 'immutable-segment',
      startedAt: now,
      endedAt: now.add(const Duration(minutes: 1)),
      sourceType: 'android_usage_history',
      processName: 'com.example.one',
    );

    await expectLater(
      repository.captureRawSegment(
        segmentId: 'immutable-segment',
        startedAt: now,
        endedAt: now.add(const Duration(minutes: 1)),
        sourceType: 'android_usage_history',
        processName: 'com.example.two',
      ),
      throwsStateError,
    );
    expect(
      await database.select(database.localActivitySegments).get(),
      hasLength(1),
    );
  });
}
