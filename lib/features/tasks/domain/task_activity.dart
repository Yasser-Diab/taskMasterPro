import 'package:uuid/uuid.dart';

enum TaskNoteType {
  general,
  progress,
  problem,
  idea,
  decision,
  nextAction,
  learningSummary,
  workResult,
}

extension TaskNoteTypeX on TaskNoteType {
  String get storageValue => switch (this) {
    TaskNoteType.nextAction => 'next_action',
    TaskNoteType.learningSummary => 'learning_summary',
    TaskNoteType.workResult => 'work_result',
    _ => name,
  };

  static TaskNoteType fromStorage(String? value) {
    return switch (value) {
      'progress' => TaskNoteType.progress,
      'problem' => TaskNoteType.problem,
      'idea' => TaskNoteType.idea,
      'decision' => TaskNoteType.decision,
      'next_action' => TaskNoteType.nextAction,
      'learning_summary' => TaskNoteType.learningSummary,
      'work_result' => TaskNoteType.workResult,
      _ => TaskNoteType.general,
    };
  }
}

enum TaskInterruptionType {
  phoneCall,
  workRequest,
  meeting,
  familyNeed,
  visitor,
  technicalIssue,
  internetProblem,
  distraction,
  breakTaken,
  personalNeed,
  changedPriority,
  other,
}

extension TaskInterruptionTypeX on TaskInterruptionType {
  String get storageValue => switch (this) {
    TaskInterruptionType.phoneCall => 'phone_call',
    TaskInterruptionType.workRequest => 'work_request',
    TaskInterruptionType.familyNeed => 'family_need',
    TaskInterruptionType.technicalIssue => 'technical_issue',
    TaskInterruptionType.internetProblem => 'internet_problem',
    TaskInterruptionType.breakTaken => 'break',
    TaskInterruptionType.personalNeed => 'personal_need',
    TaskInterruptionType.changedPriority => 'changed_priority',
    _ => name,
  };

  String get label => switch (this) {
    TaskInterruptionType.phoneCall => 'Phone call',
    TaskInterruptionType.workRequest => 'Work request',
    TaskInterruptionType.meeting => 'Meeting',
    TaskInterruptionType.familyNeed => 'Family need',
    TaskInterruptionType.visitor => 'Visitor',
    TaskInterruptionType.technicalIssue => 'Technical issue',
    TaskInterruptionType.internetProblem => 'Internet problem',
    TaskInterruptionType.distraction => 'Distraction',
    TaskInterruptionType.breakTaken => 'Break',
    TaskInterruptionType.personalNeed => 'Personal need',
    TaskInterruptionType.changedPriority => 'Changed priority',
    TaskInterruptionType.other => 'Other',
  };

  static TaskInterruptionType fromStorage(String? value) {
    return switch (value) {
      'phone_call' => TaskInterruptionType.phoneCall,
      'work_request' => TaskInterruptionType.workRequest,
      'meeting' => TaskInterruptionType.meeting,
      'family_need' => TaskInterruptionType.familyNeed,
      'visitor' => TaskInterruptionType.visitor,
      'technical_issue' => TaskInterruptionType.technicalIssue,
      'internet_problem' => TaskInterruptionType.internetProblem,
      'distraction' => TaskInterruptionType.distraction,
      'break' => TaskInterruptionType.breakTaken,
      'personal_need' => TaskInterruptionType.personalNeed,
      'changed_priority' => TaskInterruptionType.changedPriority,
      _ => TaskInterruptionType.other,
    };
  }
}

class TaskNote {
  TaskNote({
    String? id,
    required this.taskId,
    this.sessionId,
    this.type = TaskNoteType.general,
    this.title = '',
    required this.body,
    this.isPinned = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String? sessionId;
  final TaskNoteType type;
  final String title;
  final String body;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskNote copyWith({
    TaskNoteType? type,
    String? title,
    String? body,
    bool? isPinned,
  }) {
    return TaskNote(
      id: id,
      taskId: taskId,
      sessionId: sessionId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  factory TaskNote.fromMap(Map<String, dynamic> map) {
    return TaskNote(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      sessionId: map['session_id']?.toString(),
      type: TaskNoteTypeX.fromStorage(map['note_type']?.toString()),
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      isPinned: map['is_pinned'] as bool? ?? false,
      createdAt: _dateFromMap(map['created_at']) ?? DateTime.now(),
      updatedAt: _dateFromMap(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'task_id': taskId,
      'session_id': sessionId,
      'note_type': type.storageValue,
      'title': title,
      'body': body,
      'is_pinned': isPinned,
    };
  }
}

class TaskInterruption {
  TaskInterruption({
    String? id,
    required this.taskId,
    this.sessionId,
    required this.type,
    DateTime? startedAt,
    this.endedAt,
    int? durationSeconds,
    this.pausedTask = true,
    this.isWorkRelated = false,
    this.description = '',
    this.isResolved = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       startedAt = startedAt ?? DateTime.now(),
       durationSeconds =
           durationSeconds ??
           (endedAt == null
               ? 0
               : endedAt.difference(startedAt ?? DateTime.now()).inSeconds),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String? sessionId;
  final TaskInterruptionType type;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final bool pausedTask;
  final bool isWorkRelated;
  final String description;
  final bool isResolved;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskInterruption copyWith({
    TaskInterruptionType? type,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    bool? pausedTask,
    bool? isWorkRelated,
    String? description,
    bool? isResolved,
  }) {
    return TaskInterruption(
      id: id,
      taskId: taskId,
      sessionId: sessionId,
      type: type ?? this.type,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      pausedTask: pausedTask ?? this.pausedTask,
      isWorkRelated: isWorkRelated ?? this.isWorkRelated,
      description: description ?? this.description,
      isResolved: isResolved ?? this.isResolved,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  factory TaskInterruption.fromMap(Map<String, dynamic> map) {
    return TaskInterruption(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      sessionId: map['session_id']?.toString(),
      type: TaskInterruptionTypeX.fromStorage(
        map['interruption_type']?.toString() ??
            map['interruption_type_id']?.toString(),
      ),
      startedAt: _dateFromMap(map['started_at']) ?? DateTime.now(),
      endedAt: _dateFromMap(map['ended_at']),
      durationSeconds: _intFromMap(map['duration_seconds']),
      pausedTask: map['paused_task'] as bool? ?? true,
      isWorkRelated: map['is_work_related'] as bool? ?? false,
      description: map['description']?.toString() ?? '',
      isResolved: map['is_resolved'] as bool? ?? false,
      createdAt: _dateFromMap(map['created_at']) ?? DateTime.now(),
      updatedAt: _dateFromMap(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'task_id': taskId,
      'session_id': sessionId,
      'interruption_type': type.storageValue,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration_seconds': durationSeconds,
      'paused_task': pausedTask,
      'is_work_related': isWorkRelated,
      'description': description,
      'is_resolved': isResolved,
    };
  }
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
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
