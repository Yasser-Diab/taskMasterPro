import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_service.dart';
import '../../sessions/domain/session_models.dart';
import '../domain/task_activity.dart';
import '../domain/task_category.dart';
import '../domain/task_execution_models.dart';
import '../domain/task_item.dart';
import '../domain/task_support_models.dart';
import 'task_local_store.dart';

class SessionControlClaim {
  const SessionControlClaim({
    required this.granted,
    required this.deviceId,
    this.controllingDeviceId,
    this.expiresAt,
  });

  final bool granted;
  final String deviceId;
  final String? controllingDeviceId;
  final DateTime? expiresAt;
}

class SessionControlledElsewhere implements Exception {
  const SessionControlledElsewhere(this.claim);

  final SessionControlClaim claim;

  @override
  String toString() => 'Task state changed on another device.';
}

class SessionCommandResult {
  const SessionCommandResult({
    required this.status,
    required this.revision,
    this.message,
    this.stage,
    this.sessionState,
    this.segmentId,
  });

  final String status;
  final int revision;
  final String? message;
  final String? stage;
  final String? sessionState;
  final String? segmentId;

  bool get applied => status == 'applied' || status == 'duplicate';

  factory SessionCommandResult.fromMap(Map<String, dynamic> map) {
    return SessionCommandResult(
      status: map['status']?.toString() ?? 'unknown',
      revision: _intValue(map['revision']),
      message: map['message']?.toString(),
      stage: map['stage']?.toString(),
      sessionState: map['session_state']?.toString(),
      segmentId: map['segment_id']?.toString(),
    );
  }
}

class TaskRepository {
  TaskRepository(this._supabaseService, {TaskLocalStore? localStore})
    : _localStore = localStore ?? TaskLocalStore();

  final SupabaseService _supabaseService;
  final TaskLocalStore _localStore;

  String? get currentUserId => _supabaseService.currentUser?.id;
  SupabaseClient? get clientOrNull => _supabaseService.clientOrNull;

  Future<String> loadDeviceId() => _localStore.loadDeviceId();

  Future<void> publishSyncEvent({
    required String entityType,
    required String entityId,
    required String eventType,
    int revision = 0,
    Map<String, Object?> payload = const {},
  }) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (client == null || user == null) return;
    try {
      await client.from('sync_events').insert({
        'user_id': user.id,
        'entity_type': entityType,
        'entity_id': entityId,
        'event_type': eventType,
        'revision': revision,
        'device_id': await _localStore.loadDeviceId(),
        'payload': payload,
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object catch (error) {
      if (kDebugMode && !_isConnectivityError(error)) {
        debugPrint('SYNC EVENT PUBLISH FAILED: $error');
      }
    }
  }

  Future<SessionControlClaim> claimSessionControl({
    required String sessionId,
    required String taskId,
    bool takeOver = false,
  }) async {
    final user = _supabaseService.currentUser;
    if (user == null) throw StateError('You need to sign in first.');
    final deviceId = await _localStore.loadDeviceId();
    return SessionControlClaim(granted: true, deviceId: deviceId);
  }

  Future<void> releaseSessionControl(String sessionId) async {
    return;
  }

  Future<void> renewSessionControl({
    required String sessionId,
    required String taskId,
  }) async {
    return;
  }

  Future<SessionCommandResult?> applySessionCommand({
    String? commandId,
    required String sessionId,
    required String taskId,
    required int expectedRevision,
    required String commandType,
    required DateTime occurredAt,
    Map<String, Object?> payload = const {},
  }) async {
    final user = _supabaseService.currentUser;
    final client = _supabaseService.clientOrNull;
    if (user == null || client == null) return null;
    final deviceId = await _localStore.loadDeviceId();
    try {
      final result = await client.rpc(
        'apply_session_command',
        params: {
          'p_command_id': commandId ?? const Uuid().v4(),
          'p_session_id': sessionId,
          'p_task_id': taskId,
          'p_expected_revision': expectedRevision,
          'p_command_type': commandType,
          'p_device_id': deviceId,
          'p_client_occurred_at': occurredAt.toUtc().toIso8601String(),
          'p_payload': payload,
        },
      );
      final map = result is Map
          ? Map<String, dynamic>.from(result)
          : const <String, dynamic>{};
      return SessionCommandResult.fromMap(map);
    } on Object catch (error) {
      if (kDebugMode && !_isConnectivityError(error)) {
        debugPrint('SESSION COMMAND DEFERRED: $error');
      }
      return null;
    }
  }

  Future<void> recordWidgetActionEvent({
    required String commandType,
    required DateTime localOccurredAt,
    String widgetKind = 'active_timer',
    String? sessionId,
    String? taskId,
    String status = 'applied',
    Map<String, Object?> payload = const {},
    String? errorMessage,
  }) async {
    final user = _supabaseService.currentUser;
    if (user == null) return;
    final client = _supabaseService.clientOrNull;
    final deviceId = await _localStore.loadDeviceId();
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    final row = <String, dynamic>{
      'id': id,
      'user_id': user.id,
      'device_id': deviceId,
      'widget_kind': widgetKind,
      'command_type': commandType,
      'session_id': sessionId,
      'task_id': taskId,
      'local_occurred_at': localOccurredAt.toUtc().toIso8601String(),
      'app_received_at': now.toIso8601String(),
      'applied_at': status == 'applied' ? now.toIso8601String() : null,
      'status': status,
      'payload': payload,
      'error_message': errorMessage,
      'revision': now.millisecondsSinceEpoch,
    };
    await _localStore.upsertRow(user.id, 'widget_action_events', id, row);
    final operation = await _queueTaskOperation(
      user.id,
      'widget_action_event',
      row,
    );
    if (client == null) return;
    try {
      await client.from('widget_action_events').upsert(row, onConflict: 'id');
      await _localStore.removeOperation(user.id, operation.id);
      final syncPayload = <String, Object?>{
        'widget_kind': widgetKind,
        'command_type': commandType,
      };
      if (taskId != null) syncPayload['task_id'] = taskId;
      if (sessionId != null) syncPayload['session_id'] = sessionId;
      unawaited(
        publishSyncEvent(
          entityType: 'widget',
          entityId: id,
          eventType: 'widget_action_applied',
          revision: now.millisecondsSinceEpoch,
          payload: syncPayload,
        ),
      );
    } on Object catch (error) {
      if (_isConnectivityError(error)) return;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<List<TaskItem>> loadLocalTasks({bool deleted = false}) async {
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final snapshot = await _localStore.load(user.id);
    return snapshot.tasks
        .where(
          (task) => deleted ? task.deletedAt != null : task.deletedAt == null,
        )
        .toList(growable: false);
  }

  Future<List<TaskItem>> loadTasks() async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return const [];
    }
    if (client == null) {
      final snapshot = await _localStore.load(user.id);
      return snapshot.tasks.where((task) => task.deletedAt == null).toList();
    }

    try {
      final rows = await client
          .from('tasks')
          .select()
          .eq('user_id', user.id)
          .eq('is_recurring_template', false)
          .isFilter('deleted_at', null)
          .isFilter('archived_at', null)
          .order('priority_rank')
          .order('scheduled_start_at', nullsFirst: false)
          .order('due_date', nullsFirst: false)
          .limit(1000);

      final parsed = _parseTaskRows(rows);
      await _replaceCachedPartition(user.id, parsed, deleted: false);
      return parsed;
    } on Object catch (error) {
      if (!_isConnectivityError(error)) return const [];
      final snapshot = await _localStore.load(user.id);
      return snapshot.tasks
          .where((task) => task.deletedAt == null && task.archivedAt == null)
          .toList();
    }
  }

  Future<List<TaskItem>> loadDeletedTasks() async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return const [];
    }
    if (client == null) {
      final snapshot = await _localStore.load(user.id);
      return snapshot.tasks.where((task) => task.deletedAt != null).toList();
    }

    try {
      final rows = await client
          .from('tasks')
          .select()
          .not('deleted_at', 'is', null)
          .order('deleted_at', ascending: false)
          .limit(100);

      final parsed = _parseTaskRows(rows);
      await _replaceCachedPartition(user.id, parsed, deleted: true);
      return parsed;
    } on Object catch (error) {
      if (!_isConnectivityError(error)) return const [];
      final snapshot = await _localStore.load(user.id);
      return snapshot.tasks.where((task) => task.deletedAt != null).toList();
    }
  }

