import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/onboarding/data/android_permission_setup_store.dart';

void main() {
  test('permission setup storage stays scoped to backend and user', () {
    expect(
      SharedPreferencesAndroidPermissionSetupStore.storageKeyFor(
        projectRef: 'clean-project',
        userId: 'user-a',
      ),
      'taskmaster.android_permission_setup.v1:clean-project:user-a',
    );
    expect(
      SharedPreferencesAndroidPermissionSetupStore.storageKeyFor(
        projectRef: 'clean-project',
        userId: 'user-b',
      ),
      isNot(
        SharedPreferencesAndroidPermissionSetupStore.storageKeyFor(
          projectRef: 'other-project',
          userId: 'user-a',
        ),
      ),
    );
  });

  test('a completed review preserves its local diagnostic snapshot', () {
    final reviewedAt = DateTime.utc(2026, 8, 11, 18, 30);
    final record = AndroidPermissionSetupRecord(
      outcome: AndroidPermissionSetupOutcome.completed,
      reviewedAt: reviewedAt,
      capabilityStates: const {
        'notifications': 'allowed',
        'usageAccess': 'needsSettings',
      },
    );

    final restored = AndroidPermissionSetupRecord.tryParse(
      '{"outcome":"completed","reviewed_at":"${reviewedAt.toIso8601String()}",'
      '"capability_states":{"notifications":"allowed",'
      '"usageAccess":"needsSettings"}}',
    );

    expect(restored?.outcome, record.outcome);
    expect(restored?.reviewedAt, reviewedAt);
    expect(restored?.capabilityStates, record.capabilityStates);
  });

  test('malformed storage never suppresses a first-run review', () {
    expect(AndroidPermissionSetupRecord.tryParse('not-json'), isNull);
    expect(
      AndroidPermissionSetupRecord.tryParse(
        '{"outcome":"completed","reviewed_at":"not-a-date"}',
      ),
      isNull,
    );
  });
}
