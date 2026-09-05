import '../time/time_zone_service.dart';

/// Produces the exact JSON contract accepted by
/// `apply_user_settings_merge_command`.
///
/// Settings updates are intentionally validated before they enter the durable
/// outbox. Older clients could leave an unsupported root key or a non-JSON
/// object in a command, which then blocked the entire account queue with an
/// `invalid_command_payload` conflict. Unknown keys are discarded rather than
/// guessed; valid preference data is retained losslessly.
Map<String, Object?>? normalizedUserSettingsUpdatePayload(
  Map<String, dynamic> payload,
) {
  final normalized = <String, Object?>{};

  final language = payload['preferred_language'];
  if (language is String &&
      RegExp(r'^[a-z]{2}(?:-[A-Z]{2})?$').hasMatch(language.trim())) {
    normalized['preferred_language'] = language.trim();
  }

  final timeZone = payload['time_zone'];
  if (timeZone is String && TimeZoneService.isValidIana(timeZone.trim())) {
    normalized['time_zone'] = timeZone.trim();
  }

  final clockFormat = payload['clock_format'];
  if (clockFormat == '12h' || clockFormat == '24h') {
    normalized['clock_format'] = clockFormat;
  }

  final theme = payload['theme'];
  if (theme is String &&
      const {'light', 'dark', 'golden', 'system'}.contains(theme)) {
    normalized['theme'] = theme;
  }

  final accentColor = payload['accent_color'];
  if (accentColor is int ||
      (accentColor is num &&
          accentColor.isFinite &&
          accentColor == accentColor.roundToDouble())) {
    normalized['accent_color'] = (accentColor as num).toInt();
  }

  final notificationSound = payload['notification_sound'];
  if (notificationSound is String && notificationSound.trim().isNotEmpty) {
    normalized['notification_sound'] = notificationSound.trim();
  }

  for (final key in const <String>[
    'workday_settings',
    'sleep_preferences',
    'notification_preferences',
    'data',
  ]) {
    final value = _normalizedJsonObject(payload[key]);
    if (value != null) normalized[key] = value;
  }

  return normalized.isEmpty ? null : normalized;
}

Map<String, Object?>? _normalizedJsonObject(Object? value) {
  if (value is! Map) return null;
  final normalized = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) continue;
    final jsonValue = _normalizedJsonValue(entry.value);
    if (identical(jsonValue, _discardedJsonValue)) continue;
    normalized[entry.key as String] = jsonValue;
  }
  return normalized;
}

Object? _normalizedJsonValue(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) return value.isFinite ? value : _discardedJsonValue;
  if (value is Map) return _normalizedJsonObject(value) ?? _discardedJsonValue;
  if (value is List) {
    final normalized = <Object?>[];
    for (final item in value) {
      final jsonValue = _normalizedJsonValue(item);
      if (!identical(jsonValue, _discardedJsonValue)) normalized.add(jsonValue);
    }
    return normalized;
  }
  return _discardedJsonValue;
}

const _discardedJsonValue = _DiscardedJsonValue();

class _DiscardedJsonValue {
  const _DiscardedJsonValue();
}
