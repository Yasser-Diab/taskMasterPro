import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/data/entity_record_repository.dart';
import '../../../core/platform/device_identity.dart';
import '../domain/task_domain_catalog.dart';
import '../domain/task_schedule_policy.dart';

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

  TaskScheduleWindow? get scheduleWindow =>
      TaskSchedulePolicy.resolve(plannedStart, plannedEnd);

  DateTime? get effectivePlannedEnd => scheduleWindow?.end ?? plannedEnd;

  Duration get effectiveEstimatedDuration =>
      scheduleWindow?.duration ?? estimatedDuration;
}

/// Starting a task and resuming a paused session are deliberately different
/// operations.  A caller must ask the user before changing the account-wide
/// active task.
enum ActiveTaskSwitchAction { pauseCurrent, finishCurrent }

class TaskStartResult {
  const TaskStartResult._(this.requiresSwitch, this.activeTaskId);

  const TaskStartResult.started() : this._(false, null);

  const TaskStartResult.switchRequired(String activeTaskId)
    : this._(true, activeTaskId);

  final bool requiresSwitch;
  final String? activeTaskId;
}

class TaskCompletionResult {
  const TaskCompletionResult({
    required this.taskId,
    required this.snapshotId,
    required this.completedAt,
    required this.undoExpiresAt,
  });

  final String taskId;
  final String snapshotId;
  final DateTime completedAt;
  final DateTime undoExpiresAt;

  bool get canUndo =>
      snapshotId.isNotEmpty && DateTime.now().toUtc().isBefore(undoExpiresAt);
}

/// The identity of one durable execution command.
///
/// Runtime state and its outbox row must share this exact identity.  Creating
/// it before the local state write lets a later canonical runtime echo be
/// compared with the optimistic state instead of being treated as unrelated
/// data.
class _RuntimeCommandIdentity {
  const _RuntimeCommandIdentity({
    required this.commandId,
    required this.deviceId,
    required this.deviceSequence,
  });

  final String commandId;
  final String deviceId;
  final int deviceSequence;
}

enum TaskRestorationOutcome {
  restored,
  taskNotFound,
  notCompleted,
  snapshotNotFound,
  undoExpired,
  reopenTooEarly,
}

class TaskRepository {
  TaskRepository(
    this.database,
    this.client, {
    DateTime Function()? clock,
    this.recalculateRoadmap,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase database;
  final SupabaseClient client;
  final DateTime Function() _clock;
  final Future<void> Function(String roadmapId)? recalculateRoadmap;
  static const _uuid = Uuid();
  static const completionUndoWindow = Duration(seconds: 15);
  static const _completionSnapshotType = 'task_completion_evidence';
  static const _completionEvidenceType = 'task_completion_evidence';
  final Map<String, Future<TaskCompletionResult>> _completionInFlight = {};
  Future<void> _executionTransitionTail = Future<void>.value();
  late final EntityRecordRepository entities = EntityRecordRepository(
    database,
    client,
  );

  String get _userId => client.auth.currentUser?.id ?? 'local';
  String get _runtimeId => localRuntimeStateId(_userId);

  Stream<List<LocalTask>> watchTasks() {
    final query = database.select(database.localTasks)
      ..where((row) => row.userId.equals(_userId) & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.scheduledDate),
        (row) => OrderingTerm.asc(row.plannedStart),
        (row) => OrderingTerm.desc(row.priority),
      ]);
    return query.watch();
  }

  Future<LocalTask?> getTask(String taskId) {
    return (database.select(database.localTasks)..where(
          (row) =>
              row.id.equals(taskId) &
              row.userId.equals(_userId) &
              row.deletedAt.isNull(),
        ))
        .getSingleOrNull();
  }

  Stream<LocalTask?> watchTask(String taskId) {
    return (database.select(database.localTasks)..where(
          (row) =>
              row.id.equals(taskId) &
              row.userId.equals(_userId) &
              row.deletedAt.isNull(),
        ))
        .watchSingleOrNull();
  }