  List<TaskItem> _parseTaskRows(Object? rows) {
    if (rows is! List) {
      return const [];
    }
    final tasks = <TaskItem>[];
    for (final row in rows) {
      if (row is! Map) {
        continue;
      }
      final typedRow = Map<String, dynamic>.from(row);
      try {
        tasks.add(TaskItem.fromMap(typedRow));
      } on Object catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('TASK PARSE FAILED');
          debugPrint('ROW: $typedRow');
          debugPrint('ERROR: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }
    return tasks;
  }

  Future<List<TaskCategory>> loadCategories() async {
    final client = _supabaseService.clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      return const [];
    }

    try {
      final rows = await client
          .from('categories')
          .select('name,color_seed')
          .isFilter('deleted_at', null)
          .order('sort_order')
          .order('name');
      return rows.map<TaskCategory>((row) {
        return TaskCategory(
          name: row['name']?.toString() ?? 'Personal',
          colorSeed: _colorFromStorage(row['color_seed']?.toString()),
        );
      }).toList();
    } on Object {
      return const [];
    }
  }

  Future<TaskEditorLinks> loadTaskEditorLinks() async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return const TaskEditorLinks();
    }

    final projects = <TaskProjectOption>[];
    final roadmaps = <TaskRoadmapOption>[];
    final phases = <TaskRoadmapPhaseOption>[];
    final milestones = <TaskMilestoneOption>[];

    try {
      final rows = await client
          .from('projects')
          .select('id,name')
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .order('name');
      projects.addAll(
        rows.map(
          (row) => TaskProjectOption(
            id: row['id'].toString(),
            name: row['name']?.toString() ?? '',
          ),
        ),
      );
    } on Object catch (error) {
      if (kDebugMode) debugPrint('PROJECT OPTIONS FAILED: $error');
    }

    try {
      final rows = await client
          .from('roadmaps')
          .select('id,title')
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .order('created_at');
      roadmaps.addAll(
        rows.map(
          (row) => TaskRoadmapOption(
            id: row['id'].toString(),
            title: row['title']?.toString() ?? '',
          ),
        ),
      );
    } on Object catch (error) {
      if (kDebugMode) debugPrint('ROADMAP OPTIONS FAILED: $error');
    }

    try {
      final rows = await client
          .from('roadmap_phases')
          .select('id,roadmap_id,phase_order,phase_number,objective')
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .order('phase_order');
      for (final row in rows) {
        final roadmapId = row['roadmap_id']?.toString();
        if (roadmapId == null || roadmapId.isEmpty) continue;
        phases.add(
          TaskRoadmapPhaseOption(
            id: row['id'].toString(),
            roadmapId: roadmapId,
            title: row['objective']?.toString() ?? '',
            phaseOrder: _intValue(
              row['phase_order'] ?? row['phase_number'],
              fallback: phases.length + 1,
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('ROADMAP PHASE OPTIONS FAILED: $error');
    }

    try {
      final rows = await client
          .from('roadmap_items')
          .select('id,roadmap_id,phase_id,topic,item_type')
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .order('planned_start');
      for (final row in rows) {
        final roadmapId = row['roadmap_id']?.toString();
        if (roadmapId == null || roadmapId.isEmpty) continue;
        milestones.add(
          TaskMilestoneOption(
            id: row['id'].toString(),
            roadmapId: roadmapId,
            phaseId: row['phase_id']?.toString(),
            title: row['topic']?.toString() ?? '',
          ),
        );
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('MILESTONE OPTIONS FAILED: $error');
    }

    return TaskEditorLinks(
      projects: projects,
      roadmaps: roadmaps,
      phases: phases,
      milestones: milestones,
    );
  }

  Future<TaskItem> createTask(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return task;
    }

    final insertValues = task.toInsertMap()..remove('default_resource_id');
    final payload = {'id': task.id, 'user_id': user.id, ...insertValues};
    await _localStore.upsertTask(user.id, task);
    final operation = await _queueTaskOperation(user.id, 'create', payload);
    if (client == null) return task;
    try {
      final row = await client
          .from('tasks')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();

      final saved = TaskItem.fromMap(row);
      await _localStore.upsertTask(user.id, saved);
      await _localStore.removeOperation(user.id, operation.id);
      await _createRecurrenceIfNeeded(client, saved, task);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: saved.id,
          eventType: 'task_created',
          revision: saved.updatedAt.millisecondsSinceEpoch,
        ),
      );
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return task;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<TaskItem> addTask(TaskItem task) => createTask(task);

  Future<TaskItem> updateTask(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return task;
    }
    final payload = {'id': task.id, ...task.toInsertMap()};
    await _localStore.upsertTask(user.id, task);
    final operation = await _queueTaskOperation(user.id, 'update', payload);
    if (client == null) return task;
    try {
      final row = await client
          .from('tasks')
          .update(task.toInsertMap())
          .eq('id', task.id)
          .eq('user_id', user.id)
          .select()
          .single();

      final saved = TaskItem.fromMap(row);
      await _localStore.upsertTask(user.id, saved);
      await _localStore.removeOperation(user.id, operation.id);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: saved.id,
          eventType: 'task_updated',
          revision: saved.updatedAt.millisecondsSinceEpoch,
        ),
      );
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return task;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<TaskItem> saveTaskBundle({
    required TaskItem task,
    required List<TaskResource> resources,
    required List<TaskReminder> reminders,
    RecurrenceEditScope scope = RecurrenceEditScope.occurrence,
  }) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return task;
    }

    try {
      final result = await client.rpc(
        'edit_task_with_scope',
        params: {
          'target_task_id': task.id,
          'edit_scope': scope.storageValue,
          'task_values': task.toInsertMap(),
          'resource_values': [
            for (final resource in resources) resource.toMap(userId: user.id),
          ],
          'reminder_values': [
            for (final reminder in reminders) reminder.toMap(userId: user.id),
          ],
        },
      );
      if (result is Map) {
        final taskRow = result['task'];
        if (taskRow is Map) {
          return TaskItem.fromMap(Map<String, dynamic>.from(taskRow));
        }
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('BUNDLED TASK EDIT FALLBACK: $error');
      }
    }

    final savedWithoutResource = await updateTask(
      task.copyWith(clearDefaultResource: true),
    );
    await replaceTaskResources(task.id, resources);
    await replaceTaskReminders(task.id, reminders);
    if (task.defaultResourceId == null) return savedWithoutResource;
    return updateTask(task);
  }

