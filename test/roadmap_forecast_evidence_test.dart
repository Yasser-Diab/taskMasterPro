import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/roadmaps/data/roadmap_repository.dart';
import 'package:taskmaster_pro/features/roadmaps/presentation/roadmaps_screen.dart';

void main() {
  LocalRoadmap roadmap({int? requiredEffortMs}) => LocalRoadmap(
    id: 'roadmap-1',
    userId: 'user-1',
    title: 'English Professional Fluency',
    description: '',
    status: 'active',
    finalOutcome: '',
    progress: 0,
    requiredEffortMs: requiredEffortMs,
    completedEffortMs: const Duration(minutes: 14).inMilliseconds,
    riskLevel: 'low',
    forecastConfidence: 'insufficient',
    revision: 1,
    createdAt: DateTime.utc(2026, 8, 10),
    updatedAt: DateTime.utc(2026, 8, 10),
  );

  LocalTask task({
    required String id,
    Duration estimate = Duration.zero,
    DateTime? start,
    DateTime? end,
    DateTime? deletedAt,
  }) => LocalTask(
    id: id,
    userId: 'user-1',
    title: id,
    description: '',
    status: 'scheduled',
    priority: 2,
    executionMode: 'manual',
    scheduledDate: DateTime.utc(2026, 8, 10),
    plannedStart: start,
    plannedEnd: end,
    estimatedDurationMs: estimate.inMilliseconds,
    activeDurationMs: 0,
    pausedDurationMs: 0,
    idleDurationMs: 0,
    progress: 0,
    roadmapId: 'roadmap-1',
    dataJson: '{}',
    revision: 1,
    createdAt: DateTime.utc(2026, 8, 10),
    updatedAt: DateTime.utc(2026, 8, 10),
    deletedAt: deletedAt,
  );

  test('29 imported linked tasks repair a zero legacy denominator', () {
    final tasks = [
      for (var index = 0; index < 29; index++)
        task(id: 'english-$index', estimate: const Duration(minutes: 45)),
    ];

    expect(
      effectiveRoadmapRequiredEffortMs(roadmap(requiredEffortMs: 0), tasks),
      const Duration(hours: 21, minutes: 45).inMilliseconds,
    );
  });

  test('canonical planning window wins over a stale zero estimate', () {
    final tasks = [
      task(
        id: 'scheduled-task',
        start: DateTime.utc(2026, 8, 10, 9, 30),
        end: DateTime.utc(2026, 8, 10, 10, 30),
      ),
    ];

    expect(
      effectiveRoadmapRequiredEffortMs(roadmap(), tasks),
      const Duration(hours: 1).inMilliseconds,
    );
  });

  test('no canonical linked task effort remains unavailable', () {
    expect(
      effectiveRoadmapRequiredEffortMs(roadmap(), [
        task(id: 'legacy-zero'),
        task(id: 'deleted', deletedAt: DateTime.utc(2026, 8, 11)),
      ]),
      isNull,
    );
  });

  test('unknown planned effort never renders a zero-second denominator', () {
    final summary = roadmapEffortSummary(
      const AppLocalizations(Locale('en')),
      recordedEffortMs: const Duration(minutes: 14).inMilliseconds,
      requiredEffortMs: null,
    );

    expect(summary, '14 min recorded · planned effort unavailable');
    expect(summary, isNot(contains('0 sec planned')));
  });

  test('a new roadmap does not manufacture a forecast from structure', () {
    final projection = projectRoadmapForecast(
      requiredEffortMs: const Duration(hours: 100).inMilliseconds,
      completedEffortMs: const Duration(hours: 1).inMilliseconds,
      completedTaskCount: 1,
      observations: [
        RoadmapForecastObservation(
          day: DateTime.utc(2026, 8, 10),
          effortMs: const Duration(hours: 1).inMilliseconds,
        ),
      ],
      now: DateTime.utc(2026, 8, 10),
    );

    expect(projection.confidence, 'insufficient');
    expect(projection.forecast, isNull);
  });

  test('one abnormal day cannot claim high confidence or move years', () {
    final projection = projectRoadmapForecast(
      requiredEffortMs: const Duration(hours: 100).inMilliseconds,
      completedEffortMs: const Duration(hours: 5).inMilliseconds,
      completedTaskCount: 2,
      observations: [
        RoadmapForecastObservation(
          day: DateTime.utc(2026, 8, 7),
          effortMs: const Duration(hours: 1).inMilliseconds,
        ),
        RoadmapForecastObservation(
          day: DateTime.utc(2026, 8, 8),
          effortMs: const Duration(hours: 1).inMilliseconds,
        ),
        RoadmapForecastObservation(
          day: DateTime.utc(2026, 8, 9),
          effortMs: const Duration(hours: 12).inMilliseconds,
        ),
      ],
      now: DateTime.utc(2026, 8, 10),
      previousForecast: DateTime.utc(2028, 8, 10),
    );

    expect(projection.confidence, 'low');
    expect(projection.forecast, DateTime.utc(2028, 7, 20));
    expect(
      projection.observedEffortMs,
      const Duration(hours: 5).inMilliseconds,
    );
  });

  test('stable multi-day evidence can earn a high-confidence forecast', () {
    final projection = projectRoadmapForecast(
      requiredEffortMs: const Duration(hours: 100).inMilliseconds,
      completedEffortMs: const Duration(hours: 40).inMilliseconds,
      completedTaskCount: 10,
      observations: [
        for (var index = 0; index < 20; index++)
          RoadmapForecastObservation(
            day: DateTime.utc(2026, 7, 1).add(Duration(days: index)),
            effortMs: const Duration(hours: 2).inMilliseconds,
          ),
      ],
      now: DateTime.utc(2026, 8, 10),
    );

    expect(projection.confidence, 'high');
    expect(projection.forecast, DateTime.utc(2026, 9, 9));
    expect(projection.rangeStart, isNotNull);
    expect(projection.rangeEnd, isNotNull);
  });

  test('stored forecast is presented as a confidence-bounded range', () {
    final roadmap = LocalRoadmap(
      id: 'roadmap-1',
      userId: 'user-1',
      title: 'Study',
      description: '',
      status: 'active',
      forecastTargetDate: DateTime.utc(2028, 6, 18),
      finalOutcome: '',
      progress: 0.2,
      completedEffortMs: 1,
      riskLevel: 'low',
      forecastConfidence: 'low',
      revision: 1,
      createdAt: DateTime.utc(2026, 8, 10),
      updatedAt: DateTime.utc(2026, 8, 10),
    );

    final range = storedRoadmapForecastRange(roadmap)!;
    expect(range.start, DateTime.utc(2028, 5, 21));
    expect(range.end, DateTime.utc(2028, 7, 16));
  });
}
