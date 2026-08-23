import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../activity/presentation/break_activity_check_in.dart';
import '../data/task_execution_commands.dart';
import '../data/task_execution_providers.dart';
import '../domain/pomodoro_execution_state.dart';
import 'task_completion_flow.dart';
import 'task_editor_dialog.dart';
import 'task_start_flow.dart';
import 'stale_paused_task_recovery.dart';
import 'task_workspace_screen.dart';

class TaskCard extends ConsumerWidget {
  const TaskCard({
    required this.task,
    this.compact = false,
    this.suggested = false,
    this.activeSessionState,
    this.hideExecutionControl = false,
    this.domainLabel,
    this.recurrenceLabel,
    super.key,
  });

  final LocalTask task;
  final bool compact;
  final bool suggested;

  /// The runtime is canonical while a task has an active execution session.
  /// A task row can otherwise lag behind the runtime record during a realtime
  /// update and incorrectly show "Ready" next to an active task.
  final String? activeSessionState;
  final bool hideExecutionControl;
  final String? domainLabel;
  final String? recurrenceLabel;

  Future<void> _run(WidgetRef ref, Future<void> Function() localAction) async {
    await localAction();
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveStatus = activeSessionState == 'running'
        ? 'in_progress'
        : activeSessionState ?? task.status;
    final completed = effectiveStatus == 'completed';
    final note = task.description.trim();
    final runtime = effectiveStatus == 'paused'
        ? ref.watch(taskExecutionRuntimeProvider).value
        : null;
    final estimatedDuration = Duration(
      milliseconds: task.estimatedDurationMs.clamp(0, 1 << 62),
    );

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => TaskWorkspaceScreen.open(context, task),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 5,
                    height: compact ? 46 : 58,
                    decoration: BoxDecoration(
                      color: _priorityColor(context, task.priority),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            note,
                            key: ValueKey('task-subheading-${task.id}'),
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.25,
                                ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 10,
                          runSpacing: 5,
                          children: [
                            _Meta(
                              icon: _modeIcon(task.executionMode),
                              label: context.l10n.executionMode(
                                task.executionMode,
                              ),
                            ),
                            _Meta(
                              icon: Icons.timer_outlined,
                              label: context.l10n.duration(estimatedDuration),
                            ),
                            _StatusPill(
                              status: effectiveStatus,
                              activeSession: activeSessionState != null,
                            ),
                            if (domainLabel?.isNotEmpty == true)
                              _Meta(
                                icon: Icons.folder_outlined,
                                label: domainLabel!,
                              ),
                            if (recurrenceLabel?.isNotEmpty == true)
                              _Meta(
                                icon: Icons.repeat_rounded,
                                label: recurrenceLabel!,
                              ),
                            if (suggested) const _SuggestedPill(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (!completed && !hideExecutionControl)
                    _CanonicalTaskControl(task: task),
                  PopupMenuButton<String>(
                    tooltip: context.l10n.text('task_actions'),
                    onSelected: (action) async {
                      switch (action) {
                        case 'open':
                          await TaskWorkspaceScreen.open(context, task);
                        case 'edit':
                          await TaskEditorDialog.show(context, task: task);
                        case 'duplicate':
                          await _run(
                            ref,
                            () => ref
                                .read(taskRepositoryProvider)
                                .duplicate(task),
                          );
                        case 'complete':
                          await completeTaskWithUndo(context, ref, task);
                        case 'reopen':
                          await reopenTask(context, ref, task);
                        case 'delete':
                          await _run(
                            ref,
                            () => ref
                                .read(taskRepositoryProvider)
                                .softDelete(task),
                          );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'open',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.open_in_new),
                          title: Text(context.l10n.text('open_task_workspace')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(context.l10n.text('edit_task')),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.copy_outlined),
                          title: Text(context.l10n.text('duplicate')),
                        ),
                      ),
                      if (!completed)
                        PopupMenuItem(
                          value: 'complete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.check_circle_outline,
                              color: colorScheme.primary,
                            ),
                            title: Text(context.l10n.text('complete')),
                          ),
                        ),
                      if (completed)
                        PopupMenuItem(
                          value: 'reopen',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.restore,
                              color: colorScheme.primary,
                            ),
                            title: Text(context.l10n.text('reopen_task')),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            color: colorScheme.error,
                          ),
                          title: Text(context.l10n.text('delete')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (effectiveStatus == 'paused') ...[
                const SizedBox(height: 10),
                StalePausedTaskRecovery(
                  task: task,
                  runtime: runtime,
                  compact: compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _priorityColor(BuildContext context, int priority) {
    return switch (priority) {
      4 => Theme.of(context).colorScheme.error,
      3 => const Color(0xFFF28C28),
      2 => Theme.of(context).colorScheme.primary,
      1 => const Color(0xFF35A870),
      _ => Theme.of(context).colorScheme.outline,
    };
  }

  IconData _modeIcon(String mode) {
    return switch (mode) {
      'pomodoro' => Icons.timelapse,
      'continuous' => Icons.timer,
      'checklist' => Icons.checklist,
      'reading' => Icons.menu_book,
      'habit' => Icons.repeat,
      'event' => Icons.event,
      'hybrid' => Icons.hub,
      _ => Icons.touch_app,
    };
  }
}

class _CanonicalTaskControl extends ConsumerStatefulWidget {
  const _CanonicalTaskControl({required this.task});

  final LocalTask task;

  @override
  ConsumerState<_CanonicalTaskControl> createState() =>
      _CanonicalTaskControlState();
}

class _CanonicalTaskControlState extends ConsumerState<_CanonicalTaskControl> {
  bool _busy = false;

  Future<void> _run(TaskExecutionPrimaryAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    bool? startAccepted;
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: () async {
          final repository = ref.read(taskRepositoryProvider);
          switch (action) {
            case TaskExecutionPrimaryAction.start:
              startAccepted = await startTaskWithConfirmation(
                context,
                ref,
                widget.task,
                launchPreferredResource: false,
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
        },
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
      if (action == TaskExecutionPrimaryAction.start && mounted) {
        if (startAccepted != true) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.text('task_start_rejected'))),
          );
        } else {
          unawaited(
            TaskWorkspaceScreen.open(context, widget.task, initialSection: 1),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    final ownsTask = runtime?.activeTaskId == widget.task.id;
    if (ownsTask &&
        (runtime?.state == 'running' || runtime?.state == 'break')) {
      ref.watch(taskExecutionClockProvider);
    }
    final pomodoro = ownsTask && widget.task.executionMode == 'pomodoro'
        ? PomodoroExecutionSnapshot.fromTask(
            task: widget.task,
            runtime: runtime,
            now: DateTime.now().toUtc(),
          )
        : null;
    final controls = TaskExecutionControlState.from(
      taskId: widget.task.id,
      executionMode: widget.task.executionMode,
      runtime: runtime,
      pomodoro: pomodoro,
    );
    final tooltipKey = switch (controls.primary) {
      TaskExecutionPrimaryAction.start => 'start',
      TaskExecutionPrimaryAction.pause => 'pause',
      TaskExecutionPrimaryAction.resume => 'resume',
      TaskExecutionPrimaryAction.startBreak => 'notification_start_break',
      TaskExecutionPrimaryAction.startFocus => 'notification_start_focus',
    };
    final icon = switch (controls.primary) {
      TaskExecutionPrimaryAction.pause => Icons.pause,
      TaskExecutionPrimaryAction.startBreak => Icons.coffee_outlined,
      TaskExecutionPrimaryAction.startFocus => Icons.center_focus_strong,
      _ => Icons.play_arrow,
    };
    return IconButton.filledTonal(
      tooltip: context.l10n.text(tooltipKey),
      onPressed: _busy ? null : () => _run(controls.primary),
      icon: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, this.activeSession = false});

  final String status;
  final bool activeSession;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => const Color(0xFF35A870),
      'in_progress' || 'running' => Theme.of(context).colorScheme.primary,
      'break' => const Color(0xFF2BAE9A),
      'paused' => const Color(0xFFF28C28),
      'overdue' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          activeSession && (status == 'in_progress' || status == 'running')
              ? context.l10n.text('currently_running')
              : status == 'break'
              ? context.l10n.text('break_in_progress')
              : context.l10n.taskStatus(status, compact: true),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _SuggestedPill extends StatelessWidget {
  const _SuggestedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.green.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            context.l10n.text('schedule_suggested'),
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
