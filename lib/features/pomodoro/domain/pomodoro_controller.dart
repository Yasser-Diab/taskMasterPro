import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/platform/task_reminder_scheduler.dart';
import 'pomodoro_models.dart';

class PomodoroController extends ChangeNotifier {
  PomodoroController({PomodoroPreset? preset, TaskReminderScheduler? scheduler})
    : _preset = preset ?? defaultPomodoroPresets[0],
      _scheduler = scheduler ?? const TaskReminderScheduler(),
      _remainingSeconds =
          (preset ?? defaultPomodoroPresets[0]).focusMinutes * 60 {
    _current = this;
  }

  static PomodoroController? _current;

  static void observeWebsiteDuringBreak(
    String domain, {
    String? relatedTaskId,
  }) {
    _current?._observeWebsiteDuringBreak(domain, relatedTaskId: relatedTaskId);
  }

  Timer? _timer;
  final TaskReminderScheduler _scheduler;
  PomodoroPreset _preset;
  PomodoroPhase _phase = PomodoroPhase.focus;
  PomodoroRunState _state = PomodoroRunState.idle;
  TrackingMode _trackingMode = TrackingMode.interactive;
  DateTime? _startedAt;
  int _remainingSeconds;
  int _completedFocusSessions = 0;
  int _interruptionCount = 0;
  bool _successful = true;
  String _note = '';
  List<SessionSegment> _segments = const [];
  String? _sessionId;
  String? _selectedTaskId;
  PomodoroBreakActivity? _breakActivity;
  PomodoroBreakActivity? _pendingBreakReview;

  PomodoroPreset get preset => _preset;
  PomodoroPhase get phase => _phase;
  PomodoroRunState get state => _state;
  TrackingMode get trackingMode => _trackingMode;
  DateTime? get startedAt => _startedAt;
  int get remainingSeconds => _remainingSeconds;
  int get completedFocusSessions => _completedFocusSessions;
  int get interruptionCount => _interruptionCount;
  bool get successful => _successful;
  String get note => _note;
  List<SessionSegment> get segments => _segments;
  String? get sessionId => _sessionId;
  String? get selectedTaskId => _selectedTaskId;
  PomodoroBreakActivity? get breakActivity => _breakActivity;
  PomodoroBreakActivity? get pendingBreakReview => _pendingBreakReview;

  void selectTask(String? taskId) {
    _selectedTaskId = taskId;
    notifyListeners();
  }

  void classifyBreak(PomodoroBreakUse use, {String? relatedTaskId}) {
    final activity = _breakActivity;
    if (activity == null) return;
    _breakActivity = activity.copyWith(use: use, relatedTaskId: relatedTaskId);
    notifyListeners();
  }

  void clearBreakReview() {
    _pendingBreakReview = null;
    notifyListeners();
  }

  void _observeWebsiteDuringBreak(String domain, {String? relatedTaskId}) {
    final activity = _breakActivity;
    final normalized = domain.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (activity == null || normalized.isEmpty) return;
    _breakActivity = activity.copyWith(
      evidenceDomain: normalized,
      relatedTaskId: relatedTaskId,
    );
    notifyListeners();
  }

