import 'dart:math' as math;

import 'package:health/health.dart';

const double healthStrideFactor = 0.415;
const double minimumHealthHeightCm = 50;
const double maximumHealthHeightCm = 250;

String healthLocalDayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

HealthSummary healthSummaryForLocalDay(
  Map<String, HealthSummary> summariesByDay,
  DateTime day,
) => summariesByDay[healthLocalDayKey(day)] ?? const HealthSummary();

bool isValidHealthHeight(double? heightCm) =>
    heightCm != null &&
    heightCm.isFinite &&
    heightCm >= minimumHealthHeightCm &&
    heightCm <= maximumHealthHeightCm;

double? estimatedDistanceMetersFromSteps(int steps, double? heightCm) {
  if (steps <= 0 || !isValidHealthHeight(heightCm)) return null;
  return steps * heightCm! * healthStrideFactor / 100;
}

enum HealthConnectionState {
  permissionRequired,
  permissionGrantedWaitingForData,
  connectedDataReceived,
  connectedNoRecentRecords,
  needsAttention,
}

HealthConnectionState resolveHealthConnectionState({
  required bool authorized,
  required bool hasActualRecords,
  required DateTime now,
  DateTime? latestRecordAt,
  bool readFailed = false,
  Duration recentWindow = const Duration(days: 2),
}) {
  if (readFailed) return HealthConnectionState.needsAttention;
  if (!authorized) return HealthConnectionState.permissionRequired;
  if (!hasActualRecords) {
    return HealthConnectionState.permissionGrantedWaitingForData;
  }
  if (latestRecordAt == null ||
      now.toUtc().difference(latestRecordAt.toUtc()) > recentWindow) {
    return HealthConnectionState.connectedNoRecentRecords;
  }
  return HealthConnectionState.connectedDataReceived;
}

String friendlyHealthSource(HealthDataPoint point) {
  final candidates = [point.sourceName, point.sourceId]
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  final joined = candidates.join(' ').toLowerCase();
  if (joined.contains('huawei')) return 'Huawei Health';
  if (joined.contains('nothing')) return 'Nothing X';
  if (joined.contains('healthdata') || joined.contains('health connect')) {
    return 'Health Connect';
  }
  if (candidates.isEmpty) return 'Health Connect';
  final source = candidates.first;
  if (source.contains('.') && !source.contains(' ')) {
    return source;
  }
  return source;
}

class HealthInterval {
  HealthInterval(this.start, this.end)
    : assert(end.millisecondsSinceEpoch > start.millisecondsSinceEpoch);

  final DateTime start;
  final DateTime end;

  int get durationMilliseconds =>
      math.max(1, end.difference(start).inMilliseconds);

  HealthInterval? intersection(HealthInterval other) {
    final overlapStart = start.isAfter(other.start) ? start : other.start;
    final overlapEnd = end.isBefore(other.end) ? end : other.end;
    if (!overlapStart.isBefore(overlapEnd)) return null;
    return HealthInterval(overlapStart, overlapEnd);
  }
}

class HealthRecordAllocation {
  const HealthRecordAllocation({
    required this.point,
    required this.originalInterval,
    required this.acceptedIntervals,
  });

  final HealthDataPoint point;
  final HealthInterval originalInterval;
  final List<HealthInterval> acceptedIntervals;

  int get acceptedDurationMilliseconds => acceptedIntervals.fold(
    0,
    (sum, interval) => sum + interval.durationMilliseconds,
  );

  double get acceptedFraction =>
      (acceptedDurationMilliseconds / originalInterval.durationMilliseconds)
          .clamp(0.0, 1.0);
}

class HealthReconciliationResult {
  const HealthReconciliationResult({
    required this.allocations,
    required this.rawRecordCount,
    required this.uniqueRecordCount,
  });

  final List<HealthRecordAllocation> allocations;
  final int rawRecordCount;
  final int uniqueRecordCount;

  List<HealthDataPoint> get points =>
      List.unmodifiable(allocations.map((allocation) => allocation.point));
}

