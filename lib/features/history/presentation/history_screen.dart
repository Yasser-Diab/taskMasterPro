import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../sessions/application/time_analytics_service.dart';
import '../../sessions/domain/session_models.dart';
import '../../tasks/application/task_action_controller.dart';
import '../../tasks/domain/task_item.dart';
import '../../tasks/presentation/task_workspace_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    required this.controller,
    required this.tasks,
    super.key,
  });

  final TaskActionController controller;
  final List<TaskItem> tasks;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = _todayOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final sessions = widget.controller.sessions;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.text('history')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.text('calendar')),
              Tab(text: context.text('agenda')),
              Tab(text: context.text('timeline')),
              Tab(text: context.text('reports')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CalendarTab(
              controller: widget.controller,
              tasks: widget.tasks,
              sessions: sessions,
              visibleMonth: _visibleMonth,
              selectedDay: _selectedDay,
              onMonthChanged: (month) => setState(() => _visibleMonth = month),
              onDaySelected: (day) => setState(() => _selectedDay = day),
            ),
            _AgendaTab(
              controller: widget.controller,
              tasks: widget.tasks,
              sessions: sessions,
            ),
            _TimelineTab(sessions: sessions),
            _ReportsTab(tasks: widget.tasks, sessions: sessions),
          ],
        ),
      ),
    );
  }
}

class _CalendarTab extends StatelessWidget {
  const _CalendarTab({
    required this.controller,
    required this.tasks,
    required this.sessions,
    required this.visibleMonth,
    required this.selectedDay,
    required this.onMonthChanged,
    required this.onDaySelected,
  });

  final TaskActionController controller;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final calendar = _MonthGrid(
      tasks: tasks,
      sessions: sessions,
      visibleMonth: visibleMonth,
      selectedDay: selectedDay,
      onDaySelected: onDaySelected,
      onPrevious: () =>
          onMonthChanged(DateTime(visibleMonth.year, visibleMonth.month - 1)),
      onNext: () =>
          onMonthChanged(DateTime(visibleMonth.year, visibleMonth.month + 1)),
    );
    final detail = _DayHistoryPanel(
      controller: controller,
      tasks: tasks,
      sessions: sessions,
      day: selectedDay,
    );

