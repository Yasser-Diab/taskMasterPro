import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows permission plugin never keeps location active', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final plugin = File(
      'third_party/permission_handler_windows/windows/'
      'permission_handler_windows_plugin.cpp',
    ).readAsStringSync();

    expect(
      pubspec,
      contains('path: third_party/permission_handler_windows'),
      reason: 'The audited Windows permission implementation must be used.',
    );
    expect(plugin, isNot(contains('PositionChanged(')));
    expect(plugin, isNot(contains('PositionChanged_revoker')));
    expect(plugin, isNot(contains('Geolocator geolocator;')));
    expect(plugin, contains('one_shot_geolocator'));
    expect(
      plugin,
      isNot(contains('SetStateAsync')),
      reason: 'Checking a service must not switch a Windows radio on.',
    );
  });

  test(
    'startup reads the operating-system time zone once without position',
    () {
      final service = File(
        'lib/core/time/time_zone_service.dart',
      ).readAsStringSync();
      final authGate = File(
        'lib/features/auth/presentation/auth_gate.dart',
      ).readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(service, contains('FlutterTimezone.getLocalTimezone()'));
      expect(service, isNot(contains('Geolocator')));
      expect(service, isNot(contains('Permission.location')));
      expect(
        RegExp(
          r'settings\.refreshDeviceTimeZoneIfAutomatic\(\)',
        ).allMatches(authGate).length,
        1,
      );
      expect(
        manifest,
        isNot(contains('android.permission.ACCESS_FINE_LOCATION')),
      );
      expect(
        manifest,
        isNot(contains('android.permission.ACCESS_COARSE_LOCATION')),
      );
    },
  );
}
