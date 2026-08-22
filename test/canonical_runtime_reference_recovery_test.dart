import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/sync/sync_service.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';

const _userId = '07704e12-d1c9-4c03-8fb5-04b1b6efe904';
const _taskId = '12133bd5-0190-4fed-9223-c8083e5323a7';
const _sessionId = 'e7b414bc-bfca-47cf-bf45-c85b12d0009d';
const _commandId = '90af2e5d-5e2d-4fd6-bf23-639c57ef6970';
final _now = DateTime.utc(2026, 8, 20, 11);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'early canonical runtime restores at the same revision after references arrive',
    () async {
      final fixture = await _RuntimeRecoveryFixture.create();
      addTearDown(fixture.dispose);
      final canonical = fixture.canonicalRuntime();

      await fixture.receiveAndSanitize(canonical);
      await fixture.addExactReferences();
      await fixture.service.applyRemoteRuntimeForTesting(canonical);

      final restored = await fixture.repository.getRuntime();
      expect(restored, isNotNull);
      expect(restored!.state, 'running');
      expect(restored.activeTaskId, _taskId);
      expect(restored.sessionId, _sessionId);
      expect(restored.revision, 45);
      expect(restored.lastCommandId, _commandId);
      expect(
        jsonDecode(restored.dataJson),
        isNot(contains(localRuntimeReferenceRepairMarkerKey)),
      );

      await fixture.service.applyRemoteRuntimeForTesting({
        ...canonical,
        'state': 'paused',
        'active_segment_started_at': null,
      });
      final stillValid = await fixture.repository.getRuntime();
      expect(stillValid!.state, 'running');
    },
  );

  test('v0.0.39 markerless sanitized runtime restores exactly once', () async {
    final fixture = await _RuntimeRecoveryFixture.create();
    addTearDown(fixture.dispose);
    final canonical = fixture.canonicalRuntime();

    await fixture.receiveAndSanitize(canonical);
    await (fixture.database.update(
      fixture.database.localRuntimeStates,
    )).write(const LocalRuntimeStatesCompanion(dataJson: drift.Value('{}')));
    await fixture.addExactReferences();
    await fixture.service.applyRemoteRuntimeForTesting(canonical);

    final restored = await fixture.repository.getRuntime();
    expect(restored, isNotNull);
    expect(restored!.state, 'running');
    expect(restored.revision, 45);
    expect(restored.lastCommandId, _commandId);
  });

  test('stale canonical revision cannot restore a sanitized runtime', () async {
    final fixture = await _RuntimeRecoveryFixture.create();
    addTearDown(fixture.dispose);
    final canonical = fixture.canonicalRuntime();

    await fixture.receiveAndSanitize(canonical);
    await fixture.addExactReferences();
    await fixture.service.applyRemoteRuntimeForTesting({
      ...canonical,
      'revision': 44,
    });

    expect((await fixture.storedRuntime()).state, 'idle');
    expect(await fixture.repository.getRuntime(), isNull);
  });

  test('foreign session cannot restore a sanitized runtime', () async {
    final fixture = await _RuntimeRecoveryFixture.create();
    addTearDown(fixture.dispose);
    final canonical = fixture.canonicalRuntime();

    await fixture.receiveAndSanitize(canonical);
    await fixture.addTask();
    await fixture.addSession(userId: 'another-account');
    await fixture.service.applyRemoteRuntimeForTesting(canonical);

    expect((await fixture.storedRuntime()).state, 'idle');
    expect(await fixture.repository.getRuntime(), isNull);
  });

  test('pending execution command blocks same-revision restoration', () async {
    final fixture = await _RuntimeRecoveryFixture.create();
    addTearDown(fixture.dispose);
    final canonical = fixture.canonicalRuntime();

    await fixture.receiveAndSanitize(canonical);
    await fixture.addExactReferences();
    await fixture.addPendingRuntimeCommand();
    await fixture.service.applyRemoteRuntimeForTesting(canonical);

    expect((await fixture.storedRuntime()).state, 'idle');
    expect(await fixture.repository.getRuntime(), isNull);
  });

  test(
    'repair guard requires exact marker, references, revision and command',
    () {
      final marker = jsonEncode({
        localRuntimeReferenceRepairMarkerKey: {
          'task_id': _taskId,
          'session_id': _sessionId,
          'state': 'running',
          'revision': 45,
          'command_id': _commandId,
        },
      });
      bool allowed({
        String localState = 'idle',
        String? localTaskId,
        int incomingRevision = 45,
        String incomingCommandId = _commandId,
        bool pending = false,
        bool taskExists = true,
        bool sessionExists = true,
      }) => shouldRestoreSanitizedCanonicalRuntime(
        localState: localState,
        localTaskId: localTaskId,
        localSessionId: null,
        localDataJson: marker,
        localRevision: 45,
        localCommandId: _commandId,
        incomingState: 'running',
        incomingTaskId: _taskId,
        incomingSessionId: _sessionId,
        incomingRevision: incomingRevision,
        incomingCommandId: incomingCommandId,
        hasPendingRuntimeCommand: pending,
        exactTaskReferenceExists: taskExists,
        exactSessionReferenceExists: sessionExists,
      );

      expect(allowed(), isTrue);
      expect(allowed(localState: 'running', localTaskId: _taskId), isFalse);
      expect(allowed(incomingRevision: 44), isFalse);
      expect(allowed(incomingCommandId: 'different-command'), isFalse);
      expect(allowed(pending: true), isFalse);
      expect(allowed(taskExists: false), isFalse);
      expect(allowed(sessionExists: false), isFalse);
    },
  );
}

