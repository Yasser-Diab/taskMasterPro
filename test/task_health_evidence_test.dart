import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/health/presentation/task_health_evidence_strip.dart';

void main() {
  test(
    'task health evidence deduplicates sessions and aggregates compactly',
    () {
      final now = DateTime.utc(2026, 7, 28, 12);

      LocalEntityRecord record({
        required String id,
        required String sessionId,
        required String metric,
        required num value,
        required int count,
        bool estimated = false,
        Duration age = Duration.zero,
      }) {
        final updatedAt = now.subtract(age);
        return LocalEntityRecord(
          id: id,
          userId: 'user-1',
          entityType: 'task_health_summaries',
          parentId: 'task-1',
          secondaryParentId: sessionId,
          title: metric,
          status: 'recorded',
          position: 0,
          dataJson: jsonEncode({
            'task_occurrence_id': 'task-1',
            'execution_session_id': sessionId,
            'metric_type': metric,
            'value': value,
            'record_count': count,
            'source_applications': ['Huawei Health'],
            'estimated': estimated,
            'last_updated_at': updatedAt.toIso8601String(),
          }),
          revision: 1,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        );
      }

      final summary = TaskHealthEvidenceSummary.fromRecords([
        record(
          id: 'old-steps',
          sessionId: 'session-1',
          metric: 'steps',
          value: 500,
          count: 1,
          age: const Duration(minutes: 5),
        ),
        record(
          id: 'new-steps',
          sessionId: 'session-1',
          metric: 'steps',
          value: 600,
          count: 1,
        ),
        record(
          id: 'other-steps',
          sessionId: 'session-2',
          metric: 'steps',
          value: 400,
          count: 1,
        ),
        record(
          id: 'distance',
          sessionId: 'session-1',
          metric: 'distance',
          value: 1300,
          count: 1,
          estimated: true,
        ),
        record(
          id: 'heart-1',
          sessionId: 'session-1',
          metric: 'average_heart_rate',
          value: 80,
          count: 2,
        ),
        record(
          id: 'heart-2',
          sessionId: 'session-2',
          metric: 'average_heart_rate',
          value: 100,
          count: 1,
        ),
        record(
          id: 'energy',
          sessionId: 'session-1',
          metric: 'active_calories',
          value: 55,
          count: 2,
        ),
        record(
          id: 'empty',
          sessionId: 'session-1',
          metric: 'distance',
          value: 0,
          count: 0,
        ),
      ]);

      expect(summary.steps, 1000);
      expect(summary.distanceMeters, 1300);
      expect(summary.averageHeartRate, closeTo(86.666, .01));
      expect(summary.activeCalories, 55);
      expect(summary.sources, {'Huawei Health'});
      expect(summary.hasEstimatedValues, isTrue);
      expect(summary.hasData, isTrue);
    },
  );
}