/// Removes exact duplicates and apportions only the uncovered tails of
/// overlapping records from secondary sources.
///
/// Health Connect can return the same interval through a phone, a watch, and
/// an intermediary application. A secondary additive record is therefore
/// never counted wholesale when part of its interval is already represented.
abstract final class HealthRecordReconciler {
  static HealthReconciliationResult reconcile(List<HealthDataPoint> rawPoints) {
    final unique = <String, HealthDataPoint>{};
    for (final point in rawPoints) {
      unique.putIfAbsent(_identity(point), () => point);
    }
    final byType = <HealthDataType, List<HealthDataPoint>>{};
    for (final point in unique.values) {
      byType.putIfAbsent(point.type, () => []).add(point);
    }

    final allocations = <HealthRecordAllocation>[];
    for (final entry in byType.entries) {
      final bySource = <String, List<HealthDataPoint>>{};
      for (final point in entry.value) {
        bySource.putIfAbsent(_sourceKey(point), () => []).add(point);
      }
      final sources = bySource.entries.toList()
        ..sort((left, right) {
          final coverageOrder = _coverageMilliseconds(
            right.value,
          ).compareTo(_coverageMilliseconds(left.value));
          if (coverageOrder != 0) return coverageOrder;
          final countOrder = right.value.length.compareTo(left.value.length);
          if (countOrder != 0) return countOrder;
          return left.key.compareTo(right.key);
        });

      var acceptedCoverage = <HealthInterval>[];
      for (final source in sources) {
        final candidates = [...source.value]
          ..sort((left, right) {
            final startOrder = left.dateFrom.compareTo(right.dateFrom);
            if (startOrder != 0) return startOrder;
            final endOrder = left.dateTo.compareTo(right.dateTo);
            if (endOrder != 0) return endOrder;
            return left.uuid.compareTo(right.uuid);
          });
        for (final point in candidates) {
          final original = _pointInterval(point);
          final uncovered = _subtract(original, acceptedCoverage);
          if (uncovered.isEmpty) continue;
          allocations.add(
            HealthRecordAllocation(
              point: point,
              originalInterval: original,
              acceptedIntervals: List.unmodifiable(uncovered),
            ),
          );
          acceptedCoverage = _mergeIntervals([
            ...acceptedCoverage,
            ...uncovered,
          ]);
        }
      }
    }

    allocations.sort((left, right) {
      final startOrder = left.point.dateFrom.compareTo(right.point.dateFrom);
      if (startOrder != 0) return startOrder;
      final typeOrder = left.point.type.name.compareTo(right.point.type.name);
      if (typeOrder != 0) return typeOrder;
      return left.point.uuid.compareTo(right.point.uuid);
    });
    return HealthReconciliationResult(
      allocations: List.unmodifiable(allocations),
      rawRecordCount: rawPoints.length,
      uniqueRecordCount: unique.length,
    );
  }

  static String _identity(HealthDataPoint point) {
    final uuid = point.uuid.trim();
    if (uuid.isNotEmpty) return '${point.type.name}|$uuid';
    final numeric = _numeric(point);
    return [
      point.type.name,
      _sourceKey(point),
      point.dateFrom.toUtc().toIso8601String(),
      point.dateTo.toUtc().toIso8601String(),
      numeric?.toString() ?? point.value.toString(),
    ].join('|');
  }

  static String _sourceKey(HealthDataPoint point) {
    final sourceId = point.sourceId.trim();
    if (sourceId.isNotEmpty) return sourceId.toLowerCase();
    final sourceName = point.sourceName.trim();
    if (sourceName.isNotEmpty) return sourceName.toLowerCase();
    return point.sourceDeviceId.trim().toLowerCase();
  }

  static int _coverageMilliseconds(List<HealthDataPoint> points) {
    return _mergeIntervals(
      points.map(_pointInterval).toList(),
    ).fold(0, (sum, interval) => sum + interval.durationMilliseconds);
  }
}

class HealthSummary {
  const HealthSummary({
    this.steps = 0,
    this.distanceMeters = 0,
    this.averageHeartRate,
    this.sleepMinutes = 0,
    this.activeCalories = 0,
    this.workoutCount = 0,
    this.sources = const {},
    this.recordCount = 0,
    this.rawRecordCount = 0,
    this.discardedOverlapCount = 0,
    this.latestRecordAt,
    this.importedAt,
    this.metricRecordCounts = const {},
    this.metricSources = const {},
    this.metricLatestRecordAt = const {},
    this.metricSourceRecordCounts = const {},
    this.sourceRecordCounts = const {},
    this.sourceLatestRecordAt = const {},
    this.distanceEstimated = false,
    this.distanceProvenance = 'health_connect_record',
    this.heightCm,
    this.strideFactor,
  });

  factory HealthSummary.fromPoints(
    List<HealthDataPoint> points, {
    HealthInterval? window,
    int? canonicalSteps,
    double? heightCm,
    DateTime? importedAt,
  }) {
    return HealthSummary.fromReconciliation(
      HealthRecordReconciler.reconcile(points),
      rawPoints: points,
      window: window,
      canonicalSteps: canonicalSteps,
      heightCm: heightCm,
      importedAt: importedAt,
    );
  }

