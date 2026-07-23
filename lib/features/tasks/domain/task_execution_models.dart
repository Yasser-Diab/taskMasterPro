import 'package:uuid/uuid.dart';

enum WorkDemandStatus { open, inProgress, blocked, completed, cancelled }

extension WorkDemandStatusX on WorkDemandStatus {
  String get storageValue => switch (this) {
    WorkDemandStatus.inProgress => 'in_progress',
    _ => name,
  };

  static WorkDemandStatus fromStorage(String? value) {
    return switch (value) {
      'in_progress' => WorkDemandStatus.inProgress,
      'blocked' => WorkDemandStatus.blocked,
      'completed' => WorkDemandStatus.completed,
      'cancelled' || 'canceled' => WorkDemandStatus.cancelled,
      _ => WorkDemandStatus.open,
    };
  }
}

class WorkDemand {
  WorkDemand({
    String? id,
    required this.taskId,
    required this.title,
    this.description = '',
    this.priority = 'normal',
    this.status = WorkDemandStatus.open,
    this.weight = 1,
    this.originalDueDate,
    this.currentScheduledDate,
    this.completedAt,
    this.rolloverPolicy = 'next_valid_work_occurrence',
    this.position = 0,
    this.tags = const [],
    this.attachments = const [],
    this.notes = '',
    this.overdueDismissedAt,
    this.overdueDismissalReason,
    this.deviceId,
    this.revision = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String title;
  final String description;
  final String priority;
  final WorkDemandStatus status;
  final double weight;
  final DateTime? originalDueDate;
  final DateTime? currentScheduledDate;
  final DateTime? completedAt;
  final String rolloverPolicy;
  final int position;
  final List<String> tags;
  final List<Map<String, dynamic>> attachments;
  final String notes;
  final DateTime? overdueDismissedAt;
  final String? overdueDismissalReason;
  final String? deviceId;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isCompleted => status == WorkDemandStatus.completed;

  WorkDemand copyWith({
    String? title,
    String? description,
    String? priority,
    WorkDemandStatus? status,
    double? weight,
    DateTime? originalDueDate,
    DateTime? currentScheduledDate,
    DateTime? completedAt,
    String? rolloverPolicy,
    int? position,
    List<String>? tags,
    List<Map<String, dynamic>>? attachments,
    String? notes,
    DateTime? overdueDismissedAt,
    String? overdueDismissalReason,
    String? deviceId,
    int? revision,
    DateTime? deletedAt,
    bool clearCompletedAt = false,
    bool clearOverdueDismissal = false,
  }) {
    return WorkDemand(
      id: id,
      taskId: taskId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      weight: weight ?? this.weight,
      originalDueDate: originalDueDate ?? this.originalDueDate,
      currentScheduledDate: currentScheduledDate ?? this.currentScheduledDate,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      rolloverPolicy: rolloverPolicy ?? this.rolloverPolicy,
      position: position ?? this.position,
      tags: tags ?? this.tags,
      attachments: attachments ?? this.attachments,
      notes: notes ?? this.notes,
      overdueDismissedAt: clearOverdueDismissal
          ? null
          : overdueDismissedAt ?? this.overdueDismissedAt,
      overdueDismissalReason: clearOverdueDismissal
          ? null
          : overdueDismissalReason ?? this.overdueDismissalReason,
      deviceId: deviceId ?? this.deviceId,
      revision: revision ?? this.revision,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  factory WorkDemand.fromMap(Map<String, dynamic> map) {
    return WorkDemand(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      priority: map['priority']?.toString() ?? 'normal',
      status: WorkDemandStatusX.fromStorage(map['status']?.toString()),
      weight: _double(map['weight'], fallback: 1),
      originalDueDate: _date(map['original_due_date']),
      currentScheduledDate: _date(map['current_scheduled_date']),
      completedAt: _date(map['completed_at']),
      rolloverPolicy:
          map['rollover_policy']?.toString() ?? 'next_valid_work_occurrence',
      position: _int(map['position']),
      tags: _stringList(map['tags']),
      attachments: _mapList(map['attachments']),
      notes: map['notes']?.toString() ?? '',
      overdueDismissedAt: _date(map['overdue_dismissed_at']),
      overdueDismissalReason: map['overdue_dismissal_reason']?.toString(),
      deviceId: map['device_id']?.toString(),
      revision: _int(map['revision']),
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      updatedAt: _date(map['updated_at']) ?? DateTime.now(),
      deletedAt: _date(map['deleted_at']),
    );
  }

  Map<String, dynamic> toMap({required String userId}) => {
    'id': id,
    'user_id': userId,
    'task_id': taskId,
    'title': title,
    'description': description,
    'priority': priority,
    'status': status.storageValue,
    'weight': weight,
    'original_due_date': _dateOnly(originalDueDate),
    'current_scheduled_date': _dateOnly(currentScheduledDate),
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'rollover_policy': rolloverPolicy,
    'position': position,
    'tags': tags,
    'attachments': attachments,
    'notes': notes,
    'overdue_dismissed_at': overdueDismissedAt?.toUtc().toIso8601String(),
    'overdue_dismissal_reason': overdueDismissalReason,
    'device_id': deviceId,
    'revision': revision,
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };
}

enum LearningCheckpointStatus {
  open,
  inProgress,
  completed,
  skipped,
  cancelled,
}

extension LearningCheckpointStatusX on LearningCheckpointStatus {
  String get storageValue => switch (this) {
    LearningCheckpointStatus.inProgress => 'in_progress',
    _ => name,
  };

  static LearningCheckpointStatus fromStorage(String? value) {
    return switch (value) {
      'in_progress' => LearningCheckpointStatus.inProgress,
      'completed' => LearningCheckpointStatus.completed,
      'skipped' => LearningCheckpointStatus.skipped,
      'cancelled' || 'canceled' => LearningCheckpointStatus.cancelled,
      _ => LearningCheckpointStatus.open,
    };
  }
}

class LearningCheckpoint {
  LearningCheckpoint({
    String? id,
    required this.taskId,
    this.roadmapId,
    this.roadmapPhaseId,
    required this.title,
    this.description = '',
    this.targetDate,
    this.status = LearningCheckpointStatus.open,
    this.evidence,
    this.linkedResources = const [],
    this.estimatedEffortMinutes = 0,
    this.actualFocusedSeconds = 0,
    this.notes = '',
    this.completionCriteria = '',
    this.position = 0,
    this.deviceId,
    this.completedAt,
    this.revision = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String? roadmapId;
  final String? roadmapPhaseId;
  final String title;
  final String description;
  final DateTime? targetDate;
  final LearningCheckpointStatus status;
  final String? evidence;
  final List<Map<String, dynamic>> linkedResources;
  final int estimatedEffortMinutes;
  final int actualFocusedSeconds;
  final String notes;
  final String completionCriteria;
  final int position;
  final String? deviceId;
  final DateTime? completedAt;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isCompleted => status == LearningCheckpointStatus.completed;

  factory LearningCheckpoint.fromMap(Map<String, dynamic> map) {
    return LearningCheckpoint(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      roadmapId: map['roadmap_id']?.toString(),
      roadmapPhaseId: map['roadmap_phase_id']?.toString(),
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      targetDate: _date(map['target_date']),
      status: LearningCheckpointStatusX.fromStorage(map['status']?.toString()),
      evidence: map['evidence']?.toString(),
      linkedResources: _mapList(map['linked_resources']),
      estimatedEffortMinutes: _int(map['estimated_effort_minutes']),
      actualFocusedSeconds: _int(map['actual_focused_seconds']),
      notes: map['notes']?.toString() ?? '',
      completionCriteria: map['completion_criteria']?.toString() ?? '',
      position: _int(map['position']),
      deviceId: map['device_id']?.toString(),
      completedAt: _date(map['completed_at']),
      revision: _int(map['revision']),
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      updatedAt: _date(map['updated_at']) ?? DateTime.now(),
      deletedAt: _date(map['deleted_at']),
    );
  }

  Map<String, dynamic> toMap({required String userId}) => {
    'id': id,
    'user_id': userId,
    'task_id': taskId,
    'roadmap_id': roadmapId,
    'roadmap_phase_id': roadmapPhaseId,
    'title': title,
    'description': description,
    'target_date': _dateOnly(targetDate),
    'status': status.storageValue,
    'evidence': evidence,
    'linked_resources': linkedResources,
    'estimated_effort_minutes': estimatedEffortMinutes,
    'actual_focused_seconds': actualFocusedSeconds,
    'notes': notes,
    'completion_criteria': completionCriteria,
    'position': position,
    'device_id': deviceId,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'revision': revision,
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

String? _dateOnly(DateTime? value) => value?.toIso8601String().split('T').first;

int _int(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _double(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> _stringList(Object? value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  return const [];
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
  return const [];
}
