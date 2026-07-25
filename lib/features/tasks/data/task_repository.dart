import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/data/entity_record_repository.dart';
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
    this.plannedEnd,
    this.dueAt,
    this.estimatedDuration = const Duration(minutes: 30),
    this.roadmapId,
    this.roadmapPhaseId,
    this.templateId,
    this.occurrenceKey,
    this.configuration = const {},
  });

  final String title;
  final String description;
  final String? domainId;
  final int priority;
  final String executionMode;
  final DateTime? scheduledDate;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? dueAt;
  final Duration estimatedDuration;
  final String? roadmapId;
  final String? roadmapPhaseId;
  final String? templateId;
  final String? occurrenceKey;
  final Map<String, Object?> configuration;
}

class TaskRepository {
  TaskRepository(this.database, this.client);

  final AppDatabase database;
  final SupabaseClient client;
  static const _uuid = Uuid();
  late final EntityRecordRepository entities = EntityRecordRepository(
    database,
    client,
  );

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

  Future<LocalTask?> getTask(String taskId) {
    return (database.select(database.localTasks)
          ..where((row) => row.id.equals(taskId) & row.deletedAt.isNull()))
        .getSingleOrNull();
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
      'planned_end': draft.plannedEnd?.toUtc().toIso8601String(),
      'due_at': draft.dueAt?.toUtc().toIso8601String(),
      'estimated_duration_ms': draft.estimatedDuration.inMilliseconds,
      'roadmap_id': draft.roadmapId,
      'roadmap_phase_id': draft.roadmapPhaseId,
      'template_id': draft.templateId,
      'occurrence_key': draft.occurrenceKey,
      'data': draft.configuration,
    };

