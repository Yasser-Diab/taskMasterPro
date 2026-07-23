import 'package:uuid/uuid.dart';

enum TrackedSessionType {
  work,
  learning,
  personal,
  household,
  family,
  health,
  social,
  custom,
}

extension TrackedSessionTypeX on TrackedSessionType {
  String get storageValue => name;

  static TrackedSessionType fromStorage(String? value) {
    return switch (value) {
      'work' => TrackedSessionType.work,
      'learning' => TrackedSessionType.learning,
      'household' => TrackedSessionType.household,
      'family' => TrackedSessionType.family,
      'health' => TrackedSessionType.health,
      'social' => TrackedSessionType.social,
      'custom' => TrackedSessionType.custom,
      _ => TrackedSessionType.personal,
    };
  }
}

enum TrackedSessionStatus {
  created,
  running,
  paused,
  idle,
  interrupted,
  completed,
  stopped,
  recovered,
  corrected,
  discarded,
}

extension TrackedSessionStatusX on TrackedSessionStatus {
  String get storageValue => name;

  static TrackedSessionStatus fromStorage(String? value) {
    return switch (value) {
      'created' => TrackedSessionStatus.created,
      'running' || 'in_progress' => TrackedSessionStatus.running,
      'paused' => TrackedSessionStatus.paused,
      'idle' => TrackedSessionStatus.idle,
      'interrupted' => TrackedSessionStatus.interrupted,
      'completed' => TrackedSessionStatus.completed,
      'stopped' => TrackedSessionStatus.stopped,
      'recovered' => TrackedSessionStatus.recovered,
      'corrected' => TrackedSessionStatus.corrected,
      'discarded' => TrackedSessionStatus.discarded,
      _ => TrackedSessionStatus.created,
    };
  }
}

enum SessionTrackingMode { interactive, video, reading, manual }

extension SessionTrackingModeX on SessionTrackingMode {
  String get storageValue => name;

  static SessionTrackingMode fromStorage(String? value) {
    return switch (value) {
      'video' => SessionTrackingMode.video,
      'reading' => SessionTrackingMode.reading,
      'manual' => SessionTrackingMode.manual,
      _ => SessionTrackingMode.interactive,
    };
  }
}

enum SessionSegmentType {
  active,
  idle,
  paused,
  interruption,
  breakTime,
  manual,
  video,
  reading,
  externalResource,
}

extension SessionSegmentTypeX on SessionSegmentType {
  String get storageValue => switch (this) {
    SessionSegmentType.breakTime => 'break',
    SessionSegmentType.externalResource => 'external_resource',
    _ => name,
  };

  bool get countsAsActive => switch (this) {
    SessionSegmentType.active ||
    SessionSegmentType.video ||
    SessionSegmentType.reading ||
    SessionSegmentType.externalResource ||
    SessionSegmentType.manual => true,
    _ => false,
  };

  static SessionSegmentType fromStorage(String? value) {
    return switch (value) {
      'idle' => SessionSegmentType.idle,
      'paused' => SessionSegmentType.paused,
      'interruption' => SessionSegmentType.interruption,
      'break' => SessionSegmentType.breakTime,
      'manual' => SessionSegmentType.manual,
      'video' => SessionSegmentType.video,
      'reading' => SessionSegmentType.reading,
      'external_resource' => SessionSegmentType.externalResource,
      _ => SessionSegmentType.active,
    };
  }
}

