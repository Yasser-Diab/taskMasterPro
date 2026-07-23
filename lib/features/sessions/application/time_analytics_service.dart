import '../domain/session_models.dart';

class TimeBreakdown {
  const TimeBreakdown({
    this.grossSeconds = 0,
    this.activeSeconds = 0,
    this.idleSeconds = 0,
    this.pausedSeconds = 0,
    this.interruptedSeconds = 0,
    this.breakSeconds = 0,
    this.manualSeconds = 0,
  });

  final int grossSeconds;
  final int activeSeconds;
  final int idleSeconds;
  final int pausedSeconds;
  final int interruptedSeconds;
  final int breakSeconds;
  final int manualSeconds;

  int get nonActiveSeconds =>
      idleSeconds + pausedSeconds + interruptedSeconds + breakSeconds;

  TimeBreakdown operator +(TimeBreakdown other) {
    return TimeBreakdown(
      grossSeconds: grossSeconds + other.grossSeconds,
      activeSeconds: activeSeconds + other.activeSeconds,
      idleSeconds: idleSeconds + other.idleSeconds,
      pausedSeconds: pausedSeconds + other.pausedSeconds,
      interruptedSeconds: interruptedSeconds + other.interruptedSeconds,
      breakSeconds: breakSeconds + other.breakSeconds,
      manualSeconds: manualSeconds + other.manualSeconds,
    );
  }
}

class EstimateComparison {
  const EstimateComparison({
    required this.estimatedSeconds,
    required this.actualActiveSeconds,
  });

  final int estimatedSeconds;
  final int actualActiveSeconds;

  int get varianceSeconds => actualActiveSeconds - estimatedSeconds;

  double get accuracy {
    if (estimatedSeconds <= 0 && actualActiveSeconds <= 0) {
      return 1;
    }
    if (estimatedSeconds <= 0 || actualActiveSeconds <= 0) {
      return 0;
    }
    final minValue = estimatedSeconds < actualActiveSeconds
        ? estimatedSeconds
        : actualActiveSeconds;
    final maxValue = estimatedSeconds > actualActiveSeconds
        ? estimatedSeconds
        : actualActiveSeconds;
    return minValue / maxValue;
  }
}

class TimeAnalyticsService {
  const TimeAnalyticsService();

  TimeBreakdown fromSegments(List<TrackedSessionSegment> segments) {
    var active = 0;
    var idle = 0;
    var paused = 0;
    var interrupted = 0;
    var breaks = 0;
    var manual = 0;
    DateTime? firstStart;
    DateTime? lastEnd;

    for (final segment in segments) {
      final end = segment.endedAt ?? DateTime.now();
      final seconds = segment.durationSeconds > 0
          ? segment.durationSeconds
          : end.difference(segment.startedAt).inSeconds.clamp(0, 1 << 31);
      firstStart = firstStart == null || segment.startedAt.isBefore(firstStart)
          ? segment.startedAt
          : firstStart;
      lastEnd = lastEnd == null || end.isAfter(lastEnd) ? end : lastEnd;

      switch (segment.type) {
        case SessionSegmentType.active:
        case SessionSegmentType.video:
        case SessionSegmentType.reading:
        case SessionSegmentType.externalResource:
          active += seconds;
        case SessionSegmentType.manual:
          active += seconds;
          manual += seconds;
        case SessionSegmentType.idle:
          idle += seconds;
        case SessionSegmentType.paused:
          paused += seconds;
        case SessionSegmentType.interruption:
          interrupted += seconds;
        case SessionSegmentType.breakTime:
          breaks += seconds;
      }
    }

    final gross = firstStart == null || lastEnd == null
        ? 0
        : lastEnd.difference(firstStart).inSeconds.clamp(0, 1 << 31);

    return TimeBreakdown(
      grossSeconds: gross,
      activeSeconds: active,
      idleSeconds: idle,
      pausedSeconds: paused,
      interruptedSeconds: interrupted,
      breakSeconds: breaks,
      manualSeconds: manual,
    );
  }

  TimeBreakdown fromSessions(List<TrackedSession> sessions) {
    return sessions.fold<TimeBreakdown>(
      const TimeBreakdown(),
      (total, session) =>
          total +
          TimeBreakdown(
            grossSeconds: session.grossSeconds,
            activeSeconds: session.activeSeconds,
            idleSeconds: session.idleSeconds,
            pausedSeconds: session.pausedSeconds,
            interruptedSeconds: session.interruptedSeconds,
            breakSeconds: session.breakSeconds,
            manualSeconds: session.manualSeconds,
          ),
    );
  }

  EstimateComparison compareEstimate({
    required int estimatedMinutes,
    required int actualActiveSeconds,
  }) {
    return EstimateComparison(
      estimatedSeconds: estimatedMinutes * 60,
      actualActiveSeconds: actualActiveSeconds,
    );
  }

  Map<DateTime, int> activeSecondsByDay(List<TrackedSession> sessions) {
    final result = <DateTime, int>{};
    for (final session in sessions) {
      final day = DateTime(
        session.startedAt.year,
        session.startedAt.month,
        session.startedAt.day,
      );
      result.update(
        day,
        (value) => value + session.activeSeconds,
        ifAbsent: () => session.activeSeconds,
      );
    }
    return result;
  }
}

String formatDurationCompact(int seconds) {
  final safeSeconds = seconds.clamp(0, 1 << 31).toInt();
  if (safeSeconds < 60) {
    return '${safeSeconds}s';
  }
  final minutes = safeSeconds ~/ 60;
  final secondsRemainder = safeSeconds % 60;
  if (minutes < 10 && secondsRemainder > 0) {
    return '${minutes}m ${secondsRemainder}s';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) {
    return '${minutes}m';
  }
  if (remainder == 0) {
    return '${hours}h';
  }
  return '${hours}h ${remainder}m';
}
