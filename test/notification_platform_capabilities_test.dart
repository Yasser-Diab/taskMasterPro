import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/settings/presentation/notifications_sounds_screen.dart';

void main() {
  test('Windows notification settings expose only supported controls', () {
    final capabilities = notificationPlatformCapabilities(
      TargetPlatform.windows,
    );

    expect(capabilities.supportsVibration, isFalse);
    expect(capabilities.supportsDeviceSoundPicker, isFalse);
    expect(capabilities.supportsNotificationSettings, isTrue);
  });

  test('Android notification settings retain device-specific controls', () {
    final capabilities = notificationPlatformCapabilities(
      TargetPlatform.android,
    );

    expect(capabilities.supportsVibration, isTrue);
    expect(capabilities.supportsDeviceSoundPicker, isTrue);
    expect(capabilities.supportsNotificationSettings, isTrue);
  });
}