    await database.transaction(() async {
      await database
          .into(database.localTasks)
          .insert(
            LocalTasksCompanion.insert(
              id: taskId,
              userId: _userId,
              templateId: Value(draft.templateId),
              title: title,
              description: Value(draft.description.trim()),
              domainId: Value(draft.domainId),
              priority: Value(draft.priority),
              executionMode: Value(draft.executionMode),
              scheduledDate: Value(scheduled),
              plannedStart: Value(draft.plannedStart),
              plannedEnd: Value(draft.plannedEnd),
              dueAt: Value(draft.dueAt),
              estimatedDurationMs: Value(
                draft.estimatedDuration.inMilliseconds,
              ),
              roadmapId: Value(draft.roadmapId),
              roadmapPhaseId: Value(draft.roadmapPhaseId),
              occurrenceKey: Value(draft.occurrenceKey),
              dataJson: Value(jsonEncode(draft.configuration)),
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

  Future<void> updateTask(LocalTask task, TaskDraft draft) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    final scheduled = draft.scheduledDate ?? task.scheduledDate;
    final payload = <String, Object?>{
      'title': draft.title.trim(),
      'description': draft.description.trim(),
      'domain_id': draft.domainId,
      'priority': draft.priority,
      'execution_mode': draft.executionMode,
      'scheduled_date': scheduled == null ? null : _dateOnly(scheduled),
      'planned_start': draft.plannedStart?.toUtc().toIso8601String(),
      'planned_end': draft.plannedEnd?.toUtc().toIso8601String(),
      'due_at': draft.dueAt?.toUtc().toIso8601String(),
      'estimated_duration_ms': draft.estimatedDuration.inMilliseconds,
      'roadmap_id': draft.roadmapId,
      'roadmap_phase_id': draft.roadmapPhaseId,
      'template_id': draft.templateId ?? task.templateId,
      'occurrence_key': draft.occurrenceKey ?? task.occurrenceKey,
      'data': draft.configuration,
    };
    await database.transaction(() async {
      await (database.update(
        database.localTasks,
      )..where((row) => row.id.equals(task.id))).write(
        LocalTasksCompanion(
          title: Value(draft.title.trim()),
          description: Value(draft.description.trim()),
          domainId: Value(draft.domainId),
          priority: Value(draft.priority),
          executionMode: Value(draft.executionMode),
          scheduledDate: Value(scheduled),
          plannedStart: Value(draft.plannedStart),
          plannedEnd: Value(draft.plannedEnd),
          dueAt: Value(draft.dueAt),
          estimatedDurationMs: Value(draft.estimatedDuration.inMilliseconds),
          roadmapId: Value(draft.roadmapId),
          roadmapPhaseId: Value(draft.roadmapPhaseId),
          templateId: Value(draft.templateId ?? task.templateId),
          occurrenceKey: Value(draft.occurrenceKey ?? task.occurrenceKey),
          dataJson: Value(jsonEncode(draft.configuration)),
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
        payload: payload,
        now: now,
      );
    });
  }

  Future<void> updateRelationships(
    LocalTask task, {
    String? roadmapId,
    String? roadmapPhaseId,
  }) async {
    final latest = await (database.select(
      database.localTasks,
    )..where((row) => row.id.equals(task.id))).getSingle();
    await updateTask(
      latest,
      TaskDraft(
        title: latest.title,
        description: latest.description,
        domainId: latest.domainId,
        priority: latest.priority,
        executionMode: latest.executionMode,
        scheduledDate: latest.scheduledDate,
        plannedStart: latest.plannedStart,
        plannedEnd: latest.plannedEnd,
        dueAt: latest.dueAt,
        estimatedDuration: Duration(milliseconds: latest.estimatedDurationMs),
        roadmapId: roadmapId,
        roadmapPhaseId: roadmapPhaseId,
        templateId: latest.templateId,
        occurrenceKey: latest.occurrenceKey,
        configuration: _configuration(latest),
      ),
    );
  }

  Future<void> updateConfiguration(
    LocalTask task,
    Map<String, Object?> configuration,
  ) async {
    final latest = await getTask(task.id);
    if (latest == null) return;
    await updateTask(
      latest,
      TaskDraft(
        title: latest.title,
        description: latest.description,
        domainId: latest.domainId,
        priority: latest.priority,
        executionMode: latest.executionMode,
        scheduledDate: latest.scheduledDate,
        plannedStart: latest.plannedStart,
        plannedEnd: latest.plannedEnd,
        dueAt: latest.dueAt,
        estimatedDuration: Duration(milliseconds: latest.estimatedDurationMs),
        roadmapId: latest.roadmapId,
        roadmapPhaseId: latest.roadmapPhaseId,
        templateId: latest.templateId,
        occurrenceKey: latest.occurrenceKey,
        configuration: configuration,
      ),
    );
  }

  Future<void> attachTemplate({
    required String taskId,
    required String templateId,
    required String occurrenceKey,
  }) async {
    final task = await getTask(taskId);
    if (task == null) return;
    await updateTask(
      task,
      TaskDraft(
        title: task.title,
        description: task.description,
        domainId: task.domainId,
        priority: task.priority,
        executionMode: task.executionMode,
        scheduledDate: task.scheduledDate,
        plannedStart: task.plannedStart,
        plannedEnd: task.plannedEnd,
        dueAt: task.dueAt,
        estimatedDuration: Duration(milliseconds: task.estimatedDurationMs),
        roadmapId: task.roadmapId,
        roadmapPhaseId: task.roadmapPhaseId,
        templateId: templateId,
        occurrenceKey: occurrenceKey,
        configuration: _configuration(task),
      ),
    );
  }

  Future<String> duplicate(LocalTask task) {
    return createTask(
      TaskDraft(
        title: '${task.title} copy',
        description: task.description,
        domainId: task.domainId,
        priority: task.priority,
        executionMode: task.executionMode,
        scheduledDate: task.scheduledDate,
        plannedStart: task.plannedStart,
        plannedEnd: task.plannedEnd,
        dueAt: task.dueAt,
        estimatedDuration: Duration(milliseconds: task.estimatedDurationMs),
        roadmapId: task.roadmapId,
        roadmapPhaseId: task.roadmapPhaseId,
        templateId: task.templateId,
        occurrenceKey: task.occurrenceKey,
        configuration: _configuration(task),
      ),
    );
  }

  Future<void> reschedule(LocalTask task, DateTime date) async {
    final latest = await (database.select(
      database.localTasks,
    )..where((row) => row.id.equals(task.id))).getSingle();
    await updateTask(
      latest,
      TaskDraft(
        title: latest.title,
        description: latest.description,
        domainId: latest.domainId,
        priority: latest.priority,
        executionMode: latest.executionMode,
        scheduledDate: date,
        plannedStart: latest.plannedStart,
        plannedEnd: latest.plannedEnd,
        dueAt: latest.dueAt,
        estimatedDuration: Duration(milliseconds: latest.estimatedDurationMs),
        roadmapId: latest.roadmapId,
        roadmapPhaseId: latest.roadmapPhaseId,
        templateId: latest.templateId,
        occurrenceKey: latest.occurrenceKey,
        configuration: _configuration(latest),
      ),
    );
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
    final previousRuntime = await (database.select(
      database.localRuntimeStates,
    )..where((row) => row.id.equals('runtime'))).getSingleOrNull();
    if (previousRuntime?.activeTaskId != null &&
        previousRuntime!.activeTaskId != task.id) {
      final previousTask = await getTask(previousRuntime.activeTaskId!);
      if (previousTask != null) {
        await changeStatus(previousTask, 'paused');
        await _recordInterruption(
          sessionId: previousRuntime.sessionId,
          taskId: previousTask.id,
          targetTaskId: task.id,
          startedAt: now,
        );
        await _updateExecutionSession(
          previousRuntime,
          state: 'paused',
          now: now,
        );
      }
    }
    final sessionId = await _createExecutionSession(task, now);
    final latest = await getTask(task.id) ?? task;
    await changeStatus(latest, 'in_progress');
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
    await _recordSessionEvent(
      taskId: task.id,
      sessionId: sessionId,
      eventType: 'started',
      occurredAt: now,
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
    await _updateExecutionSession(runtime, state: 'paused', now: now);
    if (runtime?.sessionId != null) {
      await _recordSessionEvent(
        taskId: task.id,
        sessionId: runtime!.sessionId!,
        eventType: 'paused',
        occurredAt: now,
        durationMs: elapsed,
      );
    }
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
    await _updateExecutionSession(runtime, state: 'running', now: now);
    if (runtime?.sessionId != null) {
      await _recordSessionEvent(
        taskId: task.id,
        sessionId: runtime!.sessionId!,
        eventType: 'resumed',
        occurredAt: now,
      );
    }
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
    final latest = await getTask(task.id) ?? task;
    final totalActive = (runtime?.accumulatedActiveMs ?? 0) + runningElapsed;
    await changeStatus(latest, 'completed');
    final completedTask = await getTask(task.id);
    if (completedTask != null) {
      await _updateActualDuration(completedTask, totalActive);
    }
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
    await _updateExecutionSession(
      runtime,
      state: 'completed',
      now: now,
      finishedAt: now,
      accumulatedActiveMs: totalActive,
    );
    if (runtime?.sessionId != null) {
      await _recordSessionEvent(
        taskId: task.id,
        sessionId: runtime!.sessionId!,
        eventType: 'completed',
        occurredAt: now,
        durationMs: totalActive,
      );
    }
  }

  Future<String> _createExecutionSession(LocalTask task, DateTime now) {
    return entities.create(
      EntityRecordDraft(
        entityType: 'execution_sessions',
        parentId: task.id,
        title: '${task.title} session',
        status: 'running',
        data: {
          'task_occurrence_id': task.id,
          'mode': task.executionMode,
          'state': 'running',
          'started_at': now.toIso8601String(),
          'active_segment_started_at': now.toIso8601String(),
          'accumulated_active_ms': 0,
          'accumulated_paused_ms': 0,
          'accumulated_idle_ms': 0,
          'current_cycle': 0,
          'is_unscheduled': task.scheduledDate == null,
        },
        syncPayload: {
          'task_occurrence_id': task.id,
          'mode': task.executionMode,
          'state': 'running',
          'started_at': now.toIso8601String(),
          'finished_at': null,
          'active_segment_started_at': now.toIso8601String(),
          'accumulated_active_ms': 0,
          'accumulated_paused_ms': 0,
          'accumulated_idle_ms': 0,
          'current_pomodoro_segment': task.executionMode == 'pomodoro'
              ? 'focus'
              : null,
          'current_cycle': 0,
          'is_unscheduled': task.scheduledDate == null,
          'data': <String, Object?>{},
        },
      ),
    );
  }

  Future<void> _updateExecutionSession(
    LocalRuntime? runtime, {
    required String state,
    required DateTime now,
    DateTime? finishedAt,
    int? accumulatedActiveMs,
  }) async {
    final sessionId = runtime?.sessionId;
    if (sessionId == null) return;
    final session = await entities.get(sessionId);
    if (session == null) return;
    final data = entities.decode(session);
    final segmentElapsed =
        runtime?.state == 'running' && runtime?.segmentStartedAt != null
        ? now.difference(runtime!.segmentStartedAt!).inMilliseconds
        : 0;
    final active =
        accumulatedActiveMs ??
        ((data['accumulated_active_ms'] as num?)?.toInt() ?? 0) +
            segmentElapsed;
    data
      ..['state'] = state
      ..['active_segment_started_at'] = state == 'running'
          ? now.toIso8601String()
          : null
      ..['finished_at'] = finishedAt?.toIso8601String()
      ..['accumulated_active_ms'] = active;
    await entities.update(
      session,
      status: state,
      data: data,
      syncPayload: {
        'state': state,
        'active_segment_started_at': data['active_segment_started_at'],
        'finished_at': data['finished_at'],
        'accumulated_active_ms': active,
      },
    );
  }

  Future<void> _recordSessionEvent({
    required String taskId,
    required String sessionId,
    required String eventType,
    required DateTime occurredAt,
    int? durationMs,
  }) async {
    final deviceId = await DeviceIdentity.id();
    await entities.create(
      EntityRecordDraft(
        entityType: 'session_events',
        parentId: taskId,
        secondaryParentId: sessionId,
        title: eventType,
        status: eventType,
        data: {
          'session_id': sessionId,
          'task_occurrence_id': taskId,
          'event_type': eventType,
          'occurred_at': occurredAt.toIso8601String(),
          'duration_ms': durationMs,
          'source_device_id': deviceId,
        },
        syncPayload: {
          'session_id': sessionId,
          'event_type': eventType,
          'occurred_at': occurredAt.toIso8601String(),
          'duration_ms': durationMs,
          'source_device_id': deviceId,
          'event_payload': {'task_occurrence_id': taskId},
          'data': <String, Object?>{},
        },
      ),
    );
  }

  Future<void> _recordInterruption({
    required String? sessionId,
    required String taskId,
    required String targetTaskId,
    required DateTime startedAt,
  }) async {
    if (sessionId == null) return;
    await entities.create(
      EntityRecordDraft(
        entityType: 'interruptions',
        parentId: taskId,
        secondaryParentId: targetTaskId,
        title: 'Context switch to another task',
        status: 'open',
        data: {
          'session_id': sessionId,
          'task_occurrence_id': taskId,
          'started_at': startedAt.toIso8601String(),
          'interruption_type': 'cross_task',
          'target_task_id': targetTaskId,
        },
        syncPayload: {
          'session_id': sessionId,
          'task_occurrence_id': taskId,
          'started_at': startedAt.toIso8601String(),
          'ended_at': null,
          'interruption_type': 'cross_task',
          'target_task_id': targetTaskId,
          'notes': null,
        },
      ),
    );
  }

  Future<void> _updateActualDuration(
    LocalTask task,
    int activeDurationMs,
  ) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    await database.transaction(() async {
      await (database.update(
        database.localTasks,
      )..where((row) => row.id.equals(task.id))).write(
        LocalTasksCompanion(
          activeDurationMs: Value(activeDurationMs),
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
        payload: {'actual_duration_ms': activeDurationMs},
        now: now,
      );
    });
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

  Map<String, Object?> _configuration(LocalTask task) {
    final value = jsonDecode(task.dataJson);
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }
}
