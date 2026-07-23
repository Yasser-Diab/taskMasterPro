import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/platform/app_notification_service.dart';
import '../../../core/widgets/app_controls.dart';
import '../application/task_action_controller.dart';
import '../domain/task_category.dart';
import '../domain/task_item.dart';
import '../domain/task_workspace_config.dart';
import 'task_editor_dialog.dart';
import 'task_workspace_screen.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({
    required this.tasks,
    required this.controller,
    required this.onAddTask,
    super.key,
  });

  final List<TaskItem> tasks;
  final TaskActionController controller;
  final VoidCallback onAddTask;

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  String _view = 'today';

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTasks();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.text('tasks')),
        actions: [
          IconButton(
            tooltip: context.text('quickAdd'),
            onPressed: widget.onAddTask,
            icon: const Icon(Icons.add_task_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAddTask,
        icon: const Icon(Icons.add_outlined),
        label: Text(context.text('quickAdd')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'today',
                    label: Text(context.text('today')),
                  ),
                  ButtonSegment(
                    value: 'upcoming',
                    label: Text(context.text('upcoming')),
                  ),
                  ButtonSegment(
                    value: 'list',
                    label: Text(context.text('list')),
                  ),
                  ButtonSegment(
                    value: 'overdue',
                    label: Text(context.text('overdue')),
                  ),
                  ButtonSegment(
                    value: 'waiting',
                    label: Text(context.text('waiting')),
                  ),
                  ButtonSegment(
                    value: 'completed',
                    label: Text(context.text('completed')),
                  ),
                  ButtonSegment(
                    value: 'review',
                    label: Text(context.text('reviewRequired')),
                  ),
                  ButtonSegment(
                    value: 'trash',
                    label: Text(context.text('trash')),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (value) {
                  setState(() => _view = value.first);
                },
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(context.text('nextAction')))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _view == 'trash'
                            ? _TrashTaskCard(
                                task: filtered[index],
                                controller: widget.controller,
                              )
                            : _TaskCard(
                                task: filtered[index],
                                controller: widget.controller,
                              );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<TaskItem> _filteredTasks() {
    final tasks = [...widget.tasks]
      ..sort((a, b) {
        final priority = a.priority.rank.compareTo(b.priority.rank);
        if (priority != 0) {
          return priority;
        }
        final aDue =
            a.effectiveDueUtc?.millisecondsSinceEpoch ?? 9999999999999;
        final bDue =
            b.effectiveDueUtc?.millisecondsSinceEpoch ?? 9999999999999;
        return aDue.compareTo(bDue);
      });

    return switch (_view) {
      'today' =>
        tasks.where((task) => task.isDueToday && !task.isCompleted).toList(),
      'upcoming' =>
        tasks
            .where(
              (task) =>
                  !task.isCompleted &&
                  (task.effectiveDueUtc?.isAfter(DateTime.now().toUtc()) ??
                      false),
            )
            .toList(),
      'overdue' => tasks.where((task) => task.isOverdue).toList(),
      'waiting' =>
        tasks.where((task) => task.status == TaskStatus.waiting).toList(),
      'completed' =>
        tasks.where((task) => task.status == TaskStatus.completed).toList(),
      'review' =>
        tasks
            .where((task) => task.status == TaskStatus.reviewRequired)
            .toList(),
      'trash' => widget.controller.deletedTasks,
      _ => tasks,
    };
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.controller});

  final TaskItem task;
  final TaskActionController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => _openWorkspace(context, 0),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _PriorityChip(priority: task.priority),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'open') {
                        _openWorkspace(context, 0);
                      } else if (value == 'edit' || value == 'move') {
                        await _editTask(context);
                      } else if (value == 'duplicate') {
                        await controller.duplicateTask(task);
                      } else if (value == 'skip') {
                        await controller.skipToday(task);
                      } else if (value == 'pause_recurrence') {
                        await controller.pauseRecurrence(task);
                      } else if (value == 'resume_recurrence') {
                        await controller.resumeRecurrence(task);
                      } else if (value == 'archive') {
                        await controller.archiveTask(task);
                      } else if (value == 'delete') {
                        await _confirmDelete(context);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'open',
                        child: Text(context.text('openTask')),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.text('editTask')),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text(context.text('duplicate')),
                      ),
                      if (task.recurrenceId != null ||
                          task.recurrence?.isNotEmpty == true) ...[
                        PopupMenuItem(
                          value: 'skip',
                          child: Text(context.text('skipToday')),
                        ),
                        PopupMenuItem(
                          value: task.recurrencePausedAt == null
                              ? 'pause_recurrence'
                              : 'resume_recurrence',
                          child: Text(
                            context.text(
                              task.recurrencePausedAt == null
                                  ? 'pauseRecurrence'
                                  : 'resumeRecurrence',
                            ),
                          ),
                        ),
                      ],
                      PopupMenuItem(
                        value: 'move',
                        child: Text(context.text('moveTask')),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(context.text('archiveTask')),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          context.text('deleteTask'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _TaskScheduleSummary(task: task),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.category_outlined, size: 16),
                    label: Text(task.category),
                  ),
                  if (task.project != null)
                    Chip(
                      avatar: const Icon(Icons.folder_outlined, size: 16),
                      label: Text(task.project!),
                    ),
                  if (task.roadmapPhase != null)
                    Chip(
                      avatar: const Icon(Icons.route_outlined, size: 16),
                      label: Text('Phase ${task.roadmapPhase}'),
                    ),
                  Chip(
                    avatar: Icon(_taskTypeIcon(task.taskType), size: 16),
                    label: Text(context.text('taskType_${task.taskType.name}')),
                  ),
                  if (task.taskType == TaskType.focus)
                    Chip(
                      avatar: const Icon(Icons.timer_outlined, size: 16),
                      label: Text(
                        '${task.estimatedPomodoros} ${context.text('pomodoros')}',
                      ),
                    ),
                  if (task.taskType == TaskType.timed)
                    Chip(
                      avatar: const Icon(Icons.schedule_outlined, size: 16),
                      label: Text(
                        '${context.text('planned')}: ${_formatMinutes(task.estimatedMinutes)}',
                      ),
                    ),
                  if (task.taskType == TaskType.event &&
                      task.location?.isNotEmpty == true)
                    Chip(
                      avatar: const Icon(Icons.location_on_outlined, size: 16),
                      label: Text(task.location!),
                    ),
                  if (task.taskType == TaskType.habit)
                    Chip(
                      avatar: const Icon(
                        Icons.local_fire_department_outlined,
                        size: 16,
                      ),
                      label: Text(
                        '${context.text('currentStreak')}: ${task.habitCurrentStreak}',
                      ),
                    ),
                  if (task.recurrence != null && task.recurrence!.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.repeat_outlined, size: 16),
                      label: Text(task.recurrence!),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.sticky_note_2_outlined, size: 16),
                    label: Text(
                      '${context.text('notes')}: ${controller.noteCount(task.id)}',
                    ),
                    onPressed: () => _openWorkspace(context, 4),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.report_problem_outlined, size: 16),
                    label: Text(
                      '${context.text('interruptions')}: ${controller.interruptionCount(task.id)}',
                    ),
                    onPressed: () => _openWorkspace(context, 3),
                  ),
                  Chip(
                    avatar: const Icon(Icons.trending_up_outlined, size: 16),
                    label: Text(
                      '${context.text('progress')}: ${task.progressPercentage}%',
                    ),
                  ),
                ],
              ),
              if (task.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(task.notes),
              ],
              const SizedBox(height: 10),
              LinearProgressIndicator(value: task.progressPercentage / 100),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((task.status == TaskStatus.notStarted ||
                          task.status == TaskStatus.ready) &&
                      (task.timerEnabled &&
                          task.taskType != TaskType.habit &&
                          task.taskType != TaskType.manual))
                    AppButton.filled(
                      onPressed: () => controller.startTask(task),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: Text(context.text('start')),
                    ),
                  if (task.status == TaskStatus.running)
                    AppButton.outlined(
                      onPressed: () => controller.pauseTask(task),
                      icon: const Icon(Icons.pause_outlined),
                      label: Text(context.text('pause')),
                    ),
                  if (task.status == TaskStatus.paused)
                    AppButton.filled(
                      onPressed: () => controller.resumeTask(task),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: Text(context.text('resume')),
                    ),
                  AppButton.outlined(
                    onPressed: () => _openWorkspace(context, 4),
                    icon: const Icon(Icons.note_add_outlined),
                    label: Text(context.text('notes')),
                  ),
                  if (!task.isCompleted)
                    AppButton.text(
                      onPressed: () => controller.completeTask(task),
                      icon: const Icon(Icons.done_all_outlined),
                      label: Text(context.text('completeTask')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTask(BuildContext context) async {
    final resources = await controller.resourcesForTask(task);
    final reminders = await controller.remindersForTask(task.id);
    final editorLinks = await controller.taskEditorLinks();
    if (!context.mounted) return;
    final result = await showDialog<TaskEditorResult>(
      context: context,
      builder: (context) => TaskEditorDialog(
        task: task,
        categories: controller.categories,
        resources: resources,
        reminders: reminders,
        editorLinks: editorLinks,
      ),
    );
    if (result == null) return;
    await controller.editTaskBundle(
      task: result.task,
      resources: result.resources,
      reminders: result.reminders,
      scope: result.scope,
    );
    if (!context.mounted) return;
    final notifications = AppServices.of(context).notificationService;
    if (controller.syncState == TaskSyncState.failed) {
      notifications.showError(
        context.text('taskUpdateFailed'),
        action: AppNotificationAction(
          label: context.text('retry'),
          onPressed: () => controller.editTaskBundle(
            task: result.task,
            resources: result.resources,
            reminders: result.reminders,
            scope: result.scope,
          ),
        ),
      );
    } else {
      notifications.showSuccess(context.text('taskUpdated'));
    }
  }

  void _openWorkspace(BuildContext context, int tab) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskWorkspaceScreen(
          controller: controller,
          task: task,
          initialTab: tab,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final active = controller.activeSession?.task.id == task.id;
    var discard = false;
    if (active) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.text('activeSessionRunning')),
          content: Text(context.text('deleteActiveTaskHelp')),
          actions: [
            AppButton.text(
              onPressed: () => Navigator.of(context).pop(),
              label: Text(context.text('cancel')),
            ),
            AppButton.outlined(
              onPressed: () => Navigator.of(context).pop('discard'),
              label: Text(context.text('discardSessionDelete')),
            ),
            AppButton.filled(
              onPressed: () => Navigator.of(context).pop('save'),
              label: Text(context.text('saveSessionDelete')),
            ),
          ],
        ),
      );
      if (action == null) {
        return;
      }
      discard = action == 'discard';
    } else if (task.recurrenceId != null ||
        task.recurrence?.isNotEmpty == true) {
      final scope = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(context.text('deleteRecurringScope')),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('this'),
              child: Text(context.text('thisOccurrenceOnly')),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('future'),
              child: Text(context.text('thisAndFutureOccurrences')),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('series'),
              child: Text(context.text('entireRecurringSeries')),
            ),
          ],
        ),
      );
      if (scope == null) {
        return;
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.text('deleteTask')),
          content: Text(context.text('deleteTaskHistoryWarning')),
          actions: [
            AppButton.text(
              onPressed: () => Navigator.of(context).pop(false),
              label: Text(context.text('cancel')),
            ),
            AppButton.filled(
              onPressed: () => Navigator.of(context).pop(true),
              label: Text(context.text('deleteTask')),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }

    await controller.deleteTask(task, discardActiveSession: discard);
    if (!context.mounted) {
      return;
    }
    AppServices.of(context).notificationService.showWarning(
      context.text('taskMovedToTrash'),
      action: AppNotificationAction(
        label: context.text('undo'),
        onPressed: () => controller.restoreTask(task),
      ),
    );
  }
}

