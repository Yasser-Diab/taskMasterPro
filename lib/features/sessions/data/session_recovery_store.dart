import 'dart:convert';
import 'dart:io';

import '../domain/session_models.dart';

class SessionRecoveryCheckpoint {
  const SessionRecoveryCheckpoint({
    required this.userId,
    required this.taskId,
    required this.sessionId,
    required this.timerState,
    required this.lastStateChange,
    required this.trackingMode,
    this.segmentType,
    this.segmentStartedAt,
    this.plannedSeconds,
    this.controllingDeviceId,
    this.lastCheckpointAt,
    this.openInterruptionId,
    this.unsavedNoteDraft,
  });

  final String userId;
  final String taskId;
  final String sessionId;
  final String timerState;
  final DateTime lastStateChange;
  final SessionTrackingMode trackingMode;
  final SessionSegmentType? segmentType;
  final DateTime? segmentStartedAt;
  final int? plannedSeconds;
  final String? controllingDeviceId;
  final DateTime? lastCheckpointAt;
  final String? openInterruptionId;
  final String? unsavedNoteDraft;

  factory SessionRecoveryCheckpoint.fromMap(Map<String, dynamic> map) {
    return SessionRecoveryCheckpoint(
      userId: map['user_id']?.toString() ?? '',
      taskId: map['task_id']?.toString() ?? '',
      sessionId: map['session_id']?.toString() ?? '',
      timerState: map['timer_state']?.toString() ?? 'running',
      lastStateChange:
          DateTime.tryParse(map['last_state_change']?.toString() ?? '') ??
          DateTime.now(),
      trackingMode: SessionTrackingModeX.fromStorage(
        map['tracking_mode']?.toString(),
      ),
      segmentType: map['segment_type'] == null
          ? null
          : SessionSegmentTypeX.fromStorage(map['segment_type']?.toString()),
      segmentStartedAt: DateTime.tryParse(
        map['segment_started_at']?.toString() ?? '',
      ),
      plannedSeconds: _intFromMap(map['planned_seconds']),
      controllingDeviceId: map['controlling_device_id']?.toString(),
      lastCheckpointAt: DateTime.tryParse(
        map['last_checkpoint_at']?.toString() ?? '',
      ),
      openInterruptionId: map['open_interruption_id']?.toString(),
      unsavedNoteDraft: map['unsaved_note_draft']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'task_id': taskId,
      'session_id': sessionId,
      'timer_state': timerState,
      'last_state_change': lastStateChange.toIso8601String(),
      'tracking_mode': trackingMode.storageValue,
      'segment_type': segmentType?.storageValue,
      'segment_started_at': segmentStartedAt?.toIso8601String(),
      'planned_seconds': plannedSeconds,
      'controlling_device_id': controllingDeviceId,
      'last_checkpoint_at': lastCheckpointAt?.toIso8601String(),
      'open_interruption_id': openInterruptionId,
      'unsaved_note_draft': unsavedNoteDraft,
    };
  }
}

int? _intFromMap(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

class SessionRecoveryStore {
  SessionRecoveryStore({File? file}) : _file = file;

  final File? _file;

  Future<SessionRecoveryCheckpoint?> load(String userId) async {
    final file = _resolveFile(userId);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return SessionRecoveryCheckpoint.fromMap(decoded);
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<void> save(SessionRecoveryCheckpoint checkpoint) async {
    final file = _resolveFile(checkpoint.userId);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(checkpoint.toMap()),
    );
  }

  Future<void> clear(String userId) async {
    final file = _resolveFile(userId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  File _resolveFile(String userId) {
    final explicit = _file;
    if (explicit != null) {
      return explicit;
    }
    final basePath = Platform.isWindows
        ? Platform.environment['APPDATA']
        : Platform.environment['HOME'];
    final base = basePath != null && basePath.trim().isNotEmpty
        ? Directory(basePath)
        : Directory.systemTemp;
    return File(
      '${base.path}${Platform.pathSeparator}TaskMasterPro'
      '${Platform.pathSeparator}users'
      '${Platform.pathSeparator}$userId'
      '${Platform.pathSeparator}active-session.json',
    );
  }
}
