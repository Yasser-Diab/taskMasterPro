import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/time/time_zone_service.dart';
import 'task_workspace_config.dart';

enum TaskPriority { critical, high, normal, low }

enum TaskType { focus, timed, event, habit, reading, manual }

extension TaskTypeX on TaskType {
  String get storageValue => name;

  static TaskType fromStorage(String? value) {
    return switch (value) {
      'timed' => TaskType.timed,
      'event' => TaskType.event,
      'habit' => TaskType.habit,
      'reading' => TaskType.reading,
      'manual' || 'completion_only' => TaskType.manual,
      _ => TaskType.focus,
    };
  }
}

enum TaskDomain {
  work,
  learning,
  reading,
  selfImprovement,
  household,
  sport,
  event,
  personal,
  custom,
}

extension TaskDomainX on TaskDomain {
  String get storageValue => switch (this) {
    TaskDomain.selfImprovement => 'self_improvement',
    _ => name,
  };

  static TaskDomain fromStorage(String? value, {TaskDomain? fallback}) {
    return switch (value) {
      'work' => TaskDomain.work,
      'learning' => TaskDomain.learning,
      'reading' => TaskDomain.reading,
      'self_improvement' => TaskDomain.selfImprovement,
      'household' || 'householding' => TaskDomain.household,
      'sport' => TaskDomain.sport,
      'event' => TaskDomain.event,
      'custom' => TaskDomain.custom,
      'personal' => TaskDomain.personal,
      _ => fallback ?? TaskDomain.personal,
    };
  }

  static TaskDomain infer({
    required TaskType taskType,
    required String category,
  }) {
    final normalized = category.trim().toLowerCase();
    if (taskType == TaskType.reading) return TaskDomain.reading;
    if (taskType == TaskType.event) return TaskDomain.event;
    if ({'work', 'main job', 'job'}.contains(normalized)) {
      return TaskDomain.work;
    }
    if ({'learning', 'study', 'education'}.contains(normalized)) {
      return TaskDomain.learning;
    }
    if ({'household', 'householding', 'home'}.contains(normalized)) {
      return TaskDomain.household;
    }
    if ({'sport', 'fitness', 'exercise', 'health'}.contains(normalized)) {
      return TaskDomain.sport;
    }
    return TaskDomain.personal;
  }
}

enum TaskExecutionMode {
  pomodoroFocus,
  continuousTimer,
  checklist,
  readingSession,
  habit,
  event,
  manualCompletion,
  hybrid,
}

extension TaskExecutionModeX on TaskExecutionMode {
  String get storageValue => switch (this) {
    TaskExecutionMode.pomodoroFocus => 'pomodoro_focus',
    TaskExecutionMode.continuousTimer => 'continuous_timer',
    TaskExecutionMode.readingSession => 'reading_session',
    TaskExecutionMode.manualCompletion => 'manual_completion',
    _ => name,
  };

  static TaskExecutionMode fromStorage(
    String? value, {
    TaskExecutionMode? fallback,
  }) {
    return switch (value) {
      'continuous_timer' => TaskExecutionMode.continuousTimer,
      'checklist' => TaskExecutionMode.checklist,
      'reading_session' => TaskExecutionMode.readingSession,
      'habit' => TaskExecutionMode.habit,
      'event' => TaskExecutionMode.event,
      'manual_completion' => TaskExecutionMode.manualCompletion,
      'hybrid' => TaskExecutionMode.hybrid,
      'pomodoro_focus' => TaskExecutionMode.pomodoroFocus,
      _ => fallback ?? TaskExecutionMode.pomodoroFocus,
    };
  }

  static TaskExecutionMode infer(TaskType taskType) {
    return switch (taskType) {
      TaskType.timed => TaskExecutionMode.continuousTimer,
      TaskType.event => TaskExecutionMode.event,
      TaskType.habit => TaskExecutionMode.habit,
      TaskType.reading => TaskExecutionMode.readingSession,
      TaskType.manual => TaskExecutionMode.manualCompletion,
      TaskType.focus => TaskExecutionMode.pomodoroFocus,
    };
  }
}

enum TaskEventState {
  upcoming,
  arrived,
  inProgress,
  completed,
  missed,
  cancelled,
}

extension TaskEventStateX on TaskEventState {
  String get storageValue => switch (this) {
    TaskEventState.inProgress => 'in_progress',
    _ => name,
  };

  static TaskEventState fromStorage(String? value) {
    return switch (value) {
      'arrived' => TaskEventState.arrived,
      'in_progress' => TaskEventState.inProgress,
      'completed' => TaskEventState.completed,
      'missed' => TaskEventState.missed,
      'cancelled' || 'canceled' => TaskEventState.cancelled,
      _ => TaskEventState.upcoming,
    };
  }
}

extension TaskPriorityX on TaskPriority {
  String get storageValue => name;

  int get rank => switch (this) {
    TaskPriority.critical => 0,
    TaskPriority.high => 1,
    TaskPriority.normal => 2,
    TaskPriority.low => 3,
  };

  static TaskPriority fromStorage(String? value) {
    return switch (value) {
      'critical' => TaskPriority.critical,
      'high' => TaskPriority.high,
      'low' => TaskPriority.low,
      _ => TaskPriority.normal,
    };
  }
}

enum TaskStatus {
  notStarted,
  ready,
  running,
  paused,
  interrupted,
  completed,
  cancelled,
  waiting,
  overdue,
  reviewRequired,
  someday,
}