  factory HealthSummary.fromReconciliation(
    HealthReconciliationResult reconciliation, {
    required List<HealthDataPoint> rawPoints,
    HealthInterval? window,
    int? canonicalSteps,
    double? heightCm,
    DateTime? importedAt,
  }) {
    var rawSteps = 0.0;
    var distance = 0.0;
    var sleep = 0.0;
    var calories = 0.0;
    var heartRate = 0.0;
    var heartRateWeight = 0.0;
    var workouts = 0;
    final contributingRecords = <String>{};
    final sources = <String>{};
    final metricRecordIds = <HealthDataType, Set<String>>{};
    final metricSources = <HealthDataType, Set<String>>{};
    final metricLatest = <HealthDataType, DateTime>{};
    final metricSourceRecordIds = <HealthDataType, Map<String, Set<String>>>{};
    final sourceRecordIds = <String, Set<String>>{};
    final sourceLatest = <String, DateTime>{};

    for (final allocation in reconciliation.allocations) {
      final point = allocation.point;
      final accepted = window == null
          ? allocation.acceptedIntervals
          : allocation.acceptedIntervals
                .map((interval) => interval.intersection(window))
                .whereType<HealthInterval>()
                .toList(growable: false);
      if (accepted.isEmpty) continue;
      if (_isAdditiveMetric(point.type) &&
          (!point.dateTo.isAfter(point.dateFrom) ||
              allocation.originalInterval.durationMilliseconds >
                  const Duration(days: 1).inMilliseconds)) {
        continue;
      }
      final acceptedMilliseconds = accepted.fold<int>(
        0,
        (sum, interval) => sum + interval.durationMilliseconds,
      );
      final fraction =
          (acceptedMilliseconds /
                  allocation.originalInterval.durationMilliseconds)
              .clamp(0.0, 1.0);
      if (fraction <= 0) continue;
      if (point.type == HealthDataType.WORKOUT &&
          window != null &&
          (point.dateFrom.isBefore(window.start) ||
              !point.dateFrom.isBefore(window.end))) {
        continue;
      }
      final numeric = _numeric(point);
      if (point.type != HealthDataType.WORKOUT && numeric == null) continue;

      final identity = _recordIdentity(point);
      final source = friendlyHealthSource(point);
      contributingRecords.add(identity);
      sources.add(source);
      metricRecordIds.putIfAbsent(point.type, () => <String>{}).add(identity);
      metricSources.putIfAbsent(point.type, () => <String>{}).add(source);
      metricSourceRecordIds
          .putIfAbsent(point.type, () => <String, Set<String>>{})
          .putIfAbsent(source, () => <String>{})
          .add(identity);
      sourceRecordIds.putIfAbsent(source, () => <String>{}).add(identity);
      final currentSourceLatest = sourceLatest[source];
      if (currentSourceLatest == null ||
          point.dateTo.isAfter(currentSourceLatest)) {
        sourceLatest[source] = point.dateTo;
      }
      final currentLatest = metricLatest[point.type];
      if (currentLatest == null || point.dateTo.isAfter(currentLatest)) {
        metricLatest[point.type] = point.dateTo;
      }

      switch (point.type) {
        case HealthDataType.STEPS:
          rawSteps += numeric! * fraction;
        case HealthDataType.DISTANCE_DELTA:
          distance += numeric! * fraction;
        case HealthDataType.HEART_RATE:
          heartRate += numeric! * fraction;
          heartRateWeight += fraction;
        case HealthDataType.SLEEP_ASLEEP:
          sleep += numeric! * fraction;
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          calories += numeric! * fraction;
        case HealthDataType.WORKOUT:
          workouts++;
        default:
          break;
      }
    }

    var steps = canonicalSteps ?? rawSteps.round();
    if (steps < 0) steps = 0;
    if (canonicalSteps != null &&
        canonicalSteps > 0 &&
        (metricRecordIds[HealthDataType.STEPS]?.isEmpty ?? true)) {
      const aggregateSource = 'Health Connect';
      const aggregateId = 'health_connect_aggregate_steps';
      sources.add(aggregateSource);
      contributingRecords.add(aggregateId);
      metricRecordIds[HealthDataType.STEPS] = {aggregateId};
      metricSources[HealthDataType.STEPS] = {aggregateSource};
      metricSourceRecordIds[HealthDataType.STEPS] = {
        aggregateSource: {aggregateId},
      };
      sourceRecordIds
          .putIfAbsent(aggregateSource, () => <String>{})
          .add(aggregateId);
      sourceLatest[aggregateSource] =
          window?.end ?? importedAt?.toUtc() ?? DateTime.now().toUtc();
    }

    var distanceEstimated = false;
    var distanceProvenance = 'health_connect_record';
    double? distanceHeight;
    double? distanceStride;
    if ((metricRecordIds[HealthDataType.DISTANCE_DELTA]?.isEmpty ?? true)) {
      final estimated = estimatedDistanceMetersFromSteps(steps, heightCm);
      if (estimated != null) {
        distance = estimated;
        distanceEstimated = true;
        distanceProvenance = 'steps_height_stride_estimate';
        distanceHeight = heightCm;
        distanceStride = healthStrideFactor;
        metricRecordIds[HealthDataType.DISTANCE_DELTA] = {
          ...?metricRecordIds[HealthDataType.STEPS],
        };
        metricSources[HealthDataType.DISTANCE_DELTA] = {
          ...?metricSources[HealthDataType.STEPS],
        };
        metricSourceRecordIds[HealthDataType.DISTANCE_DELTA] = {
          for (final entry
              in metricSourceRecordIds[HealthDataType.STEPS]?.entries ??
                  const <MapEntry<String, Set<String>>>[])
            entry.key: {...entry.value},
        };
        final latestSteps = metricLatest[HealthDataType.STEPS];
        if (latestSteps != null) {
          metricLatest[HealthDataType.DISTANCE_DELTA] = latestSteps;
        }
      }
    }

    final latestRecordAt = metricLatest.values.fold<DateTime?>(
      null,
      (latest, value) =>
          latest == null || value.isAfter(latest) ? value : latest,
    );
    final rawRecordCount = rawPoints.where((point) {
      if (window == null) return true;
      return _pointInterval(point).intersection(window) != null;
    }).length;
    final metricRecordCounts = metricRecordIds.map(
      (type, ids) => MapEntry(type, ids.length),
    );
    return HealthSummary(
      steps: steps,
      distanceMeters: distance,
      averageHeartRate: heartRateWeight == 0
          ? null
          : heartRate / heartRateWeight,
      sleepMinutes: sleep,
      activeCalories: calories,
      workoutCount: workouts,
      sources: Set.unmodifiable(sources),
      recordCount: contributingRecords.length,
      rawRecordCount: rawRecordCount,
      discardedOverlapCount: math.max(
        0,
        rawRecordCount - contributingRecords.length,
      ),
      latestRecordAt: latestRecordAt,
      importedAt: importedAt?.toUtc() ?? DateTime.now().toUtc(),
      metricRecordCounts: Map.unmodifiable(metricRecordCounts),
      metricSources: Map.unmodifiable(
        metricSources.map(
          (type, values) => MapEntry(type, Set.unmodifiable(values)),
        ),
      ),
      metricLatestRecordAt: Map.unmodifiable(metricLatest),
      metricSourceRecordCounts:
          Map<HealthDataType, Map<String, int>>.unmodifiable(
            metricSourceRecordIds.map(
              (type, counts) => MapEntry(
                type,
                Map<String, int>.unmodifiable(
                  counts.map((source, ids) => MapEntry(source, ids.length)),
                ),
              ),
            ),
          ),
      sourceRecordCounts: Map.unmodifiable(
        sourceRecordIds.map((source, ids) => MapEntry(source, ids.length)),
      ),
      sourceLatestRecordAt: Map.unmodifiable(sourceLatest),
      distanceEstimated: distanceEstimated,
      distanceProvenance: distanceProvenance,
      heightCm: distanceHeight,
      strideFactor: distanceStride,
    );
  }

