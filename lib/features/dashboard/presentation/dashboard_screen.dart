import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../tasks/presentation/task_card.dart';
import '../../tasks/presentation/task_editor_dialog.dart';

final todayTasksProvider = StreamProvider<List<LocalTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTodayTasks(DateTime.now()),
);

final runtimeProvider = StreamProvider<LocalRuntime?>(
  (ref) => ref.watch(taskRepositoryProvider).watchRuntime(),
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({required this.user, super.key});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(todayTasksProvider).value ?? const <LocalTask>[];
    final runtime = ref.watch(runtimeProvider).value;
    final activeTask = runtime?.activeTaskId == null
        ? null
        : tasks.where((task) => task.id == runtime!.activeTaskId).firstOrNull;
    final readyTasks = tasks
        .where(
          (task) =>
              task.status != 'completed' &&
              task.status != 'cancelled' &&
              task.id != activeTask?.id,
        )
        .toList();
    final nextTask = readyTasks.firstOrNull;
    final completed = tasks.where((task) => task.status == 'completed').length;
    final overdue = tasks.where((task) => task.status == 'overdue').length;
    final plannedMs = tasks.fold<int>(
      0,
      (total, task) => total + task.estimatedDurationMs,
    );
    final activeMs = tasks.fold<int>(
      0,
      (total, task) => total + task.activeDurationMs,
    );
    final displayName =
        user.userMetadata?['display_name'] as String? ??
        user.userMetadata?['full_name'] as String? ??
        user.email?.split('@').first ??
        '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            sliver: SliverToBoxAdapter(
              child: _DashboardHeader(
                displayName: displayName,
                onQuickAdd: () => TaskEditorDialog.show(context),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (activeTask != null && runtime != null)
                  _ActiveTaskPanel(task: activeTask, runtime: runtime)
                else
                  _NoActiveTask(onAdd: () => TaskEditorDialog.show(context)),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final next = _NextTaskCard(task: nextTask);
                    final attention = const _AttentionCard();
                    if (!wide) {
                      return Column(
                        children: [next, const SizedBox(height: 16), attention],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: next),
                        const SizedBox(width: 16),
                        const Expanded(flex: 2, child: _AttentionCard()),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _PerformanceGrid(
                  plannedMs: plannedMs,
                  activeMs: activeMs,
                  completed: completed,
                  overdue: overdue,
                ),
                const SizedBox(height: 16),
                _TodaySchedule(tasks: tasks),
                const SizedBox(height: 16),
                const _CoachingCard(),
              ]),
            ),
          ),
        ],
      ),
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
    final greeting = switch (now.hour) {
      < 12 => 'Good morning',
      < 18 => 'Good afternoon',
      _ => 'Good evening',
    };
    return Row(
      children: [
        Expanded(
          child: Column(
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
                '$greeting${displayName.isEmpty ? '' : ', $displayName'}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onQuickAdd,
          icon: const Icon(Icons.add),
          label: Text(context.l10n.text('quick_add')),
        ),
      ],
    );
  }
}

class _ActiveTaskPanel extends ConsumerWidget {
  const _ActiveTaskPanel({required this.task, required this.runtime});

  final LocalTask task;
  final LocalRuntime runtime;

