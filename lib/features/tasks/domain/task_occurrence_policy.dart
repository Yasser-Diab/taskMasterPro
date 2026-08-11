import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/time/time_zone_service.dart';

/// The single interpretation of a task occurrence used by Dashboard, Tasks,
/// Calendar, coaching, notifications, and reports.
///
/// A synchronized `status == overdue` value is only a presentation cache. The
/// deadline and the user's current IANA time zone decide whether an occurrence
/// is actually overdue. This prevents a stale status from disagreeing with
/// coaching or a device that crossed a local date boundary.
abstract final class TaskOccurrencePolicy {
  static const Set<String> terminalStatuses = {
    'completed',
    'cancelled',
    'deleted',
    'archived',
    'skipped',
    'replaced',
  };

  static bool isRealOccurrence(LocalTask task) {
    if (task.deletedAt != null) return false;
    final data = _configuration(task);
    return data['is_recurrence_template'] != true &&
        data['record_type'] != 'template' &&
        data['occurrence_state'] != 'replaced';
  }

  static bool isOpenOccurrence(LocalTask task) =>
      isRealOccurrence(task) && !terminalStatuses.contains(task.status);

  static bool isCompletedOccurrence(LocalTask task) =>
      isRealOccurrence(task) && task.status == 'completed';

  static DateTime localDateAt(DateTime instant, {required String timeZone}) {
    final local = tz.TZDateTime.from(instant.toUtc(), _location(timeZone));
    return DateTime(local.year, local.month, local.day);
  }

  static bool isCompletedOn(
    LocalTask task,
    DateTime localDay, {
    required String timeZone,
  }) {
    if (!isCompletedOccurrence(task) || task.actualFinish == null) {
      return false;
    }
    final location = _location(timeZone);
    final completed = tz.TZDateTime.from(task.actualFinish!.toUtc(), location);
    final day = tz.TZDateTime(
      location,
      localDay.year,
      localDay.month,
      localDay.day,
    );
    return completed.year == day.year &&
        completed.month == day.month &&
        completed.day == day.day;
  }

  static bool isRecurringOccurrence(LocalTask task) =>
      isRealOccurrence(task) &&
      (task.templateId?.isNotEmpty == true ||
          task.occurrenceKey?.isNotEmpty == true);

  static bool isOverdue(
    LocalTask task, {
    required DateTime now,
    required String timeZone,
  }) {
    if (!isOpenOccurrence(task)) return false;
    final dueAt = task.dueAt;
    if (dueAt == null) return false;
    final location = _location(timeZone);
    final localDue = tz.TZDateTime.from(dueAt.toUtc(), location);
    final localNow = tz.TZDateTime.from(now.toUtc(), location);
    return localDue.isBefore(localNow);
  }

  static List<LocalTask> overdueOccurrences(
    Iterable<LocalTask> tasks, {
    required DateTime now,
    required String timeZone,
  }) => tasks
      .where((task) => isOverdue(task, now: now, timeZone: timeZone))
      .toList(growable: false);

  static bool isScheduledOn(
    LocalTask task,
    DateTime localDay, {
    required String timeZone,
  }) {
    if (!isRealOccurrence(task)) return false;
    final scheduled = task.plannedStart ?? task.scheduledDate;
    if (scheduled == null) return false;
    final location = _location(timeZone);
    final value = task.plannedStart == null
        ? tz.TZDateTime(
            location,
            scheduled.year,
            scheduled.month,
            scheduled.day,
          )
        : tz.TZDateTime.from(scheduled.toUtc(), location);
    final day = tz.TZDateTime(
      location,
      localDay.year,
      localDay.month,
      localDay.day,
    );
    return value.year == day.year &&
        value.month == day.month &&
        value.day == day.day;
  }

  static bool isUpcoming(
    LocalTask task, {
    required DateTime now,
    required String timeZone,
  }) {
    if (!isOpenOccurrence(task) ||
        isOverdue(task, now: now, timeZone: timeZone)) {
      return false;
    }
    final scheduled = task.plannedStart ?? task.scheduledDate;
    if (scheduled == null) return false;
    final location = _location(timeZone);
    final value = task.plannedStart == null
        ? tz.TZDateTime(
            location,
            scheduled.year,
            scheduled.month,
            scheduled.day,
          )
        : tz.TZDateTime.from(scheduled.toUtc(), location);
    final today = tz.TZDateTime.from(now.toUtc(), location);
    final tomorrowStart = tz.TZDateTime(
      location,
      today.year,
      today.month,
      today.day + 1,
    );
    return !value.isBefore(tomorrowStart);
  }

  static tz.Location _location(String timeZone) {
    final normalized = TimeZoneService.isValidIana(timeZone) ? timeZone : 'UTC';
    return tz.getLocation(normalized == 'UTC' ? 'Etc/UTC' : normalized);
  }

  static Map<String, Object?> _configuration(LocalTask task) {
    try {
      final decoded = jsonDecode(task.dataJson);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }
}
