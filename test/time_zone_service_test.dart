import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/time/time_zone_service.dart';

void main() {
  group('IANA time-zone selection', () {
    test(
      'automatic mode prefers the operating-system zone over stale Cairo',
      () {
        expect(
          TimeZoneService.resolveStoredIanaZone(
            deviceZone: 'America/Vancouver',
            storedZone: 'Africa/Cairo',
            useDeviceTimeZone: true,
          ),
          'America/Vancouver',
        );
        expect(
          TimeZoneService.resolveStoredIanaZone(
            deviceZone: 'America/Vancouver',
            storedZone: 'Asia/Kathmandu',
            useDeviceTimeZone: false,
          ),
          'Asia/Kathmandu',
        );
      },
    );

    test('uses IANA IDs and formats fractional UTC offsets', () {
      final kathmandu = TimeZoneService.describe(
        'Asia/Kathmandu',
        at: DateTime.utc(2026, 7, 28),
      );

      expect(kathmandu.ianaId, 'Asia/Kathmandu');
      expect(kathmandu.offsetLabel, 'UTC+05:45');
      expect(kathmandu.city, 'Kathmandu');
    });

    test('has one representative for every current offset group', () {
      final all = TimeZoneService.allChoices(at: DateTime.utc(2026, 7, 28));
      final representatives = TimeZoneService.representativeChoices(
        at: DateTime.utc(2026, 7, 28),
      );

      expect(
        representatives.map((choice) => choice.offset.inMinutes).toSet(),
        all.map((choice) => choice.offset.inMinutes).toSet(),
      );
      expect(
        representatives.any((choice) => choice.ianaId == 'Africa/Cairo'),
        isTrue,
      );
    });
  });
}
