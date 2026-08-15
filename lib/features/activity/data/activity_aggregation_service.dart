import 'dart:convert';
import 'dart:isolate';

import 'package:path/path.dart' as path;

import '../../../core/database/app_database.dart';
import '../../tasks/data/installed_application_service.dart';
import '../domain/activity_reporting_policy.dart';

enum ActivityTimeKind { active, idle, uncertain }

class ActivityPeriodSummary {
  const ActivityPeriodSummary({
    required this.segmentId,
    required this.startedAt,
    required this.endedAt,
    required this.durationMs,
    required this.kind,
    required this.detail,
    required this.classification,
    required this.targetId,
    required this.isBreak,
    required this.isCrossTask,
  });

  final String segmentId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMs;
  final ActivityTimeKind kind;
  final String detail;
  final String classification;
  final String? targetId;
  final bool isBreak;
  final bool isCrossTask;
}

class ActivityGroupSummary {
  const ActivityGroupSummary({
    required this.key,
    required this.name,
    required this.sourceType,
    required this.totalMs,
    required this.activeMs,
    required this.idleMs,
    required this.uncertainMs,
    required this.classification,
    required this.relatedTaskId,
    required this.periods,
    required this.containsBreak,
    required this.containsCrossTask,
    required this.suggestionSource,
  });

  final String key;
  final String name;
  final String sourceType;
  final int totalMs;
  final int activeMs;
  final int idleMs;
  final int uncertainMs;
  final String classification;
  final String? relatedTaskId;
  final List<ActivityPeriodSummary> periods;
  final bool containsBreak;
  final bool containsCrossTask;
  final String? suggestionSource;

