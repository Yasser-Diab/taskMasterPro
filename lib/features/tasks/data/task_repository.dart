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
    final snapshot = _objectMap(map['snapshot']);
    final session = _objectMap(snapshot == null ? null : snapshot['session']);
    final segment = _objectMap(
      snapshot == null ? null : snapshot['current_segment'],
    );
    final cleanState =
        map['stage']?.toString() ??
        (session == null ? null : session['state']?.toString());
    String? fallbackSegmentId;
    if (segment != null && segment['state']?.toString() == 'running') {
      fallbackSegmentId = segment['id']?.toString();
    }
    final currentSegmentId = map['segment_id']?.toString() ?? fallbackSegmentId;
    return SessionCommandResult(
      status: map['status']?.toString() ?? 'unknown',
      revision: _intValue(
        map['revision'] ??
            (session == null ? null : session['revision']) ??
            map['result_revision'],
      ),
      message: map['message']?.toString() ?? map['error']?.toString(),
      stage: cleanState,
      sessionState:
          map['session_state']?.toString() ??
          _legacyStatusForCleanState(cleanState),
      segmentId: currentSegmentId,
    );
  }

  static Map<String, dynamic>? _objectMap(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  static String? _legacyStatusForCleanState(String? state) {
    return switch (state) {
      'focus_running' || 'break_running' || 'running' => 'running',
      'focus_paused' ||
      'break_paused' ||
      'paused' ||
      'focus_ready' ||
      'break_ready' ||
      'focus_completed_waiting' ||
      'break_completed_waiting' => 'paused',
      'task_completed' => 'completed',
      'cancelled' => 'discarded',
      _ => null,
    };
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
      final channel = client.channel(
        'taskmaster:user:${user.id}:runtime',
        opts: const RealtimeChannelConfig(private: true),
      );
      await channel.sendBroadcastMessage(
        event: _runtimeEventName(entityType),
        payload: {
          'entity_type': entityType,
          'entity_id': entityId,
          'event_type': eventType,
          'revision': revision,
          'device_id': await _localStore.loadDeviceId(),
          'payload': payload,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      await client.removeChannel(channel);
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
      await _ensureRemoteDevice(client, user, deviceId);
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

  Future<void> _ensureRemoteDevice(
    SupabaseClient client,
    User user,
    String deviceId,
  ) async {
    await client.from('devices').upsert({
      'id': deviceId,
      'user_id': user.id,
      'device_name': Platform.localHostname,
      'platform': Platform.isAndroid ? 'android' : 'windows',
      'platform_version': Platform.operatingSystemVersion,
      'app_version': '',
      'build_number': '',
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'notification_enabled': false,
    }, onConflict: 'id');
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
          .select('*,task_domains(name)')
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .neq('status', 'archived')
          .order('planned_start_at_utc', nullsFirst: false)
          .order('due_at_utc', nullsFirst: false)
          .order('updated_at', ascending: false)
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
          .select('*,task_domains(name)')
          .eq('user_id', user.id)
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
        tasks.add(TaskItem.fromMap(_taskRowForUi(typedRow)));
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
          .from('task_domains')
          .select('name,color')
          .eq('user_id', client.auth.currentUser!.id)
          .isFilter('deleted_at', null)
          .order('sort_order')
          .order('name');
      return rows.map<TaskCategory>((row) {
        return TaskCategory(
          name: row['name']?.toString() ?? 'Personal',
          colorSeed: _colorFromStorage(row['color']?.toString()),
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
          .select('id,roadmap_id,phase_order,title')
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
            title: row['title']?.toString() ?? '',
            phaseOrder: _intValue(row['phase_order'], fallback: phases.length),
          ),
        );
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('ROADMAP PHASE OPTIONS FAILED: $error');
    }

    try {
      final rows = await client
          .from('roadmap_milestones')
          .select('id,roadmap_id,phase_id,title')
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .order('created_at');
      for (final row in rows) {
        final roadmapId = row['roadmap_id']?.toString();
        if (roadmapId == null || roadmapId.isEmpty) continue;
        milestones.add(
          TaskMilestoneOption(
            id: row['id'].toString(),
            roadmapId: roadmapId,
            phaseId: row['phase_id']?.toString(),
            title: row['title']?.toString() ?? '',
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

    final payload = await _taskPayloadForRemote(
      task,
      userId: user.id,
      client: client,
    );
    await _localStore.upsertTask(user.id, task);
    final operation = await _queueTaskOperation(user.id, 'create', payload);
    if (client == null) return task;
    try {
      final row = await client
          .from('tasks')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();

      final saved = TaskItem.fromMap(_taskRowForUi(row));
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
    final payload = await _taskPayloadForRemote(
      task,
      userId: user.id,
      client: client,
    );
    await _localStore.upsertTask(user.id, task);
    final operation = await _queueTaskOperation(user.id, 'update', payload);
    if (client == null) return task;
    try {
      final updateValues = Map<String, dynamic>.from(payload)..remove('id');
      final row = await client
          .from('tasks')
          .update(updateValues)
          .eq('id', task.id)
          .eq('user_id', user.id)
          .select()
          .single();

      final saved = TaskItem.fromMap(_taskRowForUi(row));
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
            .map((row) => WorkDemand.fromMap(_workDemandRowForUi(row)))
            .where((item) => item.deletedAt == null)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (client == null) return local;
    try {
      final rows = await client
          .from('task_demands')
          .select()
          .eq('user_id', user.id)
          .eq('task_id', taskId)
          .isFilter('deleted_at', null)
          .order('sort_order');
      final parsed = rows
          .map<WorkDemand>(
            (row) => WorkDemand.fromMap(_workDemandRowForUi(row)),
          )
          .toList();
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
    final payload = _workDemandPayload(demand, user.id);
    await _localStore.upsertRow(user.id, 'work_demands', demand.id, payload);
    final operation = await _queueTaskOperation(
      user.id,
      'work_demand',
      payload,
    );
    if (client == null) return demand;
    try {
      final row = await client
          .from('task_demands')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();
      await _localStore.removeOperation(user.id, operation.id);
      final saved = WorkDemand.fromMap(_workDemandRowForUi(row));
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
            .map(
              (row) =>
                  LearningCheckpoint.fromMap(_learningCheckpointRowForUi(row)),
            )
            .where((item) => item.deletedAt == null)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (client == null) return local;
    try {
      final rows = await client
          .from('task_checkpoints')
          .select()
          .eq('user_id', user.id)
          .eq('task_id', taskId)
          .isFilter('deleted_at', null)
          .order('sort_order');
      final parsed = rows
          .map<LearningCheckpoint>(
            (row) =>
                LearningCheckpoint.fromMap(_learningCheckpointRowForUi(row)),
          )
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
    final payload = _learningCheckpointPayload(checkpoint, user.id);
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
          .from('task_checkpoints')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();
      await _localStore.removeOperation(user.id, operation.id);
      final saved = LearningCheckpoint.fromMap(
        _learningCheckpointRowForUi(row),
      );
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
    await client
        .from('tasks')
        .update({
          'status': 'skipped',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', task.id)
        .eq('user_id', user.id);
  }

  Future<void> setRecurrenceState(TaskItem task, String action) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return;
    }
    final paused = switch (action) {
      'pause' || 'paused' || 'disable' => true,
      'resume' || 'active' || 'enable' => false,
      _ => null,
    };
    if (paused == null) return;
    await client
        .from('tasks')
        .update({
          'recurrence_paused': paused,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', task.id)
        .eq('user_id', user.id);
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
        .map((row) => TaskUsageActivity.fromMap(_activityIntervalRowForUi(row)))
        .toList(growable: false);
    if (client == null) return local;
    try {
      final rows = await client
          .from('activity_intervals')
          .select()
          .eq('task_id', taskId)
          .eq('user_id', user.id)
          .order('started_at_utc', ascending: false);
      final parsed = rows
          .map<TaskUsageActivity>(
            (row) => TaskUsageActivity.fromMap(_activityIntervalRowForUi(row)),
          )
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
    final rows = [
      for (final record in records) _activityIntervalPayload(record, user.id),
    ];
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
      await client.from('activity_intervals').upsert(rows);
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
          .from('browser_tabs')
          .update({'deleted_at': now, 'active': false, 'updated_at': now})
          .eq('user_id', user.id)
          .eq('task_id', task.id)
          .isFilter('deleted_at', null);
      if (tabs.isNotEmpty) {
        await client.from('browser_tabs').upsert([
          for (var index = 0; index < tabs.length; index += 1)
            {
              'id':
                  _uuidOrNull(tabs[index]['id']?.toString()) ??
                  const Uuid().v4(),
              'user_id': user.id,
              'device_id': null,
              'task_id': task.id,
              'occurrence_id': null,
              'resource_id': null,
              'url': tabs[index]['url']?.toString().trim().isNotEmpty == true
                  ? tabs[index]['url'].toString()
                  : 'https://www.google.com',
              'title':
                  tabs[index]['title']?.toString().trim().isNotEmpty == true
                  ? tabs[index]['title'].toString()
                  : 'Google',
              'custom_title': tabs[index]['custom_title']?.toString(),
              'pinned': tabs[index]['pinned'] == true,
              'active': index == selectedTab,
              'sort_order': index,
              'last_seen_at': now,
              'updated_at': now,
              'deleted_at': null,
            },
        ], onConflict: 'id');
      }
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
      await client
          .from('tasks')
          .update({
            'deleted_at': deleted.deletedAt?.toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', task.id)
          .eq('user_id', user.id);
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
            'status': 'archived',
            'updated_at': archivedAt.toUtc().toIso8601String(),
          })
          .eq('id', task.id)
          .eq('user_id', user.id)
          .select()
          .single();
      final saved = TaskItem.fromMap(
        _taskRowForUi({
          ...Map<String, dynamic>.from(row),
          'archived_at': archivedAt.toUtc().toIso8601String(),
        }),
      );
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
            'status': _cleanTaskStatus(restored),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', task.id)
          .eq('user_id', user.id)
          .select()
          .single();
      final saved = TaskItem.fromMap(_taskRowForUi(row));
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
    final user = _supabaseService.currentUser;
    if (user == null) return const [];
    final localRows = await _localStore.loadRows(user.id, 'task_interruptions');
    return localRows
        .where(
          (row) =>
              row['task_id']?.toString() == taskId && row['deleted_at'] == null,
        )
        .map(TaskInterruption.fromMap)
        .toList(growable: false);
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
    final user = _supabaseService.currentUser;
    if (user == null) return interruption;
    final payload = _interruptionRow(interruption, user.id);
    await _localStore.upsertRow(
      user.id,
      'task_interruptions',
      interruption.id,
      payload,
    );
    return interruption;
  }

  Future<void> deleteInterruption(TaskInterruption interruption) async {
    final user = _supabaseService.currentUser;
    if (user == null) return;
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    await _localStore.upsertRow(
      user.id,
      'task_interruptions',
      interruption.id,
      {..._interruptionRow(interruption, user.id), 'deleted_at': deletedAt},
    );
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

    for (var i = 0; i < categories.length; i += 1) {
      final category = categories[i];
      final existing = await client
          .from('task_domains')
          .select('id')
          .eq('user_id', user.id)
          .ilike('name', category.name)
          .isFilter('deleted_at', null)
          .limit(1)
          .maybeSingle();
      final values = {
        'user_id': user.id,
        'name': category.name,
        'icon': _taskDomainIcon(category.name),
        'color': _colorToStorage(category.colorSeed),
        'sort_order': i * 10,
        'is_template': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final existingId = existing?['id']?.toString();
      if (existingId != null) {
        await client
            .from('task_domains')
            .update(values)
            .eq('id', existingId)
            .eq('user_id', user.id);
      } else {
        await client.from('task_domains').insert(values);
      }
    }
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
          .from('task_sessions')
          .select()
          .eq('user_id', user.id)
          .eq('task_id', taskId)
          .order('started_at_utc', ascending: false);
      return rows
          .map<TrackedSession>(
            (row) => TrackedSession.fromMap(_sessionRowForUi(row)),
          )
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
          .from('task_sessions')
          .select()
          .eq('user_id', user.id)
          .gte('started_at_utc', start.toUtc().toIso8601String())
          .lt('started_at_utc', end.toUtc().toIso8601String())
          .order('started_at_utc', ascending: false);
      final parsed = rows
          .map<TrackedSession>(
            (row) => TrackedSession.fromMap(_sessionRowForUi(row)),
          )
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
          .from('task_sessions')
          .select()
          .eq('user_id', user.id)
          .eq('id', sessionId)
          .maybeSingle();
      return row == null ? null : TrackedSession.fromMap(_sessionRowForUi(row));
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
    final payload = _sessionPayload(local, user.id);
    await _localStore.upsertRow(
      user.id,
      'sessions',
      session.id,
      local.toInsertMap(),
    );
    final operation = await _queueTaskOperation(user.id, 'session', payload);
    if (client == null) return local;
    try {
      final row = await client
          .from('task_sessions')
          .upsert(payload, onConflict: 'id')
          .select()
          .single();
      final saved = TrackedSession.fromMap(_sessionRowForUi(row));
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
          .order('started_at_utc');
      return rows
          .map<TrackedSessionSegment>(
            (row) => TrackedSessionSegment.fromMap(_segmentRowForUi(row)),
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
    await _localStore.upsertRow(user.id, 'session_segments', segment.id, {
      ...segment.toInsertMap(),
      'user_id': user.id,
    });
    final payload = await _segmentPayload(segment, user.id);
    if (payload == null) return segment;
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
      return TrackedSessionSegment.fromMap(_segmentRowForUi(row));
    } on Object catch (error) {
      if (_isConnectivityError(error)) return segment;
      await _localStore.removeOperation(user.id, operation.id);
      rethrow;
    }
  }

  Future<void> addSessionEvent(SessionEventRecord event) async {
    final user = _supabaseService.currentUser;
    if (user == null) return;
    final payload = {...event.toInsertMap(), 'user_id': user.id};
    await _localStore.upsertRow(user.id, 'session_events', event.id, payload);
  }

  Future<List<TaskProgressEntry>> loadProgressEntries(String taskId) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return const [];
    }

    try {
      final row = await client
          .from('tasks')
          .select('id,manual_progress,updated_at')
          .eq('user_id', user.id)
          .eq('id', taskId)
          .maybeSingle();
      if (row == null || row['manual_progress'] == null) return const [];
      return [
        TaskProgressEntry.fromMap({
          'id': '${taskId}_manual_progress',
          'task_id': taskId,
          'progress_percentage': row['manual_progress'],
          'progress_value': row['manual_progress'],
          'progress_unit': 'percent',
          'summary': '',
          'recorded_at': row['updated_at'],
          'created_at': row['updated_at'],
          'updated_at': row['updated_at'],
        }),
      ];
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

    await client
        .from('tasks')
        .update({
          'manual_progress': entry.progressPercentage,
          'progress_method': 'manual',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', entry.taskId)
        .eq('user_id', user.id);
    return entry;
  }

  Future<Map<String, dynamic>> _taskPayloadForRemote(
    TaskItem task, {
    required String userId,
    required SupabaseClient? client,
  }) async {
    final plannedStart = task.plannedStartAt ?? task.scheduledStartAt;
    final plannedEnd = task.plannedEndAt ?? task.scheduledEndAt;
    final plannedDate =
        task.plannedDate ?? task.scheduledLocalDate ?? task.startDate;
    return {
      'id': task.id,
      'user_id': userId,
      'domain_id': await _resolveDomainId(
        task: task,
        userId: userId,
        client: client,
      ),
      'roadmap_id': _uuidOrNull(task.roadmapId),
      'phase_id': task.roadmapId == null
          ? null
          : _uuidOrNull(task.roadmapPhaseId),
      'title': task.title,
      'description': task.description,
      'execution_mode': _cleanExecutionMode(task.executionMode),
      'status': _cleanTaskStatus(task),
      'priority': _cleanPriority(task.priority),
      'planned_local_date': _dateOnly(plannedDate),
      'planned_start_minutes':
          _clockToMinutes(task.scheduledLocalTime) ??
          _minutesFromDateTime(plannedStart),
      'planned_end_minutes': _minutesFromDateTime(plannedEnd),
      'time_zone_behavior': _cleanTimeZoneBehavior(task.timeZoneBehavior),
      'time_zone_id': task.effectiveTimeZoneId.isEmpty
          ? null
          : task.effectiveTimeZoneId,
      'planned_start_at_utc': plannedStart?.toUtc().toIso8601String(),
      'planned_end_at_utc': plannedEnd?.toUtc().toIso8601String(),
      'due_at_utc': (task.dueAt ?? task.dueDate)?.toUtc().toIso8601String(),
      'estimated_duration_seconds': task.estimatedMinutes * 60,
      'estimated_focus_sessions': task.estimatedPomodoros,
      'progress_method': task.checklist.isNotEmpty ? 'checklist' : 'manual',
      'manual_progress': task.progressPercentage,
      'recurrence_rule': task.recurrenceRule,
      'recurrence_time_zone_id': task.recurrenceTimezone,
      'recurrence_series_id': _uuidOrNull(task.seriesTaskId),
      'recurrence_paused': task.recurrencePausedAt != null,
      'reminders_enabled': task.reminderRules.isNotEmpty,
      'adaptive_reminders_enabled': task.adaptiveRemindersEnabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _taskRowForUi(Map<String, dynamic> row) {
    final domain = row['task_domains'];
    final domainName = domain is Map ? domain['name']?.toString() : null;
    final executionMode = row['execution_mode']?.toString();
    final status = row['status']?.toString();
    final archivedAt = status == 'archived'
        ? row['updated_at']?.toString()
        : row['archived_at']?.toString();
    final estimatedSeconds = _intValue(row['estimated_duration_seconds']);
    return {
      ...row,
      'task_type': _legacyTaskType(executionMode),
      'task_domain': _legacyDomainValue(domainName),
      'execution_mode': _legacyExecutionMode(executionMode),
      'category_id': row['domain_id'],
      'category_name': domainName ?? 'Personal',
      'roadmap_phase_id': row['phase_id'],
      'priority': _legacyPriority(row['priority']?.toString()),
      'status': _legacyStatus(status),
      'planned_date': row['planned_local_date'],
      'planned_start_at': row['planned_start_at_utc'],
      'planned_end_at': row['planned_end_at_utc'],
      'due_at': row['due_at_utc'],
      'estimated_minutes': estimatedSeconds <= 0
          ? 25
          : (estimatedSeconds / 60).round(),
      'estimated_pomodoros': row['estimated_focus_sessions'],
      'progress_percentage': _intValue(row['manual_progress']),
      'recurrence_timezone': row['recurrence_time_zone_id'],
      'series_task_id': row['recurrence_series_id'],
      'scheduled_start_at': row['planned_start_at_utc'],
      'scheduled_end_at': row['planned_end_at_utc'],
      'scheduled_local_date': row['planned_local_date'],
      'time_zone_behavior': row['time_zone_behavior'],
      'is_recurring_template': false,
      'is_recurrence_exception': false,
      'archived_at': archivedAt,
    };
  }

  Map<String, dynamic> _workDemandPayload(WorkDemand demand, String userId) {
    return {
      'id': demand.id,
      'user_id': userId,
      'task_id': demand.taskId,
      'title': demand.title,
      'description': demand.description,
      'priority': _cleanDemandPriority(demand.priority),
      'status': _cleanDemandStatus(demand.status),
      'original_due_date': _dateOnly(demand.originalDueDate),
      'current_scheduled_date': _dateOnly(demand.currentScheduledDate),
      'completed_at': demand.completedAt?.toUtc().toIso8601String(),
      'rollover_policy': _cleanRolloverPolicy(demand.rolloverPolicy),
      'sort_order': demand.position,
      'deleted_at': demand.deletedAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _workDemandRowForUi(Map<String, dynamic> row) {
    return {
      ...row,
      'priority': _legacyDemandPriority(row['priority']?.toString()),
      'status': row['status']?.toString() == 'deferred'
          ? 'blocked'
          : row['status'],
      'rollover_policy': row['rollover_policy']?.toString() == 'next_occurrence'
          ? 'next_valid_work_occurrence'
          : row['rollover_policy'],
      'position': row['position'] ?? row['sort_order'],
    };
  }

  Map<String, dynamic> _learningCheckpointPayload(
    LearningCheckpoint checkpoint,
    String userId,
  ) {
    return {
      'id': checkpoint.id,
      'user_id': userId,
      'task_id': checkpoint.taskId,
      'title': checkpoint.title,
      'description': checkpoint.description,
      'status': _cleanCheckpointStatus(checkpoint.status),
      'completion_criteria': checkpoint.completionCriteria,
      'target_date': _dateOnly(checkpoint.targetDate),
      'evidence': checkpoint.evidence,
      'completed_at': checkpoint.completedAt?.toUtc().toIso8601String(),
      'sort_order': checkpoint.position,
      'deleted_at': checkpoint.deletedAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> _learningCheckpointRowForUi(Map<String, dynamic> row) {
    return {
      ...row,
      'status': row['status']?.toString() == 'not_started'
          ? 'open'
          : row['status']?.toString() == 'archived'
          ? 'cancelled'
          : row['status'],
      'position': row['position'] ?? row['sort_order'],
    };
  }

  Map<String, dynamic> _activityIntervalPayload(
    TaskUsageActivity record,
    String userId,
  ) {
    final totalSeconds = record.activeSeconds + record.idleSeconds;
    final durationSeconds = totalSeconds <= 0
        ? record.creditedSeconds
        : totalSeconds;
    final endedAt =
        record.endedAt ??
        record.startedAt.add(Duration(seconds: durationSeconds));
    final isApplication = record.type == TaskActivityType.application;
    return {
      'id': record.id,
      'user_id': userId,
      'session_id': _uuidOrNull(record.sessionId),
      'segment_id': null,
      'task_id': record.taskId,
      'device_id': null,
      'context_type': isApplication ? 'external_application' : 'browser',
      'application_id': isApplication
          ? record.applicationName ?? record.windowTitle
          : record.domain ?? record.normalizedDomain,
      'window_title': record.windowTitle ?? record.pageTitle,
      'resource_id': null,
      'started_at_utc': record.startedAt.toUtc().toIso8601String(),
      'ended_at_utc': endedAt.toUtc().toIso8601String(),
      'duration_seconds': durationSeconds < 0 ? 0 : durationSeconds,
      'idle_seconds': record.idleSeconds < 0 ? 0 : record.idleSeconds,
    };
  }

  Map<String, dynamic> _activityIntervalRowForUi(Map<String, dynamic> row) {
    if (row.containsKey('started_at')) return row;
    final duration = _intValue(row['duration_seconds']);
    final idle = _intValue(row['idle_seconds']);
    final active = duration - idle;
    final contextType = row['context_type']?.toString();
    final isApplication = contextType == 'external_application';
    return {
      ...row,
      'activity_type': isApplication ? 'application' : 'website',
      'application_name': isApplication
          ? row['application_id']?.toString()
          : null,
      'domain': isApplication ? null : row['application_id']?.toString(),
      'window_title': row['window_title'],
      'source_task_id': row['task_id'],
      'started_at': row['started_at_utc'],
      'ended_at': row['ended_at_utc'],
      'active_seconds': active < 0 ? 0 : active,
      'idle_seconds': idle,
      'credited_seconds': active < 0 ? 0 : active,
      'visit_count': 1,
      'is_saved_resource': false,
      'excluded_from_reports': false,
      'user_confirmed': false,
      'is_cross_task_contribution': false,
    };
  }

  Map<String, dynamic> _sessionPayload(TrackedSession session, String userId) {
    return {
      'id': session.id,
      'user_id': userId,
      'task_id': session.taskId,
      'occurrence_id': null,
      'execution_mode': _sessionExecutionMode(session),
      'state': _cleanSessionState(session.status, stage: session.stage),
      'started_at_utc': session.startedAt.toUtc().toIso8601String(),
      'completed_at_utc': session.endedAt?.toUtc().toIso8601String(),
      'accumulated_active_seconds': session.accumulatedActiveSeconds > 0
          ? session.accumulatedActiveSeconds
          : session.activeSeconds,
      'accumulated_paused_seconds': session.accumulatedPausedSeconds > 0
          ? session.accumulatedPausedSeconds
          : session.pausedSeconds,
      'accumulated_idle_seconds': session.idleSeconds,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'revision': session.revision,
    };
  }

  Map<String, dynamic> _sessionRowForUi(Map<String, dynamic> row) {
    final active = _intValue(row['accumulated_active_seconds']);
    final paused = _intValue(row['accumulated_paused_seconds']);
    final idle = _intValue(row['accumulated_idle_seconds']);
    return {
      ...row,
      'started_at': row['started_at_utc'],
      'ended_at': row['completed_at_utc'],
      'gross_seconds': active + paused + idle,
      'active_seconds': active,
      'idle_seconds': idle,
      'paused_seconds': paused,
      'status': _legacySessionStatus(
        row['state']?.toString(),
        row['completed_at_utc'],
      ),
      'stage': row['state'],
      'accumulated_active_seconds': active,
      'accumulated_paused_seconds': paused,
      'sync_status': 'synced',
    };
  }

  Future<Map<String, dynamic>?> _segmentPayload(
    TrackedSessionSegment segment,
    String userId,
  ) async {
    final session = (await _loadLocalSessions(
      userId,
    )).where((item) => item.id == segment.sessionId).firstOrNull;
    final taskId = session?.taskId;
    if (taskId == null || taskId.isEmpty) return null;
    final active = segment.type.countsAsActive ? segment.durationSeconds : 0;
    final paused = segment.type == SessionSegmentType.paused
        ? segment.durationSeconds
        : segment.accumulatedPausedSeconds;
    final idle = segment.type == SessionSegmentType.idle
        ? segment.durationSeconds
        : 0;
    return {
      'id': segment.id,
      'user_id': userId,
      'session_id': segment.sessionId,
      'task_id': taskId,
      'segment_number': await _localSegmentNumber(userId, segment),
      'segment_type': _cleanSegmentType(segment.type),
      'state': segment.endedAt == null ? 'running' : 'completed',
      'planned_duration_seconds': segment.plannedDurationSeconds,
      'actual_active_seconds': active < 0 ? 0 : active,
      'paused_seconds': paused < 0 ? 0 : paused,
      'idle_seconds': idle < 0 ? 0 : idle,
      'started_at_utc': segment.startedAt.toUtc().toIso8601String(),
      'last_resumed_at_utc': segment.startedAt.toUtc().toIso8601String(),
      'completed_at_utc': (segment.completedAt ?? segment.endedAt)
          ?.toUtc()
          .toIso8601String(),
      'transition_reason': segment.transitionReason,
      'parent_segment_id': null,
      'created_at': segment.createdAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<int> _localSegmentNumber(
    String userId,
    TrackedSessionSegment segment,
  ) async {
    final rows = await _localStore.loadRows(userId, 'session_segments');
    final matching =
        [
          for (final row in rows)
            if (row['session_id']?.toString() == segment.sessionId) row,
        ]..sort((a, b) {
          final aStarted =
              DateTime.tryParse(a['started_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bStarted =
              DateTime.tryParse(b['started_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final byTime = aStarted.compareTo(bStarted);
          if (byTime != 0) return byTime;
          return (a['id']?.toString() ?? '').compareTo(
            b['id']?.toString() ?? '',
          );
        });
    final index = matching.indexWhere(
      (row) => row['id']?.toString() == segment.id,
    );
    return index < 0 ? matching.length + 1 : index + 1;
  }

  Map<String, dynamic> _segmentRowForUi(Map<String, dynamic> row) {
    final active = _intValue(row['actual_active_seconds']);
    final paused = _intValue(row['paused_seconds']);
    final idle = _intValue(row['idle_seconds']);
    return {
      ...row,
      'segment_type': _legacySegmentType(row['segment_type']?.toString()),
      'started_at': row['started_at_utc'],
      'ended_at': row['completed_at_utc'],
      'duration_seconds': active + paused + idle,
      'planned_duration_seconds': row['planned_duration_seconds'],
      'accumulated_active_seconds': active,
      'accumulated_paused_seconds': paused,
      'completed_at': row['completed_at_utc'],
      'source': 'timer',
      'stage': row['state'],
    };
  }

  Future<String?> _resolveDomainId({
    required TaskItem task,
    required String userId,
    required SupabaseClient? client,
  }) async {
    if (client == null) return null;
    final name = _domainNameForTask(task);
    try {
      final existing = await client
          .from('task_domains')
          .select('id')
          .eq('user_id', userId)
          .ilike('name', name)
          .isFilter('deleted_at', null)
          .limit(1)
          .maybeSingle();
      final existingId = existing?['id']?.toString();
      if (existingId != null) {
        return existingId;
      }
      final inserted = await client
          .from('task_domains')
          .insert({
            'user_id': userId,
            'name': name,
            'icon': _taskDomainIcon(name),
            'color': _domainColor(task.taskDomain),
            'sort_order': 900,
            'is_template': false,
          })
          .select('id')
          .single();
      return inserted['id']?.toString();
    } on Object {
      return null;
    }
  }

  String _domainNameForTask(TaskItem task) {
    if (task.taskDomain == TaskDomain.custom &&
        task.category.trim().isNotEmpty) {
      return task.category.trim();
    }
    return switch (task.taskDomain) {
      TaskDomain.work => 'Work',
      TaskDomain.learning => 'Learning',
      TaskDomain.reading => 'Reading',
      TaskDomain.selfImprovement => 'Self-improvement',
      TaskDomain.household => 'Householding',
      TaskDomain.sport => 'Sport',
      TaskDomain.event => 'Event',
      TaskDomain.personal => 'Personal',
      TaskDomain.custom => 'Personal',
    };
  }

  static String _runtimeEventName(String entityType) {
    return switch (entityType) {
      'roadmap' || 'roadmap_phase' || 'roadmap_milestone' => 'roadmap_changed',
      'session' || 'session_segment' => 'session_changed',
      'activity' || 'activity_interval' => 'activity_changed',
      'settings' => 'settings_changed',
      'notification' || 'task_reminder' => 'notification_changed',
      _ => 'task_changed',
    };
  }

  static String _cleanExecutionMode(TaskExecutionMode mode) {
    return switch (mode) {
      TaskExecutionMode.pomodoroFocus => 'pomodoro',
      TaskExecutionMode.continuousTimer => 'continuous_timer',
      TaskExecutionMode.checklist => 'checklist',
      TaskExecutionMode.readingSession => 'reading',
      TaskExecutionMode.habit => 'habit',
      TaskExecutionMode.event => 'event',
      TaskExecutionMode.manualCompletion => 'manual_completion',
      TaskExecutionMode.hybrid => 'hybrid',
    };
  }

  static String _cleanTaskStatus(TaskItem task) {
    if (task.archivedAt != null) return 'archived';
    return switch (task.status) {
      TaskStatus.running => 'running',
      TaskStatus.paused || TaskStatus.interrupted => 'paused',
      TaskStatus.completed => 'completed',
      TaskStatus.cancelled => 'cancelled',
      TaskStatus.ready ||
      TaskStatus.waiting ||
      TaskStatus.reviewRequired ||
      TaskStatus.overdue => 'scheduled',
      _ => 'not_started',
    };
  }

  static String _cleanPriority(TaskPriority priority) {
    return switch (priority) {
      TaskPriority.critical => 'urgent',
      TaskPriority.high => 'high',
      TaskPriority.normal => 'medium',
      TaskPriority.low => 'low',
    };
  }

  static String _cleanDemandPriority(String priority) {
    return switch (priority.trim().toLowerCase()) {
      'critical' || 'urgent' => 'urgent',
      'high' => 'high',
      'low' => 'low',
      _ => 'medium',
    };
  }

  static String _legacyDemandPriority(String? priority) {
    return switch (priority) {
      'urgent' => 'critical',
      'high' => 'high',
      'low' => 'low',
      _ => 'normal',
    };
  }

  static String _cleanDemandStatus(WorkDemandStatus status) {
    return switch (status) {
      WorkDemandStatus.inProgress => 'in_progress',
      WorkDemandStatus.completed => 'completed',
      WorkDemandStatus.cancelled => 'cancelled',
      WorkDemandStatus.blocked => 'deferred',
      WorkDemandStatus.open => 'open',
    };
  }

  static String _cleanCheckpointStatus(LearningCheckpointStatus status) {
    return switch (status) {
      LearningCheckpointStatus.inProgress => 'in_progress',
      LearningCheckpointStatus.completed => 'completed',
      LearningCheckpointStatus.skipped => 'skipped',
      LearningCheckpointStatus.cancelled => 'archived',
      LearningCheckpointStatus.open => 'not_started',
    };
  }

  static String _cleanRolloverPolicy(String policy) {
    return switch (policy.trim().toLowerCase()) {
      'none' => 'none',
      'manual' => 'manual',
      'next_work_day' => 'next_work_day',
      _ => 'next_occurrence',
    };
  }

  static String _cleanTimeZoneBehavior(String value) {
    return switch (value) {
      'fixed_time_zone' => 'fixed_time_zone',
      'device_time_zone' => 'device_time_zone',
      'keep_local_clock' => 'keep_local_clock',
      'keep_absolute_time' => 'keep_absolute_time',
      _ => 'floating',
    };
  }

  static String _sessionExecutionMode(TrackedSession session) {
    final stage = _cleanRuntimeStage(session.stage);
    if (stage != null &&
        (stage.startsWith('focus_') || stage.startsWith('break_'))) {
      return 'pomodoro';
    }
    return switch (session.trackingMode) {
      SessionTrackingMode.reading => 'reading',
      SessionTrackingMode.manual => 'manual_completion',
      _ => 'continuous_timer',
    };
  }

  static String _cleanSessionState(
    TrackedSessionStatus status, {
    String? stage,
  }) {
    final cleanStage = _cleanRuntimeStage(stage);
    if (cleanStage != null) return cleanStage;
    return switch (status) {
      TrackedSessionStatus.running => 'running',
      TrackedSessionStatus.paused => 'paused',
      TrackedSessionStatus.completed ||
      TrackedSessionStatus.stopped ||
      TrackedSessionStatus.corrected => 'task_completed',
      TrackedSessionStatus.discarded => 'cancelled',
      _ => 'focus_ready',
    };
  }

  static String? _cleanRuntimeStage(String? stage) {
    return switch (stage) {
      'focus_ready' ||
      'focus_running' ||
      'focus_paused' ||
      'focus_completed_waiting' ||
      'break_ready' ||
      'break_running' ||
      'break_paused' ||
      'break_completed_waiting' ||
      'running' ||
      'paused' ||
      'task_completed' ||
      'cancelled' => stage,
      _ => null,
    };
  }

  static String _legacySessionStatus(String? state, Object? completedAt) {
    if (completedAt != null) return 'completed';
    return switch (state) {
      'focus_running' || 'break_running' => 'running',
      'focus_paused' || 'break_paused' => 'paused',
      'focus_ready' ||
      'break_ready' ||
      'focus_completed_waiting' ||
      'break_completed_waiting' => 'paused',
      'running' => 'running',
      'paused' => 'paused',
      'task_completed' => 'completed',
      'cancelled' => 'discarded',
      _ => 'created',
    };
  }

  static String _cleanSegmentType(SessionSegmentType type) {
    return switch (type) {
      SessionSegmentType.breakTime => 'short_break',
      SessionSegmentType.reading || SessionSegmentType.video => 'reading',
      SessionSegmentType.manual => 'manual',
      _ => 'continuous_work',
    };
  }

  static String _legacySegmentType(String? type) {
    return switch (type) {
      'short_break' || 'long_break' => 'break',
      'reading' => 'reading',
      'manual' => 'manual',
      _ => 'active',
    };
  }

  static String _legacyTaskType(String? executionMode) {
    return switch (executionMode) {
      'continuous_timer' => 'timed',
      'event' => 'event',
      'habit' => 'habit',
      'reading' => 'reading',
      'manual_completion' => 'manual',
      _ => 'focus',
    };
  }

  static String _legacyExecutionMode(String? executionMode) {
    return switch (executionMode) {
      'pomodoro' => 'pomodoro_focus',
      'reading' => 'reading_session',
      'continuous_timer' => 'continuous_timer',
      'checklist' => 'checklist',
      'habit' => 'habit',
      'event' => 'event',
      'manual_completion' => 'manual_completion',
      'hybrid' => 'hybrid',
      _ => 'manual_completion',
    };
  }

  static String _legacyPriority(String? priority) {
    return switch (priority) {
      'urgent' => 'critical',
      'high' => 'high',
      'low' => 'low',
      _ => 'normal',
    };
  }

  static String _legacyStatus(String? status) {
    return switch (status) {
      'running' => 'running',
      'paused' => 'paused',
      'completed' => 'completed',
      'cancelled' => 'cancelled',
      'scheduled' => 'ready',
      _ => 'not_started',
    };
  }

  static String _legacyDomainValue(String? name) {
    return switch (name?.trim().toLowerCase()) {
      'work' => 'work',
      'learning' => 'learning',
      'reading' => 'reading',
      'self-improvement' || 'self improvement' => 'self_improvement',
      'householding' || 'household' => 'household',
      'sport' => 'sport',
      'event' => 'event',
      'personal' => 'personal',
      _ => 'custom',
    };
  }

  static String _taskDomainIcon(String name) {
    return switch (name.trim().toLowerCase()) {
      'work' => 'briefcase',
      'learning' => 'graduation-cap',
      'reading' => 'book-open',
      'self-improvement' || 'self improvement' => 'sparkles',
      'householding' || 'household' => 'home',
      'sport' => 'dumbbell',
      'event' => 'calendar',
      'habit' => 'repeat',
      _ => 'circle',
    };
  }

  static String _domainColor(TaskDomain domain) {
    return switch (domain) {
      TaskDomain.work => '#3B82F6',
      TaskDomain.learning => '#22D3EE',
      TaskDomain.reading => '#6366F1',
      TaskDomain.selfImprovement => '#A855F7',
      TaskDomain.household => '#84CC16',
      TaskDomain.sport => '#22C55E',
      TaskDomain.event => '#F97316',
      TaskDomain.personal => '#64748B',
      TaskDomain.custom => '#64748B',
    };
  }

  static String? _uuidOrNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(value)
        ? value
        : null;
  }

  static String? _dateOnly(DateTime? value) =>
      value?.toIso8601String().split('T').first;

  static int? _minutesFromDateTime(DateTime? value) {
    if (value == null) return null;
    final local = value.toLocal();
    return local.hour * 60 + local.minute;
  }

  static int? _clockToMinutes(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
    return hours * 60 + minutes;
  }

  static String _colorToStorage(int value) {
    return '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
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
              'status': 'archived',
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
          await client.from('activity_intervals').upsert(rows);
        }
      case 'session':
        await client.from('task_sessions').upsert(payload, onConflict: 'id');
      case 'session_segment':
        await client.from('session_segments').upsert(payload, onConflict: 'id');
      case 'session_event':
        return;
      case 'work_demand':
        await client.from('task_demands').upsert(payload, onConflict: 'id');
      case 'learning_checkpoint':
        await client.from('task_checkpoints').upsert(payload, onConflict: 'id');
      case 'widget_action_event':
        return;
      case 'note_upsert':
        await client.from('task_notes').upsert(payload, onConflict: 'id');
      case 'note_delete':
        await client
            .from('task_notes')
            .update({'deleted_at': payload['deleted_at']})
            .eq('id', payload['id'])
            .eq('user_id', userId);
      case 'interruption_upsert':
        return;
      case 'interruption_delete':
        return;
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
          .update({
            'recurrence_rule': rrule,
            'recurrence_time_zone_id': original.recurrenceTimezone,
            'recurrence_series_id': saved.id,
            'recurrence_paused': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', saved.id);
    } on Object {
      // Keep the task usable if recurrence metadata cannot be synchronized.
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
