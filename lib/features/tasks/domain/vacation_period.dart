import '../../../core/database/app_database.dart';

enum VacationRecurrence { none, yearly }

enum VacationTaskPolicy { postpone, skip }

enum VacationTaskScope { allRecurring, selectedTemplates }

class VacationPeriodDraft {
  const VacationPeriodDraft({
    required this.title,
    required this.startsOn,
    required this.endsOn,
    this.recurrence = VacationRecurrence.none,
    this.interval = 1,
    this.taskPolicy = VacationTaskPolicy.postpone,
    this.taskScope = VacationTaskScope.allRecurring,
    this.selectedTemplateIds = const {},
    this.enabled = true,
  });

  final String title;
  final DateTime startsOn;
  final DateTime endsOn;
  final VacationRecurrence recurrence;
  final int interval;
  final VacationTaskPolicy taskPolicy;
  final VacationTaskScope taskScope;
  final Set<String> selectedTemplateIds;
  final bool enabled;

  void validate() {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'A vacation needs a name.');
    }
    final start = dateOnly(startsOn);
    final end = dateOnly(endsOn);
    if (end.isBefore(start)) {
      throw ArgumentError.value(endsOn, 'endsOn', 'End must follow start.');
    }
    if (interval < 1) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive.');
    }
    if (taskScope == VacationTaskScope.selectedTemplates &&
        selectedTemplateIds.isEmpty) {
      throw ArgumentError.value(
        selectedTemplateIds,
        'selectedTemplateIds',
        'Choose at least one recurring task.',
      );
    }
  }
}

class VacationPeriod {
  const VacationPeriod({
    required this.id,
    required this.title,
    required this.startsOn,
    required this.endsOn,
    required this.recurrence,
    required this.interval,
    required this.taskPolicy,
    required this.taskScope,
    required this.selectedTemplateIds,
    required this.enabled,
    required this.record,
  });

  final String id;
  final String title;
  final DateTime startsOn;
  final DateTime endsOn;
  final VacationRecurrence recurrence;
  final int interval;
  final VacationTaskPolicy taskPolicy;
  final VacationTaskScope taskScope;
  final Set<String> selectedTemplateIds;
  final bool enabled;
  final LocalEntityRecord record;

  bool appliesToTemplate(String templateId) =>
      enabled &&
      (taskScope == VacationTaskScope.allRecurring ||
          selectedTemplateIds.contains(templateId));

  VacationOccurrence? occurrenceContaining(DateTime value) {
    final day = dateOnly(value);
    if (!enabled) return null;
    if (recurrence == VacationRecurrence.none) {
      return !day.isBefore(startsOn) && !day.isAfter(endsOn)
          ? VacationOccurrence(startsOn, endsOn)
          : null;
    }

    // Checking both anchors covers recurring periods that cross New Year.
    for (final anchorYear in [day.year - 1, day.year]) {
      final yearsFromStart = anchorYear - startsOn.year;
      if (yearsFromStart < 0 || yearsFromStart % interval != 0) continue;
      final start = _sameMonthDay(startsOn, anchorYear);
      final duration = endsOn.difference(startsOn).inDays;
      final end = start.add(Duration(days: duration));
      if (!day.isBefore(start) && !day.isAfter(end)) {
        return VacationOccurrence(start, end);
      }
    }
    return null;
  }

  static DateTime _sameMonthDay(DateTime source, int year) {
    final lastDay = DateTime(year, source.month + 1, 0).day;
    return DateTime(year, source.month, source.day.clamp(1, lastDay));
  }
}

class VacationOccurrence {
  const VacationOccurrence(this.startsOn, this.endsOn);

  final DateTime startsOn;
  final DateTime endsOn;
}

class VacationDisposition {
  const VacationDisposition.keep(DateTime date)
    : scheduledDate = date,
      policy = null,
      vacationId = null;

  const VacationDisposition.adjusted({
    required this.scheduledDate,
    required this.policy,
    required this.vacationId,
  });

  final DateTime scheduledDate;
  final VacationTaskPolicy? policy;
  final String? vacationId;

  bool get isAdjusted => policy != null;
  bool get isSkipped => policy == VacationTaskPolicy.skip;
}

/// Pure scheduling policy used by both recurrence generation and repair of the
/// already-materialized near-term window.
///
/// A postponed occurrence keeps its original identity and is moved by its
/// offset inside the vacation. This is deterministic across devices and avoids
/// collapsing every delayed task onto the first day back.
class VacationPlanner {
  VacationPlanner(Iterable<VacationPeriod> periods)
    : periods = List.unmodifiable(
        periods.where((period) => period.enabled).toList()..sort((a, b) {
          final dateOrder = a.startsOn.compareTo(b.startsOn);
          return dateOrder != 0 ? dateOrder : a.id.compareTo(b.id);
        }),
      );

  final List<VacationPeriod> periods;

  VacationDisposition dispositionFor({
    required DateTime occurrenceDate,
    required String templateId,
  }) {
    final source = dateOnly(occurrenceDate);
    final matches = <(VacationPeriod, VacationOccurrence)>[];
    for (final period in periods) {
      if (!period.appliesToTemplate(templateId)) continue;
      final occurrence = period.occurrenceContaining(source);
      if (occurrence != null) matches.add((period, occurrence));
    }
    if (matches.isEmpty) return VacationDisposition.keep(source);

    final skipped = matches.where(
      (match) => match.$1.taskPolicy == VacationTaskPolicy.skip,
    );
    if (skipped.isNotEmpty) {
      final winner = skipped.reduce(
        (left, right) => left.$1.id.compareTo(right.$1.id) <= 0 ? left : right,
      );
      return VacationDisposition.adjusted(
        scheduledDate: source,
        policy: VacationTaskPolicy.skip,
        vacationId: winner.$1.id,
      );
    }

    var target = source;
    String? controllingId;
    // Overlapping or back-to-back vacations are followed until the postponed
    // task reaches a real working date. The bound is defensive against corrupt
    // imported data; valid user periods converge in only a few passes.
    for (var pass = 0; pass < periods.length + 2; pass++) {
      (VacationPeriod, VacationOccurrence)? blocking;
      for (final period in periods) {
        if (period.taskPolicy != VacationTaskPolicy.postpone ||
            !period.appliesToTemplate(templateId)) {
          continue;
        }
        final occurrence = period.occurrenceContaining(target);
        if (occurrence == null) continue;
        if (blocking == null ||
            occurrence.endsOn.isAfter(blocking.$2.endsOn) ||
            (occurrence.endsOn == blocking.$2.endsOn &&
                period.id.compareTo(blocking.$1.id) < 0)) {
          blocking = (period, occurrence);
        }
      }
      if (blocking == null) break;
      controllingId = blocking.$1.id;
      final offset = target.difference(blocking.$2.startsOn).inDays;
      target = blocking.$2.endsOn.add(Duration(days: offset + 1));
    }
    return VacationDisposition.adjusted(
      scheduledDate: target,
      policy: VacationTaskPolicy.postpone,
      vacationId: controllingId ?? matches.first.$1.id,
    );
  }
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String dateOnlyText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
