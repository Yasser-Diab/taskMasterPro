import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/activity/data/activity_privacy_policy.dart';

void main() {
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
