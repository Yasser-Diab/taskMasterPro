import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../config/app_config.dart';
import '../localization/app_localizations.dart';

enum TimeZoneChangeDecision { keepLocalClock, keepAbsoluteMoment, useHomeZone }

class DeviceTimeZoneChange {
  const DeviceTimeZoneChange({
    required this.previousId,
    required this.currentId,
  });

  final String previousId;
  final String currentId;
}

class TimeZoneService extends ChangeNotifier {
  TimeZoneService();

  static const _androidChannel = MethodChannel('taskmasterpro/device');
  static const _windowsChannel = MethodChannel(
    'taskmasterpro/windows_lifecycle',
  );

  String _deviceZoneId = 'Etc/UTC';
  String _mode = 'follow_device';
  String _configuredZoneId = 'Etc/UTC';
  String _effectiveZoneId = 'Etc/UTC';
  Locale _locale = const Locale('en');
  String _clockFormat = 'system';
  DateTime? _lastZoneRefreshAt;
  String? _lastDetectedZoneId;
  DeviceTimeZoneChange? _pendingChange;
  bool _initialized = false;

  String get deviceZoneId => _deviceZoneId;
  String get mode => _mode;
  String get configuredTimeZoneId => _configuredZoneId;
  String get effectiveTimeZoneId => _effectiveZoneId;
  Locale get locale => _locale;
  String get clockFormat => _clockFormat;
  DateTime? get lastZoneRefreshAt => _lastZoneRefreshAt;
  String? get lastTaskValueReceived => TimeZoneRegistry.lastTaskValueReceived;
  String? get lastConvertedTaskValue => TimeZoneRegistry.lastConvertedTaskValue;
  DeviceTimeZoneChange? get pendingChange => _pendingChange;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
    await refreshDeviceZone();
  }

  Future<DeviceTimeZoneChange?> refreshDeviceZone() async {
    String detected;
    try {
      if (Platform.isAndroid) {
        detected =
            await _androidChannel.invokeMethod<String>('getTimeZoneId') ??
            'Etc/UTC';
      } else if (Platform.isWindows) {
        detected =
            await _windowsChannel.invokeMethod<String>('getTimeZoneId') ??
            'Etc/UTC';
      } else {
        detected = Platform.environment['TZ'] ?? 'Etc/UTC';
      }
      tz.getLocation(detected);
    } on Object {
      detected = 'Etc/UTC';
    }
    final previous = _lastDetectedZoneId;
    _lastDetectedZoneId = detected;
    _deviceZoneId = detected;
    TimeZoneRegistry.deviceZoneId = detected;
    _lastZoneRefreshAt = DateTime.now().toUtc();
    if (previous != null && previous != detected) {
      _pendingChange = DeviceTimeZoneChange(
        previousId: previous,
        currentId: detected,
      );
    }
    notifyListeners();
    return _pendingChange;
  }

  void configure(AppConfig config, {Locale? locale}) {
    final nextMode = config.timeZoneMode == 'fixed'
        ? 'fixed_zone'
        : 'follow_device';
    final nextConfigured = config.timeZoneMode == 'fixed'
        ? validatedZoneId(config.fixedTimeZoneId)
        : validatedZoneId(config.homeTimeZoneId);
    final nextEffective = effectiveZoneId(config);
    final nextLocale = locale ?? config.locale;
    if (_mode == nextMode &&
        _configuredZoneId == nextConfigured &&
        _effectiveZoneId == nextEffective &&
        _locale == nextLocale) {
      return;
    }
    _mode = nextMode;
    _configuredZoneId = nextConfigured;
    _effectiveZoneId = nextEffective;
    _locale = nextLocale;
    _lastZoneRefreshAt = DateTime.now().toUtc();
    notifyListeners();
  }

  String effectiveZoneId(AppConfig config) {
    if (config.keepHomeTimeZoneWhileTravelling &&
        config.homeTimeZoneId.trim().isNotEmpty) {
      return validatedZoneId(config.homeTimeZoneId);
    }
    if (config.timeZoneMode == 'fixed') {
      return validatedZoneId(config.fixedTimeZoneId);
    }
    return validatedZoneId(_deviceZoneId);
  }

  tz.Location location(String? zoneId) {
    final id = validatedZoneId(zoneId);
    return tz.getLocation(id);
  }

  String validatedZoneId(String? value) {
    final candidate = value?.trim();
    if (candidate == null || candidate.isEmpty) return _deviceZoneId;
    try {
      tz.getLocation(candidate);
      return candidate;
    } on Object {
      return _deviceZoneId;
    }
  }

  List<String> availableZoneIds() {
    return tz.timeZoneDatabase.locations.keys.toList(growable: false)..sort();
  }

  String offsetLabel(String zoneId, {DateTime? instant}) {
    final at = tz.TZDateTime.from(instant ?? DateTime.now(), location(zoneId));
    final offset = at.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  DateTime parseDatabaseInstant(String value) {
    final parsed = parseDatabaseInstantValue(value);
    TimeZoneRegistry.lastTaskValueReceived = value;
    return parsed;
  }

  tz.TZDateTime convertInstantToAppZone(DateTime utcInstant, {String? zoneId}) {
    final converted = tz.TZDateTime.from(
      utcInstant.toUtc(),
      location(zoneId ?? _effectiveZoneId),
    );
    TimeZoneRegistry.lastConvertedTaskValue = converted.toIso8601String();
    return converted;
  }

  String formatTaskTimeRange(
    BuildContext context, {
    required DateTime startUtc,
    DateTime? endUtc,
    String? zoneId,
  }) {
    final material = MaterialLocalizations.of(context);
    final localStart = convertInstantToAppZone(startUtc, zoneId: zoneId);
    final startDate = _friendlyDateLabel(context, localStart);
    final startTime = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(localStart),
    );
    if (endUtc == null) {
      return '$startDate · $startTime';
    }
    final localEnd = convertInstantToAppZone(endUtc, zoneId: zoneId);
    final endDate = _friendlyDateLabel(context, localEnd);
    final endTime = material.formatTimeOfDay(TimeOfDay.fromDateTime(localEnd));
    if (startDate == endDate) {
      return '$startDate · $startTime-$endTime';
    }
    return '$startDate · $startTime-$endDate · $endTime';
  }

  String formatTaskDate(BuildContext context, DateTime instantUtc) {
    final material = MaterialLocalizations.of(context);
    return material.formatMediumDate(convertInstantToAppZone(instantUtc));
  }

  String formatTaskDateTime(BuildContext context, DateTime instantUtc) {
    final material = MaterialLocalizations.of(context);
    final local = convertInstantToAppZone(instantUtc);
    return '${material.formatMediumDate(local)} · '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  String formatRelativeTaskTime(BuildContext context, DateTime instantUtc) {
    return _friendlyDateLabel(context, convertInstantToAppZone(instantUtc));
  }

  String _friendlyDateLabel(BuildContext context, DateTime local) {
    final material = MaterialLocalizations.of(context);
    final now = convertInstantToAppZone(DateTime.now().toUtc());
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return context.text('today');
    if (day == today.add(const Duration(days: 1))) {
      return context.text('tomorrow');
    }
    return material.formatMediumDate(local);
  }

  void resolvePendingChange() {
    _pendingChange = null;
    notifyListeners();
  }
}

