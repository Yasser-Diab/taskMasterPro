import 'package:uuid/uuid.dart';

class TaskProjectOption {
  const TaskProjectOption({required this.id, required this.name});

  final String id;
  final String name;
}

class TaskRoadmapOption {
  const TaskRoadmapOption({required this.id, required this.title});

  final String id;
  final String title;
}

class TaskRoadmapPhaseOption {
  const TaskRoadmapPhaseOption({
    required this.id,
    required this.roadmapId,
    required this.title,
    required this.phaseOrder,
  });

  final String id;
  final String roadmapId;
  final String title;
  final int phaseOrder;
}

class TaskMilestoneOption {
  const TaskMilestoneOption({
    required this.id,
    required this.roadmapId,
    required this.phaseId,
    required this.title,
  });

  final String id;
  final String roadmapId;
  final String? phaseId;
  final String title;
}

class TaskEditorLinks {
  const TaskEditorLinks({
    this.projects = const [],
    this.roadmaps = const [],
    this.phases = const [],
    this.milestones = const [],
  });

  final List<TaskProjectOption> projects;
  final List<TaskRoadmapOption> roadmaps;
  final List<TaskRoadmapPhaseOption> phases;
  final List<TaskMilestoneOption> milestones;
}

enum TaskResourceType {
  course,
  documentation,
  article,
  video,
  repository,
  exercise,
  application,
  deployment,
  book,
  reference,
  meeting,
  custom,
}

enum TaskResourceOpenMode { inApp, external, ask }

extension TaskResourceOpenModeX on TaskResourceOpenMode {
  String get storageValue => switch (this) {
    TaskResourceOpenMode.inApp => 'in_app',
    TaskResourceOpenMode.external => 'external',
    TaskResourceOpenMode.ask => 'ask',
  };

  static TaskResourceOpenMode fromStorage(String? value) {
    return switch (value) {
      'external' => TaskResourceOpenMode.external,
      'ask' => TaskResourceOpenMode.ask,
      _ => TaskResourceOpenMode.inApp,
    };
  }
}