  String get clockText {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void selectPreset(PomodoroPreset preset) {
    if (!_state.isInactive) {
      return;
    }
    _preset = preset;
    _remainingSeconds = preset.focusMinutes * 60;
    notifyListeners();
  }

  void setTrackingMode(TrackingMode mode) {
    _trackingMode = mode;
    notifyListeners();
  }

  void start({String? sessionId}) {
    startFocus(sessionId: sessionId);
  }

  void attachSession(String sessionId) {
    if (sessionId.trim().isEmpty || _sessionId == sessionId) {
      return;
    }
    _sessionId = sessionId;
    notifyListeners();
  }

  void startFocus({String? sessionId}) {
    if (_state == PomodoroRunState.focusRunning) return;
    _startedAt ??= DateTime.now();
    _sessionId ??= sessionId ?? const Uuid().v4();
    if (_phase != PomodoroPhase.focus) {
      _finishBreakForReview(reason: 'return_to_focus');
    }
    _phase = PomodoroPhase.focus;
    if (_remainingSeconds <= 0) {
      _remainingSeconds = _preset.focusMinutes * 60;
    }
    _state = PomodoroRunState.focusRunning;
    _addSegment('active');
    _startTicker();
    notifyListeners();
  }

  void pause() {
    if (!_state.isRunning) {
      return;
    }
    _state = _phase == PomodoroPhase.focus
        ? PomodoroRunState.focusPaused
        : PomodoroRunState.breakPaused;
    _closeOpenSegment();
    _addSegment('paused');
    _timer?.cancel();
    notifyListeners();
  }

  void resume() {
    if (!_state.isPaused) {
      return;
    }
    _state = _phase == PomodoroPhase.focus
        ? PomodoroRunState.focusRunning
        : PomodoroRunState.breakRunning;
    _closeOpenSegment();
    _addSegment(_phase == PomodoroPhase.focus ? 'active' : 'break');
    _startTicker();
    notifyListeners();
  }

  void completeEarly() {
    if (_state.isInactive || _state.isWaitingForUser) {
      return;
    }
    _finishCurrentStage(reason: 'completed_early');
    notifyListeners();
  }

  void skipBreak() {
    if (_phase == PomodoroPhase.focus) {
      return;
    }
    _finishBreakForReview(reason: 'break_skipped');
    _prepareNextFocus();
    notifyListeners();
  }

  void startBreak() {
    if (_phase != PomodoroPhase.focus) return;
    if (_state != PomodoroRunState.focusFinishedWaitingForUser) {
      _finishFocusSegment(reason: 'jumped_to_break');
    }
    final shouldLongBreak =
        _completedFocusSessions > 0 &&
        _completedFocusSessions % _preset.longBreakAfter == 0;
    _phase = shouldLongBreak
        ? PomodoroPhase.longBreak
        : PomodoroPhase.shortBreak;
    _remainingSeconds = shouldLongBreak
        ? _preset.longBreakMinutes * 60
        : _preset.shortBreakMinutes * 60;
    _state = PomodoroRunState.breakRunning;
    _breakActivity = PomodoroBreakActivity(startedAt: DateTime.now());
    _addSegment('break');
    _startTicker();
    notifyListeners();
    unawaited(
      _scheduler.showImmediate(
        title: 'Break started',
        body: 'Your break has started.',
        channel: 'break_alarm',
      ),
    );
  }

  void finishBreakEarly() {
    if (_phase == PomodoroPhase.focus || _state.isInactive) return;
    _finishBreakForReview(reason: 'break_finished_early');
    _state = PomodoroRunState.breakFinishedWaitingForUser;
    _remainingSeconds = 0;
    notifyListeners();
  }

  void extendBreak({int minutes = 5}) {
    if (_phase == PomodoroPhase.focus) return;
    _remainingSeconds += minutes * 60;
    if (!_state.isRunning) {
      _state = PomodoroRunState.breakRunning;
      _addSegment('break');
      _startTicker();
    }
    notifyListeners();
  }

  void returnToFocus() {
    if (_phase != PomodoroPhase.focus) {
      _finishBreakForReview(reason: 'return_to_focus');
    }
    _prepareNextFocus();
    notifyListeners();
  }

  void continueWorking({int minutes = 5}) {
    if (_phase != PomodoroPhase.focus) return;
    if (_state == PomodoroRunState.focusFinishedWaitingForUser) {
      _remainingSeconds = minutes * 60;
      _state = PomodoroRunState.focusRunning;
      _addSegment('active');
      _startTicker();
      notifyListeners();
    } else {
      addTime(minutes: minutes);
    }
  }

  void finishTask() {
    _timer?.cancel();
    _closeOpenSegment();
    _finishBreakForReview(reason: 'task_finished');
    _state = PomodoroRunState.completed;
    notifyListeners();
  }

  void addTime({int minutes = 5}) {
    _remainingSeconds += minutes * 60;
    notifyListeners();
  }

  void markInterruption(InterruptionReason reason) {
    _interruptionCount += 1;
    _closeOpenSegment();
    _addSegment('interruption:${reason.storageValue}');
    _closeOpenSegment();
    if (_state.isRunning) {
      _addSegment(_phase == PomodoroPhase.focus ? 'active' : 'break');
    }
    notifyListeners();
  }

  void markUnsuccessful() {
    _successful = false;
    notifyListeners();
  }

  void updateNote(String note) {
    _note = note;
    notifyListeners();
  }

  PomodoroSessionSummary? stopAndSave() {
    final summary = _buildSummary();
    _reset();
    return summary;
  }

  void stopWithoutSaving() {
    _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (identical(_current, this)) _current = null;
    super.dispose();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds > 0) {
        _remainingSeconds -= 1;
        notifyListeners();
        return;
      }
      _finishCurrentStage(reason: 'planned_duration_reached');
    });
  }

  void _finishCurrentStage({required String reason}) {
    if (_phase == PomodoroPhase.focus) {
      _finishFocusSegment(reason: reason);
    } else {
      _finishBreakForReview(reason: reason);
      _state = PomodoroRunState.breakFinishedWaitingForUser;
      _remainingSeconds = 0;
      unawaited(
        _scheduler.showImmediate(
          title: 'Break completed',
          body: 'It is time to choose your next step.',
          channel: 'break_alarm',
        ),
      );
    }
    notifyListeners();
  }

  void _finishFocusSegment({required String reason}) {
    _timer?.cancel();
    _closeOpenSegment();
    final countsAsCompleted =
        reason == 'planned_duration_reached' || _remainingSeconds <= 0;
    if (countsAsCompleted) {
      _completedFocusSessions += 1;
    }
    _remainingSeconds = 0;
    _state = PomodoroRunState.focusFinishedWaitingForUser;
    unawaited(
      _scheduler.showImmediate(
        title: 'Focus completed',
        body: '${_preset.focusMinutes} minutes recorded.',
        channel: 'focus_alarm',
      ),
    );
  }

  void _finishBreakForReview({required String reason}) {
    _timer?.cancel();
    _closeOpenSegment();
    if (_breakActivity != null) {
      _pendingBreakReview = _breakActivity!.copyWith(endedAt: DateTime.now());
    }
    _breakActivity = null;
  }

  void _prepareNextFocus() {
    _phase = PomodoroPhase.focus;
    _state = PomodoroRunState.focusReady;
    _remainingSeconds = _preset.focusMinutes * 60;
  }

  void _addSegment(String kind) {
    _segments = [
      ..._segments,
      SessionSegment(kind: kind, startedAt: DateTime.now()),
    ];
  }

  void _closeOpenSegment() {
    if (_segments.isEmpty) {
      return;
    }
    final last = _segments.last;
    if (last.endedAt != null) {
      return;
    }
    _segments = [
      ..._segments.take(_segments.length - 1),
      last.close(DateTime.now()),
    ];
  }

  PomodoroSessionSummary? _buildSummary() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return null;
    }
    _timer?.cancel();
    _closeOpenSegment();
    final endedAt = DateTime.now();
    var activeSeconds = 0;
    var pausedSeconds = 0;

    for (final segment in _segments) {
      final end = segment.endedAt ?? endedAt;
      final seconds = end.difference(segment.startedAt).inSeconds;
      if (segment.kind == 'active') {
        activeSeconds += seconds;
      } else if (segment.kind == 'paused') {
        pausedSeconds += seconds;
      }
    }

    return PomodoroSessionSummary(
      startedAt: startedAt,
      endedAt: endedAt,
      grossSeconds: endedAt.difference(startedAt).inSeconds,
      activeSeconds: activeSeconds,
      pausedSeconds: pausedSeconds,
      interruptionCount: _interruptionCount,
      successful: _successful,
      note: _note,
      trackingMode: _trackingMode,
    );
  }

  void _reset() {
    _timer?.cancel();
    _phase = PomodoroPhase.focus;
    _state = PomodoroRunState.idle;
    _startedAt = null;
    _remainingSeconds = _preset.focusMinutes * 60;
    _completedFocusSessions = 0;
    _interruptionCount = 0;
    _successful = true;
    _note = '';
    _segments = const [];
    _sessionId = null;
    _breakActivity = null;
    _pendingBreakReview = null;
    notifyListeners();
  }
}
