import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../../health/presentation/task_health_evidence_strip.dart';
import '../../roadmaps/presentation/roadmaps_screen.dart';
import '../../activity/presentation/task_activity_panel.dart';
import '../data/installed_application_service.dart';
import '../data/task_execution_commands.dart';
import '../data/task_execution_providers.dart';
import '../data/task_resource_service.dart';
import '../data/website_rule_service.dart';
import '../domain/pomodoro_execution_state.dart';
import '../domain/task_resource_launch.dart';
import 'task_browser_workspace.dart';
import 'task_completion_flow.dart';
import 'task_document_workspace.dart';
import 'task_editor_dialog.dart';
import 'installed_application_picker_dialog.dart';
import 'interruption_editor_dialog.dart';
import 'task_start_flow.dart';

class TaskWorkspaceScreen extends ConsumerStatefulWidget {
  const TaskWorkspaceScreen({
    required this.taskId,
    this.initialSection = 0,
    this.initialBrowserUrl,
    super.key,
  });

  final String taskId;
  final int initialSection;
  final String? initialBrowserUrl;

  static Future<void> open(
    BuildContext context,
    LocalTask task, {
    int initialSection = 0,
    String? initialBrowserUrl,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskWorkspaceScreen(
          taskId: task.id,
          initialSection: initialSection,
          initialBrowserUrl: initialBrowserUrl,
        ),
      ),
    );
  }

  @override
  ConsumerState<TaskWorkspaceScreen> createState() =>
      _TaskWorkspaceScreenState();
}

class _TaskWorkspaceScreenState extends ConsumerState<TaskWorkspaceScreen> {
  static const _browserSectionIndex = 3;

  late int _section;
  String? _browserInitialUrl;
  bool _browserWorkspaceStarted = false;
  bool _browserFullScreen = false;
  final GlobalKey _browserWorkspaceKey = GlobalKey(
    debugLabel: 'task-browser-workspace',
  );

