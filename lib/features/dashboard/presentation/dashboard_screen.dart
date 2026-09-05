import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../../activity/data/activity_repository.dart';
import '../../activity/presentation/activity_review_screen.dart';
import '../../activity/presentation/break_activity_check_in.dart';
import '../../coaching/data/adaptive_coaching_service.dart';
import '../../coaching/presentation/coaching_expression_visual.dart';
import '../../tasks/data/task_execution_commands.dart';
import '../../tasks/data/task_execution_providers.dart';
import '../../tasks/domain/pomodoro_execution_state.dart';
import '../../tasks/domain/task_occurrence_policy.dart';
import '../../tasks/presentation/task_card.dart';
import '../../tasks/presentation/task_completion_flow.dart';
import '../../tasks/presentation/task_editor_dialog.dart';
import '../../tasks/presentation/interruption_editor_dialog.dart';
import '../../tasks/presentation/standalone_pomodoro_screen.dart';
import '../../tasks/presentation/task_start_flow.dart';
import '../../tasks/presentation/stale_paused_task_recovery.dart';
import '../../tasks/presentation/task_workspace_screen.dart';
import '../../tasks/domain/daily_planned_time.dart';
import 'today_recorded_sessions_screen.dart';

/// Coaching decisions remain locale-neutral. Duration evidence crosses this
/// boundary as milliseconds and is rendered here with the one shared,
/// localized duration formatter instead of leaking raw minute counts.
Map<String, Object?> _coachingDisplayValues(
  AppLocalizations l10n,
  Map<String, Object?> values,
) {
  final formatted = <String, Object?>{...values};
  final durationMs = formatted.remove('duration_ms');
  if (durationMs is num) {
    formatted['duration'] = l10n.duration(
      Duration(milliseconds: durationMs.round().clamp(0, 1 << 53).toInt()),
    );
  }
  return formatted;
}

final todayTasksProvider = StreamProvider<List<LocalTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTodayTasks(DateTime.now()),
);

final allTasksProvider = StreamProvider<List<LocalTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTasks(),
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    required this.user,
    this.onOpenTasksFilter,
    this.onOpenActivityFilter,
    super.key,
  });

  final User user;
  final ValueChanged<String>? onOpenTasksFilter;
  final ValueChanged<String>? onOpenActivityFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(todayTasksProvider).value ?? const <LocalTask>[];
    final allTasks = ref.watch(allTasksProvider).value ?? const <LocalTask>[];
    final settings = ref.watch(appSettingsProvider).value;
    final now = DateTime.now();
    final timeZone = settings?.timeZone ?? 'UTC';
    final localToday = TaskOccurrencePolicy.localDateAt(
      now,
      timeZone: timeZone,
    );
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    final recordedWork =
        ref.watch(todayRecordedWorkSummaryProvider).value ??
        TodayRecordedWorkSummary.empty;
    final activeTaskState = runtime?.activeTaskId == null
        ? null
        : ref.watch(taskExecutionTaskProvider(runtime!.activeTaskId!));
    final activeTask = activeTaskState?.value;
    final readyTasks = tasks
        .where(
          (task) =>
              task.status != 'completed' &&
              task.status != 'cancelled' &&
              task.status != 'in_progress' &&
              // The shared runtime ID is available before the individual
              // task stream finishes loading, so it is the only safe way to
              // keep an active task out of the suggestion list.
              task.id != runtime?.activeTaskId &&
              // A recurring task creates future occurrences with different
              // IDs. While one occurrence is active, presenting another
              // occurrence of the exact same template as "next" is just as
              // contradictory to the user as showing the active occurrence.
              (task.templateId == null ||
                  task.templateId != activeTask?.templateId) &&
              // A legacy recurrence import can omit the template identifier
              // from one side of the local query. Keep the visible state
              // coherent even during that migration window.
              (activeTask == null || task.title != activeTask.title),
        )
        .toList();
    final schedule = _buildSchedule(
      day: DateTime.now(),
      scheduledTasks: tasks,
      allTasks: allTasks,
      activeTask: activeTask,
    );
    final nextTask = readyTasks.firstOrNull;
    // Roadmap recommendations are useful cards, but they are not scheduled
    // work and must never inflate today's planned/completed totals.
    final scheduledTasks = schedule
        .where((entry) => !entry.suggested)
        .map((entry) => entry.task)
        .toList();
    final completed = allTasks
        .where(
          (task) => TaskOccurrencePolicy.isCompletedOn(
            task,
            localToday,
            timeZone: timeZone,
          ),
        )
        .length;
    final overdue = TaskOccurrencePolicy.overdueOccurrences(
      allTasks,
      now: now,
      timeZone: timeZone,
    ).length;
    final plannedMs = DailyPlannedTime.calculate(
      scheduledTasks,
      localDay: localToday,
      timeZone: timeZone,
    ).inMilliseconds;
    final profile = ref.watch(localProfileProvider(user.id)).value;
    final displayName = profile?.displayName.trim().isNotEmpty == true
        ? profile!.displayName
        : user.userMetadata?['display_name'] as String? ??
              user.userMetadata?['full_name'] as String? ??
              user.email?.split('@').first ??
              '';
    final age = _ageOn(profile?.dateOfBirth, DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        // A desktop-sized gutter leaves too little usable width on a 360 px
        // phone. Keep the generous spacing on larger layouts, but reserve
        // room for the actual task content on compact screens.
        final compact = constraints.maxWidth < 420;
        final horizontalPadding = compact ? 16.0 : 24.0;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compact ? 20 : 24,
                  horizontalPadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: _DashboardHeader(
                    displayName: displayName,
                    onQuickAdd: () => TaskEditorDialog.show(context),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  20,
                  horizontalPadding,
                  32,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (activeTask != null && runtime != null)
                      _ActiveTaskPanel(task: activeTask, runtime: runtime)
                    else if (runtime != null &&
                        activeTaskState?.isLoading == true)
                      const _RestoringActiveTaskPanel()
                    else if (runtime != null)
                      _UnavailableActiveTaskPanel(
                        onRetry: () => unawaited(
                          ref.read(syncServiceProvider).synchronizeNow(),
                        ),
                      )
                    else
                      _NoActiveTask(
                        onAdd: () => TaskEditorDialog.show(context),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: ActionChip(
                        key: const ValueKey(
                          'dashboard-standalone-pomodoro-shortcut',
                        ),
                        avatar: const Icon(Icons.timer_outlined, size: 18),
                        label: Text(context.l10n.text('standalone_pomodoro')),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StandalonePomodoroScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 900;
                        final next = _NextTaskCard(task: nextTask);
                        final attention = _AttentionCard(
                          onOpenFilter: onOpenActivityFilter,
                        );
                        if (!wide) {
                          return Column(
                            children: [
                              next,
                              const SizedBox(height: 20),
                              attention,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: next),
                            const SizedBox(width: 20),
                            Expanded(flex: 2, child: attention),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _PerformanceGrid(
                      plannedMs: plannedMs,
                      recordedWork: recordedWork,
                      runtime: runtime,
                      completed: completed,
                      overdue: overdue,
                      onOpenTasksFilter: onOpenTasksFilter,
                    ),
                    const SizedBox(height: 20),
                    _TodaySchedule(
                      entries: schedule,
                      activeTaskId: runtime?.activeTaskId,
                      activeSessionState: runtime?.state,
                    ),
                    const SizedBox(height: 20),
                    _AdaptiveCoachingCard(
                      userId: user.id,
                      userName: displayName,
                      age: age,
                      createdAt: profile?.createdAt,
                      tasks: allTasks,
                      runtime: runtime,
                      settings: settings,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.displayName, required this.onQuickAdd});

  final String displayName;
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greetingKey = switch (now.hour) {
      < 12 => 'dashboard_greeting_morning',
      < 18 => 'dashboard_greeting_afternoon',
      _ => 'dashboard_greeting_evening',
    };
    final greeting = context.l10n.format(greetingKey, {
      'userName': displayName,
    });
    Widget title({required bool compact}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.yMMMMEEEEd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(now),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          greeting,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: compact ? 29 : null,
            height: compact ? 1.08 : null,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    final add = FilledButton.icon(
      onPressed: onQuickAdd,
      icon: const Icon(Icons.add),
      label: Text(context.l10n.text('quick_add')),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title(compact: compact),
              const SizedBox(height: 14),
              add,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title(compact: compact)),
            const SizedBox(width: 16),
            add,
          ],
        );
      },
    );
  }
}

