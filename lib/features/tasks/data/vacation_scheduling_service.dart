import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:collection/collection.dart';

import '../../../core/database/app_database.dart';
import '../domain/vacation_period.dart';
import 'task_repository.dart';
import 'vacation_repository.dart';

const vacationAdjustmentKey = 'vacation_adjustment';

class VacationSchedulingService {
  VacationSchedulingService({
    required this.database,
    required this.tasks,
    required this.vacations,
    this.now,
  });

  final AppDatabase database;
  final TaskRepository tasks;
  final VacationRepository vacations;
  final DateTime Function()? now;
  Future<void> _tail = Future<void>.value();
  static const _deepEquality = DeepCollectionEquality();

  Future<int> reconcileUpcoming() {
    final operation = _tail.then((_) => _reconcileUpcoming());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<int> _reconcileUpcoming() async {
    final planner = VacationPlanner(await vacations.list());
    final rows =
        await (database.select(database.localTasks)..where(
              (row) =>
                  row.userId.equals(vacations.userId) &
                  row.deletedAt.isNull() &
                  row.templateId.isNotNull(),
            ))
            .get();
    final today = dateOnly(now?.call() ?? DateTime.now());
    var changed = 0;
    for (final task in rows) {
      final templateId = task.templateId;
      if (templateId == null ||
          task.status == 'completed' ||
          task.actualStart != null ||
          const {'in_progress', 'running', 'paused'}.contains(task.status)) {
        continue;
      }
      final configuration = _configuration(task.dataJson);
      final adjustment = _object(configuration[vacationAdjustmentKey]);
      if (task.status == 'cancelled' && adjustment.isEmpty) continue;

      final originalDate =
          _instant(adjustment['original_scheduled_date'])?.toLocal() ??
          task.scheduledDate;
      if (originalDate == null || dateOnly(originalDate).isBefore(today)) {
        continue;
      }

      // A user edit made after our prior adjustment takes ownership. Remove
      // only our marker and keep every date/status the user chose.
      if (adjustment.isNotEmpty && !_stillOwnsAppliedState(task, adjustment)) {
        final manualConfiguration = <String, Object?>{...configuration}
          ..remove(vacationAdjustmentKey);
        await tasks.applyVacationAdjustment(
          task,
          status: task.status,
          scheduledDate: task.scheduledDate ?? originalDate,
          plannedStart: task.plannedStart,
          plannedEnd: task.plannedEnd,
          dueAt: task.dueAt,
          configuration: manualConfiguration,
        );
        changed++;
        continue;
      }

      final originalStatus =
          adjustment['original_status']?.toString() ?? task.status;
      final originalPlannedStart =
          _instant(adjustment['original_planned_start'])?.toLocal() ??
          task.plannedStart;
      final originalPlannedEnd =
          _instant(adjustment['original_planned_end'])?.toLocal() ??
          task.plannedEnd;
      final originalDueAt =
          _instant(adjustment['original_due_at'])?.toLocal() ?? task.dueAt;
      final baseConfiguration = <String, Object?>{...configuration}
        ..remove(vacationAdjustmentKey);
      final disposition = planner.dispositionFor(
        occurrenceDate: originalDate,
        templateId: templateId,
      );

      late final String desiredStatus;
      late final DateTime desiredDate;
      late final DateTime? desiredPlannedStart;
      late final DateTime? desiredPlannedEnd;
      late final DateTime? desiredDueAt;
      late final Map<String, Object?> desiredConfiguration;
      if (!disposition.isAdjusted) {
        if (adjustment.isEmpty) continue;
        desiredStatus = originalStatus == 'cancelled'
            ? 'ready'
            : originalStatus;
        desiredDate = dateOnly(originalDate);
        desiredPlannedStart = originalPlannedStart;
        desiredPlannedEnd = originalPlannedEnd;
        desiredDueAt = originalDueAt;
        desiredConfiguration = baseConfiguration;
      } else {
        final shiftDays = disposition.scheduledDate
            .difference(dateOnly(originalDate))
            .inDays;
        desiredStatus = disposition.isSkipped
            ? 'cancelled'
            : (originalStatus == 'cancelled' ? 'ready' : originalStatus);
        desiredDate = disposition.isSkipped
            ? dateOnly(originalDate)
            : disposition.scheduledDate;
        desiredPlannedStart = _shift(originalPlannedStart, shiftDays);
        desiredPlannedEnd = _shift(originalPlannedEnd, shiftDays);
        desiredDueAt = _shift(originalDueAt, shiftDays);
        desiredConfiguration = <String, Object?>{
          ...baseConfiguration,
          vacationAdjustmentKey: {
            'schema_version': 1,
            'vacation_id': disposition.vacationId,
            'policy': disposition.policy!.name,
            'original_status': originalStatus,
            'original_scheduled_date': dateOnlyText(originalDate),
            'original_planned_start': originalPlannedStart?.toIso8601String(),
            'original_planned_end': originalPlannedEnd?.toIso8601String(),
            'original_due_at': originalDueAt?.toIso8601String(),
            'applied_status': desiredStatus,
            'applied_scheduled_date': dateOnlyText(desiredDate),
            'applied_planned_start': desiredPlannedStart?.toIso8601String(),
            'applied_planned_end': desiredPlannedEnd?.toIso8601String(),
            'applied_due_at': desiredDueAt?.toIso8601String(),
          },
        };
      }
      if (_sameState(
        task,
        status: desiredStatus,
        scheduledDate: desiredDate,
        plannedStart: desiredPlannedStart,
        plannedEnd: desiredPlannedEnd,
        dueAt: desiredDueAt,
        configuration: desiredConfiguration,
      )) {
        continue;
      }
      await tasks.applyVacationAdjustment(
        task,
        status: desiredStatus,
        scheduledDate: desiredDate,
        plannedStart: desiredPlannedStart,
        plannedEnd: desiredPlannedEnd,
        dueAt: desiredDueAt,
        configuration: desiredConfiguration,
      );
      changed++;
    }
    return changed;
  }

  static bool _stillOwnsAppliedState(
    LocalTask task,
    Map<String, Object?> adjustment,
  ) =>
      task.status == adjustment['applied_status'] &&
      _sameDate(
        task.scheduledDate,
        _instant(adjustment['applied_scheduled_date']),
      ) &&
      _sameInstant(
        task.plannedStart,
        _instant(adjustment['applied_planned_start']),
      ) &&
      _sameInstant(
        task.plannedEnd,
        _instant(adjustment['applied_planned_end']),
      ) &&
      _sameInstant(task.dueAt, _instant(adjustment['applied_due_at']));

  static bool _sameState(
    LocalTask task, {
    required String status,
    required DateTime scheduledDate,
    required DateTime? plannedStart,
    required DateTime? plannedEnd,
    required DateTime? dueAt,
    required Map<String, Object?> configuration,
  }) =>
      task.status == status &&
      _sameDate(task.scheduledDate, scheduledDate) &&
      _sameInstant(task.plannedStart, plannedStart) &&
      _sameInstant(task.plannedEnd, plannedEnd) &&
      _sameInstant(task.dueAt, dueAt) &&
      _deepEquality.equals(_configuration(task.dataJson), configuration);

  static DateTime? _shift(DateTime? value, int days) =>
      value?.add(Duration(days: days));

  static bool _sameDate(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == right;
    return dateOnly(left) == dateOnly(right);
  }

  static bool _sameInstant(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == right;
    return left.toUtc().millisecondsSinceEpoch ==
        right.toUtc().millisecondsSinceEpoch;
  }

  static Map<String, Object?> _configuration(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } on FormatException {
      return <String, Object?>{};
    }
  }

  static Map<String, Object?> _object(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

  static DateTime? _instant(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : DateTime.tryParse(text);
  }
}