  static const _sections = <(String, IconData)>[
    ('workspace_overview', Icons.dashboard_outlined),
    ('workspace_execute', Icons.play_circle_outline),
    ('workspace_checklist', Icons.checklist),
    ('workspace_browser', Icons.language),
    ('workspace_resources', Icons.folder_copy_outlined),
    ('workspace_connections', Icons.hub_outlined),
    ('workspace_notes', Icons.notes_outlined),
    ('activity', Icons.insights_outlined),
    ('workspace_history', Icons.history),
    ('settings', Icons.tune),
  ];

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection.clamp(0, _sections.length - 1);
    _browserInitialUrl = widget.initialBrowserUrl;
    _browserWorkspaceStarted =
        _section == _browserSectionIndex ||
        (_browserInitialUrl?.trim().isNotEmpty ?? false);
  }

  @override
  void dispose() {
    if (_browserFullScreen && Platform.isAndroid) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = ref.watch(taskExecutionTaskProvider(widget.taskId)).value;
    if (task == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_browserFullScreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setBrowserFullScreen(false);
        },
        child: Scaffold(
          body: SafeArea(child: _browserWorkspace(task, fullScreen: true)),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 920;
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    final ownsRuntime = runtime?.activeTaskId == task.id;
    final pomodoro = ownsRuntime && task.executionMode == 'pomodoro'
        ? PomodoroExecutionSnapshot.fromTask(
            task: task,
            runtime: runtime,
            now: DateTime.now().toUtc(),
          )
        : null;
    final stateLabel = !ownsRuntime
        ? context.l10n.taskStatus(task.status)
        : runtime?.state == 'break'
        ? context.l10n.text(
            pomodoro?.isWaiting == true
                ? 'notification_break_completed_title'
                : 'break_in_progress',
          )
        : context.l10n.taskStatus(runtime?.state ?? task.status);
    final note = task.description.trim();
    final executionSummary =
        '${context.l10n.executionMode(task.executionMode)} · $stateLabel';
    final taskSubheading = note.isEmpty
        ? executionSummary
        : '$note · $executionSummary';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Tooltip(
              message: taskSubheading,
              child: Text(
                taskSubheading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.text('task_edit'),
            onPressed: () => TaskEditorDialog.show(context, task: task),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.text('task_actions'),
            onSelected: (action) => _taskAction(task, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'duplicate',
                child: Text(context.l10n.text('task_duplicate')),
              ),
              PopupMenuItem(
                value: 'postpone',
                child: Text(context.l10n.text('task_postpone')),
              ),
              if (task.status == 'completed')
                PopupMenuItem(
                  value: 'reopen',
                  child: Text(context.l10n.text('reopen_task')),
                )
              else
                PopupMenuItem(
                  value: 'complete',
                  child: Text(context.l10n.text('task_mark_complete')),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Text(context.l10n.text('task_delete')),
              ),
            ],
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _section,
                  onDestinationSelected: _selectSection,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final section in _sections)
                      NavigationRailDestination(
                        icon: Icon(section.$2),
                        selectedIcon: Icon(section.$2),
                        label: Text(context.l10n.text(section.$1)),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _page(task)),
              ],
            )
          : Column(
              children: [
                SizedBox(
                  height: 54,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemBuilder: (context, index) => ChoiceChip(
                      selected: _section == index,
                      avatar: Icon(_sections[index].$2, size: 18),
                      label: Text(context.l10n.text(_sections[index].$1)),
                      onSelected: (_) => _selectSection(index),
                    ),
                    separatorBuilder: (_, _) => const SizedBox(width: 7),
                    itemCount: _sections.length,
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _page(task)),
              ],
            ),
    );
  }

  Widget _page(LocalTask task) {
    final page = switch (_section) {
      0 => _TaskOverview(task: task, onOpenSection: _openSection),
      1 => _TaskExecutionPanel(
        task: task,
        onOpenResource: _openBrowserResource,
      ),
      2 => _ChecklistPanel(task: task),
      _browserSectionIndex => const SizedBox.expand(),
      4 => _ResourcesPanel(task: task, onOpenUrl: _openBrowserResource),
      5 => _ConnectionsPanel(task: task),
      6 => _NotesPanel(task: task),
      7 => TaskActivityPanel(task: task),
      8 => _HistoryPanel(task: task),
      _ => _TaskSettingsPanel(task: task),
    };
    if (!_browserWorkspaceStarted) return page;

    // The browser is intentionally kept in the tree once it has been opened.
    // Leaving Browser for Overview, Checklist, or any other workspace section
    // must not dispose its WebViews or reset an in-progress lesson.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_section != _browserSectionIndex) page,
        Offstage(
          offstage: _section != _browserSectionIndex,
          child: TickerMode(
            enabled: _section == _browserSectionIndex,
            child: _browserWorkspace(task),
          ),
        ),
      ],
    );
  }

  void _openSection(int index) => _selectSection(index);

  void _selectSection(int index) {
    setState(() {
      _section = index;
      if (index == _browserSectionIndex) _browserWorkspaceStarted = true;
    });
  }

  Widget _browserWorkspace(LocalTask task, {bool fullScreen = false}) {
    return TaskBrowserWorkspace(
      key: _browserWorkspaceKey,
      task: task,
      initialUrl: _browserInitialUrl,
      fullScreen: fullScreen,
      onFullScreenChanged: _setBrowserFullScreen,
    );
  }

  void _setBrowserFullScreen(bool fullScreen) {
    if (_browserFullScreen == fullScreen || !mounted) return;
    setState(() => _browserFullScreen = fullScreen);
    if (!Platform.isAndroid) return;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  void _openBrowserResource(String url) {
    setState(() {
      _browserInitialUrl = url;
      _section = _browserSectionIndex;
      _browserWorkspaceStarted = true;
    });
  }

  Future<void> _taskAction(LocalTask task, String action) async {
    final repository = ref.read(taskRepositoryProvider);
    switch (action) {
      case 'duplicate':
        await repository.duplicate(task);
      case 'postpone':
        final date = await showDatePicker(
          context: context,
          initialDate: (task.scheduledDate ?? DateTime.now()).add(
            const Duration(days: 1),
          ),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (date != null) await repository.reschedule(task, date);
      case 'complete':
        await completeTaskWithUndo(context, ref, task);
        return;
      case 'reopen':
        await reopenTask(context, ref, task);
        return;
      case 'delete':
        final confirmed = await _confirm(
          context,
          title: context.l10n.text('task_delete_title'),
          body: context.l10n.text('task_delete_description'),
          confirmLabel: context.l10n.text('delete'),
        );
        if (confirmed) {
          await repository.softDelete(task);
          if (mounted) Navigator.pop(context);
        }
    }
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
}

class _TaskOverview extends ConsumerWidget {
  const _TaskOverview({required this.task, required this.onOpenSection});

  final LocalTask task;
  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = MaterialLocalizations.of(context);
    final planned = task.plannedStart?.toLocal();
    final due = task.dueAt?.toLocal();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _LiveTaskMetrics(task: task),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.text('plan'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (task.description.trim().isNotEmpty) ...[
                  Text(
                    context.l10n.text('task_subheading_note'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.description.trim(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: context.l10n.text('status_scheduled'),
                  value: task.scheduledDate == null
                      ? context.l10n.text('flexible')
                      : local.formatFullDate(task.scheduledDate!.toLocal()),
                ),
                _InfoRow(
                  icon: Icons.access_time,
                  label: context.l10n.text('local_start'),
                  value: planned == null
                      ? context.l10n.text('not_fixed')
                      : '${local.formatMediumDate(planned)} · '
                            '${local.formatTimeOfDay(TimeOfDay.fromDateTime(planned))}',
                ),
                _InfoRow(
                  icon: Icons.event_available_outlined,
                  label: context.l10n.text('due'),
                  value: due == null
                      ? context.l10n.text('no_deadline')
                      : '${local.formatMediumDate(due)} · '
                            '${local.formatTimeOfDay(TimeOfDay.fromDateTime(due))}',
                ),
                _InfoRow(
                  icon: Icons.public,
                  label: context.l10n.text('local_time'),
                  value: context.l10n.text('local_time_detail'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.l10n.text('task_workspace'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.65,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _WorkspaceShortcut(
              icon: Icons.play_circle_outline,
              title: context.l10n.text('workspace_execute'),
              subtitle: context.l10n.text('workspace_execute_detail'),
              onTap: () => onOpenSection(1),
            ),
            _WorkspaceShortcut(
              icon: Icons.language,
              title: context.l10n.text('task_browser'),
              subtitle: context.l10n.text('task_browser_detail'),
              onTap: () => onOpenSection(3),
            ),
            _WorkspaceShortcut(
              icon: Icons.folder_copy_outlined,
              title: context.l10n.text('workspace_resources'),
              subtitle: context.l10n.text('task_resources_detail'),
              onTap: () => onOpenSection(4),
            ),
            _WorkspaceShortcut(
              icon: Icons.hub_outlined,
              title: context.l10n.text('workspace_connections'),
              subtitle: context.l10n.text('task_connections_detail'),
              onTap: () => onOpenSection(5),
            ),
            _WorkspaceShortcut(
              icon: Icons.checklist,
              title: context.l10n.text('requirements'),
              subtitle: context.l10n.text('requirements_detail'),
              onTap: () => onOpenSection(2),
            ),
            _WorkspaceShortcut(
              icon: Icons.history,
              title: context.l10n.text('evidence_history'),
              subtitle: context.l10n.text('evidence_history_detail'),
              onTap: () => onOpenSection(8),
            ),
          ],
        ),
      ],
    );
  }
}

/// Isolated one-second task metrics. The rest of the workspace stays idle;
/// timestamps from the canonical runtime determine live recorded work and
/// progress without a network write for each tick.
class _LiveTaskMetrics extends ConsumerWidget {
  const _LiveTaskMetrics({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    final ownsRuntime = runtime?.activeTaskId == task.id;
    if (ownsRuntime && runtime?.state == 'running') {
      ref.watch(taskExecutionClockProvider);
    }
    final liveSegment =
        ownsRuntime &&
            runtime?.state == 'running' &&
            runtime?.segmentStartedAt != null
        ? DateTime.now()
              .toUtc()
              .difference(runtime!.segmentStartedAt!)
              .inMilliseconds
        : 0;
    final pomodoro = task.executionMode == 'pomodoro' && ownsRuntime
        ? PomodoroExecutionSnapshot.fromTask(
            task: task,
            runtime: runtime,
            now: DateTime.now().toUtc(),
          )
        : null;
    final recorded = ownsRuntime
        ? pomodoro?.focusedMs ??
              (runtime?.accumulatedActiveMs ?? 0) + liveSegment
        : task.activeDurationMs;
    final planned = task.estimatedDurationMs;
    final rawProgress = planned <= 0 ? task.progress : recorded / planned;
    final progress = rawProgress.clamp(0.0, 1.0);
    final remaining = (planned - recorded).clamp(0, planned);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  width: width,
                  label: context.l10n.text('progress'),
                  value: '${(progress * 100).round()}%',
                  icon: Icons.donut_large,
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('recorded_work'),
                  value: context.l10n.duration(
                    Duration(milliseconds: recorded),
                  ),
                  icon: Icons.timer_outlined,
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('planned_effort'),
                  value: context.l10n.duration(Duration(milliseconds: planned)),
                  icon: Icons.schedule,
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('remaining'),
                  value: context.l10n.duration(
                    Duration(milliseconds: remaining),
                  ),
                  icon: Icons.hourglass_bottom_rounded,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Chip(
          avatar: const Icon(Icons.flag_outlined, size: 16),
          label: Text(
            '${context.l10n.text('priority')}: '
            '${_localizedPriority(context, task.priority)}',
          ),
        ),
        if (rawProgress > 1) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.format('overtime_duration', {
              'duration': context.l10n.duration(
                Duration(milliseconds: recorded - planned),
              ),
            }),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _TaskExecutionPanel extends ConsumerStatefulWidget {
  const _TaskExecutionPanel({required this.task, required this.onOpenResource});

  final LocalTask task;
  final ValueChanged<String> onOpenResource;

  @override
  ConsumerState<_TaskExecutionPanel> createState() =>
      _TaskExecutionPanelState();
}

class _TaskExecutionPanelState extends ConsumerState<_TaskExecutionPanel> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      padding: EdgeInsets.all(compact ? 12 : 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: _ExecutionLiveHero(
              task: widget.task,
              runtime: runtime,
              busy: _busy,
              onPrimary: (action) => _runPrimary(ref, action),
              onStartBreakEarly: () => _runBusy(
                () => ref.read(taskRepositoryProvider).startBreak(widget.task),
              ),
              onSkipBreak: () => _skipBreak(ref),
              onExtendBreak: () => _extendBreak(ref),
              onFinishTask: () => _runBusy(
                () => completeTaskWithUndo(context, ref, widget.task),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.center,
          child: OutlinedButton.icon(
            onPressed: () => InterruptionEditorDialog.show(
              context,
              task: widget.task,
              sessionId: runtime?.activeTaskId == widget.task.id
                  ? runtime?.sessionId
                  : null,
            ),
            icon: const Icon(Icons.flash_on_outlined),
            label: Text(context.l10n.text('add_interruption')),
          ),
        ),
        const SizedBox(height: 18),
        _ExecutionModeExplanation(mode: widget.task.executionMode),
      ],
    );
  }

  Future<void> _runPrimary(
    WidgetRef ref,
    TaskExecutionPrimaryAction action,
  ) async {
    await _runBusy(() async {
      final repository = ref.read(taskRepositoryProvider);
      switch (action) {
        case TaskExecutionPrimaryAction.start:
          await startTaskWithConfirmation(
            context,
            ref,
            widget.task,
            onOpenInAppResource: widget.onOpenResource,
          );
        case TaskExecutionPrimaryAction.pause:
          await repository.pause(widget.task);
        case TaskExecutionPrimaryAction.resume:
          await repository.resume(widget.task);
        case TaskExecutionPrimaryAction.startBreak:
          await TaskExecutionCommands.startOfferedBreak(
            repository,
            widget.task,
          );
        case TaskExecutionPrimaryAction.startFocus:
          await repository.finishBreak(widget.task);
      }
    });
  }

  Future<void> _skipBreak(WidgetRef ref) async {
    await _runBusy(
      () => TaskExecutionCommands.skipOfferedBreak(
        ref.read(taskRepositoryProvider),
        widget.task,
      ),
    );
  }

  Future<void> _extendBreak(WidgetRef ref) async {
    final repository = ref.read(taskRepositoryProvider);
    var extended = false;
    await _runBusy(() async {
      extended = await TaskExecutionCommands.extendBreak(
        repository: repository,
        task: widget.task,
      );
    });
    if (!extended) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('break_extended_five'))),
    );
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: action,
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The only clock-watching island on the Execute page.
///
/// The surrounding workspace, navigation, resources and explanation remain
/// static while this compact hero updates its elapsed/countdown presentation.
class _ExecutionLiveHero extends ConsumerWidget {
  const _ExecutionLiveHero({
    required this.task,
    required this.runtime,
    required this.busy,
    required this.onPrimary,
    required this.onStartBreakEarly,
    required this.onSkipBreak,
    required this.onExtendBreak,
    required this.onFinishTask,
  });

  final LocalTask task;
  final LocalRuntime? runtime;
  final bool busy;
  final Future<void> Function(TaskExecutionPrimaryAction action) onPrimary;
  final Future<void> Function() onStartBreakEarly;
  final Future<void> Function() onSkipBreak;
  final Future<void> Function() onExtendBreak;
  final Future<void> Function() onFinishTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownsTask = runtime?.activeTaskId == task.id;
    final running = ownsTask && runtime?.state == 'running';
    final paused = ownsTask && runtime?.state == 'paused';
    final breakActive = ownsTask && runtime?.state == 'break';
    if (running || breakActive) {
      ref.watch(taskExecutionClockProvider);
    }

    final now = DateTime.now().toUtc();
    final currentSegment =
        (running || breakActive) && runtime?.segmentStartedAt != null
        ? math.max(0, now.difference(runtime!.segmentStartedAt!).inMilliseconds)
        : 0;
    final activeMs =
        (ownsTask ? runtime?.accumulatedActiveMs ?? 0 : task.activeDurationMs) +
        (running ? currentSegment : 0);
    final plannedMs = math.max(1, task.estimatedDurationMs);
    final rawRemainingMs = task.estimatedDurationMs - activeMs;
    final countdownRemainingMs = taskEffortRemainingMs(
      plannedMs: task.estimatedDurationMs,
      recordedMs: activeMs,
    );
    final overtimeMs = taskEffortOvertimeMs(
      plannedMs: task.estimatedDurationMs,
      recordedMs: activeMs,
    );
    final pomodoro = task.executionMode == 'pomodoro'
        ? PomodoroExecutionSnapshot.fromTask(
            task: task,
            runtime: ownsTask ? runtime : null,
            now: now,
          )
        : null;
    final controls = TaskExecutionControlState.from(
      taskId: task.id,
      executionMode: task.executionMode,
      runtime: runtime,
      pomodoro: pomodoro,
    );
    final isBreak = pomodoro?.isBreak ?? breakActive;
    final waiting =
        pomodoro?.isWaiting == true || (!running && !paused && !breakActive);
    final recordedMs = pomodoro?.focusedMs ?? activeMs;
    final rawTaskProgress = recordedMs / plannedMs;
    final taskProgress = rawTaskProgress.clamp(0.0, 1.0);
    final remainingFraction = pomodoro == null
        ? (countdownRemainingMs / plannedMs).clamp(0.0, 1.0)
        : pomodoro.intervalDurationMs <= 0
        ? 0.0
        : (pomodoro.remainingMs / pomodoro.intervalDurationMs).clamp(0.0, 1.0);
    final ringProgress = pomodoro == null ? taskProgress : remainingFraction;
    final displayTime = pomodoro == null
        ? overtimeMs > 0 && running
              ? formatTaskEffortOvertime(overtimeMs)
              : formatTaskEffortCountdown(countdownRemainingMs)
        : formatPomodoroCountdown(pomodoro.remainingMs);
    final stateLabel = pomodoro == null && overtimeMs > 0 && running
        ? context.l10n.text('overtime_label')
        : _executionStateLabel(
            context,
            task: task,
            running: running,
            paused: paused,
            breakActive: breakActive,
            waiting: pomodoro?.isWaiting == true,
          );
    final semanticLabel = pomodoro == null
        ? context.l10n.executionMode(task.executionMode)
        : pomodoro.isBreak
        ? context.l10n.text('pomodoro_break_session')
        : context.l10n.text('pomodoro_focus_session');
    return ExecutionTimerSurface(
      surfaceKey: ValueKey('execution-hero-${task.executionMode}'),
      mode: task.executionMode,
      title: semanticLabel,
      stateLabel: stateLabel,
      icon: _executionModeIcon(task.executionMode),
      isBreak: isBreak,
      active: running || breakActive,
      paused: paused,
      waiting: waiting,
      remainingFraction: remainingFraction,
      contentBuilder: (context, palette) => LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 760;
          final timer = ExecutionTimerDial(
            displayTime: displayTime,
            progress: ringProgress,
            remainingFraction: remainingFraction,
            isBreak: isBreak,
            active: running || breakActive,
            waiting: waiting,
            paused: paused,
            semanticLabel: semanticLabel,
            stateLabel: stateLabel,
            modeIcon: _executionModeIcon(task.executionMode),
          );
          final details = _ExecutionDetails(
            task: task,
            pomodoro: pomodoro,
            activeMs: activeMs,
            recordedMs: recordedMs,
            remainingMs: rawRemainingMs,
            rawTaskProgress: rawTaskProgress,
            stateLabel: stateLabel,
            controls: controls,
            busy: busy,
            palette: palette,
            onPrimary: onPrimary,
            onStartBreakEarly: onStartBreakEarly,
            onSkipBreak: onSkipBreak,
            onExtendBreak: onExtendBreak,
            onFinishTask: onFinishTask,
          );
          if (!horizontal) {
            return Column(
              children: [
                Center(child: timer),
                const SizedBox(height: 22),
                details,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 11, child: Center(child: timer)),
              const SizedBox(width: 34),
              Expanded(flex: 10, child: details),
            ],
          );
        },
      ),
    );
  }
}

/// Shared presentation shell for both task-bound and standalone Pomodoro
/// timers. It owns the visual language (palette, field, header and responsive
/// padding), while each timer supplies only its canonical state and actions.
class ExecutionTimerSurface extends StatelessWidget {
  const ExecutionTimerSurface({
    required this.surfaceKey,
    required this.mode,
    required this.title,
    required this.stateLabel,
    required this.icon,
    required this.isBreak,
    required this.active,
    required this.paused,
    required this.waiting,
    required this.remainingFraction,
    required this.contentBuilder,
    super.key,
  });

  final String mode;
  final Key surfaceKey;
  final String title;
  final String stateLabel;
  final IconData icon;
  final bool isBreak;
  final bool active;
  final bool paused;
  final bool waiting;
  final double remainingFraction;
  final Widget Function(BuildContext, ExecutionTimerPalette) contentBuilder;

  @override
  Widget build(BuildContext context) {
    final palette = executionTimerPalette(
      context,
      isBreak: isBreak,
      active: active,
      paused: paused,
      waiting: waiting,
      remainingFraction: remainingFraction,
    );
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      key: surfaceKey,
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.border, width: 1.25),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              palette.ambient.withValues(alpha: .10),
              colorScheme.surfaceContainerLow,
            ),
            Color.alphaBlend(
              palette.accent.withValues(alpha: .055),
              colorScheme.surfaceContainer,
            ),
            colorScheme.surfaceContainerLow,
          ],
          stops: const [0, .48, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.glow.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? .20
                  : .10,
            ),
            blurRadius: 30,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HolographicFieldPainter(
                  accent: palette.accent,
                  ambient: palette.ambient,
                  line: colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 18 : 30,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ExecutionHeroHeader(
                  mode: mode,
                  title: title,
                  stateLabel: stateLabel,
                  icon: icon,
                  palette: palette,
                ),
                const SizedBox(height: 22),
                contentBuilder(context, palette),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExecutionHeroHeader extends StatelessWidget {
  const _ExecutionHeroHeader({
    required this.mode,
    required this.title,
    required this.stateLabel,
    required this.icon,
    required this.palette,
  });

  final String mode;
  final String title;
  final String stateLabel;
  final IconData icon;
  final ExecutionTimerPalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent.withValues(alpha: .13),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: .38),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.glow.withValues(alpha: .25),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: palette.accent, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      context.l10n.executionMode(mode),
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.accent.withValues(alpha: .34)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              stateLabel,
              style: textTheme.labelLarge?.copyWith(
                color: palette.secondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExecutionDetails extends StatelessWidget {
  const _ExecutionDetails({
    required this.task,
    required this.pomodoro,
    required this.activeMs,
    required this.recordedMs,
    required this.remainingMs,
    required this.rawTaskProgress,
    required this.stateLabel,
    required this.controls,
    required this.busy,
    required this.palette,
    required this.onPrimary,
    required this.onStartBreakEarly,
    required this.onSkipBreak,
    required this.onExtendBreak,
    required this.onFinishTask,
  });

  final LocalTask task;
  final PomodoroExecutionSnapshot? pomodoro;
  final int activeMs;
  final int recordedMs;
  final int remainingMs;
  final double rawTaskProgress;
  final String stateLabel;
  final TaskExecutionControlState controls;
  final bool busy;
  final ExecutionTimerPalette palette;
  final Future<void> Function(TaskExecutionPrimaryAction action) onPrimary;
  final Future<void> Function() onStartBreakEarly;
  final Future<void> Function() onSkipBreak;
  final Future<void> Function() onExtendBreak;
  final Future<void> Function() onFinishTask;

  @override
  Widget build(BuildContext context) {
    final detail = pomodoro == null
        ? remainingMs >= 0
              ? context.l10n.format('planned_remaining', {
                  'duration': context.l10n.duration(
                    Duration(milliseconds: remainingMs),
                  ),
                })
              : context.l10n.format('overtime_duration', {
                  'duration': context.l10n.duration(
                    Duration(milliseconds: -remainingMs),
                  ),
                })
        : context.l10n.format('pomodoro_session_progress', {
            'current': pomodoro!.currentSession,
            'total': pomodoro!.approximateSessions,
          });
    final progressLabel = '${math.max(0, rawTaskProgress * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          detail,
          key: const ValueKey('execution-primary-detail'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: remainingMs < 0 && pomodoro == null
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (pomodoro != null) ...[
          const SizedBox(height: 5),
          Text(
            context.l10n.format('pomodoro_task_progress', {
              'focused': context.l10n.duration(
                Duration(milliseconds: pomodoro!.focusedMs),
              ),
              'planned': context.l10n.duration(
                Duration(milliseconds: task.estimatedDurationMs),
              ),
            }),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth < 390
                ? constraints.maxWidth
                : (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _ExecutionMetricTile(
                    icon: Icons.timer_outlined,
                    label: context.l10n.text('recorded_work'),
                    value: context.l10n.duration(
                      Duration(milliseconds: recordedMs),
                    ),
                    palette: palette,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ExecutionMetricTile(
                    icon: Icons.flag_outlined,
                    label: context.l10n.text('planned_effort'),
                    value: context.l10n.duration(
                      Duration(milliseconds: task.estimatedDurationMs),
                    ),
                    palette: palette,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ExecutionMetricTile(
                    icon: Icons.donut_large_rounded,
                    label: context.l10n.text('progress'),
                    value: progressLabel,
                    palette: palette,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ExecutionMetricTile(
                    icon: Icons.graphic_eq_rounded,
                    label: context.l10n.text('status'),
                    value: stateLabel,
                    palette: palette,
                  ),
                ),
              ],
            );
          },
        ),
        if (pomodoro?.isWaiting == true) ...[
          const SizedBox(height: 14),
          _PomodoroWaitingIndicator(
            message: pomodoro!.isBreak
                ? context.l10n.text('pomodoro_break_complete_waiting')
                : context.l10n.format('pomodoro_focus_complete_waiting', {
                    'duration': context.l10n.duration(
                      Duration(milliseconds: pomodoro!.nextBreakDurationMs),
                    ),
                  }),
            palette: palette,
          ),
        ],
        const SizedBox(height: 20),
        _ExecutionActionCluster(
          controls: controls,
          busy: busy,
          palette: palette,
          onPrimary: onPrimary,
          onStartBreakEarly: onStartBreakEarly,
          onSkipBreak: onSkipBreak,
          onExtendBreak: onExtendBreak,
          onFinishTask: onFinishTask,
        ),
      ],
    );
  }
}

class _ExecutionMetricTile extends StatelessWidget {
  const _ExecutionMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final String value;
  final ExecutionTimerPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border.withValues(alpha: .72)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(icon, color: palette.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionActionCluster extends StatelessWidget {
  const _ExecutionActionCluster({
    required this.controls,
    required this.busy,
    required this.palette,
    required this.onPrimary,
    required this.onStartBreakEarly,
    required this.onSkipBreak,
    required this.onExtendBreak,
    required this.onFinishTask,
  });

  final TaskExecutionControlState controls;
  final bool busy;
  final ExecutionTimerPalette palette;
  final Future<void> Function(TaskExecutionPrimaryAction action) onPrimary;
  final Future<void> Function() onStartBreakEarly;
  final Future<void> Function() onSkipBreak;
  final Future<void> Function() onExtendBreak;
  final Future<void> Function() onFinishTask;

  @override
  Widget build(BuildContext context) {
    final primaryIcon = switch (controls.primary) {
      TaskExecutionPrimaryAction.pause => Icons.pause_rounded,
      TaskExecutionPrimaryAction.startBreak => Icons.coffee_outlined,
      TaskExecutionPrimaryAction.startFocus => Icons.center_focus_strong,
      _ => Icons.play_arrow_rounded,
    };
    final primaryLabel = context.l10n.text(switch (controls.primary) {
      TaskExecutionPrimaryAction.start => 'start',
      TaskExecutionPrimaryAction.pause => 'pause',
      TaskExecutionPrimaryAction.resume => 'resume',
      TaskExecutionPrimaryAction.startBreak => 'notification_start_break',
      TaskExecutionPrimaryAction.startFocus => 'notification_start_focus',
    });
    final primaryForeground =
        ThemeData.estimateBrightnessForColor(palette.accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF07130D);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          key: const ValueKey('execution-primary-action'),
          style: FilledButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: primaryForeground,
            shadowColor: palette.glow,
            elevation: 2,
          ),
          onPressed: busy ? null : () => onPrimary(controls.primary),
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(primaryIcon),
          label: Text(primaryLabel),
        ),
        if (controls.canStartBreakEarly)
          OutlinedButton.icon(
            onPressed: busy ? null : onStartBreakEarly,
            icon: const Icon(Icons.coffee_outlined),
            label: Text(context.l10n.text('notification_start_break')),
          ),
        if (controls.canSkipBreak)
          OutlinedButton.icon(
            onPressed: busy ? null : onSkipBreak,
            icon: const Icon(Icons.skip_next_rounded),
            label: Text(context.l10n.text('pomodoro_skip_break')),
          ),
        if (controls.canExtendBreak)
          OutlinedButton.icon(
            onPressed: busy ? null : onExtendBreak,
            icon: const Icon(Icons.more_time),
            label: Text(context.l10n.text('notification_extend_break')),
          ),
        if (controls.ownsTask)
          OutlinedButton.icon(
            onPressed: busy ? null : onFinishTask,
            icon: const Icon(Icons.check_rounded),
            label: Text(context.l10n.text('finish_task')),
          ),
      ],
    );
  }
}

