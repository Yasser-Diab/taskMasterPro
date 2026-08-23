import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/sync/sync_service.dart';

const _userId = '07704e12-d1c9-4c03-8fb5-04b1b6efe904';
const _deviceId = '28b905c5-19c5-4d13-bd35-d19c381db41c';
const _taskId = 'fe0b0f5a-b215-5460-87db-be8670678f7c';
const _sessionId = '58c96eb0-19e3-4d74-8f48-d2a18fdd0d84';
const _createId = '5952468d-2518-40ed-9dba-22335510f08d';
const _runtimeId = 'ed8523f5-2518-40ed-9dba-22335510f08d';
final _now = DateTime.utc(2026, 8, 20, 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'taskmaster.device_sequence.$_userId': 2,
    });
  });

  test('restart repair queues one deterministic orphan cleanup', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final service = SyncService(
      database: database,
      client: SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
      ),
    );
    addTearDown(() async {
      await service.dispose();
      await database.close();
    });

    await database
        .into(database.localEntityRecords)
        .insert(
          LocalEntityRecordsCompanion.insert(
            id: _sessionId,
            userId: _userId,
            entityType: 'execution_sessions',
            parentId: const drift.Value(_taskId),
            title: const drift.Value('Rejected start session'),
            status: const drift.Value('running'),
            dataJson: drift.Value(
              jsonEncode({
                'accumulated_active_ms': 0,
                'accumulated_paused_ms': 0,
                'accumulated_idle_ms': 0,
              }),
            ),
            revision: const drift.Value(2),
            createdAt: _now,
            updatedAt: _now,
            createdByDeviceId: const drift.Value(_deviceId),
            lastCommandId: const drift.Value(_runtimeId),
          ),
        );
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: _createId,
            userId: _userId,
            deviceId: _deviceId,
            deviceSequence: 1,
            entityType: 'execution_sessions',
            entityId: _sessionId,
            commandType: 'create',
            baseRevision: 0,
            payloadJson: jsonEncode({'task_occurrence_id': _taskId}),
            clientTimestamp: _now,
            createdAt: _now,
            status: const drift.Value('accepted'),
          ),
        );
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: _runtimeId,
            userId: _userId,
            deviceId: _deviceId,
            deviceSequence: 2,
            entityType: 'execution_runtime',
            entityId: _sessionId,
            commandType: 'start',
            baseRevision: 45,
            payloadJson: jsonEncode({
              'action': 'start',
              'task_occurrence_id': _taskId,
            }),
            clientTimestamp: _now,
            createdAt: _now,
            status: const drift.Value('superseded'),
          ),
        );

    await service.repairSupersededStartCleanupCommandsForTesting(_userId);
    await service.repairSupersededStartCleanupCommandsForTesting(_userId);

    final cleanup =
        await (database.select(database.localOutboxCommands)..where(
              (row) => row.entityType.equals('execution_runtime_start_cleanup'),
            ))
            .get();
    expect(cleanup, hasLength(1));
    expect(
      cleanup.single.commandId,
      supersededStartCleanupCommandId(
        userId: _userId,
        runtimeCommandId: _runtimeId,
        sessionCreateCommandId: _createId,
        sessionId: _sessionId,
      ),
    );
    expect(cleanup.single.status, 'pending');
    expect(cleanup.single.deviceSequence, 3);
    expect(jsonDecode(cleanup.single.payloadJson), {
      'runtime_command_id': _runtimeId,
      'session_create_command_id': _createId,
      'task_occurrence_id': _taskId,
    });
  });

  test('missing v0033 RPC conflict is reopened exactly once', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final service = SyncService(
      database: database,
      client: SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test_key',
      ),
    );
    addTearDown(() async {
      await service.dispose();
      await database.close();
    });

    const cleanupId = 'd66759c9-dd35-5132-bd18-dc16e8ae3a4e';
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: cleanupId,
            userId: _userId,
            deviceId: _deviceId,
            deviceSequence: 63,
            entityType: 'execution_runtime_start_cleanup',
            entityId: _sessionId,
            commandType: 'retire',
            baseRevision: 0,
            payloadJson: jsonEncode({
              'runtime_command_id': _runtimeId,
              'session_create_command_id': _createId,
              'task_occurrence_id': _taskId,
            }),
            clientTimestamp: _now,
            createdAt: _now,
            status: const drift.Value('conflict'),
            attemptCount: const drift.Value(95),
            lastError: drift.Value(
              jsonEncode({
                'reason': 'server_rejected_command',
                'code': 'PGRST202',
                'message':
                    'Could not find the function public.retire_superseded_execution_start_v0033_command in the schema cache',
              }),
            ),
          ),
        );

    await service.repairMissingSupersededStartCleanupRpcConflictsForTesting(
      _userId,
    );
    await service.repairMissingSupersededStartCleanupRpcConflictsForTesting(
      _userId,
    );

    final repaired = await (database.select(
      database.localOutboxCommands,
    )..where((row) => row.commandId.equals(cleanupId))).getSingle();
    expect(repaired.status, 'pending');
    expect(repaired.attemptCount, 0);
    expect(repaired.nextAttemptAt, isNotNull);
    expect(repaired.lastError, isNull);
    expect(
      jsonDecode(repaired.payloadJson)['cleanup_rpc_repair_version'],
      supersededStartCleanupRpcRepairVersion,
    );
  });

  test('cleanup RPC repair ignores unrelated permanent failures', () {
    expect(
      shouldRepairMissingSupersededStartCleanupRpc(
        entityType: 'execution_runtime_start_cleanup',
        status: 'conflict',
        payload: const {},
        error: const {'code': '42501', 'message': 'permission denied'},
      ),
      isFalse,
    );
    expect(
      shouldRepairMissingSupersededStartCleanupRpc(
        entityType: 'execution_runtime_start_cleanup',
        status: 'conflict',
        payload: const {'cleanup_rpc_repair_version': 1},
        error: const {
          'code': 'PGRST202',
          'message':
              'retire_superseded_execution_start_v0033_command is missing',
        },
      ),
      isFalse,
    );
  });

  test('newer or pending session state blocks cleanup rollback', () {
    LocalEntityRecord session({
      String lastCommandId = _runtimeId,
      int revision = 2,
      DateTime? deletedAt,
    }) => LocalEntityRecord(
      id: _sessionId,
      userId: _userId,
      entityType: 'execution_sessions',
      parentId: _taskId,
      title: 'Session',
      status: 'running',
      position: 0,
      dataJson: '{}',
      revision: revision,
      createdAt: _now,
      updatedAt: _now,
      createdByDeviceId: _deviceId,
      lastCommandId: lastCommandId,
      deletedAt: deletedAt,
    );

    final canonical = <String, dynamic>{
      'id': _sessionId,
      'user_id': _userId,
      'task_occurrence_id': _taskId,
      'state': 'cancelled',
      'revision': 3,
      'deleted_at': _now.toIso8601String(),
      'last_command_id': 'cleanup-command',
      'data': const {'retired_reason': 'superseded_start_v0033'},
    };
    bool allowed({LocalEntityRecord? local, bool pending = false}) =>
        shouldApplySupersededStartCanonicalSession(
          userId: _userId,
          taskId: _taskId,
          runtimeCommandId: _runtimeId,
          sessionCreateCommandId: _createId,
          cleanupCommandId: 'cleanup-command',
          orphanSessionId: _sessionId,
          localSession: local ?? session(),
          canonicalSession: canonical,
          hasPendingSessionCommand: pending,
        );

    expect(allowed(), isTrue);
    expect(allowed(pending: true), isFalse);
    expect(allowed(local: session(lastCommandId: 'newer-command')), isFalse);
    expect(allowed(local: session(revision: 4)), isFalse);
    expect(allowed(local: session(deletedAt: _now)), isFalse);
  });

  test('newer or pending task state blocks cleanup rollback', () {
    LocalTask task({String lastCommandId = _runtimeId}) => LocalTask(
      id: _taskId,
      userId: _userId,
      title: 'Daily work routine',
      description: '',
      status: 'in_progress',
      priority: 2,
      executionMode: 'pomodoro',
      estimatedDurationMs: 30600000,
      activeDurationMs: 0,
      pausedDurationMs: 0,
      idleDurationMs: 0,
      progress: 0,
      dataJson: '{}',
      revision: 4,
      createdAt: _now,
      updatedAt: _now,
      lastCommandId: lastCommandId,
    );
    final canonicalTask = <String, dynamic>{
      'id': _taskId,
      'user_id': _userId,
      'status': 'ready',
    };
    final canonicalRuntime = <String, dynamic>{
      'user_id': _userId,
      'active_session_id': null,
    };
    bool allowed({LocalTask? local, bool pending = false}) =>
        shouldApplySupersededStartCanonicalTask(
          userId: _userId,
          taskId: _taskId,
          runtimeCommandId: _runtimeId,
          orphanSessionId: _sessionId,
          localTask: local ?? task(),
          canonicalTask: canonicalTask,
          canonicalRuntime: canonicalRuntime,
          hasPendingTaskCommand: pending,
        );

    expect(allowed(), isTrue);
    expect(allowed(pending: true), isFalse);
    expect(allowed(local: task(lastCommandId: 'newer-command')), isFalse);
    expect(
      shouldApplySupersededStartCanonicalTask(
        userId: _userId,
        taskId: _taskId,
        runtimeCommandId: _runtimeId,
        orphanSessionId: _sessionId,
        localTask: task(),
        canonicalTask: canonicalTask,
        canonicalRuntime: {
          ...canonicalRuntime,
          'active_session_id': _sessionId,
        },
        hasPendingTaskCommand: false,
      ),
      isFalse,
    );
  });

  test('v0033 requires positive superseded evidence and hardened replay', () {
    final sql = File(
      'supabase/migrations/20260820123000_v0033_superseded_start_cleanup.sql',
    ).readAsStringSync();

    expect(
      'runtime_command.result ->> \'canonical_only\' = \'true\''.allMatches(
        sql,
      ),
      hasLength(2),
    );
    expect(
      'runtime_command.result ->> \'superseded\' = \'true\''.allMatches(sql),
      hasLength(2),
    );
    expect(sql, contains("owner_record.user_id::text || ':execution-runtime'"));
    expect(sql, contains("raise exception 'command_identity_mismatch'"));
    expect(
      sql.indexOf('pg_advisory_xact_lock('),
      lessThan(sql.indexOf('select *\n  into existing_command')),
    );
    expect(sql, contains('to authenticated, service_role;'));
    expect(
      sql,
      isNot(contains("entity_type in (\n        'execution_runtime'")),
    );
  });
}
