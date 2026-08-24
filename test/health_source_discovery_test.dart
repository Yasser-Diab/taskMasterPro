import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/health/data/health_source_discovery.dart';

void main() {
  test(
    'only explicitly paired native health wearables enter Health Sources',
    () {
      final wearables = PairedHealthWearable.fromPlatformValues([
        {
          'address': 'AA:BB:CC:DD:EE:01',
          'name': 'Paired watch',
          'bonded': true,
          'healthDevice': true,
          'connected': true,
          'capabilityState': 'not_checked',
          'capabilities': const <String>[],
        },
        {
          'address': 'AA:BB:CC:DD:EE:02',
          'name': 'Nearby earbuds',
          'bonded': false,
          'healthDevice': false,
        },
        {
          'address': 'AA:BB:CC:DD:EE:03',
          'name': 'Paired keyboard',
          'bonded': true,
          'healthDevice': false,
        },
      ]);

      expect(wearables, hasLength(1));
      expect(wearables.single.displayName, 'Paired watch');
      expect(wearables.single.isConnected, isTrue);
      expect(wearables.single.capabilityState, 'not_checked');
    },
  );

  test('direct capabilities require a later platform inspection result', () {
    final wearable = PairedHealthWearable.fromPlatformValues([
      {
        'address': 'AA:BB:CC:DD:EE:01',
        'name': 'Paired watch',
        'bonded': true,
        'healthDevice': true,
      },
    ]).single;

    expect(wearable.capabilityState, 'not_checked');
    expect(wearable.capabilities, isEmpty);

    final inspected = wearable.copyWithPlatformInspection({
      'capabilityState': 'direct_supported',
      'capabilities': ['live_heart_rate', 'battery'],
      'directReadings': {'batteryPercent': 74},
    });
    expect(inspected.capabilityState, 'direct_supported');
    expect(inspected.capabilities, ['live_heart_rate', 'battery']);
    expect(inspected.batteryPercent, 74);
  });

  test('health provider labels do not expose raw package identifiers', () {
    expect(healthApplicationDisplayName('com.huawei.health'), 'Huawei Health');
    expect(healthApplicationDisplayName('com.unknown.vendor.health'), isNull);
    expect(
      observedHealthApplicationSources([
        'Health Connect',
        'com.google.android.apps.healthdata',
        'com.huawei.health',
        'Samsung Health',
      ]),
      {'Huawei Health', 'Samsung Health'},
    );
  });
}