  Future<List<TaskResource>> loadTaskResources(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final taskIds = <String>{task.id};
    final seriesId = task.seriesTaskId;
    if (seriesId != null && seriesId.isNotEmpty) {
      taskIds.add(seriesId);
    }
    final localRows = await _localStore.loadRows(user.id, 'task_resources');
    final local = localRows
        .where((row) => taskIds.contains(row['task_id']?.toString()))
        .map(TaskResource.fromMap)
        .toList(growable: false);
    if (client == null) return _resolveInheritedResources(task, local);
    try {
      final rows = await client
          .from('task_resources')
          .select()
          .eq('user_id', user.id)
          .inFilter('task_id', taskIds.toList())
          .isFilter('deleted_at', null)
          .order('sort_order');
      final parsed = rows
          .map<TaskResource>((row) => TaskResource.fromMap(row))
          .toList();
      await _localStore.replaceRowsWhere(
        user.id,
        'task_resources',
        'task_id',
        taskIds,
        [for (final resource in parsed) resource.toMap(userId: user.id)],
      );
      return _resolveInheritedResources(task, parsed);
    } on Object {
      return _resolveInheritedResources(task, local);
    }
  }

  List<TaskResource> _resolveInheritedResources(
    TaskItem task,
    List<TaskResource> resources,
  ) {
    final seriesId = task.seriesTaskId;
    if (seriesId == null || seriesId.isEmpty) {
      return resources.where((resource) => !resource.isHidden).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    final overrides = resources
        .where((resource) => resource.taskId == task.id)
        .toList();
    final overriddenIds = overrides
        .map((resource) => resource.seriesResourceId)
        .whereType<String>()
        .toSet();
    final inherited = resources.where(
      (resource) =>
          resource.taskId == seriesId && !overriddenIds.contains(resource.id),
    );
    return [
      ...overrides.where((resource) => !resource.isHidden),
      ...inherited.where((resource) => !resource.isHidden),
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<String?> findTaskIdForResourceDomain(String domain) async {
    final user = _supabaseService.currentUser;
    if (user == null) return null;
    final normalized = domain.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final local = await _localStore.loadRows(user.id, 'task_resources');
    for (final row in local) {
      if (row['normalized_domain']?.toString() == normalized &&
          row['deleted_at'] == null) {
        return row['task_id']?.toString();
      }
    }
    final client = _supabaseService.clientOrNull;
    if (client == null) return null;
    try {
      final row = await client
          .from('task_resources')
          .select('task_id')
          .eq('user_id', user.id)
          .eq('normalized_domain', normalized)
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['task_id']?.toString();
    } on Object {
      return null;
    }
  }

  Future<void> replaceTaskResources(
    String taskId,
    List<TaskResource> resources,
  ) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return;
    }
    final rows = [
      for (var index = 0; index < resources.length; index += 1)
        resources[index].copyWith(sortOrder: index).toMap(userId: user.id),
    ];
    await _localStore.replaceRowsWhere(user.id, 'task_resources', 'task_id', {
      taskId,
    }, rows);
    if (client == null) {
      await _queueTaskOperation(user.id, 'resources', {
        'task_id': taskId,
        'rows': rows,
      });
      return;
    }
    try {
      await client
          .from('task_resources')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('task_id', taskId)
          .eq('user_id', user.id)
          .isFilter('deleted_at', null);
      if (rows.isNotEmpty) await client.from('task_resources').upsert(rows);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: taskId,
          eventType: 'resources_changed',
          payload: {'resource_count': rows.length},
        ),
      );
    } on Object catch (error) {
      if (!_isConnectivityError(error)) rethrow;
      await _queueTaskOperation(user.id, 'resources', {
        'task_id': taskId,
        'rows': rows,
      });
    }
  }

  Future<List<WorkDemand>> loadWorkDemands(String taskId) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final localRows = await _localStore.loadRows(user.id, 'work_demands');
    final local =
        localRows
            .where((row) => row['task_id']?.toString() == taskId)
            .map(WorkDemand.fromMap)
            .where((item) => item.deletedAt == null)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (client == null) return local;
    try {
      final rows = await client
          .from('work_demands')
          .select()
          .eq('user_id', user.id)
          .eq('task_id', taskId)
          .isFilter('deleted_at', null)
          .order('position');
      final parsed = rows.map<WorkDemand>(WorkDemand.fromMap).toList();
      await _localStore.replaceRowsWhere(
        user.id,
        'work_demands',
        'task_id',
        {taskId},
        [for (final demand in parsed) demand.toMap(userId: user.id)],
      );
      return parsed;
    } on Object {
      return local;
    }
  }

  Future<WorkDemand> upsertWorkDemand(WorkDemand demand) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return demand;
    final payload = demand.toMap(userId: user.id);
    await _localStore.upsertRow(user.id, 'work_demands', demand.id, payload);
    final operation = await _queueTaskOperation(
      user.id,
      'work_demand',
      payload,
    );
    if (client == null) return demand;
    try {
      final row = await client
          .from('work_demands')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();
      await _localStore.removeOperation(user.id, operation.id);
      final saved = WorkDemand.fromMap(row);
      await _localStore.upsertRow(
        user.id,
        'work_demands',
        saved.id,
        saved.toMap(userId: user.id),
      );
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: saved.taskId,
          eventType: 'work_demands_changed',
          revision: saved.revision,
        ),
      );
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return demand;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<List<LearningCheckpoint>> loadLearningCheckpoints(
    String taskId,
  ) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final localRows = await _localStore.loadRows(
      user.id,
      'learning_checkpoints',
    );
    final local =
        localRows
            .where((row) => row['task_id']?.toString() == taskId)
            .map(LearningCheckpoint.fromMap)
            .where((item) => item.deletedAt == null)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (client == null) return local;
    try {
      final rows = await client
          .from('learning_checkpoints')
          .select()
          .eq('user_id', user.id)
          .eq('task_id', taskId)
          .isFilter('deleted_at', null)
          .order('position');
      final parsed = rows
          .map<LearningCheckpoint>(LearningCheckpoint.fromMap)
          .toList();
      await _localStore.replaceRowsWhere(
        user.id,
        'learning_checkpoints',
        'task_id',
        {taskId},
        [for (final checkpoint in parsed) checkpoint.toMap(userId: user.id)],
      );
      return parsed;
    } on Object {
      return local;
    }
  }

  Future<LearningCheckpoint> upsertLearningCheckpoint(
    LearningCheckpoint checkpoint,
  ) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return checkpoint;
    final payload = checkpoint.toMap(userId: user.id);
    await _localStore.upsertRow(
      user.id,
      'learning_checkpoints',
      checkpoint.id,
      payload,
    );
    final operation = await _queueTaskOperation(
      user.id,
      'learning_checkpoint',
      payload,
    );
    if (client == null) return checkpoint;
    try {
      final row = await client
          .from('learning_checkpoints')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();
      await _localStore.removeOperation(user.id, operation.id);
      final saved = LearningCheckpoint.fromMap(row);
      await _localStore.upsertRow(
        user.id,
        'learning_checkpoints',
        saved.id,
        saved.toMap(userId: user.id),
      );
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: saved.taskId,
          eventType: 'learning_checkpoints_changed',
          revision: saved.revision,
        ),
      );
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return checkpoint;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<List<TaskReminder>> loadTaskReminders(String taskId) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final localRows = await _localStore.loadRows(user.id, 'task_reminders');
    final local = localRows
        .where(
          (row) =>
              row['task_id']?.toString() == taskId &&
              row['status']?.toString() != 'cancelled',
        )
        .map(TaskReminder.fromMap)
        .toList(growable: false);
    if (client == null) return local;
    try {
      final rows = await client
          .from('task_reminders')
          .select()
          .eq('task_id', taskId)
          .eq('user_id', user.id)
          .not('status', 'eq', 'cancelled')
          .order('offset_minutes', ascending: false);
      final parsed = rows
          .map<TaskReminder>((row) => TaskReminder.fromMap(row))
          .toList();
      await _localStore.replaceRowsWhere(
        user.id,
        'task_reminders',
        'task_id',
        {taskId},
        [for (final reminder in parsed) reminder.toMap(userId: user.id)],
      );
      return parsed;
    } on Object {
      return local;
    }
  }

  Future<Map<String, List<TaskReminder>>> loadUpcomingReminders() async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return const {};
    }
    try {
      final rows = await client
          .from('task_reminders')
          .select()
          .eq('user_id', user.id)
          .inFilter('status', ['pending', 'scheduled', 'snoozed'])
          .or(
            'scheduled_at.gte.${DateTime.now().toUtc().toIso8601String()},snoozed_until.gte.${DateTime.now().toUtc().toIso8601String()},scheduled_at.is.null',
          )
          .limit(2000);
      final grouped = <String, List<TaskReminder>>{};
      for (final row in rows) {
        final reminder = TaskReminder.fromMap(row);
        grouped.putIfAbsent(reminder.taskId, () => []).add(reminder);
      }
      return grouped;
    } on Object {
      return const {};
    }
  }

  Future<void> replaceTaskReminders(
    String taskId,
    List<TaskReminder> reminders,
  ) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return;
    }
    final rows = [
      for (final reminder in reminders) reminder.toMap(userId: user.id),
    ];
    await _localStore.replaceRowsWhere(user.id, 'task_reminders', 'task_id', {
      taskId,
    }, rows);
    if (client == null) {
      await _queueTaskOperation(user.id, 'reminders', {
        'task_id': taskId,
        'rows': rows,
      });
      return;
    }
    try {
      await client
          .from('task_reminders')
          .update({
            'status': 'cancelled',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('task_id', taskId)
          .eq('user_id', user.id)
          .not('status', 'eq', 'cancelled');
      if (rows.isNotEmpty) await client.from('task_reminders').upsert(rows);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: taskId,
          eventType: 'reminders_changed',
          payload: {'reminder_count': rows.length},
        ),
      );
    } on Object catch (error) {
      if (!_isConnectivityError(error)) rethrow;
      await _queueTaskOperation(user.id, 'reminders', {
        'task_id': taskId,
        'rows': rows,
      });
    }
  }

  Future<void> skipOccurrence(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return;
    }
    await client.rpc(
      'skip_task_occurrence',
      params: {'target_task_id': task.id},
    );
  }

  Future<void> setRecurrenceState(TaskItem task, String action) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return;
    }
    await client.rpc(
      'set_task_recurrence_state',
      params: {'target_task_id': task.id, 'requested_action': action},
    );
  }

  Future<List<TaskUsageActivity>> loadTaskUsage(String taskId) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final localRows = await _localStore.loadRows(
      user.id,
      'task_activity_records',
    );
    final local = localRows
        .where(
          (row) =>
              row['task_id']?.toString() == taskId &&
              row['excluded_from_reports'] != true,
        )
        .map(TaskUsageActivity.fromMap)
        .toList(growable: false);
    if (client == null) return local;
    try {
      final rows = await client
          .from('task_activity_records')
          .select()
          .eq('task_id', taskId)
          .eq('user_id', user.id)
          .eq('excluded_from_reports', false)
          .order('started_at', ascending: false);
      final parsed = rows
          .map<TaskUsageActivity>((row) => TaskUsageActivity.fromMap(row))
          .toList();
      await _localStore.replaceRowsWhere(
        user.id,
        'task_activity_records',
        'task_id',
        {taskId},
        [for (final record in parsed) record.toMap(userId: user.id)],
      );
      return parsed;
    } on Object {
      return local;
    }
  }

  Future<void> upsertTaskUsage(List<TaskUsageActivity> records) async {
    if (records.isEmpty) return;
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return;
    }
    final rows = [for (final record in records) record.toMap(userId: user.id)];
    for (final row in rows) {
      await _localStore.upsertRow(
        user.id,
        'task_activity_records',
        row['id']!.toString(),
        row,
      );
    }
    if (client == null) {
      await _queueTaskOperation(user.id, 'usage', {'rows': rows});
      return;
    }
    try {
      await client.from('task_activity_records').upsert(rows);
      unawaited(
        publishSyncEvent(
          entityType: 'activity',
          entityId: records.first.taskId,
          eventType: 'activity_recorded',
          payload: {'record_count': rows.length},
        ),
      );
    } on Object catch (error) {
      if (!_isConnectivityError(error)) rethrow;
      await _queueTaskOperation(user.id, 'usage', {'rows': rows});
    }
  }

  Future<void> saveBrowserCheckpoint({
    required TaskItem task,
    required List<Map<String, dynamic>> tabs,
    required int selectedTab,
    required bool browserExpanded,
    required String browserMode,
    required double browserWidth,
    required int selectedPanel,
    String? sessionId,
  }) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await client
          .from('task_browser_tabs')
          .update({'closed_at': now, 'is_active': false, 'updated_at': now})
          .eq('user_id', user.id)
          .eq('task_id', task.id)
          .isFilter('closed_at', null);
      if (tabs.isNotEmpty) {
        await client.from('task_browser_tabs').upsert([
          for (var index = 0; index < tabs.length; index += 1)
            {
              'id': tabs[index]['id'],
              'user_id': user.id,
              'task_id': task.id,
              'session_id': sessionId,
              'url': tabs[index]['url'],
              'title': tabs[index]['title'],
              'domain': Uri.tryParse(
                tabs[index]['url']?.toString() ?? '',
              )?.host,
              'tab_order': index,
              'is_active': index == selectedTab,
              'closed_at': null,
              'last_active_at': index == selectedTab ? now : null,
              'updated_at': now,
            },
        ]);
      }
      final selectedTabId = tabs.isEmpty
          ? null
          : tabs[selectedTab.clamp(0, tabs.length - 1)]['id'];
      await client.from('task_workspace_state').upsert({
        'user_id': user.id,
        'task_id': task.id,
        'browser_expanded': browserExpanded,
        'browser_width': browserWidth,
        'workspace_layout': browserExpanded ? 'right_panel' : 'collapsed',
        'browser_mode': browserMode,
        'selected_task_panel': selectedPanel.toString(),
        'selected_browser_tab_id': selectedTabId,
        'last_opened_at': now,
        'updated_at': now,
      }, onConflict: 'user_id,task_id');
    } on Object catch (error) {
      if (kDebugMode) debugPrint('BROWSER CHECKPOINT DEFERRED: $error');
    }
  }

  Future<TaskItem> updateStatus(TaskItem task, TaskStatus status) {
    return updateTask(task.copyWith(status: status));
  }

  Future<void> moveToTrash(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return;
    }

    final deleted = task.copyWith(deletedAt: DateTime.now());
    await _localStore.upsertTask(user.id, deleted);
    final operation = await _queueTaskOperation(user.id, 'soft_delete', {
      'task_id': task.id,
      'deleted_at': deleted.deletedAt?.toUtc().toIso8601String(),
    });
    if (client == null) return;

    try {
      await client.rpc('soft_delete_task', params: {'task_id': task.id});
      await _localStore.removeOperation(user.id, operation.id);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: task.id,
          eventType: 'task_deleted',
        ),
      );
    } on Object catch (error) {
      if (_isConnectivityError(error)) return;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<void> deleteTask(TaskItem task) => moveToTrash(task);

  Future<TaskItem> archiveTask(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return task;
    }
    final archivedAt = DateTime.now();
    final archived = task.copyWith(archivedAt: archivedAt);
    await _localStore.upsertTask(user.id, archived);
    final operation = await _queueTaskOperation(user.id, 'archive', {
      'task_id': task.id,
      'archived_at': archivedAt.toUtc().toIso8601String(),
    });
    if (client == null) return archived;
    try {
      final row = await client
          .from('tasks')
          .update({
            'archived_at': archivedAt.toUtc().toIso8601String(),
            'updated_at': archivedAt.toUtc().toIso8601String(),
          })
          .eq('id', task.id)
          .eq('user_id', user.id)
          .select()
          .single();
      final saved = TaskItem.fromMap(row);
      await _localStore.upsertTask(user.id, saved);
      await _localStore.removeOperation(user.id, operation.id);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: saved.id,
          eventType: 'task_archived',
          revision: saved.updatedAt.millisecondsSinceEpoch,
        ),
      );
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return archived;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<TaskItem> restoreTask(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return task;
    }
    final restored = task.copyWith(clearDeletedAt: true);
    await _localStore.upsertTask(user.id, restored);
    final operation = await _queueTaskOperation(user.id, 'restore', {
      'task_id': task.id,
    });
    if (client == null) return restored;
    try {
      final row = await client
          .from('tasks')
          .update({
            'deleted_at': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', task.id)
          .eq('user_id', user.id)
          .select()
          .single();
      final saved = TaskItem.fromMap(row);
      await _localStore.upsertTask(user.id, saved);
      await _localStore.removeOperation(user.id, operation.id);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: saved.id,
          eventType: 'task_restored',
          revision: saved.updatedAt.millisecondsSinceEpoch,
        ),
      );
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return restored;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<void> permanentlyDeleteTask(TaskItem task) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) {
      return;
    }
    await _localStore.removeTask(user.id, task.id);
    final operation = await _queueTaskOperation(user.id, 'permanent_delete', {
      'task_id': task.id,
    });
    if (client == null) return;
    try {
      await client
          .from('tasks')
          .delete()
          .eq('id', task.id)
          .eq('user_id', user.id);
      await _localStore.removeOperation(user.id, operation.id);
      unawaited(
        publishSyncEvent(
          entityType: 'task',
          entityId: task.id,
          eventType: 'task_permanently_deleted',
        ),
      );
    } on Object catch (error) {
      if (_isConnectivityError(error)) return;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<void> synchronizePendingOperations() async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (client == null || user == null) return;
    final snapshot = await _localStore.load(user.id);
    final ordered = List<PendingTaskOperation>.of(snapshot.operations)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final operation in ordered) {
      try {
        await _localStore.updateOperation(
          user.id,
          operation.copyWith(syncState: 'uploading'),
        );
        await _replayOperation(client, user.id, operation);
        await _localStore.removeOperation(user.id, operation.id);
      } on Object catch (error) {
        await _localStore.updateOperation(
          user.id,
          operation.copyWith(
            attemptCount: operation.attemptCount + 1,
            syncState: _isConnectivityError(error) ? 'pending' : 'failed',
            lastError: error.toString(),
          ),
        );
        if (_isConnectivityError(error)) return;
        if (kDebugMode) {
          debugPrint('TASK OPERATION REJECTED ${operation.id}: $error');
        }
        rethrow;
      }
    }
  }

  Future<void> rollbackFailedOperation(String operationId) async {
    final userId = currentUserId;
    if (userId != null) {
      await _localStore.removeOperation(userId, operationId);
    }
  }

  Future<List<TaskNote>> loadNotes(String taskId) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final localRows = await _localStore.loadRows(user.id, 'task_notes');
    final local = localRows
        .where(
          (row) =>
              row['task_id']?.toString() == taskId && row['deleted_at'] == null,
        )
        .map(TaskNote.fromMap)
        .toList(growable: false);
    if (client == null) return local;

    try {
      final rows = await client
          .from('task_notes')
          .select()
          .eq('user_id', user.id)
          .eq('task_id', taskId)
          .isFilter('deleted_at', null)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);
      final parsed = rows
          .map<TaskNote>((row) => TaskNote.fromMap(row))
          .toList();
      await _localStore.replaceRowsWhere(
        user.id,
        'task_notes',
        'task_id',
        {taskId},
        [for (final note in parsed) _noteRow(note, user.id)],
      );
      return parsed;
    } on Object {
      return local;
    }
  }

  Future<TaskNote> addNote(TaskNote note) async {
    return _saveNote(note);
  }

  Future<TaskNote> updateNote(TaskNote note) async {
    return _saveNote(note);
  }

  Future<TaskNote> _saveNote(TaskNote note) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return note;
    final payload = _noteRow(note, user.id);
    await _localStore.upsertRow(user.id, 'task_notes', note.id, payload);
    final operation = await _queueTaskOperation(
      user.id,
      'note_upsert',
      payload,
    );
    if (client == null) return note;
    try {
      final row = await client
          .from('task_notes')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();
      final saved = TaskNote.fromMap(row);
      await _localStore.upsertRow(
        user.id,
        'task_notes',
        saved.id,
        _noteRow(saved, user.id),
      );
      await _localStore.removeOperation(user.id, operation.id);
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return note;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<void> deleteNote(TaskNote note) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return;
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    await _localStore.upsertRow(user.id, 'task_notes', note.id, {
      ..._noteRow(note, user.id),
      'deleted_at': deletedAt,
    });
    final operation = await _queueTaskOperation(user.id, 'note_delete', {
      'id': note.id,
      'deleted_at': deletedAt,
    });
    if (client == null) return;
    try {
      await client
          .from('task_notes')
          .update({'deleted_at': deletedAt})
          .eq('id', note.id)
          .eq('user_id', user.id);
      await _localStore.removeOperation(user.id, operation.id);
    } on Object catch (error) {
      if (_isConnectivityError(error)) return;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<List<TaskInterruption>> loadInterruptions(String taskId) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final localRows = await _localStore.loadRows(user.id, 'task_interruptions');
    final local = localRows
        .where(
          (row) =>
              row['task_id']?.toString() == taskId && row['deleted_at'] == null,
        )
        .map(TaskInterruption.fromMap)
        .toList(growable: false);
    if (client == null) return local;

    try {
      final rows = await client
          .from('task_interruptions')
          .select()
          .eq('user_id', user.id)
          .eq('task_id', taskId)
          .isFilter('deleted_at', null)
          .order('started_at', ascending: false);
      final parsed = rows
          .map<TaskInterruption>((row) => TaskInterruption.fromMap(row))
          .toList();
      await _localStore.replaceRowsWhere(
        user.id,
        'task_interruptions',
        'task_id',
        {taskId},
        [for (final item in parsed) _interruptionRow(item, user.id)],
      );
      return parsed;
    } on Object {
      return local;
    }
  }

  Future<TaskInterruption> addInterruption(
    TaskInterruption interruption,
  ) async {
    return _saveInterruption(interruption);
  }

  Future<TaskInterruption> updateInterruption(
    TaskInterruption interruption,
  ) async {
    return _saveInterruption(interruption);
  }

  Future<TaskInterruption> _saveInterruption(
    TaskInterruption interruption,
  ) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return interruption;
    final payload = _interruptionRow(interruption, user.id);
    await _localStore.upsertRow(
      user.id,
      'task_interruptions',
      interruption.id,
      payload,
    );
    final operation = await _queueTaskOperation(
      user.id,
      'interruption_upsert',
      payload,
    );
    if (client == null) return interruption;
    try {
      final row = await client
          .from('task_interruptions')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();
      final saved = TaskInterruption.fromMap(row);
      await _localStore.upsertRow(
        user.id,
        'task_interruptions',
        saved.id,
        _interruptionRow(saved, user.id),
      );
      await _localStore.removeOperation(user.id, operation.id);
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return interruption;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<void> deleteInterruption(TaskInterruption interruption) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return;
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    await _localStore.upsertRow(
      user.id,
      'task_interruptions',
      interruption.id,
      {..._interruptionRow(interruption, user.id), 'deleted_at': deletedAt},
    );
    final operation = await _queueTaskOperation(
      user.id,
      'interruption_delete',
      {'id': interruption.id, 'deleted_at': deletedAt},
    );
    if (client == null) return;
    try {
      await client
          .from('task_interruptions')
          .update({'deleted_at': deletedAt})
          .eq('id', interruption.id)
          .eq('user_id', user.id);
      await _localStore.removeOperation(user.id, operation.id);
    } on Object catch (error) {
      if (_isConnectivityError(error)) return;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Map<String, dynamic> _noteRow(TaskNote note, String userId) => {
    'id': note.id,
    'user_id': userId,
    ...note.toInsertMap(),
    'created_at': note.createdAt.toUtc().toIso8601String(),
    'updated_at': note.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _interruptionRow(
    TaskInterruption interruption,
    String userId,
  ) => {
    'id': interruption.id,
    'user_id': userId,
    ...interruption.toInsertMap(),
    'created_at': interruption.createdAt.toUtc().toIso8601String(),
    'updated_at': interruption.updatedAt.toUtc().toIso8601String(),
  };

  Future<void> upsertCategories(List<TaskCategory> categories) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null || categories.isEmpty) {
      return;
    }

    await client.from('categories').upsert([
      for (var i = 0; i < categories.length; i += 1)
        {
          'user_id': user.id,
          'name': categories[i].name,
          'color_seed':
              '#${categories[i].colorSeed.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
          'sort_order': i * 10,
          'is_system': false,
        },
    ], onConflict: 'user_id,name');
  }

  Future<List<TrackedSession>> loadSessionsForTask(String taskId) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    if (client == null) {
      return (await _loadLocalSessions(
        user.id,
      )).where((session) => session.taskId == taskId).toList();
    }

    try {
      final rows = await client
          .from('sessions')
          .select()
          .eq('task_id', taskId)
          .isFilter('deleted_at', null)
          .order('started_at', ascending: false);
      return rows
          .map<TrackedSession>((row) => TrackedSession.fromMap(row))
          .toList();
    } on Object {
      return (await _loadLocalSessions(
        user.id,
      )).where((session) => session.taskId == taskId).toList();
    }
  }

  Future<List<TrackedSession>> loadSessionsInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    if (client == null) {
      return (await _loadLocalSessions(user.id))
          .where(
            (session) =>
                !session.startedAt.isBefore(start) &&
                session.startedAt.isBefore(end),
          )
          .toList();
    }

    try {
      final rows = await client
          .from('sessions')
          .select()
          .gte('started_at', start.toIso8601String())
          .lt('started_at', end.toIso8601String())
          .isFilter('deleted_at', null)
          .order('started_at', ascending: false);
      final parsed = rows
          .map<TrackedSession>((row) => TrackedSession.fromMap(row))
          .toList();
      for (final session in parsed) {
        await _localStore.upsertRow(
          user.id,
          'sessions',
          session.id,
          session.toInsertMap(),
        );
      }
      return parsed;
    } on Object {
      return (await _loadLocalSessions(user.id))
          .where(
            (session) =>
                !session.startedAt.isBefore(start) &&
                session.startedAt.isBefore(end),
          )
          .toList();
    }
  }

  Future<TrackedSession?> loadSessionById(String sessionId) async {
    final client = _supabaseService.clientOrNull;
    final user = _supabaseService.currentUser;
    if (user == null) return null;
    if (client == null) {
      return (await _loadLocalSessions(
        user.id,
      )).where((session) => session.id == sessionId).firstOrNull;
    }

    try {
      final row = await client
          .from('sessions')
          .select()
          .eq('id', sessionId)
          .maybeSingle();
      return row == null ? null : TrackedSession.fromMap(row);
    } on Object {
      return (await _loadLocalSessions(
        user.id,
      )).where((session) => session.id == sessionId).firstOrNull;
    }
  }

  Future<TrackedSession> upsertSession(TrackedSession session) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (user == null) return session;
    final local = session.copyWith(syncStatus: 'pending');
    final payload = {...local.toInsertMap(), 'user_id': user.id};
    await _localStore.upsertRow(user.id, 'sessions', session.id, payload);
    final operation = await _queueTaskOperation(user.id, 'session', payload);
    if (client == null) return local;
    try {
      final row = await client
          .from('sessions')
          .upsert({...payload, 'sync_status': 'synced'})
          .select()
          .single();
      final saved = TrackedSession.fromMap(row);
      await _localStore.upsertRow(
        user.id,
        'sessions',
        saved.id,
        saved.toInsertMap(),
      );
      await _localStore.removeOperation(user.id, operation.id);
      unawaited(
        publishSyncEvent(
          entityType: 'session',
          entityId: saved.id,
          eventType: 'session_changed',
          revision: saved.updatedAt.millisecondsSinceEpoch,
          payload: {'task_id': saved.taskId, 'status': saved.status.name},
        ),
      );
      return saved;
    } on Object catch (error) {
      if (_isConnectivityError(error)) return local;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<List<TrackedSessionSegment>> loadSegmentsForSession(
    String sessionId,
  ) async {
    final client = _supabaseService.clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      return const [];
    }

    try {
      final rows = await client
          .from('session_segments')
          .select()
          .eq('session_id', sessionId)
          .isFilter('deleted_at', null)
          .order('started_at');
      return rows
          .map<TrackedSessionSegment>(
            (row) => TrackedSessionSegment.fromMap(row),
          )
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<TrackedSessionSegment> upsertSegment(
    TrackedSessionSegment segment,
  ) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (user == null) return segment;
    final payload = {...segment.toInsertMap(), 'user_id': user.id};
    await _localStore.upsertRow(
      user.id,
      'session_segments',
      segment.id,
      payload,
    );
    final operation = await _queueTaskOperation(
      user.id,
      'session_segment',
      payload,
    );
    if (client == null) return segment;
    try {
      final row = await client
          .from('session_segments')
          .upsert(payload)
          .select()
          .single();
      await _localStore.removeOperation(user.id, operation.id);
      return TrackedSessionSegment.fromMap(row);
    } on Object catch (error) {
      if (_isConnectivityError(error)) return segment;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<void> addSessionEvent(SessionEventRecord event) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (user == null) return;
    final payload = {...event.toInsertMap(), 'user_id': user.id};
    await _localStore.upsertRow(user.id, 'session_events', event.id, payload);
    final operation = await _queueTaskOperation(
      user.id,
      'session_event',
      payload,
    );
    if (client == null) return;
    try {
      await client.from('session_events').upsert(payload, onConflict: 'id');
      await _localStore.removeOperation(user.id, operation.id);
      unawaited(
        publishSyncEvent(
          entityType: 'session',
          entityId: event.sessionId,
          eventType: event.eventType,
          revision: event.eventTime.millisecondsSinceEpoch,
        ),
      );
    } on Object catch (error) {
      if (_isConnectivityError(error)) return;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<List<TaskProgressEntry>> loadProgressEntries(String taskId) async {
    final client = _supabaseService.clientOrNull;
    if (client == null || client.auth.currentUser == null) {
      return const [];
    }

    try {
      final rows = await client
          .from('task_progress_entries')
          .select()
          .eq('task_id', taskId)
          .order('recorded_at');
      return rows
          .map<TaskProgressEntry>((row) => TaskProgressEntry.fromMap(row))
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<TaskProgressEntry> addProgressEntry(TaskProgressEntry entry) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return entry;
    }

    final row = await client
        .from('task_progress_entries')
        .insert({...entry.toInsertMap(), 'user_id': user.id})
        .select()
        .single();
    return TaskProgressEntry.fromMap(row);
  }

  static int _colorFromStorage(String? value) {
    final normalized = value?.replaceFirst('#', '').trim();
    if (normalized == null || normalized.length != 6) {
      return 0xFF64748B;
    }
    return int.tryParse('FF$normalized', radix: 16) ?? 0xFF64748B;
  }

  Future<void> _replaceCachedPartition(
    String userId,
    List<TaskItem> incoming, {
    required bool deleted,
  }) async {
    final snapshot = await _localStore.load(userId);
    final pendingIds = snapshot.operations
        .where((operation) => operation.entityType == 'task')
        .map((operation) => operation.entityId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final retained = snapshot.tasks.where((task) {
      if (pendingIds.contains(task.id)) return true;
      return deleted ? task.deletedAt == null : task.deletedAt != null;
    });
    final retainedIds = retained.map((task) => task.id).toSet();
    await _localStore.replaceTasks(userId, [
      ...retained,
      ...incoming.where((task) => !retainedIds.contains(task.id)),
    ]);
  }

  Future<PendingTaskOperation> _queueTaskOperation(
    String userId,
    String type,
    Map<String, dynamic> payload,
  ) async {
    final deviceId = await _localStore.loadDeviceId();
    final entityId =
        payload['id']?.toString() ?? payload['task_id']?.toString() ?? '';
    final entityType = switch (type) {
      'session' => 'session',
      'session_segment' => 'session_segment',
      'session_event' => 'session_event',
      'usage' => 'task_activity',
      'resources' => 'task_resource',
      'reminders' => 'task_reminder',
      'work_demand' => 'work_demand',
      'learning_checkpoint' => 'learning_checkpoint',
      'widget_action_event' => 'widget_action_event',
      'note_upsert' || 'note_delete' => 'task_note',
      'interruption_upsert' || 'interruption_delete' => 'task_interruption',
      _ => 'task',
    };
    final operation = PendingTaskOperation(
      type: type,
      operation: type,
      entityType: entityType,
      entityId: entityId,
      deviceId: deviceId,
      changedFields: payload.keys.toList(growable: false),
      payload: payload,
    );
    await _localStore.enqueue(userId, operation);
    return operation;
  }

  Future<void> _replayOperation(
    dynamic client,
    String userId,
    PendingTaskOperation operation,
  ) async {
    final payload = operation.payload;
    switch (operation.type) {
      case 'create':
        await client.from('tasks').upsert(payload, onConflict: 'id');
      case 'update':
        final values = Map<String, dynamic>.from(payload);
        final taskId = values.remove('id')?.toString();
        if (taskId == null) return;
        await client
            .from('tasks')
            .update(values)
            .eq('id', taskId)
            .eq('user_id', userId);
      case 'soft_delete':
        await client
            .from('tasks')
            .update({
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', payload['task_id'])
            .eq('user_id', userId);
      case 'restore':
        await client
            .from('tasks')
            .update({
              'deleted_at': null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', payload['task_id'])
            .eq('user_id', userId);
      case 'archive':
        await client
            .from('tasks')
            .update({
              'archived_at': payload['archived_at'],
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', payload['task_id'])
            .eq('user_id', userId);
      case 'permanent_delete':
        await client
            .from('tasks')
            .delete()
            .eq('id', payload['task_id'])
            .eq('user_id', userId);
      case 'resources':
        final taskId = payload['task_id']?.toString();
        if (taskId == null) return;
        await client
            .from('task_resources')
            .update({
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('task_id', taskId)
            .eq('user_id', userId)
            .isFilter('deleted_at', null);
        final rows = payload['rows'];
        if (rows is List && rows.isNotEmpty) {
          await client.from('task_resources').upsert(rows);
        }
      case 'reminders':
        final taskId = payload['task_id']?.toString();
        if (taskId == null) return;
        await client
            .from('task_reminders')
            .update({
              'status': 'cancelled',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('task_id', taskId)
            .eq('user_id', userId)
            .not('status', 'eq', 'cancelled');
        final rows = payload['rows'];
        if (rows is List && rows.isNotEmpty) {
          await client.from('task_reminders').upsert(rows);
        }
      case 'usage':
        final rows = payload['rows'];
        if (rows is List && rows.isNotEmpty) {
          await client.from('task_activity_records').upsert(rows);
        }
      case 'session':
        await client.from('sessions').upsert(payload, onConflict: 'id');
      case 'session_segment':
        await client.from('session_segments').upsert(payload, onConflict: 'id');
      case 'session_event':
        await client.from('session_events').upsert(payload, onConflict: 'id');
      case 'work_demand':
        await client.from('work_demands').upsert(payload, onConflict: 'id');
      case 'learning_checkpoint':
        await client
            .from('learning_checkpoints')
            .upsert(payload, onConflict: 'id');
      case 'widget_action_event':
        await client
            .from('widget_action_events')
            .upsert(payload, onConflict: 'id');
      case 'note_upsert':
        await client.from('task_notes').upsert(payload, onConflict: 'id');
      case 'note_delete':
        await client
            .from('task_notes')
            .update({'deleted_at': payload['deleted_at']})
            .eq('id', payload['id'])
            .eq('user_id', userId);
      case 'interruption_upsert':
        await client
            .from('task_interruptions')
            .upsert(payload, onConflict: 'id');
      case 'interruption_delete':
        await client
            .from('task_interruptions')
            .update({'deleted_at': payload['deleted_at']})
            .eq('id', payload['id'])
            .eq('user_id', userId);
    }
  }

  Future<List<TrackedSession>> _loadLocalSessions(String userId) async {
    final rows = await _localStore.loadRows(userId, 'sessions');
    return rows.map(TrackedSession.fromMap).toList(growable: false);
  }

  Future<void> _createRecurrenceIfNeeded(
    dynamic client,
    TaskItem saved,
    TaskItem original,
  ) async {
    final user = _supabaseService.currentUser;
    final preset = original.reminderRules['repeatPreset']?.toString();
    final explicitRule = original.recurrenceRule?.trim();
    if (user == null ||
        ((preset == null || preset.isEmpty) &&
            (explicitRule == null || explicitRule.isEmpty))) {
      return;
    }

    final start =
        saved.plannedStartAt ??
        saved.scheduledStartAt ??
        saved.dueAt ??
        saved.dueDate ??
        saved.startDate ??
        DateTime.now();
    final startsAt = start;
    final rrule = explicitRule?.isNotEmpty == true
        ? explicitRule!
        : _rruleForPreset(preset!, startsAt);
    try {
      await client
          .from('tasks')
          .update({'is_recurring_template': true})
          .eq('id', saved.id);
      final existing = await client
          .from('task_recurrences')
          .select('id')
          .eq('task_id', saved.id)
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final recurrenceValues = {
        'user_id': user.id,
        'task_id': saved.id,
        'rule': {'preset': ?preset, 'rrule': rrule},
        'timezone': original.recurrenceTimezone,
        'rrule': rrule,
        'starts_at': startsAt.toIso8601String(),
        'duration_minutes': saved.estimatedMinutes,
        'end_type': original.recurrenceEndType,
        'ends_at': original.recurrenceEndAt?.toIso8601String(),
        'maximum_occurrences': original.recurrenceMaximumOccurrences,
        'is_active': true,
      };
      final recurrenceRow = existing == null
          ? await client
                .from('task_recurrences')
                .insert(recurrenceValues)
                .select('id')
                .single()
          : await client
                .from('task_recurrences')
                .update(recurrenceValues)
                .eq('id', existing['id'])
                .eq('user_id', user.id)
                .select('id')
                .single();
      final recurrenceId = recurrenceRow['id']?.toString();
      if (recurrenceId == null) {
        return;
      }
      await client
          .from('tasks')
          .update({'recurrence_id': recurrenceId})
          .eq('id', saved.id);
      await client.rpc(
        'generate_task_occurrences',
        params: {
          'recurrence_id': recurrenceId,
          'range_start': DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          'range_end': DateTime.now()
              .add(const Duration(days: 90))
              .toIso8601String(),
        },
      );
    } on Object {
      // Recurrence support depends on the latest migration. Keep the task
      // usable if the backend has not been upgraded yet.
    }
  }

  String _rruleForPreset(String preset, DateTime startsAt) {
    final dayCode = _weekdayCode(startsAt.weekday);
    return switch (preset) {
      'daily' => 'FREQ=DAILY;INTERVAL=1',
      'weekday' => 'FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,TU,WE,TH,FR',
      'weekend' => 'FREQ=WEEKLY;INTERVAL=1;BYDAY=SA,SU',
      'two_weeks' => 'FREQ=WEEKLY;INTERVAL=2;BYDAY=$dayCode',
      'monthly' => 'FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=${startsAt.day}',
      'yearly' => 'FREQ=YEARLY;INTERVAL=1',
      _ => 'FREQ=WEEKLY;INTERVAL=1;BYDAY=$dayCode',
    };
  }

  String _weekdayCode(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'MO',
      DateTime.tuesday => 'TU',
      DateTime.wednesday => 'WE',
      DateTime.thursday => 'TH',
      DateTime.friday => 'FR',
      DateTime.saturday => 'SA',
      _ => 'SU',
    };
  }
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _isConnectivityError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('connection closed') ||
      text.contains('timed out') ||
      text.contains('xmlhttprequest error');
}

class TaskController {
  TaskController(this._repository);

  final TaskRepository _repository;
  List<TaskItem> _tasks = const [];
  List<TaskCategory> _categories = const [];

  List<TaskItem> get tasks => _tasks;
  List<TaskCategory> get categories => _categories;

  Future<List<TaskItem>> load() async {
    final results = await Future.wait([
      _repository.loadTasks(),
      _repository.loadCategories(),
    ]);
    _tasks = results[0] as List<TaskItem>;
    _categories = results[1] as List<TaskCategory>;
    return _tasks;
  }

  Future<TaskItem> add(TaskItem task) async {
    final saved = await _repository.addTask(task);
    _tasks = [saved, ..._tasks];
    return saved;
  }

  Future<void> addCategories(List<TaskCategory> categories) async {
    await _repository.upsertCategories(categories);
    _categories = await _repository.loadCategories();
  }
}