  Future<void> _action(
    WidgetRef ref,
    Future<void> Function() localAction,
  ) async {
    await localAction();
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = runtime.state == 'running';
    final estimate = Duration(milliseconds: task.estimatedDurationMs);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 600;
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
                Text(
                  '${task.executionMode} • planned ${_durationLabel(estimate)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final timer = _ElapsedClock(runtime: runtime);
            final actions = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _action(
                    ref,
                    () => isRunning
                        ? ref.read(taskRepositoryProvider).pause(task)
                        : ref.read(taskRepositoryProvider).resume(task),
                  ),
                  icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    context.l10n.text(isRunning ? 'pause' : 'resume'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _action(
                    ref,
                    () => ref.read(taskRepositoryProvider).complete(task),
                  ),
                  icon: const Icon(Icons.check),
                  label: Text(context.l10n.text('complete')),
                ),
                IconButton.outlined(
                  tooltip: 'Add interruption',
                  onPressed: () {},
                  icon: const Icon(Icons.flash_on_outlined),
                ),
                IconButton.outlined(
                  tooltip: 'Add note',
                  onPressed: () {},
                  icon: const Icon(Icons.note_add_outlined),
                ),
              ],
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  const SizedBox(height: 18),
                  timer,
                  const SizedBox(height: 18),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                timer,
                const SizedBox(width: 24),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ElapsedClock extends StatefulWidget {
  const _ElapsedClock({required this.runtime});

  final LocalRuntime runtime;

  @override
  State<_ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends State<_ElapsedClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var milliseconds = widget.runtime.accumulatedActiveMs;
    if (widget.runtime.state == 'running' &&
        widget.runtime.segmentStartedAt != null) {
      milliseconds += DateTime.now()
          .toUtc()
          .difference(widget.runtime.segmentStartedAt!)
          .inMilliseconds;
    }
    final duration = Duration(milliseconds: milliseconds);
    return Column(
      children: [
        Text(
          _clockLabel(duration),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          'active time',
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
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.play_arrow_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No task is running',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  SizedBox(height: 4),
                  Text('Start from today’s schedule or add a responsibility.'),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
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
          title: context.l10n.text('next_task'),
          icon: Icons.auto_awesome,
        ),
        const SizedBox(height: 10),
        if (task == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No ready task requires attention.'),
            ),
          )
        else
          TaskCard(task: task!, compact: true),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Attention', icon: Icons.notifications_none),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                onTap: () {},
                leading: const Icon(Icons.compare_arrows),
                title: const Text('Cross-task work'),
                subtitle: const Text('0 detected today'),
                trailing: const Icon(Icons.chevron_right),
              ),
              const Divider(height: 1),
              ListTile(
                onTap: () {},
                leading: const Icon(Icons.hourglass_empty),
                title: const Text('Technical idle'),
                subtitle: const Text('Nothing awaiting review'),
                trailing: const Icon(Icons.chevron_right),
              ),
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
    required this.activeMs,
    required this.completed,
    required this.overdue,
  });

  final int plannedMs;
  final int activeMs;
  final int completed;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: context.l10n.text('daily_performance'),
          icon: Icons.analytics_outlined,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 860 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(
                  width: width,
                  label: context.l10n.text('planned'),
                  value: _durationLabel(Duration(milliseconds: plannedMs)),
                  icon: Icons.event_note,
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('active_work'),
                  value: _durationLabel(Duration(milliseconds: activeMs)),
                  icon: Icons.bolt,
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('completed'),
                  value: '$completed',
                  icon: Icons.task_alt,
                ),
                _MetricCard(
                  width: width,
                  label: context.l10n.text('overdue'),
                  value: '$overdue',
                  icon: Icons.warning_amber,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
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
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
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
    );
  }
}

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({required this.tasks});

  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: '${context.l10n.text('today')}’s schedule',
          icon: Icons.view_agenda_outlined,
        ),
        const SizedBox(height: 10),
        if (tasks.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nothing is scheduled for today.'),
            ),
          )
        else ...[
          for (final task in tasks) ...[
            TaskCard(task: task, compact: true),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _CoachingCard extends StatelessWidget {
  const _CoachingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.psychology_outlined),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coaching will use evidence, not guesses',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Complete a few sessions and TaskMaster Pro will compare '
                    'planned effort with actual effort before suggesting changes.',
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Evidence: 0 comparable sessions • Confidence: not rated',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton.outlined(
              tooltip: 'Helpful',
              onPressed: null,
              icon: const Icon(Icons.thumb_up_outlined),
            ),
          ],
        ),
      ),
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

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${duration.inMinutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String _clockLabel(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
