import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/task_execution_commands.dart';
import '../data/task_execution_providers.dart';
import '../data/task_repository.dart';
import '../domain/pomodoro_execution_state.dart';

/// An explicit escape hatch for forgotten pauses.
///
/// It intentionally contains no timer: paused wall time remains dead. A
/// shared minute clock only decides when the twelve-hour prompt becomes due.
class StalePausedTaskRecovery extends ConsumerStatefulWidget {
  const StalePausedTaskRecovery({
    required this.task,
    required this.runtime,
    this.compact = false,
    super.key,
  });

  final LocalTask task;
  final LocalRuntime? runtime;
  final bool compact;

  @override
  ConsumerState<StalePausedTaskRecovery> createState() =>
      _StalePausedTaskRecoveryState();
}

class _StalePausedTaskRecoveryState
    extends ConsumerState<StalePausedTaskRecovery> {
  bool _busy = false;

  Future<void> _resolve(StalePausedTaskDecision decision) async {
    if (_busy) return;
    setState(() => _busy = true);
    var resolved = false;
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: () async {
          resolved = await ref
              .read(taskRepositoryProvider)
              .resolveStalePausedTask(widget.task, decision);
        },
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
      if (!mounted || !resolved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('stale_pause_resolved'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final paused =
        (runtime?.activeTaskId == widget.task.id &&
            runtime?.state == 'paused') ||
        widget.task.status == 'paused';
    if (!paused) return const SizedBox.shrink();
    ref.watch(stalePausedTaskClockProvider);
    if (!isStalePausedTask(
      task: widget.task,
      runtime: runtime,
      now: DateTime.now().toUtc(),
    )) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('stale-pause-recovery-${widget.task.id}'),
      width: double.infinity,
      padding: EdgeInsets.all(widget.compact ? 12 : 14),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.error.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_rounded, color: colors.error, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.text('stale_pause_title'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.l10n.text('stale_pause_body'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => _resolve(StalePausedTaskDecision.needsAttention),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.assignment_return_outlined),
                label: Text(context.l10n.text('stale_pause_needs_attention')),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _resolve(StalePausedTaskDecision.skip),
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(context.l10n.text('stale_pause_skip')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
