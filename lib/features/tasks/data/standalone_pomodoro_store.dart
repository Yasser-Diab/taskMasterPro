import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/account/account_context.dart';

enum StandalonePomodoroPhase {
  idle,
  focusRunning,
  focusPaused,
  focusFinished,
  breakRunning,
  breakPaused,
  breakFinished,
}

class StandalonePomodoroState {
  const StandalonePomodoroState({
    this.phase = StandalonePomodoroPhase.idle,
    this.focusDurationMs = 25 * 60 * 1000,
    this.breakDurationMs = 5 * 60 * 1000,
    this.intervalExtensionMs = 0,
    this.accumulatedMs = 0,
    this.segmentStartedAt,
    this.completedFocusCount = 0,
  });

  final StandalonePomodoroPhase phase;
  final int focusDurationMs;
  final int breakDurationMs;

  /// A one-off extension for the current break. It is cleared whenever a new
  /// focus or break interval starts, so extending one rest never mutates the
  /// user's configured default.
  final int intervalExtensionMs;
  final int accumulatedMs;
  final DateTime? segmentStartedAt;
  final int completedFocusCount;

  bool get isActive => phase != StandalonePomodoroPhase.idle;
  bool get isRunning =>
      phase == StandalonePomodoroPhase.focusRunning ||
      phase == StandalonePomodoroPhase.breakRunning;
  bool get isPaused =>
      phase == StandalonePomodoroPhase.focusPaused ||
      phase == StandalonePomodoroPhase.breakPaused;
  bool get isBreak =>
      phase == StandalonePomodoroPhase.breakRunning ||
      phase == StandalonePomodoroPhase.breakPaused ||
      phase == StandalonePomodoroPhase.breakFinished;
  bool get isFinished =>
      phase == StandalonePomodoroPhase.focusFinished ||
      phase == StandalonePomodoroPhase.breakFinished;

  int get intervalDurationMs =>
      isBreak ? breakDurationMs + intervalExtensionMs : focusDurationMs;

  bool get canStartFocus =>
      phase == StandalonePomodoroPhase.idle ||
      phase == StandalonePomodoroPhase.focusFinished ||
      isBreak;
  bool get canStartBreak => !isBreak && phase != StandalonePomodoroPhase.idle;
  bool get canExtendBreak => isBreak;

  /// Absolute boundary for the current running interval. The UI may tick as
  /// often as it likes, but persistence and notification scheduling need only
  /// this one timestamp.
  DateTime? get boundaryAtUtc {
    final startedAt = segmentStartedAt;
    if (!isRunning || startedAt == null) return null;
    final remainingFromSegmentMs = (intervalDurationMs - accumulatedMs).clamp(
      0,
      intervalDurationMs,
    );
    return startedAt.toUtc().add(
      Duration(milliseconds: remainingFromSegmentMs),
    );
  }

  String? get completionEventType => !isRunning
      ? null
      : isBreak
      ? 'standalone_break_completed'
      : 'standalone_focus_completed';

  int elapsedAt(DateTime now) {
    final liveMs = isRunning && segmentStartedAt != null
        ? now.toUtc().difference(segmentStartedAt!.toUtc()).inMilliseconds
        : 0;
    return (accumulatedMs + liveMs).clamp(0, intervalDurationMs);
  }

  int remainingAt(DateTime now) =>
      (intervalDurationMs - elapsedAt(now)).clamp(0, intervalDurationMs);

  StandalonePomodoroState advanceAt(DateTime now) {
    if (!isRunning || remainingAt(now) > 0) return this;
    return copyWith(
      phase: isBreak
          ? StandalonePomodoroPhase.breakFinished
          : StandalonePomodoroPhase.focusFinished,
      accumulatedMs: intervalDurationMs,
      clearSegmentStartedAt: true,
      completedFocusCount: isBreak
          ? completedFocusCount
          : completedFocusCount + 1,
    );
  }

