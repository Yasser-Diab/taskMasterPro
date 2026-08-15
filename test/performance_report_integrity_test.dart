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
    dataJson: '{}',
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
