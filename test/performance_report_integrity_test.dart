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
    DateTime? actualStart,
    DateTime? actualFinish,
    int activeMs = 0,
  }) => LocalTask(
    id: id,
    userId: 'user-1',
    title: id,
    description: '',
    status: actualFinish == null ? 'running' : 'completed',
    priority: 2,
    executionMode: mode,
    scheduledDate: actualStart,
    estimatedDurationMs: const Duration(hours: 1).inMilliseconds,
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
  }) => PerformanceReportSnapshot(
    profile: null,
    roadmap: null,
    tasks: tasks,
    phases: const [],
    milestones: const [],
    checkpoints: const [],
    activity: activity,
    contributions: const [],
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
}
