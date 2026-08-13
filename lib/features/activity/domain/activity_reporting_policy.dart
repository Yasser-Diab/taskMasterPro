import 'dart:convert';

import '../../../core/database/app_database.dart';

/// One eligibility policy for every derived Activity metric.
///
/// Raw rows remain available for diagnostics, but TaskMaster Pro's own usage
/// and periods whose latest user decision is `system_activity` must never be
/// credited to work, coaching, reports, or roadmap forecasts.
bool isSystemActivityClassification(String? classification) =>
    classification?.trim().toLowerCase() == 'system_activity';

bool activityClassificationAllowsCredit(String? classification) =>
    !isSystemActivityClassification(classification);

bool isTaskMasterActivityIdentity(String? value) {
  if (value == null) return false;
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceAll(' ', '');
  return normalized == 'pro.taskmaster.app' ||
      normalized == 'taskmaster_pro.exe' ||
      normalized == 'taskmasterpro.exe';
}

bool isTaskMasterSelfActivity(LocalActivitySegment segment) {
  if (isTaskMasterActivityIdentity(segment.processName)) return true;
  try {
    final decoded = jsonDecode(segment.rawMetadataJson);
    if (decoded is! Map) return false;
    return isTaskMasterActivityIdentity(decoded['package_name']?.toString()) ||
        isTaskMasterActivityIdentity(decoded['packageName']?.toString()) ||
        isTaskMasterActivityIdentity(decoded['process_name']?.toString());
  } on FormatException {
    return false;
  }
}

Map<String, LocalAttribution> latestActivityAttributionBySegment(
  Iterable<LocalAttribution> attributions,
) {
  final result = <String, LocalAttribution>{};
  for (final attribution in attributions) {
    if (attribution.deletedAt != null) continue;
    final existing = result[attribution.activitySegmentId];
    if (existing == null || _isNewerAttribution(attribution, existing)) {
      result[attribution.activitySegmentId] = attribution;
    }
  }
  return result;
}

bool _isNewerAttribution(LocalAttribution candidate, LocalAttribution current) {
  final updatedComparison = candidate.updatedAt.compareTo(current.updatedAt);
  if (updatedComparison != 0) return updatedComparison > 0;
  if (candidate.revision != current.revision) {
    return candidate.revision > current.revision;
  }
  if (candidate.confirmedByUser != current.confirmedByUser) {
    return candidate.confirmedByUser;
  }
  return candidate.id.compareTo(current.id) > 0;
}

Set<String> excludedActivitySegmentIds({
  required Iterable<LocalActivitySegment> segments,
  required Iterable<LocalAttribution> attributions,
}) {
  final latest = latestActivityAttributionBySegment(attributions);
  return {
    for (final segment in segments)
      if (isTaskMasterSelfActivity(segment) ||
          isSystemActivityClassification(latest[segment.id]?.classification))
        segment.id,
  };
}

List<LocalActivitySegment> reportableActivitySegments({
  required Iterable<LocalActivitySegment> segments,
  required Iterable<LocalAttribution> attributions,
}) {
  final source = segments.toList(growable: false);
  final excluded = excludedActivitySegmentIds(
    segments: source,
    attributions: attributions,
  );
  return source
      .where((segment) => !excluded.contains(segment.id))
      .toList(growable: false);
}