class TrackedSession {
  TrackedSession({
    String? id,
    required this.taskId,
    this.projectId,
    this.categoryId,
    this.categoryName,
    this.deviceId,
    this.type = TrackedSessionType.personal,
    this.trackingMode = SessionTrackingMode.interactive,
    this.status = TrackedSessionStatus.created,
    DateTime? startedAt,
    this.endedAt,
    this.grossSeconds = 0,
    this.activeSeconds = 0,
    this.idleSeconds = 0,
    this.pausedSeconds = 0,
    this.interruptedSeconds = 0,
    this.breakSeconds = 0,
    this.manualSeconds = 0,
    this.pomodorosCompleted = 0,
    this.completionReason,
    this.syncStatus = 'pending',
    this.revision = 0,
    this.stage,
    this.currentSegmentId,
    this.plannedDurationSeconds,
    this.lastResumedAt,
    this.accumulatedActiveSeconds = 0,
    this.accumulatedPausedSeconds = 0,
    this.sourceDeviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       startedAt = startedAt ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String? projectId;
  final String? categoryId;
  final String? categoryName;
  final String? deviceId;
  final TrackedSessionType type;
  final SessionTrackingMode trackingMode;
  final TrackedSessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int grossSeconds;
  final int activeSeconds;
  final int idleSeconds;
  final int pausedSeconds;
  final int interruptedSeconds;
  final int breakSeconds;
  final int manualSeconds;
  final int pomodorosCompleted;
  final String? completionReason;
  final String syncStatus;
  final int revision;
  final String? stage;
  final String? currentSegmentId;
  final int? plannedDurationSeconds;
  final DateTime? lastResumedAt;
  final int accumulatedActiveSeconds;
  final int accumulatedPausedSeconds;
  final String? sourceDeviceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  TrackedSession copyWith({
    TrackedSessionType? type,
    SessionTrackingMode? trackingMode,
    TrackedSessionStatus? status,
    DateTime? endedAt,
    int? grossSeconds,
    int? activeSeconds,
    int? idleSeconds,
    int? pausedSeconds,
    int? interruptedSeconds,
    int? breakSeconds,
    int? manualSeconds,
    int? pomodorosCompleted,
    String? completionReason,
    String? syncStatus,
    int? revision,
    String? stage,
    String? currentSegmentId,
    int? plannedDurationSeconds,
    DateTime? lastResumedAt,
    int? accumulatedActiveSeconds,
    int? accumulatedPausedSeconds,
    String? sourceDeviceId,
    bool clearStage = false,
    bool clearCurrentSegmentId = false,
    bool clearPlannedDurationSeconds = false,
    bool clearLastResumedAt = false,
    bool clearSourceDeviceId = false,
  }) {
    return TrackedSession(
      id: id,
      taskId: taskId,
      projectId: projectId,
      categoryId: categoryId,
      categoryName: categoryName,
      deviceId: deviceId,
      type: type ?? this.type,
      trackingMode: trackingMode ?? this.trackingMode,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      grossSeconds: grossSeconds ?? this.grossSeconds,
      activeSeconds: activeSeconds ?? this.activeSeconds,
      idleSeconds: idleSeconds ?? this.idleSeconds,
      pausedSeconds: pausedSeconds ?? this.pausedSeconds,
      interruptedSeconds: interruptedSeconds ?? this.interruptedSeconds,
      breakSeconds: breakSeconds ?? this.breakSeconds,
      manualSeconds: manualSeconds ?? this.manualSeconds,
      pomodorosCompleted: pomodorosCompleted ?? this.pomodorosCompleted,
      completionReason: completionReason ?? this.completionReason,
      syncStatus: syncStatus ?? this.syncStatus,
      revision: revision ?? this.revision,
      stage: clearStage ? null : stage ?? this.stage,
      currentSegmentId: clearCurrentSegmentId
          ? null
          : currentSegmentId ?? this.currentSegmentId,
      plannedDurationSeconds: clearPlannedDurationSeconds
          ? null
          : plannedDurationSeconds ?? this.plannedDurationSeconds,
      lastResumedAt: clearLastResumedAt
          ? null
          : lastResumedAt ?? this.lastResumedAt,
      accumulatedActiveSeconds:
          accumulatedActiveSeconds ?? this.accumulatedActiveSeconds,
      accumulatedPausedSeconds:
          accumulatedPausedSeconds ?? this.accumulatedPausedSeconds,
      sourceDeviceId: clearSourceDeviceId
          ? null
          : sourceDeviceId ?? this.sourceDeviceId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  factory TrackedSession.fromMap(Map<String, dynamic> map) {
    return TrackedSession(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      projectId: map['project_id']?.toString(),
      categoryId: map['category_id']?.toString(),
      categoryName: map['category_name']?.toString(),
      deviceId: map['device_id']?.toString(),
      type: TrackedSessionTypeX.fromStorage(map['session_type']?.toString()),
      trackingMode: SessionTrackingModeX.fromStorage(
        map['tracking_mode']?.toString(),
      ),
      status: TrackedSessionStatusX.fromStorage(map['status']?.toString()),
      startedAt: _dateFromMap(map['started_at']) ?? DateTime.now(),
      endedAt: _dateFromMap(map['ended_at']),
      grossSeconds: _intFromMap(
        map['gross_seconds'] ?? map['gross_duration_seconds'],
      ),
      activeSeconds: _intFromMap(
        map['active_seconds'] ?? map['active_duration_seconds'],
      ),
      idleSeconds: _intFromMap(
        map['idle_seconds'] ?? map['idle_duration_seconds'],
      ),
      pausedSeconds: _intFromMap(
        map['paused_seconds'] ?? map['paused_duration_seconds'],
      ),
      interruptedSeconds: _intFromMap(map['interrupted_seconds']),
      breakSeconds: _intFromMap(map['break_seconds']),
      manualSeconds: _intFromMap(map['manual_seconds']),
      pomodorosCompleted: _intFromMap(map['pomodoros_completed']),
      completionReason: map['completion_reason']?.toString(),
      syncStatus: map['sync_status']?.toString() ?? 'synced',
      revision: _intFromMap(map['revision']),
      stage: map['stage']?.toString(),
      currentSegmentId: map['current_segment_id']?.toString(),
      plannedDurationSeconds: map['planned_duration_seconds'] == null
          ? null
          : _intFromMap(map['planned_duration_seconds']),
      lastResumedAt: _dateFromMap(map['last_resumed_at']),
      accumulatedActiveSeconds: _intFromMap(map['accumulated_active_seconds']),
      accumulatedPausedSeconds: _intFromMap(map['accumulated_paused_seconds']),
      sourceDeviceId: map['source_device_id']?.toString(),
      createdAt: _dateFromMap(map['created_at']) ?? DateTime.now(),
      updatedAt: _dateFromMap(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'task_id': taskId,
      'project_id': projectId,
      'category_id': categoryId,
      'category_name': categoryName,
      'device_id': deviceId,
      'session_type': type.storageValue,
      'tracking_mode': trackingMode.storageValue,
      'status': status.storageValue,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'gross_seconds': grossSeconds,
      'active_seconds': activeSeconds,
      'idle_seconds': idleSeconds,
      'paused_seconds': pausedSeconds,
      'interrupted_seconds': interruptedSeconds,
      'break_seconds': breakSeconds,
      'manual_seconds': manualSeconds,
      'pomodoros_completed': pomodorosCompleted,
      'completion_reason': completionReason,
      'sync_status': syncStatus,
      'revision': revision,
      'stage': stage,
      'current_segment_id': currentSegmentId,
      'planned_duration_seconds': plannedDurationSeconds,
      'last_resumed_at': lastResumedAt?.toIso8601String(),
      'accumulated_active_seconds': accumulatedActiveSeconds,
      'accumulated_paused_seconds': accumulatedPausedSeconds,
      'source_device_id': sourceDeviceId,
    };
  }
}

class TrackedSessionSegment {
  TrackedSessionSegment({
    String? id,
    required this.sessionId,
    required this.type,
    DateTime? startedAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.source = 'timer',
    this.trackingMode = SessionTrackingMode.interactive,
    this.stage,
    this.plannedDurationSeconds,
    this.accumulatedActiveSeconds = 0,
    this.accumulatedPausedSeconds = 0,
    this.completedAt,
    this.transitionReason,
    this.controllingDeviceId,
    this.lastCheckpointAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       startedAt = startedAt ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String sessionId;
  final SessionSegmentType type;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String source;
  final SessionTrackingMode trackingMode;
  final String? stage;
  final int? plannedDurationSeconds;
  final int accumulatedActiveSeconds;
  final int accumulatedPausedSeconds;
  final DateTime? completedAt;
  final String? transitionReason;
  final String? controllingDeviceId;
  final DateTime? lastCheckpointAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOpen => endedAt == null;

  TrackedSessionSegment close(DateTime end) {
    return copyWith(
      endedAt: end,
      durationSeconds: end.difference(startedAt).inSeconds.clamp(0, 1 << 31),
    );
  }

  TrackedSessionSegment copyWith({
    SessionSegmentType? type,
    DateTime? endedAt,
    int? durationSeconds,
    String? source,
    SessionTrackingMode? trackingMode,
    String? stage,
    int? plannedDurationSeconds,
    int? accumulatedActiveSeconds,
    int? accumulatedPausedSeconds,
    DateTime? completedAt,
    String? transitionReason,
    String? controllingDeviceId,
    DateTime? lastCheckpointAt,
    bool clearStage = false,
    bool clearPlannedDurationSeconds = false,
    bool clearCompletedAt = false,
    bool clearTransitionReason = false,
    bool clearControllingDeviceId = false,
    bool clearLastCheckpointAt = false,
  }) {
    return TrackedSessionSegment(
      id: id,
      sessionId: sessionId,
      type: type ?? this.type,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      source: source ?? this.source,
      trackingMode: trackingMode ?? this.trackingMode,
      stage: clearStage ? null : stage ?? this.stage,
      plannedDurationSeconds: clearPlannedDurationSeconds
          ? null
          : plannedDurationSeconds ?? this.plannedDurationSeconds,
      accumulatedActiveSeconds:
          accumulatedActiveSeconds ?? this.accumulatedActiveSeconds,
      accumulatedPausedSeconds:
          accumulatedPausedSeconds ?? this.accumulatedPausedSeconds,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      transitionReason: clearTransitionReason
          ? null
          : transitionReason ?? this.transitionReason,
      controllingDeviceId: clearControllingDeviceId
          ? null
          : controllingDeviceId ?? this.controllingDeviceId,
      lastCheckpointAt: clearLastCheckpointAt
          ? null
          : lastCheckpointAt ?? this.lastCheckpointAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  factory TrackedSessionSegment.fromMap(Map<String, dynamic> map) {
    return TrackedSessionSegment(
      id: map['id']?.toString(),
      sessionId: map['session_id']?.toString() ?? '',
      type: SessionSegmentTypeX.fromStorage(map['segment_type']?.toString()),
      startedAt: _dateFromMap(map['started_at']) ?? DateTime.now(),
      endedAt: _dateFromMap(map['ended_at']),
      durationSeconds: _intFromMap(map['duration_seconds']),
      source: map['source']?.toString() ?? 'timer',
      trackingMode: SessionTrackingModeX.fromStorage(
        map['tracking_mode']?.toString(),
      ),
      stage: map['stage']?.toString(),
      plannedDurationSeconds: map['planned_duration_seconds'] == null
          ? null
          : _intFromMap(map['planned_duration_seconds']),
      accumulatedActiveSeconds: _intFromMap(map['accumulated_active_seconds']),
      accumulatedPausedSeconds: _intFromMap(map['accumulated_paused_seconds']),
      completedAt: _dateFromMap(map['completed_at']),
      transitionReason: map['transition_reason']?.toString(),
      controllingDeviceId: map['controlling_device_id']?.toString(),
      lastCheckpointAt: _dateFromMap(map['last_checkpoint_at']),
      createdAt: _dateFromMap(map['created_at']) ?? DateTime.now(),
      updatedAt: _dateFromMap(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'segment_type': type.storageValue,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'source': source,
      'tracking_mode': trackingMode.storageValue,
      'stage': stage,
      'planned_duration_seconds': plannedDurationSeconds,
      'accumulated_active_seconds': accumulatedActiveSeconds,
      'accumulated_paused_seconds': accumulatedPausedSeconds,
      'completed_at': completedAt?.toIso8601String(),
      'transition_reason': transitionReason,
      'controlling_device_id': controllingDeviceId,
      'last_checkpoint_at': lastCheckpointAt?.toIso8601String(),
    };
  }
}

class SessionEventRecord {
  SessionEventRecord({
    String? id,
    required this.sessionId,
    required this.eventType,
    DateTime? eventTime,
    this.metadata = const {},
    this.deviceId,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       eventTime = eventTime ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String sessionId;
  final String eventType;
  final DateTime eventTime;
  final Map<String, dynamic> metadata;
  final String? deviceId;
  final DateTime createdAt;

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'event_type': eventType,
      'event_time': eventTime.toIso8601String(),
      'metadata': metadata,
      'device_id': deviceId,
    };
  }
}

class TaskProgressEntry {
  TaskProgressEntry({
    String? id,
    required this.taskId,
    this.sessionId,
    required this.progressPercentage,
    this.progressValue,
    this.progressUnit,
    this.confidence,
    this.remainingEstimateMinutes,
    this.summary = '',
    this.nextAction,
    DateTime? recordedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       recordedAt = recordedAt ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String? sessionId;
  final int progressPercentage;
  final num? progressValue;
  final String? progressUnit;
  final int? confidence;
  final int? remainingEstimateMinutes;
  final String summary;
  final String? nextAction;
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TaskProgressEntry.fromMap(Map<String, dynamic> map) {
    return TaskProgressEntry(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      sessionId: map['session_id']?.toString(),
      progressPercentage: _intFromMap(map['progress_percentage']),
      progressValue: map['progress_value'] is num
          ? map['progress_value'] as num
          : num.tryParse(map['progress_value']?.toString() ?? ''),
      progressUnit: map['progress_unit']?.toString(),
      confidence: _nullableIntFromMap(map['confidence']),
      remainingEstimateMinutes: _nullableIntFromMap(
        map['remaining_estimate_minutes'],
      ),
      summary: map['summary']?.toString() ?? '',
      nextAction: map['next_action']?.toString(),
      recordedAt: _dateFromMap(map['recorded_at']) ?? DateTime.now(),
      createdAt: _dateFromMap(map['created_at']) ?? DateTime.now(),
      updatedAt: _dateFromMap(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'id': id,
      'task_id': taskId,
      'session_id': sessionId,
      'progress_percentage': progressPercentage,
      'progress_value': progressValue,
      'progress_unit': progressUnit,
      'confidence': confidence,
      'remaining_estimate_minutes': remainingEstimateMinutes,
      'summary': summary,
      'next_action': nextAction,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}

class SessionWithSegments {
  const SessionWithSegments({required this.session, required this.segments});

  final TrackedSession session;
  final List<TrackedSessionSegment> segments;
}

DateTime? _dateFromMap(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

int _intFromMap(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableIntFromMap(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value.toString());
}
