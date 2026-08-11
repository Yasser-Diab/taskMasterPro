import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/task_repository.dart';

/// Shared completion entry point for task cards, workspaces, notifications,
/// and tray commands. All surfaces receive the same canonical completion
/// result and the same short synchronized Undo opportunity.
Future<TaskCompletionResult> completeTaskWithUndo(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final result = await ref.read(taskRepositoryProvider).complete(task);
  unawaited(ref.read(syncServiceProvider).drainOutbox());
  if (!context.mounted) return result;

  final remaining = result.undoExpiresAt.difference(DateTime.now().toUtc());
  final canUndo = result.snapshotId.isNotEmpty && !remaining.isNegative;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(context.l10n.text('task_completed_message')),
        duration: canUndo ? remaining : const Duration(seconds: 4),
        action: canUndo
            ? SnackBarAction(
                label: context.l10n.text('undo'),
                onPressed: () => unawaited(
                  _undoCompletion(context, ref, task.id, result.snapshotId),
                ),
              )
            : null,
      ),
    );
  return result;
}

Future<void> reopenTask(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final outcome = await ref.read(taskRepositoryProvider).reopen(task.id);
  if (outcome == TaskRestorationOutcome.restored) {
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  if (!context.mounted) return;
  final message = switch (outcome) {
    TaskRestorationOutcome.restored => context.l10n.text('task_reopened'),
    TaskRestorationOutcome.reopenTooEarly => context.l10n.text(
      'completion_reopen_too_early',
    ),
    _ => context.l10n.text('completion_restore_failed'),
  };
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _undoCompletion(
  BuildContext context,
  WidgetRef ref,
  String taskId,
  String snapshotId,
) async {
  final outcome = await ref
      .read(taskRepositoryProvider)
      .undoCompletion(taskId, snapshotId: snapshotId);
  if (outcome == TaskRestorationOutcome.restored) {
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  if (!context.mounted) return;
  final message = switch (outcome) {
    TaskRestorationOutcome.restored => context.l10n.text('completion_undone'),
    TaskRestorationOutcome.undoExpired => context.l10n.text(
      'completion_undo_unavailable',
    ),
    _ => context.l10n.text('completion_restore_failed'),
  };
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