  final int steps;
  final double distanceMeters;
  final double? averageHeartRate;
  final double sleepMinutes;
  final double activeCalories;
  final int workoutCount;
  final Set<String> sources;
  final int recordCount;
  final int rawRecordCount;
  final int discardedOverlapCount;
  final DateTime? latestRecordAt;
  final DateTime? importedAt;
  final Map<HealthDataType, int> metricRecordCounts;
  final Map<HealthDataType, Set<String>> metricSources;
  final Map<HealthDataType, DateTime> metricLatestRecordAt;
  final Map<HealthDataType, Map<String, int>> metricSourceRecordCounts;
  final Map<String, int> sourceRecordCounts;
  final Map<String, DateTime> sourceLatestRecordAt;
  final bool distanceEstimated;
  final String distanceProvenance;
  final double? heightCm;
  final double? strideFactor;

  @Deprecated('Use latestRecordAt for the measurement timestamp.')
  DateTime? get lastUpdatedAt => latestRecordAt;
}

class HealthExecutionSession {
  const HealthExecutionSession({
    required this.id,
    required this.taskOccurrenceId,
    required this.state,
    required this.startedAt,
    required this.updatedAt,
    required this.accumulatedActiveMs,
    this.finishedAt,
    this.activeSegmentStartedAt,
  });

