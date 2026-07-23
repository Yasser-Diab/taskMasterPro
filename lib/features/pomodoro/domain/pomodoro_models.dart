enum PomodoroPhase { focus, shortBreak, longBreak }

enum PomodoroStage {
  idle,
  focusReady,
  focusRunning,
  focusPaused,
  focusCompletedWaiting,
  breakReady,
  breakRunning,
  breakPaused,
  breakCompletedWaiting,
  taskCompleted,
  cancelled,
}

extension PomodoroStageX on PomodoroStage {
  String get storageValue => switch (this) {
    PomodoroStage.focusReady => 'focus_ready',
    PomodoroStage.focusRunning => 'focus_running',
    PomodoroStage.focusPaused => 'focus_paused',
    PomodoroStage.focusCompletedWaiting => 'focus_completed_waiting',
    PomodoroStage.breakReady => 'break_ready',
    PomodoroStage.breakRunning => 'break_running',
    PomodoroStage.breakPaused => 'break_paused',
    PomodoroStage.breakCompletedWaiting => 'break_completed_waiting',
    PomodoroStage.taskCompleted => 'task_completed',
    PomodoroStage.cancelled => 'cancelled',
    PomodoroStage.idle => 'idle',
  };

  bool get isRunning =>
      this == PomodoroStage.focusRunning || this == PomodoroStage.breakRunning;

  bool get isPaused =>
      this == PomodoroStage.focusPaused || this == PomodoroStage.breakPaused;

  bool get isWaiting =>
      this == PomodoroStage.focusCompletedWaiting ||
      this == PomodoroStage.breakCompletedWaiting ||
      this == PomodoroStage.breakReady ||
      this == PomodoroStage.focusReady;

  bool get isFocusStage =>
      this == PomodoroStage.focusReady ||
      this == PomodoroStage.focusRunning ||
      this == PomodoroStage.focusPaused ||
      this == PomodoroStage.focusCompletedWaiting;

  bool get isBreakStage =>
      this == PomodoroStage.breakReady ||
      this == PomodoroStage.breakRunning ||
      this == PomodoroStage.breakPaused ||
      this == PomodoroStage.breakCompletedWaiting;

  static PomodoroStage fromStorage(String? value) {
    return switch (value) {
      'focus_ready' => PomodoroStage.focusReady,
      'focus_running' => PomodoroStage.focusRunning,
      'focus_paused' => PomodoroStage.focusPaused,
      'focus_completed_waiting' => PomodoroStage.focusCompletedWaiting,
      'break_ready' => PomodoroStage.breakReady,
      'break_running' => PomodoroStage.breakRunning,
      'break_paused' => PomodoroStage.breakPaused,
      'break_completed_waiting' => PomodoroStage.breakCompletedWaiting,
      'task_completed' => PomodoroStage.taskCompleted,
      'cancelled' => PomodoroStage.cancelled,
      _ => PomodoroStage.idle,
    };
  }
}

enum PomodoroRunState {
  idle,
  focusReady,
  focusRunning,
  focusPaused,
  focusFinishedWaitingForUser,
  breakReady,
  breakRunning,
  breakPaused,
  breakFinishedWaitingForUser,
  completed,
  cancelled,
}

extension PomodoroRunStateX on PomodoroRunState {
  PomodoroStage get stage => switch (this) {
    PomodoroRunState.focusReady => PomodoroStage.focusReady,
    PomodoroRunState.focusRunning => PomodoroStage.focusRunning,
    PomodoroRunState.focusPaused => PomodoroStage.focusPaused,
    PomodoroRunState.focusFinishedWaitingForUser =>
      PomodoroStage.focusCompletedWaiting,
    PomodoroRunState.breakReady => PomodoroStage.breakReady,
    PomodoroRunState.breakRunning => PomodoroStage.breakRunning,
    PomodoroRunState.breakPaused => PomodoroStage.breakPaused,
    PomodoroRunState.breakFinishedWaitingForUser =>
      PomodoroStage.breakCompletedWaiting,
    PomodoroRunState.completed => PomodoroStage.taskCompleted,
    PomodoroRunState.cancelled => PomodoroStage.cancelled,
    PomodoroRunState.idle => PomodoroStage.idle,
  };

  bool get isInactive =>
      this == PomodoroRunState.idle ||
      this == PomodoroRunState.completed ||
      this == PomodoroRunState.cancelled;

  bool get isRunning =>
      this == PomodoroRunState.focusRunning ||
      this == PomodoroRunState.breakRunning;

  bool get isPaused =>
      this == PomodoroRunState.focusPaused ||
      this == PomodoroRunState.breakPaused;

  bool get isWaitingForUser =>
      this == PomodoroRunState.focusFinishedWaitingForUser ||
      this == PomodoroRunState.breakFinishedWaitingForUser;

  bool get isFocusState =>
      this == PomodoroRunState.focusReady ||
      this == PomodoroRunState.focusRunning ||
      this == PomodoroRunState.focusPaused ||
      this == PomodoroRunState.focusFinishedWaitingForUser;

