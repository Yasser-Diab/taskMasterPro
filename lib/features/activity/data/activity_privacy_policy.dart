import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

const manualBreakActivitySourceType = 'manual_break';
const breakActivityReviewReason = 'break_without_device_activity';
const breakActivityClassifications = <String>{
  'break_activity_reading',
  'break_activity_sport',
  'break_activity_relaxing',
  'break_activity_drink',
  'break_activity_other',
};

/// Returns the exact privacy-safe metadata that may leave the device for an
/// explicit break check-in, or `null` when the local evidence is incomplete.
///
/// Local metadata may contain bookkeeping such as `prompt_version`; the
/// returned map deliberately allowlists only the fields accepted by the
/// server privacy trigger.
Map<String, Object?>? privacySafeManualBreakSyncMetadata({
  required String sourceType,
  required Map<String, Object?> localMetadata,
}) {
  if (sourceType != manualBreakActivitySourceType ||
      localMetadata['manual_break_check_in'] != true) {
    return null;
  }
  final category = localMetadata['manual_break_category'];
  if (category is! String || !breakActivityClassifications.contains(category)) {
    return null;
  }
  final labelValue = localMetadata['manual_break_label'];
  if (labelValue != null &&
      (labelValue is! String || labelValue.runes.length > 120)) {
    return null;
  }

  String? safeText(String key) {
    final value = localMetadata[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  final label = labelValue is String && labelValue.isNotEmpty
      ? labelValue
      : null;
  final result = <String, Object?>{
    'normalized': true,
    'raw_samples_included': false,
    'manual_break_check_in': true,
    'manual_break_category': category,
  };
  for (final key in const <String>[
    'source_task_id',
    'source_session_id',
    'source_runtime_state',
  ]) {
    final value = safeText(key);
    if (value != null) result[key] = value;
  }
  if (label != null) result['manual_break_label'] = label;
  return result;
}

bool isApprovedPrivacySafeManualBreak({
  required String sourceType,
  required Map<String, Object?> localMetadata,
  required String reviewReason,
  required String reviewStatus,
  required bool wasReviewed,
  required String attributionClassification,
  required bool attributionConfirmed,
}) {
  final safeMetadata = privacySafeManualBreakSyncMetadata(
    sourceType: sourceType,
    localMetadata: localMetadata,
  );
  return safeMetadata != null &&
      reviewReason == breakActivityReviewReason &&
      reviewStatus == 'confirmed' &&
      wasReviewed &&
      attributionConfirmed &&
      attributionClassification == safeMetadata['manual_break_category'];
}

/// The server-owned storage choice for captured device Activity.
///
/// `user_settings.data` contains presentation preferences, but it must never
/// overrule `privacy_settings` when deciding whether raw device usage can
/// leave this device.  A missing or unreadable privacy projection is treated
/// as local-only deliberately.
enum ActivityStorageMode { disabled, localOnly, synchronized }

class ActivityPrivacyPolicy {
  const ActivityPrivacyPolicy({
    required this.storageMode,
    required this.hasExplicitDetailedSyncOptIn,
  });

  const ActivityPrivacyPolicy.localOnly()
    : storageMode = ActivityStorageMode.localOnly,
      hasExplicitDetailedSyncOptIn = false;

  final ActivityStorageMode storageMode;
  final bool hasExplicitDetailedSyncOptIn;

  bool get hasCanonicalDetailedActivityConsent {
    return storageMode == ActivityStorageMode.synchronized &&
        hasExplicitDetailedSyncOptIn;
  }

  /// Raw application/window/site observations may leave this device only
  /// after the canonical privacy record and the local preference both agree.
  bool allowsDetailedActivityUpload(LocalAppSetting? settings) {
    return allowsDetailedActivityUploadFor(
      settings?.detailedActivitySyncEnabled == true,
    );
  }

  bool allowsDetailedActivityUploadFor(bool localPreferenceEnabled) {
    return hasCanonicalDetailedActivityConsent && localPreferenceEnabled;
  }

  /// A user-confirmed, privacy-safe contribution remains useful across
  /// devices. It is not raw Activity history and is allowed in local-only
  /// mode unless the user disabled Activity sharing entirely.
  bool allowsApprovedContributionUpload(LocalAppSetting? settings) {
    return storageMode != ActivityStorageMode.disabled &&
        settings?.activitySyncEnabled != false;
  }

  static ActivityPrivacyPolicy fromRemoteRow(Map<String, Object?>? row) {
    if (row == null) return const ActivityPrivacyPolicy.localOnly();
    final data = _map(row['data']);
    return ActivityPrivacyPolicy(
      storageMode: _storageMode(row['activity_storage'] as String?),
      hasExplicitDetailedSyncOptIn:
          data['detailed_activity_sync_opt_in'] == true,
    );
  }

  static ActivityPrivacyPolicy fromLocalRecord(LocalEntityRecord? record) {
    if (record == null || record.deletedAt != null) {
      return const ActivityPrivacyPolicy.localOnly();
    }
    try {
      final decoded = jsonDecode(record.dataJson);
      if (decoded is Map) {
        return fromRemoteRow(
          Map<String, Object?>.from(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    } on FormatException {
      // A malformed local cache must fail closed rather than upload Activity.
    }
    return const ActivityPrivacyPolicy.localOnly();
  }

  static Future<ActivityPrivacyPolicy> load(
    AppDatabase database,
    String userId,
  ) async {
    final record =
        await (database.select(database.localEntityRecords)
              ..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.entityType.equals('privacy_settings') &
                    row.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    return fromLocalRecord(record);
  }

  static ActivityStorageMode _storageMode(String? value) {
    return switch (value) {
      'disabled' => ActivityStorageMode.disabled,
      'synchronized' => ActivityStorageMode.synchronized,
      _ => ActivityStorageMode.localOnly,
    };
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
}
