import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/activity/data/activity_aggregation_service.dart';

void main() {
  test(
    'matching executable periods are grouped without duplicate time',
    () async {
      final start = DateTime.utc(2026, 7, 26, 8);
      final segments = List.generate(5, (index) {
        final segmentStart = start.add(Duration(minutes: index * 2));
        return LocalActivitySegment(
          id: 'segment-$index',
          userId: 'user',
          deviceId: 'device',
          deviceEventId: 'event-$index',
          startedAt: segmentStart,
          endedAt: segmentStart.add(const Duration(seconds: 30)),
          sourceType: 'windows_foreground',
          processName: index.isEven
              ? r'C:\Program Files\ChatGPT\ChatGPT.exe'
              : 'chatgpt.exe',
          idleState: 'technical_idle',
          rawMetadataJson: '{}',
          revision: 1,
          createdAt: segmentStart,
          updatedAt: segmentStart,
        );
      });

      final result = await ActivityAggregationService().aggregate(
        segments: segments,
        attributions: const <LocalAttribution>[],
        rangeStartUtc: start,
        rangeEndUtc: start.add(const Duration(hours: 1)),
      );

      expect(result.groups, hasLength(1));
      expect(result.groups.single.name, 'Chatgpt');
      expect(result.groups.single.periods, hasLength(5));
      expect(result.groups.single.totalMs, 150000);
      expect(result.totalMs, 150000);
    },
  );

  test(
    'System periods stay visible for audit but never enter totals',
    () async {
      final start = DateTime.utc(2026, 8, 15, 9);
      LocalActivitySegment segment(String id, int minute) =>
          LocalActivitySegment(
            id: id,
            userId: 'user',
            deviceId: 'device',
            deviceEventId: id,
            startedAt: start.add(Duration(minutes: minute)),
            endedAt: start.add(Duration(minutes: minute + 5)),
            sourceType: 'windows_foreground',
            processName: 'chrome.exe',
            rawMetadataJson: '{}',
            revision: 1,
            createdAt: start,
            updatedAt: start,
          );
      LocalAttribution attribution(String id, String segmentId, String value) =>
          LocalAttribution(
            id: id,
            userId: 'user',
            activitySegmentId: segmentId,
            targetType: 'unassigned_activity',
            classification: value,
            confidence: 1,
            attributionStatus: 'confirmed',
            confirmedByUser: true,
            revision: 1,
            createdAt: start,
            updatedAt: start,
          );
      final work = segment('work', 0);
      final system = segment('system', 5);

      final result = await ActivityAggregationService().aggregate(
        segments: [work, system],
        attributions: [
          attribution('work-attribution', work.id, 'supporting_work'),
          attribution('system-attribution', system.id, 'system_activity'),
        ],
        rangeStartUtc: start,
        rangeEndUtc: start.add(const Duration(minutes: 10)),
      );

      expect(result.groups, hasLength(2));
      expect(
        result.groups
            .singleWhere((group) => group.classification == 'system_activity')
            .totalMs,
        const Duration(minutes: 5).inMilliseconds,
      );
      expect(result.totalMs, const Duration(minutes: 5).inMilliseconds);
      expect(result.activeMs, const Duration(minutes: 5).inMilliseconds);
    },
  );
}
