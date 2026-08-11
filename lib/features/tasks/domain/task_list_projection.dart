import '../../../core/database/app_database.dart';
import 'task_occurrence_policy.dart';

enum TaskListFilter {
  today,
  tomorrow,
  upcoming,
  active,
  paused,
  overdue,
  recurring,
  completed,
  completedToday,
  all,
}

extension TaskListFilterKey on TaskListFilter {
  String get localizationKey => switch (this) {
    TaskListFilter.today => 'task_filter_today',
    TaskListFilter.tomorrow => 'task_filter_tomorrow',
    TaskListFilter.upcoming => 'task_filter_upcoming',
    TaskListFilter.active => 'task_filter_active',
    TaskListFilter.paused => 'task_filter_paused',
    TaskListFilter.overdue => 'task_filter_overdue',
    TaskListFilter.recurring => 'task_filter_recurring',
    TaskListFilter.completed => 'task_filter_completed',
    TaskListFilter.completedToday => 'task_filter_completed_today',
    TaskListFilter.all => 'filter_all',
  };
}

class TaskListEntry {
  const TaskListEntry({
    required this.task,
    this.isRecurringTemplate = false,
    this.occurrenceCount = 1,
    this.nextOccurrence,
  });

  final LocalTask task;
  final bool isRecurringTemplate;
  final int occurrenceCount;
  final DateTime? nextOccurrence;
}

class TaskListQuery {
  const TaskListQuery({
    this.filter = TaskListFilter.all,
    this.search = '',
    this.domainId,
    this.roadmapId,
    this.executionMode,
    this.priority,
  });

  final TaskListFilter filter;
  final String search;
  final String? domainId;
  final String? roadmapId;
  final String? executionMode;
  final int? priority;

  List<TaskListEntry> apply(
    Iterable<LocalTask> source, {
    required DateTime now,
    required String timeZone,
  }) {
    final today = TaskOccurrencePolicy.localDateAt(now, timeZone: timeZone);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final normalizedSearch = search.trim().toLowerCase();
    final selected = source.where((task) {
      if (!TaskOccurrencePolicy.isRealOccurrence(task)) return false;
      if (normalizedSearch.isNotEmpty &&
          !task.title.toLowerCase().contains(normalizedSearch) &&
          !task.description.toLowerCase().contains(normalizedSearch)) {
        return false;
      }
      if (domainId != null && task.domainId != domainId) return false;
      if (roadmapId != null && task.roadmapId != roadmapId) return false;
      if (executionMode != null && task.executionMode != executionMode) {
        return false;
      }
      if (priority != null && task.priority != priority) return false;
      return switch (filter) {
        TaskListFilter.today =>
          TaskOccurrencePolicy.isOpenOccurrence(task) &&
              TaskOccurrencePolicy.isScheduledOn(
                task,
                today,
                timeZone: timeZone,
              ),
        TaskListFilter.tomorrow =>
          TaskOccurrencePolicy.isOpenOccurrence(task) &&
              TaskOccurrencePolicy.isScheduledOn(
                task,
                tomorrow,
                timeZone: timeZone,
              ),
        TaskListFilter.upcoming => TaskOccurrencePolicy.isUpcoming(
          task,
          now: now,
          timeZone: timeZone,
        ),
        TaskListFilter.active => task.status == 'in_progress',
        TaskListFilter.paused => task.status == 'paused',
        TaskListFilter.overdue => TaskOccurrencePolicy.isOverdue(
          task,
          now: now,
          timeZone: timeZone,
        ),
        TaskListFilter.recurring =>
          TaskOccurrencePolicy.isRecurringOccurrence(task) &&
              TaskOccurrencePolicy.isOpenOccurrence(task),
        TaskListFilter.completed => TaskOccurrencePolicy.isCompletedOccurrence(
          task,
        ),
        TaskListFilter.completedToday => TaskOccurrencePolicy.isCompletedOn(
          task,
          today,
          timeZone: timeZone,
        ),
        TaskListFilter.all => true,
      };
    }).toList();

    if (filter == TaskListFilter.completed ||
        filter == TaskListFilter.completedToday) {
      selected.sort(
        (left, right) => (right.actualFinish ?? right.updatedAt).compareTo(
          left.actualFinish ?? left.updatedAt,
        ),
      );
      return selected
          .map((task) => TaskListEntry(task: task))
          .toList(growable: false);
    }

    final standalone = <TaskListEntry>[];
    final recurring = <String, List<LocalTask>>{};
    for (final task in selected) {
      final identity = task.templateId;
      if (identity == null || identity.isEmpty) {
        standalone.add(TaskListEntry(task: task));
      } else {
        recurring.putIfAbsent(identity, () => <LocalTask>[]).add(task);
      }
    }
    for (final group in recurring.values) {
      group.sort((left, right) {
        final leftOpen = TaskOccurrencePolicy.isOpenOccurrence(left);
        final rightOpen = TaskOccurrencePolicy.isOpenOccurrence(right);
        if (leftOpen != rightOpen) return leftOpen ? -1 : 1;
        return _sortDate(left).compareTo(_sortDate(right));
      });
      final next = group
          .where(TaskOccurrencePolicy.isOpenOccurrence)
          .map((task) => task.plannedStart ?? task.scheduledDate)
          .whereType<DateTime>()
          .firstOrNull;
      standalone.add(
        TaskListEntry(
          task: group.first,
          isRecurringTemplate: true,
          occurrenceCount: group.length,
          nextOccurrence: next,
        ),
      );
    }
    standalone.sort(
      (left, right) => _sortDate(left.task).compareTo(_sortDate(right.task)),
    );
    return standalone;
  }

  static DateTime _sortDate(LocalTask task) =>
      task.plannedStart ??
      task.scheduledDate ??
      task.dueAt ??
      DateTime.fromMillisecondsSinceEpoch(8640000000000000);
}
