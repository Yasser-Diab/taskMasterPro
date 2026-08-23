import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/activity/data/activity_privacy_policy.dart';

void main() {
  test('manual break transport keeps only the server privacy allowlist', () {
    final metadata = privacySafeManualBreakSyncMetadata(
      sourceType: manualBreakActivitySourceType,
      localMetadata: const <String, Object?>{
        'manual_break_check_in': true,
        'manual_break_category': 'break_activity_sport',
        'manual_break_label': 'Stretching',
        'source_task_id': 'task-id',
        'source_session_id': 'session-id',
        'source_runtime_state': 'break',
        'prompt_version': 1,
        'private_field': 'must stay local',
      },
    );

    expect(metadata, isNotNull);
    expect(metadata!['normalized'], isTrue);
    expect(metadata['raw_samples_included'], isFalse);
    expect(metadata['manual_break_category'], 'break_activity_sport');
    expect(metadata['prompt_version'], isNull);
    expect(metadata['private_field'], isNull);
  });

  test('manual break transport rejects unapproved or malformed evidence', () {
    expect(
      privacySafeManualBreakSyncMetadata(
        sourceType: manualBreakActivitySourceType,
        localMetadata: const <String, Object?>{
          'manual_break_check_in': true,
          'manual_break_category': 'raw_device_activity',
        },
      ),
      isNull,
    );
    expect(
      isApprovedPrivacySafeManualBreak(
        sourceType: manualBreakActivitySourceType,
        localMetadata: const <String, Object?>{
          'manual_break_check_in': true,
          'manual_break_category': 'break_activity_sport',
        },
        reviewReason: breakActivityReviewReason,
        reviewStatus: 'confirmed',
        wasReviewed: true,
        attributionClassification: 'break_activity_reading',
        attributionConfirmed: true,
      ),
      isFalse,
      reason: 'the approved attribution must match the explicit category',
    );
  });

  test('missing privacy data fails closed to local-only Activity', () {
    final policy = ActivityPrivacyPolicy.fromRemoteRow(null);

    expect(policy.storageMode, ActivityStorageMode.localOnly);
    expect(policy.allowsDetailedActivityUploadFor(true), isFalse);
  });

  test('a legacy detailed preference cannot override local-only privacy', () {
    final policy = ActivityPrivacyPolicy.fromRemoteRow({
      'activity_storage': 'local_only',
      'data': {'detailed_activity_sync_opt_in': true},
    });

    expect(policy.hasCanonicalDetailedActivityConsent, isFalse);
    expect(policy.allowsDetailedActivityUploadFor(true), isFalse);
  });

  test('detailed Activity requires both synchronized storage and consent', () {
    final missingConsent = ActivityPrivacyPolicy.fromRemoteRow({
      'activity_storage': 'synchronized',
      'data': const <String, Object?>{},
    });
    final consented = ActivityPrivacyPolicy.fromRemoteRow({
      'activity_storage': 'synchronized',
      'data': {'detailed_activity_sync_opt_in': true},
    });

    expect(missingConsent.allowsDetailedActivityUploadFor(true), isFalse);
    expect(consented.allowsDetailedActivityUploadFor(false), isFalse);
    expect(consented.allowsDetailedActivityUploadFor(true), isTrue);
  });
}
