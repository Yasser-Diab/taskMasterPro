import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

@immutable
class InstalledApplication {
  const InstalledApplication({
    required this.identifier,
    required this.displayName,
    required this.platform,
  });

  final String identifier;
  final String displayName;
  final String platform;
}

String normalizeApplicationIdentifier(String value) =>
    value.trim().toLowerCase();

/// Mirrors `private.normalize_application_key` in the canonical database.
///
/// Activity discovery and task connections must send this value with the
/// catalog create itself. Relying on a later server-side repair leaves a fresh
/// install with a permanently rejected outbox command because the canonical
/// column is intentionally NOT NULL.
String normalizedApplicationKey(String value) {
  final normalized = normalizeApplicationIdentifier(
    value,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'unknown' : normalized;
}

/// Converts a technical package, executable, or legacy activity identifier
/// into the stable user-facing product name used everywhere resources are
/// rendered. Raw identifiers remain available for matching and diagnostics,
/// but must never be the primary label of a connected application.
String normalizedApplicationDisplayName(String? value) {
  final original = value?.trim() ?? '';
  if (original.isEmpty) return '';
  final normalizedPath = original.replaceAll(r'\', '/').trim();
  final rawTail = normalizedPath.split('/').last;
  final roleTail = rawTail.split('|').last.trim();
  final key = roleTail.toLowerCase();

  const known = <String, String>{
    'chrome': 'Google Chrome',
    'chrome.exe': 'Google Chrome',
    'exe.chrome': 'Google Chrome',
    'com.android.chrome': 'Google Chrome',
    'com.google.android.apps.chrome': 'Google Chrome',
    'msedge': 'Microsoft Edge',
    'msedge.exe': 'Microsoft Edge',
    'exe.msedge': 'Microsoft Edge',
    'com.microsoft.emmx': 'Microsoft Edge',
    'code': 'Visual Studio Code',
    'code.exe': 'Visual Studio Code',
    'exe.code': 'Visual Studio Code',
    'com.microsoft.code': 'Visual Studio Code',
    'com.visualstudio.code': 'Visual Studio Code',
    'duolingo': 'Duolingo',
    'com.duolingo': 'Duolingo',
    'com.duolingo.android': 'Duolingo',
    'org.freecodecamp': 'freeCodeCamp',
    'freecodecamp': 'freeCodeCamp',
    'taskmasterpro': 'TaskMaster Pro',
    'taskmaster pro': 'TaskMaster Pro',
    'taskmaster_pro': 'TaskMaster Pro',
    'pro.taskmanager.com': 'TaskMaster Pro',
    'pro.taskmaster.app': 'TaskMaster Pro',
    // Preserve the existing catalog's title-case convention for this label.
    // The important invariant is that the Android identifier is never shown.
    'com.openai.chatgpt': 'Chatgpt',
    'chatgpt': 'Chatgpt',
    'explorer.exe': 'File Explorer',
  };
  final direct = known[key];
  if (direct != null) return direct;

  // A normal friendly label should be retained exactly as supplied. Only
  // technical looking values (package names, executable names, paths or
  // Activity role identifiers) need heuristic normalization.
  final technical =
      key.contains('|') ||
      key.contains('/') ||
      key.endsWith('.exe') ||
      key.startsWith('exe.') ||
      RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+)+$').hasMatch(key);
  if (!technical) return original;

  var candidate = key.replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '');
  final parts = candidate
      .split('.')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isNotEmpty) {
    const namespaceParts = {
      'app',
      'com',
      'exe',
      'io',
      'net',
      'org',
      'pro',
      'www',
    };
    candidate = parts.reversed.firstWhere(
      (part) => !namespaceParts.contains(part),
      orElse: () => parts.last,
    );
  }
  final readable = candidate.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (readable.isEmpty) return original;
  return readable
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

/// Stable canonical identity for the same application discovered by multiple
/// devices before either one has synchronized.
String applicationCatalogIdForTaskConnection({
  required String userId,
  required String platform,
  required String applicationIdentifier,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/application/'
  '${platform.trim().toLowerCase()}/'
  '${normalizeApplicationIdentifier(applicationIdentifier)}',
);

/// Stable semantic identity for one application connected to one task.
///
/// A simultaneous connection on two phones therefore produces one outbox
/// entity and one canonical server link rather than two random rows.
String taskApplicationLinkIdFor({
  required String userId,
  required String taskOccurrenceId,
  required String applicationId,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/task/$taskOccurrenceId/'
  'application/$applicationId',
);

/// Accessible label priority for a normalized task application link.
///
/// The remove action is never rendered against an empty title: even a broken
/// historical relationship has a readable identifier or the localized
/// unknown fallback.
String resolvedApplicationDisplayName({
  String? userOverride,
  String? normalizedName,
  String? displayNameSnapshot,
  String? rawIdentifier,
  required String unknownLabel,
}) {
  final override = userOverride?.trim() ?? '';
  if (override.isNotEmpty) return override;
  for (final candidate in [
    normalizedName,
    displayNameSnapshot,
    rawIdentifier,
  ]) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) {
      final normalized = normalizedApplicationDisplayName(value);
      if (normalized.isNotEmpty) return normalized;
    }
  }
  return unknownLabel;
}