class _ActiveTaskPanel extends ConsumerStatefulWidget {
  const _ActiveTaskPanel({required this.task, required this.runtime});

  final LocalTask task;
  final LocalRuntime runtime;

  @override
  ConsumerState<_ActiveTaskPanel> createState() => _ActiveTaskPanelState();
}

class _ActiveTaskPanelState extends ConsumerState<_ActiveTaskPanel> {
  bool _busy = false;

  LocalTask get task => widget.task;
  LocalRuntime get runtime => widget.runtime;

  Future<void> _runBusy(Future<void> Function() localAction) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: localAction,
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runPrimary(TaskExecutionPrimaryAction action) async {
    await _runBusy(() async {
      final repository = ref.read(taskRepositoryProvider);
      switch (action) {
        case TaskExecutionPrimaryAction.start:
          await startTaskWithConfirmation(
            context,
            ref,
            widget.task,
            onOpenInAppResource: (url) {
              unawaited(
                TaskWorkspaceScreen.openForTaskId(
                  context,
                  widget.task.id,
                  initialSection: 3,
                  initialBrowserUrl: url,
                ),
              );
            },
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
          await finishBreakWithOptionalActivityCheckIn(
            context: context,
            ref: ref,
            task: widget.task,
          );
      }
    });
  }

  Future<void> _skipBreak() async {
    await _runBusy(
      () => TaskExecutionCommands.skipOfferedBreak(
        ref.read(taskRepositoryProvider),
        widget.task,
      ),
    );
  }

  Future<void> _extendBreak() async {
    var extended = false;
    await _runBusy(() async {
      extended = await TaskExecutionCommands.extendBreak(
        repository: ref.read(taskRepositoryProvider),
        task: widget.task,
      );
    });
    if (!extended || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('break_extended_five'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final runtime = widget.runtime;
    if (runtime.state == 'running' || runtime.state == 'break') {
      ref.watch(taskExecutionClockProvider);
    }
    final pomodoro = task.executionMode == 'pomodoro'
        ? PomodoroExecutionSnapshot.fromTask(
            task: task,
            runtime: runtime,
            now: DateTime.now().toUtc(),
          )
        : null;
    final controls = TaskExecutionControlState.from(
      taskId: task.id,
      executionMode: task.executionMode,
      runtime: runtime,
      pomodoro: pomodoro,
    );
    final breakCompleted = pomodoro?.breakComplete ?? false;
    final estimate = Duration(milliseconds: task.estimatedDurationMs);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => TaskWorkspaceScreen.openForTaskId(
          context,
          task.id,
          initialSection: 1,
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('active_task').toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _RuntimeStatusPill(
                    state: runtime.state,
                    breakCompleted: breakCompleted,
                  ),
                  if (runtime.state == 'paused') ...[
                    const SizedBox(height: 10),
                    StalePausedTaskRecovery(
                      task: task,
                      runtime: runtime,
                      compact: true,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.format('planned_duration', {
                      'mode': context.l10n.executionMode(task.executionMode),
                      'duration': _durationLabel(context, estimate),
                    }),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final timer = _ElapsedClock(
                task: task,
                runtime: runtime,
                pomodoro: pomodoro,
              );
              final actionButtonStyle = ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                ),
                visualDensity: VisualDensity.standard,
              );
              final primaryActions = <Widget>[
                FilledButton.icon(
                  style: actionButtonStyle,
                  onPressed: _busy ? null : () => _runPrimary(controls.primary),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(switch (controls.primary) {
                          TaskExecutionPrimaryAction.pause => Icons.pause,
                          TaskExecutionPrimaryAction.startBreak =>
                            Icons.coffee_outlined,
                          TaskExecutionPrimaryAction.startFocus =>
                            Icons.center_focus_strong,
                          _ => Icons.play_arrow,
                        }),
                  label: Text(
                    context.l10n.text(switch (controls.primary) {
                      TaskExecutionPrimaryAction.start => 'start',
                      TaskExecutionPrimaryAction.pause => 'pause',
                      TaskExecutionPrimaryAction.resume => 'resume',
                      TaskExecutionPrimaryAction.startBreak =>
                        'notification_start_break',
                      TaskExecutionPrimaryAction.startFocus =>
                        'notification_start_focus',
                    }),
                  ),
                ),
                if (controls.canStartBreakEarly)
                  OutlinedButton.icon(
                    style: actionButtonStyle,
                    onPressed: _busy
                        ? null
                        : () => _runBusy(
                            () => ref
                                .read(taskRepositoryProvider)
                                .startBreak(task),
                          ),
                    icon: const Icon(Icons.coffee_outlined),
                    label: Text(context.l10n.text('notification_start_break')),
                  ),
                if (controls.canSkipBreak)
                  OutlinedButton.icon(
                    style: actionButtonStyle,
                    onPressed: _busy ? null : _skipBreak,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: Text(context.l10n.text('pomodoro_skip_break')),
                  ),
                if (controls.canExtendBreak)
                  OutlinedButton.icon(
                    style: actionButtonStyle,
                    onPressed: _busy ? null : _extendBreak,
                    icon: const Icon(Icons.more_time),
                    label: Text(context.l10n.text('notification_extend_break')),
                  ),
                OutlinedButton.icon(
                  style: actionButtonStyle,
                  onPressed: _busy
                      ? null
                      : () => _runBusy(
                          () => completeTaskWithUndo(context, ref, task),
                        ),
                  icon: const Icon(Icons.check),
                  label: Text(context.l10n.text('complete')),
                ),
              ];
              final utilityActions = <Widget>[
                IconButton.outlined(
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                    maximumSize: const Size.square(48),
                  ),
                  tooltip: context.l10n.text('add_interruption'),
                  onPressed: () => _addInterruption(context, ref),
                  icon: const Icon(Icons.flash_on_outlined),
                ),
                IconButton.outlined(
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                    maximumSize: const Size.square(48),
                  ),
                  tooltip: context.l10n.text('add_note'),
                  onPressed: () => _addNote(context, ref),
                  icon: const Icon(Icons.note_add_outlined),
                ),
              ];
              return DashboardActiveTaskResponsiveLayout(
                details: details,
                timer: timer,
                primaryActions: primaryActions,
                utilityActions: utilityActions,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addInterruption(BuildContext context, WidgetRef ref) async {
    await InterruptionEditorDialog.show(
      context,
      task: task,
      sessionId: runtime.sessionId,
    );
  }

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final body = await _askDashboardText(
      context,
      title: context.l10n.text('add_task_note'),
      label: context.l10n.text('note_prompt'),
      lines: 4,
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
              'session_id': runtime.sessionId,
              'body': body.trim(),
              'note_version': 1,
              'conflicting_copy_of': null,
            },
          ),
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
}

/// Keeps the active task readable when a desktop window is resized down to
/// tablet width, while also giving phone controls a full-width touch target.
///
/// This is public only so the responsive geometry can be exercised without
/// constructing the dashboard's database-backed providers in widget tests.
@visibleForTesting
class DashboardActiveTaskResponsiveLayout extends StatelessWidget {
  const DashboardActiveTaskResponsiveLayout({
    required this.details,
    required this.timer,
    required this.primaryActions,
    required this.utilityActions,
    super.key,
  });

  final Widget details;
  final Widget timer;
  final List<Widget> primaryActions;
  final List<Widget> utilityActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = _DashboardActiveTaskActions(
          primaryActions: primaryActions,
          utilityActions: utilityActions,
        );

        // The control group can contain Start/Skip break, Complete, an
        // interruption, and a note at the same time. A 600 px breakpoint was
        // therefore too small: at common narrow Windows sizes the controls
        // kept their desktop row and reduced the title to a few characters.
        if (constraints.maxWidth >= 1120) {
          return Row(
            key: const ValueKey('dashboard-active-task-wide-layout'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 4, child: details),
              const SizedBox(width: 18),
              timer,
              const SizedBox(width: 24),
              Expanded(flex: 5, child: actions),
            ],
          );
        }

        if (constraints.maxWidth >= 560) {
          return Column(
            key: const ValueKey('dashboard-active-task-reflow-layout'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 18),
                  timer,
                ],
              ),
              const SizedBox(height: 18),
              actions,
            ],
          );
        }

        return Column(
          key: const ValueKey('dashboard-active-task-phone-layout'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            details,
            const SizedBox(height: 16),
            Align(alignment: AlignmentDirectional.centerStart, child: timer),
            const SizedBox(height: 16),
            actions,
          ],
        );
      },
    );
  }
}

