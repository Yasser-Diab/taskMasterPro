import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';

class TaskCard extends ConsumerWidget {
  const TaskCard({required this.task, this.compact = false, super.key});

  final LocalTask task;
  final bool compact;

  Future<void> _run(WidgetRef ref, Future<void> Function() localAction) async {
    await localAction();
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final completed = task.status == 'completed';
    final active = task.status == 'in_progress';
    final paused = task.status == 'paused';
    final minutes = (task.estimatedDurationMs / 60000).round();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {},
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Row(
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 5,
                      children: [
                        _Meta(
                          icon: _modeIcon(task.executionMode),
                          label: _titleCase(task.executionMode),
                        ),
                        _Meta(
                          icon: Icons.timer_outlined,
                          label: '$minutes min',
                        ),
                        _StatusPill(status: task.status),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!completed)
                switch ((active, paused)) {
                  (true, _) => IconButton.filledTonal(
                    tooltip: context.l10n.text('pause'),
                    onPressed: () => _run(
                      ref,
                      () => ref.read(taskRepositoryProvider).pause(task),
                    ),
                    icon: const Icon(Icons.pause),
                  ),
                  (_, true) => IconButton.filled(
                    tooltip: context.l10n.text('resume'),
                    onPressed: () => _run(
                      ref,
                      () => ref.read(taskRepositoryProvider).resume(task),
                    ),
                    icon: const Icon(Icons.play_arrow),
                  ),
                  _ => IconButton.filled(
                    tooltip: context.l10n.text('start'),
                    onPressed: () => _run(
                      ref,
                      () => ref.read(taskRepositoryProvider).start(task),
                    ),
                    icon: const Icon(Icons.play_arrow),
                  ),
                },
              PopupMenuButton<String>(
                tooltip: 'Task actions',
                onSelected: (action) async {
                  switch (action) {
                    case 'complete':
                      await _run(
                        ref,
                        () => ref.read(taskRepositoryProvider).complete(task),
                      );
                    case 'delete':
                      await _run(
                        ref,
                        () => ref.read(taskRepositoryProvider).softDelete(task),
                      );
                  }
                },
                itemBuilder: (context) => [
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

  String _titleCase(String input) {
    if (input.isEmpty) return input;
    return '${input[0].toUpperCase()}${input.substring(1)}';
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
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => const Color(0xFF35A870),
      'in_progress' => Theme.of(context).colorScheme.primary,
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
          status.replaceAll('_', ' '),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}