    return wide
        ? Row(
            children: [
              Expanded(flex: 2, child: calendar),
              const VerticalDivider(width: 1),
              SizedBox(width: 380, child: detail),
            ],
          )
        : Column(
            children: [
              Expanded(child: calendar),
              const Divider(height: 1),
              SizedBox(height: 340, child: detail),
            ],
          );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.tasks,
    required this.sessions,
    required this.visibleMonth,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPrevious,
    required this.onNext,
  });

  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month);
    final leading = first.weekday % 7;
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final totalCells = rows * 7;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_outlined),
              ),
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatMonthYear(first),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -120) onNext();
              if (velocity > 120) onPrevious();
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.05,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: totalCells,
              itemBuilder: (context, index) {
                final dayNumber = index - leading + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final day = DateTime(
                  visibleMonth.year,
                  visibleMonth.month,
                  dayNumber,
                );
                final daySessions = _sessionsOnDay(sessions, day);
                final dayTasks = _tasksOnDay(tasks, day);
                final activeSeconds = daySessions.fold<int>(
                  0,
                  (total, session) => total + session.activeSeconds,
                );
                final completed = dayTasks
                    .where((task) => task.isCompleted)
                    .length;
                final selected = _sameDay(day, selectedDay);
                final today = _sameDay(day, _todayOnly(DateTime.now()));
                final colorScheme = Theme.of(context).colorScheme;
                return Semantics(
                  button: true,
                  label:
                      '${MaterialLocalizations.of(context).formatFullDate(day)}, ${formatDurationCompact(activeSeconds)} ${context.text('active')}, ${daySessions.length} ${context.text('sessions')}',
                  child: InkWell(
                    onTap: () => onDaySelected(day),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? colorScheme.primaryContainer.withValues(
                                alpha: 0.35,
                              )
                            : null,
                        border: Border.all(
                          color: selected
                              ? colorScheme.primary
                              : today
                              ? colorScheme.secondary
                              : Theme.of(context).dividerColor,
                          width: selected || today ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: today
                                  ? BoxDecoration(
                                      color: colorScheme.secondaryContainer,
                                      shape: BoxShape.circle,
                                    )
                                  : null,
                              child: Text(
                                '$dayNumber',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (activeSeconds > 0)
                                  _DayStatusDot(color: colorScheme.primary),
                                if (daySessions.isNotEmpty)
                                  _DayStatusDot(color: colorScheme.tertiary),
                                if (completed > 0)
                                  _DayStatusDot(color: colorScheme.secondary),
                              ].take(3).toList(),
                            ),
                            const Spacer(),
                            if (daySessions.isNotEmpty || dayTasks.isNotEmpty)
                              Container(
                                constraints: const BoxConstraints(minWidth: 22),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${daySessions.length + dayTasks.length}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DayStatusDot extends StatelessWidget {
  const _DayStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DayHistoryPanel extends StatelessWidget {
  const _DayHistoryPanel({
    required this.controller,
    required this.tasks,
    required this.sessions,
    required this.day,
  });

  final TaskActionController controller;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final dayTasks = _tasksOnDay(tasks, day);
    final daySessions = _sessionsOnDay(sessions, day);
    final totals = const TimeAnalyticsService().fromSessions(daySessions);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          MaterialLocalizations.of(context).formatFullDate(day),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _MetricRow(
          label: context.text('active'),
          value: formatDurationCompact(totals.activeSeconds),
        ),
        _MetricRow(
          label: context.text('idle'),
          value: formatDurationCompact(totals.idleSeconds),
        ),
        _MetricRow(
          label: context.text('paused'),
          value: formatDurationCompact(totals.pausedSeconds),
        ),
        _MetricRow(
          label: context.text('interrupted'),
          value: formatDurationCompact(totals.interruptedSeconds),
        ),
        const Divider(),
        Text(
          context.text('sessions'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (daySessions.isEmpty)
          Text(context.text('noRecordedSessions'))
        else
          for (final session in daySessions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_taskTitle(tasks, session.taskId)),
              subtitle: Text(
                '${_timeLabel(session.startedAt)}-${session.endedAt == null ? context.text('running') : _timeLabel(session.endedAt!)} • ${formatDurationCompact(session.activeSeconds)}',
              ),
            ),
        const Divider(),
        Text(
          context.text('tasks'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (dayTasks.isEmpty)
          Text(context.text('none'))
        else
          for (final task in dayTasks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(task.title),
              subtitle: Text('${task.category} • ${task.status.name}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TaskWorkspaceScreen(
                    controller: controller,
                    task: task,
                    initialTab: task.isCompleted ? 5 : 0,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _AgendaTab extends StatelessWidget {
  const _AgendaTab({
    required this.controller,
    required this.tasks,
    required this.sessions,
  });

  final TaskActionController controller;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;

  @override
  Widget build(BuildContext context) {
    final ordered = [...sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final session = ordered[index];
        final task = tasks
            .where((item) => item.id == session.taskId)
            .firstOrNull;
        return ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: Text(task?.title ?? context.text('session')),
          subtitle: Text(
            '${MaterialLocalizations.of(context).formatFullDate(session.startedAt)} • ${formatDurationCompact(session.activeSeconds)}',
          ),
          onTap: task == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TaskWorkspaceScreen(
                      controller: controller,
                      task: task,
                      initialTab: 5,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.sessions});

  final List<TrackedSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Center(child: Text(context.text('noRecordedSessions')));
    }
    final ordered = [...sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final session = ordered[index];
        return ListTile(
          leading: const Icon(Icons.timeline_outlined),
          title: Text(session.categoryName ?? session.type.name),
          subtitle: Text(
            '${_dateLabel(context, session.startedAt)} • ${formatDurationCompact(session.grossSeconds)}',
          ),
        );
      },
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({required this.tasks, required this.sessions});

  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;

  @override
  Widget build(BuildContext context) {
    final totals = const TimeAnalyticsService().fromSessions(sessions);
    final completed = tasks.where((task) => task.isCompleted).length;
    final plannedSeconds = tasks.fold<int>(
      0,
      (total, task) => total + task.estimatedMinutes * 60,
    );
    final accuracy = const TimeAnalyticsService()
        .compareEstimate(
          estimatedMinutes: plannedSeconds ~/ 60,
          actualActiveSeconds: totals.activeSeconds,
        )
        .accuracy;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _MetricRow(
          label: context.text('recordedFocusTime'),
          value: formatDurationCompact(totals.grossSeconds),
        ),
        _MetricRow(
          label: context.text('verifiedActiveTime'),
          value: formatDurationCompact(totals.activeSeconds),
        ),
        _MetricRow(
          label: context.text('interruptedTime'),
          value: formatDurationCompact(totals.interruptedSeconds),
        ),
        _MetricRow(
          label: context.text('tasksCompleted'),
          value: completed.toString(),
        ),
        _MetricRow(
          label: context.text('estimateAccuracy'),
          value: '${(accuracy * 100).round()}%',
        ),
        const SizedBox(height: 16),
        Text(
          totals.activeSeconds == 0
              ? context.text('noTrackingDataHonest')
              : context.text('reportTraceableToSessions'),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

List<TaskItem> _tasksOnDay(List<TaskItem> tasks, DateTime day) {
  return tasks.where((task) {
    final due = task.dueDate;
    if (due != null && _sameDay(due, day)) {
      return true;
    }
    return task.isCompleted && _sameDay(task.updatedAt, day);
  }).toList();
}

List<TrackedSession> _sessionsOnDay(
  List<TrackedSession> sessions,
  DateTime day,
) {
  return sessions.where((session) => _sameDay(session.startedAt, day)).toList();
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime _todayOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _taskTitle(List<TaskItem> tasks, String taskId) {
  return tasks.where((task) => task.id == taskId).firstOrNull?.title ??
      'Session';
}

String _dateLabel(BuildContext context, DateTime date) {
  return MaterialLocalizations.of(context).formatFullDate(date);
}

String _timeLabel(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