class _DashboardActiveTaskActions extends StatelessWidget {
  const _DashboardActiveTaskActions({
    required this.primaryActions,
    required this.utilityActions,
  });

  final List<Widget> primaryActions;
  final List<Widget> utilityActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390) {
          return Column(
            key: const ValueKey('dashboard-active-task-stacked-actions'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < primaryActions.length; index++) ...[
                SizedBox(width: double.infinity, child: primaryActions[index]),
                if (index != primaryActions.length - 1)
                  const SizedBox(height: 10),
              ],
              if (primaryActions.isNotEmpty && utilityActions.isNotEmpty)
                const SizedBox(height: 10),
              if (utilityActions.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: utilityActions,
                  ),
                ),
            ],
          );
        }

        return Wrap(
          key: const ValueKey('dashboard-active-task-wrapped-actions'),
          spacing: 10,
          runSpacing: 10,
          children: [...primaryActions, ...utilityActions],
        );
      },
    );
  }
}

class _ElapsedClock extends StatelessWidget {
  const _ElapsedClock({
    required this.task,
    required this.runtime,
    required this.pomodoro,
  });

  final LocalTask task;
  final LocalRuntime runtime;
  final PomodoroExecutionSnapshot? pomodoro;

  @override
  Widget build(BuildContext context) {
    final recordedMs = liveTaskRecordedWorkMs(
      recordedMs: runtime.accumulatedActiveMs,
      running: runtime.state == 'running',
      segmentStartedAt: runtime.segmentStartedAt,
      now: DateTime.now().toUtc(),
    );
    final overtimeMs = taskEffortOvertimeMs(
      plannedMs: task.estimatedDurationMs,
      recordedMs: recordedMs,
    );
    final showsOvertime =
        pomodoro == null && runtime.state == 'running' && overtimeMs > 0;
    return Column(
      children: [
        Text(
          pomodoro == null
              ? showsOvertime
                    ? formatTaskEffortOvertime(overtimeMs)
                    : formatTaskEffortCountdown(
                        taskEffortRemainingMs(
                          plannedMs: task.estimatedDurationMs,
                          recordedMs: recordedMs,
                        ),
                      )
              : formatPomodoroCountdown(pomodoro!.remainingMs),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          pomodoro == null
              ? context.l10n.text(
                  showsOvertime ? 'overtime_label' : 'remaining',
                )
              : context.l10n.text(
                  pomodoro!.isBreak
                      ? 'pomodoro_break_session'
                      : 'pomodoro_focus_session',
                ),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _NoActiveTask extends StatelessWidget {
  const _NoActiveTask({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('dashboard-no-active-task-card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final colorScheme = Theme.of(context).colorScheme;
            final icon = CircleAvatar(
              radius: constraints.maxWidth < 360 ? 22 : 26,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(Icons.play_arrow_rounded, color: colorScheme.primary),
            );
            final title = Text(
              context.l10n.text('dashboard_no_active_task'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            );
            final description = Text(
              context.l10n.text('dashboard_start_suggestion'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            );
            final add = OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.text('add_task')),
            );
            // On a compact handset the description and action need the whole
            // card width. Reserving their width beside a large play icon is
            // what produced the word-by-word wrapping seen on real devices.
            if (constraints.maxWidth < 430) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(child: title),
                    ],
                  ),
                  const SizedBox(height: 12),
                  description,
                  const SizedBox(height: 14),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: add,
                  ),
                ],
              );
            }
            return Row(
              children: [
                icon,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 4), description],
                  ),
                ),
                const SizedBox(width: 12),
                add,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Avoids the misleading “No task is running” empty state for the short
/// interval where the authoritative runtime arrived before its task row.
class _RestoringActiveTaskPanel extends StatelessWidget {
  const _RestoringActiveTaskPanel();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(22),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// A runtime can briefly outlive a deleted or not-yet-pulled task row. That is
/// an actionable sync state, not an endless loading state that blocks the main
/// dashboard with an unlabeled spinner.
class _UnavailableActiveTaskPanel extends StatelessWidget {
  const _UnavailableActiveTaskPanel({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(
              Icons.sync_problem_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(context.l10n.text('sync_needs_attention'))),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.text('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextTaskCard extends StatelessWidget {
  const _NextTaskCard({required this.task});

  final LocalTask? task;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: context.l10n.text('dashboard_next_suggested_task'),
          icon: Icons.auto_awesome,
        ),
        const SizedBox(height: 10),
        if (task == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.l10n.text('dashboard_no_ready_task')),
            ),
          )
        else
          TaskCard(task: task!, compact: true),
      ],
    );
  }
}