  DateTime get firstDetected => periods
      .map((period) => period.startedAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get lastDetected => periods
      .map((period) => period.endedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

class ActivityAggregation {
  const ActivityAggregation({
    required this.groups,
    required this.totalMs,
    required this.activeMs,
    required this.idleMs,
    required this.uncertainMs,
    required this.needsReviewMs,
  });

  final List<ActivityGroupSummary> groups;
  final int totalMs;
  final int activeMs;
  final int idleMs;
  final int uncertainMs;
  final int needsReviewMs;
}

class ActivityAggregationService {
  Future<ActivityAggregation> aggregate({
    required List<LocalActivitySegment> segments,
    required List<LocalAttribution> attributions,
    required DateTime rangeStartUtc,
    required DateTime rangeEndUtc,
    String? taskId,
  }) async {
    final attributionBySegment = <String, List<Map<String, Object?>>>{};
    for (final attribution in latestActivityAttributionBySegment(
      attributions,
    ).values) {
      attributionBySegment
          .putIfAbsent(attribution.activitySegmentId, () => [])
          .add({
            'classification': attribution.classification,
            'target_id': attribution.targetId,
            'status': attribution.attributionStatus,
            'confidence': attribution.confidence,
            'suggested_by': attribution.confirmedByUser
                ? 'user_confirmed'
                : attribution.attributionStatus == 'automatic'
                ? 'learned_from_usage'
                : 'taskmaster_suggestion',
          });
    }
    final input = <Map<String, Object?>>[];
    for (final segment in segments) {
      if (isTaskMasterSelfActivity(segment)) continue;
      final started = segment.startedAt.isBefore(rangeStartUtc)
          ? rangeStartUtc
          : segment.startedAt;
      final ended = segment.endedAt.isAfter(rangeEndUtc)
          ? rangeEndUtc
          : segment.endedAt;
      if (!ended.isAfter(started)) continue;
      input.add({
        'id': segment.id,
        'device_event_id': segment.deviceEventId,
        'started_at': started.microsecondsSinceEpoch,
        'ended_at': ended.microsecondsSinceEpoch,
        'source_type': segment.sourceType,
        'process_name': segment.processName,
        'window_title': segment.windowTitle,
        'domain': segment.domain,
        'url': segment.url,
        'page_title': segment.pageTitle,
        'idle_state': segment.idleState,
        'confidence': segment.captureConfidence ?? 0,
        'metadata': segment.rawMetadataJson,
        'attributions':
            attributionBySegment[segment.id] ?? const <Map<String, Object?>>[],
      });
    }
    final result = await Isolate.run(
      () => _aggregateSerializable(input, taskId),
    );
    final resultGroups = (result['groups'] as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList(growable: false);
    return ActivityAggregation(
      groups: [
        for (final group in resultGroups)
          ActivityGroupSummary(
            key: group['key'] as String,
            name: group['name'] as String,
            sourceType: group['source_type'] as String,
            totalMs: group['total_ms'] as int,
            activeMs: group['active_ms'] as int,
            idleMs: group['idle_ms'] as int,
            uncertainMs: group['uncertain_ms'] as int,
            classification: group['classification'] as String,
            relatedTaskId: group['related_task_id'] as String?,
            periods: [
              for (final rawPeriod in group['periods'] as List)
                if (rawPeriod case final Map period)
                  ActivityPeriodSummary(
                    segmentId: period['segment_id'] as String,
                    startedAt: DateTime.fromMicrosecondsSinceEpoch(
                      period['started_at'] as int,
                      isUtc: true,
                    ),
                    endedAt: DateTime.fromMicrosecondsSinceEpoch(
                      period['ended_at'] as int,
                      isUtc: true,
                    ),
                    durationMs: period['duration_ms'] as int,
                    kind: ActivityTimeKind.values[period['kind'] as int],
                    detail: period['detail'] as String,
                    classification: period['classification'] as String,
                    targetId: period['target_id'] as String?,
                    isBreak: period['is_break'] as bool,
                    isCrossTask: period['is_cross_task'] as bool,
                  ),
            ],
            containsBreak: group['contains_break'] as bool,
            containsCrossTask: group['contains_cross_task'] as bool,
            suggestionSource: group['suggestion_source'] as String?,
          ),
      ],
      totalMs: result['total_ms'] as int,
      activeMs: result['active_ms'] as int,
      idleMs: result['idle_ms'] as int,
      uncertainMs: result['uncertain_ms'] as int,
      needsReviewMs: result['needs_review_ms'] as int,
    );
  }

  static Map<String, Object?> _aggregateSerializable(
    List<Map<String, Object?>> inputs,
    String? taskId,
  ) {
    final deduplicated = <String, Map<String, Object?>>{};
    for (final input in inputs) {
      final eventId = input['device_event_id'] as String;
      final existing = deduplicated[eventId];
      if (existing == null ||
          (input['confidence'] as num) > (existing['confidence'] as num)) {
        deduplicated[eventId] = input;
      }
    }
    final segments = deduplicated.values.toList();
    final boundaries = <int>{};
    for (final segment in segments) {
      boundaries
        ..add(segment['started_at'] as int)
        ..add(segment['ended_at'] as int);
    }
    final orderedBoundaries = boundaries.toList()..sort();
    final periodDurations = <String, int>{};
    final periodKinds = <String, List<int>>{};

    for (var index = 0; index + 1 < orderedBoundaries.length; index++) {
      final sliceStart = orderedBoundaries[index];
      final sliceEnd = orderedBoundaries[index + 1];
      if (sliceEnd <= sliceStart) continue;
      final candidates = segments.where(
        (segment) =>
            (segment['started_at'] as int) < sliceEnd &&
            (segment['ended_at'] as int) > sliceStart,
      );
      if (candidates.isEmpty) continue;
      final winner = candidates.reduce((a, b) {
        final aSpecificity = _specificity(a);
        final bSpecificity = _specificity(b);
        if (aSpecificity != bSpecificity) {
          return aSpecificity > bSpecificity ? a : b;
        }
        return (a['confidence'] as num) >= (b['confidence'] as num) ? a : b;
      });
      final durationMs = (sliceEnd - sliceStart) ~/ 1000;
      final id = winner['id'] as String;
      periodDurations[id] = (periodDurations[id] ?? 0) + durationMs;
      final kind = _kind(winner);
      final values = periodKinds.putIfAbsent(id, () => [0, 0, 0]);
      values[kind] += durationMs;
    }

    final groupMaps = <String, Map<String, Object?>>{};
    for (final segment in segments) {
      final allocatedMs = periodDurations[segment['id']] ?? 0;
      if (allocatedMs <= 0) continue;
      final identity = _identity(segment);
      final rawAttributions = segment['attributions'] as List;
      final attribution = _bestAttribution(
        rawAttributions
            .map((value) => Map<String, Object?>.from(value as Map))
            .toList(growable: false),
        taskId,
      );
      final classification =
          attribution?['classification'] as String? ?? 'unclassified';
      final targetId = attribution?['target_id'] as String?;
      final kinds = periodKinds[segment['id']] ?? const [0, 0, 0];
      // One application can contain both genuine work and OS-owned periods.
      // Keep those decisions in separate audit groups so a longer useful
      // period can never cause a System period to leak back into totals.
      final classifiedIdentityKey = '${identity.$1}::$classification';
      final group = groupMaps.putIfAbsent(
        classifiedIdentityKey,
        () => {
          'key': classifiedIdentityKey,
          'name': identity.$2,
          'source_type': identity.$3,
          'total_ms': 0,
          'active_ms': 0,
          'idle_ms': 0,
          'uncertain_ms': 0,
          'classifications': <String, int>{},
          'targets': <String, int>{},
          'suggestion_sources': <String, int>{},
          'periods': <Map<String, Object?>>[],
          'contains_break': false,
          'contains_cross_task': false,
        },
      );
      group['total_ms'] = (group['total_ms'] as int) + allocatedMs;
      group['active_ms'] = (group['active_ms'] as int) + kinds[0];
      group['idle_ms'] = (group['idle_ms'] as int) + kinds[1];
      group['uncertain_ms'] = (group['uncertain_ms'] as int) + kinds[2];
      final classifications = group['classifications'] as Map<String, int>;
      classifications[classification] =
          (classifications[classification] ?? 0) + allocatedMs;
      if (targetId != null) {
        final targets = group['targets'] as Map<String, int>;
        targets[targetId] = (targets[targetId] ?? 0) + allocatedMs;
      }
      final suggestionSource = attribution?['suggested_by'] as String?;
      if (suggestionSource != null) {
        final sources = group['suggestion_sources'] as Map<String, int>;
        sources[suggestionSource] =
            (sources[suggestionSource] ?? 0) + allocatedMs;
      }
      final metadata = _metadata(segment);
      final sourceTaskId = metadata['source_task_id'] as String?;
      final isBreak = metadata['source_runtime_state'] == 'break';
      final isCrossTask =
          sourceTaskId != null && targetId != null && sourceTaskId != targetId;
      group['contains_break'] = (group['contains_break'] as bool) || isBreak;
      group['contains_cross_task'] =
          (group['contains_cross_task'] as bool) || isCrossTask;
      (group['periods'] as List<Map<String, Object?>>).add({
        'segment_id': segment['id'],
        'started_at': segment['started_at'],
        'ended_at': segment['ended_at'],
        'duration_ms': allocatedMs,
        'kind': _kind(segment),
        'detail': _detail(segment),
        'classification': classification,
        'target_id': targetId,
        'is_break': isBreak,
        'is_cross_task': isCrossTask,
      });
    }

    var total = 0;
    var active = 0;
    var idle = 0;
    var uncertain = 0;
    var needsReview = 0;
    final groups = <Map<String, Object?>>[];
    for (final group in groupMaps.values) {
      final classifications =
          group.remove('classifications') as Map<String, int>;
      final targets = group.remove('targets') as Map<String, int>;
      final suggestionSources =
          group.remove('suggestion_sources') as Map<String, int>;
      final classification = classifications.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      group['classification'] = classification.key;
      group['related_task_id'] = targets.isEmpty
          ? null
          : targets.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      group['suggestion_source'] = suggestionSources.isEmpty
          ? null
          : suggestionSources.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
      final periods = group['periods'] as List<Map<String, Object?>>;
      periods.sort(
        (a, b) => (a['started_at'] as int).compareTo(b['started_at'] as int),
      );
      // System periods remain in the raw grouped audit, clearly labelled, but
      // cannot inflate any Activity metric.
      if (!isSystemActivityClassification(classification.key)) {
        total += group['total_ms'] as int;
        active += group['active_ms'] as int;
        idle += group['idle_ms'] as int;
        uncertain += group['uncertain_ms'] as int;
      }
      if (const {
        'unclassified',
        'unknown',
        'requires_review',
        'distraction',
        'unrelated',
      }.contains(classification.key)) {
        needsReview += group['total_ms'] as int;
      }
      groups.add(group);
    }
    groups.sort(
      (a, b) => (b['total_ms'] as int).compareTo(a['total_ms'] as int),
    );
    return {
      'groups': groups,
      'total_ms': total,
      'active_ms': active,
      'idle_ms': idle,
      'uncertain_ms': uncertain,
      'needs_review_ms': needsReview,
    };
  }

  static Map<String, Object?>? _bestAttribution(
    List<Map<String, Object?>> values,
    String? taskId,
  ) {
    if (values.isEmpty) return null;
    if (taskId != null) {
      final taskValues = values.where((value) => value['target_id'] == taskId);
      if (taskValues.isNotEmpty) return taskValues.first;
    }
    values.sort((a, b) {
      int rank(Map<String, Object?> value) => switch (value['status']) {
        'confirmed' || 'automatic' => 3,
        'rejected' || 'ignored' => 2,
        _ => 1,
      };
      final statusOrder = rank(b).compareTo(rank(a));
      if (statusOrder != 0) return statusOrder;
      return ((b['confidence'] as num?) ?? 0).compareTo(
        (a['confidence'] as num?) ?? 0,
      );
    });
    return values.first;
  }

  static int _specificity(Map<String, Object?> segment) {
    if ((segment['domain'] as String?)?.isNotEmpty == true) return 40;
    final metadata = _metadata(segment);
    if ((metadata['resource_id'] as String?)?.isNotEmpty == true ||
        (metadata['document_path'] as String?)?.isNotEmpty == true) {
      return 35;
    }
    if ((metadata['package_name'] as String?)?.isNotEmpty == true) return 30;
    if ((segment['process_name'] as String?)?.isNotEmpty == true) return 20;
    return 10;
  }

  static (String, String, String) _identity(Map<String, Object?> segment) {
    final domain = (segment['domain'] as String?)?.trim().toLowerCase();
    if (domain != null && domain.isNotEmpty) {
      return ('domain:$domain', domain, 'website');
    }
    final metadata = _metadata(segment);
    final document =
        (metadata['document_path'] as String?) ??
        (metadata['resource_name'] as String?);
    if (document != null && document.trim().isNotEmpty) {
      final normalized = document.replaceAll('\\', '/').toLowerCase();
      return (
        'document:$normalized',
        path.basename(document.replaceAll('\\', '/')),
        'document',
      );
    }
    final packageName = (metadata['package_name'] as String?)?.toLowerCase();
    if (packageName != null && packageName.isNotEmpty) {
      return (
        'package:$packageName',
        _friendlyName(packageName),
        'application',
      );
    }
    final process = (segment['process_name'] as String?)?.trim();
    if (process != null && process.isNotEmpty) {
      final executable = path
          .basename(process.replaceAll('\\', '/'))
          .toLowerCase();
      return (
        'application:$executable',
        _friendlyName(executable),
        'application',
      );
    }
    return ('other:unknown', 'Other activity', 'unknown');
  }

  static String _friendlyName(String value) {
    return normalizedApplicationDisplayName(value);
  }

  static int _kind(Map<String, Object?> segment) {
    final idle = (segment['idle_state'] as String?)?.toLowerCase();
    if (idle == 'idle' ||
        idle == 'confirmed_idle' ||
        idle == 'technical_idle') {
      return ActivityTimeKind.idle.index;
    }
    if (idle == 'unknown_idle' || idle == 'uncertain') {
      return ActivityTimeKind.uncertain.index;
    }
    return ActivityTimeKind.active.index;
  }

  static String _detail(Map<String, Object?> segment) {
    return (segment['domain'] as String?) ??
        (segment['page_title'] as String?) ??
        (segment['window_title'] as String?) ??
        (segment['process_name'] as String?) ??
        'Unknown activity';
  }

  static Map<String, Object?> _metadata(Map<String, Object?> segment) {
    try {
      final decoded = jsonDecode(segment['metadata'] as String? ?? '{}');
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    } catch (_) {
      return const {};
    }
  }
}
