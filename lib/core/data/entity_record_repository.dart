import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../platform/device_identity.dart';

class EntityRecordDraft {
  const EntityRecordDraft({
    this.id,
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

  /// Optional permanent identity for records whose domain has a canonical
  /// natural key. Most records continue to receive a random UUID.
  final String? id;
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
            row.userId.equals(userId) &
            row.entityType.equals(entityType) &
            row.deletedAt.isNull();
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
            row.userId.equals(userId) &
            row.entityType.equals(entityType) &
            row.deletedAt.isNull();
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
    return (database.select(database.localEntityRecords)..where(
          (row) =>
              row.id.equals(id) &
              row.userId.equals(userId) &
              row.deletedAt.isNull(),
        ))
        .getSingleOrNull();
  }

  Future<LocalEntityRecord?> getIncludingDeleted(String id) {
    return (database.select(database.localEntityRecords)
          ..where((row) => row.id.equals(id) & row.userId.equals(userId)))
        .getSingleOrNull();
  }

  Future<String> create(EntityRecordDraft draft) async {
    final title = draft.title.trim();
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(userId);
    final sequence = await DeviceIdentity.nextSequence(userId);
    final id = draft.id ?? _uuid.v4();
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
    final deviceId = await DeviceIdentity.accountId(userId);
    final sequence = await DeviceIdentity.nextSequence(userId);
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
      await (database.update(database.localEntityRecords)..where(
            (row) => row.id.equals(record.id) & row.userId.equals(userId),
          ))
          .write(
            LocalEntityRecordsCompanion(
              title: title == null ? const Value.absent() : Value(title.trim()),
              status: status == null ? const Value.absent() : Value(status),
              position: position == null
                  ? const Value.absent()
                  : Value(position),
              parentId: parentId == null
                  ? const Value.absent()
                  : Value(parentId),
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

  /// Persists device-only metadata without advancing the canonical revision.
  ///
  /// Open counters, last-read positions and similar local observations are not
  /// synchronization commands. Advancing [revision] for them would make the
  /// next real edit use a base revision the server has never seen, creating a
  /// false `revision_mismatch` conflict.
  Future<void> updateLocalData(
    LocalEntityRecord record, {
    required Map<String, Object?> data,
  }) async {
    await (database.update(
          database.localEntityRecords,
        )..where((row) => row.id.equals(record.id) & row.userId.equals(userId)))
        .write(
          LocalEntityRecordsCompanion(
            dataJson: Value(jsonEncode(data)),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> softDelete(
    LocalEntityRecord record, {
    Map<String, Object?> payload = const {},
    bool synchronize = true,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(userId);
    final sequence = await DeviceIdentity.nextSequence(userId);
    final commandId = _uuid.v4();
    await database.transaction(() async {
      await (database.update(database.localEntityRecords)..where(
            (row) => row.id.equals(record.id) & row.userId.equals(userId),
          ))
          .write(
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

  /// Restores a soft-deleted generic entity using the revision immediately
  /// produced by its delete command.
  ///
  /// The server's generic update path clears `deleted_at` even for an empty
  /// payload, so Undo remains an idempotent canonical command instead of a
  /// device-only visual reversal.
  Future<void> restore(
    String recordId, {
    String? title,
    String? status,
    String? parentId,
    String? secondaryParentId,
    Map<String, Object?>? data,
    Map<String, Object?>? syncPayload,
  }) async {
    final record =
        await (database.select(database.localEntityRecords)..where(
              (row) => row.id.equals(recordId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (record == null || record.deletedAt == null) return;

    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(userId);
    final sequence = await DeviceIdentity.nextSequence(userId);
    final commandId = _uuid.v4();
    await database.transaction(() async {
      await (database.update(database.localEntityRecords)..where(
            (row) => row.id.equals(record.id) & row.userId.equals(userId),
          ))
          .write(
            LocalEntityRecordsCompanion(
              title: title == null ? const Value.absent() : Value(title.trim()),
              status: status == null ? const Value.absent() : Value(status),
              parentId: parentId == null
                  ? const Value.absent()
                  : Value(parentId),
              secondaryParentId: secondaryParentId == null
                  ? const Value.absent()
                  : Value(secondaryParentId),
              dataJson: data == null
                  ? const Value.absent()
                  : Value(jsonEncode(data)),
              deletedAt: const Value(null),
              revision: Value(record.revision + 1),
              updatedAt: Value(now),
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityType: record.entityType,
        entityId: record.id,
        commandType: 'update',
        baseRevision: record.revision,
        payload: syncPayload ?? const {},
        now: now,
      );
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
  }) async {
    final wirePayload = _wirePayload(entityType, payload);
    // A record can be edited repeatedly while it is still waiting for its
    // initial upload.  Keeping each intermediate update creates a revision
    // chain the server can never accept (the create is still revision 0), and
    // was the source of large offline queues on Android.  Retain one durable
    // command with the newest complete state instead.
    final pending =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.entityType.equals(entityType) &
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
            payloadJson: Value(
              _encodeMergedPayload(existingPayload, wirePayload),
            ),
            clientTimestamp: Value(now),
          ),
        );
        return;
      }
    }

    if (commandType == 'delete') {
      // A locally created record deleted before its first upload has no
      // remote representation to delete.  Retire the create instead of
      // producing an invalid delete command.
      if (pendingCreate != null) {
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(pendingCreate.commandId))).write(
          const LocalOutboxCommandsCompanion(
            status: Value('superseded'),
            lastError: Value(null),
          ),
        );
        return;
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
        return;
      }
    }

    await database
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
            payloadJson: jsonEncode(wirePayload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  Map<String, Object?> _decodePayload(String raw) {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, Object?>.from(decoded)
        : <String, Object?>{};
  }

  Map<String, Object?> _wirePayload(
    String entityType,
    Map<String, Object?> payload,
  ) {
    final normalized = <String, Object?>{...payload};
    // PostgreSQL arrays are represented by the generic command endpoint as
    // their text-array literal, while the editor naturally holds weekdays as
    // a Dart list. Convert at the synchronization boundary only.
    if (entityType == 'recurrence_rules' && normalized['weekdays'] is List) {
      final days = (normalized['weekdays'] as List)
          .whereType<num>()
          .map((day) => day.toInt())
          .join(',');
      normalized['weekdays'] = '{$days}';
    }
    return normalized;
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
}