  bool get isBreakState =>
      this == PomodoroRunState.breakReady ||
      this == PomodoroRunState.breakRunning ||
      this == PomodoroRunState.breakPaused ||
      this == PomodoroRunState.breakFinishedWaitingForUser;
}

enum TrackingMode { interactive, video, reading, manual }

enum PomodoroBreakUse {
  undecided,
  rest,
  learning,
  reading,
  exercise,
  housework,
  anotherTask,
  custom,
}

class PomodoroBreakActivity {
  const PomodoroBreakActivity({
    required this.startedAt,
    this.endedAt,
    this.use = PomodoroBreakUse.undecided,
    this.relatedTaskId,
    this.evidenceDomain,
  });

  final DateTime startedAt;
  final DateTime? endedAt;
  final PomodoroBreakUse use;
  final String? relatedTaskId;
  final String? evidenceDomain;

  int get durationSeconds => (endedAt ?? DateTime.now())
      .difference(startedAt)
      .inSeconds
      .clamp(0, 7200);

  PomodoroBreakActivity copyWith({
    DateTime? endedAt,
    PomodoroBreakUse? use,
    String? relatedTaskId,
    String? evidenceDomain,
  }) => PomodoroBreakActivity(
    startedAt: startedAt,
    endedAt: endedAt ?? this.endedAt,
    use: use ?? this.use,
    relatedTaskId: relatedTaskId ?? this.relatedTaskId,
    evidenceDomain: evidenceDomain ?? this.evidenceDomain,
  );
}

enum InterruptionReason {
  phoneCall,
  workRequest,
  familyNeed,
  technicalProblem,
  distraction,
  breakTaken,
  taskCompleted,
  changedPriority,
  other,
}

extension InterruptionReasonX on InterruptionReason {
  String get label => switch (this) {
    InterruptionReason.phoneCall => 'Phone call',
    InterruptionReason.workRequest => 'Work request',
    InterruptionReason.familyNeed => 'Family need',
    InterruptionReason.technicalProblem => 'Technical problem',
    InterruptionReason.distraction => 'Distraction',
    InterruptionReason.breakTaken => 'Break',
    InterruptionReason.taskCompleted => 'Task completed',
    InterruptionReason.changedPriority => 'Changed priority',
    InterruptionReason.other => 'Other',
  };

  String get storageValue => switch (this) {
    InterruptionReason.phoneCall => 'phone_call',
    InterruptionReason.workRequest => 'work_request',
    InterruptionReason.familyNeed => 'family_need',
    InterruptionReason.technicalProblem => 'technical_problem',
    InterruptionReason.breakTaken => 'break',
    InterruptionReason.taskCompleted => 'task_completed',
    InterruptionReason.changedPriority => 'changed_priority',
    _ => name,
  };
}

class PomodoroPreset {
  const PomodoroPreset({
    required this.name,
    required this.focusMinutes,
    required this.shortBreakMinutes,
    required this.longBreakMinutes,
    required this.longBreakAfter,
  });

  final String name;
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int longBreakAfter;
}

const defaultPomodoroPresets = <PomodoroPreset>[
  PomodoroPreset(
    name: '25/5 default',
    focusMinutes: 25,
    shortBreakMinutes: 5,
    longBreakMinutes: 20,
    longBreakAfter: 4,
  ),
  PomodoroPreset(
    name: '50/10 deep work',
    focusMinutes: 50,
    shortBreakMinutes: 10,
    longBreakMinutes: 20,
    longBreakAfter: 4,
  ),
  PomodoroPreset(
    name: '45/10 practice',
    focusMinutes: 45,
    shortBreakMinutes: 10,
    longBreakMinutes: 20,
    longBreakAfter: 4,
  ),
  PomodoroPreset(
    name: '15/5 low-energy study',
    focusMinutes: 15,
    shortBreakMinutes: 5,
    longBreakMinutes: 15,
    longBreakAfter: 4,
  ),
  PomodoroPreset(
    name: '90/20 project building',
    focusMinutes: 90,
    shortBreakMinutes: 20,
    longBreakMinutes: 20,
    longBreakAfter: 2,
  ),
];

class SessionSegment {
  const SessionSegment({
    required this.kind,
    required this.startedAt,
    this.endedAt,
  });

  final String kind;
  final DateTime startedAt;
  final DateTime? endedAt;

  SessionSegment close(DateTime endedAt) {
    return SessionSegment(kind: kind, startedAt: startedAt, endedAt: endedAt);
  }
}

class PomodoroSessionSummary {
  const PomodoroSessionSummary({
    required this.startedAt,
    required this.endedAt,
    required this.grossSeconds,
    required this.activeSeconds,
    required this.pausedSeconds,
    required this.interruptionCount,
    required this.successful,
    required this.note,
    required this.trackingMode,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final int grossSeconds;
  final int activeSeconds;
  final int pausedSeconds;
  final int interruptionCount;
  final bool successful;
  final String note;
  final TrackingMode trackingMode;
}
