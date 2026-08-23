import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/reports/data/performance_report_service.dart';

void main() {
  final l10n = const AppLocalizations(Locale('en'));

  PerformanceReportOptions options({DateTime? from, DateTime? to}) =>
      PerformanceReportOptions(
        type: PerformanceReportType.account,
        from: from ?? DateTime(2026, 7, 1),
        to: to ?? DateTime(2026, 7, 31),
        localeCode: 'en',
        landscape: false,
        sections: const {'summary', 'activity'},
        timeZone: 'UTC',
      );

  LocalTask task({
    required String id,
    String mode = 'continuous',
    String? templateId,
    String? status,
    DateTime? scheduledDate,
    DateTime? plannedStart,
    DateTime? plannedEnd,
    Duration estimate = const Duration(hours: 1),
    DateTime? actualStart,
    DateTime? actualFinish,
    int activeMs = 0,
    String dataJson = '{}',
  }) => LocalTask(
    id: id,
    userId: 'user-1',
    templateId: templateId,
    title: id,
    description: '',
    status: status ?? (actualFinish == null ? 'running' : 'completed'),
    priority: 2,
    executionMode: mode,
    scheduledDate: scheduledDate ?? actualStart,
    plannedStart: plannedStart,
    plannedEnd: plannedEnd,
    estimatedDurationMs: estimate.inMilliseconds,
    actualStart: actualStart,
    actualFinish: actualFinish,
    activeDurationMs: activeMs,
    pausedDurationMs: 0,
    idleDurationMs: 0,
    progress: 0,
    dataJson: dataJson,
    revision: 1,
    createdAt: actualStart ?? DateTime.utc(2026, 7, 1),
    updatedAt: actualFinish ?? actualStart ?? DateTime.utc(2026, 7, 1),
  );

  LocalEntityRecord session({
    required String id,
    required String taskId,
    required DateTime start,
    required DateTime finish,
    required int activeMs,
  }) => LocalEntityRecord(
    id: id,
    userId: 'user-1',
    entityType: 'execution_sessions',
    parentId: taskId,
    title: 'Session',
    status: 'completed',
    position: 0,
    dataJson: jsonEncode({
      'task_occurrence_id': taskId,
      'started_at': start.toIso8601String(),
      'finished_at': finish.toIso8601String(),
      'accumulated_active_ms': activeMs,
      'state': 'completed',
    }),
    revision: 1,
    createdAt: start,
    updatedAt: finish,
  );

  LocalEntityRecord event({
    required String id,
    required String sessionId,
    required String type,
    required DateTime at,
    int? durationMs,
  }) => LocalEntityRecord(
    id: id,
    userId: 'user-1',
    entityType: 'session_events',
    parentId: sessionId,
    title: type,
    status: 'recorded',
    position: 0,
    dataJson: jsonEncode({
      'session_id': sessionId,
      'event_type': type,
      'occurred_at': at.toIso8601String(),
      'duration_ms': durationMs,
    }),
    revision: 1,
    createdAt: at,
    updatedAt: at,
  );

  PerformanceReportSnapshot snapshot({
    required List<LocalTask> tasks,
    List<LocalEntityRecord> sessions = const [],
    List<LocalEntityRecord> events = const [],
    List<LocalActivitySegment> activity = const [],
    List<LocalAttribution> attributions = const [],
    LocalRuntime? runtime,
  }) => PerformanceReportSnapshot(
    profile: null,
    roadmap: null,
    tasks: tasks,
    phases: const [],
    milestones: const [],
    checkpoints: const [],
    activity: activity,
    contributions: const [],
    attributions: attributions,
    insights: const [],
    health: const [],
    sessions: sessions,
    sessionEvents: events,
    runtime: runtime,
  );

  LocalActivitySegment activity({
    required String id,
    required DateTime start,
    required DateTime end,
    String deviceId = 'device-1',
    String? deviceEventId,
    String? processName,
    String? domain,
    String? url,
    String? idleState,
  }) => LocalActivitySegment(
    id: id,
    userId: 'user-1',
    deviceId: deviceId,
    deviceEventId: deviceEventId ?? id,
    startedAt: start,
    endedAt: end,
    sourceType: 'application',
    processName: processName,
    domain: domain,
    url: url,
    idleState: idleState,
    rawMetadataJson: '{}',
    revision: 1,
    createdAt: start,
    updatedAt: end,
  );

  LocalAttribution attribution({
    required String segmentId,
    required String classification,
    required DateTime at,
    int revision = 1,
  }) => LocalAttribution(
    id: 'attribution-$segmentId-$revision',
    userId: 'user-1',
    activitySegmentId: segmentId,
    targetType: 'unassigned_activity',
    classification: classification,
    confidence: 1,
    attributionStatus: 'confirmed',
    confirmedByUser: true,
    revision: revision,
    createdAt: at,
    updatedAt: at,
  );

  test(
    'uses an interval union and fair task allocation for overlapping sessions',
    () {
      final aStart = DateTime.utc(2026, 7, 10, 10);
      final bStart = DateTime.utc(2026, 7, 10, 10, 10);
      final aEnd = DateTime.utc(2026, 7, 10, 10, 30);
      final bEnd = DateTime.utc(2026, 7, 10, 10, 40);
      final data = snapshot(
        tasks: [
          task(id: 'continuous-task', mode: 'continuous'),
          task(id: 'focus-task', mode: 'pomodoro'),
        ],
        sessions: [
          session(
            id: 'session-a',
            taskId: 'continuous-task',
            start: aStart,
            finish: aEnd,
            activeMs: const Duration(minutes: 30).inMilliseconds,
          ),
          session(
            id: 'session-b',
            taskId: 'focus-task',
            start: bStart,
            finish: bEnd,
            activeMs: const Duration(minutes: 30).inMilliseconds,
          ),
        ],
        events: [
          event(
            id: 'a-start',
            sessionId: 'session-a',
            type: 'start',
            at: aStart,
          ),
          event(
            id: 'a-end',
            sessionId: 'session-a',
            type: 'complete',
            at: aEnd,
          ),
          event(
            id: 'b-start',
            sessionId: 'session-b',
            type: 'start',
            at: bStart,
          ),
          event(
            id: 'b-end',
            sessionId: 'session-b',
            type: 'complete',
            at: bEnd,
          ),
        ],
      );

      final facts = PerformanceReportService.factsForSnapshot(
        data,
        options(),
        l10n,
        now: DateTime.utc(2026, 7, 10, 12),
      );

      expect(facts.productiveMs, const Duration(minutes: 40).inMilliseconds);
      expect(facts.focusMs, const Duration(minutes: 20).inMilliseconds);
      expect(facts.continuousMs, const Duration(minutes: 20).inMilliseconds);
      expect(facts.focusMs + facts.continuousMs, facts.productiveMs);
      expect(
        facts.daily
            .singleWhere((item) => item.day == DateTime(2026, 7, 10))
            .productiveMs,
        const Duration(minutes: 40).inMilliseconds,
      );
    },
  );

  test(
    'ignores a stale zero-duration running session when canonical runtime is idle',
    () {
      final staleStart = DateTime.utc(2026, 7, 10, 8);
      final realStart = DateTime.utc(2026, 7, 10, 8, 10);
      final realPause = realStart.add(const Duration(minutes: 14));
      final realFinish = realPause.add(const Duration(minutes: 3));
      final recordedMs = realPause.difference(realStart).inMilliseconds;
      final completedTask = task(
        id: 'completed-task',
        mode: 'pomodoro',
        status: 'completed',
        actualStart: realStart,
        actualFinish: realFinish,
        activeMs: recordedMs,
      );
      final staleSession = LocalEntityRecord(
        id: 'stale-running-session',
        userId: 'user-1',
        entityType: 'execution_sessions',
        parentId: completedTask.id,
        title: 'Session',
        status: 'running',
        position: 0,
        dataJson: jsonEncode({
          'task_occurrence_id': completedTask.id,
          'started_at': staleStart.toIso8601String(),
          'finished_at': null,
          'active_segment_started_at': staleStart.toIso8601String(),
          'accumulated_active_ms': 0,
          'state': 'running',
        }),
        revision: 1,
        createdAt: staleStart,
        updatedAt: staleStart,
      );
      final completedSession = session(
        id: 'completed-session',
        taskId: completedTask.id,
        start: realStart,
        finish: realFinish,
        activeMs: recordedMs,
      );
      final data = snapshot(
        tasks: [completedTask],
        sessions: [staleSession, completedSession],
        events: [
          event(
            id: 'real-start',
            sessionId: completedSession.id,
            type: 'start',
            at: realStart,
          ),
          event(
            id: 'real-pause',
            sessionId: completedSession.id,
            type: 'pause',
            at: realPause,
          ),
          event(
            id: 'real-complete',
            sessionId: completedSession.id,
            type: 'complete',
            at: realFinish,
          ),
        ],
        runtime: LocalRuntime(
          id: 'runtime:user-1',
          userId: 'user-1',
          state: 'idle',
          accumulatedActiveMs: recordedMs,
          accumulatedPausedMs: 0,
          dataJson: '{}',
          revision: 1,
          updatedAt: realFinish,
        ),
      );

      final facts = PerformanceReportService.factsForSnapshot(
        data,
        options(),
        l10n,
        now: DateTime.utc(2026, 7, 13, 12),
      );

      expect(facts.productiveMs, recordedMs);
      expect(facts.focusMs, recordedMs);
      expect(
        facts.daily
            .singleWhere((point) => point.day == DateTime(2026, 7, 10))
            .productiveMs,
        recordedMs,
      );
      expect(
        PerformanceReportService.taskGroupsForReport(
          data.tasks,
          facts,
          now: DateTime.utc(2026, 7, 13, 12),
        ).single.recordedMs,
        recordedMs,
      );
    },
  );

  test(
    'uses canonical session totals when a remote snapshot has no event rows',
    () {
      final startedAt = DateTime.utc(2026, 7, 10, 9);
      final finishedAt = DateTime.utc(2026, 7, 10, 12);
      final recordedMs = const Duration(hours: 1, minutes: 40).inMilliseconds;
      final synchronizedTask = task(
        id: 'remote-task',
        mode: 'pomodoro',
        status: 'completed',
        actualStart: startedAt,
        actualFinish: finishedAt,
        // A fresh device must not depend on the task's denormalized cache.
        activeMs: 0,
      );
      final remoteSession = session(
        id: 'remote-session',
        taskId: synchronizedTask.id,
        start: startedAt,
        finish: finishedAt,
        activeMs: recordedMs,
      );
      final data = snapshot(
        tasks: [synchronizedTask],
        sessions: [remoteSession],
        // This is the shape observed after an authoritative mobile snapshot:
        // the canonical session is present while its event ledger is absent.
        events: const [],
      );

      final facts = PerformanceReportService.factsForSnapshot(
        data,
        options(),
        l10n,
        now: DateTime.utc(2026, 7, 10, 13),
      );

      expect(facts.productiveMs, recordedMs);
      expect(facts.focusMs, recordedMs);
      expect(facts.continuousMs, 0);
      expect(facts.taskWork.single.durationMs, recordedMs);
    },
  );

  test(
    'uses cumulative event duration while the mobile session row is stale',
    () {
      final startedAt = DateTime.utc(2026, 7, 11, 9);
      final firstBoundary = startedAt.add(const Duration(minutes: 25));
      final resumedAt = startedAt.add(const Duration(minutes: 35));
      final finishedAt = startedAt.add(const Duration(minutes: 55));
      final recordedMs = const Duration(minutes: 45).inMilliseconds;
      final synchronizedTask = task(
        id: 'stale-mobile-task',
        mode: 'pomodoro',
        status: 'completed',
        actualStart: startedAt,
        actualFinish: finishedAt,
        activeMs: 0,
      );
      final staleSession = session(
        id: 'stale-mobile-session',
        taskId: synchronizedTask.id,
        start: startedAt,
        finish: finishedAt,
        // The mutable session row arrived before its final canonical update.
        activeMs: 0,
      );
      final data = snapshot(
        tasks: [synchronizedTask],
        sessions: [staleSession],
        events: [
          event(
            id: 'mobile-start',
            sessionId: staleSession.id,
            type: 'start',
            at: startedAt,
          ),
          event(
            id: 'mobile-break',
            sessionId: staleSession.id,
            type: 'start_break',
            at: firstBoundary,
            durationMs: const Duration(minutes: 25).inMilliseconds,
          ),
          event(
            id: 'mobile-resume',
            sessionId: staleSession.id,
            type: 'finish_break',
            at: resumedAt,
            durationMs: const Duration(minutes: 25).inMilliseconds,
          ),
          event(
            id: 'mobile-complete',
            sessionId: staleSession.id,
            type: 'complete',
            at: finishedAt,
            durationMs: recordedMs,
          ),
        ],
      );

      final facts = PerformanceReportService.factsForSnapshot(
        data,
        options(),
        l10n,
        now: finishedAt.add(const Duration(hours: 1)),
      );

      expect(facts.productiveMs, recordedMs);
      expect(facts.focusMs, recordedMs);
      expect(facts.breakMs, const Duration(minutes: 10).inMilliseconds);
    },
  );

  test('fills only uncovered work after a trailing break completion', () {
    final startedAt = DateTime.utc(2026, 7, 12, 9);
    final finishedAt = DateTime.utc(2026, 7, 12, 12);
    final recordedMs = const Duration(hours: 1).inMilliseconds;
    final synchronizedTask = task(
      id: 'partial-ledger-task',
      mode: 'pomodoro',
      status: 'completed',
      actualStart: startedAt,
      actualFinish: finishedAt,
      activeMs: 0,
    );
    final staleSession = session(
      id: 'partial-ledger-session',
      taskId: synchronizedTask.id,
      start: startedAt,
      finish: finishedAt,
      activeMs: 0,
    );
    final data = snapshot(
      tasks: [synchronizedTask],
      sessions: [staleSession],
      events: [
        event(
          id: 'partial-start',
          sessionId: staleSession.id,
          type: 'start',
          at: startedAt,
        ),
        event(
          id: 'partial-break-1',
          sessionId: staleSession.id,
          type: 'start_break',
          at: startedAt.add(const Duration(minutes: 25)),
          durationMs: const Duration(minutes: 25).inMilliseconds,
        ),
        event(
          id: 'partial-resume',
          sessionId: staleSession.id,
          type: 'finish_break',
          at: startedAt.add(const Duration(minutes: 35)),
          durationMs: const Duration(minutes: 25).inMilliseconds,
        ),
        event(
          id: 'partial-break-2',
          sessionId: staleSession.id,
          type: 'start_break',
          at: startedAt.add(const Duration(minutes: 55)),
          durationMs: const Duration(minutes: 45).inMilliseconds,
        ),
        event(
          id: 'partial-complete',
          sessionId: staleSession.id,
          type: 'complete',
          at: finishedAt,
          durationMs: recordedMs,
        ),
      ],
    );

    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
      now: finishedAt.add(const Duration(days: 2)),
    );

    expect(facts.productiveMs, recordedMs);
    expect(facts.focusMs, recordedMs);
    expect(facts.breakMs, const Duration(hours: 2).inMilliseconds);
    expect(
      facts.productiveMs + facts.breakMs,
      finishedAt.difference(startedAt).inMilliseconds,
    );
  });

  test('bounds an unmatched completed break at the session finish', () {
    final startedAt = DateTime.utc(2026, 7, 13, 9);
    final finishedAt = DateTime.utc(2026, 7, 13, 10);
    final synchronizedTask = task(
      id: 'bounded-break-task',
      mode: 'pomodoro',
      status: 'completed',
      actualStart: startedAt,
      actualFinish: finishedAt,
      activeMs: const Duration(minutes: 50).inMilliseconds,
    );
    final completedSession = session(
      id: 'bounded-break-session',
      taskId: synchronizedTask.id,
      start: startedAt,
      finish: finishedAt,
      activeMs: const Duration(minutes: 50).inMilliseconds,
    );
    final data = snapshot(
      tasks: [synchronizedTask],
      sessions: [completedSession],
      events: [
        event(
          id: 'bounded-break-start',
          sessionId: completedSession.id,
          type: 'start_break',
          at: finishedAt.subtract(const Duration(minutes: 10)),
          durationMs: const Duration(minutes: 50).inMilliseconds,
        ),
      ],
    );

    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
      now: finishedAt.add(const Duration(days: 3)),
    );

    expect(facts.breakMs, const Duration(minutes: 10).inMilliseconds);
  });

  test('keeps the canonical live running session visible', () {
    final now = DateTime.utc(2026, 7, 10, 10, 10);
    final start = now.subtract(const Duration(minutes: 10));
    final runningTask = task(
      id: 'running-task',
      mode: 'pomodoro',
      status: 'running',
      actualStart: start,
    );
    final runningSession = LocalEntityRecord(
      id: 'running-session',
      userId: 'user-1',
      entityType: 'execution_sessions',
      parentId: runningTask.id,
      title: 'Session',
      status: 'running',
      position: 0,
      dataJson: jsonEncode({
        'task_occurrence_id': runningTask.id,
        'started_at': start.toIso8601String(),
        'finished_at': null,
        'active_segment_started_at': start.toIso8601String(),
        'accumulated_active_ms': 0,
        'state': 'running',
      }),
      revision: 1,
      createdAt: start,
      updatedAt: start,
    );
    final data = snapshot(
      tasks: [runningTask],
      sessions: [runningSession],
      runtime: LocalRuntime(
        id: 'runtime:user-1',
        userId: 'user-1',
        activeTaskId: runningTask.id,
        sessionId: runningSession.id,
        state: 'running',
        segmentStartedAt: start,
        accumulatedActiveMs: 0,
        accumulatedPausedMs: 0,
        dataJson: '{}',
        revision: 1,
        updatedAt: now,
      ),
    );

    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
      now: now,
    );

    expect(facts.productiveMs, const Duration(minutes: 10).inMilliseconds);
    expect(facts.focusMs, facts.productiveMs);
  });

  test('caps a live Pomodoro segment at its current focus boundary', () {
    final now = DateTime.utc(2026, 7, 10, 15);
    final sessionStart = DateTime.utc(2026, 7, 10, 10, 40);
    final firstPause = sessionStart.add(const Duration(minutes: 10));
    final resumedAt = DateTime.utc(2026, 7, 10, 11);
    final accumulatedMs = const Duration(minutes: 10).inMilliseconds;
    final runningTask = task(
      id: 'bounded-running-pomodoro',
      mode: 'pomodoro',
      status: 'running',
      actualStart: sessionStart,
      dataJson: jsonEncode({
        'pomodoro_focus_ms': const Duration(minutes: 25).inMilliseconds,
      }),
    );
    final runningSession = LocalEntityRecord(
      id: 'bounded-running-session',
      userId: 'user-1',
      entityType: 'execution_sessions',
      parentId: runningTask.id,
      title: 'Session',
      status: 'running',
      position: 0,
      dataJson: jsonEncode({
        'task_occurrence_id': runningTask.id,
        'started_at': sessionStart.toIso8601String(),
        'finished_at': null,
        'active_segment_started_at': resumedAt.toIso8601String(),
        'accumulated_active_ms': accumulatedMs,
        'state': 'running',
      }),
      revision: 1,
      createdAt: sessionStart,
      updatedAt: resumedAt,
    );
    final data = snapshot(
      tasks: [runningTask],
      sessions: [runningSession],
      events: [
        event(
          id: 'bounded-start',
          sessionId: runningSession.id,
          type: 'start',
          at: sessionStart,
        ),
        event(
          id: 'bounded-pause',
          sessionId: runningSession.id,
          type: 'pause',
          at: firstPause,
          durationMs: accumulatedMs,
        ),
        event(
          id: 'bounded-resume',
          sessionId: runningSession.id,
          type: 'resume',
          at: resumedAt,
          durationMs: accumulatedMs,
        ),
      ],
      runtime: LocalRuntime(
        id: 'runtime:user-1',
        userId: 'user-1',
        activeTaskId: runningTask.id,
        sessionId: runningSession.id,
        state: 'running',
        segmentStartedAt: resumedAt,
        accumulatedActiveMs: accumulatedMs,
        accumulatedPausedMs: resumedAt.difference(firstPause).inMilliseconds,
        dataJson: jsonEncode({'focus_interval_active_base_ms': 0}),
        revision: 1,
        updatedAt: now,
      ),
    );

    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
      now: now,
    );

    expect(facts.productiveMs, const Duration(minutes: 25).inMilliseconds);
    expect(facts.focusMs, facts.productiveMs);
  });

  test('a paused Pomodoro adds no paused wall time to productive work', () {
    final sessionStart = DateTime.utc(2026, 7, 10, 8);
    final pausedAt = sessionStart.add(const Duration(minutes: 10));
    final now = pausedAt.add(const Duration(hours: 14));
    final accumulatedMs = const Duration(minutes: 10).inMilliseconds;
    final pausedTask = task(
      id: 'paused-pomodoro',
      mode: 'pomodoro',
      status: 'paused',
      actualStart: sessionStart,
    );
    final pausedSession = LocalEntityRecord(
      id: 'paused-session',
      userId: 'user-1',
      entityType: 'execution_sessions',
      parentId: pausedTask.id,
      title: 'Session',
      status: 'paused',
      position: 0,
      dataJson: jsonEncode({
        'task_occurrence_id': pausedTask.id,
        'started_at': sessionStart.toIso8601String(),
        'finished_at': null,
        'active_segment_started_at': null,
        'accumulated_active_ms': accumulatedMs,
        'state': 'paused',
      }),
      revision: 1,
      createdAt: sessionStart,
      updatedAt: pausedAt,
    );
    final data = snapshot(
      tasks: [pausedTask],
      sessions: [pausedSession],
      events: [
        event(
          id: 'paused-start',
          sessionId: pausedSession.id,
          type: 'start',
          at: sessionStart,
        ),
        event(
          id: 'paused-boundary',
          sessionId: pausedSession.id,
          type: 'pause',
          at: pausedAt,
          durationMs: accumulatedMs,
        ),
      ],
      runtime: LocalRuntime(
        id: 'runtime:user-1',
        userId: 'user-1',
        activeTaskId: pausedTask.id,
        sessionId: pausedSession.id,
        state: 'paused',
        segmentStartedAt: pausedAt,
        accumulatedActiveMs: accumulatedMs,
        accumulatedPausedMs: now.difference(pausedAt).inMilliseconds,
        dataJson: jsonEncode({'focus_interval_active_base_ms': 0}),
        revision: 1,
        updatedAt: now,
      ),
    );

    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
      now: now,
    );

    expect(facts.productiveMs, accumulatedMs);
    expect(facts.focusMs, accumulatedMs);
  });

  test('keeps uncapped live elapsed time for a continuous timer', () {
    final now = DateTime.utc(2026, 7, 10, 15);
    final start = now.subtract(const Duration(hours: 4));
    final runningTask = task(
      id: 'running-continuous',
      mode: 'continuous',
      status: 'running',
      actualStart: start,
    );
    final runningSession = LocalEntityRecord(
      id: 'running-continuous-session',
      userId: 'user-1',
      entityType: 'execution_sessions',
      parentId: runningTask.id,
      title: 'Session',
      status: 'running',
      position: 0,
      dataJson: jsonEncode({
        'task_occurrence_id': runningTask.id,
        'started_at': start.toIso8601String(),
        'finished_at': null,
        'active_segment_started_at': start.toIso8601String(),
        'accumulated_active_ms': 0,
        'state': 'running',
      }),
      revision: 1,
      createdAt: start,
      updatedAt: start,
    );
    final data = snapshot(
      tasks: [runningTask],
      sessions: [runningSession],
      runtime: LocalRuntime(
        id: 'runtime:user-1',
        userId: 'user-1',
        activeTaskId: runningTask.id,
        sessionId: runningSession.id,
        state: 'running',
        segmentStartedAt: start,
        accumulatedActiveMs: 0,
        accumulatedPausedMs: 0,
        dataJson: '{}',
        revision: 1,
        updatedAt: now,
      ),
    );

    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
      now: now,
    );

    expect(facts.productiveMs, const Duration(hours: 4).inMilliseconds);
    expect(facts.continuousMs, facts.productiveMs);
  });

  test(
    'splits a recorded interval at midnight and never reports over 24 elapsed hours',
    () {
      final start = DateTime.utc(2026, 7, 1, 0);
      final end = DateTime.utc(2026, 7, 2, 6);
      final data = snapshot(
        tasks: [
          task(
            id: 'long-session',
            actualStart: start,
            actualFinish: end,
            activeMs: const Duration(hours: 30).inMilliseconds,
          ),
        ],
      );

      final facts = PerformanceReportService.factsForSnapshot(
        data,
        options(to: DateTime(2026, 7, 2)),
        l10n,
      );

      expect(facts.productiveMs, const Duration(hours: 30).inMilliseconds);
      expect(
        facts.daily
            .singleWhere((item) => item.day == DateTime(2026, 7, 1))
            .productiveMs,
        const Duration(hours: 24).inMilliseconds,
      );
      expect(
        facts.daily
            .singleWhere((item) => item.day == DateTime(2026, 7, 2))
            .productiveMs,
        const Duration(hours: 6).inMilliseconds,
      );
      expect(
        facts.daily.every(
          (item) =>
              item.productiveMs <= const Duration(hours: 24).inMilliseconds,
        ),
        isTrue,
      );
    },
  );

  test(
    'planned report totals use each day interval union and exclude outside dates',
    () {
      final data = snapshot(
        tasks: [
          task(
            id: 'day-1-work',
            scheduledDate: DateTime.utc(2026, 7, 10),
            plannedStart: DateTime.utc(2026, 7, 10, 0, 9),
            plannedEnd: DateTime.utc(2026, 7, 10, 17, 30),
            estimate: const Duration(hours: 17, minutes: 21),
          ),
          task(
            id: 'day-1-nested-study',
            scheduledDate: DateTime.utc(2026, 7, 10),
            plannedStart: DateTime.utc(2026, 7, 10, 6, 30),
            plannedEnd: DateTime.utc(2026, 7, 10, 7, 10),
            estimate: const Duration(minutes: 40),
          ),
          task(
            id: 'day-2-long',
            scheduledDate: DateTime.utc(2026, 7, 11),
            plannedStart: DateTime.utc(2026, 7, 11),
            plannedEnd: DateTime.utc(2026, 7, 12, 6),
            estimate: const Duration(hours: 30),
          ),
          task(
            id: 'outside-range',
            scheduledDate: DateTime.utc(2026, 7, 12),
            plannedStart: DateTime.utc(2026, 7, 12, 8),
            plannedEnd: DateTime.utc(2026, 7, 12, 9),
          ),
        ],
      );

      final facts = PerformanceReportService.factsForSnapshot(
        data,
        options(from: DateTime(2026, 7, 10), to: DateTime(2026, 7, 11)),
        l10n,
      );
      final byDay = {for (final point in facts.daily) point.day: point};

      expect(
        byDay[DateTime(2026, 7, 10)]!.plannedMs,
        const Duration(hours: 17, minutes: 21).inMilliseconds,
      );
      expect(
        byDay[DateTime(2026, 7, 11)]!.plannedMs,
        const Duration(hours: 24).inMilliseconds,
      );
      expect(
        facts.daily.every(
          (point) =>
              point.plannedMs <= const Duration(hours: 24).inMilliseconds,
        ),
        isTrue,
      );
      expect(
        facts.plannedMs,
        facts.daily.fold<int>(0, (sum, point) => sum + point.plannedMs),
      );
      expect(
        facts.plannedMs,
        const Duration(hours: 41, minutes: 21).inMilliseconds,
      );
    },
  );

  test(
    'deduplicates overlapping device activity and normalizes visible names',
    () {
      final ten = DateTime.utc(2026, 7, 12, 10);
      final data = snapshot(
        tasks: const [],
        activity: [
          activity(
            id: 'android-duolingo',
            start: ten,
            end: ten.add(const Duration(minutes: 30)),
            processName: 'com.duolingo',
          ),
          activity(
            id: 'windows-browser',
            start: ten.add(const Duration(minutes: 10)),
            end: ten.add(const Duration(minutes: 40)),
            deviceId: 'device-2',
            processName: 'chrome.exe',
            url:
                'https://www.freecodecamp.org/learn/javascript-v9/lesson/example',
          ),
          activity(
            id: 'idle-copy',
            start: ten.add(const Duration(minutes: 20)),
            end: ten.add(const Duration(minutes: 30)),
            deviceId: 'device-3',
            processName: 'pro.taskmanager.com',
            idleState: 'idle',
          ),
          activity(
            id: 'code',
            start: ten.add(const Duration(minutes: 40)),
            end: ten.add(const Duration(minutes: 50)),
            deviceId: 'device-2',
            processName: 'Code.exe',
          ),
        ],
      );

      final facts = PerformanceReportService.factsForSnapshot(
        data,
        options(),
        l10n,
      );
      final labels = [
        ...facts.applications.map((entry) => entry.label),
        ...facts.websites.map((entry) => entry.label),
      ];

      expect(
        facts.activeActivityMs,
        const Duration(minutes: 50).inMilliseconds,
      );
      expect(facts.idleActivityMs, 0);
      expect(
        facts.applications.fold<int>(
              0,
              (sum, entry) => sum + entry.durationMs,
            ) +
            facts.websites.fold<int>(0, (sum, entry) => sum + entry.durationMs),
        facts.activeActivityMs,
      );
      expect(
        labels,
        containsAll(['Duolingo', 'Visual Studio Code', 'freecodecamp.org']),
      );
      expect(labels.join(' '), isNot(contains('com.duolingo')));
      expect(labels.join(' '), isNot(contains('Code.exe')));
      expect(labels.join(' '), isNot(contains('freecodecamp.org/learn')));
    },
  );

  test('excludes TaskMaster and latest System decisions from reports', () {
    final ten = DateTime.utc(2026, 7, 13, 10);
    final systemStart = ten.add(const Duration(minutes: 10));
    final data = snapshot(
      tasks: const [],
      activity: [
        activity(
          id: 'useful',
          start: ten,
          end: ten.add(const Duration(minutes: 10)),
          processName: 'Code.exe',
        ),
        activity(
          id: 'system',
          start: systemStart,
          end: systemStart.add(const Duration(minutes: 10)),
          processName: 'SearchHost.exe',
        ),
        activity(
          id: 'self',
          start: ten.add(const Duration(minutes: 20)),
          end: ten.add(const Duration(minutes: 30)),
          processName: 'taskmaster_pro.exe',
        ),
      ],
      attributions: [
        attribution(
          segmentId: 'system',
          classification: 'supporting_work',
          at: systemStart,
        ),
        attribution(
          segmentId: 'system',
          classification: 'system_activity',
          revision: 2,
          at: systemStart.add(const Duration(seconds: 1)),
        ),
      ],
    );

    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
    );

    expect(facts.activeActivityMs, const Duration(minutes: 10).inMilliseconds);
    expect(facts.applications.map((entry) => entry.label), [
      'Visual Studio Code',
    ]);
  });

  test('groups recurring occurrences and preserves union-allocated work', () {
    final ten = DateTime.utc(2026, 7, 14, 10);
    final occurrences = [
      task(
        id: 'lesson-1',
        templateId: 'lesson-template',
        actualStart: ten,
        actualFinish: ten.add(const Duration(minutes: 20)),
        activeMs: const Duration(minutes: 20).inMilliseconds,
      ),
      task(id: 'lesson-2', templateId: 'lesson-template', status: 'missed'),
      task(id: 'lesson-3', templateId: 'lesson-template', status: 'scheduled'),
    ];
    final data = snapshot(tasks: occurrences);
    final facts = PerformanceReportService.factsForSnapshot(
      data,
      options(),
      l10n,
      now: DateTime.utc(2026, 7, 14, 12),
    );

    final group = PerformanceReportService.taskGroupsForReport(
      occurrences,
      facts,
      now: DateTime.utc(2026, 7, 14, 12),
    ).single;

    expect(group.recurring, isTrue);
    expect(group.occurrences, 3);
    expect(group.completed, 1);
    expect(group.missed, 1);
    expect(group.upcoming, 1);
    expect(
      group.plannedMs,
      const Duration(hours: 3).inMilliseconds,
      reason: 'Per-template occurrence effort remains intentionally additive.',
    );
    expect(group.recordedMs, const Duration(minutes: 20).inMilliseconds);
  });
}