  final String id;
  final String taskOccurrenceId;
  final String state;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? activeSegmentStartedAt;
  final DateTime updatedAt;
  final int accumulatedActiveMs;
}

class HealthSessionEvent {
  const HealthSessionEvent({
    required this.sessionId,
    required this.eventType,
    required this.occurredAt,
  });

  final String sessionId;
  final String eventType;
  final DateTime occurredAt;
}

class HealthExecutionInterval {
  const HealthExecutionInterval({
    required this.taskOccurrenceId,
    required this.executionSessionId,
    required this.interval,
  });

  final String taskOccurrenceId;
  final String executionSessionId;
  final HealthInterval interval;
}

abstract final class HealthExecutionIntervalBuilder {
  static const _activeEvents = {
    'start',
    'resume',
    'finish_break',
    'start_focus_now',
    'continue_working',
  };
  static const _inactiveEvents = {
    'pause',
    'start_break',
    'complete',
    'finish_task',
    'interrupted',
  };

  static List<HealthExecutionInterval> build({
    required List<HealthExecutionSession> sessions,
    required List<HealthSessionEvent> events,
    required HealthInterval refreshWindow,
    required DateTime now,
  }) {
    final eventsBySession = <String, List<HealthSessionEvent>>{};
    for (final event in events) {
      eventsBySession.putIfAbsent(event.sessionId, () => []).add(event);
    }
    final result = <HealthExecutionInterval>[];
    for (final session in sessions) {
      if (session.taskOccurrenceId.isEmpty) continue;
      final sessionEvents = [...?eventsBySession[session.id]]
        ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
      final intervals = <HealthInterval>[];
      DateTime? activeStart;
      for (final event in sessionEvents) {
        final type = event.eventType.trim().toLowerCase();
        if (_activeEvents.contains(type)) {
          activeStart ??= event.occurredAt;
          continue;
        }
        if (_inactiveEvents.contains(type)) {
          // The canonical switch command historically activated the new
          // session without inserting its initial `start` event. Its first
          // event can therefore be `pause` or `start_break`. Seed that proven
          // first active interval from the session row rather than losing it.
          activeStart ??= intervals.isEmpty && session.accumulatedActiveMs > 0
              ? session.activeSegmentStartedAt ?? session.startedAt
              : null;
          if (activeStart != null && activeStart.isBefore(event.occurredAt)) {
            intervals.add(HealthInterval(activeStart, event.occurredAt));
          }
          activeStart = null;
        }
      }

      if (activeStart != null) {
        final closure = session.state == 'running'
            ? now
            : session.finishedAt ?? session.updatedAt;
        if (activeStart.isBefore(closure)) {
          intervals.add(HealthInterval(activeStart, closure));
        }
      } else if (sessionEvents.isEmpty) {
        final segmentStart = session.state == 'running'
            ? session.activeSegmentStartedAt
            : null;
        if (segmentStart != null && segmentStart.isBefore(now)) {
          intervals.add(HealthInterval(segmentStart, now));
        } else {
          final startedAt = session.startedAt;
          final closure = session.finishedAt ?? session.updatedAt;
          final elapsed = startedAt == null
              ? 0
              : closure.difference(startedAt).inMilliseconds;
          if (startedAt != null &&
              startedAt.isBefore(closure) &&
              session.accumulatedActiveMs > 0 &&
              (elapsed - session.accumulatedActiveMs).abs() <= 1500) {
            intervals.add(HealthInterval(startedAt, closure));
          }
        }
      }

      for (final interval in _mergeIntervals(intervals)) {
        final clipped = interval.intersection(refreshWindow);
        if (clipped == null) continue;
        result.add(
          HealthExecutionInterval(
            taskOccurrenceId: session.taskOccurrenceId,
            executionSessionId: session.id,
            interval: clipped,
          ),
        );
      }
    }
    result.sort(
      (left, right) => left.interval.start.compareTo(right.interval.start),
    );
    return List.unmodifiable(result);
  }
}

class TaskHealthSummary {
  const TaskHealthSummary({
    required this.taskOccurrenceId,
    required this.executionSessionId,
    required this.metricType,
    required this.value,
    required this.unit,
    required this.recordCount,
    required this.rawRecordCount,
    required this.sourceApplications,
    required this.sourceRecordCounts,
    required this.latestRecordAt,
    required this.importedAt,
    required this.windowStartAt,
    required this.windowEndAt,
    required this.intervalStartAt,
    required this.intervalEndAt,
    required this.allocationMethod,
    required this.estimated,
    required this.provenance,
    required this.overlapFraction,
    this.heightCm,
    this.strideFactor,
  });

