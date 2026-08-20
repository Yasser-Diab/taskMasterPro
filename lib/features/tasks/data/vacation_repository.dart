import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../domain/vacation_period.dart';

class VacationRepository {
  VacationRepository(this.entities);

  static const entityType = 'vacation_periods';

  final EntityRecordRepository entities;

  String get userId => entities.userId;

  Stream<List<VacationPeriod>> watch() => entities
      .watch(entityType: entityType)
      .map((records) => _decodeAll(records));

  Future<List<VacationPeriod>> list() async =>
      _decodeAll(await entities.list(entityType: entityType));

  Future<String> create(VacationPeriodDraft draft) async {
    draft.validate();
    return entities.create(
      EntityRecordDraft(
        entityType: entityType,
        title: draft.title,
        status: draft.enabled ? 'active' : 'paused',
        data: _data(draft),
        syncPayload: _payload(draft),
      ),
    );
  }

  Future<void> update(VacationPeriod period, VacationPeriodDraft draft) async {
    draft.validate();
    await entities.update(
      period.record,
      title: draft.title,
      status: draft.enabled ? 'active' : 'paused',
      data: _data(draft),
      syncPayload: _payload(draft),
    );
  }

  Future<void> setEnabled(VacationPeriod period, bool enabled) => update(
    period,
    VacationPeriodDraft(
      title: period.title,
      startsOn: period.startsOn,
      endsOn: period.endsOn,
      recurrence: period.recurrence,
      interval: period.interval,
      taskPolicy: period.taskPolicy,
      taskScope: period.taskScope,
      selectedTemplateIds: period.selectedTemplateIds,
      enabled: enabled,
    ),
  );

  Future<void> delete(VacationPeriod period) =>
      entities.softDelete(period.record);

  List<VacationPeriod> _decodeAll(List<LocalEntityRecord> records) {
    final periods = <VacationPeriod>[];
    for (final record in records) {
      final period = _decode(record);
      if (period != null) periods.add(period);
    }
    periods.sort((a, b) {
      final dateOrder = a.startsOn.compareTo(b.startsOn);
      return dateOrder != 0 ? dateOrder : a.title.compareTo(b.title);
    });
    return periods;
  }

  VacationPeriod? _decode(LocalEntityRecord record) {
    final data = entities.decode(record);
    final startsOn = _date(data['start_date']);
    final endsOn = _date(data['end_date']);
    if (startsOn == null || endsOn == null || endsOn.isBefore(startsOn)) {
      return null;
    }
    final recurrence = VacationRecurrence.values.firstWhere(
      (value) => value.name == data['recurrence'],
      orElse: () => VacationRecurrence.none,
    );
    final taskPolicy = VacationTaskPolicy.values.firstWhere(
      (value) => value.name == data['task_policy'],
      orElse: () => VacationTaskPolicy.postpone,
    );
    final taskScope = VacationTaskScope.values.firstWhere(
      (value) => value.name == data['task_scope'],
      orElse: () => VacationTaskScope.allRecurring,
    );
    return VacationPeriod(
      id: record.id,
      title: record.title,
      startsOn: startsOn,
      endsOn: endsOn,
      recurrence: recurrence,
      interval: ((data['interval_value'] as num?)?.toInt() ?? 1).clamp(1, 100),
      taskPolicy: taskPolicy,
      taskScope: taskScope,
      selectedTemplateIds: _strings(data['selected_template_ids']).toSet(),
      enabled: record.status == 'active',
      record: record,
    );
  }

  static Map<String, Object?> _data(VacationPeriodDraft draft) => {
    'start_date': dateOnlyText(draft.startsOn),
    'end_date': dateOnlyText(draft.endsOn),
    'recurrence': draft.recurrence.name,
    'interval_value': draft.interval,
    'task_policy': draft.taskPolicy.name,
    'task_scope': draft.taskScope.name,
    'selected_template_ids': draft.selectedTemplateIds.toList()..sort(),
    'schema_version': 1,
  };

  static Map<String, Object?> _payload(VacationPeriodDraft draft) => {
    'title': draft.title.trim(),
    'status': draft.enabled ? 'active' : 'paused',
    ..._data(draft),
    'data': {'schema_version': 1},
  };

  static DateTime? _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : dateOnly(parsed);
  }

  static Iterable<String> _strings(Object? value) =>
      value is List ? value.map((item) => item.toString()) : const [];
}