class _AttentionCard extends ConsumerWidget {
  const _AttentionCard({this.onOpenFilter});

  final ValueChanged<String>? onOpenFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews =
        ref.watch(activityReviewProvider).value ??
        const <ActivityReviewEntry>[];
    final settings = ref.watch(appSettingsProvider).value;
    tz.Location location;
    try {
      location = tz.getLocation(settings?.timeZone ?? 'UTC');
    } catch (_) {
      location = tz.UTC;
    }
    final now = tz.TZDateTime.now(location);
    final start = tz.TZDateTime(location, now.year, now.month, now.day).toUtc();
    final end = now.toUtc();
    final todayReviews = reviews.where(
      (entry) =>
          entry.segment.endedAt.toUtc().isAfter(start) &&
          entry.segment.startedAt.toUtc().isBefore(end),
    );
    final summary = summarizeActivityAttention(todayReviews);
    final attentionItems =
        <({IconData icon, String titleKey, String filter, int count})>[
          if (summary.crossTaskGroups > 0)
            (
              icon: Icons.compare_arrows,
              titleKey: 'dashboard_cross_task_review',
              filter: 'pending_cross_task',
              count: summary.crossTaskGroups,
            ),
          if (summary.inactiveGroups > 0)
            (
              icon: Icons.hourglass_empty,
              titleKey: 'dashboard_inactive_review',
              filter: 'pending_idle',
              count: summary.inactiveGroups,
            ),
          if (summary.otherGroups > 0)
            (
              icon: Icons.fact_check_outlined,
              titleKey: 'dashboard_other_activity_review',
              filter: 'pending_other',
              count: summary.otherGroups,
            ),
        ];
    void openReview(String filter) {
      if (onOpenFilter != null) {
        onOpenFilter!(filter);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActivityReviewScreen(initialFilter: filter),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: context.l10n.text('dashboard_needs_attention'),
          icon: Icons.notifications_none,
        ),
        const SizedBox(height: 10),
        Card(
          child: attentionItems.isEmpty
              ? ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(context.l10n.text('dashboard_nothing_review')),
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < attentionItems.length;
                      index++
                    ) ...[
                      if (index > 0) const Divider(height: 1),
                      ListTile(
                        onTap: () => openReview(attentionItems[index].filter),
                        leading: Icon(attentionItems[index].icon),
                        title: Text(
                          context.l10n.text(attentionItems[index].titleKey),
                        ),
                        subtitle: Text(
                          context.l10n.count(
                            'dashboard_item_review',
                            'dashboard_items_review',
                            attentionItems[index].count,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PerformanceGrid extends StatelessWidget {
  const _PerformanceGrid({
    required this.plannedMs,
    required this.recordedWork,
    required this.runtime,
    required this.completed,
    required this.overdue,
    required this.onOpenTasksFilter,
  });

  final int plannedMs;
  final TodayRecordedWorkSummary recordedWork;
  final LocalRuntime? runtime;
  final int completed;
  final int overdue;
  final ValueChanged<String>? onOpenTasksFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: context.l10n.text('dashboard_today_performance'),
          icon: Icons.analytics_outlined,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            // Human-readable durations are intentionally not abbreviated.
            // On a compact handset, one full-width metric is clearer than a
            // two-column card that wraps "hours" and "minutes" vertically.
            final columns = constraints.maxWidth >= 860
                ? 4
                : constraints.maxWidth >= 440
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  width: width,
                  label: context.l10n.text('planned'),
                  value: _durationLabel(
                    context,
                    Duration(milliseconds: plannedMs),
                  ),
                  icon: Icons.event_note,
                  onTap: onOpenTasksFilter == null
                      ? null
                      : () => onOpenTasksFilter!('today'),
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('dashboard_actual_work'),
                  valueWidget: _LivePerformanceWork(
                    recordedWork: recordedWork,
                    runtime: runtime,
                  ),
                  icon: Icons.bolt,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TodayRecordedSessionsScreen(),
                    ),
                  ),
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('completed'),
                  value: '$completed',
                  icon: Icons.task_alt,
                  onTap: onOpenTasksFilter == null
                      ? null
                      : () => onOpenTasksFilter!('completed_today'),
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('overdue'),
                  value: '$overdue',
                  icon: Icons.warning_amber,
                  onTap: onOpenTasksFilter == null
                      ? null
                      : () => onOpenTasksFilter!('overdue'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LivePerformanceWork extends ConsumerWidget {
  const _LivePerformanceWork({
    required this.recordedWork,
    required this.runtime,
  });

  final TodayRecordedWorkSummary recordedWork;
  final LocalRuntime? runtime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (runtime?.state == 'running') {
      ref.watch(taskExecutionClockProvider);
    }
    var totalMs = recordedWork.totalMs;
    final runtimeSessionId = runtime?.sessionId;
    if (runtimeSessionId != null) {
      totalMs -= recordedWork.bySessionId[runtimeSessionId] ?? 0;
    }
    var runtimeMs = runtime?.accumulatedActiveMs ?? 0;
    if (runtime?.state == 'running' && runtime?.segmentStartedAt != null) {
      runtimeMs += DateTime.now()
          .toUtc()
          .difference(runtime!.segmentStartedAt!)
          .inMilliseconds;
    }
    return Text(
      _durationLabel(
        context,
        Duration(milliseconds: (totalMs + runtimeMs).clamp(0, 1 << 62).toInt()),
      ),
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _RuntimeStatusPill extends StatelessWidget {
  const _RuntimeStatusPill({required this.state, this.breakCompleted = false});

  final String state;
  final bool breakCompleted;

  @override
  Widget build(BuildContext context) {
    final isRunning = state == 'running';
    final isBreak = state == 'break';
    final label = isBreak
        ? context.l10n.text(
            breakCompleted
                ? 'notification_break_completed_title'
                : 'break_in_progress',
          )
        : context.l10n.taskStatus(isRunning ? 'running' : 'paused');
    final color = isBreak
        ? breakCompleted
              ? Colors.cyan
              : Colors.teal
        : isRunning
        ? Colors.green
        : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.icon,
    this.value,
    this.valueWidget,
    this.onTap,
  }) : assert(value != null || valueWidget != null);

  final double width;
  final String label;
  final String? value;
  final Widget? valueWidget;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      valueWidget ??
                          Text(
                            value!,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                      Text(
                        label,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
  }
}

class _ScheduleEntry {
  const _ScheduleEntry({required this.task, this.suggested = false});

  final LocalTask task;
  final bool suggested;
}

List<_ScheduleEntry> _buildSchedule({
  required DateTime day,
  required List<LocalTask> scheduledTasks,
  required List<LocalTask> allTasks,
  required LocalTask? activeTask,
}) {
  final logical = <String, LocalTask>{};
  for (final task in scheduledTasks) {
    final key = _scheduleKey(task);
    // Repeated occurrences created before the recurrence migration can share
    // a title and planning identity but still have different IDs.  The active
    // occurrence must win that logical slot so the dated card uses the same
    // canonical runtime state as the active-task panel.
    if (activeTask != null && key == _scheduleKey(activeTask)) {
      logical[key] = activeTask;
      continue;
    }
    final existing = logical[key];
    if (existing == null ||
        _scheduleOrder(task).compareTo(_scheduleOrder(existing)) < 0) {
      logical[key] = task;
    }
  }
  final dayStart = DateTime(day.year, day.month, day.day);
  final nextDayStart = dayStart.add(const Duration(days: 1));
  final activeDate = activeTask?.scheduledDate?.toLocal();
  if (activeTask != null &&
      activeDate != null &&
      !activeDate.isBefore(dayStart) &&
      activeDate.isBefore(nextDayStart)) {
    logical[_scheduleKey(activeTask)] = activeTask;
  }
  final scheduled = logical.values.toList()
    ..sort((a, b) => _scheduleOrder(a).compareTo(_scheduleOrder(b)));

  // A roadmap task is a recommendation, not a hidden duplicate.  It remains
  // editable and is shown only when the user has no dated occurrence for the
  // same logical work today.
  final suggested =
      allTasks
          .where(
            (task) =>
                task.status != 'completed' &&
                task.status != 'cancelled' &&
                task.roadmapId != null &&
                task.priority >= 3 &&
                !logical.containsKey(_scheduleKey(task)) &&
                (task.scheduledDate == null ||
                    task.scheduledDate!.isAfter(
                      day.add(const Duration(days: 1)),
                    )),
          )
          .toList()
        ..sort((a, b) => _scheduleOrder(a).compareTo(_scheduleOrder(b)));

  return [
    for (final task in scheduled) _ScheduleEntry(task: task),
    for (final task in suggested.take(2))
      _ScheduleEntry(task: task, suggested: true),
  ];
}

String _scheduleKey(LocalTask task) {
  if (task.templateId != null && task.templateId!.isNotEmpty) {
    return 'template:${task.templateId}';
  }
  // Legacy recurring rows created before template IDs were persisted are
  // recognized by their otherwise identical planning identity.
  return 'task:${task.title.trim().toLowerCase()}:${task.roadmapId ?? ''}:${task.executionMode}:${task.estimatedDurationMs}';
}

DateTime _scheduleOrder(LocalTask task) {
  return task.plannedStart ??
      task.dueAt ??
      task.scheduledDate ??
      task.createdAt;
}

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({
    required this.entries,
    required this.activeTaskId,
    required this.activeSessionState,
  });

  final List<_ScheduleEntry> entries;
  final String? activeTaskId;
  final String? activeSessionState;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: context.l10n.text('dashboard_today_schedule'),
          icon: Icons.view_agenda_outlined,
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.l10n.text('dashboard_no_tasks_scheduled')),
            ),
          )
        else ...[
          for (final entry in entries) ...[
            TaskCard(
              task: entry.task,
              compact: true,
              suggested: entry.suggested,
              activeSessionState: entry.task.id == activeTaskId
                  ? activeSessionState
                  : null,
              // The dedicated active-task panel owns the pause/resume action.
              // This dated row remains a truthful navigation/status reference
              // instead of exposing a second competing control surface.
              hideExecutionControl: entry.task.id == activeTaskId,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _AdaptiveCoachingCard extends ConsumerStatefulWidget {
  const _AdaptiveCoachingCard({
    required this.userId,
    required this.userName,
    required this.age,
    required this.createdAt,
    required this.tasks,
    required this.runtime,
    required this.settings,
  });

  final String userId;
  final String userName;
  final int? age;
  final DateTime? createdAt;
  final List<LocalTask> tasks;
  final LocalRuntime? runtime;
  final LocalAppSetting? settings;

  @override
  ConsumerState<_AdaptiveCoachingCard> createState() =>
      _AdaptiveCoachingCardState();
}

class _AdaptiveCoachingCardState extends ConsumerState<_AdaptiveCoachingCard> {
  Future<List<AdaptiveCoachingInsight>>? _insights;
  List<AdaptiveCoachingInsight> _lastInsights = const [];
  late final PageController _pageController = PageController();
  Timer? _rotationTimer;
  int _rotationCardCount = 0;
  int _rotationDirection = 1;
  int _activePage = 0;
  bool _savingFeedback = false;

  @override
  void initState() {
    super.initState();
    _insights = _load();
  }

  @override
  void didUpdateWidget(covariant _AdaptiveCoachingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks ||
        oldWidget.runtime != widget.runtime ||
        oldWidget.settings != widget.settings ||
        oldWidget.createdAt != widget.createdAt ||
        oldWidget.age != widget.age) {
      _insights = _load();
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<List<AdaptiveCoachingInsight>> _load() async {
    final insights = await ref
        .read(adaptiveCoachingServiceProvider)
        .buildInsights(
          tasks: widget.tasks,
          runtime: widget.runtime,
          settings: widget.settings,
          accountCreatedAt: widget.createdAt,
          age: widget.age,
        );
    if (mounted) {
      _configureRotation(insights.length);
      unawaited(_publishCurrentCoaching(insights));
    }
    return insights;
  }

  void _configureRotation(int count) {
    if (_rotationCardCount == count) return;
    _rotationCardCount = count;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _rotationDirection = 1;
    _activePage = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
    if (count < 2) return;
    _rotationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_pageController.hasClients) return;
      var next = _activePage + _rotationDirection;
      if (next >= count) {
        _rotationDirection = -1;
        next = count - 2;
      } else if (next < 0) {
        _rotationDirection = 1;
        next = 1;
      }
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _publishCurrentCoaching(
    List<AdaptiveCoachingInsight> insights,
  ) async {
    final settings = widget.settings;
    if (settings == null || insights.isEmpty) return;
    final preferencesJson = settings.notificationPreferencesJson;
    if (!NotificationSounds.categoryEnabled(
      preferencesJson: preferencesJson,
      category: 'coaching',
    )) {
      return;
    }
    final insight = insights
        .where(
          (item) =>
              item.decision.score >= 50 &&
              item.decision.cardKey != 'limited_evidence_plan' &&
              item.decision.cardKey != 'first_day_learning',
        )
        .firstOrNull;
    if (insight == null || !mounted) return;
    final decision = insight.decision;
    final fingerprint = jsonEncode({
      'card': decision.cardKey,
      'values': decision.bodyValues,
      'task': decision.relatedTaskId,
      'tasks': decision.relatedTaskIds,
    });
    final preferences = await SharedPreferences.getInstance();
    final keyPrefix = 'dayvector.coaching.notification.${widget.userId}';
    final previousFingerprint = preferences.getString('$keyPrefix.fingerprint');
    final previousAt = DateTime.tryParse(
      preferences.getString('$keyPrefix.sent_at') ?? '',
    );
    final now = DateTime.now().toUtc();
    final minimumGap = switch (settings.coachingSensitivity) {
      'quiet' => const Duration(hours: 4),
      'persistent' => const Duration(minutes: 10),
      'active' => const Duration(minutes: 20),
      _ => const Duration(minutes: 45),
    };
    if (previousAt != null) {
      final age = now.difference(previousAt.toUtc());
      if (previousFingerprint == fingerprint &&
          age < const Duration(hours: 8)) {
        return;
      }
      if (age < minimumGap) return;
    }
    if (!mounted) return;
    final title = context.l10n.format(decision.titleKey, {
      'userName': widget.userName,
    });
    final body = context.l10n.format(decision.bodyKey, {
      ..._coachingDisplayValues(context.l10n, decision.bodyValues),
      'userName': widget.userName,
    });
    try {
      await localNotificationService.showCategoryNotification(
        id: LocalNotificationService.coachingNotificationId(
          'adaptive:${widget.userId}',
        ),
        category: 'coaching',
        title: title,
        body: body,
        sound: NotificationSounds.forCategory(
          preferencesJson: preferencesJson,
          category: 'coaching',
          fallbackKey: settings.notificationSoundKey,
        ),
        vibration: NotificationSounds.vibrationForCategory(
          preferencesJson: preferencesJson,
          category: 'coaching',
        ),
        localeCode: settings.localeCode,
        payload: decision.relatedTaskId == null
            ? 'coaching'
            : 'task/${decision.relatedTaskId}',
      );
      await preferences.setString('$keyPrefix.fingerprint', fingerprint);
      await preferences.setString('$keyPrefix.sent_at', now.toIso8601String());
    } catch (_) {
      // The card remains useful when OS notifications are unavailable. A
      // later state refresh will retry because no delivery fingerprint was
      // persisted.
    }
  }

  Future<void> _submit(
    AdaptiveCoachingInsight insight,
    CoachingFeedbackKind kind,
  ) async {
    if (_savingFeedback) return;
    setState(() => _savingFeedback = true);
    try {
      await ref
          .read(adaptiveCoachingServiceProvider)
          .submitFeedback(insight, kind);
      if (!mounted) return;
      setState(() => _insights = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('coaching_feedback_saved'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('coaching_feedback_failed'))),
      );
    } finally {
      if (mounted) setState(() => _savingFeedback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdaptiveCoachingInsight>>(
      future: _insights,
      initialData: _lastInsights.isEmpty ? null : _lastInsights,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.requireData.isEmpty) {
          return _CoachLoadingCard(
            reducedMotion:
                MediaQuery.maybeOf(context)?.disableAnimations ?? false,
          );
        }
        _lastInsights = snapshot.requireData;
        return _buildCarousel(context, snapshot.requireData);
      },
    );
  }

  Widget _buildCarousel(
    BuildContext context,
    List<AdaptiveCoachingInsight> insights,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(
              title: context.l10n.text('coaching'),
              icon: Icons.auto_awesome_rounded,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: compact ? 430 : 340,
              child: PageView.builder(
                key: const ValueKey('adaptive-coaching-carousel'),
                controller: _pageController,
                itemCount: insights.length,
                onPageChanged: (index) {
                  setState(() => _activePage = index);
                  if (index == 0) _rotationDirection = 1;
                  if (index == insights.length - 1) _rotationDirection = -1;
                },
                itemBuilder: (context, index) => Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: insights.length > 1 ? 8 : 0,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.topCenter,
                    child: _buildInsight(context, insights[index]),
                  ),
                ),
              ),
            ),
            if (insights.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < insights.length; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: index == _activePage ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index == _activePage
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildInsight(BuildContext context, AdaptiveCoachingInsight insight) {
    final decision = insight.decision;
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 520);
    final palette = _CoachMoodPalette.resolve(
      context,
      decision.mood,
      themeKey: widget.settings?.themeKey,
    );
    final relatedTask = decision.relatedTaskId == null
        ? null
        : widget.tasks
              .where((task) => task.id == decision.relatedTaskId)
              .firstOrNull;
    final relatedTaskIds = decision.relatedTaskIds.toSet();
    final relatedTasks = widget.tasks
        .where((task) => relatedTaskIds.contains(task.id))
        .toList(growable: false);
    final navigableTasks = relatedTasks.isNotEmpty
        ? relatedTasks
        : relatedTask == null
        ? const <LocalTask>[]
        : <LocalTask>[relatedTask];
    void openRelatedTasks() {
      if (navigableTasks.isEmpty) return;
      if (navigableTasks.length == 1) {
        TaskWorkspaceScreen.open(context, navigableTasks.single);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _CoachingRelatedTasksScreen(tasks: navigableTasks),
        ),
      );
    }

    final title = context.l10n.format(decision.titleKey, {
      'userName': widget.userName,
    });
    final body = context.l10n.format(decision.bodyKey, {
      ..._coachingDisplayValues(context.l10n, decision.bodyValues),
      'userName': widget.userName,
    });
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.foreground,
            fontWeight: FontWeight.w900,
            fontSize: 21,
            height: 1.16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: TextStyle(
            color: palette.foreground.withValues(alpha: 0.86),
            fontSize: 15,
            height: 1.42,
          ),
        ),
        if (decision.evidence.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final evidence in decision.evidence)
                Chip(
                  backgroundColor: palette.chipBackground,
                  side: BorderSide(
                    color: palette.border.withValues(alpha: 0.8),
                  ),
                  avatar: Icon(
                    Icons.insights_rounded,
                    size: 16,
                    color: palette.accent,
                  ),
                  label: Text(
                    context.l10n.format(
                      evidence.key,
                      _coachingDisplayValues(context.l10n, evidence.values),
                    ),
                    style: TextStyle(
                      color: palette.foreground.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (navigableTasks.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                backgroundColor: palette.actionBackground,
                side: BorderSide(color: palette.accent.withValues(alpha: 0.6)),
                avatar: Icon(
                  Icons.task_alt_outlined,
                  size: 16,
                  color: palette.accent,
                ),
                label: Text(
                  navigableTasks.length == 1
                      ? navigableTasks.single.title
                      : decision.evidence.isEmpty
                      ? context.l10n.text('overdue')
                      : context.l10n.format(
                          decision.evidence.first.key,
                          _coachingDisplayValues(
                            context.l10n,
                            decision.evidence.first.values,
                          ),
                        ),
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: openRelatedTasks,
              ),
            ],
          ),
        ],
      ],
    );
    final illustration = AnimatedSwitcher(
      duration: transitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: Semantics(
        key: ValueKey(decision.mood),
        child: CoachingExpressionVisual(
          expression: decision.expression,
          semanticLabel: context.l10n.text(
            decision.expression.semanticLabelKey,
          ),
          accent: palette.accent,
          size: decision.compact ? 48 : 56,
          background: palette.illustrationBackground,
          border: palette.border,
        ),
      ),
    );
    final feedback = PopupMenuButton<CoachingFeedbackKind>(
      enabled: !_savingFeedback,
      tooltip: context.l10n.text('coaching_feedback'),
      onSelected: (kind) => _submit(insight, kind),
      itemBuilder: (context) => [
        for (final kind in CoachingFeedbackKind.values)
          PopupMenuItem(
            value: kind,
            child: Text(context.l10n.text(kind.labelKey)),
          ),
      ],
      icon: _savingFeedback
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.rate_review_outlined, color: palette.foreground),
    );
    final card = AnimatedContainer(
      duration: transitionDuration,
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [palette.backgroundStart, palette.backgroundEnd],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.glow,
            blurRadius: 30,
            spreadRadius: -14,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              PositionedDirectional(
                top: -48,
                end: -36,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: transitionDuration,
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.accent.withValues(alpha: 0.08),
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.12),
                          blurRadius: 46,
                          spreadRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(decision.compact ? 18 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        illustration,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _CoachMoodBadge(
                                label: context.l10n.text(
                                  decision.mood.labelKey,
                                ),
                                palette: palette,
                              ),
                              _CoachSuggestedBadge(palette: palette),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _CoachFeedbackButton(palette: palette, child: feedback),
                      ],
                    ),
                    const SizedBox(height: 14),
                    details,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (navigableTasks.isEmpty) return card;
    return Semantics(
      button: true,
      label: title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: openRelatedTasks,
          child: card,
        ),
      ),
    );
  }
}

class _CoachingRelatedTasksScreen extends StatelessWidget {
  const _CoachingRelatedTasksScreen({required this.tasks});

  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(context.l10n.text('overdue'))),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: tasks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => TaskCard(task: tasks[index]),
      ),
    );
  }
}

