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
  final normalizedPath = value.trim().toLowerCase().replaceAll('\\', '/');
  if (normalizedPath.isEmpty) return false;

  // Old Windows captures used both the executable name and the visible
  // product name. Android history has likewise existed with the application
  // id and the Kotlin namespace. Compare exact normalized identity tokens so
  // those legacy spellings are recognized without treating a window title
  // which merely mentions TaskMaster Pro as the app itself.
  final pathParts = normalizedPath.split('/');
  // A process identity may be either a visible product name or a full
  // executable path. Only compare the complete value and its basename: a
  // different executable living inside a folder named "TaskMaster Pro" must
  // not be mistaken for this application.
  final candidates = <String>{normalizedPath, pathParts.last};
  for (final candidate in candidates) {
    final token = candidate.replaceAll(RegExp('[^a-z0-9]'), '');
    if (const {
      'taskmasterpro',
      'taskmasterproexe',
      'protaskmasterapp',
      'protaskmastertaskmasterpro',
    }.contains(token)) {
      return true;
    }
  }
  return false;
}

bool isTaskMasterSelfActivity(LocalActivitySegment segment) {
  if (isTaskMasterActivityIdentity(segment.processName)) return true;
  try {
    final decoded = jsonDecode(segment.rawMetadataJson);
    return _metadataContainsTaskMasterIdentity(decoded);
  } on FormatException {
    return false;
  }
}

const _activityIdentityMetadataKeys = <String>{
  'application',
  'application_name',
  'applicationname',
  'executable',
  'executable_name',
  'executablename',
  'executable_path',
  'package',
  'package_name',
  'packagename',
  'process',
  'process_name',
  'processname',
  'process_path',
};

bool _metadataContainsTaskMasterIdentity(Object? value) {
  if (value is! Map) return false;
  for (final entry in value.entries) {
    final key = entry.key.toString().trim().toLowerCase().replaceAll('-', '_');
    if (_activityIdentityMetadataKeys.contains(key) &&
        isTaskMasterActivityIdentity(entry.value?.toString())) {
      return true;
    }
    // Synchronized rows may wrap the same privacy-safe metadata in `data` or
    // `raw_metadata`. Only inspect nested maps; arbitrary text is never used
    // as an application identity.
    if (entry.value is Map &&
        _metadataContainsTaskMasterIdentity(entry.value)) {
      return true;
    }
  }
  return false;
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
  // Revision is the canonical cross-device order. A wall clock can be ahead
  // or behind, so updatedAt may only break a tie at the same revision.
  if (candidate.revision != current.revision) {
    return candidate.revision > current.revision;
  }
  final updatedComparison = candidate.updatedAt.compareTo(current.updatedAt);
  if (updatedComparison != 0) return updatedComparison > 0;
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
