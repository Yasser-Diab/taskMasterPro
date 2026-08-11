import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmaster_pro/core/platform/device_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'remote revocation gives a later explicit sign-in a fresh device identity',
    () async {
      const userId = 'a1d1143a-33e6-420a-9ef0-610d72d652dd';
      final revokedDeviceId = await DeviceIdentity.accountId(userId);
      expect(await DeviceIdentity.nextSequence(userId), 1);

      await DeviceIdentity.rotateAfterRemoteRevocation();

      final restoredDeviceId = await DeviceIdentity.accountId(userId);
      expect(restoredDeviceId, isNot(revokedDeviceId));
      expect(await DeviceIdentity.nextSequence(userId), 1);
    },
  );

  test(
    'concurrent commands receive unique monotonic device sequences',
    () async {
      const userId = '8fcfe0cf-dc83-44b8-8c76-3da11383607a';
      final sequences = await Future.wait([
        for (var index = 0; index < 25; index++)
          DeviceIdentity.nextSequence(userId),
      ]);

      expect(sequences.toSet(), hasLength(25));
      expect(
        [...sequences]..sort(),
        List<int>.generate(25, (index) => index + 1),
      );
    },
  );
}