class ExecutionTimerDial extends StatefulWidget {
  const ExecutionTimerDial({
    required this.displayTime,
    required this.progress,
    required this.remainingFraction,
    required this.isBreak,
    required this.active,
    required this.waiting,
    required this.paused,
    required this.semanticLabel,
    required this.stateLabel,
    required this.modeIcon,
    super.key,
  });

  final String displayTime;
  final double progress;
  final double remainingFraction;
  final bool isBreak;
  final bool active;
  final bool waiting;
  final bool paused;
  final String semanticLabel;
  final String stateLabel;
  final IconData modeIcon;

  @override
  State<ExecutionTimerDial> createState() => _ExecutionTimerDialState();
}

class _ExecutionTimerDialState extends State<ExecutionTimerDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final progress = widget.progress.clamp(0.0, 1.0);
    final visualState = pomodoroTimerVisualState(
      active: widget.active,
      paused: widget.paused,
      waiting: widget.waiting,
    );
    // A stopped, paused, or waiting interval must never look as if it is
    // still recording time.  Stopping the controller also avoids spending
    // frames on a decorative animation while the timer is intentionally
    // frozen.
    final shouldAnimate = shouldAnimatePomodoroTimer(
      active: widget.active,
      paused: widget.paused,
      waiting: widget.waiting,
      reducedMotion: reducedMotion,
    );
    if (shouldAnimate && !_orbit.isAnimating) {
      _orbit.repeat();
    } else if (!shouldAnimate && _orbit.isAnimating) {
      _orbit.stop(canceled: false);
    }
    final palette = executionTimerPalette(
      context,
      isBreak: widget.isBreak,
      active: widget.active,
      paused: widget.paused,
      waiting: widget.waiting,
      remainingFraction: widget.remainingFraction,
    );
    return Semantics(
      label:
          '${widget.semanticLabel}: ${widget.displayTime}. '
          '${widget.stateLabel}',
      child: RepaintBoundary(
        key: const ValueKey('holographic-execution-timer'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 430.0;
            final diameter = math.min(430.0, available);
            return AnimatedBuilder(
              animation: _orbit,
              builder: (context, _) => SizedBox.square(
                dimension: diameter,
                child: CustomPaint(
                  painter: _HolographicTimerPainter(
                    progress: progress,
                    rotation: shouldAnimate ? _orbit.value * math.pi * 2 : 0,
                    pulse: shouldAnimate ? _orbit.value : 0,
                    animated: shouldAnimate,
                    accent: palette.accent,
                    secondary: palette.secondary,
                    ambient: palette.ambient,
                    glow: palette.glow,
                    muted: Theme.of(context).colorScheme.outlineVariant,
                    surface: Theme.of(context).colorScheme.surface,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(diameter * .20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.semanticLabel.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: palette.secondary,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                  ),
                            ),
                          ),
                          SizedBox(height: diameter * .025),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.displayTime,
                              key: const ValueKey('execution-timer-value'),
                              style: Theme.of(context).textTheme.displayLarge
                                  ?.copyWith(
                                    color: palette.accent,
                                    fontSize: diameter * .19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.5,
                                    shadows: [
                                      Shadow(
                                        color: palette.glow,
                                        blurRadius: 16,
                                      ),
                                    ],
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                          SizedBox(height: diameter * .025),
                          if (visualState != PomodoroTimerVisualState.running)
                            SizedBox.square(
                              dimension: diameter * .13,
                              child: CustomPaint(
                                painter: _HolographicSandglassPainter(
                                  fraction: widget.remainingFraction,
                                  accent: palette.accent,
                                  secondary: palette.secondary,
                                  glow: palette.glow,
                                ),
                              ),
                            )
                          else
                            Icon(
                              widget.isBreak
                                  ? Icons.spa_outlined
                                  : widget.modeIcon,
                              size: diameter * .09,
                              color: palette.secondary,
                            ),
                          SizedBox(height: diameter * .018),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.stateLabel,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: palette.secondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ExecutionTimerPalette {
  const ExecutionTimerPalette({
    required this.accent,
    required this.secondary,
    required this.ambient,
    required this.glow,
    required this.border,
  });

  final Color accent;
  final Color secondary;
  final Color ambient;
  final Color glow;
  final Color border;
}

ExecutionTimerPalette executionTimerPalette(
  BuildContext context, {
  required bool isBreak,
  required bool active,
  required bool paused,
  required bool waiting,
  required double remainingFraction,
}) {
  final scheme = Theme.of(context).colorScheme;
  final isLight = Theme.of(context).brightness == Brightness.light;
  final ambient = scheme.primary;
  Color tuneForSurface(Color color) =>
      isLight ? Color.lerp(color, Colors.black, .11)! : color;
  ExecutionTimerPalette resolved(Color rawAccent, Color rawSecondary) {
    final accent = tuneForSurface(rawAccent);
    final secondary = tuneForSurface(Color.lerp(rawSecondary, ambient, .10)!);
    return ExecutionTimerPalette(
      accent: accent,
      secondary: secondary,
      ambient: ambient,
      glow: Color.lerp(accent, ambient, .16)!,
      border: Color.alphaBlend(
        accent.withValues(alpha: isLight ? .27 : .35),
        scheme.outlineVariant.withValues(alpha: .74),
      ),
    );
  }

  // Pause and waiting states intentionally use a cool, steady palette.  The
  // focus urgency colours are reserved for a focus interval that is truly
  // running, so a frozen timer cannot be mistaken for live work.
  if (paused) {
    const cool = Color(0xFF35B9E8);
    const violet = Color(0xFF8B7BFF);
    return resolved(cool, violet);
  }
  if (waiting || !active) {
    const calm = Color(0xFF6FA9D8);
    const violet = Color(0xFF8C82DB);
    return resolved(calm, violet);
  }
  if (isBreak) {
    // Breaks remain calm and never inherit focus urgency red/orange.
    const teal = Color(0xFF1DAE9A);
    const cyan = Color(0xFF28BCE8);
    const softBlue = Color(0xFF638EEB);
    final progress = 1 - remainingFraction;
    final accent = progress < .5
        ? Color.lerp(teal, cyan, progress / .5)!
        : Color.lerp(cyan, softBlue, (progress - .5) / .5)!;
    final secondary = Color.lerp(cyan, softBlue, progress)!;
    return resolved(accent, secondary);
  }
  // The focus colour is based on the *remaining* interval and interpolated
  // continuously: green -> yellow-green -> amber -> orange -> red.
  const green = Color(0xFF32C878);
  const yellowGreen = Color(0xFFB5D43A);
  const amber = Color(0xFFFFC238);
  const orange = Color(0xFFFF8A34);
  const red = Color(0xFFE94A4A);
  final accent = remainingFraction >= .65
      ? Color.lerp(green, yellowGreen, (1 - remainingFraction) / .35)!
      : remainingFraction >= .35
      ? Color.lerp(yellowGreen, amber, (.65 - remainingFraction) / .30)!
      : remainingFraction >= .15
      ? Color.lerp(amber, orange, (.35 - remainingFraction) / .20)!
      : Color.lerp(orange, red, (.15 - remainingFraction) / .15)!;
  return resolved(accent, Color.lerp(accent, scheme.onSurface, .18)!);
}

/// A deliberately static field behind the live clock. It gives every execution
/// mode the same visual language without adding another ticker.
class _HolographicFieldPainter extends CustomPainter {
  const _HolographicFieldPainter({
    required this.accent,
    required this.ambient,
    required this.line,
  });

  final Color accent;
  final Color ambient;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = line.withValues(alpha: .11);
    final step = math.max(34.0, size.shortestSide / 10);
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        guide,
      );
    }

    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: .09);
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * .04, size.height * .12),
        radius: size.shortestSide * .72,
      ),
      -.5,
      1.72,
      false,
      haloPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * .97, size.height * .88),
        radius: size.shortestSide * .56,
      ),
      math.pi,
      1.48,
      false,
      haloPaint..color = ambient.withValues(alpha: .09),
    );

    final node = Paint()..color = accent.withValues(alpha: .24);
    for (final point in <Offset>[
      Offset(size.width * .08, size.height * .17),
      Offset(size.width * .93, size.height * .21),
      Offset(size.width * .88, size.height * .82),
    ]) {
      canvas.drawCircle(point, 2.2, node);
      canvas.drawCircle(
        point,
        7,
        Paint()
          ..color = accent.withValues(alpha: .08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HolographicFieldPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.ambient != ambient ||
      oldDelegate.line != line;
}

class _HolographicTimerPainter extends CustomPainter {
  const _HolographicTimerPainter({
    required this.progress,
    required this.rotation,
    required this.pulse,
    required this.animated,
    required this.accent,
    required this.secondary,
    required this.ambient,
    required this.glow,
    required this.muted,
    required this.surface,
  });

  final double progress;
  final double rotation;
  final double pulse;
  final bool animated;
  final Color accent;
  final Color secondary;
  final Color ambient;
  final Color glow;
  final Color muted;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 14;
    final breathing = animated
        ? .34 + .24 * ((math.sin(pulse * math.pi * 2) + 1) / 2)
        : .38;
    final halo = Paint()
      ..shader = RadialGradient(
        colors: [
          glow.withValues(alpha: .18),
          accent.withValues(alpha: .055),
          ambient.withValues(alpha: .025),
          surface.withValues(alpha: 0),
        ],
        stops: const [0, .48, .74, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, halo);

    final outerGuide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = muted.withValues(alpha: .30);
    canvas.drawCircle(center, radius, outerGuide);
    canvas.drawCircle(
      center,
      radius - 7,
      outerGuide
        ..strokeWidth = 1.2
        ..color = ambient.withValues(alpha: .14),
    );
    canvas.drawCircle(center, radius - 26, outerGuide);
    canvas.drawCircle(
      center,
      radius - 54,
      outerGuide..color = muted.withValues(alpha: .16),
    );

    const ticks = 72;
    for (var index = 0; index < ticks; index++) {
      final angle = -math.pi / 2 + (math.pi * 2 * index / ticks);
      final major = index % 6 == 0;
      final lit = index / ticks <= progress;
      final outer = radius - 4;
      final inner = outer - (major ? 8 : 4);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * inner,
        center + direction * outer,
        Paint()
          ..strokeWidth = major ? 1.8 : 1
          ..strokeCap = StrokeCap.round
          ..color = lit
              ? Color.lerp(
                  accent,
                  secondary,
                  index / ticks,
                )!.withValues(alpha: major ? .88 : .54)
              : muted.withValues(alpha: .14),
      );
    }

    final progressRect = Rect.fromCircle(center: center, radius: radius - 13);
    if (progress > .001) {
      canvas.drawArc(
        progressRect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..color = glow.withValues(alpha: .52)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [secondary, accent, ambient, secondary],
        stops: const [0, .48, .82, 1],
      ).createShader(progressRect);
    if (progress > .001) {
      canvas.drawArc(
        progressRect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        active,
      );
    }
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..color = glow.withValues(alpha: breathing);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 35),
      rotation,
      math.pi * .62,
      false,
      orbitPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 48),
      -rotation + math.pi * .88,
      math.pi * .42,
      false,
      orbitPaint..color = secondary.withValues(alpha: breathing * .86),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 65),
      rotation + math.pi * .37,
      math.pi * .28,
      false,
      orbitPaint..color = glow.withValues(alpha: breathing * .7),
    );

    final lensRadius = math.max(4.0, radius - 77);
    final lensRect = Rect.fromCircle(center: center, radius: lensRadius);
    canvas.drawCircle(
      center,
      lensRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: .045),
            ambient.withValues(alpha: .025),
            surface.withValues(alpha: 0),
          ],
          stops: const [0, .62, 1],
        ).createShader(lensRect),
    );
    canvas.drawCircle(
      center,
      lensRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = secondary.withValues(alpha: .15),
    );

    for (final particle in <(double, double, Color)>[
      (rotation, radius - 35, accent),
      (-rotation + math.pi, radius - 48, secondary),
      (rotation + math.pi * .65, radius - 65, accent),
    ]) {
      final point =
          center +
          Offset(math.cos(particle.$1), math.sin(particle.$1)) * particle.$2;
      canvas.drawCircle(
        point,
        2.2,
        Paint()
          ..color = particle.$3.withValues(alpha: .86)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(point, 1.25, Paint()..color = particle.$3);
    }

    final marker = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = secondary.withValues(alpha: .42);
    for (var quadrant = 0; quadrant < 4; quadrant++) {
      final angle = quadrant * math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - 75),
        center + direction * (radius - 69),
        marker,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HolographicTimerPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.rotation != rotation ||
      oldDelegate.pulse != pulse ||
      oldDelegate.animated != animated ||
      oldDelegate.accent != accent ||
      oldDelegate.secondary != secondary ||
      oldDelegate.ambient != ambient ||
      oldDelegate.glow != glow ||
      oldDelegate.muted != muted ||
      oldDelegate.surface != surface;
}

