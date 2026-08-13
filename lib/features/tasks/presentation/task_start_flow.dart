import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/task_repository.dart';
import '../data/task_resource_service.dart';
import '../data/execution_exclusivity_coordinator.dart';
import '../domain/task_resource_launch.dart';
import 'standalone_pomodoro_screen.dart';

/// Shared start flow for cards, the workspace, notifications and tray actions.
/// It keeps the selected task identity intact and requires an explicit choice
/// before changing the single account-wide active task.
Future<bool> startTaskWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  LocalTask selectedTask, {
  FutureOr<void> Function(String url)? onOpenInAppResource,
  bool launchPreferredResource = true,
}) async {
  final repository = ref.read(taskRepositoryProvider);
  var gatedStart = await ref
      .read(executionExclusivityCoordinatorProvider)
      .startTask<TaskStartResult>(
        stopStandalone: false,
        start: () => repository.start(selectedTask),
      );
  if (gatedStart.standaloneWasActive) {
    if (!context.mounted) return false;
    final choice = await showDialog<_StandaloneTimerConflictChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.text('standalone_pomodoro_active_title'),
        ),
        content: Text(
          dialogContext.l10n.text('standalone_pomodoro_active_detail'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.text('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _StandaloneTimerConflictChoice.openTimer,
            ),
            child: Text(
              dialogContext.l10n.text('standalone_pomodoro_open_timer'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _StandaloneTimerConflictChoice.stopAndStartTask,
            ),
            child: Text(
              dialogContext.l10n.text(
                'standalone_pomodoro_stop_and_start_task',
              ),
            ),
          ),
        ],
      ),
    );
    if (!context.mounted || choice == null) return false;
    if (choice == _StandaloneTimerConflictChoice.openTimer) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const StandalonePomodoroScreen(),
        ),
      );
      return false;
    }
    gatedStart = await ref
        .read(executionExclusivityCoordinatorProvider)
        .startTask<TaskStartResult>(
          stopStandalone: true,
          start: () => repository.start(selectedTask),
        );
  }
  final result = gatedStart.value;
  if (result == null) return false;
  if (!result.requiresSwitch) {
    if (!taskRuntimeOwnsStartedTask(
      await repository.getRuntime(),
      selectedTask.id,
    )) {
      return false;
    }
    if (!context.mounted) return false;
    _afterTaskStarted(
      context,
      ref,
      selectedTask,
      onOpenInAppResource: onOpenInAppResource,
      launchPreferredResource: launchPreferredResource,
    );
    return true;
  }
  final currentTask = result.activeTaskId == null
      ? null
      : await repository.getTask(result.activeTaskId!);
  if (!context.mounted) return false;
  final action = await showDialog<ActiveTaskSwitchAction>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogContext.l10n.text('task_another_running_title')),
      content: Text(
        dialogContext.l10n.format('task_another_running_detail', {
          'currentTask':
              currentTask?.title ?? dialogContext.l10n.text('active_task'),
          'selectedTask': selectedTask.title,
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.l10n.text('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.l10n.text('task_keep_current_running')),
        ),
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(ActiveTaskSwitchAction.finishCurrent),
          child: Text(dialogContext.l10n.text('task_finish_and_start')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(ActiveTaskSwitchAction.pauseCurrent),
          child: Text(dialogContext.l10n.text('task_pause_and_start')),
        ),
      ],
    ),
  );
  if (action == null) return false;
  await repository.switchActiveTask(selectedTask, action: action);
  if (!taskRuntimeOwnsStartedTask(
    await repository.getRuntime(),
    selectedTask.id,
  )) {
    return false;
  }
  if (!context.mounted) return false;
  _afterTaskStarted(
    context,
    ref,
    selectedTask,
    onOpenInAppResource: onOpenInAppResource,
    launchPreferredResource: launchPreferredResource,
  );
  return true;
}

enum _StandaloneTimerConflictChoice { openTimer, stopAndStartTask }

/// A Start action succeeded only when the canonical local runtime owns the
/// exact selected task. This guard prevents a stale hand-off from opening a
/// different task's learning resource after the repository safely no-ops.
bool taskRuntimeOwnsStartedTask(LocalRuntime? runtime, String taskId) {
  return runtime?.activeTaskId == taskId &&
      runtime?.sessionId?.isNotEmpty == true &&
      runtime?.state == 'running';
}

void _afterTaskStarted(
  BuildContext context,
  WidgetRef ref,
  LocalTask task, {
  required FutureOr<void> Function(String url)? onOpenInAppResource,
  required bool launchPreferredResource,
}) {
  unawaited(ref.read(syncServiceProvider).drainOutbox());
  if (!launchPreferredResource) return;
  final resources = ref.read(taskResourceServiceProvider);
  // Resource discovery and navigation are follow-up work. Keeping them off the
  // awaited Start path means a full-screen browser route, Android intent
  // chooser, or slow local resource query can never leave Start disabled.
  unawaited(
    _launchPreferredResource(
      context: context,
      resources: resources,
      task: task,
      onOpenInAppResource: onOpenInAppResource,
    ),
  );
}

Future<void> _launchPreferredResource({
  required BuildContext context,
  required TaskResourceService resources,
  required LocalTask task,
  required FutureOr<void> Function(String url)? onOpenInAppResource,
}) async {
  try {
    final request = await resources.preferredWebsiteLaunch(task);
    if (request == null) return;
    if (request.mode == TaskResourceLaunchMode.inApp &&
        (onOpenInAppResource == null || !context.mounted)) {
      return;
    }
    await resources.launchWebsite(
      request: request,
      openInApp: (url) async {
        if (!context.mounted) return;
        await onOpenInAppResource?.call(url);
      },
    );
  } catch (_) {
    // Starting and tracking the task is the durable operation. A resource can
    // still be opened from its task panel when an OS handler or web view fails.
  }
}
