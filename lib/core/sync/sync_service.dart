import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../platform/device_identity.dart';

enum SyncHealth { offline, idle, syncing, attention }

class SyncService {
  SyncService({required this.database, required this.client});

  final AppDatabase database;
  final SupabaseClient client;

  final _health = StreamController<SyncHealth>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _drainTimer;
  RealtimeChannel? _channel;

  Stream<SyncHealth> get health => _health.stream;

  Future<void> start() async {
    await _registerDevice();
    _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.every((result) => result == ConnectivityResult.none)) {
        _health.add(SyncHealth.offline);
        return;
      }
      unawaited(drainOutbox());
    });
    _drainTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(drainOutbox()),
    );
    await _subscribeToAccount();
    await drainOutbox();
  }

  Future<void> _registerDevice() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final deviceId = await DeviceIdentity.id();
    await client.from('account_devices').upsert({
      'id': deviceId,
      'user_id': user.id,
      'device_name': DeviceIdentity.displayName,
      'platform': DeviceIdentity.platform,
      'app_version': '0.1.0',
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by_device_id': deviceId,
    });
  }

  Future<void> _subscribeToAccount() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    await _channel?.unsubscribe();
    _channel = client.channel('taskmaster:user:${user.id}:runtime');
    _channel!
        .onBroadcast(
          event: 'entity_changed',
          callback: (_) => unawaited(pullChanges()),
        )
        .subscribe();
  }

  Future<void> drainOutbox() async {
    final user = client.auth.currentUser;
    if (user == null) {
      _health.add(SyncHealth.idle);
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((result) => result == ConnectivityResult.none)) {
      _health.add(SyncHealth.offline);
      return;
    }

    final query = database.select(database.localOutboxCommands)
      ..where((row) => row.status.equals('pending'))
      ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)])
      ..limit(50);
    final commands = await query.get();
    if (commands.isEmpty) {
      _health.add(SyncHealth.idle);
      return;
    }

    _health.add(SyncHealth.syncing);
    var needsAttention = false;

    for (final command in commands) {
      try {
        if (command.entityType != 'task_occurrences') continue;
        final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
        final response = await client.rpc<Object?>(
          'apply_task_occurrence_command',
          params: {
            'p_command_id': command.commandId,
            'p_device_id': command.deviceId,
            'p_device_sequence': command.deviceSequence,
            'p_entity_id': command.entityId,
            'p_base_revision': command.baseRevision,
            'p_operation': command.commandType,
            'p_payload': payload,
          },
        );
        final result = response is Map
            ? Map<String, dynamic>.from(response)
            : <String, dynamic>{};
        final remoteStatus = result['status'] as String?;
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          LocalOutboxCommandsCompanion(
            status: Value(remoteStatus == 'accepted' ? 'accepted' : 'conflict'),
            lastError: remoteStatus == 'accepted'
                ? const Value.absent()
                : Value(jsonEncode(result)),
          ),
        );
        needsAttention = needsAttention || remoteStatus != 'accepted';
      } catch (error) {
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          LocalOutboxCommandsCompanion(
            attemptCount: Value(command.attemptCount + 1),
            nextAttemptAt: Value(
              DateTime.now().add(
                Duration(seconds: 5 * (command.attemptCount + 1)),
              ),
            ),
            lastError: Value(error.toString()),
          ),
        );
        needsAttention = true;
        break;
      }
    }

    _health.add(needsAttention ? SyncHealth.attention : SyncHealth.idle);
  }

  Future<void> pullChanges() async {
    // The compact Broadcast is only an invalidation signal. Entity pulls and
    // safe pending-command rebases are the next synchronization increment.
    _health.add(SyncHealth.idle);
  }

  Future<void> dispose() async {
    _drainTimer?.cancel();
    await _connectivitySubscription?.cancel();
    await _channel?.unsubscribe();
    await _health.close();
  }
}