class TaskResource {
  TaskResource({
    String? id,
    required this.taskId,
    required this.name,
    required this.url,
    this.type = TaskResourceType.custom,
    this.openMode = TaskResourceOpenMode.inApp,
    this.description = '',
    this.sortOrder = 0,
    this.isDefault = false,
    this.isRequired = false,
    this.isFavorite = false,
    this.openAutomatically = false,
    this.seriesResourceId,
    this.isOccurrenceOverride = false,
    this.isHidden = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String name;
  final String url;
  final TaskResourceType type;
  final TaskResourceOpenMode openMode;
  final String description;
  final int sortOrder;
  final bool isDefault;
  final bool isRequired;
  final bool isFavorite;
  final bool openAutomatically;
  final String? seriesResourceId;
  final bool isOccurrenceOverride;
  final bool isHidden;
  final DateTime createdAt;
  final DateTime updatedAt;

  Uri? get uri => Uri.tryParse(url);
  String get domain => uri?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '';

  TaskResource copyWith({
    String? name,
    String? url,
    TaskResourceType? type,
    TaskResourceOpenMode? openMode,
    String? description,
    int? sortOrder,
    bool? isDefault,
    bool? isRequired,
    bool? isFavorite,
    bool? openAutomatically,
    bool? isHidden,
  }) {
    return TaskResource(
      id: id,
      taskId: taskId,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      openMode: openMode ?? this.openMode,
      description: description ?? this.description,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      isRequired: isRequired ?? this.isRequired,
      isFavorite: isFavorite ?? this.isFavorite,
      openAutomatically: openAutomatically ?? this.openAutomatically,
      seriesResourceId: seriesResourceId,
      isOccurrenceOverride: isOccurrenceOverride,
      isHidden: isHidden ?? this.isHidden,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  factory TaskResource.fromMap(Map<String, dynamic> map) {
    return TaskResource(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      name: map['name']?.toString() ?? map['title']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      type: TaskResourceType.values.firstWhere(
        (type) => type.name == map['resource_type']?.toString(),
        orElse: () => TaskResourceType.custom,
      ),
      openMode: TaskResourceOpenModeX.fromStorage(map['open_mode']?.toString()),
      description: map['description']?.toString() ?? '',
      sortOrder: _int(map['sort_order']),
      isDefault: _bool(map['is_default'] ?? map['is_starting_page']),
      isRequired: _bool(map['is_required']),
      isFavorite: _bool(map['is_favorite']),
      openAutomatically: _bool(map['open_automatically']),
      seriesResourceId: map['series_resource_id']?.toString(),
      isOccurrenceOverride: _bool(map['is_occurrence_override']),
      isHidden: _bool(map['is_hidden']),
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      updatedAt: _date(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap({String? userId}) {
    return {
      'id': id,
      'user_id': ?userId,
      'task_id': taskId,
      'name': name,
      'title': name,
      'url': url,
      'normalized_domain': domain,
      'resource_type': type.name,
      'open_mode': openMode.storageValue,
      'description': description,
      'sort_order': sortOrder,
      'is_default': isDefault,
      'is_starting_page': isDefault,
      'is_required': isRequired,
      'is_favorite': isFavorite,
      'open_automatically': openAutomatically,
      'series_resource_id': seriesResourceId,
      'is_occurrence_override': isOccurrenceOverride,
      'is_hidden': isHidden,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}

enum TaskReminderStatus {
  pending,
  scheduled,
  sent,
  dismissed,
  snoozed,
  cancelled,
}

class TaskReminder {
  TaskReminder({
    String? id,
    required this.taskId,
    this.occurrenceId,
    this.offsetMinutes,
    this.customTriggerAt,
    this.isAdaptive = false,
    this.reason,
    this.notificationId,
    this.status = TaskReminderStatus.pending,
    this.scheduledAt,
    this.sentAt,
    this.dismissedAt,
    this.snoozedUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String? occurrenceId;
  final int? offsetMinutes;
  final DateTime? customTriggerAt;
  final bool isAdaptive;
  final String? reason;
  final String? notificationId;
  final TaskReminderStatus status;
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final DateTime? dismissedAt;
  final DateTime? snoozedUntil;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TaskReminder.fromMap(Map<String, dynamic> map) {
    return TaskReminder(
      id: map['id']?.toString(),
      taskId: map['task_id']?.toString() ?? '',
      occurrenceId: map['occurrence_id']?.toString(),
      offsetMinutes: map['offset_minutes'] == null
          ? null
          : _int(map['offset_minutes']),
      customTriggerAt: _date(map['custom_trigger_at']),
      isAdaptive: _bool(map['is_adaptive']),
      reason: map['reason']?.toString(),
      notificationId: map['notification_id']?.toString(),
      status: TaskReminderStatus.values.firstWhere(
        (status) => status.name == map['status']?.toString(),
        orElse: () => TaskReminderStatus.pending,
      ),
      scheduledAt: _date(map['scheduled_at']),
      sentAt: _date(map['sent_at']),
      dismissedAt: _date(map['dismissed_at']),
      snoozedUntil: _date(map['snoozed_until']),
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      updatedAt: _date(map['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap({String? userId}) {
    return {
      'id': id,
      'user_id': ?userId,
      'task_id': taskId,
      'occurrence_id': occurrenceId,
      'offset_minutes': offsetMinutes,
      'custom_trigger_at': customTriggerAt?.toUtc().toIso8601String(),
      'is_adaptive': isAdaptive,
      'reason': reason,
      'notification_id': notificationId,
      'status': status.name,
      'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      'sent_at': sentAt?.toUtc().toIso8601String(),
      'dismissed_at': dismissedAt?.toUtc().toIso8601String(),
      'snoozed_until': snoozedUntil?.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}

enum RecurrenceEditScope { occurrence, future, series }

extension RecurrenceEditScopeX on RecurrenceEditScope {
  String get storageValue => name;
}

enum TaskActivityType { website, application }

class TaskUsageActivity {
  TaskUsageActivity({
    String? id,
    required this.taskId,
    this.sessionId,
    required this.type,
    this.applicationName,
    this.windowTitle,
    this.domain,
    this.url,
    this.pageTitle,
    this.sourceTaskId,
    this.relatedTaskId,
    this.relatedRoadmapId,
    this.relatedPhaseId,
    this.normalizedDomain,
    this.registrableDomain,
    required this.startedAt,
    this.endedAt,
    this.activeSeconds = 0,
    this.idleSeconds = 0,
    this.creditedSeconds = 0,
    this.visitCount = 1,
    this.isSavedResource = false,
    this.excludedFromReports = false,
    this.attributionMethod,
    this.userConfirmed = false,
    this.isCrossTaskContribution = false,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String taskId;
  final String? sessionId;
  final TaskActivityType type;
  final String? applicationName;
  final String? windowTitle;
  final String? domain;
  final String? url;
  final String? pageTitle;
  final String? sourceTaskId;
  final String? relatedTaskId;
  final String? relatedRoadmapId;
  final String? relatedPhaseId;
  final String? normalizedDomain;
  final String? registrableDomain;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int activeSeconds;
  final int idleSeconds;
  final int creditedSeconds;
  final int visitCount;
  final bool isSavedResource;
  final bool excludedFromReports;
  final String? attributionMethod;
  final bool userConfirmed;
  final bool isCrossTaskContribution;

  int get reportSeconds =>
      isCrossTaskContribution ? creditedSeconds : activeSeconds;

  factory TaskUsageActivity.fromMap(Map<String, dynamic> map) {
    return TaskUsageActivity(
      id: map['id']?.toString() ?? '',
      taskId: map['task_id']?.toString() ?? '',
      sessionId: map['session_id']?.toString(),
      type: map['activity_type']?.toString() == 'application'
          ? TaskActivityType.application
          : TaskActivityType.website,
      applicationName: map['application_name']?.toString(),
      windowTitle: map['window_title']?.toString(),
      domain: map['domain']?.toString(),
      url: map['url']?.toString(),
      pageTitle: map['page_title']?.toString(),
      sourceTaskId: map['source_task_id']?.toString(),
      relatedTaskId: map['related_task_id']?.toString(),
      relatedRoadmapId: map['related_roadmap_id']?.toString(),
      relatedPhaseId: map['related_phase_id']?.toString(),
      normalizedDomain: map['normalized_domain']?.toString(),
      registrableDomain: map['registrable_domain']?.toString(),
      startedAt: _date(map['started_at']) ?? DateTime.now(),
      endedAt: _date(map['ended_at']),
      activeSeconds: _int(map['active_seconds']),
      idleSeconds: _int(map['idle_seconds']),
      creditedSeconds: _int(map['credited_seconds']),
      visitCount: _int(map['visit_count'], fallback: 1),
      isSavedResource: _bool(map['is_saved_resource']),
      excludedFromReports: _bool(map['excluded_from_reports']),
      attributionMethod: map['attribution_method']?.toString(),
      userConfirmed: _bool(map['user_confirmed']),
      isCrossTaskContribution: _bool(map['is_cross_task_contribution']),
    );
  }

  Map<String, dynamic> toMap({required String userId}) {
    return {
      'id': id,
      'user_id': userId,
      'task_id': taskId,
      'session_id': sessionId,
      'activity_type': type.name,
      'application_name': applicationName,
      'window_title': windowTitle,
      'domain': domain,
      'url': url,
      'page_title': pageTitle,
      'source_task_id': sourceTaskId,
      'related_task_id': relatedTaskId,
      'related_roadmap_id': relatedRoadmapId,
      'related_phase_id': relatedPhaseId,
      'normalized_domain': normalizedDomain,
      'registrable_domain': registrableDomain,
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'active_seconds': activeSeconds,
      'idle_seconds': idleSeconds,
      'credited_seconds': creditedSeconds,
      'visit_count': visitCount,
      'is_saved_resource': isSavedResource,
      'excluded_from_reports': excludedFromReports,
      'attribution_method': attributionMethod,
      'user_confirmed': userConfirmed,
      'is_cross_task_contribution': isCrossTaskContribution,
    };
  }
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

int _int(Object? value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  return value?.toString().toLowerCase() == 'true';
}