class _RuntimeRecoveryFixture {
  _RuntimeRecoveryFixture({
    required this.database,
    required this.client,
    required this.repository,
    required this.service,
  });

  final AppDatabase database;
  final SupabaseClient client;
  final TaskRepository repository;
  final SyncService service;

  static Future<_RuntimeRecoveryFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    final client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test_key',
    );
    final user = User(
      id: _userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: 'runtime@example.test',
      createdAt: _now.toIso8601String(),
    );
    final session = Session(
      accessToken: 'not-a-jwt',
      refreshToken: 'test-refresh',
      tokenType: 'bearer',
      expiresIn: 86400,
      user: user,
    );
    await client.auth.recoverSession(jsonEncode(session.toJson()));
    final repository = TaskRepository(database, client, clock: () => _now);
    final service = SyncService(database: database, client: client);
    return _RuntimeRecoveryFixture(
      database: database,
      client: client,
      repository: repository,
      service: service,
    );
  }

  Map<String, dynamic> canonicalRuntime() => <String, dynamic>{
    'user_id': _userId,
    'active_task_occurrence_id': _taskId,
    'active_session_id': _sessionId,
    'state': 'running',
    'active_segment_started_at': _now.toIso8601String(),
    'accumulated_active_ms': 600000,
    'accumulated_paused_ms': 0,
    'data': const {'origin': 'phone'},
    'revision': 45,
    'updated_at': _now.toIso8601String(),
    'last_command_id': _commandId,
  };

  Future<void> receiveAndSanitize(Map<String, dynamic> canonical) async {
    await service.applyRemoteRuntimeForTesting(canonical);
    expect((await storedRuntime()).state, 'running');
    expect(await repository.getRuntime(), isNull);
    final sanitized = await storedRuntime();
    expect(sanitized.state, 'idle');
    expect(sanitized.activeTaskId, isNull);
    expect(sanitized.sessionId, isNull);
    expect(sanitized.revision, 45);
    expect(sanitized.lastCommandId, _commandId);
    final data = jsonDecode(sanitized.dataJson) as Map<String, dynamic>;
    expect(data[localRuntimeReferenceRepairMarkerKey], isA<Map>());
  }

  Future<void> addExactReferences() async {
    await addTask();
    await addSession();
  }

  Future<void> addTask() => database
      .into(database.localTasks)
      .insert(
        LocalTasksCompanion.insert(
          id: _taskId,
          userId: _userId,
          title: 'Phone focus',
          status: const drift.Value('in_progress'),
          createdAt: _now,
          updatedAt: _now,
        ),
      );

  Future<void> addSession({String userId = _userId}) => database
      .into(database.localEntityRecords)
      .insert(
        LocalEntityRecordsCompanion.insert(
          id: _sessionId,
          userId: userId,
          entityType: 'execution_sessions',
          parentId: const drift.Value(_taskId),
          title: const drift.Value('Phone focus session'),
          status: const drift.Value('running'),
          createdAt: _now,
          updatedAt: _now,
        ),
      );

  Future<void> addPendingRuntimeCommand() => database
      .into(database.localOutboxCommands)
      .insert(
        LocalOutboxCommandsCompanion.insert(
          commandId: 'pending-runtime-command',
          userId: _userId,
          deviceId: 'windows-device',
          deviceSequence: 46,
          entityType: 'execution_runtime',
          entityId: _sessionId,
          commandType: 'pause',
          baseRevision: 45,
          payloadJson: '{}',
          clientTimestamp: _now,
          createdAt: _now,
        ),
      );

  Future<LocalRuntime> storedRuntime() =>
      database.select(database.localRuntimeStates).getSingle();

  Future<void> dispose() async {
    await service.dispose();
    await database.close();
  }
}
