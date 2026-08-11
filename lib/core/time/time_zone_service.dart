import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// A current, IANA-backed entry for the manual time-zone picker.
class TimeZoneChoice {
  const TimeZoneChoice({
    required this.ianaId,
    required this.city,
    required this.offset,
  });

  final String ianaId;
  final String city;
  final Duration offset;

  String get offsetLabel => formatUtcOffset(offset);
  String get displayLabel => '$offsetLabel — $city';
}

/// Resolves platform time zones to IANA identifiers and builds selector values
/// from the bundled IANA database.  Stored values are always IANA IDs; the
/// human-readable offset is computed for today so daylight-saving changes are
/// never stored as a stale fixed UTC offset.
class TimeZoneService {
  TimeZoneService._();

  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static bool isValidIana(String value) {
    _ensureInitialized();
    return value == 'UTC' || tz.timeZoneDatabase.locations.containsKey(value);
  }

  static Future<String> detectDeviceIanaZone() async {
    _ensureInitialized();
    try {
      final value = (await FlutterTimezone.getLocalTimezone()).identifier;
      if (isValidIana(value)) return value;
    } catch (_) {
      // A manual IANA selection remains available when a platform cannot
      // report its configured zone. Location permission is intentionally not
      // requested for this normal OS-based detection path.
    }
    return 'UTC';
  }

  static TimeZoneChoice describe(String ianaId, {DateTime? at}) {
    _ensureInitialized();
    final normalized = isValidIana(ianaId) ? ianaId : 'UTC';
    final location = tz.getLocation(
      normalized == 'UTC' ? 'Etc/UTC' : normalized,
    );
    final instant = tz.TZDateTime.from(at ?? DateTime.now(), location);
    return TimeZoneChoice(
      ianaId: normalized,
      city: _cityName(normalized),
      offset: instant.timeZoneOffset,
    );
  }

  /// One representative city per current offset, with every IANA city still
  /// available through [allChoices] and picker search.
  static List<TimeZoneChoice> representativeChoices({DateTime? at}) {
    _ensureInitialized();
    final grouped = <int, List<TimeZoneChoice>>{};
    for (final choice in allChoices(at: at)) {
      grouped.putIfAbsent(choice.offset.inMinutes, () => []).add(choice);
    }
    return grouped.values.map((group) {
      group.sort((left, right) {
        final leftPriority = _representativePriority(left.ianaId);
        final rightPriority = _representativePriority(right.ianaId);
        return leftPriority != rightPriority
            ? leftPriority.compareTo(rightPriority)
            : left.city.compareTo(right.city);
      });
      return group.first;
    }).toList()..sort((left, right) => left.offset.compareTo(right.offset));
  }

  static List<TimeZoneChoice> allChoices({DateTime? at}) {
    _ensureInitialized();
    final ids = <String>{'UTC'};
    for (final id in tz.timeZoneDatabase.locations.keys) {
      // IANA aliases such as US/Eastern make the list noisy and are not
      // appropriate values to introduce for new settings.
      if (id.contains('/') &&
          !id.startsWith('Etc/') &&
          !id.startsWith('SystemV/')) {
        ids.add(id);
      }
    }
    final result = ids.map((id) => describe(id, at: at)).toList()
      ..sort((left, right) {
        final byOffset = left.offset.compareTo(right.offset);
        return byOffset != 0 ? byOffset : left.city.compareTo(right.city);
      });
    return result;
  }

  static String _cityName(String ianaId) {
    if (ianaId == 'UTC') return 'UTC';
    return ianaId.split('/').last.replaceAll('_', ' ').replaceAll('-', ' ');
  }

  static int _representativePriority(String ianaId) {
    const preferred = <String>[
      'Pacific/Pago_Pago',
      'Pacific/Honolulu',
      'America/Anchorage',
      'America/Los_Angeles',
      'America/Denver',
      'America/Chicago',
      'America/New_York',
      'America/Halifax',
      'America/St_Johns',
      'America/Sao_Paulo',
      'Atlantic/Reykjavik',
      'Africa/Lagos',
      'Europe/Berlin',
      'Africa/Cairo',
      'Asia/Tehran',
      'Asia/Dubai',
      'Asia/Karachi',
      'Asia/Kolkata',
      'Asia/Kathmandu',
      'Asia/Dhaka',
      'Asia/Yangon',
      'Asia/Bangkok',
      'Asia/Singapore',
      'Asia/Tokyo',
      'Australia/Adelaide',
      'Australia/Sydney',
      'Pacific/Auckland',
      'Pacific/Chatham',
      'Pacific/Kiritimati',
    ];
    final index = preferred.indexOf(ianaId);
    return index < 0 ? preferred.length : index;
  }
}

String formatUtcOffset(Duration value) {
  final minutes = value.inMinutes;
  final sign = minutes < 0 ? '−' : '+';
  final absolute = minutes.abs();
  final hours = absolute ~/ 60;
  final remainder = absolute % 60;
  return 'UTC$sign${hours.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}
