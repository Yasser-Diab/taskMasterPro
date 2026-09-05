import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';

/// A repeatable work pattern that belongs to the account settings rather than
/// a task.  `week` is one-based so it is clear in the UI and stable when the
/// same plan is synchronized to another device.
class WorkScheduleShift {
  const WorkScheduleShift({
    required this.week,
    required this.startMinutes,
    required this.endMinutes,
  });

  final int week;
  final int startMinutes;
  final int endMinutes;

  Map<String, Object?> toJson() => {
    'week': week,
    'start_minutes': startMinutes,
    'end_minutes': endMinutes,
  };

  static WorkScheduleShift? fromJson(Object? value) {
    if (value is! Map) return null;
    final week = (value['week'] as num?)?.toInt();
    final start = (value['start_minutes'] as num?)?.toInt();
    final end = (value['end_minutes'] as num?)?.toInt();
    if (week == null || week < 1 || start == null || end == null) return null;
    if (start < 0 || start >= 24 * 60 || end < 0 || end >= 24 * 60) {
      return null;
    }
    return WorkScheduleShift(week: week, startMinutes: start, endMinutes: end);
  }
}

/// Shared interpretation of the synchronized work-schedule settings.  It is
/// intentionally deterministic: every device calculates the same next shift
/// from the same IANA timezone, anchor Monday and shift cycle.
class WorkSchedulePlan {
  const WorkSchedulePlan({
    required this.enabled,
    required this.workingDays,
    required this.standardStartMinutes,
    required this.standardEndMinutes,
    required this.anchorDate,
    required this.rotation,
  });

  final bool enabled;
  final Set<int> workingDays;
  final int standardStartMinutes;
  final int standardEndMinutes;
  final DateTime anchorDate;
  final List<WorkScheduleShift> rotation;

  static WorkSchedulePlan fromSettings(LocalAppSetting settings) {
    final rawDays = _decodeList(settings.workingDaysJson);
    final days = rawDays
        .whereType<num>()
        .map((value) => value.toInt())
        .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
        .toSet();
    final decodedRotation =
        _decodeList(settings.workScheduleRotationJson)
            .map(WorkScheduleShift.fromJson)
            .whereType<WorkScheduleShift>()
            .toList()
          ..sort((left, right) => left.week.compareTo(right.week));
    final parsedAnchor = DateTime.tryParse(settings.workScheduleAnchorDate);
    final anchor = parsedAnchor == null
        ? DateTime(2026, 1, 5)
        : DateTime(parsedAnchor.year, parsedAnchor.month, parsedAnchor.day);
    return WorkSchedulePlan(
      enabled: settings.workScheduleEnabled,
      workingDays: days.isEmpty
          ? const {
              DateTime.monday,
              DateTime.tuesday,
              DateTime.wednesday,
              DateTime.thursday,
              DateTime.friday,
            }
          : days,
      standardStartMinutes: settings.workStartMinutes,
      standardEndMinutes: settings.workEndMinutes,
      anchorDate: anchor,
      rotation: decodedRotation,
    );
  }

  List<Map<String, Object?>> get rotationPayload =>
      rotation.map((shift) => shift.toJson()).toList(growable: false);

  WorkScheduleShift shiftForDate(DateTime date) {
    if (rotation.isEmpty) {
      return WorkScheduleShift(
        week: 1,
        startMinutes: standardStartMinutes,
        endMinutes: standardEndMinutes,
      );
    }
    final dateMonday = date.subtract(Duration(days: date.weekday - 1));
    final anchorMonday = anchorDate.subtract(
      Duration(days: anchorDate.weekday - 1),
    );
    final weeks = dateMonday.difference(anchorMonday).inDays ~/ 7;
    final position = weeks % rotation.length;
    return rotation[position < 0 ? position + rotation.length : position];
  }

  /// Finds the next local work start and returns its UTC instant.  Keeping
  /// this calculation here prevents Android and Windows from scheduling a
  /// different shift around daylight-saving changes.
  DateTime? nextStartUtc({required tz.Location location, DateTime? nowUtc}) {
    if (!enabled) return null;
    final now = tz.TZDateTime.from(nowUtc ?? DateTime.now().toUtc(), location);
    for (var offset = 0; offset < 22; offset++) {
      final day = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day + offset,
      );
      if (!workingDays.contains(day.weekday)) continue;
      final shift = shiftForDate(day);
      final candidate = tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
        shift.startMinutes ~/ 60,
        shift.startMinutes % 60,
      );
      if (candidate.isAfter(now)) return candidate.toUtc();
    }
    return null;
  }

  static List<Object?> _decodeList(String source) {
    try {
      final value = jsonDecode(source);
      return value is List ? value : const <Object?>[];
    } on FormatException {
      return const <Object?>[];
    }
  }
}
