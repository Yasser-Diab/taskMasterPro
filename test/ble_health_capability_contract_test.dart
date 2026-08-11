import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android lists only paired health wearables and checks direct GATT truthfully',
    () {
      final source = File(
        'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/'
        'MainActivity.kt',
      ).readAsStringSync();

      for (final serviceUuid in const [
        '0000180d-0000-1000-8000-00805f9b34fb', // Heart rate.
        '0000180f-0000-1000-8000-00805f9b34fb', // Battery.
        '00001814-0000-1000-8000-00805f9b34fb', // Running cadence.
        '00001816-0000-1000-8000-00805f9b34fb', // Cycling cadence.
        '00001822-0000-1000-8000-00805f9b34fb', // Pulse oximeter.
      ]) {
        expect(source, contains(serviceUuid));
      }
      expect(source, contains('adapter.bondedDevices'));
      expect(source, contains('isPairedHealthWearable'));
      expect(source, contains('BluetoothClass.Device.WEARABLE_WRIST_WATCH'));
      expect(source, contains('BluetoothClass.Device.HEALTH_PULSE_RATE'));
      expect(source, contains('getConnectedDevices(BluetoothProfile.GATT)'));
      expect(source, contains('inspectPairedHealthDevice'));
      expect(source, contains('openAppNotificationSettings'));
      expect(source, isNot(contains('startBleScan(')));
      expect(source, isNot(contains('bluetoothLeScanner')));
      expect(source, isNot(contains('ScanCallback')));
      expect(source, contains('discoverServices()'));
      expect(source, contains('"capabilityState" to "not_checked"'));
      expect(source, contains('"direct_supported"'));
      expect(source, contains('"no_direct_health_service"'));
      expect(source, isNot(contains('"capabilityState" to "confirmed"')));
      expect(source, contains('gatt?.disconnect()'));
      expect(source, contains('gatt?.close()'));
      expect(source, isNot(contains('"historical_steps"')));
      expect(source, isNot(contains('"sleep_history"')));
    },
  );

  test(
    'health UI uses paired health sources rather than a nearby BLE scan',
    () {
      final screen = File(
        'lib/features/health/presentation/health_connect_screen.dart',
      ).readAsStringSync();

      expect(screen, isNot(contains('Permission.bluetoothScan')));
      expect(screen, isNot(contains('Permission.locationWhenInUse')));
      expect(screen, isNot(contains("invokeListMethod<Object?>('scan'")));
      expect(screen, contains('invokeListMethod<Object?>'));
      expect(screen, contains("'pairedHealthDevices'"));
      expect(screen, contains('PairedHealthWearable.fromPlatformValues'));
      expect(screen, contains('health_wearables'));
      expect(screen, isNot(contains("device['address']")));
      expect(screen, contains('_providerSources'));
      expect(screen, contains('health_source_applications_empty'));
    },
  );

  test('Android manifest does not request nearby-device scan or location', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, isNot(contains('android.permission.BLUETOOTH_SCAN')));
    expect(
      manifest,
      isNot(contains('android.permission.ACCESS_FINE_LOCATION')),
    );
    expect(manifest, contains('android.permission.BLUETOOTH_CONNECT'));
  });
}