enum TaskApplicationAvailability {
  available,
  androidDeviceRequired,
  windowsDeviceRequired,
  unavailable,
}

TaskApplicationAvailability taskApplicationAvailability({
  required String linkedPlatform,
  required String currentPlatform,
}) {
  final link = linkedPlatform.trim().toLowerCase();
  final current = currentPlatform.trim().toLowerCase();
  if (link.isEmpty || link == current) {
    return TaskApplicationAvailability.available;
  }
  return switch (link) {
    'android' => TaskApplicationAvailability.androidDeviceRequired,
    'windows' => TaskApplicationAvailability.windowsDeviceRequired,
    _ => TaskApplicationAvailability.unavailable,
  };
}

bool applicationCatalogMatches(
  Map<String, Object?> data, {
  required String platform,
  required String identifier,
}) {
  return (data['platform'] as String?)?.trim().toLowerCase() ==
          platform.trim().toLowerCase() &&
      normalizeApplicationIdentifier(
            (data['application_identifier'] as String?) ?? '',
          ) ==
          normalizeApplicationIdentifier(identifier);
}

bool applicationRuleMatchesTask(
  Map<String, Object?> data, {
  required String applicationId,
  required String taskId,
}) {
  return data['application_id'] == applicationId &&
      data['scope_type'] == 'task' &&
      data['scope_id'] == taskId &&
      data['target_type'] == 'task_occurrence' &&
      data['target_id'] == taskId;
}

List<InstalledApplication> filterInstalledApplications(
  Iterable<InstalledApplication> applications,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  final unique = <String, InstalledApplication>{};
  for (final application in applications) {
    final identifier = normalizeApplicationIdentifier(application.identifier);
    if (identifier.isEmpty) continue;
    final displayName = normalizedApplicationDisplayName(
      application.displayName.trim().isEmpty
          ? application.identifier
          : application.displayName,
    );
    if (displayName.isEmpty) continue;
    unique.putIfAbsent(
      '${application.platform.toLowerCase()}|$identifier',
      () => InstalledApplication(
        identifier: application.identifier.trim(),
        displayName: displayName,
        platform: application.platform,
      ),
    );
  }
  final matches = unique.values.where((application) {
    if (normalizedQuery.isEmpty) return true;
    return application.displayName.toLowerCase().contains(normalizedQuery) ||
        application.identifier.toLowerCase().contains(normalizedQuery);
  }).toList();
  matches.sort(
    (left, right) => left.displayName.toLowerCase().compareTo(
      right.displayName.toLowerCase(),
    ),
  );
  return matches;
}

String? androidPackageNameFromApplicationIdentifier(String value) {
  final candidate = normalizeApplicationIdentifier(value).split('|').last;
  final finalSegment = candidate.split('.').last;
  if (const {'app', 'bat', 'cmd', 'com', 'exe', 'msi'}.contains(finalSegment)) {
    return null;
  }
  if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$').hasMatch(candidate)) {
    return null;
  }
  return candidate;
}

class InstalledApplicationService {
  const InstalledApplicationService();

  static const MethodChannel _resourceChannel = MethodChannel(
    'taskmasterpro/resources',
  );

  Future<List<InstalledApplication>> listInstalledApplications() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    try {
      final values = await _resourceChannel.invokeListMethod<Object?>(
        'listInstalledApplications',
      );
      final applications = <InstalledApplication>[];
      for (final value in values ?? const <Object?>[]) {
        if (value is! Map) continue;
        final map = value.map((key, item) => MapEntry(key.toString(), item));
        final identifier = (map['identifier'] as String?)?.trim() ?? '';
        final displayName = normalizedApplicationDisplayName(
          (map['displayName'] as String?)?.trim().isNotEmpty == true
              ? map['displayName'] as String
              : identifier,
        );
        if (identifier.isEmpty || displayName.isEmpty) continue;
        applications.add(
          InstalledApplication(
            identifier: identifier,
            displayName: displayName,
            platform: (map['platform'] as String?)?.trim() ?? 'android',
          ),
        );
      }
      return filterInstalledApplications(applications, '');
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
