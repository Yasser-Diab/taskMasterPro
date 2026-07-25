import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../platform/device_identity.dart';

class EntityRecordDraft {
  const EntityRecordDraft({
    required this.entityType,
    required this.title,
    this.parentId,
    this.secondaryParentId,
    this.status = 'active',
    this.position = 0,
    this.data = const {},
    this.syncPayload,
    this.synchronize = true,
  });

  final String entityType;
  final String title;
  final String? parentId;
  final String? secondaryParentId;
  final String status;
  final double position;
  final Map<String, Object?> data;
  final Map<String, Object?>? syncPayload;
  final bool synchronize;
}

class EntityRecordRepository {
  EntityRecordRepository(this.database, this.client);

  final AppDatabase database;
  final SupabaseClient client;
  static const _uuid = Uuid();

  String get userId => client.auth.currentUser?.id ?? 'local';

  Stream<List<LocalEntityRecord>> watch({
    required String entityType,
    String? parentId,
    String? secondaryParentId,
  }) {
    final query = database.select(database.localEntityRecords)
      ..where((row) {
        var expression =
            row.entityType.equals(entityType) & row.deletedAt.isNull();
        if (parentId != null) {
          expression = expression & row.parentId.equals(parentId);
        }
        if (secondaryParentId != null) {
          expression =
              expression & row.secondaryParentId.equals(secondaryParentId);
        }
        return expression;
      })
      ..orderBy([
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.createdAt),
      ]);
    return query.watch();
  }

  Future<List<LocalEntityRecord>> list({
    required String entityType,
    String? parentId,
    String? secondaryParentId,
  }) {
    final query = database.select(database.localEntityRecords)
      ..where((row) {
        var expression =
            row.entityType.equals(entityType) & row.deletedAt.isNull();
        if (parentId != null) {
          expression = expression & row.parentId.equals(parentId);
        }
        if (secondaryParentId != null) {
          expression =
              expression & row.secondaryParentId.equals(secondaryParentId);
        }
        return expression;
      })
      ..orderBy([
        (row) => OrderingTerm.asc(row.position),
        (row) => OrderingTerm.asc(row.createdAt),
      ]);
    return query.get();
  }

  Future<LocalEntityRecord?> get(String id) {
    return (database.select(database.localEntityRecords)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<String> create(EntityRecordDraft draft) async {
    final title = draft.title.trim();
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final id = _uuid.v4();
    final commandId = _uuid.v4();
    final payload = draft.syncPayload ?? _defaultPayload(draft);

    await database.transaction(() async {
      await database
          .into(database.localEntityRecords)
          .insert(
            LocalEntityRecordsCompanion.insert(
              id: id,
              userId: userId,
              entityType: draft.entityType,
              parentId: Value(draft.parentId),
              secondaryParentId: Value(draft.secondaryParentId),
              title: Value(title),
              status: Value(draft.status),
              position: Value(draft.position),
              dataJson: Value(jsonEncode(draft.data)),
              createdAt: now,
              updatedAt: now,
              createdByDeviceId: Value(deviceId),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      if (draft.synchronize) {
        await _enqueue(
          commandId: commandId,
          deviceId: deviceId,
          sequence: sequence,
          entityType: draft.entityType,
          entityId: id,
          commandType: 'create',
          baseRevision: 0,
          payload: payload,
          now: now,
        );
      }
    });
    return id;
  }

  Future<void> update(
    LocalEntityRecord record, {
    String? title,
    String? status,
    double? position,
    String? parentId,
    String? secondaryParentId,
    Map<String, Object?>? data,
    Map<String, Object?>? syncPayload,
    bool synchronize = true,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    final nextData = data ?? decode(record);
    final payload = syncPayload ?? <String, Object?>{...nextData};
    if (syncPayload == null) {
      if (title != null) payload['title'] = title.trim();
      if (status != null) payload['status'] = status;
      if (position != null) payload['position'] = position;
      if (parentId != null) payload['parent_id'] = parentId;
      if (secondaryParentId != null) {
        payload['secondary_parent_id'] = secondaryParentId;
      }
    }

    await database.transaction(() async {
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(record.id))).write(
        LocalEntityRecordsCompanion(
          title: title == null ? const Value.absent() : Value(title.trim()),
          status: status == null ? const Value.absent() : Value(status),
          position: position == null ? const Value.absent() : Value(position),
          parentId: parentId == null ? const Value.absent() : Value(parentId),
          secondaryParentId: secondaryParentId == null
              ? const Value.absent()
              : Value(secondaryParentId),
          dataJson: Value(jsonEncode(nextData)),
          revision: Value(record.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      if (synchronize) {
        await _enqueue(
          commandId: commandId,
          deviceId: deviceId,
          sequence: sequence,
          entityType: record.entityType,
          entityId: record.id,
          commandType: 'update',
          baseRevision: record.revision,
          payload: payload,
          now: now,
        );
      }
    });
  }

  Future<void> softDelete(
    LocalEntityRecord record, {
    Map<String, Object?> payload = const {},
    bool synchronize = true,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    await database.transaction(() async {
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(record.id))).write(
        LocalEntityRecordsCompanion(
          deletedAt: Value(now),
          revision: Value(record.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      if (synchronize) {
        await _enqueue(
          commandId: commandId,
          deviceId: deviceId,
          sequence: sequence,
          entityType: record.entityType,
          entityId: record.id,
          commandType: 'delete',
          baseRevision: record.revision,
          payload: payload,
          now: now,
        );
      }
    });
  }

  Map<String, Object?> decode(LocalEntityRecord record) {
    final value = jsonDecode(record.dataJson);
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  Map<String, Object?> _defaultPayload(EntityRecordDraft draft) {
    return <String, Object?>{
      if (draft.title.trim().isNotEmpty) 'title': draft.title.trim(),
      if (draft.parentId != null) 'parent_id': draft.parentId,
      if (draft.secondaryParentId != null)
        'secondary_parent_id': draft.secondaryParentId,
      'status': draft.status,
      'position': draft.position,
      ...draft.data,
    };
  }

  Future<void> _enqueue({
    required String commandId,
    required String deviceId,
    required int sequence,
    required String entityType,
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
            userId: userId,
            deviceId: deviceId,
            deviceSequence: sequence,
            entityType: entityType,
            entityId: entityId,
            commandType: commandType,
            baseRevision: baseRevision,
            payloadJson: jsonEncode(payload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }
}
