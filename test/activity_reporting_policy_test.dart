import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/activity/domain/activity_reporting_policy.dart';

void main() {
  final start = DateTime.utc(2026, 8, 15, 9);

  LocalActivitySegment segment(String id, String processName) =>
      LocalActivitySegment(
        id: id,
        userId: 'user',
        deviceId: 'device',
        deviceEventId: id,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 5)),
        sourceType: 'windows_foreground',
        processName: processName,
        rawMetadataJson: '{}',
        revision: 1,
        createdAt: start,
        updatedAt: start,
      );

  LocalAttribution attribution({
    required String id,
    required String segmentId,
    required String classification,
    required DateTime updatedAt,
    int revision = 1,
  }) => LocalAttribution(
    id: id,
    userId: 'user',
    activitySegmentId: segmentId,
    targetType: 'unassigned_activity',
    classification: classification,
    confidence: 1,
    attributionStatus: 'confirmed',
    confirmedByUser: true,
    revision: revision,
    createdAt: start,
    updatedAt: updatedAt,
  );

  test('TaskMaster identities are never reportable', () {
    final rows = [
      segment('windows', r'C:\Program Files\TaskMaster\taskmaster_pro.exe'),
      segment('android', 'pro.taskmaster.app'),
      segment('useful', 'Code.exe'),
    ];

    expect(
      reportableActivitySegments(segments: rows, attributions: const []),
      hasLength(1),
    );
    expect(
      reportableActivitySegments(
        segments: rows,
        attributions: const [],
      ).single.id,
      'useful',
    );
  });

  test('latest System decision overrides stale useful attribution', () {
    final row = segment('search', 'SearchHost.exe');
    final rows = [
      attribution(
        id: 'old',
        segmentId: row.id,
        classification: 'supporting_work',
        updatedAt: start,
      ),
      attribution(
        id: 'new',
        segmentId: row.id,
        classification: 'system_activity',
        revision: 2,
        updatedAt: start.add(const Duration(seconds: 1)),
      ),
    ];

    expect(excludedActivitySegmentIds(segments: [row], attributions: rows), {
      'search',
    });
    expect(
      reportableActivitySegments(segments: [row], attributions: rows),
      isEmpty,
    );
  });

  test('canonical attribution revision wins despite device clock skew', () {
    final row = segment('clock-skew', 'Code.exe');
    final rows = [
      attribution(
        id: 'stale-future-clock',
        segmentId: row.id,
        classification: 'supporting_work',
        revision: 4,
        updatedAt: DateTime.utc(2035),
      ),
      attribution(
        id: 'canonical-system-decision',
        segmentId: row.id,
        classification: 'system_activity',
        revision: 5,
        updatedAt: DateTime.utc(2026),
      ),
    ];

    expect(
      latestActivityAttributionBySegment(rows)[row.id]?.id,
      'canonical-system-decision',
    );
    expect(
      reportableActivitySegments(segments: [row], attributions: rows),
      isEmpty,
    );
  });

  test('updatedAt breaks ties only at the same attribution revision', () {
    final row = segment('equal-revision', 'Code.exe');
    final rows = [
      attribution(
        id: 'older-clock',
        segmentId: row.id,
        classification: 'system_activity',
        revision: 7,
        updatedAt: start,
      ),
      attribution(
        id: 'newer-clock',
        segmentId: row.id,
        classification: 'supporting_work',
        revision: 7,
        updatedAt: start.add(const Duration(seconds: 1)),
      ),
    ];

    expect(latestActivityAttributionBySegment(rows)[row.id]?.id, 'newer-clock');
  });
}
