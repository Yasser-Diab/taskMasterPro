import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/reports/data/performance_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders English, Arabic, and German performance reports', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final service = PerformanceReportService(database);
    final now = DateTime(2026, 7, 26, 14, 30);
    final profile = LocalProfile(
      id: 'profile-1',
      userId: 'user-1',
      displayName: 'Y. A. Diab',
      onboardingCompleted: true,
      revision: 1,
      createdAt: now.subtract(const Duration(days: 120)),
      updatedAt: now,
    );
    final roadmap = LocalRoadmap(
      id: 'roadmap-1',
      userId: 'user-1',
      title: 'Flutter Application Development',
      description: 'Build and release DayVector',
      status: 'active',
      plannedStart: now.subtract(const Duration(days: 60)),
      originalTargetDate: DateTime(2026, 10, 12),
      forecastTargetDate: DateTime(2026, 10, 16),
      finalOutcome: 'Release a reliable Windows and Android application',
      progress: 0.68,
      requiredEffortMs: const Duration(hours: 160).inMilliseconds,
      completedEffortMs: const Duration(hours: 109).inMilliseconds,
      riskLevel: 'medium',
      forecastConfidence: 'medium',
      revision: 4,
      createdAt: now.subtract(const Duration(days: 60)),
      updatedAt: now,
    );
    LocalTask task({
      required String id,
      required String title,
      required String status,
      required int plannedMinutes,
      required int activeMinutes,
      required double progress,
    }) {
      return LocalTask(
        id: id,
        userId: 'user-1',
        title: title,
        description: '',
        status: status,
        priority: 2,
        executionMode: 'continuous',
        scheduledDate: now,
        plannedStart: now.subtract(const Duration(hours: 2)),
        dueAt: now.add(const Duration(days: 1)),
        estimatedDurationMs: Duration(minutes: plannedMinutes).inMilliseconds,
        actualStart: now.subtract(const Duration(hours: 2, minutes: 12)),
        activeDurationMs: Duration(minutes: activeMinutes).inMilliseconds,
        pausedDurationMs: const Duration(minutes: 8).inMilliseconds,
        idleDurationMs: const Duration(minutes: 5).inMilliseconds,
        progress: progress,
        roadmapId: roadmap.id,
        dataJson: '{}',
        revision: 2,
        createdAt: now.subtract(const Duration(days: 4)),
        updatedAt: now,
      );
    }

    final snapshot = PerformanceReportSnapshot(
      profile: profile,
      roadmap: roadmap,
      tasks: [
        task(
          id: 'task-1',
          title: 'Build synchronization engine',
          status: 'completed',
          plannedMinutes: 120,
          activeMinutes: 138,
          progress: 1,
        ),
        task(
          id: 'task-2',
          title: 'German language practice',
          status: 'running',
          plannedMinutes: 30,
          activeMinutes: 24,
          progress: 0.8,
        ),
        task(
          id: 'task-3',
          title: 'Review client quotation',
          status: 'overdue',
          plannedMinutes: 45,
          activeMinutes: 18,
          progress: 0.4,
        ),
        task(
          id: 'task-4',
          title: 'قراءة مواصفات المشروع',
          status: 'scheduled',
          plannedMinutes: 60,
          activeMinutes: 12,
          progress: 0.2,
        ),
      ],
      phases: const [],
      milestones: const [],
      checkpoints: const [],
      activity: const [],
      contributions: const [],
      insights: const [],
      health: [
        LocalEntityRecord(
          id: 'health-steps-1',
          userId: 'user-1',
          entityType: 'health_summaries',
          title: 'steps',
          status: 'recorded',
          position: 0,
          dataJson:
              '{"summary_date":"2026-07-26","summary_type":"steps",'
              '"value":7421,"unit":"count",'
              '"record_count":1,'
              '"source_applications":["Huawei Health"],'
              '"last_updated_at":"2026-07-26T12:30:00Z"}',
          revision: 1,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final output = Directory('tmp/pdfs')..createSync(recursive: true);
    for (final localeCode in const ['en', 'ar', 'de']) {
      final options = PerformanceReportOptions(
        type: PerformanceReportType.roadmap,
        roadmapId: roadmap.id,
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 7, 26),
        localeCode: localeCode,
        landscape: localeCode == 'de',
        includeHealth: true,
        sections: const {
          'summary',
          'roadmaps',
          'tasks',
          'activity',
          'coaching',
          'health',
        },
      );
      final bytes = await service.buildPdf(snapshot, options);
      final file = File('${output.path}/performance-report-$localeCode.pdf');
      await file.writeAsBytes(bytes, flush: true);
      expect(bytes.length, greaterThan(10000));
    }
  });
}