  final String taskOccurrenceId;
  final String executionSessionId;
  final String metricType;
  final num value;
  final String unit;
  final int recordCount;
  final int rawRecordCount;
  final List<String> sourceApplications;
  final Map<String, int> sourceRecordCounts;
  final DateTime latestRecordAt;
  final DateTime importedAt;
  final DateTime windowStartAt;
  final DateTime windowEndAt;
  final DateTime intervalStartAt;
  final DateTime intervalEndAt;
  final String allocationMethod;
  final bool estimated;
  final String provenance;
  final double overlapFraction;
  final double? heightCm;
  final double? strideFactor;
}

abstract final class TaskHealthSummaryAggregator {
  static const _metricDetails = <HealthDataType, (String, String)>{
    HealthDataType.STEPS: ('steps', 'count'),
    HealthDataType.DISTANCE_DELTA: ('distance', 'm'),
    HealthDataType.ACTIVE_ENERGY_BURNED: ('active_calories', 'kcal'),
    HealthDataType.HEART_RATE: ('average_heart_rate', 'bpm'),
  };

  static List<TaskHealthSummary> aggregate({
    required List<HealthDataPoint> rawPoints,
    required List<HealthExecutionInterval> executionIntervals,
    required HealthInterval refreshWindow,
    required DateTime importedAt,
    double? heightCm,
  }) {
    if (rawPoints.isEmpty || executionIntervals.isEmpty) {
      return const <TaskHealthSummary>[];
    }
    final reconciliation = HealthRecordReconciler.reconcile(rawPoints);
    final accumulators = <String, _TaskMetricAccumulator>{};

    for (final allocation in reconciliation.allocations) {
      final details = _metricDetails[allocation.point.type];
      if (details == null) continue;
      final numeric = _numeric(allocation.point);
      if (numeric == null) continue;
      final isAdditive = allocation.point.type != HealthDataType.HEART_RATE;
      if (isAdditive &&
          (!allocation.point.dateTo.isAfter(allocation.point.dateFrom) ||
              allocation.originalInterval.durationMilliseconds >
                  const Duration(days: 1).inMilliseconds)) {
        continue;
      }

      final overlaps = <_TaskRecordOverlap>[];
      for (final execution in executionIntervals) {
        final intersections = allocation.acceptedIntervals
            .map((interval) => interval.intersection(execution.interval))
            .whereType<HealthInterval>()
            .toList(growable: false);
        if (intersections.isEmpty) continue;
        overlaps.add(
          _TaskRecordOverlap(
            execution: execution,
            intersections: intersections,
          ),
        );
      }
      if (overlaps.isEmpty) continue;
      final totalOverlapMs = overlaps.fold<int>(
        0,
        (sum, overlap) => sum + overlap.durationMilliseconds,
      );
      final denominatorMs = math.max(
        allocation.originalInterval.durationMilliseconds,
        totalOverlapMs,
      );
      final recordId = _recordIdentity(allocation.point);
      final source = friendlyHealthSource(allocation.point);
      for (final overlap in overlaps) {
        final fraction = (overlap.durationMilliseconds / denominatorMs).clamp(
          0.0,
          1.0,
        );
        if (fraction <= 0) continue;
        final key = [
          overlap.execution.taskOccurrenceId,
          overlap.execution.executionSessionId,
          details.$1,
        ].join('|');
        final accumulator = accumulators.putIfAbsent(
          key,
          () => _TaskMetricAccumulator(
            taskOccurrenceId: overlap.execution.taskOccurrenceId,
            executionSessionId: overlap.execution.executionSessionId,
            metricType: details.$1,
            unit: details.$2,
          ),
        );
        accumulator.add(
          recordId: recordId,
          source: source,
          numeric: numeric,
          fraction: fraction,
          isHeartRate: allocation.point.type == HealthDataType.HEART_RATE,
          latestRecordAt: allocation.point.dateTo,
          overlapStart: overlap.start,
          overlapEnd: overlap.end,
        );
      }
    }

    final direct = accumulators.values
        .where((accumulator) => accumulator.recordIds.isNotEmpty)
        .map((accumulator) {
          final sessionIntervals = executionIntervals
              .where(
                (interval) =>
                    interval.executionSessionId ==
                    accumulator.executionSessionId,
              )
              .toList(growable: false);
          final rawRecordIds = <String>{};
          for (final point in rawPoints) {
            final details = _metricDetails[point.type];
            if (details?.$1 != accumulator.metricType) continue;
            final interval = _pointInterval(point);
            if (sessionIntervals.any(
              (execution) => interval.intersection(execution.interval) != null,
            )) {
              rawRecordIds.add(_recordIdentity(point));
            }
          }
          return accumulator.toSummary(
            rawRecordCount: rawRecordIds.length,
            refreshWindow: refreshWindow,
            importedAt: importedAt,
          );
        })
        .toList();

    final result = <TaskHealthSummary>[...direct];
    if (isValidHealthHeight(heightCm)) {
      final directKeys = {
        for (final summary in direct)
          '${summary.taskOccurrenceId}|'
              '${summary.executionSessionId}|${summary.metricType}',
      };
      for (final steps in direct.where(
        (summary) => summary.metricType == 'steps',
      )) {
        final distanceKey =
            '${steps.taskOccurrenceId}|${steps.executionSessionId}|distance';
        if (directKeys.contains(distanceKey)) continue;
        final stepCount = steps.value.round();
        final estimated = estimatedDistanceMetersFromSteps(stepCount, heightCm);
        if (estimated == null) continue;
        result.add(
          TaskHealthSummary(
            taskOccurrenceId: steps.taskOccurrenceId,
            executionSessionId: steps.executionSessionId,
            metricType: 'distance',
            value: estimated,
            unit: 'm',
            recordCount: steps.recordCount,
            rawRecordCount: steps.rawRecordCount,
            sourceApplications: steps.sourceApplications,
            sourceRecordCounts: steps.sourceRecordCounts,
            latestRecordAt: steps.latestRecordAt,
            importedAt: importedAt.toUtc(),
            windowStartAt: refreshWindow.start,
            windowEndAt: refreshWindow.end,
            intervalStartAt: steps.intervalStartAt,
            intervalEndAt: steps.intervalEndAt,
            allocationMethod: steps.allocationMethod,
            estimated: true,
            provenance: 'steps_height_stride_estimate',
            overlapFraction: steps.overlapFraction,
            heightCm: heightCm,
            strideFactor: healthStrideFactor,
          ),
        );
      }
    }
    result.sort((left, right) {
      final taskOrder = left.taskOccurrenceId.compareTo(right.taskOccurrenceId);
      if (taskOrder != 0) return taskOrder;
      final sessionOrder = left.executionSessionId.compareTo(
        right.executionSessionId,
      );
      if (sessionOrder != 0) return sessionOrder;
      return left.metricType.compareTo(right.metricType);
    });
    return List.unmodifiable(result);
  }
}

