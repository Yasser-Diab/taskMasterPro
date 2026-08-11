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
}
