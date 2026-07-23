import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../domain/task_item.dart';

class PendingTaskOperation {
  PendingTaskOperation({
    String? id,
    String? mutationId,
    required this.type,
    required this.payload,
    this.deviceId = '',
    this.entityType = 'task',
    this.entityId = '',
    this.operation = '',
    this.baseRevision = 0,
    this.changedFields = const [],
    DateTime? createdAt,
    this.attemptCount = 0,
    this.syncState = 'pending',
    this.lastError,
  }) : id = mutationId ?? id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final String deviceId;
  final String entityType;
  final String entityId;
  final String operation;
  final int baseRevision;
  final List<String> changedFields;
  final DateTime createdAt;
  final int attemptCount;
  final String syncState;
  final String? lastError;

  String get mutationId => id;

  PendingTaskOperation copyWith({
    int? attemptCount,
    String? syncState,
    String? lastError,
  }) {
    return PendingTaskOperation(
      mutationId: id,
      type: type,
      payload: payload,
      deviceId: deviceId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      baseRevision: baseRevision,
      changedFields: changedFields,
      createdAt: createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      syncState: syncState ?? this.syncState,
      lastError: lastError ?? this.lastError,
    );
  }

  factory PendingTaskOperation.fromMap(Map<String, dynamic> map) {
    return PendingTaskOperation(
      id: map['id']?.toString(),
      type: map['type']?.toString() ?? '',
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : const {},
      deviceId: map['device_id']?.toString() ?? '',
      entityType: map['entity_type']?.toString() ?? 'task',
      entityId: map['entity_id']?.toString() ?? '',
      operation: map['operation']?.toString() ?? map['type']?.toString() ?? '',
      baseRevision: _int(map['base_revision']),
      changedFields: map['changed_fields'] is List
          ? (map['changed_fields'] as List).map((value) => '$value').toList()
          : const [],
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      attemptCount: _int(map['attempt_count']),
      syncState: map['sync_state']?.toString() ?? 'pending',
      lastError: map['last_error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'payload': payload,
    'device_id': deviceId,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation.isEmpty ? type : operation,
    'base_revision': baseRevision,
    'changed_fields': changedFields,
    'created_at': createdAt.toUtc().toIso8601String(),
    'attempt_count': attemptCount,
    'sync_state': syncState,
    'last_error': lastError,
  };
}

class TaskLocalSnapshot {
  const TaskLocalSnapshot({this.tasks = const [], this.operations = const []});

  final List<TaskItem> tasks;
  final List<PendingTaskOperation> operations;
}

class TaskLocalStore {
  TaskLocalStore({Directory? baseDirectory}) : _baseDirectory = baseDirectory;

  final Directory? _baseDirectory;
  Future<void> _writeTail = Future<void>.value();

  Future<TaskLocalSnapshot> load(String userId) async {
    final raw = await _read(userId);
    final taskRows = raw['tasks'];
    final operationRows = raw['operations'];
    return TaskLocalSnapshot(
      tasks: taskRows is List
          ? [
              for (final row in taskRows)
                if (row is Map)
                  TaskItem.fromMap(Map<String, dynamic>.from(row)),
            ]
          : const [],
      operations: operationRows is List
          ? [
              for (final row in operationRows)
                if (row is Map)
                  PendingTaskOperation.fromMap(Map<String, dynamic>.from(row)),
            ]
          : const [],
    );
  }

  Future<void> replaceTasks(String userId, List<TaskItem> tasks) {
    return _mutate(userId, (raw) {
      raw['tasks'] = [for (final task in tasks) _taskMap(task)];
    });
  }

  Future<void> upsertTask(String userId, TaskItem task) {
    return _mutate(userId, (raw) {
      final rows = raw['tasks'] is List
          ? List<Object?>.from(raw['tasks'] as List)
          : <Object?>[];
      rows.removeWhere((row) => row is Map && row['id']?.toString() == task.id);
      rows.add(_taskMap(task));
      raw['tasks'] = rows;
    });
  }

  Future<void> removeTask(String userId, String taskId) {
    return _mutate(userId, (raw) {
      final rows = raw['tasks'] is List
          ? List<Object?>.from(raw['tasks'] as List)
          : <Object?>[];
      rows.removeWhere((row) => row is Map && row['id']?.toString() == taskId);
      raw['tasks'] = rows;
    });
  }

  Future<List<Map<String, dynamic>>> loadRows(
    String userId,
    String collection,
  ) async {
    final raw = await _read(userId);
    final rows = raw[collection];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  Future<void> upsertRow(
    String userId,
    String collection,
    String id,
    Map<String, dynamic> row,
  ) {
    return _mutate(userId, (raw) {
      final rows = raw[collection] is List
          ? List<Object?>.from(raw[collection] as List)
          : <Object?>[];
      rows.removeWhere(
        (value) => value is Map && value['id']?.toString() == id,
      );
      rows.add(row);
      raw[collection] = rows;
    });
  }

  Future<void> replaceRowsWhere(
    String userId,
    String collection,
    String field,
    Set<String> values,
    List<Map<String, dynamic>> replacements,
  ) {
    return _mutate(userId, (raw) {
      final rows = raw[collection] is List
          ? List<Object?>.from(raw[collection] as List)
          : <Object?>[];
      rows.removeWhere(
        (row) => row is Map && values.contains(row[field]?.toString()),
      );
      rows.addAll(replacements);
      raw[collection] = rows;
    });
  }

  Future<void> enqueue(String userId, PendingTaskOperation operation) {
    return _mutate(userId, (raw) {
      final rows = raw['operations'] is List
          ? List<Object?>.from(raw['operations'] as List)
          : <Object?>[];
      rows.removeWhere(
        (row) => row is Map && row['id']?.toString() == operation.id,
      );
      rows.add(operation.toMap());
      raw['operations'] = rows;
    });
  }

  Future<void> removeOperation(String userId, String operationId) {
    return _mutate(userId, (raw) {
      final rows = raw['operations'] is List
          ? List<Object?>.from(raw['operations'] as List)
          : <Object?>[];
      rows.removeWhere(
        (row) => row is Map && row['id']?.toString() == operationId,
      );
      raw['operations'] = rows;
    });
  }

  Future<void> updateOperation(String userId, PendingTaskOperation operation) =>
      enqueue(userId, operation);

  Future<String> loadDeviceId() async {
    final base = _baseDirectory ?? _defaultBaseDirectory();
    final file = File(
      '${base.path}${Platform.pathSeparator}TaskMasterPro'
      '${Platform.pathSeparator}device-id',
    );
    if (await file.exists()) {
      final value = (await file.readAsString()).trim();
      if (value.isNotEmpty) return value;
    }
    final value = const Uuid().v4();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
    return value;
  }

  Future<void> _mutate(
    String userId,
    void Function(Map<String, dynamic> raw) change,
  ) {
    final operation = _writeTail.then((_) async {
      final raw = await _read(userId);
      change(raw);
      await _write(userId, raw);
    });
    _writeTail = operation.catchError((_) {});
    return operation;
  }

  Future<Map<String, dynamic>> _read(String userId) async {
    final file = _file(userId);
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  Future<void> _write(String userId, Map<String, dynamic> raw) async {
    final file = _file(userId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(raw), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  File _file(String userId) {
    final base = _baseDirectory ?? _defaultBaseDirectory();
    return File(
      '${base.path}${Platform.pathSeparator}TaskMasterPro'
      '${Platform.pathSeparator}users'
      '${Platform.pathSeparator}$userId'
      '${Platform.pathSeparator}tasks-local.json',
    );
  }

  static Directory _defaultBaseDirectory() {
    final path = Platform.isWindows
        ? Platform.environment['LOCALAPPDATA'] ??
              Platform.environment['APPDATA']
        : Platform.environment['HOME'];
    return path == null || path.trim().isEmpty
        ? Directory.systemTemp
        : Directory(path);
  }

  static Map<String, dynamic> _taskMap(TaskItem task) => {
    'id': task.id,
    ...task.toInsertMap(),
    'created_at': task.createdAt.toUtc().toIso8601String(),
    'updated_at': task.updatedAt.toUtc().toIso8601String(),
    'deleted_at': task.deletedAt?.toUtc().toIso8601String(),
  };
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
