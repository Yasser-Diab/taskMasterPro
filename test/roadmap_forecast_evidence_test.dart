import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/roadmaps/data/roadmap_repository.dart';

void main() {
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
}