class _TaskRecordOverlap {
  const _TaskRecordOverlap({
    required this.execution,
    required this.intersections,
  });

  final HealthExecutionInterval execution;
  final List<HealthInterval> intersections;

  int get durationMilliseconds => intersections.fold(
    0,
    (sum, interval) => sum + interval.durationMilliseconds,
  );

  DateTime get start => intersections
      .map((interval) => interval.start)
      .reduce((left, right) => left.isBefore(right) ? left : right);

  DateTime get end => intersections
      .map((interval) => interval.end)
      .reduce((left, right) => left.isAfter(right) ? left : right);
}

class _TaskMetricAccumulator {
  _TaskMetricAccumulator({
    required this.taskOccurrenceId,
    required this.executionSessionId,
    required this.metricType,
    required this.unit,
  });

  final String taskOccurrenceId;
  final String executionSessionId;
  final String metricType;
  final String unit;
  final Set<String> recordIds = {};
  final Set<String> sources = {};
  final Map<String, Set<String>> sourceRecordIds = {};
  final Map<String, double> recordFractions = {};
  double additiveValue = 0;
  double heartRateWeightedValue = 0;
  double heartRateWeight = 0;
  DateTime? latestRecordAt;
  DateTime? intervalStartAt;
  DateTime? intervalEndAt;

  void add({
    required String recordId,
    required String source,
    required double numeric,
    required double fraction,
    required bool isHeartRate,
    required DateTime latestRecordAt,
    required DateTime overlapStart,
    required DateTime overlapEnd,
  }) {
    recordIds.add(recordId);
    sources.add(source);
    sourceRecordIds.putIfAbsent(source, () => <String>{}).add(recordId);
    recordFractions.update(
      recordId,
      (current) => (current + fraction).clamp(0.0, 1.0),
      ifAbsent: () => fraction,
    );
    if (isHeartRate) {
      heartRateWeightedValue += numeric * fraction;
      heartRateWeight += fraction;
    } else {
      additiveValue += numeric * fraction;
    }
    if (this.latestRecordAt == null ||
        latestRecordAt.isAfter(this.latestRecordAt!)) {
      this.latestRecordAt = latestRecordAt;
    }
    if (intervalStartAt == null || overlapStart.isBefore(intervalStartAt!)) {
      intervalStartAt = overlapStart;
    }
    if (intervalEndAt == null || overlapEnd.isAfter(intervalEndAt!)) {
      intervalEndAt = overlapEnd;
    }
  }

