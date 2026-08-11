import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/reports/data/performance_report_service.dart';

void main() {
  final now = DateTime(2026, 7, 20, 9);

  LocalTask task({
    required String id,
    required String dataJson,
    String? roadmapId,
    DateTime? scheduledDate,
  }) {
    return LocalTask(
      id: id,
      userId: 'user-1',
      title: id,
      description: '',
      status: 'ready',
      priority: 2,
      executionMode: 'continuous',
      scheduledDate: scheduledDate ?? now,
      estimatedDurationMs: const Duration(hours: 1).inMilliseconds,
      activeDurationMs: 0,
      pausedDurationMs: 0,
      idleDurationMs: 0,
      progress: 0,
      roadmapId: roadmapId,
      dataJson: dataJson,
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
  }

  PerformanceReportOptions options(
    PerformanceReportType type, {
    String? taskId,
    String? roadmapId,
    Set<String> sections = const {'summary'},
    bool includeHealth = false,
  }) {
    return PerformanceReportOptions(
      type: type,
      taskId: taskId,
      roadmapId: roadmapId,
      from: DateTime(2026, 7, 1),
      to: DateTime(2026, 7, 31),
      localeCode: 'en',
      landscape: false,
      sections: sections,
      includeHealth: includeHealth,
    );
  }

  test('scopes account, task, household, and roadmap reports', () {
    final tasks = [
      task(
        id: 'personal',
        dataJson: '{"scope":"personal"}',
        roadmapId: 'roadmap-a',
      ),
      task(
        id: 'household',
        dataJson: '{"scope":"household"}',
        roadmapId: 'roadmap-a',
      ),
      task(
        id: 'shared-household',
        dataJson: '{"type":"shared_household"}',
        roadmapId: 'roadmap-b',
      ),
      task(id: 'malformed', dataJson: '{not-json', roadmapId: 'roadmap-b'),
      task(
        id: 'outside-range',
        dataJson: '{"scope":"household"}',
        roadmapId: 'roadmap-a',
        scheduledDate: DateTime(2026, 8, 1),
      ),
    ];

    expect(
      PerformanceReportService.tasksForReport(
        tasks,
        options(PerformanceReportType.account),
      ).map((item) => item.id),
      unorderedEquals([
        'personal',
        'household',
        'shared-household',
        'malformed',
      ]),
    );
    expect(
      PerformanceReportService.tasksForReport(
        tasks,
        options(PerformanceReportType.task, taskId: 'shared-household'),
      ).map((item) => item.id),
      ['shared-household'],
    );
    expect(
      PerformanceReportService.tasksForReport(
        tasks,
        options(PerformanceReportType.household),
      ).map((item) => item.id),
      unorderedEquals(['household', 'shared-household']),
    );
    expect(
      PerformanceReportService.tasksForReport(
        tasks,
        options(PerformanceReportType.roadmap, roadmapId: 'roadmap-a'),
      ).map((item) => item.id),
      unorderedEquals(['personal', 'household']),
    );
  });

  test('linked roadmaps resolve to names and never fall back to UUIDs', () {
    final roadmap = LocalRoadmap(
      id: '776d234e-3b03-4a7d-a91d-121212121212',
      userId: 'user-1',
      title: 'Full-Stack Development',
      description: '',
      status: 'active',
      finalOutcome: '',
      progress: 0,
      completedEffortMs: 0,
      riskLevel: 'low',
      forecastConfidence: 'low',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    final labels = PerformanceReportService.linkedRoadmapLabels(
      [
        task(id: 'linked', dataJson: '{}', roadmapId: roadmap.id),
        task(
          id: 'removed',
          dataJson: '{}',
          roadmapId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        ),
      ],
      [roadmap],
      const AppLocalizations(Locale('en')),
    );

    expect(labels, ['Full-Stack Development', 'Roadmap no longer available']);
    expect(labels.join(' '), isNot(contains('776d234e')));
    expect(labels.join(' '), isNot(contains('aaaaaaaa')));
  });

  test('health summaries are explicit, date-bounded, and deduplicated', () {
    LocalEntityRecord health({
      required String id,
      required String type,
      required String date,
      required Object value,
      required DateTime updatedAt,
      Object? sources = const ['Huawei Health'],
    }) {
      return LocalEntityRecord(
        id: id,
        userId: 'user-1',
        entityType: 'health_summaries',
        title: type,
        status: 'recorded',
        position: 0,
        dataJson: jsonEncode({
          'summary_date': date,
          'summary_type': type,
          'value': value,
          'unit': type == 'distance' ? 'm' : 'count',
          'record_count': 1,
          'source_applications': sources,
          'last_updated_at': updatedAt.toUtc().toIso8601String(),
        }),
        revision: 1,
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );
    }

    final records = [
      health(
        id: 'steps-old',
        type: 'steps',
        date: '2026-07-01',
        value: 1200,
        updatedAt: DateTime.utc(2026, 7, 1, 10),
      ),
      health(
        id: 'steps-latest',
        type: 'steps',
        date: '2026-07-01',
        value: 1800,
        updatedAt: DateTime.utc(2026, 7, 1, 12),
        sources: const ['Huawei Health', 'Health Connect'],
      ),
      health(
        id: 'distance',
        type: 'distance',
        date: '2026-07-31',
        value: '4250.5',
        updatedAt: DateTime.utc(2026, 7, 31, 19),
      ),
      health(
        id: 'outside',
        type: 'active_calories',
        date: '2026-08-01',
        value: 450,
        updatedAt: DateTime.utc(2026, 8, 1, 9),
      ),
      health(
        id: 'unknown',
        type: 'raw_metric_key',
        date: '2026-07-20',
        value: 3,
        updatedAt: DateTime.utc(2026, 7, 20, 9),
      ),
    ];

    expect(
      PerformanceReportService.healthSummariesForReport(
        records,
        options(PerformanceReportType.account, sections: const {'health'}),
      ),
      isEmpty,
    );

    final summaries = PerformanceReportService.healthSummariesForReport(
      records,
      options(
        PerformanceReportType.household,
        sections: const {'health'},
        includeHealth: true,
      ),
    );

    expect(summaries.map((item) => item.metricType), ['distance', 'steps']);
    final steps = summaries.singleWhere((item) => item.metricType == 'steps');
    expect(steps.value, 1800);
    expect(steps.sources, ['Huawei Health', 'Health Connect']);
    expect(steps.lastUpdatedAt, DateTime.utc(2026, 7, 1, 12));
  });

  test('task health summaries aggregate sessions without daily totals', () {
    LocalEntityRecord taskHealth({
      required String id,
      required String taskId,
      required String sessionId,
      required String metric,
      required num value,
      required int recordCount,
      required DateTime updatedAt,
      bool estimated = false,
    }) {
      return LocalEntityRecord(
        id: id,
        userId: 'user-1',
        entityType: 'task_health_summaries',
        parentId: taskId,
        secondaryParentId: sessionId,
        title: metric,
        status: 'recorded',
        position: 0,
        dataJson: jsonEncode({
          'summary_date': '2026-07-20',
          'metric_type': metric,
          'summary_type': metric,
          'value': value,
          'unit': metric == 'average_heart_rate' ? 'bpm' : 'count',
          'record_count': recordCount,
          'source_applications': ['Huawei Health'],
          'last_updated_at': updatedAt.toUtc().toIso8601String(),
          'estimated': estimated,
          'provenance': estimated
              ? 'steps_height_stride_estimate'
              : 'health_connect_record_overlap',
        }),
        revision: 1,
        createdAt: updatedAt,
        updatedAt: updatedAt,
      );
    }

    final records = [
      taskHealth(
        id: 'task-a-steps-1',
        taskId: 'task-a',
        sessionId: 'session-1',
        metric: 'steps',
        value: 400,
        recordCount: 1,
        updatedAt: DateTime.utc(2026, 7, 20, 10),
      ),
      taskHealth(
        id: 'task-a-steps-2',
        taskId: 'task-a',
        sessionId: 'session-2',
        metric: 'steps',
        value: 600,
        recordCount: 2,
        updatedAt: DateTime.utc(2026, 7, 20, 12),
      ),
      taskHealth(
        id: 'task-a-heart-1',
        taskId: 'task-a',
        sessionId: 'session-1',
        metric: 'average_heart_rate',
        value: 80,
        recordCount: 2,
        updatedAt: DateTime.utc(2026, 7, 20, 10),
      ),
      taskHealth(
        id: 'task-a-heart-2',
        taskId: 'task-a',
        sessionId: 'session-2',
        metric: 'average_heart_rate',
        value: 100,
        recordCount: 1,
        updatedAt: DateTime.utc(2026, 7, 20, 12),
      ),
      taskHealth(
        id: 'task-b-steps',
        taskId: 'task-b',
        sessionId: 'session-3',
        metric: 'steps',
        value: 9000,
        recordCount: 4,
        updatedAt: DateTime.utc(2026, 7, 20, 13),
      ),
      LocalEntityRecord(
        id: 'daily-total',
        userId: 'user-1',
        entityType: 'health_summaries',
        title: 'steps',
        status: 'recorded',
        position: 0,
        dataJson: jsonEncode({
          'summary_date': '2026-07-20',
          'summary_type': 'steps',
          'value': 20000,
          'unit': 'count',
          'record_count': 1,
          'source_applications': ['Huawei Health'],
          'last_updated_at': '2026-07-20T20:00:00Z',
        }),
        revision: 1,
        createdAt: DateTime.utc(2026, 7, 20, 20),
        updatedAt: DateTime.utc(2026, 7, 20, 20),
      ),
    ];

    final summaries = PerformanceReportService.healthSummariesForReport(
      records,
      options(
        PerformanceReportType.task,
        taskId: 'task-a',
        sections: const {'health'},
        includeHealth: true,
      ),
    );
    final steps = summaries.singleWhere(
      (summary) => summary.metricType == 'steps',
    );
    final heartRate = summaries.singleWhere(
      (summary) => summary.metricType == 'average_heart_rate',
    );

    expect(steps.value, 1000);
    expect(steps.recordCount, 3);
    expect(heartRate.value, closeTo(86.666, 0.01));
    expect(heartRate.recordCount, 3);
    expect(summaries.map((summary) => summary.metricType), [
      'steps',
      'average_heart_rate',
    ]);
  });
}
