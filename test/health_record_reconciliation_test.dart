import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:taskmaster_pro/features/health/data/health_record_processing.dart';

void main() {
  test('connection state requires real recent records before Connected', () {
    final now = DateTime.utc(2026, 7, 30, 12);

    expect(
      resolveHealthConnectionState(
        authorized: false,
        hasActualRecords: false,
        now: now,
      ),
      HealthConnectionState.permissionRequired,
    );
    expect(
      resolveHealthConnectionState(
        authorized: true,
        hasActualRecords: false,
        now: now,
      ),
      HealthConnectionState.permissionGrantedWaitingForData,
    );
    expect(
      resolveHealthConnectionState(
        authorized: true,
        hasActualRecords: true,
        latestRecordAt: now.subtract(const Duration(hours: 3)),
        now: now,
      ),
      HealthConnectionState.connectedDataReceived,
    );
    expect(
      resolveHealthConnectionState(
        authorized: true,
        hasActualRecords: true,
        latestRecordAt: now.subtract(const Duration(days: 4)),
        now: now,
      ),
      HealthConnectionState.connectedNoRecentRecords,
    );
    expect(
      resolveHealthConnectionState(
        authorized: true,
        hasActualRecords: true,
        latestRecordAt: now,
        now: now,
        readFailed: true,
      ),
      HealthConnectionState.needsAttention,
    );
  });

  test('overlapping additive records keep only the uncovered tail', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final summary = HealthSummary.fromPoints([
      _point(
        uuid: 'huawei-steps',
        value: 1000,
        from: start,
        to: start.add(const Duration(hours: 1)),
        sourceId: 'com.huawei.health',
        sourceName: 'Huawei Health',
      ),
      _point(
        uuid: 'nothing-steps',
        value: 900,
        from: start.add(const Duration(minutes: 30)),
        to: start.add(const Duration(hours: 1, minutes: 30)),
        sourceId: 'com.nothing.smartcenter',
        sourceName: 'Nothing X',
      ),
    ]);

    expect(summary.steps, 1450);
    expect(summary.recordCount, 2);
    expect(summary.rawRecordCount, 2);
    expect(summary.discardedOverlapCount, 0);
    expect(summary.sources, {'Huawei Health', 'Nothing X'});
  });

  test('a second source can fill a non-overlapping period', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final summary = HealthSummary.fromPoints([
      _point(
        uuid: 'huawei-steps',
        value: 1000,
        from: start,
        to: start.add(const Duration(hours: 1)),
        sourceId: 'com.huawei.health',
        sourceName: 'Huawei Health',
      ),
      _point(
        uuid: 'nothing-steps',
        value: 900,
        from: start.add(const Duration(hours: 1)),
        to: start.add(const Duration(hours: 2)),
        sourceId: 'com.nothing.smartcenter',
        sourceName: 'Nothing X',
      ),
    ]);

    expect(summary.steps, 1900);
    expect(summary.recordCount, 2);
    expect(summary.sources, {'Huawei Health', 'Nothing X'});
    expect(summary.lastUpdatedAt, start.add(const Duration(hours: 2)));
  });

  test('an exact Health Connect UUID is idempotent', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final record = _point(
      uuid: 'same-record',
      value: 500,
      from: start,
      to: start.add(const Duration(minutes: 30)),
      sourceId: 'com.huawei.health',
      sourceName: 'Huawei Health',
    );
    final summary = HealthSummary.fromPoints([record, record]);

    expect(summary.steps, 500);
    expect(summary.recordCount, 1);
    expect(summary.discardedOverlapCount, 1);
  });

  test('canonical daily steps do not inherit a multi-day raw total', () {
    final dayStart = DateTime.utc(2026, 7, 28);
    final summary = HealthSummary.fromPoints(
      [
        _point(
          uuid: 'seven-day-counter',
          value: 42000,
          from: dayStart.subtract(const Duration(days: 6)),
          to: dayStart.add(const Duration(hours: 12)),
          sourceId: 'com.huawei.health',
          sourceName: 'com.huawei.health',
        ),
      ],
      window: HealthInterval(dayStart, dayStart.add(const Duration(days: 1))),
      canonicalSteps: 1234,
      heightCm: 170,
      importedAt: DateTime.utc(2026, 7, 28, 18),
    );

    expect(summary.steps, 1234);
    expect(
      summary.distanceMeters,
      closeTo(1234 * 170 * healthStrideFactor / 100, 0.001),
    );
    expect(summary.distanceEstimated, isTrue);
    expect(summary.distanceProvenance, 'steps_height_stride_estimate');
    expect(summary.heightCm, 170);
  });

  test('the health headline resets when the local calendar day changes', () {
    final yesterday = DateTime(2026, 7, 29, 23, 59);
    final today = DateTime(2026, 7, 30, 0, 1);
    final summaries = <String, HealthSummary>{
      healthLocalDayKey(yesterday): HealthSummary(
        steps: 15200,
        importedAt: yesterday,
      ),
    };

    expect(healthSummaryForLocalDay(summaries, yesterday).steps, 15200);
    expect(healthSummaryForLocalDay(summaries, today).steps, 0);
  });

  test('distance fallback requires a valid profile height', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final summary = HealthSummary.fromPoints(
      [
        _point(
          uuid: 'steps',
          value: 1000,
          from: start,
          to: start.add(const Duration(hours: 1)),
          sourceId: 'com.huawei.health',
          sourceName: 'Huawei Health',
        ),
      ],
      canonicalSteps: 1000,
      heightCm: 40,
    );

    expect(summary.distanceMeters, 0);
    expect(summary.distanceEstimated, isFalse);
  });

  test('source record counts stay scoped to each metric', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final summary = HealthSummary.fromPoints([
      _point(
        uuid: 'huawei-steps',
        value: 1000,
        from: start,
        to: start.add(const Duration(hours: 1)),
        sourceId: 'com.huawei.health',
        sourceName: 'Huawei Health',
      ),
      _point(
        uuid: 'nothing-heart-rate',
        value: 82,
        from: start.add(const Duration(minutes: 15)),
        to: start.add(const Duration(minutes: 16)),
        sourceId: 'com.nothing.smartcenter',
        sourceName: 'Nothing X',
        type: HealthDataType.HEART_RATE,
        unit: HealthDataUnit.BEATS_PER_MINUTE,
      ),
    ]);

    expect(summary.metricSourceRecordCounts[HealthDataType.STEPS], {
      'Huawei Health': 1,
    });
    expect(summary.metricSourceRecordCounts[HealthDataType.HEART_RATE], {
      'Nothing X': 1,
    });
    expect(
      summary.sourceLatestRecordAt['Huawei Health'],
      start.add(const Duration(hours: 1)),
    );
    expect(
      summary.sourceLatestRecordAt['Nothing X'],
      start.add(const Duration(minutes: 16)),
    );
  });

  test('sleep sessions subtract awake time instead of disappearing', () {
    final start = DateTime.utc(2026, 8, 24, 0, 27);
    final end = DateTime.utc(2026, 8, 24, 11, 31);
    final normalized = normalizeHealthConnectSleepRecords([
      _point(
        uuid: 'night-session',
        value: 664,
        from: start,
        to: end,
        sourceId: 'com.nothing.smartcenter',
        sourceName: 'Nothing X',
        type: HealthDataType.SLEEP_SESSION,
        unit: HealthDataUnit.MINUTE,
      ),
      _point(
        uuid: 'night-session',
        value: 43,
        from: DateTime.utc(2026, 8, 24, 10, 48),
        to: end,
        sourceId: 'com.nothing.smartcenter',
        sourceName: 'Nothing X',
        type: HealthDataType.SLEEP_AWAKE,
        unit: HealthDataUnit.MINUTE,
      ),
    ]);

    final summary = HealthSummary.fromPoints(normalized);

    expect(summary.sleepMinutes, 621);
    expect(summary.metricRecordCounts[HealthDataType.SLEEP_ASLEEP], 1);
    expect(summary.metricSources[HealthDataType.SLEEP_ASLEEP], {'Nothing X'});
  });

  test('sleep sessions are not double counted with detailed stages', () {
    final start = DateTime.utc(2026, 8, 24);
    final end = start.add(const Duration(hours: 8));
    final normalized = normalizeHealthConnectSleepRecords([
      _point(
        uuid: 'session-with-stages',
        value: 480,
        from: start,
        to: end,
        sourceId: 'watch.sleep',
        sourceName: 'Watch Sleep',
        type: HealthDataType.SLEEP_SESSION,
        unit: HealthDataUnit.MINUTE,
      ),
      _point(
        uuid: 'session-with-stages',
        value: 180,
        from: start,
        to: start.add(const Duration(hours: 3)),
        sourceId: 'watch.sleep',
        sourceName: 'Watch Sleep',
        type: HealthDataType.SLEEP_DEEP,
        unit: HealthDataUnit.MINUTE,
      ),
      _point(
        uuid: 'session-with-stages',
        value: 30,
        from: start.add(const Duration(hours: 7, minutes: 30)),
        to: end,
        sourceId: 'watch.sleep',
        sourceName: 'Watch Sleep',
        type: HealthDataType.SLEEP_AWAKE_IN_BED,
        unit: HealthDataUnit.MINUTE,
      ),
    ]);

    expect(HealthSummary.fromPoints(normalized).sleepMinutes, 450);
  });

  test('multiple stage records sharing a parent UUID remain distinct', () {
    final start = DateTime.utc(2026, 8, 24);
    final normalized = normalizeHealthConnectSleepRecords([
      _point(
        uuid: 'shared-parent',
        value: 30,
        from: start,
        to: start.add(const Duration(minutes: 30)),
        sourceId: 'watch.sleep',
        sourceName: 'Watch Sleep',
        type: HealthDataType.SLEEP_LIGHT,
        unit: HealthDataUnit.MINUTE,
      ),
      _point(
        uuid: 'shared-parent',
        value: 45,
        from: start.add(const Duration(minutes: 30)),
        to: start.add(const Duration(minutes: 75)),
        sourceId: 'watch.sleep',
        sourceName: 'Watch Sleep',
        type: HealthDataType.SLEEP_REM,
        unit: HealthDataUnit.MINUTE,
      ),
    ]);

    final summary = HealthSummary.fromPoints(normalized);

    expect(summary.sleepMinutes, 75);
    expect(summary.metricRecordCounts[HealthDataType.SLEEP_ASLEEP], 2);
  });

  test('task summaries use only real execution overlap', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final window = HealthInterval(
      start.subtract(const Duration(hours: 1)),
      start.add(const Duration(hours: 2)),
    );
    final intervals = HealthExecutionIntervalBuilder.build(
      sessions: [
        HealthExecutionSession(
          id: 'session-1',
          taskOccurrenceId: 'task-1',
          state: 'paused',
          startedAt: start,
          updatedAt: start.add(const Duration(hours: 1)),
          accumulatedActiveMs: const Duration(hours: 1).inMilliseconds,
        ),
      ],
      events: [
        HealthSessionEvent(
          sessionId: 'session-1',
          eventType: 'start',
          occurredAt: start,
        ),
        HealthSessionEvent(
          sessionId: 'session-1',
          eventType: 'pause',
          occurredAt: start.add(const Duration(hours: 1)),
        ),
      ],
      refreshWindow: window,
      now: window.end,
    );
    final summaries = TaskHealthSummaryAggregator.aggregate(
      rawPoints: [
        _point(
          uuid: 'partly-overlapping-steps',
          value: 1000,
          from: start.subtract(const Duration(minutes: 30)),
          to: start.add(const Duration(minutes: 30)),
          sourceId: 'com.huawei.health',
          sourceName: 'Huawei Health',
        ),
      ],
      executionIntervals: intervals,
      refreshWindow: window,
      importedAt: window.end,
      heightCm: 170,
    );

    final steps = summaries.singleWhere(
      (summary) => summary.metricType == 'steps',
    );
    expect(steps.taskOccurrenceId, 'task-1');
    expect(steps.executionSessionId, 'session-1');
    expect(steps.value, 500);
    expect(steps.allocationMethod, 'proportional_overlap');
    expect(steps.estimated, isTrue);
    expect(steps.overlapFraction, closeTo(0.5, 0.001));
    expect(steps.sourceApplications, ['Huawei Health']);
    expect(steps.sourceRecordCounts, {'Huawei Health': 1});

    final distance = summaries.singleWhere(
      (summary) => summary.metricType == 'distance',
    );
    expect(distance.value, closeTo(352.75, 0.001));
    expect(distance.provenance, 'steps_height_stride_estimate');
    expect(distance.estimated, isTrue);
  });

  test('switched session seeds its first interval before a pause event', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final pause = start.add(const Duration(minutes: 45));
    final intervals = HealthExecutionIntervalBuilder.build(
      sessions: [
        HealthExecutionSession(
          id: 'switched-session',
          taskOccurrenceId: 'selected-task',
          state: 'paused',
          startedAt: start,
          updatedAt: pause,
          accumulatedActiveMs: const Duration(minutes: 45).inMilliseconds,
        ),
      ],
      events: [
        HealthSessionEvent(
          sessionId: 'switched-session',
          eventType: 'pause',
          occurredAt: pause,
        ),
      ],
      refreshWindow: HealthInterval(
        start.subtract(const Duration(minutes: 5)),
        pause.add(const Duration(minutes: 5)),
      ),
      now: pause,
    );

    expect(intervals, hasLength(1));
    expect(intervals.single.taskOccurrenceId, 'selected-task');
    expect(intervals.single.interval.start, start);
    expect(intervals.single.interval.end, pause);
  });

  test('overlapping task intervals never duplicate an additive record', () {
    final start = DateTime.utc(2026, 7, 28, 10);
    final interval = HealthInterval(start, start.add(const Duration(hours: 1)));
    final summaries = TaskHealthSummaryAggregator.aggregate(
      rawPoints: [
        _point(
          uuid: 'one-step-record',
          value: 1000,
          from: interval.start,
          to: interval.end,
          sourceId: 'com.huawei.health',
          sourceName: 'Huawei Health',
        ),
      ],
      executionIntervals: [
        HealthExecutionInterval(
          taskOccurrenceId: 'task-1',
          executionSessionId: 'session-1',
          interval: interval,
        ),
        HealthExecutionInterval(
          taskOccurrenceId: 'task-2',
          executionSessionId: 'session-2',
          interval: interval,
        ),
      ],
      refreshWindow: interval,
      importedAt: interval.end,
    );

    expect(
      summaries
          .where((summary) => summary.metricType == 'steps')
          .fold<num>(0, (sum, summary) => sum + summary.value),
      1000,
    );
  });

  test('zero-duration additive records are not assigned to tasks', () {
    final instant = DateTime.utc(2026, 7, 28, 10, 30);
    final summaries = TaskHealthSummaryAggregator.aggregate(
      rawPoints: [
        _point(
          uuid: 'invalid-instant-steps',
          value: 1000,
          from: instant,
          to: instant,
          sourceId: 'com.huawei.health',
          sourceName: 'Huawei Health',
        ),
      ],
      executionIntervals: [
        HealthExecutionInterval(
          taskOccurrenceId: 'task-1',
          executionSessionId: 'session-1',
          interval: HealthInterval(
            instant.subtract(const Duration(minutes: 30)),
            instant.add(const Duration(minutes: 30)),
          ),
        ),
      ],
      refreshWindow: HealthInterval(
        instant.subtract(const Duration(hours: 1)),
        instant.add(const Duration(hours: 1)),
      ),
      importedAt: instant,
    );

    expect(summaries, isEmpty);
  });
}

HealthDataPoint _point({
  required String uuid,
  required num value,
  required DateTime from,
  required DateTime to,
  required String sourceId,
  required String sourceName,
  HealthDataType type = HealthDataType.STEPS,
  HealthDataUnit unit = HealthDataUnit.COUNT,
}) {
  return HealthDataPoint(
    uuid: uuid,
    value: NumericHealthValue(numericValue: value),
    type: type,
    unit: unit,
    dateFrom: from,
    dateTo: to,
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    sourceDeviceId: 'watch',
    sourceId: sourceId,
    sourceName: sourceName,
    recordingMethod: RecordingMethod.automatic,
  );
}
