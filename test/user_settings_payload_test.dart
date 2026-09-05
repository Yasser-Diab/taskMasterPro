import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/sync/user_settings_payload.dart';

void main() {
  test('settings payload keeps only the supported wire contract', () {
    final payload = normalizedUserSettingsUpdatePayload({
      'preferred_language': 'pl',
      'time_zone': 'Europe/Warsaw',
      'clock_format': '24h',
      'theme': 'dark',
      'accent_color': 4,
      'notification_sound': 'system',
      'schema_version': 7,
      'data': {
        'wake_time_minutes': 420,
        'rotation': [
          1,
          double.infinity,
          {'start': '08:00'},
        ],
        'non_json': DateTime.utc(2026, 9, 5),
      },
      'workday_settings': {
        'days': [1, 2, 3],
      },
    });

    expect(payload, {
      'preferred_language': 'pl',
      'time_zone': 'Europe/Warsaw',
      'clock_format': '24h',
      'theme': 'dark',
      'accent_color': 4,
      'notification_sound': 'system',
      'workday_settings': {
        'days': [1, 2, 3],
      },
      'data': {
        'wake_time_minutes': 420,
        'rotation': [
          1,
          {'start': '08:00'},
        ],
      },
    });
  });

  test('settings payload refuses a command with no valid setting', () {
    expect(
      normalizedUserSettingsUpdatePayload({
        'time_zone': 'not/a-time-zone',
        'theme': 'neon',
        'accent_color': 1.5,
        'schema_version': 7,
      }),
      isNull,
    );
  });
}