class _CoachSuggestedBadge extends StatelessWidget {
  const _CoachSuggestedBadge({required this.palette});

  final _CoachMoodPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.actionBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.42)),
      ),
      child: Text(
        context.l10n.text('schedule_suggested'),
        style: TextStyle(color: palette.accent, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _CoachLoadingCard extends StatelessWidget {
  const _CoachLoadingCard({required this.reducedMotion});

  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.surfaceContainerHigh,
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              scheme.surfaceContainer,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      alignment: Alignment.center,
      child: reducedMotion
          ? Text(context.l10n.text('loading'))
          : LinearProgressIndicator(
              borderRadius: BorderRadius.circular(999),
              minHeight: 5,
            ),
    );
  }
}

class _CoachMoodBadge extends StatelessWidget {
  const _CoachMoodBadge({required this.label, required this.palette});

  final String label;
  final _CoachMoodPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: palette.actionBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.52)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.55),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: palette.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachFeedbackButton extends StatelessWidget {
  const _CoachFeedbackButton({required this.palette, required this.child});

  final _CoachMoodPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chipBackground,
        shape: BoxShape.circle,
        border: Border.all(color: palette.border.withValues(alpha: 0.75)),
      ),
      child: child,
    );
  }
}

class _CoachMoodPalette {
  const _CoachMoodPalette({
    required this.accent,
    required this.foreground,
    required this.backgroundStart,
    required this.backgroundEnd,
    required this.illustrationBackground,
    required this.chipBackground,
    required this.actionBackground,
    required this.border,
    required this.glow,
  });