extension TaskStatusX on TaskStatus {
  String get storageValue => switch (this) {
    TaskStatus.notStarted => 'not_started',
    TaskStatus.reviewRequired => 'review_required',
    TaskStatus.cancelled => 'cancelled',
    _ => name,
  };

  static TaskStatus fromStorage(String? value) {
    return switch (value) {
      'planned' || 'not_started' => TaskStatus.notStarted,
      'ready' => TaskStatus.ready,
      'in_progress' || 'running' => TaskStatus.running,
      'paused' => TaskStatus.paused,
      'interrupted' => TaskStatus.interrupted,
      'waiting' => TaskStatus.waiting,
      'someday' => TaskStatus.someday,
      'review_required' => TaskStatus.reviewRequired,
      'overdue' => TaskStatus.overdue,
      'completed' => TaskStatus.completed,
      'canceled' || 'cancelled' => TaskStatus.cancelled,
      _ => TaskStatus.notStarted,
    };
  }
}

class TaskChecklistItem {
  const TaskChecklistItem({required this.title, this.done = false});

  final String title;
  final bool done;

  Map<String, dynamic> toJson() {
    return {'title': title, 'done': done};
  }
}

class TaskItem {
  TaskItem({
    String? id,
    required this.title,
    this.description = '',
    this.taskType = TaskType.focus,
    TaskDomain? taskDomain,
    TaskExecutionMode? executionMode,
    this.eventState = TaskEventState.upcoming,
    this.categoryId,
    this.category = 'Personal',
    this.projectId,
    this.project,
    this.roadmapId,
    this.roadmapPhaseId,
    this.roadmapPhase,
    this.milestoneId,
    this.priority = TaskPriority.normal,
    this.status = TaskStatus.notStarted,
    this.startDate,
    this.dueDate,
    this.plannedDate,
    this.plannedStartAt,
    this.plannedEndAt,
    this.dueAt,
    this.actualStartAt,
    this.actualFinishAt,
    this.arrivalAt,
    this.estimatedPomodoros = 1,
    this.estimatedMinutes = 25,
    this.actualFocusedMinutes = 0,
    this.recurrence,
    this.recurrenceRule,
    this.recurrenceTimezone = '',
    this.recurrenceEndAt,
    this.recurrenceEndType = 'never',
    this.recurrenceMaximumOccurrences,
    this.recurrencePausedAt,
    this.learningResourceLink,
    this.launchMethod,
    this.notes = '',
    this.checklist = const [],
    this.tags = const [],
    this.progressPercentage = 0,
    this.difficulty = 2,
    this.energyRequirement = 2,
    this.context,
    this.attachments = const [],
    this.completionEvidence,
    this.parentTaskId,
    this.dependencies = const [],
    this.reminderRules = const {},
    this.adaptiveRemindersEnabled = false,
    this.defaultResourceId,
    this.location,
    this.calendarIntegration = false,
    this.completionRules = const {},
    this.timerEnabled = true,
    this.habitCurrentStreak = 0,
    this.habitLongestStreak = 0,
    this.workspaceEnabled = false,
    this.workspaceType = TaskWorkspaceType.none,
    this.workspaceStartingUrl,
    this.workspaceHomeUrl,
    this.workspaceResourceTitle,
    this.workspaceBrowserMode = TaskTrackingMode.interactive,
    this.workspaceAllowedDomains = const [],
    this.workspaceRestoreLastPage = true,
    this.workspaceOpenAutomatically = false,
    this.workspacePreferredLayout = TaskWorkspaceLayout.sideBySide,
    this.workspacePreferredDockState = TaskWorkspaceDockState.docked,
    this.workspaceAllowExternalNavigation = true,
    this.workspaceOpenUnsupportedExternally = true,
    this.workspaceNavigationMode = TaskWorkspaceNavigationMode.normalBrowsing,
    this.workspaceRestoreBrowserSession = true,
    this.workspaceRestoreOpenTabs = true,
    this.workspaceOpenStartingPageInNewTab = false,
    this.workspaceLastUrl,
    this.workspaceOpenTabs = const [],
    this.workspaceSelectedTabIndex = 0,
    this.recurrenceId,
    this.seriesTaskId,
    this.occurrenceOriginalStart,
    this.scheduledStartAt,
    this.scheduledEndAt,
    this.scheduledLocalDate,
    this.scheduledLocalTime,
    this.timeZoneId = '',
    this.timeZoneBehavior = 'keep_local_clock',
    this.allDayEndMinutes = 1439,
    this.isRecurringTemplate = false,
    this.isRecurrenceException = false,
    this.skippedAt,
    this.templateKey,
    this.templateVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.archivedAt,
    this.deletedAt,
  }) : id = id ?? const Uuid().v4(),
       taskDomain =
           taskDomain ??
           TaskDomainX.infer(taskType: taskType, category: category),
       executionMode = executionMode ?? TaskExecutionModeX.infer(taskType),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String title;
  final String description;
  final TaskType taskType;
  final TaskDomain taskDomain;
  final TaskExecutionMode executionMode;
  final TaskEventState eventState;
  final String? categoryId;
  final String category;
  final String? projectId;
  final String? project;
  final String? roadmapId;
  final String? roadmapPhaseId;
  final int? roadmapPhase;
  final String? milestoneId;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? plannedDate;
  final DateTime? plannedStartAt;
  final DateTime? plannedEndAt;
  final DateTime? dueAt;
  final DateTime? actualStartAt;
  final DateTime? actualFinishAt;
  final DateTime? arrivalAt;
  final int estimatedPomodoros;
  final int estimatedMinutes;
  final int actualFocusedMinutes;
  final String? recurrence;
  final String? recurrenceRule;
  final String recurrenceTimezone;
  final DateTime? recurrenceEndAt;
  final String recurrenceEndType;
  final int? recurrenceMaximumOccurrences;
  final DateTime? recurrencePausedAt;
  final String? learningResourceLink;
  final String? launchMethod;
  final String notes;
  final List<TaskChecklistItem> checklist;
  final List<String> tags;
  final int progressPercentage;
  final int difficulty;
  final int energyRequirement;
  final String? context;
  final List<String> attachments;
  final String? completionEvidence;
  final String? parentTaskId;
  final List<String> dependencies;
  final Map<String, dynamic> reminderRules;
  final bool adaptiveRemindersEnabled;
  final String? defaultResourceId;
  final String? location;
  final bool calendarIntegration;
  final Map<String, dynamic> completionRules;
  final bool timerEnabled;
  final int habitCurrentStreak;
  final int habitLongestStreak;
  final bool workspaceEnabled;
  final TaskWorkspaceType workspaceType;
  final String? workspaceStartingUrl;
  final String? workspaceHomeUrl;
  final String? workspaceResourceTitle;
  final TaskTrackingMode workspaceBrowserMode;
  final List<String> workspaceAllowedDomains;
  final bool workspaceRestoreLastPage;
  final bool workspaceOpenAutomatically;
  final TaskWorkspaceLayout workspacePreferredLayout;
  final TaskWorkspaceDockState workspacePreferredDockState;
  final bool workspaceAllowExternalNavigation;
  final bool workspaceOpenUnsupportedExternally;
  final TaskWorkspaceNavigationMode workspaceNavigationMode;
  final bool workspaceRestoreBrowserSession;
  final bool workspaceRestoreOpenTabs;
  final bool workspaceOpenStartingPageInNewTab;
  final String? workspaceLastUrl;
  final List<Map<String, dynamic>> workspaceOpenTabs;
  final int workspaceSelectedTabIndex;
  final String? recurrenceId;
  final String? seriesTaskId;
  final DateTime? occurrenceOriginalStart;
  final DateTime? scheduledStartAt;
  final DateTime? scheduledEndAt;
  final DateTime? scheduledLocalDate;
  final String? scheduledLocalTime;
  final String timeZoneId;
  final String timeZoneBehavior;
  final int allDayEndMinutes;
  final bool isRecurringTemplate;
  final bool isRecurrenceException;
  final DateTime? skippedAt;
  final String? templateKey;
  final int? templateVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;