  StandalonePomodoroState copyWith({
    StandalonePomodoroPhase? phase,
    int? focusDurationMs,
    int? breakDurationMs,
    int? intervalExtensionMs,
    int? accumulatedMs,
    DateTime? segmentStartedAt,
    bool clearSegmentStartedAt = false,
    int? completedFocusCount,
  }) {
    return StandalonePomodoroState(
      phase: phase ?? this.phase,
      focusDurationMs: focusDurationMs ?? this.focusDurationMs,
      breakDurationMs: breakDurationMs ?? this.breakDurationMs,
      intervalExtensionMs: intervalExtensionMs ?? this.intervalExtensionMs,
      accumulatedMs: accumulatedMs ?? this.accumulatedMs,
      segmentStartedAt: clearSegmentStartedAt
          ? null
          : segmentStartedAt ?? this.segmentStartedAt,
      completedFocusCount: completedFocusCount ?? this.completedFocusCount,
    );
  }

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'focus_duration_ms': focusDurationMs,
    'break_duration_ms': breakDurationMs,
    'interval_extension_ms': intervalExtensionMs,
    'accumulated_ms': accumulatedMs,
    'segment_started_at': segmentStartedAt?.toUtc().toIso8601String(),
    'completed_focus_count': completedFocusCount,
  };

  factory StandalonePomodoroState.fromJson(Map<String, Object?> json) {
    final phaseName = json['phase'] as String?;
    return StandalonePomodoroState(
      phase: StandalonePomodoroPhase.values.firstWhere(
        (value) => value.name == phaseName,
        orElse: () => StandalonePomodoroPhase.idle,
      ),
      focusDurationMs:
          (json['focus_duration_ms'] as num?)?.toInt() ?? 25 * 60 * 1000,
      breakDurationMs:
          (json['break_duration_ms'] as num?)?.toInt() ?? 5 * 60 * 1000,
      intervalExtensionMs:
          (json['interval_extension_ms'] as num?)?.toInt() ?? 0,
      accumulatedMs: (json['accumulated_ms'] as num?)?.toInt() ?? 0,
      segmentStartedAt: DateTime.tryParse(
        json['segment_started_at'] as String? ?? '',
      )?.toUtc(),
      completedFocusCount:
          (json['completed_focus_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A device-local, account-isolated timer store.
///
/// Only interval boundaries are written. The one-second display is derived
/// from [segmentStartedAt], so this timer generates no sync traffic and no
/// per-second disk writes.
class StandalonePomodoroStore {
  StandalonePomodoroStore({
    required String accountId,
    Future<SharedPreferences> Function()? openPreferences,
  }) : _key = 'taskmaster.standalone_pomodoro.v1.$accountId',
       _openPreferences = openPreferences ?? SharedPreferences.getInstance;

  final String _key;
  final Future<SharedPreferences> Function() _openPreferences;
  final _changes = StreamController<StandalonePomodoroState>.broadcast();
  Future<void> _transitionQueue = Future<void>.value();

  Future<StandalonePomodoroState> load({DateTime? now}) async {
    final preferences = await _openPreferences();
    final raw = preferences.getString(_key);
    StandalonePomodoroState state;
    try {
      state = raw == null
          ? const StandalonePomodoroState()
          : StandalonePomodoroState.fromJson(
              (jsonDecode(raw) as Map).cast<String, Object?>(),
            );
    } catch (_) {
      state = const StandalonePomodoroState();
    }
    final advanced = state.advanceAt((now ?? DateTime.now()).toUtc());
    if (advanced.phase != state.phase) await _save(advanced, preferences);
    return advanced;
  }

  Stream<StandalonePomodoroState> watch() async* {
    yield await load();
    yield* _changes.stream;
  }

  Future<void> configure({required Duration focus, required Duration rest}) =>
      _serialize(() async {
        final state = await load();
        if (state.isActive) return;
        await _save(
          state.copyWith(
            focusDurationMs: focus.inMilliseconds,
            breakDurationMs: rest.inMilliseconds,
            intervalExtensionMs: 0,
            accumulatedMs: 0,
            clearSegmentStartedAt: true,
          ),
        );
      });

  Future<void> startFocus({DateTime? now}) => _serialize(() async {
    final state = await load(now: now);
    if (!state.canStartFocus) return;
    await _save(
      state.copyWith(
        phase: StandalonePomodoroPhase.focusRunning,
        accumulatedMs: 0,
        intervalExtensionMs: 0,
        segmentStartedAt: (now ?? DateTime.now()).toUtc(),
      ),
    );
  });

  Future<void> startBreak({DateTime? now}) => _serialize(() async {
    final state = await load(now: now);
    if (!state.canStartBreak) return;
    await _save(
      state.copyWith(
        phase: StandalonePomodoroPhase.breakRunning,
        accumulatedMs: 0,
        intervalExtensionMs: 0,
        segmentStartedAt: (now ?? DateTime.now()).toUtc(),
      ),
    );
  });

  /// Ends the current focus interval early and begins the configured break.
  Future<void> skipFocus({DateTime? now}) => startBreak(now: now);

  /// Ends the current break early (or dismisses its waiting state) and begins
  /// a fresh focus interval from the configured focus duration.
  Future<void> skipBreak({DateTime? now}) => startFocus(now: now);

  /// Extends only the current break. Extending a just-finished break resumes
  /// it from zero remaining with the added time instead of staying frozen at
  /// `00:00` while claiming to run.
  Future<void> extendBreak({
    Duration by = const Duration(minutes: 5),
    DateTime? now,
  }) => _serialize(() async {
    final instant = (now ?? DateTime.now()).toUtc();
    final state = await load(now: instant);
    if (!state.canExtendBreak || by <= Duration.zero) return;
    final addedMs = by.inMilliseconds.clamp(
      Duration.millisecondsPerMinute,
      60 * Duration.millisecondsPerMinute,
    );
    final wasFinished = state.phase == StandalonePomodoroPhase.breakFinished;
    await _save(
      state.copyWith(
        phase: wasFinished ? StandalonePomodoroPhase.breakRunning : state.phase,
        intervalExtensionMs: state.intervalExtensionMs + addedMs,
        accumulatedMs: wasFinished
            ? state.intervalDurationMs
            : state.accumulatedMs,
        segmentStartedAt: wasFinished ? instant : state.segmentStartedAt,
      ),
    );
  });

  Future<void> pause({DateTime? now}) => _serialize(() async {
    final instant = (now ?? DateTime.now()).toUtc();
    final state = await load(now: instant);
    if (!state.isRunning) return;
    await _save(
      state.copyWith(
        phase: state.isBreak
            ? StandalonePomodoroPhase.breakPaused
            : StandalonePomodoroPhase.focusPaused,
        accumulatedMs: state.elapsedAt(instant),
        clearSegmentStartedAt: true,
      ),
    );
  });

  Future<void> resume({DateTime? now}) => _serialize(() async {
    final state = await load(now: now);
    if (!state.isPaused) return;
    await _save(
      state.copyWith(
        phase: state.isBreak
            ? StandalonePomodoroPhase.breakRunning
            : StandalonePomodoroPhase.focusRunning,
        segmentStartedAt: (now ?? DateTime.now()).toUtc(),
      ),
    );
  });

  Future<void> advanceIfDue({DateTime? now}) => _serialize(() async {
    final instant = (now ?? DateTime.now()).toUtc();
    final state = await load(now: instant);
    final advanced = state.advanceAt(instant);
    if (advanced.phase != state.phase) await _save(advanced);
  });

  /// Releases the local execution claim without throwing away the user's
  /// device-local durations or completed-session history.
  Future<void> reset() => _serialize(() async {
    final state = await load();
    await _save(
      state.copyWith(
        phase: StandalonePomodoroPhase.idle,
        accumulatedMs: 0,
        intervalExtensionMs: 0,
        clearSegmentStartedAt: true,
      ),
    );
  });

  Future<void> _serialize(Future<void> Function() transition) {
    final queued = _transitionQueue.then((_) => transition());
    // Keep the internal tail usable after a single preference/plugin failure;
    // the caller still receives the original error from [queued].
    _transitionQueue = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return queued;
  }

  Future<void> _save(
    StandalonePomodoroState state, [
    SharedPreferences? existingPreferences,
  ]) async {
    final preferences = existingPreferences ?? await _openPreferences();
    await preferences.setString(_key, jsonEncode(state.toJson()));
    _changes.add(state);
  }

  void dispose() => _changes.close();
}

final standalonePomodoroStoreProvider = Provider<StandalonePomodoroStore>((
  ref,
) {
  final accountId = ref.watch(activeAccountIdProvider) ?? '__signed_out__';
  final store = StandalonePomodoroStore(accountId: accountId);
  ref.onDispose(store.dispose);
  return store;
});

final standalonePomodoroStateProvider = StreamProvider<StandalonePomodoroState>(
  (ref) => ref.watch(standalonePomodoroStoreProvider).watch(),
);