class AppTimeZoneController extends TimeZoneService {
  AppTimeZoneController();
}

DateTime parseDatabaseInstantValue(String value) {
  final hasZone =
      value.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(value);
  if (!hasZone) {
    throw FormatException('Database instant has no UTC offset: $value');
  }
  return DateTime.parse(value).toUtc();
}

class TimeZoneRegistry {
  TimeZoneRegistry._();

  static String deviceZoneId = 'Etc/UTC';
  static String? lastTaskValueReceived;
  static String? lastConvertedTaskValue;

  static tz.Location location(String? zoneId) {
    final candidate = zoneId?.trim();
    try {
      return tz.getLocation(
        candidate == null || candidate.isEmpty ? deviceZoneId : candidate,
      );
    } on Object {
      try {
        return tz.getLocation(deviceZoneId);
      } on Object {
        return tz.UTC;
      }
    }
  }

  static DateTime wallClockToUtc({
    required DateTime date,
    required int minutesAfterMidnight,
    String? zoneId,
  }) {
    final location = TimeZoneRegistry.location(zoneId);
    final hour = minutesAfterMidnight ~/ 60;
    final minute = minutesAfterMidnight % 60;
    return tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    ).toUtc();
  }

  static DateTime nowIn(String? zoneId, {DateTime? nowUtc}) {
    return tz.TZDateTime.from(
      (nowUtc ?? DateTime.now().toUtc()).toUtc(),
      location(zoneId),
    );
  }
}