  bool get isCompleted => status == TaskStatus.completed;

  DateTime? get displayStart => plannedStartAt ?? scheduledStartAt ?? startDate;
  DateTime? get displayEnd => plannedEndAt ?? scheduledEndAt;
  String get effectiveTimeZoneId {
    if (timeZoneId.trim().isNotEmpty) return timeZoneId;
    if (recurrenceTimezone.trim().isNotEmpty) return recurrenceTimezone;
    return TimeZoneRegistry.deviceZoneId;
  }

  DateTime? get effectiveStartUtc {
    final absolute = plannedStartAt ?? scheduledStartAt;
    if (absolute != null) return absolute.toUtc();
    final localDate = scheduledLocalDate ?? plannedDate ?? startDate;
    if (localDate == null) return null;
    return TimeZoneRegistry.wallClockToUtc(
      date: localDate,
      minutesAfterMidnight: _minutesFromClock(scheduledLocalTime) ?? 0,
      zoneId: effectiveTimeZoneId,
    );
  }

  DateTime? get effectiveDueUtc {
    final explicit = dueAt ?? plannedEndAt ?? scheduledEndAt;
    if (explicit != null) return explicit.toUtc();

    final start = plannedStartAt ?? scheduledStartAt;
    if (start != null && estimatedMinutes > 0) {
      return start.toUtc().add(Duration(minutes: estimatedMinutes));
    }

    final localDate = scheduledLocalDate ?? dueDate ?? plannedDate ?? startDate;
    if (localDate == null) return null;
    final timeMinutes = _minutesFromClock(scheduledLocalTime);
    final localMoment = TimeZoneRegistry.wallClockToUtc(
      date: localDate,
      minutesAfterMidnight: timeMinutes ?? allDayEndMinutes,
      zoneId: effectiveTimeZoneId,
    );
    if (timeMinutes != null && estimatedMinutes > 0) {
      return localMoment.add(Duration(minutes: estimatedMinutes));
    }
    return localMoment;
  }

  DateTime? get effectiveDue => effectiveDueUtc?.toLocal();

  bool get isOverdue {
    return isOverdueAt(DateTime.now().toUtc());
  }

  bool isOverdueAt(DateTime nowUtc) {
    final due = effectiveDueUtc;
    if (due == null ||
        isCompleted ||
        status == TaskStatus.cancelled ||
        skippedAt != null ||
        deletedAt != null) {
      return false;
    }
    return nowUtc.toUtc().isAfter(due);
  }