  Stream<List<LocalTask>> watchTodayTasks(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final query = database.select(database.localTasks)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.deletedAt.isNull() &
            row.status.isNotIn(const ['completed', 'cancelled']) &
            row.scheduledDate.isBetweenValues(start, end),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.plannedStart),
        (row) => OrderingTerm.desc(row.priority),
      ]);
    return query.watch();
  }

  Stream<List<LocalDomain>> watchDomains() {
    final query = database.select(database.localDomains)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.deletedAt.isNull() &
            row.archivedAt.isNull(),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.position)]);
    return query.watch();
  }

  Stream<List<LocalDomain>> watchAllDomains() {
    final query = database.select(database.localDomains)
      ..where((row) => row.userId.equals(_userId) & row.deletedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.position)]);
    return query.watch();
  }

  Stream<LocalRuntime?> watchRuntime() {
    return _runtimeQuery().watchSingleOrNull().asyncMap(_validatedRuntime);
  }

  /// Reads the current runtime once without creating a short-lived stream
  /// subscription. Command handlers use this for boundary validation while
  /// widgets use [watchRuntime] for durable UI updates.
  Future<LocalRuntime?> getRuntime() async {
    return _validatedRuntime(await _runtimeQuery().getSingleOrNull());
  }

  SimpleSelectStatement<$LocalRuntimeStatesTable, LocalRuntime>
  _runtimeQuery() {
    return database.select(database.localRuntimeStates)..where(
      (row) =>
          row.id.equals(_runtimeId) &
          row.userId.equals(_userId) &
          row.sessionId.isNotNull() &
          row.activeTaskId.isNotNull() &
          row.state.isIn(const ['running', 'paused', 'break']),
    );
  }

  /// A runtime cache is usable only while both of its referenced records are
  /// still live for this account. A tombstoned task or missing/deleted
  /// execution session is history, not evidence that work is still running.
  ///
  /// This check sits at the repository boundary so dashboards, task cards,
  /// notifications, the tray and the Execute page cannot disagree about a
  /// ghost active task. The local repair deliberately preserves the canonical
  /// revision; cache repair is not a new server transition. Canonical
  /// snapshots apply tasks, then sessions, then runtime. If a Realtime row
  /// nevertheless arrives early, the post-sync canonical-runtime restore can
  /// safely write it again after its references arrive.
  Future<LocalRuntime?> _validatedRuntime(LocalRuntime? runtime) async {
    if (runtime == null) return null;
    final taskId = runtime.activeTaskId;
    final sessionId = runtime.sessionId;
    if (taskId == null || sessionId == null) {
      await _clearInvalidRuntime(runtime);
      return null;
    }

    final task =
        await (database.select(database.localTasks)..where(
              (row) =>
                  row.id.equals(taskId) &
                  row.userId.equals(_userId) &
                  row.deletedAt.isNull() &
                  row.status.isNotIn(const [
                    'completed',
                    'cancelled',
                    'archived',
                  ]),
            ))
            .getSingleOrNull();
    final session =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.id.equals(sessionId) &
                  row.userId.equals(_userId) &
                  row.entityType.equals('execution_sessions') &
                  row.parentId.equals(taskId) &
                  row.deletedAt.isNull() &
                  row.status.isNotIn(const ['completed', 'cancelled']),
            ))
            .getSingleOrNull();
    if (task != null && session != null) return runtime;

    await _clearInvalidRuntime(runtime);
    return null;
  }

  Future<void> _clearInvalidRuntime(LocalRuntime runtime) async {
    final now = _clock();
    await database.transaction(() async {
      await _supersedePendingRuntimeCommands(runtime);
      await (database.update(database.localRuntimeStates)..where(
            (row) =>
                row.id.equals(runtime.id) &
                row.userId.equals(_userId) &
                row.activeTaskId.equals(runtime.activeTaskId!) &
                row.sessionId.equals(runtime.sessionId!) &
                row.revision.equals(runtime.revision),
          ))
          .write(
            LocalRuntimeStatesCompanion(
              activeTaskId: const Value(null),
              sessionId: const Value(null),
              state: const Value('idle'),
              segmentStartedAt: const Value(null),
              updatedAt: Value(now),
            ),
          );
    });
  }

  Future<void> _supersedePendingRuntimeCommands(LocalRuntime runtime) async {
    final sessionId = runtime.sessionId;
    if (sessionId == null) return;
    await (database.update(database.localOutboxCommands)..where(
          (row) =>
              row.userId.equals(_userId) &
              row.status.equals('pending') &
              row.entityId.equals(sessionId) &
              row.entityType.isIn(const [
                'execution_sessions',
                'execution_runtime',
                'execution_runtime_switch',
              ]),
        ))
        .write(
          const LocalOutboxCommandsCompanion(
            status: Value('superseded'),
            lastError: Value(null),
            nextAttemptAt: Value(null),
          ),
        );
  }

  /// Serializes local execution state changes for this account.
  ///
  /// Multiple visible surfaces (and notification/tray callbacks) can invoke
  /// the same command at nearly the same time. Running each transition after
  /// the previous local commit makes a duplicate tap an idempotent no-op while
  /// preserving a valid subsequent command.
  Future<T> _serializeExecutionTransition<T>(Future<T> Function() transition) {
    final queued = _executionTransitionTail.then((_) => transition());
    _executionTransitionTail = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return queued;
  }

  Future<_RuntimeCommandIdentity> _newRuntimeCommandIdentity() async {
    final userId = _userId;
    return _RuntimeCommandIdentity(
      commandId: _uuid.v4(),
      deviceId: await DeviceIdentity.accountId(userId),
      deviceSequence: await DeviceIdentity.nextSequence(userId),
    );
  }

  Future<LocalRuntime?> _storedRuntime() {
    return (database.select(database.localRuntimeStates)..where(
          (row) => row.id.equals(_runtimeId) & row.userId.equals(_userId),
        ))
        .getSingleOrNull();
  }

  Future<void> seedStarterDomains() async {
    if (_userId == 'local') return;
    final now = _clock();
    final deviceId = await DeviceIdentity.accountId(_userId);
    for (var index = 0; index < TaskDomainCatalog.definitions.length; index++) {
      final definition = TaskDomainCatalog.definitions[index];
      final id = TaskDomainCatalog.idFor(_userId, definition.key);
      final existing =
          await (database.select(
                database.localDomains,
              )..where((row) => row.id.equals(id) & row.userId.equals(_userId)))
              .getSingleOrNull();
      if (existing != null &&
          existing.deletedAt == null &&
          existing.archivedAt == null) {
        continue;
      }
      final commandId = _uuid.v4();
      final sequence = await DeviceIdentity.nextSequence(_userId);
      await database.transaction(() async {
        await database
            .into(database.localDomains)
            .insertOnConflictUpdate(
              LocalDomainsCompanion.insert(
                id: id,
                userId: _userId,
                name: definition.canonicalName,
                iconName: Value(definition.iconName),
                colorValue: definition.colorValue,
                position: Value(index.toDouble()),
                archivedAt: const Value(null),
                revision: Value(existing?.revision ?? 1),
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                createdByDeviceId: Value(
                  existing?.createdByDeviceId ?? deviceId,
                ),
                updatedByDeviceId: Value(deviceId),
                lastCommandId: Value(commandId),
                deletedAt: const Value(null),
              ),
            );
        await database
            .into(database.localOutboxCommands)
            .insert(
              LocalOutboxCommandsCompanion.insert(
                commandId: commandId,
                userId: _userId,
                deviceId: deviceId,
                deviceSequence: sequence,
                entityType: 'task_domains',
                entityId: id,
                commandType: existing == null ? 'create' : 'update',
                baseRevision: existing?.revision ?? 0,
                payloadJson: jsonEncode({
                  'name': definition.canonicalName,
                  'icon_name': definition.iconName,
                  'color_value': _databaseColorValue(definition.colorValue),
                  'position': index.toDouble(),
                  'archived_at': null,
                  'data': {'built_in': true, 'domain_key': definition.key},
                }),
                clientTimestamp: now,
                createdAt: now,
              ),
            );
      });
    }
  }

  Future<String> createCustomDomain({
    required String name,
    String iconName = 'folder',
    int colorValue = 0xFF5064C9,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('A task domain needs a name.');
    }
    final duplicate =
        await (database.select(database.localDomains)..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.deletedAt.isNull() &
                  row.archivedAt.isNull() &
                  row.name.lower().equals(normalized.toLowerCase()),
            ))
            .getSingleOrNull();
    if (duplicate != null) return duplicate.id;
    final current = await watchAllDomains().first;
    final id = _uuid.v4();
    final commandId = _uuid.v4();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final now = _clock();
    await database.transaction(() async {
      await database
          .into(database.localDomains)
          .insert(
            LocalDomainsCompanion.insert(
              id: id,
              userId: _userId,
              name: normalized,
              iconName: Value(iconName),
              colorValue: colorValue,
              position: Value(current.length.toDouble()),
              createdAt: now,
              updatedAt: now,
              createdByDeviceId: Value(deviceId),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await _enqueueDomainCommand(
        commandId: commandId,
        deviceId: deviceId,
        entityId: id,
        commandType: 'create',
        baseRevision: 0,
        payload: {
          'name': normalized,
          'icon_name': iconName,
          'color_value': _databaseColorValue(colorValue),
          'position': current.length.toDouble(),
          'data': const {'built_in': false},
        },
        now: now,
      );
    });
    return id;
  }

  Future<void> updateCustomDomain(
    LocalDomain domain, {
    required String name,
    required String iconName,
    required int colorValue,
  }) async {
    if (TaskDomainCatalog.builtInKeyForId(_userId, domain.id) != null) {
      throw StateError('Built-in task domains cannot be renamed.');
    }
    await _updateDomain(
      domain,
      name: name.trim(),
      iconName: iconName,
      colorValue: colorValue,
    );
  }

  Future<void> archiveCustomDomain(LocalDomain domain) async {
    if (TaskDomainCatalog.builtInKeyForId(_userId, domain.id) != null) {
      throw StateError('Built-in task domains remain available to every user.');
    }
    await _updateDomain(domain, archivedAt: _clock());
  }

  Future<void> restoreCustomDomain(LocalDomain domain) =>
      _updateDomain(domain, archivedAt: null, restoreArchive: true);

  Future<void> _updateDomain(
    LocalDomain domain, {
    String? name,
    String? iconName,
    int? colorValue,
    DateTime? archivedAt,
    bool restoreArchive = false,
  }) async {
    final latest =
        await (database.select(database.localDomains)..where(
              (row) => row.id.equals(domain.id) & row.userId.equals(_userId),
            ))
            .getSingleOrNull();
    if (latest == null) return;
    final now = _clock();
    final commandId = _uuid.v4();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final payload = <String, Object?>{
      if (archivedAt != null || restoreArchive)
        'archived_at': archivedAt?.toUtc().toIso8601String(),
    };
    if (name != null) payload['name'] = name;
    if (iconName != null) payload['icon_name'] = iconName;
    if (colorValue != null) {
      payload['color_value'] = _databaseColorValue(colorValue);
    }
    await database.transaction(() async {
      await (database.update(database.localDomains)..where(
            (row) => row.id.equals(latest.id) & row.userId.equals(_userId),
          ))
          .write(
            LocalDomainsCompanion(
              name: Value.absentIfNull(name),
              iconName: Value.absentIfNull(iconName),
              colorValue: Value.absentIfNull(colorValue),
              archivedAt: archivedAt != null || restoreArchive
                  ? Value(archivedAt)
                  : const Value.absent(),
              revision: Value(latest.revision + 1),
              updatedAt: Value(now),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await _enqueueDomainCommand(
        commandId: commandId,
        deviceId: deviceId,
        entityId: latest.id,
        commandType: 'update',
        baseRevision: latest.revision,
        payload: payload,
        now: now,
      );
    });
  }

  Future<void> _enqueueDomainCommand({
    required String commandId,
    required String deviceId,
    required String entityId,
    required String commandType,
    required int baseRevision,
    required Map<String, Object?> payload,
    required DateTime now,
  }) async {
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: commandId,
            userId: _userId,
            deviceId: deviceId,
            deviceSequence: await DeviceIdentity.nextSequence(_userId),
            entityType: 'task_domains',
            entityId: entityId,
            commandType: commandType,
            baseRevision: baseRevision,
            payloadJson: jsonEncode(payload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  Future<String> createTask(TaskDraft draft) async {
    _validateDraftDurationBounds(draft);
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError('Task title is required.');
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final sequence = await DeviceIdentity.nextSequence(_userId);
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
      'planned_end': draft.effectivePlannedEnd?.toUtc().toIso8601String(),
      'due_at': draft.dueAt?.toUtc().toIso8601String(),
      'estimated_duration_ms': draft.effectiveEstimatedDuration.inMilliseconds,
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
              plannedEnd: Value(draft.effectivePlannedEnd),
              dueAt: Value(draft.dueAt),
              estimatedDurationMs: Value(
                draft.effectiveEstimatedDuration.inMilliseconds,
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
    _validateDraftDurationBounds(draft);
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final sequence = await DeviceIdentity.nextSequence(_userId);
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
      'planned_end': draft.effectivePlannedEnd?.toUtc().toIso8601String(),
      'due_at': draft.dueAt?.toUtc().toIso8601String(),
      'estimated_duration_ms': draft.effectiveEstimatedDuration.inMilliseconds,
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
          plannedEnd: Value(draft.effectivePlannedEnd),
          dueAt: Value(draft.dueAt),
          estimatedDurationMs: Value(
            draft.effectiveEstimatedDuration.inMilliseconds,
          ),
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

  Future<void> changeStatus(
    LocalTask task,
    String status, {
    int? activeDurationMs,
  }) async {
    final currentTask = await getTask(task.id);
    if (currentTask == null) return;
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final sequence = await DeviceIdentity.nextSequence(_userId);
    final commandId = _uuid.v4();
    final payload = <String, Object?>{
      'status': status,
      if (status == 'completed') 'progress': 1,
    };
    if (activeDurationMs != null) {
      payload['actual_duration_ms'] = activeDurationMs;
    }
    await database.transaction(() async {
      await (database.update(
        database.localTasks,
      )..where((row) => row.id.equals(task.id))).write(
        LocalTasksCompanion(
          status: Value(status),
          actualStart:
              status == 'in_progress' && currentTask.actualStart == null
              ? Value(now)
              : const Value.absent(),
          actualFinish: status == 'completed'
              ? Value(now)
              : const Value.absent(),
          progress: status == 'completed'
              ? const Value(1)
              : const Value.absent(),
          activeDurationMs: activeDurationMs == null
              ? const Value.absent()
              : Value(activeDurationMs),
          revision: Value(currentTask.revision + 1),
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
        baseRevision: currentTask.revision,
        payload: payload,
        now: now,
      );
    });
  }

  /// Starts exactly [task].  It never repurposes a paused session that belongs
  /// to another task and it never silently stops the currently active task.
  /// When a hand-off is required the UI receives [TaskStartResult] and must
  /// ask the user which explicit action to take.
  Future<TaskStartResult> start(LocalTask task) =>
      _serializeExecutionTransition(() => _start(task));

  Future<TaskStartResult> _start(LocalTask task) async {
    return database.transaction(() async {
      final currentTask = await getTask(task.id);
      if (currentTask == null) {
        return const TaskStartResult.started();
      }
      final now = DateTime.now().toUtc();
      var previousRuntime = await getRuntime();
      if (previousRuntime?.activeTaskId != null &&
          previousRuntime!.activeTaskId != currentTask.id) {
        final previousTask = await getTask(previousRuntime.activeTaskId!);
        final previousSession = previousRuntime.sessionId == null
            ? null
            : await entities.get(previousRuntime.sessionId!);
        final activeReferenceIsUsable =
            const {
              'running',
              'paused',
              'break',
            }.contains(previousRuntime.state) &&
            previousTask != null &&
            !const {
              'completed',
              'cancelled',
              'archived',
              'skipped',
            }.contains(previousTask.status) &&
            previousSession != null &&
            previousSession.parentId == previousTask.id &&
            const {
              'running',
              'paused',
              'break',
            }.contains(previousSession.status);
        if (!activeReferenceIsUsable) {
          // A runtime pointer without a live task/session is cache damage, not
          // an active-task conflict. Repair it before evaluating Start so the
          // user is never asked to pause a task that does not exist. Keep the
          // canonical revision unchanged; the new Start transition is still
          // checked against Supabase and cannot displace a real remote task.
          await (database.update(database.localRuntimeStates)..where(
                (row) =>
                    row.id.equals(_runtimeId) &
                    row.userId.equals(_userId) &
                    row.revision.equals(previousRuntime!.revision),
              ))
              .write(
                LocalRuntimeStatesCompanion(
                  activeTaskId: const Value(null),
                  sessionId: const Value(null),
                  state: const Value('idle'),
                  segmentStartedAt: const Value(null),
                  updatedAt: Value(now),
                ),
              );
          previousRuntime = await getRuntime();
        }
      }
      if (previousRuntime?.activeTaskId == currentTask.id &&
          previousRuntime?.sessionId != null) {
        // Start is strictly an idle-to-running intent. It is intentionally
        // idempotent once this task owns the canonical session, regardless of
        // whether that session is running, paused, or on a break. This matters
        // for delayed notification callbacks and stale task cards: replaying
        // their old Start action must never become a new Resume or Finish
        // break command after another device changed the runtime. Those
        // transitions are available only through their explicit commands.
        return const TaskStartResult.started();
      }
      if (previousRuntime?.activeTaskId != null &&
          previousRuntime!.activeTaskId != currentTask.id) {
        return TaskStartResult.switchRequired(previousRuntime.activeTaskId!);
      }
      final sessionId = await _createExecutionSession(currentTask, now);
      final latest = await getTask(currentTask.id) ?? currentTask;
      // [getRuntime] intentionally hides an idle runtime from UI callers. A
      // new Start still has to be guarded against that idle row's canonical
      // revision, rather than treating it as revision zero after a previous
      // completion.
      final storedRuntime = await _storedRuntime();
      // Both the local and canonical schemas bootstrap their one runtime row
      // at revision 1.  An absent local cache is therefore not revision 0:
      // using 0 here would let the first Start succeed remotely at revision 2
      // while leaving the optimistic runtime at revision 1.
      final runtimeRevision = storedRuntime?.revision ?? 1;
      final command = await _newRuntimeCommandIdentity();
      await changeStatus(latest, 'in_progress');
      await database
          .into(database.localRuntimeStates)
          .insertOnConflictUpdate(
            LocalRuntimeStatesCompanion.insert(
              id: _runtimeId,
              userId: _userId,
              activeTaskId: Value(currentTask.id),
              sessionId: Value(sessionId),
              state: const Value('running'),
              segmentStartedAt: Value(now),
              revision: Value(runtimeRevision + 1),
              updatedAt: now,
              lastCommandId: Value(command.commandId),
            ),
          );
      await _queueRuntimeTransition(
        command: command,
        sessionId: sessionId,
        task: currentTask,
        action: 'start',
        runtimeRevision: runtimeRevision,
        now: now,
      );
      return const TaskStartResult.started();
    });
  }

  /// Atomically hands the canonical active slot to [task].  The previous task
  /// is only paused or completed after the user has chosen that action.
  Future<void> switchActiveTask(
    LocalTask task, {
    required ActiveTaskSwitchAction action,
  }) => _serializeExecutionTransition(
    () => _switchActiveTask(task, action: action),
  );

  Future<void> _switchActiveTask(
    LocalTask task, {
    required ActiveTaskSwitchAction action,
  }) async {
    await database.transaction(() async {
      final selectedTask = await getTask(task.id);
      if (selectedTask == null) return;
      final runtime = await getRuntime();
      if (runtime == null ||
          runtime.sessionId == null ||
          runtime.activeTaskId == null ||
          runtime.state == 'idle') {
        await _start(selectedTask);
        return;
      }
      if (runtime.activeTaskId == selectedTask.id) {
        // The hand-off choice was made against an older runtime snapshot.
        // If another device has already made the selected task canonical,
        // leave its current state alone. In particular, a delayed dialog
        // confirmation must not turn a later remote Pause into Resume.
        return;
      }
      final previousTask = await getTask(runtime.activeTaskId!);
      if (previousTask == null) {
        // Do not guess a fallback task. A pull will repair the stale local
        // cache and the user can choose the requested task again.
        return;
      }

      final now = DateTime.now().toUtc();
      // This paused history row and the runtime hand-off commit together, so
      // observers can never render it as a second active task.
      final newSessionId = await _createExecutionSession(
        selectedTask,
        now,
        initialState: 'paused',
      );
      final elapsed =
          runtime.state == 'running' && runtime.segmentStartedAt != null
          ? now.difference(runtime.segmentStartedAt!).inMilliseconds
          : 0;
      final previousActiveMs = runtime.accumulatedActiveMs + elapsed;
      final command = await _newRuntimeCommandIdentity();

      await (database.update(database.localTasks)..where(
            (row) =>
                row.id.equals(previousTask.id) & row.userId.equals(_userId),
          ))
          .write(
            LocalTasksCompanion(
              status: Value(
                action == ActiveTaskSwitchAction.finishCurrent
                    ? 'completed'
                    : 'paused',
              ),
              activeDurationMs: Value(previousActiveMs),
              actualFinish: action == ActiveTaskSwitchAction.finishCurrent
                  ? Value(now)
                  : const Value.absent(),
              progress: action == ActiveTaskSwitchAction.finishCurrent
                  ? const Value(1)
                  : const Value.absent(),
              updatedAt: Value(now),
            ),
          );
      await (database.update(database.localTasks)..where(
            (row) =>
                row.id.equals(selectedTask.id) & row.userId.equals(_userId),
          ))
          .write(
            LocalTasksCompanion(
              status: const Value('in_progress'),
              actualStart: Value(selectedTask.actualStart ?? now),
              updatedAt: Value(now),
            ),
          );
      await (database.update(database.localRuntimeStates)..where(
            (row) => row.id.equals(_runtimeId) & row.userId.equals(_userId),
          ))
          .write(
            LocalRuntimeStatesCompanion(
              activeTaskId: Value(selectedTask.id),
              sessionId: Value(newSessionId),
              state: const Value('running'),
              segmentStartedAt: Value(now),
              accumulatedActiveMs: const Value(0),
              accumulatedPausedMs: const Value(0),
              revision: Value(runtime.revision + 1),
              updatedAt: Value(now),
              lastCommandId: Value(command.commandId),
            ),
          );
      await _recordInterruption(
        sessionId: runtime.sessionId,
        taskId: previousTask.id,
        targetTaskId: selectedTask.id,
        startedAt: now,
      );
      await _queueRuntimeSwitch(
        command: command,
        newSessionId: newSessionId,
        task: selectedTask,
        expectedRuntime: runtime,
        action: action,
        now: now,
      );
    });
  }

  Future<void> pause(LocalTask task) =>
      _serializeExecutionTransition(() => _pause(task));

  Future<void> _pause(LocalTask task) async {
    await database.transaction(() async {
      final currentTask = await getTask(task.id);
      if (currentTask == null) return;
      final runtime = await getRuntime();
      if (runtime == null ||
          runtime.sessionId == null ||
          runtime.activeTaskId != currentTask.id ||
          runtime.state != 'running') {
        return;
      }
      final now = DateTime.now().toUtc();
      final elapsed = _recordableSegmentMs(currentTask, runtime, now);
      final recorded = runtime.accumulatedActiveMs + elapsed;
      final command = await _newRuntimeCommandIdentity();
      final changed =
          await (database.update(database.localRuntimeStates)..where(
                (row) =>
                    row.id.equals(_runtimeId) &
                    row.userId.equals(_userId) &
                    row.activeTaskId.equals(currentTask.id) &
                    row.state.equals('running') &
                    row.revision.equals(runtime.revision),
              ))
              .write(
                LocalRuntimeStatesCompanion(
                  state: const Value('paused'),
                  segmentStartedAt: const Value(null),
                  accumulatedActiveMs: Value(recorded),
                  revision: Value(runtime.revision + 1),
                  updatedAt: Value(now),
                  lastCommandId: Value(command.commandId),
                ),
              );
      if (changed != 1) return;
      await changeStatus(currentTask, 'paused', activeDurationMs: recorded);
      await _updateExecutionSession(
        runtime,
        state: 'paused',
        now: now,
        accumulatedActiveMs: recorded,
      );
      await _queueRuntimeTransition(
        command: command,
        sessionId: runtime.sessionId!,
        task: currentTask,
        action: 'pause',
        runtimeRevision: runtime.revision,
        now: now,
      );
    });
  }

  Future<void> resume(LocalTask task) =>
      _serializeExecutionTransition(() => _resume(task));

  Future<void> _resume(LocalTask task) async {
    await database.transaction(() async {
      final currentTask = await getTask(task.id);
      if (currentTask == null) return;
      final now = DateTime.now().toUtc();
      final runtime = await getRuntime();
      // Resume always addresses the exact canonical paused session.  It must
      // never turn a stale task card into a request to start another task.
      if (runtime == null ||
          runtime.sessionId == null ||
          runtime.activeTaskId != currentTask.id ||
          runtime.state != 'paused') {
        return;
      }
      final sessionId = runtime.sessionId!;
      final command = await _newRuntimeCommandIdentity();
      final changed =
          await (database.update(database.localRuntimeStates)..where(
                (row) =>
                    row.id.equals(_runtimeId) &
                    row.userId.equals(_userId) &
                    row.activeTaskId.equals(currentTask.id) &
                    row.state.equals('paused') &
                    row.revision.equals(runtime.revision),
              ))
              .write(
                LocalRuntimeStatesCompanion(
                  state: const Value('running'),
                  segmentStartedAt: Value(now),
                  revision: Value(runtime.revision + 1),
                  updatedAt: Value(now),
                  lastCommandId: Value(command.commandId),
                ),
              );
      if (changed != 1) return;
      await changeStatus(currentTask, 'in_progress');
      await _updateExecutionSession(runtime, state: 'running', now: now);
      await _queueRuntimeTransition(
        command: command,
        sessionId: sessionId,
        task: currentTask,
        action: 'resume',
        runtimeRevision: runtime.revision,
        now: now,
      );
    });
  }

  Future<void> startBreak(LocalTask task) =>
      _serializeExecutionTransition(() => _startBreak(task));

  Future<void> _startBreak(LocalTask task) async {
    await database.transaction(() async {
      final currentTask = await getTask(task.id);
      if (currentTask == null || currentTask.executionMode != 'pomodoro') {
        return;
      }
      final runtime = await getRuntime();
      if (runtime == null ||
          runtime.activeTaskId != currentTask.id ||
          runtime.state != 'running') {
        return;
      }
      // An extension belongs to one break only. Clearing any completed
      // break's extension before the next one starts prevents a previous
      // five-minute choice from silently lengthening every later break.
      await _clearActiveBreakExtension(currentTask);
      final now = DateTime.now().toUtc();
      // A delayed notification action must never turn one 25-minute focus
      // interval into an hour of focused work. Raw wall time is capped at the
      // remaining configured focus interval before the boundary is saved.
      final elapsed = _recordableSegmentMs(currentTask, runtime, now);
      final recorded = runtime.accumulatedActiveMs + elapsed;
      final command = await _newRuntimeCommandIdentity();
      final changed =
          await (database.update(database.localRuntimeStates)..where(
                (row) =>
                    row.id.equals(_runtimeId) &
                    row.userId.equals(_userId) &
                    row.activeTaskId.equals(currentTask.id) &
                    row.state.equals('running') &
                    row.revision.equals(runtime.revision),
              ))
              .write(
                LocalRuntimeStatesCompanion(
                  state: const Value('break'),
                  segmentStartedAt: Value(now),
                  accumulatedActiveMs: Value(recorded),
                  revision: Value(runtime.revision + 1),
                  updatedAt: Value(now),
                  lastCommandId: Value(command.commandId),
                ),
              );
      if (changed != 1) return;
      await _updateExecutionSession(
        runtime,
        state: 'break',
        now: now,
        accumulatedActiveMs: recorded,
      );
      await _queueRuntimeTransition(
        command: command,
        sessionId: runtime.sessionId!,
        task: currentTask,
        action: 'start_break',
        runtimeRevision: runtime.revision,
        now: now,
      );
    });
  }

  Future<void> finishBreak(LocalTask task) =>
      _serializeExecutionTransition(() => _finishBreak(task));

  Future<void> _finishBreak(LocalTask task) async {
    await database.transaction(() async {
      final currentTask = await getTask(task.id);
      if (currentTask == null) return;
      final runtime = await getRuntime();
      if (runtime == null ||
          runtime.activeTaskId != currentTask.id ||
          runtime.state != 'break') {
        return;
      }
      final now = DateTime.now().toUtc();
      final command = await _newRuntimeCommandIdentity();
      final changed =
          await (database.update(database.localRuntimeStates)..where(
                (row) =>
                    row.id.equals(_runtimeId) &
                    row.userId.equals(_userId) &
                    row.activeTaskId.equals(currentTask.id) &
                    row.state.equals('break') &
                    row.revision.equals(runtime.revision),
              ))
              .write(
                LocalRuntimeStatesCompanion(
                  state: const Value('running'),
                  segmentStartedAt: Value(now),
                  revision: Value(runtime.revision + 1),
                  updatedAt: Value(now),
                  lastCommandId: Value(command.commandId),
                ),
              );
      if (changed != 1) return;
      await _updateExecutionSession(runtime, state: 'running', now: now);
      await _queueRuntimeTransition(
        command: command,
        sessionId: runtime.sessionId!,
        task: currentTask,
        action: 'finish_break',
        runtimeRevision: runtime.revision,
        now: now,
      );
      await _clearActiveBreakExtension(currentTask);
    });
  }

  /// Skips the break offered at a completed focus boundary in one durable
  /// runtime transition. The server verifies the same expected revision and
  /// focus boundary, so another device can never observe a synthetic
  /// `start_break` followed by a separate `finish_break`.
  Future<bool> skipOfferedBreak(LocalTask task) =>
      _serializeExecutionTransition(() => _skipOfferedBreak(task));

  Future<bool> _skipOfferedBreak(LocalTask task) async {
    return database.transaction(() async {
      final currentTask = await getTask(task.id);
      if (currentTask == null || currentTask.executionMode != 'pomodoro') {
        return false;
      }
      final runtime = await getRuntime();
      if (runtime == null ||
          runtime.sessionId == null ||
          runtime.activeTaskId != currentTask.id ||
          runtime.state != 'running' ||
          runtime.segmentStartedAt == null) {
        return false;
      }
      final now = DateTime.now().toUtc();
      final rawElapsed = now
          .difference(runtime.segmentStartedAt!.toUtc())
          .inMilliseconds;
      final recordable = _recordableSegmentMs(currentTask, runtime, now);
      // Skip break is valid only after the current configured focus interval
      // has reached its boundary. Do not use it as an early focus restart.
      if (rawElapsed < recordable) return false;

      final recorded = runtime.accumulatedActiveMs + recordable;
      final command = await _newRuntimeCommandIdentity();
      final changed =
          await (database.update(database.localRuntimeStates)..where(
                (row) =>
                    row.id.equals(_runtimeId) &
                    row.userId.equals(_userId) &
                    row.activeTaskId.equals(currentTask.id) &
                    row.state.equals('running') &
                    row.revision.equals(runtime.revision),
              ))
              .write(
                LocalRuntimeStatesCompanion(
                  state: const Value('running'),
                  segmentStartedAt: Value(now),
                  accumulatedActiveMs: Value(recorded),
                  revision: Value(runtime.revision + 1),
                  updatedAt: Value(now),
                  lastCommandId: Value(command.commandId),
                ),
              );
      if (changed != 1) return false;
      await _updateExecutionSession(
        runtime,
        state: 'running',
        now: now,
        accumulatedActiveMs: recorded,
      );
      await _queueRuntimeTransition(
        command: command,
        sessionId: runtime.sessionId!,
        task: currentTask,
        action: 'skip_break',
        runtimeRevision: runtime.revision,
        now: now,
      );
      return true;
    });
  }

  /// Extends the current shared break. The extension is task configuration
  /// with a narrowly-scoped lifetime so it is synchronized like any other
  /// task edit, rerenders on every device, and is cleared when that break
  /// ends. It is not a device-only alarm re-schedule.
  Future<void> extendCurrentBreak(
    LocalTask task, {
    Duration extension = const Duration(minutes: 5),
  }) => _serializeExecutionTransition(
    () => _extendCurrentBreak(task, extension: extension),
  );

  Future<void> _extendCurrentBreak(
    LocalTask task, {
    required Duration extension,
  }) async {
    final runtime = await getRuntime();
    if (runtime == null ||
        runtime.activeTaskId != task.id ||
        runtime.state != 'break') {
      return;
    }
    final latest = await getTask(task.id);
    if (latest == null) return;
    final configuration = _configuration(latest);
    final current =
        (configuration['active_break_extension_ms'] as num?)?.toInt() ?? 0;
    await updateConfiguration(latest, {
      ...configuration,
      'active_break_extension_ms': current + extension.inMilliseconds,
    });
  }

  /// Completes [task] as one local-first unit of work.
  ///
  /// The task, active runtime, execution-session boundary, final partial
  /// Pomodoro focus interval, completion snapshot, lifecycle evidence, and
  /// their outbox commands are committed in one Drift transaction. A crash
  /// can therefore leave either the complete pre-state or post-state, never
  /// a completed card with a still-running local timer.
  Future<TaskCompletionResult> complete(LocalTask task) {
    final pending = _completionInFlight[task.id];
    if (pending != null) return pending;
    late final Future<TaskCompletionResult> guarded;
    guarded = _serializeExecutionTransition(() => _completeTask(task))
        .whenComplete(() {
          if (identical(_completionInFlight[task.id], guarded)) {
            _completionInFlight.remove(task.id);
          }
        });
    _completionInFlight[task.id] = guarded;
    return guarded;
  }

  Future<TaskCompletionResult> _completeTask(LocalTask task) async {
    final latest = await getTask(task.id);
    if (latest == null) {
      throw StateError('Task ${task.id} is no longer available.');
    }
    if (latest.status == 'completed') {
      final existing = await _latestCompletionSnapshot(latest.id);
      if (existing != null && existing.status == 'undoable') {
        return _completionResult(existing, latest);
      }
      final completedAt = latest.actualFinish?.toUtc() ?? _clock();
      return TaskCompletionResult(
        taskId: latest.id,
        snapshotId: '',
        completedAt: completedAt,
        undoExpiresAt: completedAt,
      );
    }

    final now = _clock();
    final undoExpiresAt = now.add(completionUndoWindow);
    final runtime =
        await (database.select(database.localRuntimeStates)..where(
              (row) => row.id.equals(_runtimeId) & row.userId.equals(_userId),
            ))
            .getSingleOrNull();
    final activeRuntime =
        runtime?.sessionId != null && runtime?.activeTaskId == latest.id
        ? runtime
        : null;
    final session = activeRuntime?.sessionId == null
        ? null
        : await entities.get(activeRuntime!.sessionId!);
    final sessionData = session == null
        ? <String, Object?>{}
        : entities.decode(session);
    final runningElapsed = activeRuntime == null
        ? 0
        : _recordableSegmentMs(latest, activeRuntime, now);
    final totalActive = activeRuntime == null
        ? latest.activeDurationMs
        : activeRuntime.accumulatedActiveMs + runningElapsed;
    final snapshotId = _uuid.v4();
    final evidenceId = _uuid.v4();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final taskCommand = activeRuntime == null ? await _prepareCommand() : null;
    final runtimeCommand = activeRuntime == null
        ? null
        : await _prepareCommand();
    final snapshotCommand = await _prepareCommand();
    final evidenceCommand = await _prepareCommand();
    final shouldClosePartialFocus =
        activeRuntime?.state == 'running' &&
        activeRuntime?.segmentStartedAt != null &&
        latest.executionMode == 'pomodoro' &&
        runningElapsed > 0;
    final pomodoroBoundaryId = shouldClosePartialFocus ? _uuid.v4() : null;
    final pomodoroCommand = shouldClosePartialFocus
        ? await _prepareCommand()
        : null;
    late String effectiveTaskCommandId;

    await database.transaction(() async {
      if (activeRuntime == null && taskCommand != null) {
        effectiveTaskCommandId = await _enqueue(
          commandId: taskCommand.commandId,
          deviceId: deviceId,
          sequence: taskCommand.sequence,
          entityId: latest.id,
          commandType: 'update',
          baseRevision: latest.revision,
          payload: {
            'status': 'completed',
            'progress': 1,
            'actual_finish': now.toIso8601String(),
            'active_duration_ms': totalActive,
          },
          now: now,
        );
      } else {
        // The canonical execution RPC completes the task, session, runtime,
        // duration, progress, and history in one server transaction.
        effectiveTaskCommandId = runtimeCommand!.commandId;
      }
      await (database.update(database.localTasks)..where(
            (row) => row.id.equals(latest.id) & row.userId.equals(_userId),
          ))
          .write(
            LocalTasksCompanion(
              status: const Value('completed'),
              actualFinish: Value(now),
              activeDurationMs: Value(totalActive),
              progress: const Value(1),
              revision: Value(latest.revision + 1),
              updatedAt: Value(now),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(effectiveTaskCommandId),
            ),
          );

      if (activeRuntime != null && runtimeCommand != null) {
        await (database.update(database.localRuntimeStates)..where(
              (row) => row.id.equals(_runtimeId) & row.userId.equals(_userId),
            ))
            .write(
              LocalRuntimeStatesCompanion(
                activeTaskId: const Value(null),
                sessionId: const Value(null),
                state: const Value('idle'),
                segmentStartedAt: const Value(null),
                accumulatedActiveMs: Value(totalActive),
                revision: Value(activeRuntime.revision + 1),
                updatedAt: Value(now),
                lastCommandId: Value(runtimeCommand.commandId),
              ),
            );
        if (session != null) {
          final completedSessionData = <String, Object?>{
            ...sessionData,
            'state': 'completed',
            'active_segment_started_at': null,
            'finished_at': now.toIso8601String(),
            'accumulated_active_ms': totalActive,
          };
          await (database.update(database.localEntityRecords)..where(
                (row) => row.id.equals(session.id) & row.userId.equals(_userId),
              ))
              .write(
                LocalEntityRecordsCompanion(
                  status: const Value('completed'),
                  dataJson: Value(jsonEncode(completedSessionData)),
                  revision: Value(session.revision + 1),
                  updatedAt: Value(now),
                  updatedByDeviceId: Value(deviceId),
                  lastCommandId: Value(runtimeCommand.commandId),
                ),
              );
        }
        await _insertRuntimeTransitionCommand(
          command: runtimeCommand,
          deviceId: deviceId,
          sessionId: activeRuntime.sessionId!,
          task: latest,
          action: 'complete',
          runtimeRevision: activeRuntime.revision,
          now: now,
        );
      }

      if (shouldClosePartialFocus &&
          pomodoroBoundaryId != null &&
          pomodoroCommand != null &&
          activeRuntime != null) {
        final cycleNumber =
            ((sessionData['current_cycle'] as num?)?.toInt() ?? 0) + 1;
        await _insertSyncedEntity(
          id: pomodoroBoundaryId,
          command: pomodoroCommand,
          deviceId: deviceId,
          entityType: 'pomodoro_cycles',
          parentId: activeRuntime.sessionId,
          secondaryParentId: latest.id,
          title: 'Final partial focus interval',
          status: 'completed',
          data: {
            'session_id': activeRuntime.sessionId,
            'task_occurrence_id': latest.id,
            'cycle_number': cycleNumber,
            'focus_started_at': activeRuntime.segmentStartedAt!
                .toUtc()
                .toIso8601String(),
            'focus_ended_at': now.toIso8601String(),
            'focus_duration_ms': runningElapsed,
            'break_started_at': null,
            'break_ended_at': null,
            'break_duration_ms': 0,
            'skipped_break': true,
            'boundary_reason': 'task_completed',
          },
          syncPayload: {
            'session_id': activeRuntime.sessionId,
            'cycle_number': cycleNumber,
            'focus_started_at': activeRuntime.segmentStartedAt!
                .toUtc()
                .toIso8601String(),
            'focus_ended_at': now.toIso8601String(),
            'focus_duration_ms': runningElapsed,
            'break_started_at': null,
            'break_ended_at': null,
            'break_duration_ms': 0,
            'skipped_break': true,
            'data': {'boundary_reason': 'task_completed'},
          },
          now: now,
        );
      }

      final snapshotData = <String, Object?>{
        'task_id': latest.id,
        'completed_at': now.toIso8601String(),
        'undo_expires_at': undoExpiresAt.toIso8601String(),
        'task_completion_command_id': effectiveTaskCommandId,
        'runtime_completion_command_id': runtimeCommand?.commandId,
        'completion_evidence_command_id': evidenceCommand.commandId,
        'pomodoro_boundary_command_id': pomodoroCommand?.commandId,
        'previous_task_status': latest.status,
        'previous_task_progress': latest.progress,
        'previous_active_duration_ms': latest.activeDurationMs,
        'completed_active_duration_ms': totalActive,
        'previous_actual_start': latest.actualStart?.toUtc().toIso8601String(),
        'previous_actual_finish': latest.actualFinish
            ?.toUtc()
            .toIso8601String(),
        'runtime_was_active': activeRuntime != null,
        'previous_runtime_state': activeRuntime?.state,
        'previous_runtime_revision': activeRuntime?.revision,
        'previous_runtime_session_id': activeRuntime?.sessionId,
        'previous_runtime_accumulated_active_ms':
            activeRuntime?.accumulatedActiveMs,
        'previous_runtime_accumulated_paused_ms':
            activeRuntime?.accumulatedPausedMs,
        'previous_session_status': session?.status,
        'previous_session_revision': session?.revision,
        'previous_session_data': sessionData,
      };
      await _insertSyncedEntity(
        id: snapshotId,
        command: snapshotCommand,
        deviceId: deviceId,
        entityType: _completionSnapshotType,
        parentId: latest.id,
        secondaryParentId: activeRuntime?.sessionId,
        title: 'Task completion snapshot',
        status: 'undoable',
        data: {
          ...snapshotData,
          'evidence_type': 'completion_snapshot',
          'undo_status': 'undoable',
        },
        syncPayload: {
          'task_occurrence_id': latest.id,
          'evidence_type': 'completion_snapshot',
          'resource_id': null,
          'note': 'Task completion snapshot',
          'evidence_metadata': snapshotData,
          'data': {
            ...snapshotData,
            'evidence_type': 'completion_snapshot',
            'undo_status': 'undoable',
          },
        },
        now: now,
      );
      await _insertLifecycleEvidence(
        id: evidenceId,
        command: evidenceCommand,
        deviceId: deviceId,
        taskId: latest.id,
        sessionId: activeRuntime?.sessionId,
        eventType: 'completed',
        occurredAt: now,
        snapshotId: snapshotId,
        commandLineage: {
          'task': effectiveTaskCommandId,
          if (runtimeCommand != null) 'runtime': runtimeCommand.commandId,
          if (pomodoroCommand != null) 'pomodoro': pomodoroCommand.commandId,
        },
      );
    });

    await _recalculateLinkedRoadmap(latest.roadmapId);
    return TaskCompletionResult(
      taskId: latest.id,
      snapshotId: snapshotId,
      completedAt: now,
      undoExpiresAt: undoExpiresAt,
    );
  }

  /// Restores a just-completed task without reviving a stale timer lease.
  ///
  /// Active work is intentionally restored as paused. This preserves every
  /// recorded focus millisecond, does not count the Undo window as work, and
  /// cannot displace a task started on another device.
  Future<TaskRestorationOutcome> undoCompletion(
    String taskId, {
    String? snapshotId,
  }) async {
    final latest = await getTask(taskId);
    if (latest == null) return TaskRestorationOutcome.taskNotFound;
    if (latest.status != 'completed') {
      return TaskRestorationOutcome.notCompleted;
    }
    final snapshot = await _latestCompletionSnapshot(
      taskId,
      snapshotId: snapshotId,
    );
    if (snapshot == null) {
      return TaskRestorationOutcome.snapshotNotFound;
    }
    final data = _completionSnapshotData(snapshot);
    if ((data['undo_status'] as String? ?? snapshot.status) != 'undoable') {
      return TaskRestorationOutcome.snapshotNotFound;
    }
    final now = _clock();
    final undoExpiresAt = _instant(data['undo_expires_at']);
    if (undoExpiresAt == null || now.isAfter(undoExpiresAt)) {
      return TaskRestorationOutcome.undoExpired;
    }
    return _restoreCompletedTask(
      task: latest,
      snapshot: snapshot,
      snapshotData: data,
      eventType: 'completion_undone',
      now: now,
    );
  }

  /// Reopens a completed task after the short Undo window has elapsed.
  Future<TaskRestorationOutcome> reopen(
    String taskId, {
    String? snapshotId,
  }) async {
    final latest = await getTask(taskId);
    if (latest == null) return TaskRestorationOutcome.taskNotFound;
    if (latest.status != 'completed') {
      return TaskRestorationOutcome.notCompleted;
    }
    final snapshot = await _latestCompletionSnapshot(
      taskId,
      snapshotId: snapshotId,
    );
    final data = snapshot == null
        ? <String, Object?>{}
        : _completionSnapshotData(snapshot);
    final now = _clock();
    final undoExpiresAt =
        _instant(data['undo_expires_at']) ??
        latest.actualFinish?.toUtc().add(completionUndoWindow);
    if (undoExpiresAt != null && now.isBefore(undoExpiresAt)) {
      return TaskRestorationOutcome.reopenTooEarly;
    }
    return _restoreCompletedTask(
      task: latest,
      snapshot: snapshot,
      snapshotData: data,
      eventType: 'reopened',
      now: now,
    );
  }

  Future<TaskRestorationOutcome> _restoreCompletedTask({
    required LocalTask task,
    required LocalEntityRecord? snapshot,
    required Map<String, Object?> snapshotData,
    required String eventType,
    required DateTime now,
  }) async {
    final previousStatus =
        snapshotData['previous_task_status'] as String? ?? 'ready';
    final restoredStatus = switch (previousStatus) {
      'in_progress' || 'paused' => 'paused',
      'completed' || 'cancelled' => 'ready',
      _ => previousStatus,
    };
    final previousProgress =
        (snapshotData['previous_task_progress'] as num?)?.toDouble() ?? 0;
    final durationProgress = task.estimatedDurationMs > 0
        ? task.activeDurationMs / task.estimatedDurationMs
        : 0.0;
    final restoredProgress = previousProgress
        .clamp(0.0, 1.0)
        .toDouble()
        .clamp(durationProgress.clamp(0.0, 1.0), 1.0)
        .toDouble();
    final previousActualFinish = _instant(
      snapshotData['previous_actual_finish'],
    );
    final restoreSessionId =
        snapshotData['previous_runtime_session_id'] as String?;
    final deviceId = await DeviceIdentity.accountId(_userId);
    final runtimeRestoreCommand = await _prepareCommand();
    final evidenceCommand = await _prepareCommand();
    final snapshotCommand = snapshot == null ? null : await _prepareCommand();
    final evidenceId = _uuid.v4();
    late String effectiveTaskCommandId;

    await database.transaction(() async {
      effectiveTaskCommandId = runtimeRestoreCommand.commandId;
      await _insertRuntimeTransitionCommand(
        command: runtimeRestoreCommand,
        deviceId: deviceId,
        // An inactive completion has no execution session. The canonical RPC
        // still uses this stable UUID slot to enforce Undo/Reopen timing.
        sessionId: restoreSessionId ?? task.id,
        task: task,
        action: eventType == 'completion_undone' ? 'undo_complete' : 'reopen',
        runtimeRevision:
            (snapshotData['previous_runtime_revision'] as num?)?.toInt() ?? 0,
        now: now,
      );
      await (database.update(database.localTasks)..where(
            (row) => row.id.equals(task.id) & row.userId.equals(_userId),
          ))
          .write(
            LocalTasksCompanion(
              status: Value(restoredStatus),
              actualFinish: Value(previousActualFinish),
              activeDurationMs: Value(task.activeDurationMs),
              progress: Value(restoredProgress),
              revision: Value(task.revision + 1),
              updatedAt: Value(now),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(effectiveTaskCommandId),
            ),
          );
      if (snapshot != null) {
        final undoStatus = eventType == 'completion_undone'
            ? 'undone'
            : 'reopened';
        final updatedSnapshotData = <String, Object?>{
          ...snapshotData,
          'evidence_type': 'completion_snapshot',
          'undo_status': undoStatus,
          '${undoStatus}_at': now.toIso8601String(),
        };
        final payload = <String, Object?>{
          'task_occurrence_id': task.id,
          'evidence_type': 'completion_snapshot',
          'resource_id': null,
          'note': 'Task completion snapshot',
          'evidence_metadata': updatedSnapshotData,
          'data': updatedSnapshotData,
        };
        final pendingSnapshot =
            await (database.select(database.localOutboxCommands)
                  ..where(
                    (row) =>
                        row.userId.equals(_userId) &
                        row.entityType.equals(_completionSnapshotType) &
                        row.entityId.equals(snapshot.id) &
                        row.status.equals('pending'),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)])
                  ..limit(1))
                .getSingleOrNull();
        final effectiveSnapshotCommandId =
            pendingSnapshot?.commandId ?? snapshotCommand!.commandId;
        if (pendingSnapshot == null) {
          final preparedSnapshotCommand = snapshotCommand!;
          await database
              .into(database.localOutboxCommands)
              .insert(
                LocalOutboxCommandsCompanion.insert(
                  commandId: preparedSnapshotCommand.commandId,
                  userId: _userId,
                  deviceId: deviceId,
                  deviceSequence: preparedSnapshotCommand.sequence,
                  entityType: _completionSnapshotType,
                  entityId: snapshot.id,
                  commandType: 'update',
                  baseRevision: snapshot.revision,
                  payloadJson: jsonEncode(payload),
                  clientTimestamp: now,
                  createdAt: now,
                ),
              );
        } else {
          await (database.update(database.localOutboxCommands)..where(
                (row) => row.commandId.equals(pendingSnapshot.commandId),
              ))
              .write(
                LocalOutboxCommandsCompanion(
                  payloadJson: Value(jsonEncode(payload)),
                  clientTimestamp: Value(now),
                ),
              );
        }
        await (database.update(database.localEntityRecords)..where(
              (row) => row.id.equals(snapshot.id) & row.userId.equals(_userId),
            ))
            .write(
              LocalEntityRecordsCompanion(
                status: Value(undoStatus),
                dataJson: Value(jsonEncode(updatedSnapshotData)),
                revision: Value(snapshot.revision + 1),
                updatedAt: Value(now),
                updatedByDeviceId: Value(deviceId),
                lastCommandId: Value(effectiveSnapshotCommandId),
              ),
            );
      }
      await _insertLifecycleEvidence(
        id: evidenceId,
        command: evidenceCommand,
        deviceId: deviceId,
        taskId: task.id,
        sessionId: snapshotData['previous_runtime_session_id'] as String?,
        eventType: eventType,
        occurredAt: now,
        snapshotId: snapshot?.id,
        commandLineage: {
          'restored_task': effectiveTaskCommandId,
          'completed_task':
              snapshotData['task_completion_command_id'] as String?,
          'completed_runtime':
              snapshotData['runtime_completion_command_id'] as String?,
        },
      );
    });
    await _recalculateLinkedRoadmap(task.roadmapId);
    return TaskRestorationOutcome.restored;
  }

  Future<({String commandId, int sequence})> _prepareCommand() async {
    return (
      commandId: _uuid.v4(),
      sequence: await DeviceIdentity.nextSequence(_userId),
    );
  }

  Future<LocalEntityRecord?> _latestCompletionSnapshot(
    String taskId, {
    String? snapshotId,
  }) async {
    final query = database.select(database.localEntityRecords)
      ..where((row) {
        var predicate =
            row.userId.equals(_userId) &
            row.entityType.equals(_completionSnapshotType) &
            row.parentId.equals(taskId) &
            row.deletedAt.isNull();
        if (snapshotId != null && snapshotId.isNotEmpty) {
          predicate = predicate & row.id.equals(snapshotId);
        }
        return predicate;
      })
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(snapshotId == null || snapshotId.isEmpty ? 25 : 1);
    final records = await query.get();
    for (final record in records) {
      final data = _completionSnapshotData(record);
      if (data['evidence_type'] == 'completion_snapshot') return record;
    }
    return null;
  }

  TaskCompletionResult _completionResult(
    LocalEntityRecord snapshot,
    LocalTask task,
  ) {
    final data = _completionSnapshotData(snapshot);
    final completedAt =
        _instant(data['completed_at']) ??
        task.actualFinish?.toUtc() ??
        snapshot.createdAt.toUtc();
    final undoExpiresAt =
        _instant(data['undo_expires_at']) ??
        completedAt.add(completionUndoWindow);
    return TaskCompletionResult(
      taskId: task.id,
      snapshotId: snapshot.id,
      completedAt: completedAt,
      undoExpiresAt: undoExpiresAt,
    );
  }

  Future<void> _insertRuntimeTransitionCommand({
    required ({String commandId, int sequence}) command,
    required String deviceId,
    required String sessionId,
    required LocalTask task,
    required String action,
    required int runtimeRevision,
    required DateTime now,
  }) async {
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: command.commandId,
            userId: _userId,
            deviceId: deviceId,
            deviceSequence: command.sequence,
            entityType: 'execution_runtime',
            entityId: sessionId,
            commandType: action,
            baseRevision: runtimeRevision,
            payloadJson: jsonEncode({
              'action': action,
              'task_occurrence_id': task.id,
              'mode': task.executionMode,
            }),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  Future<void> _insertLifecycleEvidence({
    required String id,
    required ({String commandId, int sequence}) command,
    required String deviceId,
    required String taskId,
    required String? sessionId,
    required String eventType,
    required DateTime occurredAt,
    required String? snapshotId,
    required Map<String, Object?> commandLineage,
  }) {
    final metadata = <String, Object?>{
      'event_type': eventType,
      'occurred_at': occurredAt.toIso8601String(),
      'session_id': sessionId,
      'completion_snapshot_id': snapshotId,
      'command_lineage': commandLineage,
    };
    return _insertSyncedEntity(
      id: id,
      command: command,
      deviceId: deviceId,
      entityType: _completionEvidenceType,
      parentId: taskId,
      secondaryParentId: sessionId,
      title: eventType,
      status: 'active',
      data: {
        'task_occurrence_id': taskId,
        'evidence_type': 'lifecycle_event',
        'note': eventType,
        'evidence_metadata': metadata,
      },
      syncPayload: {
        'task_occurrence_id': taskId,
        'evidence_type': 'lifecycle_event',
        'note': eventType,
        'evidence_metadata': metadata,
        'data': <String, Object?>{},
      },
      now: occurredAt,
    );
  }

  Future<void> _insertSyncedEntity({
    required String id,
    required ({String commandId, int sequence}) command,
    required String deviceId,
    required String entityType,
    required String? parentId,
    required String? secondaryParentId,
    required String title,
    required String status,
    required Map<String, Object?> data,
    required Map<String, Object?> syncPayload,
    required DateTime now,
  }) async {
    await database
        .into(database.localEntityRecords)
        .insert(
          LocalEntityRecordsCompanion.insert(
            id: id,
            userId: _userId,
            entityType: entityType,
            parentId: Value(parentId),
            secondaryParentId: Value(secondaryParentId),
            title: Value(title),
            status: Value(status),
            dataJson: Value(jsonEncode(data)),
            createdAt: now,
            updatedAt: now,
            createdByDeviceId: Value(deviceId),
            updatedByDeviceId: Value(deviceId),
            lastCommandId: Value(command.commandId),
          ),
        );
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: command.commandId,
            userId: _userId,
            deviceId: deviceId,
            deviceSequence: command.sequence,
            entityType: entityType,
            entityId: id,
            commandType: 'create',
            baseRevision: 0,
            payloadJson: jsonEncode(syncPayload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  Future<void> _recalculateLinkedRoadmap(String? roadmapId) async {
    if (roadmapId == null || roadmapId.isEmpty) return;
    await recalculateRoadmap?.call(roadmapId);
  }

  DateTime? _instant(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  Map<String, Object?> _completionSnapshotData(LocalEntityRecord snapshot) {
    final decoded = entities.decode(snapshot);
    final remoteData = decoded['data'];
    final metadata = decoded['evidence_metadata'];
    return <String, Object?>{
      ...decoded,
      if (remoteData is Map) ...Map<String, Object?>.from(remoteData),
      if (metadata is Map) ...Map<String, Object?>.from(metadata),
    };
  }

  Future<String> _createExecutionSession(
    LocalTask task,
    DateTime now, {
    String initialState = 'running',
  }) {
    return entities.create(
      EntityRecordDraft(
        entityType: 'execution_sessions',
        parentId: task.id,
        title: '${task.title} session',
        status: initialState,
        data: {
          'task_occurrence_id': task.id,
          'mode': task.executionMode,
          'state': initialState,
          'started_at': now.toIso8601String(),
          'active_segment_started_at': initialState == 'running'
              ? now.toIso8601String()
              : null,
          'accumulated_active_ms': 0,
          'accumulated_paused_ms': 0,
          'accumulated_idle_ms': 0,
          'current_cycle': 0,
          'is_unscheduled': task.scheduledDate == null,
        },
        syncPayload: {
          'task_occurrence_id': task.id,
          'mode': task.executionMode,
          'state': initialState,
          'started_at': now.toIso8601String(),
          'finished_at': null,
          'active_segment_started_at': initialState == 'running'
              ? now.toIso8601String()
              : null,
          'accumulated_active_ms': 0,
          'accumulated_paused_ms': 0,
          'accumulated_idle_ms': 0,
          'current_pomodoro_segment':
              initialState == 'running' && task.executionMode == 'pomodoro'
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
      ..['current_pomodoro_segment'] = state == 'break'
          ? 'break'
          : state == 'running'
          ? 'focus'
          : data['current_pomodoro_segment']
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
        'current_pomodoro_segment': data['current_pomodoro_segment'],
      },
    );
  }

  Future<void> _cancelLocalExecutionSession(
    LocalRuntime runtime, {
    required DateTime now,
    required int accumulatedActiveMs,
  }) async {
    final sessionId = runtime.sessionId;
    if (sessionId == null) return;
    final session = await entities.get(sessionId);
    if (session == null) return;
    final data = entities.decode(session)
      ..['state'] = 'cancelled'
      ..['active_segment_started_at'] = null
      ..['finished_at'] = now.toIso8601String()
      ..['accumulated_active_ms'] = accumulatedActiveMs;
    await (database.update(database.localEntityRecords)..where(
          (row) =>
              row.id.equals(session.id) &
              row.userId.equals(_userId) &
              row.entityType.equals('execution_sessions'),
        ))
        .write(
          LocalEntityRecordsCompanion(
            status: const Value('cancelled'),
            dataJson: Value(jsonEncode(data)),
            updatedAt: Value(now),
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

  /// The server's `user_runtime_state` is the canonical timer state shared by
  /// Windows and Android.  Task/session rows retain history, while this one
  /// compact command is the authoritative start/pause/resume/break boundary.
  /// No timer tick is ever enqueued.
  Future<void> _queueRuntimeTransition({
    required _RuntimeCommandIdentity command,
    required String sessionId,
    required LocalTask task,
    required String action,
    required int runtimeRevision,
    required DateTime now,
  }) async {
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: command.commandId,
            userId: _userId,
            deviceId: command.deviceId,
            deviceSequence: command.deviceSequence,
            entityType: 'execution_runtime',
            entityId: sessionId,
            commandType: action,
            baseRevision: runtimeRevision,
            payloadJson: jsonEncode({
              'action': action,
              'task_occurrence_id': task.id,
              'mode': task.executionMode,
              'expected_runtime_revision': runtimeRevision,
            }),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  Future<void> _queueRuntimeSwitch({
    required _RuntimeCommandIdentity command,
    required String newSessionId,
    required LocalTask task,
    required LocalRuntime expectedRuntime,
    required ActiveTaskSwitchAction action,
    required DateTime now,
  }) async {
    await database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: command.commandId,
            userId: _userId,
            deviceId: command.deviceId,
            deviceSequence: command.deviceSequence,
            entityType: 'execution_runtime_switch',
            entityId: newSessionId,
            commandType: action == ActiveTaskSwitchAction.finishCurrent
                ? 'finish_current'
                : 'pause_current',
            baseRevision: expectedRuntime.revision,
            payloadJson: jsonEncode({
              'task_occurrence_id': task.id,
              'mode': task.executionMode,
              'expected_active_session_id': expectedRuntime.sessionId,
              'expected_active_task_id': expectedRuntime.activeTaskId,
              'expected_runtime_revision': expectedRuntime.revision,
              'current_task_action':
                  action == ActiveTaskSwitchAction.finishCurrent
                  ? 'finish'
                  : 'pause',
            }),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  Future<void> softDelete(LocalTask task) =>
      _serializeExecutionTransition(() => _softDelete(task));

  Future<void> _softDelete(LocalTask task) async {
    final now = _clock();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final sequence = await DeviceIdentity.nextSequence(_userId);
    final commandId = _uuid.v4();
    await database.transaction(() async {
      final latest = await getTask(task.id);
      if (latest == null) return;
      final runtime = await _runtimeQuery().getSingleOrNull();
      final ownsRuntime = runtime?.activeTaskId == latest.id;
      int? deletedActiveDurationMs;
      if (ownsRuntime && runtime != null) {
        final elapsed = _recordableSegmentMs(latest, runtime, now);
        final recorded = runtime.accumulatedActiveMs + elapsed;
        deletedActiveDurationMs = recorded;
        // The task tombstone is the canonical synchronized command. Its
        // server-side invariant closes the matching session and runtime.
        // Mirror that state immediately without inventing a second local
        // canonical revision or leaving an obsolete Start command to replay.
        await _cancelLocalExecutionSession(
          runtime,
          now: now,
          accumulatedActiveMs: recorded,
        );
        await _supersedePendingRuntimeCommands(runtime);
        await (database.update(database.localRuntimeStates)..where(
              (row) =>
                  row.id.equals(_runtimeId) &
                  row.userId.equals(_userId) &
                  row.activeTaskId.equals(latest.id) &
                  row.sessionId.equals(runtime.sessionId!) &
                  row.revision.equals(runtime.revision),
            ))
            .write(
              LocalRuntimeStatesCompanion(
                activeTaskId: const Value(null),
                sessionId: const Value(null),
                state: const Value('idle'),
                segmentStartedAt: const Value(null),
                accumulatedActiveMs: Value(recorded),
                updatedAt: Value(now),
              ),
            );
      }
      await (database.update(database.localTasks)..where(
            (row) => row.id.equals(latest.id) & row.userId.equals(_userId),
          ))
          .write(
            LocalTasksCompanion(
              deletedAt: Value(now),
              activeDurationMs: deletedActiveDurationMs != null
                  ? Value(deletedActiveDurationMs)
                  : const Value.absent(),
              revision: Value(latest.revision + 1),
              updatedAt: Value(now),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: latest.id,
        commandType: 'delete',
        baseRevision: latest.revision,
        payload: const {},
        now: now,
      );
    });
  }

  Future<String> _enqueue({
    required String commandId,
    required String deviceId,
    required int sequence,
    required String entityId,
    required String commandType,
    required int baseRevision,
    required Map<String, Object?> payload,
    required DateTime now,
  }) async {
    // A task can be started, paused, completed, or edited before its create
    // command has reached Supabase.  Collapse those local changes into the
    // original create so the task is uploaded once with its latest state.
    final pending =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.entityType.equals('task_occurrences') &
                    row.entityId.equals(entityId) &
                    row.status.equals('pending'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)]))
            .get();
    final pendingCreate = pending
        .where((row) => row.commandType == 'create')
        .firstOrNull;
    final pendingUpdate = pending
        .where((row) => row.commandType == 'update')
        .lastOrNull;

    if (commandType == 'update') {
      final existing = pendingCreate ?? pendingUpdate;
      if (existing != null) {
        final existingPayload = _decodePayload(existing.payloadJson);
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(existing.commandId))).write(
          LocalOutboxCommandsCompanion(
            payloadJson: Value(_encodeMergedPayload(existingPayload, payload)),
            clientTimestamp: Value(now),
          ),
        );
        return existing.commandId;
      }
    }

    if (commandType == 'delete') {
      if (pendingCreate != null) {
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(pendingCreate.commandId))).write(
          const LocalOutboxCommandsCompanion(
            status: Value('superseded'),
            lastError: Value(null),
          ),
        );
        return pendingCreate.commandId;
      }
      if (pendingUpdate != null) {
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(pendingUpdate.commandId))).write(
          LocalOutboxCommandsCompanion(
            commandType: const Value('delete'),
            payloadJson: const Value('{}'),
            clientTimestamp: Value(now),
          ),
        );
        return pendingUpdate.commandId;
      }
    }

    await database
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
    return commandId;
  }

  Map<String, Object?> _decodePayload(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{};
  }

  String _encodeMergedPayload(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final merged = <String, Object?>{...existing, ...incoming};
    final existingData = existing['data'];
    final incomingData = incoming['data'];
    if (existingData is Map || incomingData is Map) {
      merged['data'] = <String, Object?>{
        if (existingData is Map) ...Map<String, Object?>.from(existingData),
        if (incomingData is Map) ...Map<String, Object?>.from(incomingData),
      };
    }
    return jsonEncode(merged);
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  void _validateDraftDurationBounds(TaskDraft draft) {
    final configuration = draft.configuration;
    final minimumDuration = _configuredDuration(
      configuration['minimum_useful_duration_ms'],
    );
    final maximumDuration = _configuredDuration(
      configuration['maximum_intended_duration_ms'],
    );
    final violation = TaskSchedulePolicy.validateDurationBounds(
      plannedDuration: draft.effectiveEstimatedDuration,
      minimumUsefulDuration: minimumDuration,
      maximumIntendedDuration: maximumDuration,
    );
    if (violation == null) return;
    throw ArgumentError.value(
      violation.name,
      'duration bounds',
      'Task duration bounds must contain the estimated duration.',
    );
  }

  Duration _configuredDuration(Object? value) {
    final milliseconds = value is num
        ? value.toInt()
        : int.tryParse('${value ?? ''}') ?? 0;
    return Duration(milliseconds: milliseconds.clamp(0, 0x7fffffff).toInt());
  }

  int _databaseColorValue(int value) =>
      value > 0x7fffffff ? value - 0x100000000 : value;

  Map<String, Object?> _configuration(LocalTask task) {
    final value = jsonDecode(task.dataJson);
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  Future<void> _clearActiveBreakExtension(LocalTask task) async {
    final latest = await getTask(task.id);
    if (latest == null) return;
    final configuration = _configuration(latest);
    if (!configuration.containsKey('active_break_extension_ms')) return;
    final updated = {...configuration}..remove('active_break_extension_ms');
    await updateConfiguration(latest, updated);
  }

  int _recordableSegmentMs(LocalTask task, LocalRuntime runtime, DateTime now) {
    if (runtime.state != 'running' || runtime.segmentStartedAt == null) {
      return 0;
    }
    final elapsed = now.difference(runtime.segmentStartedAt!).inMilliseconds;
    if (task.executionMode != 'pomodoro') return elapsed;
    final focusMs = _pomodoroFocusDurationMs(task);
    if (focusMs <= 0) return elapsed;
    final alreadyInFocus = runtime.accumulatedActiveMs % focusMs;
    final remaining = focusMs - alreadyInFocus;
    return elapsed.clamp(0, remaining).toInt();
  }

  int _pomodoroFocusDurationMs(LocalTask task) {
    final configuration = _configuration(task);
    final configuredValue = configuration['pomodoro_focus_ms'];
    final legacyValue = configuration['pomodoro_focus_minutes'];
    final configuredMilliseconds = configuredValue is num
        ? configuredValue.toInt()
        : int.tryParse('${configuredValue ?? ''}');
    final legacyMinutes = legacyValue is num
        ? legacyValue.toInt()
        : int.tryParse('${legacyValue ?? ''}');
    return (configuredMilliseconds ??
            (legacyMinutes == null
                ? null
                : legacyMinutes * Duration.millisecondsPerMinute) ??
            const Duration(minutes: 25).inMilliseconds)
        .clamp(
          const Duration(minutes: 1).inMilliseconds,
          const Duration(hours: 24).inMilliseconds,
        )
        .toInt();
  }
}