class _HolographicSandglassPainter extends CustomPainter {
  const _HolographicSandglassPainter({
    required this.fraction,
    required this.accent,
    required this.secondary,
    required this.glow,
  });

  final double fraction;
  final Color accent;
  final Color secondary;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(
      size.width * .18,
      size.height * .08,
      size.width * .64,
      size.height * .84,
    );
    final framePath = Path()
      ..moveTo(frame.left, frame.top)
      ..lineTo(frame.right, frame.top)
      ..moveTo(frame.left, frame.bottom)
      ..lineTo(frame.right, frame.bottom)
      ..moveTo(frame.left + size.width * .06, frame.top)
      ..cubicTo(
        frame.left + size.width * .08,
        frame.center.dy - size.height * .10,
        frame.center.dx,
        frame.center.dy - size.height * .04,
        frame.center.dx,
        frame.center.dy,
      )
      ..cubicTo(
        frame.center.dx,
        frame.center.dy + size.height * .04,
        frame.left + size.width * .08,
        frame.bottom - size.height * .10,
        frame.left + size.width * .06,
        frame.bottom,
      )
      ..moveTo(frame.right - size.width * .06, frame.top)
      ..cubicTo(
        frame.right - size.width * .08,
        frame.center.dy - size.height * .10,
        frame.center.dx,
        frame.center.dy - size.height * .04,
        frame.center.dx,
        frame.center.dy,
      )
      ..cubicTo(
        frame.center.dx,
        frame.center.dy + size.height * .04,
        frame.right - size.width * .08,
        frame.bottom - size.height * .10,
        frame.right - size.width * .06,
        frame.bottom,
      );
    canvas.drawPath(
      framePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(3, size.width * .11)
        ..strokeCap = StrokeCap.round
        ..color = glow.withValues(alpha: .52)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      framePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, size.width * .055)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(
          colors: [secondary, accent, secondary],
        ).createShader(frame),
    );

    final sand = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [secondary.withValues(alpha: .72), accent],
      ).createShader(frame);
    final topAmount = fraction.clamp(0.08, 0.92);
    final topSand = Path()
      ..moveTo(frame.left + size.width * .12, frame.top + size.height * .13)
      ..lineTo(frame.right - size.width * .12, frame.top + size.height * .13)
      ..lineTo(frame.center.dx, frame.center.dy - size.height * .04 * topAmount)
      ..close();
    final bottomSand = Path()
      ..moveTo(frame.center.dx, frame.center.dy + size.height * .04)
      ..lineTo(frame.right - size.width * .11, frame.bottom - size.height * .10)
      ..lineTo(frame.left + size.width * .11, frame.bottom - size.height * .10)
      ..close();
    canvas.drawPath(topSand, sand);
    canvas.drawPath(bottomSand, sand);
    canvas.drawLine(
      Offset(frame.center.dx, frame.center.dy - size.height * .02),
      Offset(frame.center.dx, frame.center.dy + size.height * .18),
      Paint()
        ..strokeWidth = math.max(1, size.width * .035)
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: .82),
    );
  }

  @override
  bool shouldRepaint(covariant _HolographicSandglassPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.accent != accent ||
      oldDelegate.secondary != secondary ||
      oldDelegate.glow != glow;
}

class _PomodoroWaitingIndicator extends StatelessWidget {
  const _PomodoroWaitingIndicator({
    required this.message,
    required this.palette,
  });