  TaskHealthSummary toSummary({
    required int rawRecordCount,
    required HealthInterval refreshWindow,
    required DateTime importedAt,
  }) {
    final averageFraction = recordFractions.isEmpty
        ? 0.0
        : (recordFractions.values.fold<double>(0, (sum, value) => sum + value) /
                  recordFractions.length)
              .clamp(0.0, 1.0);
    final proportional = recordFractions.values.any((value) => value < 0.999);
    final rawValue = metricType == 'average_heart_rate'
        ? heartRateWeightedValue / math.max(heartRateWeight, 0.000001)
        : additiveValue;
    final value = metricType == 'steps' ? rawValue.round() : rawValue;
    return TaskHealthSummary(
      taskOccurrenceId: taskOccurrenceId,
      executionSessionId: executionSessionId,
      metricType: metricType,
      value: value,
      unit: unit,
      recordCount: recordIds.length,
      rawRecordCount: math.max(rawRecordCount, recordIds.length),
      sourceApplications: (sources.toList()..sort()),
      sourceRecordCounts: Map.unmodifiable(
        sourceRecordIds.map((source, ids) => MapEntry(source, ids.length)),
      ),
      latestRecordAt: latestRecordAt ?? intervalEndAt!,
      importedAt: importedAt.toUtc(),
      windowStartAt: refreshWindow.start,
      windowEndAt: refreshWindow.end,
      intervalStartAt: intervalStartAt!,
      intervalEndAt: intervalEndAt!,
      allocationMethod: proportional ? 'proportional_overlap' : 'exact_record',
      estimated: proportional,
      provenance: 'health_connect_record_overlap',
      overlapFraction: averageFraction,
    );
  }
}

bool _isAdditiveMetric(HealthDataType type) =>
    type == HealthDataType.STEPS ||
    type == HealthDataType.DISTANCE_DELTA ||
    type == HealthDataType.SLEEP_ASLEEP ||
    type == HealthDataType.ACTIVE_ENERGY_BURNED;

double? _numeric(HealthDataPoint point) {
  final value = point.value;
  return value is NumericHealthValue ? value.numericValue.toDouble() : null;
}

String _recordIdentity(HealthDataPoint point) {
  final uuid = point.uuid.trim();
  if (uuid.isNotEmpty) return '${point.type.name}|$uuid';
  return [
    point.type.name,
    point.sourceId.trim().toLowerCase(),
    point.sourceName.trim().toLowerCase(),
    point.dateFrom.toUtc().toIso8601String(),
    point.dateTo.toUtc().toIso8601String(),
    _numeric(point)?.toString() ?? point.value.toString(),
  ].join('|');
}

HealthInterval _pointInterval(HealthDataPoint point) {
  final start = point.dateFrom;
  final rawEnd = point.dateTo;
  return HealthInterval(
    start,
    rawEnd.isAfter(start) ? rawEnd : start.add(const Duration(milliseconds: 1)),
  );
}

List<HealthInterval> _subtract(
  HealthInterval original,
  List<HealthInterval> coverage,
) {
  final result = <HealthInterval>[];
  var cursor = original.start;
  for (final covered in coverage) {
    if (!covered.end.isAfter(cursor)) continue;
    if (!covered.start.isBefore(original.end)) break;
    if (covered.start.isAfter(cursor)) {
      final gapEnd = covered.start.isBefore(original.end)
          ? covered.start
          : original.end;
      if (cursor.isBefore(gapEnd)) {
        result.add(HealthInterval(cursor, gapEnd));
      }
    }
    if (covered.end.isAfter(cursor)) cursor = covered.end;
    if (!cursor.isBefore(original.end)) break;
  }
  if (cursor.isBefore(original.end)) {
    result.add(HealthInterval(cursor, original.end));
  }
  return result;
}

List<HealthInterval> _mergeIntervals(List<HealthInterval> intervals) {
  if (intervals.isEmpty) return const [];
  final sorted = [...intervals]
    ..sort((left, right) => left.start.compareTo(right.start));
  final result = <HealthInterval>[];
  var start = sorted.first.start;
  var end = sorted.first.end;
  for (final interval in sorted.skip(1)) {
    if (!interval.start.isAfter(end)) {
      if (interval.end.isAfter(end)) end = interval.end;
      continue;
    }
    result.add(HealthInterval(start, end));
    start = interval.start;
    end = interval.end;
  }
  result.add(HealthInterval(start, end));
  return result;
}
