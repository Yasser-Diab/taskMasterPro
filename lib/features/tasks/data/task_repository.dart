import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity.dart';

class TaskDraft {
  const TaskDraft({
    required this.title,
    this.description = '',
    this.domainId,
    this.priority = 2,
    this.executionMode = 'manual',
    this.scheduledDate,
    this.plannedStart,
    this.estimatedDuration = const Duration(minutes: 30),
  });

  final String title;
  final String description;
  final String? domainId;
  final int priority;
  final String executionMode;
  final DateTime? scheduledDate;
  final DateTime? plannedStart;
  final Duration estimatedDuration;
}

class TaskRepository {
  TaskRepository(this.database, this.client);

  final AppDatabase database;
  final SupabaseClient client;
  static const _uuid = Uuid();

  String get _userId => client.auth.currentUser?.id ?? 'local';

  Stream<List<LocalTask>> watchTasks() {
    final query = database.select(database.localTasks)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.scheduledDate),
        (row) => OrderingTerm.asc(row.plannedStart),
        (row) => OrderingTerm.desc(row.priority),
      ]);
    return query.watch();
  }

  Stream<List<LocalTask>> watchTodayTasks(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final query = database.select(database.localTasks)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            (row.scheduledDate.isBetweenValues(start, end) |
                row.status.equals('in_progress') |
                row.status.equals('paused')),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.plannedStart),
        (row) => OrderingTerm.desc(row.priority),
      ]);
    return query.watch();
  }

  Stream<List<LocalDomain>> watchDomains() {
    final query = database.select(database.localDomains)
      ..where((row) => row.deletedAt.isNull() & row.archivedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.position)]);
    return query.watch();
  }

  Stream<LocalRuntime?> watchRuntime() {
    return (database.select(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).watchSingleOrNull();
  }

  Future<void> seedStarterDomains() async {
    final count = await database.localDomains.count().getSingle();
    if (count > 0) return;
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    const seeds = [
      ('Work', 'work', 0xFF4169E1),
      ('Learning', 'school', 0xFF00A88F),
      ('Reading', 'book', 0xFF8E5BB7),
      ('Health', 'health', 0xFFE55353),
      ('Personal', 'person', 0xFFE29B2D),
    ];
    await database.batch((batch) {
      for (var index = 0; index < seeds.length; index++) {
        final seed = seeds[index];
        batch.insert(
          database.localDomains,
          LocalDomainsCompanion.insert(
            id: _uuid.v4(),
            userId: _userId,
            name: seed.$1,
            iconName: Value(seed.$2),
            colorValue: seed.$3,
            position: Value(index.toDouble()),
            createdAt: now,
            updatedAt: now,
            createdByDeviceId: Value(deviceId),
            updatedByDeviceId: Value(deviceId),
          ),
        );
      }
    });
  }

  Future<String> createTask(TaskDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError('Task title is required.');
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final taskId = _uuid.v4();
    final commandId = _uuid.v4();
    final scheduled = draft.scheduledDate ?? DateTime.now();
    final payload = <String, Object?>{
      'title': title,
      'description': draft.description.trim(),
      'domain_id': draft.domainId,
      'priority': draft.priority,
      'status': 'ready',
      'execution_mode': draft.executionMode,
      'scheduled_date': _dateOnly(scheduled),
      'planned_start': draft.plannedStart?.toUtc().toIso8601String(),
      'estimated_duration_ms': draft.estimatedDuration.inMilliseconds,
    };

    await database.transaction(() async {
      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: taskId,
              userId: _userId,
              title: title,
              description: Value(draft.description.trim()),
              domainId: Value(draft.domainId),
              priority: Value(draft.priority),
              executionMode: Value(draft.executionMode),
              scheduledDate: Value(scheduled),
              plannedStart: Value(draft.plannedStart),
              estimatedDurationMs: Value(
                draft.estimatedDuration.inMilliseconds,
              ),
              createdAt: now,
              updatedAt: now,
              createdByDeviceId: Value(deviceId),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: taskId,
        commandType: 'create',
        baseRevision: 0,
        payload: payload,
        now: now,
      );
    });
    return taskId;
  }

  Future<void> changeStatus(LocalTask task, String status) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    await database.transaction(() async {
      await (database.update(
        database.localTasks,
      )..where((row) => row.id.equals(task.id))).write(
        LocalTasksCompanion(
          status: Value(status),
          actualStart: status == 'in_progress' && task.actualStart == null
              ? Value(now)
              : const Value.absent(),
          actualFinish: status == 'completed'
              ? Value(now)
              : const Value.absent(),
          progress: status == 'completed'
              ? const Value(1)
              : const Value.absent(),
          revision: Value(task.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: task.id,
        commandType: 'update',
        baseRevision: task.revision,
        payload: {'status': status, if (status == 'completed') 'progress': 1},
        now: now,
      );
    });
  }

  Future<void> start(LocalTask task) async {
    final now = DateTime.now().toUtc();
    final sessionId = _uuid.v4();
    await changeStatus(task, 'in_progress');
    await database
        .into(database.localRuntimeStates)
        .insertOnConflictUpdate(
          LocalRuntimeStatesCompanion.insert(
            id: 'runtime',
            userId: _userId,
            activeTaskId: Value(task.id),
            sessionId: Value(sessionId),
            state: const Value('running'),
            segmentStartedAt: Value(now),
            updatedAt: now,
          ),
        );
  }

  Future<void> pause(LocalTask task) async {
    final runtime = await (database.select(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final elapsed = runtime?.segmentStartedAt == null
        ? 0
        : now.difference(runtime!.segmentStartedAt!).inMilliseconds;
    await changeStatus(task, 'paused');
    await (database.update(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).write(
      LocalRuntimeStatesCompanion(
        state: const Value('paused'),
        segmentStartedAt: const Value(null),
        accumulatedActiveMs: Value(
          (runtime?.accumulatedActiveMs ?? 0) + elapsed,
        ),
        revision: Value((runtime?.revision ?? 0) + 1),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> resume(LocalTask task) async {
    final now = DateTime.now().toUtc();
    await changeStatus(task, 'in_progress');
    final runtime = await (database.select(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).getSingleOrNull();
    await (database.update(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).write(
      LocalRuntimeStatesCompanion(
        state: const Value('running'),
        segmentStartedAt: Value(now),
        revision: Value((runtime?.revision ?? 0) + 1),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> complete(LocalTask task) async {
    final runtime = await (database.select(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final runningElapsed =
        runtime?.state == 'running' && runtime?.segmentStartedAt != null
        ? now.difference(runtime!.segmentStartedAt!).inMilliseconds
        : 0;
    await changeStatus(task, 'completed');
    await (database.update(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).write(
      LocalRuntimeStatesCompanion(
        activeTaskId: const Value(null),
        sessionId: const Value(null),
        state: const Value('idle'),
        segmentStartedAt: const Value(null),
        accumulatedActiveMs: Value(
          (runtime?.accumulatedActiveMs ?? 0) + runningElapsed,
        ),
        revision: Value((runtime?.revision ?? 0) + 1),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> softDelete(LocalTask task) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    await database.transaction(() async {
      await (database.update(
        database.localTasks,
      )..where((row) => row.id.equals(task.id))).write(
        LocalTasksCompanion(
          deletedAt: Value(now),
          revision: Value(task.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: task.id,
        commandType: 'delete',
        baseRevision: task.revision,
        payload: const {},
        now: now,
      );
    });
  }

  Future<void> _enqueue({
    required String commandId,
    required String deviceId,
    required int sequence,
    required String entityId,
    required String commandType,
    required int baseRevision,
    required Map<String, Object?> payload,
    required DateTime now,
  }) {
    return database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: commandId,
            userId: _userId,
            deviceId: deviceId,
            deviceSequence: sequence,
            entityType: 'task_occurrences',
            entityId: entityId,
            commandType: commandType,
            baseRevision: baseRevision,
            payloadJson: jsonEncode(payload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