  final String message;
  final ExecutionTimerPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.accent.withValues(alpha: .32)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.hourglass_bottom_rounded, color: palette.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

String _executionStateLabel(
  BuildContext context, {
  required LocalTask task,
  required bool running,
  required bool paused,
  required bool breakActive,
  required bool waiting,
}) {
  if (task.status == 'completed') {
    return context.l10n.taskStatus('completed');
  }
  if (waiting) return context.l10n.text('pomodoro_waiting');
  if (breakActive) return context.l10n.text('break_in_progress');
  if (paused) return context.l10n.taskStatus('paused');
  if (running) return context.l10n.taskStatus('running');
  return context.l10n.taskStatus(task.status);
}

IconData _executionModeIcon(String mode) {
  return switch (mode) {
    'pomodoro' => Icons.center_focus_strong,
    'continuous' => Icons.all_inclusive_rounded,
    'checklist' => Icons.fact_check_outlined,
    'reading' => Icons.auto_stories_outlined,
    'habit' => Icons.repeat_rounded,
    'event' => Icons.event_available_outlined,
    'hybrid' => Icons.hub_outlined,
    _ => Icons.timer_outlined,
  };
}

class _ChecklistPanel extends ConsumerWidget {
  const _ChecklistPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: entities.watch(entityType: 'checklist_items', parentId: task.id),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        final required = items.where(
          (item) => entities.decode(item)['is_required'] != false,
        );
        final completed = required.where(
          (item) => entities.decode(item)['is_completed'] == true,
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionHeader(
              title: context.l10n.text('checklist_requirements'),
              subtitle: context.l10n.format('required_items_complete', {
                'completed': completed.length,
                'total': required.length,
              }),
              actionLabel: context.l10n.text('add_item'),
              icon: Icons.add,
              onAction: () => _addChecklistItem(context, ref, task, items),
            ),
            if (items.isEmpty)
              _EmptyPanel(
                icon: Icons.checklist,
                title: context.l10n.text('no_requirements'),
                message: context.l10n.text('no_requirements_detail'),
              )
            else
              ...items.map((item) {
                final data = entities.decode(item);
                final checked = data['is_completed'] == true;
                return Card(
                  child: CheckboxListTile(
                    value: checked,
                    title: Text(
                      item.title,
                      style: TextStyle(
                        decoration: checked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(
                      data['is_required'] == false
                          ? context.l10n.text('optional')
                          : context.l10n.text('required'),
                    ),
                    secondary: IconButton(
                      tooltip: context.l10n.text('delete_item'),
                      onPressed: () async {
                        await entities.softDelete(item);
                        unawaited(ref.read(syncServiceProvider).drainOutbox());
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onChanged: (value) async {
                      await _setChecklistCompletionWithUndo(
                        context,
                        ref,
                        entities,
                        item,
                        completed: value == true,
                      );
                    },
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

Future<void> _setChecklistCompletionWithUndo(
  BuildContext context,
  WidgetRef ref,
  EntityRecordRepository entities,
  LocalEntityRecord item, {
  required bool completed,
}) async {
  final previousData = <String, Object?>{...entities.decode(item)};
  final completedAt = completed
      ? DateTime.now().toUtc().toIso8601String()
      : null;
  final nextData = <String, Object?>{
    ...previousData,
    'is_completed': completed,
    'completed_at': completedAt,
  };
  await entities.update(
    item,
    data: nextData,
    syncPayload: {'is_completed': completed, 'completed_at': completedAt},
  );
  unawaited(ref.read(syncServiceProvider).drainOutbox());
  if (!completed || !context.mounted) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(context.l10n.text('checklist_item_completed')),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: context.l10n.text('undo'),
          onPressed: () => unawaited(
            _undoChecklistCompletion(
              context,
              ref,
              entities,
              item.id,
              completedAt!,
              previousData,
            ),
          ),
        ),
      ),
    );
}

Future<void> _undoChecklistCompletion(
  BuildContext context,
  WidgetRef ref,
  EntityRecordRepository entities,
  String itemId,
  String completedAt,
  Map<String, Object?> previousData,
) async {
  final latest = await entities.get(itemId);
  if (latest == null) return;
  final latestData = entities.decode(latest);
  // A later edit or a completion from another device wins. The short Undo
  // must never overwrite a newer checklist decision.
  if (latestData['is_completed'] != true ||
      latestData['completed_at'] != completedAt) {
    return;
  }
  await entities.update(
    latest,
    data: previousData,
    syncPayload: {
      'is_completed': previousData['is_completed'] == true,
      'completed_at': previousData['completed_at'],
    },
  );
  unawaited(ref.read(syncServiceProvider).drainOutbox());
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(context.l10n.text('completion_undone'))),
  );
}

class _ResourcesPanel extends ConsumerWidget {
  const _ResourcesPanel({required this.task, required this.onOpenUrl});

  final LocalTask task;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: entities.watch(entityType: 'task_resources', parentId: task.id),
      builder: (context, snapshot) {
        final resources = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionHeader(
              title: context.l10n.text('resources_attachments'),
              subtitle: context.l10n.text('resources_attachments_detail'),
              actionLabel: context.l10n.text('add'),
              icon: Icons.add,
              onAction: () => _showResourceActions(context, ref, task),
            ),
            if (resources.isEmpty)
              _EmptyPanel(
                icon: Icons.folder_copy_outlined,
                title: context.l10n.text('task_no_resources'),
                message: context.l10n.text('task_no_resources_detail'),
              )
            else
              ...resources.map(
                (resource) => _ResourceTile(
                  task: task,
                  resource: resource,
                  onOpenUrl: onOpenUrl,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ResourceTile extends ConsumerWidget {
  const _ResourceTile({
    required this.task,
    required this.resource,
    required this.onOpenUrl,
  });

  final LocalTask task;
  final LocalEntityRecord resource;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    final data = entities.decode(resource);
    final type = data['resource_type'] as String? ?? 'file';
    final isUrl = isTaskWebsiteResourceType(type);
    final websiteUrl = isUrl ? taskWebsiteResourceUrl(data) : null;
    final path = data['local_path'] as String?;
    final available = path == null || File(path).existsSync();
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_resourceIcon(type))),
        title: Text(resource.title),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                context.l10n.text(
                  isUrl ? 'resource_type_url' : 'resource_type_$type',
                ),
                if (data['author'] case final String author
                    when author.isNotEmpty)
                  author,
                if (data['pending_upload'] == true)
                  context.l10n.text('waiting_to_upload'),
                if (!available) context.l10n.text('unavailable_device'),
              ].join(' · '),
            ),
            if (websiteUrl != null) ...[
              const SizedBox(height: 2),
              Text(
                websiteUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ],
        ),
        onTap: () =>
            _openResource(context, ref, task, resource, data, onOpenUrl),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'open_in_app') {
              await ref
                  .read(taskResourceServiceProvider)
                  .launchWebsiteRecord(
                    task: task,
                    resource: resource,
                    mode: TaskResourceLaunchMode.inApp,
                    openInApp: onOpenUrl,
                  );
            } else if (action == 'open_installed_app') {
              await ref
                  .read(taskResourceServiceProvider)
                  .launchWebsiteRecord(
                    task: task,
                    resource: resource,
                    mode: TaskResourceLaunchMode.externalApp,
                    openInApp: onOpenUrl,
                  );
            } else if (action == 'open_browser') {
              await ref
                  .read(taskResourceServiceProvider)
                  .launchWebsiteRecord(
                    task: task,
                    resource: resource,
                    mode: TaskResourceLaunchMode.externalBrowser,
                    openInApp: onOpenUrl,
                  );
            } else if (action == 'open_external') {
              await ref.read(taskResourceServiceProvider).open(resource);
            } else if (action == 'delete') {
              await entities.softDelete(resource);
            }
          },
          itemBuilder: (_) => [
            if (isUrl) ...[
              PopupMenuItem(
                value: 'open_in_app',
                child: Text(context.l10n.text('resource_open_in_app')),
              ),
              PopupMenuItem(
                value: 'open_installed_app',
                child: Text(context.l10n.text('resource_open_installed_app')),
              ),
              PopupMenuItem(
                value: 'open_browser',
                child: Text(
                  context.l10n.text('resource_open_external_browser'),
                ),
              ),
            ],
            if (!isUrl && type != 'book')
              PopupMenuItem(
                value: 'open_external',
                child: Text(context.l10n.text('open_externally')),
              ),
            PopupMenuItem(
              value: 'delete',
              child: Text(context.l10n.text('remove')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionsPanel extends ConsumerWidget {
  const _ConnectionsPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          title: context.l10n.text('task_connections'),
          subtitle: context.l10n.text('task_connections_description'),
        ),
        _RoadmapConnectionCard(task: task),
        const SizedBox(height: 12),
        _ConnectionList(
          title: context.l10n.text('dependency_tasks'),
          subtitle: context.l10n.text('dependency_tasks_detail'),
          icon: Icons.account_tree_outlined,
          stream: entities.watch(
            entityType: 'task_dependencies',
            parentId: task.id,
          ),
          entities: entities,
          addLabel: context.l10n.text('connect_task'),
          onAdd: () => _addDependency(context, ref, task),
        ),
        const SizedBox(height: 12),
        _ConnectionList(
          title: context.l10n.text('applications'),
          subtitle: context.l10n.text('application_connections_detail'),
          icon: Icons.apps,
          stream: entities.watch(
            entityType: 'task_application_links',
            parentId: task.id,
          ),
          entities: entities,
          addLabel: context.l10n.text('add_application'),
          onAdd: () => _addApplication(context, ref, task),
          applicationEntries: true,
        ),
        const SizedBox(height: 12),
        _ConnectionList(
          title: context.l10n.text('websites'),
          subtitle: context.l10n.text('website_connections_detail'),
          icon: Icons.public,
          stream: entities.watch(
            entityType: 'website_rules',
            parentId: task.id,
          ),
          entities: entities,
          addLabel: context.l10n.text('add_website'),
          onAdd: () => _addWebsite(context, ref, task),
        ),
      ],
    );
  }
}

class _NotesPanel extends ConsumerWidget {
  const _NotesPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: entities.watch(entityType: 'task_notes', parentId: task.id),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionHeader(
              title: context.l10n.text('task_notes'),
              subtitle: context.l10n.text('task_notes_detail'),
              actionLabel: context.l10n.text('add_note'),
              icon: Icons.add,
              onAction: () => _addNote(context, ref, task),
            ),
            if (notes.isEmpty)
              _EmptyPanel(
                icon: Icons.notes_outlined,
                title: context.l10n.text('no_notes'),
                message: context.l10n.text('no_notes_detail'),
              )
            else
              ...notes.reversed.map((note) {
                final data = entities.decode(note);
                return Card(
                  child: ListTile(
                    title: Text(data['body'] as String? ?? note.title),
                    subtitle: Text(
                      '${context.l10n.format('version_number', {'version': (data['note_version'] as num?)?.toInt() ?? 1})} · ${DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_jm().format(note.updatedAt.toLocal())}',
                    ),
                    trailing: IconButton(
                      tooltip: context.l10n.text('delete_note'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => entities.softDelete(note),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _HistoryPanel extends ConsumerWidget {
  const _HistoryPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    final database = ref.watch(databaseProvider);
    final query = database.select(database.localEntityRecords)
      ..where((row) {
        var expression =
            row.userId.equals(entities.userId) & row.deletedAt.isNull();
        expression =
            expression &
            row.entityType.isIn(const [
              'execution_sessions',
              'session_events',
              'pomodoro_cycles',
              'interruptions',
              'task_notes',
              'activity_contributions',
              'task_completion_evidence',
              'task_application_links',
              'website_rules',
              'task_resources',
              'resource_activity',
              'browser_history_events',
            ]);
        return expression;
      });
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: query.watch(),
      builder: (context, snapshot) {
        final allRecords = snapshot.data ?? const <LocalEntityRecord>[];
        final sessionIds = <String>{
          for (final record in allRecords)
            if (record.entityType == 'execution_sessions' &&
                _historyRecordReferencesTask(record, task.id, const {}))
              record.id,
        };
        final records = [
          for (final record in allRecords)
            if (_historyRecordReferencesTask(record, task.id, sessionIds))
              record,
        ];
        records.sort((a, b) => _historyTime(b).compareTo(_historyTime(a)));
        final hasRecordedCompletion = records.any(
          (record) =>
              record.entityType == 'task_completion_evidence' &&
              _lifecycleEventType(record) == 'completed',
        );
        if (hasRecordedCompletion) {
          records.removeWhere(
            (record) =>
                record.entityType == 'session_events' &&
                _recordEventType(record) == 'complete',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionHeader(
              title: context.l10n.text('execution_history'),
              subtitle: context.l10n.text('execution_history_detail'),
              actionLabel: context.l10n.text('add_interruption'),
              icon: Icons.flash_on_outlined,
              onAction: () => InterruptionEditorDialog.show(
                context,
                task: task,
                sessionId: runtime?.activeTaskId == task.id
                    ? runtime?.sessionId
                    : null,
              ),
            ),
            TaskHealthEvidenceStrip(
              taskId: task.id,
              margin: const EdgeInsets.only(bottom: 12),
            ),
            Card(
              child: Column(
                children: [
                  _HistoryRow(
                    icon: Icons.add_task,
                    title: context.l10n.text('task_created'),
                    time: task.createdAt,
                  ),
                  if (task.plannedStart != null || task.scheduledDate != null)
                    _HistoryRow(
                      icon: Icons.event_outlined,
                      title: context.l10n.text('history_scheduled'),
                      time: task.plannedStart ?? task.scheduledDate!,
                      details: task.plannedEnd == null
                          ? null
                          : context.l10n.format('history_planned_until', {
                              'time': DateFormat.yMMMd(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).add_jm().format(task.plannedEnd!.toLocal()),
                            }),
                    ),
                  if (task.actualStart != null)
                    _HistoryRow(
                      icon: Icons.play_arrow,
                      title: context.l10n.text('first_started'),
                      time: task.actualStart!,
                    ),
                  if (task.actualFinish != null && !hasRecordedCompletion)
                    _HistoryRow(
                      icon: Icons.check,
                      title: context.l10n.text('completed'),
                      time: task.actualFinish!,
                    ),
                  for (final record in records)
                    _HistoryRow(
                      icon: _historyIcon(record.entityType),
                      title: _historyTitle(context, record),
                      time: _historyTime(record),
                      details: _historyDetails(context, record),
                      onTap: record.entityType == 'interruptions'
                          ? () => InterruptionEditorDialog.show(
                              context,
                              task: task,
                              sessionId: runtime?.activeTaskId == task.id
                                  ? runtime?.sessionId
                                  : null,
                              existing: record,
                            )
                          : null,
                      trailing: record.entityType == 'interruptions'
                          ? Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  tooltip: context.l10n.text(
                                    'edit_interruption',
                                  ),
                                  onPressed: () =>
                                      InterruptionEditorDialog.show(
                                        context,
                                        task: task,
                                        sessionId:
                                            runtime?.activeTaskId == task.id
                                            ? runtime?.sessionId
                                            : null,
                                        existing: record,
                                      ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: context.l10n.text('delete'),
                                  onPressed: () => _deleteInterruptionWithUndo(
                                    context,
                                    ref,
                                    record,
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TaskSettingsPanel extends ConsumerWidget {
  const _TaskSettingsPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    final configuration =
        (jsonDecode(task.dataJson) as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final keepWorkspace =
        configuration['browser_persistence_mode'] != 'start_clean';
    final autoOpenResource = configuration['auto_open_resource'] != false;
    final launchMode = TaskResourceLaunchMode.fromKey(
      configuration['resource_launch_mode'],
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          title: context.l10n.text('task_settings'),
          subtitle: context.l10n.text('task_settings_detail'),
          actionLabel: context.l10n.text('task_edit'),
          icon: Icons.edit_outlined,
          onAction: () => TaskEditorDialog.show(context, task: task),
        ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: keepWorkspace,
                onChanged: (value) async {
                  final updated = Map<String, Object?>.from(configuration);
                  updated['browser_persistence_mode'] = value
                      ? 'keep_all'
                      : 'start_clean';
                  await ref
                      .read(taskRepositoryProvider)
                      .updateConfiguration(task, updated);
                  unawaited(ref.read(syncServiceProvider).drainOutbox());
                },
                title: Text(context.l10n.text('keep_browser_workspace')),
                subtitle: Text(
                  context.l10n.text('keep_browser_workspace_detail'),
                ),
              ),
              SwitchListTile(
                value: autoOpenResource,
                onChanged: (value) async {
                  final updated = Map<String, Object?>.from(configuration);
                  updated['auto_open_resource'] = value;
                  await ref
                      .read(taskRepositoryProvider)
                      .updateConfiguration(task, updated);
                  unawaited(ref.read(syncServiceProvider).drainOutbox());
                },
                title: Text(context.l10n.text('resource_auto_open')),
                subtitle: Text(context.l10n.text('resource_auto_open_detail')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: DropdownButtonFormField<TaskResourceLaunchMode>(
                  key: ValueKey('resource-launch-${launchMode.key}'),
                  isExpanded: true,
                  initialValue: launchMode == TaskResourceLaunchMode.disabled
                      ? TaskResourceLaunchMode.inApp
                      : launchMode,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('resource_launch_behavior'),
                    helperText: context.l10n.text(
                      'resource_launch_behavior_detail',
                    ),
                    prefixIcon: const Icon(Icons.open_in_new_outlined),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: TaskResourceLaunchMode.inApp,
                      child: Text(context.l10n.text('resource_open_in_app')),
                    ),
                    DropdownMenuItem(
                      value: TaskResourceLaunchMode.externalApp,
                      child: Text(
                        context.l10n.text('resource_open_installed_app'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: TaskResourceLaunchMode.externalBrowser,
                      child: Text(
                        context.l10n.text('resource_open_external_browser'),
                      ),
                    ),
                  ],
                  onChanged: autoOpenResource
                      ? (mode) async {
                          if (mode == null) return;
                          final updated = Map<String, Object?>.from(
                            configuration,
                          );
                          updated['resource_launch_mode'] = mode.key;
                          await ref
                              .read(taskRepositoryProvider)
                              .updateConfiguration(task, updated);
                          unawaited(
                            ref.read(syncServiceProvider).drainOutbox(),
                          );
                        }
                      : null,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(context.l10n.text('reminders')),
                subtitle: Text(context.l10n.text('task_reminders_detail')),
                trailing: FilledButton.tonal(
                  onPressed: () => _addReminder(context, ref, task),
                  child: Text(context.l10n.text('add')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<LocalEntityRecord>>(
          stream: entities.watch(
            entityType: 'task_reminders',
            parentId: task.id,
          ),
          builder: (context, snapshot) {
            final reminders = snapshot.data ?? const [];
            if (reminders.isEmpty) {
              return _EmptyPanel(
                icon: Icons.notifications_off_outlined,
                title: context.l10n.text('no_task_reminders'),
                message: context.l10n.text('no_task_reminders_detail'),
              );
            }
            return Column(
              children: [
                for (final reminder in reminders)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(reminder.title),
                      subtitle: Text(
                        _formatReminder(entities.decode(reminder), context),
                      ),
                      trailing: IconButton(
                        onPressed: () => entities.softDelete(reminder),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RoadmapConnectionCard extends ConsumerWidget {
  const _RoadmapConnectionCard({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<LocalRoadmap>>(
      stream: ref.watch(roadmapRepositoryProvider).watchRoadmaps(),
      builder: (context, snapshot) {
        final roadmaps = snapshot.data ?? const [];
        final current = roadmaps
            .where((roadmap) => roadmap.id == task.roadmapId)
            .firstOrNull;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.route_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.text('roadmap_and_phase'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            current?.title ??
                                context.l10n.text('roadmap_not_linked'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (current != null)
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                RoadmapDetailScreen(roadmapId: current.id),
                          ),
                        ),
                        child: Text(context.l10n.text('open_roadmap')),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: current?.id,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('roadmap_title_short'),
                    prefixIcon: const Icon(Icons.route_outlined),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.l10n.text('task_no_roadmap')),
                    ),
                    for (final roadmap in roadmaps)
                      DropdownMenuItem(
                        value: roadmap.id,
                        child: Text(roadmap.title),
                      ),
                  ],
                  onChanged: (roadmapId) async {
                    await ref
                        .read(taskRepositoryProvider)
                        .updateRelationships(
                          task,
                          roadmapId: roadmapId,
                          roadmapPhaseId: null,
                        );
                    unawaited(ref.read(syncServiceProvider).drainOutbox());
                  },
                ),
                if (current != null) ...[
                  const SizedBox(height: 12),
                  StreamBuilder<List<LocalEntityRecord>>(
                    stream: ref
                        .watch(roadmapRepositoryProvider)
                        .watchPhases(current.id),
                    builder: (context, phaseSnapshot) {
                      final phases = phaseSnapshot.data ?? const [];
                      return DropdownButtonFormField<String?>(
                        initialValue:
                            phases.any(
                              (phase) => phase.id == task.roadmapPhaseId,
                            )
                            ? task.roadmapPhaseId
                            : null,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('task_roadmap_phase'),
                          prefixIcon: const Icon(Icons.view_timeline_outlined),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              context.l10n.text('task_roadmap_level'),
                            ),
                          ),
                          for (final phase in phases)
                            DropdownMenuItem(
                              value: phase.id,
                              child: Text(phase.title),
                            ),
                        ],
                        onChanged: (phaseId) async {
                          await ref
                              .read(taskRepositoryProvider)
                              .updateRelationships(
                                task,
                                roadmapId: current.id,
                                roadmapPhaseId: phaseId,
                              );
                          unawaited(
                            ref.read(syncServiceProvider).drainOutbox(),
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionList extends ConsumerWidget {
  const _ConnectionList({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.stream,
    required this.entities,
    required this.addLabel,
    required this.onAdd,
    this.applicationEntries = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Stream<List<LocalEntityRecord>> stream;
  final EntityRecordRepository entities;
  final String addLabel;
  final VoidCallback onAdd;
  final bool applicationEntries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: stream,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const [];
        return Card(
          key: ValueKey('connection-card-$title'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 420;
                    final copy = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    );
                    final add = TextButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: Text(addLabel),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(radius: 20, child: Icon(icon)),
                              const SizedBox(width: 12),
                              Expanded(child: copy),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: add,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        CircleAvatar(child: Icon(icon)),
                        const SizedBox(width: 12),
                        Expanded(child: copy),
                        const SizedBox(width: 8),
                        add,
                      ],
                    );
                  },
                ),
                if (records.isNotEmpty) ...[
                  const Divider(height: 24),
                  for (final record in records) ...[
                    Builder(
                      builder: (context) {
                        final data = _decodedEntityData(entities, record);
                        final label = applicationEntries
                            ? resolvedApplicationDisplayName(
                                userOverride:
                                    data['custom_display_name'] as String?,
                                normalizedName:
                                    data['default_display_name'] as String? ??
                                    data['display_name'] as String?,
                                displayNameSnapshot:
                                    data['display_name_snapshot'] as String? ??
                                    record.title,
                                rawIdentifier:
                                    data['raw_identifier_snapshot']
                                        as String? ??
                                    data['raw_identifier'] as String? ??
                                    data['application_identifier'] as String?,
                                unknownLabel: context.l10n.text(
                                  'unknown_application',
                                ),
                              )
                            : record.title.trim().isNotEmpty
                            ? record.title.trim()
                            : context.l10n.text('unknown_connection');
                        final description = _connectionDescription(
                          context,
                          data,
                          applicationAvailability: applicationEntries
                              ? taskApplicationAvailability(
                                  linkedPlatform:
                                      data['platform'] as String? ?? 'unknown',
                                  currentPlatform: _currentTaskPlatform(),
                                )
                              : null,
                        );
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (applicationEntries) ...[
                              const Padding(
                                padding: EdgeInsetsDirectional.only(top: 12),
                                child: Icon(Icons.apps_outlined, size: 20),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    if (description.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        description,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.text('remove_connection'),
                              onPressed: () async {
                                await entities.softDelete(record);
                                unawaited(
                                  ref.read(syncServiceProvider).drainOutbox(),
                                );
                              },
                              icon: const Icon(Icons.link_off),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.icon,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData? icon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onAction != null && actionLabel != null)
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(icon ?? Icons.add),
              label: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double? width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 205,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _WorkspaceShortcut extends StatelessWidget {
  const _WorkspaceShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExecutionModeExplanation extends StatelessWidget {
  const _ExecutionModeExplanation({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final content = context.l10n.text(switch (mode) {
      'pomodoro' => 'mode_pomodoro_detail',
      'continuous' => 'mode_continuous_detail',
      'checklist' => 'mode_checklist_detail',
      'reading' => 'mode_reading_detail',
      'habit' => 'mode_habit_detail',
      'event' => 'mode_event_detail',
      'hybrid' => 'mode_hybrid_detail',
      _ => 'mode_manual_detail',
    });
    return Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(
          context.l10n.format('mode_execution_title', {
            'mode': context.l10n.executionMode(mode),
          }),
        ),
        subtitle: Text(content),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.title,
    required this.time,
    this.details,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final DateTime time;
  final String? details;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
      trailing: trailing,
      subtitle: Text(
        [
          DateFormat.yMMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).add_jm().format(time.toLocal()),
          if (details?.trim().isNotEmpty == true) details!.trim(),
        ].join('\n'),
      ),
    );
  }
}

Future<void> _deleteInterruptionWithUndo(
  BuildContext context,
  WidgetRef ref,
  LocalEntityRecord record,
) async {
  final repository = ref.read(entityRecordRepositoryProvider);
  await repository.softDelete(record);
  unawaited(ref.read(syncServiceProvider).drainOutbox());
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(context.l10n.text('interruption_deleted')),
      duration: const Duration(seconds: 15),
      action: SnackBarAction(
        label: context.l10n.text('undo'),
        onPressed: () => unawaited(() async {
          await repository.restore(record.id);
          await ref.read(syncServiceProvider).drainOutbox();
        }()),
      ),
    ),
  );
}

Future<void> _addChecklistItem(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
  List<LocalEntityRecord> existing,
) async {
  final result = await _textAndToggleDialog(
    context,
    title: context.l10n.text('add_checklist_item'),
    label: context.l10n.text('requirement'),
    toggleLabel: context.l10n.text('required_for_completion'),
  );
  if (result == null || result.$1.trim().isEmpty) return;
  await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'checklist_items',
          parentId: task.id,
          title: result.$1,
          position: existing.length.toDouble(),
          data: {
            'task_occurrence_id': task.id,
            'description': '',
            'is_required': result.$2,
            'is_completed': false,
            'weight': 1,
          },
          syncPayload: {
            'task_template_id': null,
            'task_occurrence_id': task.id,
            'title': result.$1,
            'description': '',
            'is_required': result.$2,
            'is_completed': false,
            'completed_at': null,
            'due_at': null,
            'weight': 1,
            'position': existing.length,
            'evidence': <Object?>[],
          },
        ),
      );
  unawaited(ref.read(syncServiceProvider).drainOutbox());
}

Future<void> _showResourceActions(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(context.l10n.text('attach_files')),
            subtitle: Text(context.l10n.text('attach_files_detail')),
            onTap: () async {
              Navigator.pop(sheetContext);
              await ref
                  .read(taskResourceServiceProvider)
                  .pickAndAddFiles(taskId: task.id, synchronizeFiles: true);
              unawaited(ref.read(syncServiceProvider).drainOutbox());
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(context.l10n.text('add_url')),
            subtitle: Text(context.l10n.text('add_url_detail')),
            onTap: () async {
              Navigator.pop(sheetContext);
              final value = await _askText(
                context,
                title: context.l10n.text('add_web_resource'),
                label: context.l10n.text('url'),
                hint: 'https://example.com/resource',
              );
              if (value == null || value.trim().isEmpty) return;
              try {
                await ref
                    .read(taskResourceServiceProvider)
                    .addUrl(taskId: task.id, url: value);
              } on FormatException {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.text('resource_invalid_website_url'),
                    ),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(context.l10n.text('add_book_target')),
            subtitle: Text(context.l10n.text('add_book_target_detail')),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _addBook(context, ref, task);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _openResource(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
  LocalEntityRecord resource,
  Map<String, Object?> data,
  ValueChanged<String> onOpenUrl,
) async {
  final type = data['resource_type'] as String? ?? 'file';
  if (type == 'pdf') {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TaskDocumentWorkspace(task: task, resource: resource),
      ),
    );
  } else if (isTaskWebsiteResourceType(type)) {
    final configuredMode = configuredTaskResourceLaunchMode(task, data);
    await ref
        .read(taskResourceServiceProvider)
        .launchWebsiteRecord(
          task: task,
          resource: resource,
          mode: configuredMode == TaskResourceLaunchMode.disabled
              ? TaskResourceLaunchMode.inApp
              : configuredMode,
          openInApp: onOpenUrl,
        );
  } else if (type == 'book') {
    await _updateReadingPosition(context, ref, task, resource);
  } else {
    await ref.read(taskResourceServiceProvider).open(resource);
  }
}

Future<void> _addBook(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final title = TextEditingController();
  final author = TextEditingController();
  final pages = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.text('add_book')),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.text('title'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: author,
              decoration: InputDecoration(
                labelText: context.l10n.text('author'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pages,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.text('total_pages_optional'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.text('add_book')),
        ),
      ],
    ),
  );
  if (saved == true && title.text.trim().isNotEmpty) {
    await ref
        .read(taskResourceServiceProvider)
        .addBook(
          taskId: task.id,
          title: title.text,
          author: author.text,
          totalPages: int.tryParse(pages.text),
        );
  }
  title.dispose();
  author.dispose();
  pages.dispose();
}

Future<void> _updateReadingPosition(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
  LocalEntityRecord resource,
) async {
  final l10n = context.l10n;
  final entities = ref.read(entityRecordRepositoryProvider);
  final targets = await entities.list(
    entityType: 'reading_targets',
    parentId: task.id,
    secondaryParentId: resource.id,
  );
  if (targets.isEmpty || !context.mounted) return;
  final target = targets.first;
  final targetData = entities.decode(target);
  final controller = TextEditingController(
    text: ((targetData['current_page'] as num?)?.toInt() ?? 1).toString(),
  );
  final result = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        context.l10n.format('update_resource', {'resource': resource.title}),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: context.l10n.text('current_page'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(controller.text)),
          child: Text(context.l10n.text('save_progress')),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result <= 0) return;
  final uniquePages = List<int>.from(
    (targetData['unique_pages'] as List?)?.whereType<num>().map(
          (value) => value.toInt(),
        ) ??
        const <int>[],
  );
  final previous = (targetData['current_page'] as num?)?.toInt() ?? 1;
  for (var page = previous + 1; page <= result; page++) {
    if (!uniquePages.contains(page)) uniquePages.add(page);
  }
  final positionTitle = l10n.format('resource_page', {
    'resource': resource.title,
    'page': result,
  });
  targetData['current_page'] = result;
  targetData['unique_pages'] = uniquePages;
  await entities.updateLocalData(target, data: targetData);
  final now = DateTime.now().toUtc().toIso8601String();
  await entities.create(
    EntityRecordDraft(
      entityType: 'reading_positions',
      parentId: task.id,
      secondaryParentId: resource.id,
      title: positionTitle,
      data: {
        'reading_target_id': target.id,
        'resource_id': resource.id,
        'page_number': result,
        'unique_pages': uniquePages,
        'reread_pages': <int>[],
        'reading_duration_ms': 0,
        'recorded_at': now,
      },
      syncPayload: {
        'reading_target_id': target.id,
        'resource_id': resource.id,
        'page_number': result,
        'position_value': 'page:$result',
        'unique_pages': uniquePages,
        'reread_pages': <int>[],
        'reading_duration_ms': 0,
        'recorded_at': now,
      },
    ),
  );
}

Future<void> _addDependency(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final tasks = await ref.read(taskRepositoryProvider).watchTasks().first;
  if (!context.mounted) return;
  var relation = 'blocks';
  final selected = await showDialog<LocalTask>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.text('connect_another_task')),
        content: SizedBox(
          width: 480,
          height: 420,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: relation,
                decoration: InputDecoration(
                  labelText: context.l10n.text('relationship'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'blocks',
                    child: Text(context.l10n.text('task_depends_on')),
                  ),
                  DropdownMenuItem(
                    value: 'related',
                    child: Text(context.l10n.text('related_work')),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => relation = value ?? relation),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    for (final candidate in tasks)
                      if (candidate.id != task.id)
                        ListTile(
                          title: Text(candidate.title),
                          subtitle: Text(
                            context.l10n.taskStatus(candidate.status),
                          ),
                          onTap: () => Navigator.pop(context, candidate),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (selected == null) return;
  await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'task_dependencies',
          parentId: task.id,
          secondaryParentId: selected.id,
          title: selected.title,
          status: relation,
          data: {
            'task_occurrence_id': task.id,
            'depends_on_task_id': selected.id,
            'dependency_type': relation,
          },
          syncPayload: {
            'task_occurrence_id': task.id,
            'depends_on_task_id': selected.id,
            'dependency_type': relation,
          },
        ),
      );
}

Future<void> _addApplication(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  InstalledApplication? selected;
  if (Platform.isAndroid) {
    selected = await showInstalledApplicationPicker(
      context,
      applications: const InstalledApplicationService()
          .listInstalledApplications(),
    );
  } else {
    final identifier = await _askText(
      context,
      title: context.l10n.text('connect_application'),
      label: context.l10n.text('application_name_executable'),
      hint: 'Visual Studio Code or Code.exe',
    );
    if (identifier != null && identifier.trim().isNotEmpty) {
      selected = InstalledApplication(
        identifier: identifier.trim(),
        displayName: identifier.trim(),
        platform: 'windows',
      );
    }
  }
  if (selected == null) return;
  final displayName = normalizedApplicationDisplayName(
    selected.displayName.trim().isEmpty
        ? selected.identifier
        : selected.displayName,
  );
  final entities = ref.read(entityRecordRepositoryProvider);
  final applicationId = applicationCatalogIdForTaskConnection(
    userId: entities.userId,
    platform: selected.platform,
    applicationIdentifier: selected.identifier,
  );
  final linkId = taskApplicationLinkIdFor(
    userId: entities.userId,
    taskOccurrenceId: task.id,
    applicationId: applicationId,
  );
  final linkData = <String, Object?>{
    'task_occurrence_id': task.id,
    'application_id': applicationId,
    'platform': selected.platform.trim().toLowerCase(),
    'raw_identifier': selected.identifier.trim(),
    'raw_identifier_snapshot': selected.identifier.trim(),
    'detected_display_name': displayName,
    'display_name_snapshot': displayName,
    'default_display_name': displayName,
    'normalized_application_key_snapshot': normalizeApplicationIdentifier(
      selected.identifier,
    ),
    'relationship_type': 'supporting',
    'classification': 'direct_task_work',
    'automatic_credit': true,
  };
  final existingLinks = await entities.list(
    entityType: 'task_application_links',
    parentId: task.id,
  );
  LocalEntityRecord? existingLink;
  for (final link in existingLinks) {
    final data = _decodedEntityData(entities, link);
    if (data['application_id'] == applicationId ||
        link.secondaryParentId == applicationId) {
      existingLink = link;
      break;
    }
  }
  final alreadyConnected = existingLink != null;
  if (!alreadyConnected) {
    final removedLink = await entities.getIncludingDeleted(linkId);
    if (removedLink?.deletedAt != null) {
      await entities.restore(
        linkId,
        title: displayName,
        status: 'active',
        parentId: task.id,
        secondaryParentId: applicationId,
        data: linkData,
        syncPayload: linkData,
      );
    } else {
      await entities.create(
        EntityRecordDraft(
          id: linkId,
          entityType: 'task_application_links',
          parentId: task.id,
          secondaryParentId: applicationId,
          title: displayName,
          status: 'active',
          data: linkData,
          syncPayload: linkData,
        ),
      );
    }
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  } else {
    if (!context.mounted) return;
    final unknownApplicationLabel = context.l10n.text('unknown_application');
    final existingData = _decodedEntityData(entities, existingLink);
    final currentLabel = resolvedApplicationDisplayName(
      normalizedName: existingData['default_display_name'] as String?,
      displayNameSnapshot:
          existingData['display_name_snapshot'] as String? ??
          existingLink.title,
      rawIdentifier:
          existingData['raw_identifier_snapshot'] as String? ??
          existingData['raw_identifier'] as String?,
      unknownLabel: unknownApplicationLabel,
    );
    if (currentLabel == unknownApplicationLabel) {
      await entities.update(
        existingLink,
        title: displayName,
        data: {...existingData, ...linkData},
        syncPayload: linkData,
      );
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    }
  }
  if (!context.mounted) return;
  final configured = await _offerApplicationForResourceLinks(
    context,
    ref,
    task,
    selected,
  );
  if (alreadyConnected && !configured && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.text('application_already_connected')),
      ),
    );
  }
}

Future<bool> _offerApplicationForResourceLinks(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
  InstalledApplication application,
) async {
  if (application.platform.toLowerCase() != 'android' ||
      configuredTaskResourceLaunchMode(task) ==
          TaskResourceLaunchMode.externalApp) {
    return false;
  }
  final useApplication = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        dialogContext.l10n.format('application_links_title', {
          'application': normalizedApplicationDisplayName(
            application.displayName,
          ),
        }),
      ),
      content: Text(dialogContext.l10n.text('application_links_detail')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            dialogContext.l10n.text('application_links_keep_current'),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.l10n.text('application_links_use_app')),
        ),
      ],
    ),
  );
  if (useApplication != true) return false;
  Map<String, Object?> configuration;
  try {
    final decoded = jsonDecode(task.dataJson);
    configuration = decoded is Map
        ? decoded.map<String, Object?>((key, value) => MapEntry('$key', value))
        : <String, Object?>{};
  } catch (_) {
    configuration = <String, Object?>{};
  }
  configuration['resource_launch_mode'] =
      TaskResourceLaunchMode.externalApp.key;
  configuration['auto_open_resource'] = true;
  await ref
      .read(taskRepositoryProvider)
      .updateConfiguration(task, configuration);
  unawaited(ref.read(syncServiceProvider).drainOutbox());
  return true;
}

Map<String, Object?> _decodedEntityData(
  EntityRecordRepository entities,
  LocalEntityRecord record,
) {
  final value = entities.decode(record);
  final nested = value['data'];
  return nested is Map
      ? <String, Object?>{...value, ...Map<String, Object?>.from(nested)}
      : value;
}

Future<void> _addWebsite(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final value = await _askText(
    context,
    title: context.l10n.text('connect_website'),
    label: context.l10n.text('domain_or_url'),
    hint: 'https://example.org',
  );
  if (!context.mounted) return;
  if (value == null || value.trim().isEmpty) return;
  final address = NormalizedWebsiteAddress.tryParse(value);
  if (address == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.text('resource_invalid_website_url')),
      ),
    );
    return;
  }
  final scope = await _selectWebsiteMatchScope(context, address);
  if (scope == null || !context.mounted) return;
  await ref
      .read(websiteRuleServiceProvider)
      .connectToTask(taskId: task.id, url: address.originalUrl, scope: scope);
  unawaited(ref.read(syncServiceProvider).drainOutbox());
}

Future<void> _addNote(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final body = await _askText(
    context,
    title: context.l10n.text('add_task_note'),
    label: context.l10n.text('note'),
    hint: context.l10n.text('note_hint'),
    lines: 5,
  );
  if (body == null || body.trim().isEmpty) return;
  await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'task_notes',
          parentId: task.id,
          title: body.trim().split('\n').first,
          data: {
            'task_occurrence_id': task.id,
            'body': body.trim(),
            'note_version': 1,
          },
          syncPayload: {
            'task_occurrence_id': task.id,
            'task_template_id': null,
            'session_id': null,
            'body': body.trim(),
            'note_version': 1,
            'conflicting_copy_of': null,
          },
        ),
      );
}

Future<void> _addReminder(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final l10n = context.l10n;
  var type = 'before_start';
  var date =
      task.plannedStart?.toLocal() ??
      task.scheduledDate?.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  var sound = 'system';
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.text('add_task_reminder')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(
                  labelText: context.l10n.text('reminder_type'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'before_start',
                    child: Text(context.l10n.text('before_start')),
                  ),
                  DropdownMenuItem(
                    value: 'start',
                    child: Text(context.l10n.text('at_planned_start')),
                  ),
                  DropdownMenuItem(
                    value: 'planned_end',
                    child: Text(context.l10n.text('at_planned_end')),
                  ),
                  DropdownMenuItem(
                    value: 'due',
                    child: Text(context.l10n.text('due_reminder')),
                  ),
                  DropdownMenuItem(
                    value: 'overdue',
                    child: Text(context.l10n.text('overdue_reminder')),
                  ),
                  DropdownMenuItem(
                    value: 'missed',
                    child: Text(context.l10n.text('missed_task_reminder')),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(context.l10n.text('local_date_time')),
                subtitle: Text(
                  DateFormat.yMMMd(
                    Localizations.localeOf(context).toLanguageTag(),
                  ).add_jm().format(date),
                ),
                onTap: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (day == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(date),
                  );
                  if (time == null) return;
                  setDialogState(() {
                    date = DateTime(
                      day.year,
                      day.month,
                      day.day,
                      time.hour,
                      time.minute,
                    );
                  });
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: sound,
                decoration: InputDecoration(
                  labelText: context.l10n.text('sound'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(context.l10n.text('sound_system_default')),
                  ),
                  DropdownMenuItem(
                    value: 'selected',
                    child: Text(context.l10n.text('sound_selected')),
                  ),
                  DropdownMenuItem(
                    value: 'silent',
                    child: Text(context.l10n.text('silent')),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => sound = value ?? sound),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('schedule')),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final utc = date.toUtc().toIso8601String();
  final reminderTitle = _localizedReminderTypeFrom(l10n, type);
  final reminderId = await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'task_reminders',
          parentId: task.id,
          title: reminderTitle,
          status: 'enabled',
          data: {
            'task_occurrence_id': task.id,
            'reminder_type': type,
            'scheduled_at': utc,
            'sound_key': sound,
            'enabled': true,
          },
          syncPayload: {
            'task_template_id': null,
            'task_occurrence_id': task.id,
            'reminder_type': type,
            'scheduled_at': utc,
            'offset_ms': null,
            'repeat_rule': <String, Object?>{},
            'sound_key': sound,
            'enabled': true,
          },
        ),
      );
  final settings = ref.read(appSettingsProvider).value;
  final selectedSoundKey = settings?.notificationSoundKey ?? 'system';
  final preferencesJson = settings?.notificationPreferencesJson ?? '{}';
  final category = NotificationSounds.categoryForReminderType(type);
  final effectiveSoundKey = switch (sound) {
    'selected' => selectedSoundKey,
    _ => sound,
  };
  await localNotificationService.requestPermission();
  await localNotificationService.scheduleTaskReminder(
    id: reminderId.hashCode & 0x7fffffff,
    taskId: task.id,
    taskTitle: task.title,
    reminderType: type,
    scheduledAtUtc: date.toUtc(),
    sound: sound == 'selected'
        ? NotificationSounds.forCategory(
            preferencesJson: preferencesJson,
            category: category,
            fallbackKey: selectedSoundKey,
          )
        : NotificationSounds.byKey(effectiveSoundKey),
    category: category,
    enabled: NotificationSounds.categoryEnabled(
      preferencesJson: preferencesJson,
      category: category,
    ),
    vibration: NotificationSounds.vibrationForCategory(
      preferencesJson: preferencesJson,
      category: category,
    ),
    localeCode: settings?.localeCode ?? 'en',
  );
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  int lines = 1,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: lines == 1
              ? (value) => Navigator.pop(context, value)
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(context.l10n.text('save')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<(String, bool)?> _textAndToggleDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String toggleLabel,
}) async {
  final controller = TextEditingController();
  var enabled = true;
  final result = await showDialog<(String, bool)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: label),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: Text(toggleLabel),
                onChanged: (value) => setDialogState(() => enabled = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (controller.text, enabled)),
            child: Text(context.l10n.text('add')),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

String _formatReminder(Map<String, Object?> data, BuildContext context) {
  final value = DateTime.tryParse(data['scheduled_at'] as String? ?? '');
  return [
    if (value != null)
      DateFormat.yMMMd(
        Localizations.localeOf(context).toLanguageTag(),
      ).add_jm().format(value.toLocal())
    else
      context.l10n.text('no_time'),
    _localizedSound(context, data['sound_key'] as String? ?? 'system'),
  ].join(' · ');
}

Future<WebsiteMatchScope?> _selectWebsiteMatchScope(
  BuildContext context,
  NormalizedWebsiteAddress address,
) {
  return showModalBottomSheet<WebsiteMatchScope>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sheetContext.l10n.text('website_rule_scope_title'),
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              address.originalUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final scope in WebsiteMatchScope.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_websiteScopeIcon(scope)),
                title: Text(
                  sheetContext.l10n.text(_websiteScopeLabelKey(scope)),
                ),
                subtitle: Text(
                  address.patternFor(scope),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(sheetContext).pop(scope),
              ),
          ],
        ),
      ),
    ),
  );
}

String _websiteScopeLabelKey(WebsiteMatchScope scope) => switch (scope) {
  WebsiteMatchScope.page => 'website_rule_scope_page',
  WebsiteMatchScope.section => 'website_rule_scope_section',
  WebsiteMatchScope.host => 'website_rule_scope_host',
  WebsiteMatchScope.site => 'website_rule_scope_site',
};

IconData _websiteScopeIcon(WebsiteMatchScope scope) => switch (scope) {
  WebsiteMatchScope.page => Icons.article_outlined,
  WebsiteMatchScope.section => Icons.account_tree_outlined,
  WebsiteMatchScope.host => Icons.language_outlined,
  WebsiteMatchScope.site => Icons.public,
};

String _currentTaskPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  return 'unknown';
}

String _applicationAvailabilityLabel(
  BuildContext context,
  TaskApplicationAvailability availability,
) => switch (availability) {
  TaskApplicationAvailability.available => context.l10n.text(
    'application_available_this_device',
  ),
  TaskApplicationAvailability.androidDeviceRequired => context.l10n.text(
    'application_android_device_required',
  ),
  TaskApplicationAvailability.windowsDeviceRequired => context.l10n.text(
    'application_windows_device_required',
  ),
  TaskApplicationAvailability.unavailable => context.l10n.text(
    'unavailable_device',
  ),
};

String _connectionDescription(
  BuildContext context,
  Map<String, Object?> data, {
  TaskApplicationAvailability? applicationAvailability,
}) {
  return [
    if (applicationAvailability != null)
      _applicationAvailabilityLabel(context, applicationAvailability),
    if (data['match_scope'] is String)
      context.l10n.text(
        _websiteScopeLabelKey(
          WebsiteMatchScope.fromKey(data['match_scope'] as String?),
        ),
      ),
    if (data['classification'] case final String value)
      _localizedClassification(context, value),
    if (data['dependency_type'] case final String value)
      context.l10n.text(value == 'blocks' ? 'task_depends_on' : 'related_work'),
    if (data['automatic_credit'] == true)
      context.l10n.text('automatic_credit')
    else if (data.containsKey('automatic_credit'))
      context.l10n.text('confirmation_required'),
  ].whereType<Object>().join(' · ');
}

IconData _resourceIcon(String type) {
  return switch (type) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'book' => Icons.menu_book_outlined,
    'url' => Icons.link,
    'image' => Icons.image_outlined,
    'audio' => Icons.audio_file_outlined,
    'video' => Icons.video_file_outlined,
    'spreadsheet' => Icons.table_chart_outlined,
    'document' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

IconData _historyIcon(String type) {
  return switch (type) {
    'execution_sessions' => Icons.timer_outlined,
    'pomodoro_cycles' => Icons.hourglass_bottom,
    'task_notes' => Icons.notes_outlined,
    'interruptions' => Icons.warning_amber,
    'activity_contributions' => Icons.call_merge,
    'task_completion_evidence' => Icons.task_alt,
    'task_application_links' => Icons.apps_outlined,
    'website_rules' => Icons.language,
    'task_resources' || 'resource_activity' => Icons.open_in_new,
    _ => Icons.bolt,
  };
}

String _historyTitle(BuildContext context, LocalEntityRecord record) {
  if (record.entityType == 'task_completion_evidence') {
    return context.l10n.text(switch (_lifecycleEventType(record)) {
      'completed' => 'completed',
      'completion_undone' => 'completion_undone',
      'reopened' => 'task_reopened',
      _ => 'task_history_event',
    });
  }
  if (record.entityType == 'session_events') {
    return context.l10n.text(switch (_recordEventType(record)) {
      'start' || 'start_focus' || 'resume_focus' => 'history_focus_started',
      'pause' => 'history_paused',
      'resume' => 'history_resumed',
      'finish_focus' || 'focus_completed' => 'history_focus_completed',
      'start_break' => 'history_break_started',
      'extend_break' => 'history_break_extended',
      'skip_break' => 'history_break_skipped',
      'overtime_started' => 'history_overtime_started',
      'complete' => 'completed',
      _ => 'session_events',
    });
  }
  if (record.entityType == 'execution_sessions') {
    return context.l10n.text('history_session_started');
  }
  if (record.entityType == 'pomodoro_cycles') {
    return context.l10n.text('history_pomodoro_cycle');
  }
  if (record.entityType == 'task_application_links') {
    return context.l10n.text('history_application_connected');
  }
  if (record.entityType == 'website_rules' ||
      record.entityType == 'activity_contributions') {
    return context.l10n.text('history_website_credited');
  }
  if (record.entityType == 'task_resources' ||
      record.entityType == 'resource_activity' ||
      record.entityType == 'browser_history_events') {
    return context.l10n.text('history_resource_opened');
  }
  return record.title.isEmpty
      ? _localizedEntityType(context, record.entityType)
      : _historySafeLabel(record.title) ??
            _localizedEntityType(context, record.entityType);
}

bool _historyRecordReferencesTask(
  LocalEntityRecord record,
  String taskId,
  Set<String> sessionIds,
) {
  final data = _historyData(record);
  final candidates = <Object?>[
    record.parentId,
    record.secondaryParentId,
    data['task_occurrence_id'],
    data['task_id'],
    data['target_task_id'],
  ];
  if (candidates.any((value) => value?.toString() == taskId)) return true;
  final sessionId = data['session_id']?.toString();
  return sessionIds.contains(record.parentId) ||
      sessionIds.contains(record.secondaryParentId) ||
      (sessionId != null && sessionIds.contains(sessionId));
}

Map<String, Object?> _historyData(LocalEntityRecord record) {
  try {
    final decoded = jsonDecode(record.dataJson);
    if (decoded is! Map) return const {};
    final data = Map<String, Object?>.from(decoded);
    final nested = data['data'];
    if (nested is Map) data.addAll(Map<String, Object?>.from(nested));
    final metadata = data['evidence_metadata'];
    if (metadata is Map) data.addAll(Map<String, Object?>.from(metadata));
    return data;
  } catch (_) {
    return const {};
  }
}

DateTime _historyTime(LocalEntityRecord record) {
  final data = _historyData(record);
  for (final key in const [
    'occurred_at',
    'started_at',
    'focus_started_at',
    'break_started_at',
    'completed_at',
    'finished_at',
    'ended_at',
  ]) {
    final value = data[key];
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return record.updatedAt;
}

String? _historyDetails(BuildContext context, LocalEntityRecord record) {
  final data = _historyData(record);
  int? durationMs;
  for (final key in const [
    'duration_ms',
    'focus_duration_ms',
    'break_duration_ms',
    'active_duration_ms',
    'accumulated_active_ms',
    'credited_duration_ms',
  ]) {
    final value = data[key];
    if (value is num && value > 0) {
      durationMs = value.toInt();
      break;
    }
  }
  durationMs ??= switch (data['duration_seconds']) {
    final num seconds when seconds > 0 => (seconds * 1000).round(),
    _ => null,
  };
  final device = _historySafeLabel(
    data['device_name']?.toString() ??
        data['source_device_name']?.toString() ??
        data['device_label']?.toString(),
  );
  final resource = _historySafeLabel(
    data['resource_name']?.toString() ??
        data['resource_title']?.toString() ??
        data['application_name']?.toString() ??
        data['display_name']?.toString() ??
        data['registrable_domain']?.toString() ??
        data['host']?.toString(),
  );
  final parts = <String>[
    if (durationMs != null)
      context.l10n.format('history_duration', {
        'duration': context.l10n.duration(Duration(milliseconds: durationMs)),
      }),
    if (device != null)
      context.l10n.format('history_device', {'device': device}),
    if (resource != null)
      context.l10n.format('history_resource', {'resource': resource}),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _historySafeLabel(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return null;
  }
  return trimmed.replaceAll('_', ' ');
}

String? _lifecycleEventType(LocalEntityRecord record) {
  try {
    final data = jsonDecode(record.dataJson);
    if (data is! Map) return record.title;
    final metadata = data['evidence_metadata'];
    if (metadata is Map && metadata['event_type'] is String) {
      return metadata['event_type'] as String;
    }
    return data['note'] as String? ?? record.title;
  } catch (_) {
    return record.title;
  }
}

String? _recordEventType(LocalEntityRecord record) {
  try {
    final data = jsonDecode(record.dataJson);
    return data is Map ? data['event_type'] as String? : null;
  } catch (_) {
    return null;
  }
}

String _localizedPriority(BuildContext context, int value) {
  return context.l10n.text(switch (value) {
    4 => 'priority_critical',
    3 => 'priority_high',
    2 => 'priority_important',
    1 => 'priority_normal',
    _ => 'priority_low',
  });
}

String _localizedEntityType(BuildContext context, String value) {
  return context.l10n.text(switch (value) {
    'task_notes' => 'task_notes',
    'interruptions' => 'interruptions',
    'activity_contributions' => 'activity_contributions',
    'session_events' => 'session_events',
    _ => 'activity',
  });
}

String _localizedReminderTypeFrom(AppLocalizations l10n, String type) {
  return l10n.text(switch (type) {
    'before_start' => 'before_start',
    'start' => 'at_planned_start',
    'planned_end' => 'at_planned_end',
    'due' => 'due_reminder',
    'overdue' => 'overdue_reminder',
    'missed' => 'missed_task_reminder',
    _ => 'reminders',
  });
}

String _localizedSound(BuildContext context, String value) {
  return context.l10n.text(switch (value) {
    'silent' => 'silent',
    'selected' => 'sound_selected',
    _ => 'sound_system_default',
  });
}

String _localizedClassification(BuildContext context, String value) {
  return context.l10n.text(switch (value) {
    'direct_task_work' => 'activity_class_direct',
    'supporting_work' => 'activity_class_supporting',
    'research' => 'activity_class_research',
    'communication' => 'activity_class_communication',
    'distraction' => 'activity_class_distracting',
    'idle' => 'activity_class_idle',
    _ => 'activity_class_unclassified',
  });
}