class _TaskScheduleSummary extends StatelessWidget {
  const _TaskScheduleSummary({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final start = task.effectiveStartUtc;
    final end =
        task.plannedEndAt?.toUtc() ??
        task.scheduledEndAt?.toUtc() ??
        (start == null || task.estimatedMinutes <= 0
            ? null
            : start.add(Duration(minutes: task.estimatedMinutes)));
    if (start == null && end == null) {
      return Text(
        context.text('unscheduled'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final zoneService = AppServices.of(context).timeZoneService;
    final label = start == null
        ? zoneService.formatTaskDateTime(context, end!)
        : zoneService.formatTaskTimeRange(
            context,
            startUtc: start,
            endUtc: end,
          );
    return Row(
      children: [
        const Icon(Icons.schedule_outlined, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

IconData _taskTypeIcon(TaskType type) {
  return switch (type) {
    TaskType.focus => Icons.center_focus_strong_outlined,
    TaskType.timed => Icons.timer_outlined,
    TaskType.event => Icons.event_outlined,
    TaskType.habit => Icons.repeat_on_outlined,
    TaskType.reading => Icons.menu_book_outlined,
    TaskType.manual => Icons.check_circle_outline,
  };
}

String _formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

String _formatTaskDateTime(BuildContext context, DateTime value) {
  return AppServices.of(
    context,
  ).timeZoneService.formatTaskDateTime(context, value.toUtc());
}

class _TrashTaskCard extends StatelessWidget {
  const _TrashTaskCard({required this.task, required this.controller});

  final TaskItem task;
  final TaskActionController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.delete_outline),
        title: Text(task.title),
        subtitle: Text(
          '${task.category}\n'
          '${context.text('deleted')}: ${task.deletedAt == null ? context.text('unknown') : _formatTaskDateTime(context, task.deletedAt!)}',
        ),
        isThreeLine: true,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TaskWorkspaceScreen(
                controller: controller,
                task: task,
                initialTab: 0,
              ),
            ),
          );
        },
        trailing: Wrap(
          spacing: 8,
          children: [
            AppButton.text(
              onPressed: () async {
                await controller.restoreTask(task);
                if (context.mounted) {
                  AppServices.of(context).notificationService.showSuccess(
                    context.text('taskRestored'),
                  );
                }
              },
              label: Text(context.text('restore')),
            ),
            AppButton.text(
              onPressed: () => _confirmPermanentDelete(context),
              label: Text(context.text('deletePermanently')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmPermanentDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.text('deletePermanently')),
        content: Text(context.text('permanentDeleteTaskWarning')),
        actions: [
          AppButton.text(
            onPressed: () => Navigator.of(context).pop(false),
            label: Text(context.text('cancel')),
          ),
          AppButton.filled(
            onPressed: () => Navigator.of(context).pop(true),
            label: Text(context.text('deletePermanently')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.permanentlyDeleteTask(task);
    }
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      TaskPriority.critical => Theme.of(context).colorScheme.error,
      TaskPriority.high => Colors.orange,
      TaskPriority.normal => Theme.of(context).colorScheme.primary,
      TaskPriority.low => Colors.grey,
    };

    return Chip(
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      label: Text(priority.name),
    );
  }
}

class QuickTaskDialog extends StatefulWidget {
  const QuickTaskDialog({required this.categories, super.key});

  final List<TaskCategory> categories;

  @override
  State<QuickTaskDialog> createState() => _QuickTaskDialogState();
}

class _QuickTaskDialogState extends State<QuickTaskDialog> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final _workspaceUrlController = TextEditingController();
  final _workspaceHomeController = TextEditingController();
  final _workspaceTitleController = TextEditingController();
  late String _category;
  TaskPriority _priority = TaskPriority.normal;
  int _estimatedPomodoros = 1;
  bool _dueToday = true;
  bool _isRecurring = false;
  String _repeatPreset = 'weekly';
  bool _workspaceEnabled = false;
  TaskWorkspaceType _workspaceType = TaskWorkspaceType.none;
  TaskTrackingMode _trackingMode = TaskTrackingMode.interactive;
  TaskWorkspaceDockState _dockState = TaskWorkspaceDockState.docked;
  TaskWorkspaceNavigationMode _navigationMode =
      TaskWorkspaceNavigationMode.normalBrowsing;
  bool _openAutomatically = true;
  bool _restoreLastPage = true;
  bool _restoreBrowserSession = true;
  bool _restoreOpenTabs = true;
  bool _openStartingPageInNewTab = false;
  bool _allowExternalNavigation = true;

  List<TaskCategory> get _categories => widget.categories.isNotEmpty
      ? widget.categories
      : defaultLifeAreaTemplates;

  @override
  void initState() {
    super.initState();
    _category = _categories.first.name;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _workspaceUrlController.dispose();
    _workspaceHomeController.dispose();
    _workspaceTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.text('quickAdd')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.text('taskTitle'),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: context.text('category'),
                ),
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category.name,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskPriority>(
                initialValue: _priority,
                decoration: InputDecoration(
                  labelText: context.text('priority'),
                ),
                items: [
                  for (final priority in TaskPriority.values)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(priority.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _priority = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(context.text('estimatedPomodoros'))),
                  IconButton(
                    onPressed: _estimatedPomodoros > 1
                        ? () => setState(() => _estimatedPomodoros -= 1)
                        : null,
                    icon: const Icon(Icons.remove_outlined),
                  ),
                  Text('$_estimatedPomodoros'),
                  IconButton(
                    onPressed: () => setState(() => _estimatedPomodoros += 1),
                    icon: const Icon(Icons.add_outlined),
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _dueToday,
                title: Text(context.text('today')),
                onChanged: (value) => setState(() => _dueToday = value ?? true),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(context.text('oneTime')),
                    icon: const Icon(Icons.event_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(context.text('recurring')),
                    icon: const Icon(Icons.repeat_outlined),
                  ),
                ],
                selected: {_isRecurring},
                onSelectionChanged: (selection) {
                  setState(() => _isRecurring = selection.first);
                },
              ),
              if (_isRecurring) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _repeatPreset,
                  decoration: InputDecoration(
                    labelText: context.text('repeat'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'daily',
                      child: Text(context.text('repeatDaily')),
                    ),
                    DropdownMenuItem(
                      value: 'weekday',
                      child: Text(context.text('repeatWeekday')),
                    ),
                    DropdownMenuItem(
                      value: 'weekend',
                      child: Text(context.text('repeatWeekend')),
                    ),
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text(context.text('repeatWeekly')),
                    ),
                    DropdownMenuItem(
                      value: 'two_weeks',
                      child: Text(context.text('repeatTwoWeeks')),
                    ),
                    DropdownMenuItem(
                      value: 'monthly',
                      child: Text(context.text('repeatMonthly')),
                    ),
                    DropdownMenuItem(
                      value: 'yearly',
                      child: Text(context.text('repeatYearly')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _repeatPreset = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _recurrenceSummary(context),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: context.text('notes')),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(context.text('workspaceResources')),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _workspaceEnabled,
                    title: Text(context.text('enableTaskWorkspace')),
                    onChanged: (value) {
                      setState(() {
                        _workspaceEnabled = value;
                        if (value && _workspaceType == TaskWorkspaceType.none) {
                          _workspaceType = TaskWorkspaceType.inAppBrowser;
                        }
                        if (!value) {
                          _workspaceType = TaskWorkspaceType.none;
                        }
                      });
                    },
                  ),
                  DropdownButtonFormField<TaskWorkspaceType>(
                    initialValue: _workspaceType,
                    decoration: InputDecoration(
                      labelText: context.text('workspaceType'),
                    ),
                    items: [
                      for (final type in TaskWorkspaceType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(_workspaceTypeLabel(context, type)),
                        ),
                    ],
                    onChanged: _workspaceEnabled
                        ? (value) {
                            if (value != null) {
                              setState(() => _workspaceType = value);
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _workspaceUrlController,
                    enabled: _workspaceEnabled,
                    decoration: InputDecoration(
                      labelText: context.text('startingUrl'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _workspaceHomeController,
                    enabled: _workspaceEnabled,
                    decoration: InputDecoration(
                      labelText: context.text('homepageUrl'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _workspaceTitleController,
                    enabled: _workspaceEnabled,
                    decoration: InputDecoration(
                      labelText: context.text('resourceTitle'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TaskTrackingMode>(
                    initialValue: _trackingMode,
                    decoration: InputDecoration(
                      labelText: context.text('preferredTrackingMode'),
                    ),
                    items: [
                      for (final mode in TaskTrackingMode.values)
                        DropdownMenuItem(
                          value: mode,
                          child: Text(_trackingModeLabel(context, mode)),
                        ),
                    ],
                    onChanged: _workspaceEnabled
                        ? (value) {
                            if (value != null) {
                              setState(() => _trackingMode = value);
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TaskWorkspaceDockState>(
                    initialValue: _dockState,
                    decoration: InputDecoration(
                      labelText: context.text('preferredDockState'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: TaskWorkspaceDockState.docked,
                        child: Text(context.text('docked')),
                      ),
                      DropdownMenuItem(
                        value: TaskWorkspaceDockState.detached,
                        child: Text(context.text('detached')),
                      ),
                    ],
                    onChanged: _workspaceEnabled
                        ? (value) {
                            if (value != null) {
                              setState(() => _dockState = value);
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TaskWorkspaceNavigationMode>(
                    initialValue: _navigationMode,
                    decoration: InputDecoration(
                      labelText: context.text('navigationMode'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: TaskWorkspaceNavigationMode.normalBrowsing,
                        child: Text(context.text('normalBrowsing')),
                      ),
                      DropdownMenuItem(
                        value: TaskWorkspaceNavigationMode.trustedDomainsOnly,
                        child: Text(context.text('trustedDomainsOnly')),
                      ),
                      DropdownMenuItem(
                        value: TaskWorkspaceNavigationMode.startingDomainOnly,
                        child: Text(context.text('startingDomainOnly')),
                      ),
                    ],
                    onChanged: _workspaceEnabled
                        ? (value) {
                            if (value != null) {
                              setState(() => _navigationMode = value);
                            }
                          }
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _openAutomatically,
                    title: Text(context.text('openAutomatically')),
                    onChanged: _workspaceEnabled
                        ? (value) =>
                              setState(() => _openAutomatically = value ?? true)
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _restoreLastPage,
                    title: Text(context.text('restoreLastPage')),
                    onChanged: _workspaceEnabled
                        ? (value) =>
                              setState(() => _restoreLastPage = value ?? true)
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _restoreBrowserSession,
                    title: Text(context.text('restoreBrowserSession')),
                    onChanged: _workspaceEnabled
                        ? (value) => setState(
                            () => _restoreBrowserSession = value ?? true,
                          )
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _restoreOpenTabs,
                    title: Text(context.text('restoreOpenTabs')),
                    onChanged: _workspaceEnabled
                        ? (value) =>
                              setState(() => _restoreOpenTabs = value ?? true)
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _openStartingPageInNewTab,
                    title: Text(context.text('openStartingPageNewTab')),
                    onChanged: _workspaceEnabled
                        ? (value) => setState(
                            () => _openStartingPageInNewTab = value ?? false,
                          )
                        : null,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowExternalNavigation,
                    title: Text(context.text('allowExternalNavigation')),
                    onChanged: _workspaceEnabled
                        ? (value) => setState(
                            () => _allowExternalNavigation = value ?? true,
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.text('cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(context.text('saveTask'))),
      ],
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    final now = DateTime.now();
    Navigator.of(context).pop(
      TaskItem(
        title: title,
        category: _category,
        priority: _priority,
        dueDate: _dueToday ? DateTime(now.year, now.month, now.day) : null,
        estimatedPomodoros: _estimatedPomodoros,
        estimatedMinutes: _estimatedPomodoros * 25,
        recurrence: _isRecurring ? _recurrenceSummary(context) : null,
        reminderRules: _isRecurring
            ? {'repeatPreset': _repeatPreset}
            : const {},
        notes: _notesController.text.trim(),
        workspaceEnabled: _workspaceEnabled,
        workspaceType: _workspaceEnabled
            ? _workspaceType
            : TaskWorkspaceType.none,
        workspaceStartingUrl: _workspaceUrlController.text.trim().isEmpty
            ? null
            : _workspaceUrlController.text.trim(),
        workspaceHomeUrl: _workspaceHomeController.text.trim().isEmpty
            ? null
            : _workspaceHomeController.text.trim(),
        workspaceResourceTitle: _workspaceTitleController.text.trim().isEmpty
            ? null
            : _workspaceTitleController.text.trim(),
        workspaceBrowserMode: _trackingMode,
        workspaceOpenAutomatically: _openAutomatically,
        workspaceRestoreLastPage: _restoreLastPage,
        workspacePreferredDockState: _dockState,
        workspaceAllowExternalNavigation: _allowExternalNavigation,
        workspaceNavigationMode: _navigationMode,
        workspaceRestoreBrowserSession: _restoreBrowserSession,
        workspaceRestoreOpenTabs: _restoreOpenTabs,
        workspaceOpenStartingPageInNewTab: _openStartingPageInNewTab,
        learningResourceLink: _workspaceUrlController.text.trim().isEmpty
            ? null
            : _workspaceUrlController.text.trim(),
      ),
    );
  }

  String _recurrenceSummary(BuildContext context) {
    return switch (_repeatPreset) {
      'daily' => context.text('repeatDaily'),
      'weekday' => context.text('repeatWeekday'),
      'weekend' => context.text('repeatWeekend'),
      'two_weeks' => context.text('repeatTwoWeeks'),
      'monthly' => context.text('repeatMonthly'),
      'yearly' => context.text('repeatYearly'),
      _ => context.text('repeatWeekly'),
    };
  }
}

String _workspaceTypeLabel(BuildContext context, TaskWorkspaceType type) {
  return switch (type) {
    TaskWorkspaceType.none => context.text('noWorkspace'),
    TaskWorkspaceType.inAppBrowser => context.text('inAppBrowser'),
    TaskWorkspaceType.externalBrowser => context.text('externalBrowser'),
    TaskWorkspaceType.localFileOrFolder => context.text('localFileFolder'),
    TaskWorkspaceType.applicationShortcut => context.text(
      'applicationShortcut',
    ),
  };
}

String _trackingModeLabel(BuildContext context, TaskTrackingMode mode) {
  return switch (mode) {
    TaskTrackingMode.interactive => context.text('interactiveMode'),
    TaskTrackingMode.video => context.text('videoMode'),
    TaskTrackingMode.reading => context.text('readingMode'),
    TaskTrackingMode.manual => context.text('manualMode'),
  };
}