  final Color accent;
  final Color foreground;
  final Color backgroundStart;
  final Color backgroundEnd;
  final Color illustrationBackground;
  final Color chipBackground;
  final Color actionBackground;
  final Color border;
  final Color glow;

  static _CoachMoodPalette resolve(
    BuildContext context,
    CoachingMood mood, {
    required String? themeKey,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isGolden = themeKey == 'golden';
    final (rawAccent, rawSecondary) = switch (mood) {
      CoachingMood.celebrating => (
        const Color(0xFF36D69A),
        const Color(0xFFFFC857),
      ),
      CoachingMood.supportive => (
        const Color(0xFF48D8FF),
        const Color(0xFF6E8FFF),
      ),
      CoachingMood.firm => (const Color(0xFFFFAA4D), const Color(0xFFFF7166)),
      CoachingMood.recovery => (
        const Color(0xFF42D6C5),
        const Color(0xFF9B8BFF),
      ),
      CoachingMood.planning => (
        const Color(0xFF6DABFF),
        const Color(0xFFB28BFF),
      ),
    };
    final accent = isGolden
        ? Color.lerp(rawAccent, const Color(0xFFFFC928), 0.26)!
        : rawAccent;
    final secondary = isGolden
        ? Color.lerp(rawSecondary, const Color(0xFFE8B923), 0.18)!
        : rawSecondary;
    final base = isDark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLowest;
    final startOpacity = isDark ? 0.22 : 0.14;
    final endOpacity = isDark ? 0.17 : 0.1;
    final backgroundStart = Color.alphaBlend(
      accent.withValues(alpha: startOpacity),
      base,
    );
    final backgroundEnd = Color.alphaBlend(
      secondary.withValues(alpha: endOpacity),
      scheme.surfaceContainer,
    );
    return _CoachMoodPalette(
      accent: accent,
      foreground: scheme.onSurface,
      backgroundStart: backgroundStart,
      backgroundEnd: backgroundEnd,
      illustrationBackground: Color.alphaBlend(
        scheme.surface.withValues(alpha: isDark ? 0.58 : 0.74),
        backgroundStart,
      ),
      chipBackground: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.12 : 0.09),
        scheme.surface.withValues(alpha: isDark ? 0.78 : 0.9),
      ),
      actionBackground: accent.withValues(alpha: isDark ? 0.15 : 0.12),
      border: Color.lerp(
        accent,
        scheme.outlineVariant,
        isDark ? 0.42 : 0.56,
      )!.withValues(alpha: 0.84),
      glow: accent.withValues(alpha: isDark ? 0.22 : 0.14),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

String _durationLabel(BuildContext context, Duration duration) {
  return context.l10n.duration(duration);
}

int? _ageOn(DateTime? birthDate, DateTime today) {
  if (birthDate == null) return null;
  var age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age -= 1;
  }
  return age < 0 ? null : age;
}

Future<String?> _askDashboardText(
  BuildContext context, {
  required String title,
  required String label,
  int lines = 2,
}) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: lines,
          maxLines: lines,
          decoration: InputDecoration(labelText: label),
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
  } finally {
    controller.dispose();
  }
}