  bool get isDueToday {
    final due = effectiveDueUtc;
    if (due == null) {
      return false;
    }
    final now = TimeZoneRegistry.nowIn(effectiveTimeZoneId);
    final zonedDue = TimeZoneRegistry.nowIn(effectiveTimeZoneId, nowUtc: due);
    return zonedDue.year == now.year &&
        zonedDue.month == now.month &&
        zonedDue.day == now.day;
  }

  TaskItem copyWith({
    String? title,
    String? description,
    TaskType? taskType,
    TaskDomain? taskDomain,
    TaskExecutionMode? executionMode,
    TaskEventState? eventState,
    String? categoryId,
    String? category,
    String? projectId,
    String? project,
    String? roadmapId,
    String? roadmapPhaseId,
    int? roadmapPhase,
    String? milestoneId,
    TaskPriority? priority,
    TaskStatus? status,
    DateTime? startDate,
    DateTime? dueDate,
    DateTime? plannedDate,
    DateTime? plannedStartAt,
    DateTime? plannedEndAt,
    DateTime? dueAt,
    DateTime? actualStartAt,
    DateTime? actualFinishAt,
    DateTime? arrivalAt,
    int? estimatedPomodoros,
    int? estimatedMinutes,
    int? actualFocusedMinutes,
    String? recurrence,
    String? recurrenceRule,
    String? recurrenceTimezone,
    DateTime? recurrenceEndAt,
    String? recurrenceEndType,
    int? recurrenceMaximumOccurrences,
    DateTime? recurrencePausedAt,
    String? learningResourceLink,
    String? launchMethod,
    String? notes,
    List<TaskChecklistItem>? checklist,
    List<String>? tags,
    int? progressPercentage,
    int? difficulty,
    int? energyRequirement,
    String? context,
    List<String>? attachments,
    String? completionEvidence,
    String? parentTaskId,
    List<String>? dependencies,
    Map<String, dynamic>? reminderRules,
    bool? adaptiveRemindersEnabled,
    String? defaultResourceId,
    String? location,
    bool? calendarIntegration,
    Map<String, dynamic>? completionRules,
    bool? timerEnabled,
    int? habitCurrentStreak,
    int? habitLongestStreak,
    bool? workspaceEnabled,
    TaskWorkspaceType? workspaceType,
    String? workspaceStartingUrl,
    String? workspaceHomeUrl,
    String? workspaceResourceTitle,
    TaskTrackingMode? workspaceBrowserMode,
    List<String>? workspaceAllowedDomains,
    bool? workspaceRestoreLastPage,
    bool? workspaceOpenAutomatically,
    TaskWorkspaceLayout? workspacePreferredLayout,
    TaskWorkspaceDockState? workspacePreferredDockState,
    bool? workspaceAllowExternalNavigation,
    bool? workspaceOpenUnsupportedExternally,
    TaskWorkspaceNavigationMode? workspaceNavigationMode,
    bool? workspaceRestoreBrowserSession,
    bool? workspaceRestoreOpenTabs,
    bool? workspaceOpenStartingPageInNewTab,
    String? workspaceLastUrl,
    List<Map<String, dynamic>>? workspaceOpenTabs,
    int? workspaceSelectedTabIndex,
    String? recurrenceId,
    String? seriesTaskId,
    DateTime? occurrenceOriginalStart,
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
    DateTime? scheduledLocalDate,
    String? scheduledLocalTime,
    String? timeZoneId,
    String? timeZoneBehavior,
    int? allDayEndMinutes,
    bool? isRecurringTemplate,
    bool? isRecurrenceException,
    DateTime? skippedAt,
    String? templateKey,
    int? templateVersion,
    DateTime? archivedAt,
    DateTime? deletedAt,
    bool clearArchivedAt = false,
    bool clearDeletedAt = false,
    bool clearProject = false,
    bool clearRoadmap = false,
    bool clearMilestone = false,
    bool clearSchedule = false,
    bool clearDefaultResource = false,
    bool clearLocation = false,
    bool clearRecurrence = false,
    bool clearRecurrencePause = false,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      taskType: taskType ?? this.taskType,
      taskDomain: taskDomain ?? this.taskDomain,
      executionMode: executionMode ?? this.executionMode,
      eventState: eventState ?? this.eventState,
      categoryId: categoryId ?? this.categoryId,
      category: category ?? this.category,
      projectId: clearProject ? null : projectId ?? this.projectId,
      project: clearProject ? null : project ?? this.project,
      roadmapId: clearRoadmap ? null : roadmapId ?? this.roadmapId,
      roadmapPhaseId: clearRoadmap
          ? null
          : roadmapPhaseId ?? this.roadmapPhaseId,
      roadmapPhase: clearRoadmap ? null : roadmapPhase ?? this.roadmapPhase,
      milestoneId: clearMilestone ? null : milestoneId ?? this.milestoneId,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      plannedDate: clearSchedule ? null : plannedDate ?? this.plannedDate,
      plannedStartAt: clearSchedule
          ? null
          : plannedStartAt ?? this.plannedStartAt,
      plannedEndAt: clearSchedule ? null : plannedEndAt ?? this.plannedEndAt,
      dueAt: clearSchedule ? null : dueAt ?? this.dueAt,
      actualStartAt: actualStartAt ?? this.actualStartAt,
      actualFinishAt: actualFinishAt ?? this.actualFinishAt,
      arrivalAt: arrivalAt ?? this.arrivalAt,
      estimatedPomodoros: estimatedPomodoros ?? this.estimatedPomodoros,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      actualFocusedMinutes: actualFocusedMinutes ?? this.actualFocusedMinutes,
      recurrence: clearRecurrence ? null : recurrence ?? this.recurrence,
      recurrenceRule: clearRecurrence
          ? null
          : recurrenceRule ?? this.recurrenceRule,
      recurrenceTimezone: recurrenceTimezone ?? this.recurrenceTimezone,
      recurrenceEndAt: clearRecurrence
          ? null
          : recurrenceEndAt ?? this.recurrenceEndAt,
      recurrenceEndType: clearRecurrence
          ? 'never'
          : recurrenceEndType ?? this.recurrenceEndType,
      recurrenceMaximumOccurrences: clearRecurrence
          ? null
          : recurrenceMaximumOccurrences ?? this.recurrenceMaximumOccurrences,
      recurrencePausedAt: clearRecurrencePause
          ? null
          : recurrencePausedAt ?? this.recurrencePausedAt,
      learningResourceLink: learningResourceLink ?? this.learningResourceLink,
      launchMethod: launchMethod ?? this.launchMethod,
      notes: notes ?? this.notes,
      checklist: checklist ?? this.checklist,
      tags: tags ?? this.tags,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      difficulty: difficulty ?? this.difficulty,
      energyRequirement: energyRequirement ?? this.energyRequirement,
      context: context ?? this.context,
      attachments: attachments ?? this.attachments,
      completionEvidence: completionEvidence ?? this.completionEvidence,
      parentTaskId: parentTaskId ?? this.parentTaskId,
      dependencies: dependencies ?? this.dependencies,
      reminderRules: reminderRules ?? this.reminderRules,
      adaptiveRemindersEnabled:
          adaptiveRemindersEnabled ?? this.adaptiveRemindersEnabled,
      defaultResourceId: clearDefaultResource
          ? null
          : defaultResourceId ?? this.defaultResourceId,
      location: clearLocation ? null : location ?? this.location,
      calendarIntegration: calendarIntegration ?? this.calendarIntegration,
      completionRules: completionRules ?? this.completionRules,
      timerEnabled: timerEnabled ?? this.timerEnabled,
      habitCurrentStreak: habitCurrentStreak ?? this.habitCurrentStreak,
      habitLongestStreak: habitLongestStreak ?? this.habitLongestStreak,
      workspaceEnabled: workspaceEnabled ?? this.workspaceEnabled,
      workspaceType: workspaceType ?? this.workspaceType,
      workspaceStartingUrl: workspaceStartingUrl ?? this.workspaceStartingUrl,
      workspaceHomeUrl: workspaceHomeUrl ?? this.workspaceHomeUrl,
      workspaceResourceTitle:
          workspaceResourceTitle ?? this.workspaceResourceTitle,
      workspaceBrowserMode: workspaceBrowserMode ?? this.workspaceBrowserMode,
      workspaceAllowedDomains:
          workspaceAllowedDomains ?? this.workspaceAllowedDomains,
      workspaceRestoreLastPage:
          workspaceRestoreLastPage ?? this.workspaceRestoreLastPage,
      workspaceOpenAutomatically:
          workspaceOpenAutomatically ?? this.workspaceOpenAutomatically,
      workspacePreferredLayout:
          workspacePreferredLayout ?? this.workspacePreferredLayout,
      workspacePreferredDockState:
          workspacePreferredDockState ?? this.workspacePreferredDockState,
      workspaceAllowExternalNavigation:
          workspaceAllowExternalNavigation ??
          this.workspaceAllowExternalNavigation,
      workspaceOpenUnsupportedExternally:
          workspaceOpenUnsupportedExternally ??
          this.workspaceOpenUnsupportedExternally,
      workspaceNavigationMode:
          workspaceNavigationMode ?? this.workspaceNavigationMode,
      workspaceRestoreBrowserSession:
          workspaceRestoreBrowserSession ?? this.workspaceRestoreBrowserSession,
      workspaceRestoreOpenTabs:
          workspaceRestoreOpenTabs ?? this.workspaceRestoreOpenTabs,
      workspaceOpenStartingPageInNewTab:
          workspaceOpenStartingPageInNewTab ??
          this.workspaceOpenStartingPageInNewTab,
      workspaceLastUrl: workspaceLastUrl ?? this.workspaceLastUrl,
      workspaceOpenTabs: workspaceOpenTabs ?? this.workspaceOpenTabs,
      workspaceSelectedTabIndex:
          workspaceSelectedTabIndex ?? this.workspaceSelectedTabIndex,
      recurrenceId: recurrenceId ?? this.recurrenceId,
      seriesTaskId: seriesTaskId ?? this.seriesTaskId,
      occurrenceOriginalStart:
          occurrenceOriginalStart ?? this.occurrenceOriginalStart,
      scheduledStartAt: scheduledStartAt ?? this.scheduledStartAt,
      scheduledEndAt: scheduledEndAt ?? this.scheduledEndAt,
      scheduledLocalDate: clearSchedule
          ? null
          : scheduledLocalDate ?? this.scheduledLocalDate,
      scheduledLocalTime: clearSchedule
          ? null
          : scheduledLocalTime ?? this.scheduledLocalTime,
      timeZoneId: timeZoneId ?? this.timeZoneId,
      timeZoneBehavior: timeZoneBehavior ?? this.timeZoneBehavior,
      allDayEndMinutes: allDayEndMinutes ?? this.allDayEndMinutes,
      isRecurringTemplate: isRecurringTemplate ?? this.isRecurringTemplate,
      isRecurrenceException:
          isRecurrenceException ?? this.isRecurrenceException,
      skippedAt: skippedAt ?? this.skippedAt,
      templateKey: templateKey ?? this.templateKey,
      templateVersion: templateVersion ?? this.templateVersion,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  TaskItem duplicate({String? newTitle}) {
    return TaskItem.fromMap({
      ...toInsertMap(),
      'id': const Uuid().v4(),
      'title': newTitle ?? '$title (copy)',
      'status': TaskStatus.notStarted.storageValue,
      'progress_percentage': 0,
      'actual_focused_minutes': 0,
      'recurrence_id': null,
      'series_task_id': null,
      'occurrence_original_start': null,
      'is_recurring_template': false,
      'is_recurrence_exception': false,
      'skipped_at': null,
      'template_key': null,
      'template_version': null,
      'archived_at': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  factory TaskItem.fromMap(Map<String, dynamic> map) {
    final taskType = TaskTypeX.fromStorage(map['task_type']?.toString());
    final category = map['category_name']?.toString() ?? 'Personal';
    return TaskItem(
      id: map['id']?.toString(),
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      taskType: taskType,
      taskDomain: TaskDomainX.fromStorage(
        map['task_domain']?.toString(),
        fallback: TaskDomainX.infer(taskType: taskType, category: category),
      ),
      executionMode: TaskExecutionModeX.fromStorage(
        map['execution_mode']?.toString(),
        fallback: TaskExecutionModeX.infer(taskType),
      ),
      eventState: TaskEventStateX.fromStorage(map['event_state']?.toString()),
      categoryId: map['category_id']?.toString(),
      category: category,
      projectId: map['project_id']?.toString(),
      project: map['project_name']?.toString(),
      roadmapId: map['roadmap_id']?.toString(),
      roadmapPhaseId: map['roadmap_phase_id']?.toString(),
      roadmapPhase: map['roadmap_phase'] is int
          ? map['roadmap_phase'] as int
          : null,
      milestoneId: map['milestone_id']?.toString(),
      priority: TaskPriorityX.fromStorage(map['priority']?.toString()),
      status: TaskStatusX.fromStorage(map['status']?.toString()),
      startDate: _dateFromMap(map['start_date']),
      dueDate: _dateFromMap(map['due_date']),
      plannedDate: _dateFromMap(map['planned_date']),
      plannedStartAt: _instantFromMap(
        map['planned_start_at'] ?? map['scheduled_start_at'],
        field: 'planned_start_at',
      ),
      plannedEndAt: _instantFromMap(
        map['planned_end_at'] ?? map['scheduled_end_at'],
        field: 'planned_end_at',
      ),
      dueAt: _instantFromMap(map['due_at'], field: 'due_at'),
      actualStartAt: _instantFromMap(
        map['actual_start_at'],
        field: 'actual_start_at',
      ),
      actualFinishAt: _instantFromMap(
        map['actual_finish_at'],
        field: 'actual_finish_at',
      ),
      arrivalAt: _instantFromMap(map['arrival_at'], field: 'arrival_at'),
      estimatedPomodoros: _intFromMap(map['estimated_pomodoros'], fallback: 1),
      estimatedMinutes: _intFromMap(map['estimated_minutes'], fallback: 25),
      actualFocusedMinutes: _intFromMap(map['actual_focused_minutes']),
      recurrence: map['recurrence']?.toString(),
      recurrenceRule: map['recurrence_rule']?.toString(),
      recurrenceTimezone: map['recurrence_timezone']?.toString() ?? 'UTC',
      recurrenceEndAt: _instantFromMap(
        map['recurrence_end_at'],
        field: 'recurrence_end_at',
      ),
      recurrenceEndType: map['recurrence_end_type']?.toString() ?? 'never',
      recurrenceMaximumOccurrences: _nullableIntFromMap(
        map['recurrence_maximum_occurrences'],
      ),
      recurrencePausedAt: _instantFromMap(
        map['recurrence_paused_at'],
        field: 'recurrence_paused_at',
      ),
      learningResourceLink: map['learning_resource_link']?.toString(),
      launchMethod: map['launch_method']?.toString(),
      notes: map['notes']?.toString() ?? '',
      checklist: _checklistFromMap(map['checklist']),
      tags: _stringListFromMap(map['tags']),
      progressPercentage: _intFromMap(map['progress_percentage']),
      difficulty: _intFromMap(map['difficulty'], fallback: 2),
      energyRequirement: _intFromMap(map['energy_requirement'], fallback: 2),
      context: map['context']?.toString(),
      attachments: _stringListFromMap(map['attachments']),
      completionEvidence: map['completion_evidence']?.toString(),
      parentTaskId: map['parent_task_id']?.toString(),
      dependencies: _stringListFromMap(map['dependencies']),
      reminderRules: _mapFromMap(map['reminder_rules']),
      adaptiveRemindersEnabled: _boolFromMap(map['adaptive_reminders_enabled']),
      defaultResourceId: map['default_resource_id']?.toString(),
      location: map['location']?.toString(),
      calendarIntegration: _boolFromMap(map['calendar_integration']),
      completionRules: _mapFromMap(map['completion_rules']),
      timerEnabled: _boolFromMap(map['timer_enabled'], fallback: true),
      habitCurrentStreak: _intFromMap(map['habit_current_streak']),
      habitLongestStreak: _intFromMap(map['habit_longest_streak']),
      workspaceEnabled: _boolFromMap(map['workspace_enabled']),
      workspaceType: TaskWorkspaceTypeX.fromStorage(
        map['workspace_type']?.toString(),
      ),
      workspaceStartingUrl: map['workspace_starting_url']?.toString(),
      workspaceHomeUrl: map['workspace_home_url']?.toString(),
      workspaceResourceTitle: map['workspace_resource_title']?.toString(),
      workspaceBrowserMode: TaskTrackingModeX.fromStorage(
        map['workspace_browser_mode']?.toString(),
      ),
      workspaceAllowedDomains: _stringListFromMap(
        map['workspace_allowed_domains'],
      ),
      workspaceRestoreLastPage: _boolFromMap(
        map['workspace_restore_last_page'],
        fallback: true,
      ),
      workspaceOpenAutomatically: _boolFromMap(
        map['workspace_open_automatically'],
      ),
      workspacePreferredLayout: TaskWorkspaceLayoutX.fromStorage(
        map['workspace_preferred_layout']?.toString(),
      ),
      workspacePreferredDockState: TaskWorkspaceDockStateX.fromStorage(
        map['workspace_preferred_dock_state']?.toString(),
      ),
      workspaceAllowExternalNavigation: _boolFromMap(
        map['workspace_allow_external_navigation'],
        fallback: true,
      ),
      workspaceOpenUnsupportedExternally: _boolFromMap(
        map['workspace_open_unsupported_externally'],
        fallback: true,
      ),
      workspaceNavigationMode: TaskWorkspaceNavigationModeX.fromStorage(
        map['workspace_navigation_mode']?.toString(),
      ),
      workspaceRestoreBrowserSession: _boolFromMap(
        map['workspace_restore_browser_session'],
        fallback: true,
      ),
      workspaceRestoreOpenTabs: _boolFromMap(
        map['workspace_restore_open_tabs'],
        fallback: true,
      ),
      workspaceOpenStartingPageInNewTab: _boolFromMap(
        map['workspace_open_starting_page_in_new_tab'],
      ),
      workspaceLastUrl: map['workspace_last_url']?.toString(),
      workspaceOpenTabs: _mapListFromMap(map['workspace_open_tabs']),
      workspaceSelectedTabIndex: _intFromMap(
        map['workspace_selected_tab_index'],
      ),
      recurrenceId: map['recurrence_id']?.toString(),
      seriesTaskId: map['series_task_id']?.toString(),
      occurrenceOriginalStart: _instantFromMap(
        map['occurrence_original_start'],
        field: 'occurrence_original_start',
      ),
      scheduledStartAt: _instantFromMap(
        map['scheduled_start_at'],
        field: 'scheduled_start_at',
      ),
      scheduledEndAt: _instantFromMap(
        map['scheduled_end_at'],
        field: 'scheduled_end_at',
      ),
      scheduledLocalDate: _dateFromMap(map['scheduled_local_date']),
      scheduledLocalTime: map['scheduled_local_time']?.toString(),
      timeZoneId:
          map['time_zone_id']?.toString() ??
          map['recurrence_timezone']?.toString() ??
          '',
      timeZoneBehavior:
          map['time_zone_behavior']?.toString() ?? 'keep_local_clock',
      allDayEndMinutes: _intFromMap(map['all_day_end_minutes'], fallback: 1439),
      isRecurringTemplate: _boolFromMap(map['is_recurring_template']),
      isRecurrenceException: _boolFromMap(map['is_recurrence_exception']),
      skippedAt: _instantFromMap(map['skipped_at'], field: 'skipped_at'),
      templateKey: map['template_key']?.toString(),
      templateVersion: _nullableIntFromMap(map['template_version']),
      createdAt:
          _instantFromMap(map['created_at'], field: 'created_at') ??
          DateTime.now().toUtc(),
      updatedAt:
          _instantFromMap(map['updated_at'], field: 'updated_at') ??
          DateTime.now().toUtc(),
      archivedAt: _instantFromMap(map['archived_at'], field: 'archived_at'),
      deletedAt: _instantFromMap(map['deleted_at'], field: 'deleted_at'),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'title': title,
      'description': description,
      'task_type': taskType.storageValue,
      'task_domain': taskDomain.storageValue,
      'execution_mode': executionMode.storageValue,
      'event_state': eventState.storageValue,
      'category_id': categoryId,
      'category_name': category,
      'project_id': projectId,
      'project_name': project,
      'roadmap_id': roadmapId,
      'roadmap_phase_id': roadmapPhaseId,
      'roadmap_phase': roadmapPhase,
      'milestone_id': milestoneId,
      'priority': priority.storageValue,
      'priority_rank': priority.rank,
      'status': status.storageValue,
      'start_date': startDate?.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'planned_date': plannedDate?.toIso8601String().split('T').first,
      'planned_start_at': plannedStartAt?.toUtc().toIso8601String(),
      'planned_end_at': plannedEndAt?.toUtc().toIso8601String(),
      'due_at': dueAt?.toUtc().toIso8601String(),
      'actual_start_at': actualStartAt?.toUtc().toIso8601String(),
      'actual_finish_at': actualFinishAt?.toUtc().toIso8601String(),
      'arrival_at': arrivalAt?.toUtc().toIso8601String(),
      'estimated_pomodoros': estimatedPomodoros,
      'estimated_minutes': estimatedMinutes,
      'actual_focused_minutes': actualFocusedMinutes,
      'recurrence': recurrence,
      'recurrence_rule': recurrenceRule,
      'recurrence_timezone': recurrenceTimezone,
      'recurrence_end_at': recurrenceEndAt?.toUtc().toIso8601String(),
      'recurrence_end_type': recurrenceEndType,
      'recurrence_maximum_occurrences': recurrenceMaximumOccurrences,
      'recurrence_paused_at': recurrencePausedAt?.toUtc().toIso8601String(),
      'learning_resource_link': learningResourceLink,
      'launch_method': launchMethod,
      'notes': notes,
      'checklist': [for (final item in checklist) item.toJson()],
      'tags': tags,
      'progress_percentage': progressPercentage,
      'difficulty': difficulty,
      'energy_requirement': energyRequirement,
      'context': context,
      'attachments': attachments,
      'completion_evidence': completionEvidence,
      'parent_task_id': parentTaskId,
      'dependencies': dependencies,
      'reminder_rules': reminderRules,
      'adaptive_reminders_enabled': adaptiveRemindersEnabled,
      'default_resource_id': defaultResourceId,
      'location': location,
      'calendar_integration': calendarIntegration,
      'completion_rules': completionRules,
      'timer_enabled': timerEnabled,
      'habit_current_streak': habitCurrentStreak,
      'habit_longest_streak': habitLongestStreak,
      'workspace_enabled': workspaceEnabled,
      'workspace_type': workspaceType.storageValue,
      'workspace_starting_url': workspaceStartingUrl,
      'workspace_home_url': workspaceHomeUrl,
      'workspace_resource_title': workspaceResourceTitle,
      'workspace_browser_mode': workspaceBrowserMode.storageValue,
      'workspace_allowed_domains': workspaceAllowedDomains,
      'workspace_restore_last_page': workspaceRestoreLastPage,
      'workspace_open_automatically': workspaceOpenAutomatically,
      'workspace_preferred_layout': workspacePreferredLayout.storageValue,
      'workspace_preferred_dock_state':
          workspacePreferredDockState.storageValue,
      'workspace_allow_external_navigation': workspaceAllowExternalNavigation,
      'workspace_open_unsupported_externally':
          workspaceOpenUnsupportedExternally,
      'workspace_navigation_mode': workspaceNavigationMode.storageValue,
      'workspace_restore_browser_session': workspaceRestoreBrowserSession,
      'workspace_restore_open_tabs': workspaceRestoreOpenTabs,
      'workspace_open_starting_page_in_new_tab':
          workspaceOpenStartingPageInNewTab,
      'workspace_last_url': workspaceLastUrl,
      'workspace_open_tabs': workspaceOpenTabs,
      'workspace_selected_tab_index': workspaceSelectedTabIndex,
      'recurrence_id': recurrenceId,
      'series_task_id': seriesTaskId,
      'occurrence_original_start': occurrenceOriginalStart
          ?.toUtc()
          .toIso8601String(),
      'scheduled_start_at': scheduledStartAt?.toUtc().toIso8601String(),
      'scheduled_end_at': scheduledEndAt?.toUtc().toIso8601String(),
      'scheduled_local_date': scheduledLocalDate
          ?.toIso8601String()
          .split('T')
          .first,
      'scheduled_local_time': scheduledLocalTime,
      'time_zone_id': effectiveTimeZoneId,
      'time_zone_behavior': timeZoneBehavior,
      'all_day_end_minutes': allDayEndMinutes,
      'is_recurring_template': isRecurringTemplate,
      'is_recurrence_exception': isRecurrenceException,
      'skipped_at': skippedAt?.toUtc().toIso8601String(),
      'template_key': templateKey,
      'template_version': templateVersion,
      'archived_at': archivedAt?.toUtc().toIso8601String(),
    };
  }

  static DateTime? _dateFromMap(Object? value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }

  static DateTime? _instantFromMap(Object? value, {required String field}) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    try {
      TimeZoneRegistry.lastTaskValueReceived = text;
      return parseDatabaseInstantValue(text);
    } on FormatException catch (error) {
      if (kDebugMode) {
        debugPrint('TASK INSTANT PARSE REJECTED ($field): $error');
      }
      return null;
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('TASK INSTANT PARSE FAILED ($field): $error');
      }
      return null;
    }
  }

  static int _intFromMap(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _minutesFromClock(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  static int? _nullableIntFromMap(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  static List<String> _stringListFromMap(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  static List<TaskChecklistItem> _checklistFromMap(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map && item['title']?.toString().trim().isNotEmpty == true)
          TaskChecklistItem(
            title: item['title'].toString(),
            done: _boolFromMap(item['done']),
          ),
    ];
  }

  static Map<String, dynamic> _mapFromMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return const {};
  }

  static List<Map<String, dynamic>> _mapListFromMap(Object? value) {
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    return const [];
  }

  static bool _boolFromMap(Object? value, {bool fallback = false}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return switch (value?.toString().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      'false' || '0' || 'no' => false,
      _ => fallback,
    };
  }
}
