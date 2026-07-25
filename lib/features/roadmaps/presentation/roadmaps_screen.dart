import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../tasks/presentation/task_card.dart';
import '../data/roadmap_repository.dart';

final roadmapsProvider = StreamProvider<List<LocalRoadmap>>(
  (ref) => ref.watch(roadmapRepositoryProvider).watchRoadmaps(),
);

class RoadmapsScreen extends ConsumerWidget {
  const RoadmapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roadmaps = ref.watch(roadmapsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRoadmapEditor(context, ref),
        icon: const Icon(Icons.add_road),
        label: const Text('New roadmap'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('roadmaps'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Turn long-term outcomes into phases, milestones, checkpoints, and linked executable work',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          roadmaps.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(child: Text(error.toString())),
            ),
            data: (items) {
              if (items.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyRoadmaps(
                    onCreate: () => _showRoadmapEditor(context, ref),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 100),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisExtent: 250,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _RoadmapCard(
                    roadmap: items[index],
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            RoadmapDetailScreen(roadmapId: items[index].id),
                      ),
                    ),
                    onEdit: () =>
                        _showRoadmapEditor(context, ref, roadmap: items[index]),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoadmapCard extends ConsumerWidget {
  const _RoadmapCard({
    required this.roadmap,
    required this.onOpen,
    required this.onEdit,
  });

  final LocalRoadmap roadmap;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _riskColor(context, roadmap.riskLevel);
    final target = roadmap.forecastTargetDate ?? roadmap.originalTargetDate;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.route_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      roadmap.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) async {
                      switch (action) {
                        case 'edit':
                          onEdit();
                        case 'pause':
                          await ref
                              .read(roadmapRepositoryProvider)
                              .setStatus(
                                roadmap,
                                roadmap.status == 'paused'
                                    ? 'active'
                                    : 'paused',
                              );
                        case 'archive':
                          await ref
                              .read(roadmapRepositoryProvider)
                              .setStatus(roadmap, 'archived');
                      }
                      unawaited(ref.read(syncServiceProvider).drainOutbox());
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit roadmap'),
                      ),
                      PopupMenuItem(
                        value: 'pause',
                        child: Text(
                          roadmap.status == 'paused'
                              ? 'Resume roadmap'
                              : 'Pause roadmap',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'archive',
                        child: Text('Archive roadmap'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                roadmap.description.isEmpty
                    ? 'No description yet'
                    : roadmap.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    '${(roadmap.progress * 100).round()}%',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: roadmap.progress.clamp(0, 1),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Pill(
                    icon: Icons.flag_outlined,
                    label: target == null
                        ? 'No target'
                        : DateFormat.yMMMd().format(target),
                  ),
                  const SizedBox(width: 8),
                  _Pill(
                    icon: Icons.warning_amber_rounded,
                    label: '${roadmap.riskLevel} risk',
                    color: color,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoadmapDetailScreen extends ConsumerStatefulWidget {
  const RoadmapDetailScreen({required this.roadmapId, super.key});

  final String roadmapId;

  @override
  ConsumerState<RoadmapDetailScreen> createState() =>
      _RoadmapDetailScreenState();
}

class _RoadmapDetailScreenState extends ConsumerState<RoadmapDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref
            .read(roadmapRepositoryProvider)
            .recalculateProgress(widget.roadmapId),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(roadmapRepositoryProvider);
    return StreamBuilder<LocalRoadmap?>(
      stream: repository.watchRoadmap(widget.roadmapId),
      builder: (context, roadmapSnapshot) {
        final roadmap = roadmapSnapshot.data;
        if (roadmap == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return StreamBuilder<List<LocalEntityRecord>>(
          stream: repository.watchPhases(widget.roadmapId),
          builder: (context, phaseSnapshot) {
            final phases = phaseSnapshot.data ?? const [];
            return StreamBuilder<List<LocalEntityRecord>>(
              stream: repository.watchMilestones(widget.roadmapId),
              builder: (context, milestoneSnapshot) {
                final milestones = milestoneSnapshot.data ?? const [];
                return StreamBuilder<List<LocalEntityRecord>>(
                  stream: repository.watchCheckpoints(widget.roadmapId),
                  builder: (context, checkpointSnapshot) {
                    final checkpoints = checkpointSnapshot.data ?? const [];
                    return StreamBuilder<List<LocalTask>>(
                      stream: repository.watchLinkedTasks(widget.roadmapId),
                      builder: (context, taskSnapshot) {
                        final tasks = taskSnapshot.data ?? const [];
                        return DefaultTabController(
                          length: 5,
                          child: Scaffold(
                            appBar: AppBar(
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(roadmap.title),
                                  Text(
                                    '${(roadmap.progress * 100).round()}% complete · ${roadmap.riskLevel} risk',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              actions: [
                                IconButton(
                                  tooltip: 'Recalculate progress and forecast',
                                  onPressed: () => repository
                                      .recalculateProgress(widget.roadmapId),
                                  icon: const Icon(Icons.calculate_outlined),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    if (action == 'edit') {
                                      await _showRoadmapEditor(
                                        context,
                                        ref,
                                        roadmap: roadmap,
                                      );
                                    } else if (action == 'delete') {
                                      await _confirmDelete(
                                        context,
                                        ref,
                                        roadmap,
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit roadmap'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete roadmap'),
                                    ),
                                  ],
                                ),
                              ],
                              bottom: const TabBar(
                                isScrollable: true,
                                tabs: [
                                  Tab(
                                    icon: Icon(Icons.dashboard_outlined),
                                    text: 'Overview',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.view_timeline_outlined),
                                    text: 'Timeline',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.layers_outlined),
                                    text: 'Phases',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.task_alt_outlined),
                                    text: 'Linked work',
                                  ),
                                  Tab(
                                    icon: Icon(Icons.insights_outlined),
                                    text: 'Forecast',
                                  ),
                                ],
                              ),
                            ),
                            body: TabBarView(
                              children: [
                                _RoadmapOverview(
                                  roadmap: roadmap,
                                  phases: phases,
                                  milestones: milestones,
                                  checkpoints: checkpoints,
                                  tasks: tasks,
                                ),
                                _RoadmapTimeline(
                                  phases: phases,
                                  milestones: milestones,
                                  checkpoints: checkpoints,
                                  tasks: tasks,
                                ),
                                _RoadmapPhases(
                                  roadmapId: roadmap.id,
                                  phases: phases,
                                  milestones: milestones,
                                  checkpoints: checkpoints,
                                  tasks: tasks,
                                ),
                                _LinkedWork(
                                  roadmapId: roadmap.id,
                                  phases: phases,
                                  tasks: tasks,
                                ),
                                _RoadmapForecast(
                                  roadmap: roadmap,
                                  phaseCount: phases.length,
                                  milestoneCount: milestones.length,
                                  checkpointCount: checkpoints.length,
                                  tasks: tasks,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RoadmapOverview extends StatelessWidget {
  const _RoadmapOverview({
    required this.roadmap,
    required this.phases,
    required this.milestones,
    required this.checkpoints,
    required this.tasks,
  });

  final LocalRoadmap roadmap;
  final List<LocalEntityRecord> phases;
  final List<LocalEntityRecord> milestones;
  final List<LocalEntityRecord> checkpoints;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context) {
    final completedTasks = tasks.where((task) => task.status == 'completed');
    final completedMilestones = milestones.where(
      (item) => item.status == 'completed',
    );
    final completedCheckpoints = checkpoints.where(
      (item) => item.status == 'completed',
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roadmap.finalOutcome.isEmpty
                      ? roadmap.description
                      : roadmap.finalOutcome,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      '${(roadmap.progress * 100).round()}%',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: roadmap.progress.clamp(0, 1),
                        minHeight: 14,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(
                      icon: Icons.layers_outlined,
                      label: '${phases.length} phases',
                    ),
                    _Pill(
                      icon: Icons.flag_outlined,
                      label:
                          '${completedMilestones.length}/${milestones.length} milestones',
                    ),
                    _Pill(
                      icon: Icons.fact_check_outlined,
                      label:
                          '${completedCheckpoints.length}/${checkpoints.length} checkpoints',
                    ),
                    _Pill(
                      icon: Icons.task_alt_outlined,
                      label:
                          '${completedTasks.length}/${tasks.length} linked tasks',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ProgressExplanation(
          phases: phases,
          milestones: milestones,
          checkpoints: checkpoints,
          tasks: tasks,
        ),
      ],
    );
  }
}

class _RoadmapTimeline extends ConsumerWidget {
  const _RoadmapTimeline({
    required this.phases,
    required this.milestones,
    required this.checkpoints,
    required this.tasks,
  });

  final List<LocalEntityRecord> phases;
  final List<LocalEntityRecord> milestones;
  final List<LocalEntityRecord> checkpoints;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (phases.isEmpty) {
      return const Center(child: Text('Add a phase to build the timeline'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: phases.length,
      itemBuilder: (context, index) {
        final phase = phases[index];
        final data = ref.read(entityRecordRepositoryProvider).decode(phase);
        final phaseMilestones = milestones.where(
          (item) => item.secondaryParentId == phase.id,
        );
        final phaseCheckpoints = checkpoints.where(
          (item) => item.secondaryParentId == phase.id,
        );
        final phaseTasks = tasks.where(
          (task) => task.roadmapPhaseId == phase.id,
        );
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: phase.status == 'completed'
                          ? const Color(0xFF35A870)
                          : Theme.of(context).colorScheme.primary,
                      child: Text('${index + 1}'),
                    ),
                    if (index != phases.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phase.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(data['description'] as String? ?? ''),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            _Pill(
                              icon: Icons.flag_outlined,
                              label: '${phaseMilestones.length} milestones',
                            ),
                            _Pill(
                              icon: Icons.fact_check_outlined,
                              label: '${phaseCheckpoints.length} checkpoints',
                            ),
                            _Pill(
                              icon: Icons.task_alt_outlined,
                              label: '${phaseTasks.length} tasks',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoadmapPhases extends ConsumerWidget {
  const _RoadmapPhases({
    required this.roadmapId,
    required this.phases,
    required this.milestones,
    required this.checkpoints,
    required this.tasks,
  });

  final String roadmapId;
  final List<LocalEntityRecord> phases;
  final List<LocalEntityRecord> milestones;
  final List<LocalEntityRecord> checkpoints;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Drag phases to reorder them. Open a phase to manage its milestones, checkpoints, and linked tasks.',
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _showPhaseEditor(
                  context,
                  ref,
                  roadmapId,
                  phases.length.toDouble(),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add phase'),
              ),
            ],
          ),
        ),
        Expanded(
          child: phases.isEmpty
              ? const Center(child: Text('No phases yet'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: phases.length,
                  onReorderItem: (oldIndex, newIndex) => ref
                      .read(roadmapRepositoryProvider)
                      .reorderPhases(phases, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final phase = phases[index];
                    return _PhaseExpansionCard(
                      key: ValueKey(phase.id),
                      index: index,
                      roadmapId: roadmapId,
                      phase: phase,
                      milestones: milestones
                          .where((item) => item.secondaryParentId == phase.id)
                          .toList(),
                      checkpoints: checkpoints
                          .where((item) => item.secondaryParentId == phase.id)
                          .toList(),
                      tasks: tasks
                          .where((task) => task.roadmapPhaseId == phase.id)
                          .toList(),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PhaseExpansionCard extends ConsumerWidget {
  const _PhaseExpansionCard({
    required this.index,
    required this.roadmapId,
    required this.phase,
    required this.milestones,
    required this.checkpoints,
    required this.tasks,
    super.key,
  });

  final int index;
  final String roadmapId;
  final LocalEntityRecord phase;
  final List<LocalEntityRecord> milestones;
  final List<LocalEntityRecord> checkpoints;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(roadmapRepositoryProvider);
    final data = ref.read(entityRecordRepositoryProvider).decode(phase);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_indicator),
        ),
        title: Text(
          phase.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${milestones.length} milestones · ${checkpoints.length} checkpoints · ${tasks.length} tasks',
        ),
        trailing: Checkbox(
          value: phase.status == 'completed',
          onChanged: (value) => repository.setChildStatus(
            phase,
            value == true ? 'completed' : 'active',
          ),
        ),
        children: [
          if ((data['description'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(data['description']! as String),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _showMilestoneEditor(context, ref, roadmapId, phase.id),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Milestone'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _showCheckpointEditor(context, ref, roadmapId, phase.id),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Checkpoint'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _showLinkTask(context, ref, roadmapId, phase.id),
                  icon: const Icon(Icons.add_link),
                  label: const Text('Link task'),
                ),
              ],
            ),
          ),
          for (final item in [...milestones, ...checkpoints])
            CheckboxListTile(
              value: item.status == 'completed',
              onChanged: (value) => repository.setChildStatus(
                item,
                value == true ? 'completed' : 'planned',
              ),
              secondary: Icon(
                item.entityType == 'roadmap_milestones'
                    ? Icons.flag_outlined
                    : Icons.fact_check_outlined,
              ),
              title: Text(item.title),
              subtitle: Text(
                item.entityType == 'roadmap_milestones'
                    ? 'Milestone'
                    : 'Checkpoint',
              ),
            ),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: TaskCard(task: task, compact: true),
            ),
        ],
      ),
    );
  }
}

class _LinkedWork extends ConsumerWidget {
  const _LinkedWork({
    required this.roadmapId,
    required this.phases,
    required this.tasks,
  });

  final String roadmapId;
  final List<LocalEntityRecord> phases;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLinkTask(
          context,
          ref,
          roadmapId,
          phases.isEmpty ? null : phases.first.id,
        ),
        icon: const Icon(Icons.add_link),
        label: const Text('Link task'),
      ),
      body: tasks.isEmpty
          ? const Center(child: Text('No tasks are linked to this roadmap yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => TaskCard(task: tasks[index]),
            ),
    );
  }
}

class _RoadmapForecast extends StatelessWidget {
  const _RoadmapForecast({
    required this.roadmap,
    required this.phaseCount,
    required this.milestoneCount,
    required this.checkpointCount,
    required this.tasks,
  });

  final LocalRoadmap roadmap;
  final int phaseCount;
  final int milestoneCount;
  final int checkpointCount;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context) {
    final original = roadmap.originalTargetDate;
    final forecast = roadmap.forecastTargetDate;
    final variance = original == null || forecast == null
        ? null
        : forecast.difference(original).inDays;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explainable forecast',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  forecast == null
                      ? 'Add target dates and recorded effort to calculate a forecast'
                      : variance == null || variance == 0
                      ? 'The current forecast remains ${DateFormat.yMMMMd().format(forecast)}'
                      : 'The expected completion is ${variance > 0 ? '$variance days later' : '${variance.abs()} days earlier'} than the original target',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill(
                      icon: Icons.event_outlined,
                      label: original == null
                          ? 'No original target'
                          : 'Original ${DateFormat.yMMMd().format(original)}',
                    ),
                    _Pill(
                      icon: Icons.auto_graph,
                      label: forecast == null
                          ? 'Forecast unavailable'
                          : 'Forecast ${DateFormat.yMMMd().format(forecast)}',
                    ),
                    _Pill(
                      icon: Icons.verified_outlined,
                      label: '${roadmap.forecastConfidence} confidence',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Evidence used',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$phaseCount phases · $milestoneCount milestones · '
                  '$checkpointCount checkpoints · ${tasks.length} linked tasks',
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatDuration(roadmap.completedEffortMs)} recorded effort '
                  'of ${_formatDuration(roadmap.requiredEffortMs ?? 0)} planned',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressExplanation extends StatelessWidget {
  const _ProgressExplanation({
    required this.phases,
    required this.milestones,
    required this.checkpoints,
    required this.tasks,
  });

  final List<LocalEntityRecord> phases;
  final List<LocalEntityRecord> milestones;
  final List<LocalEntityRecord> checkpoints;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Why this percentage?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _CountProgress(
              label: 'Phases',
              completed: phases
                  .where((item) => item.status == 'completed')
                  .length,
              total: phases.length,
            ),
            _CountProgress(
              label: 'Milestones',
              completed: milestones
                  .where((item) => item.status == 'completed')
                  .length,
              total: milestones.length,
            ),
            _CountProgress(
              label: 'Checkpoints',
              completed: checkpoints
                  .where((item) => item.status == 'completed')
                  .length,
              total: checkpoints.length,
            ),
            _CountProgress(
              label: 'Linked tasks',
              completed: tasks
                  .where((item) => item.status == 'completed')
                  .length,
              total: tasks.length,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountProgress extends StatelessWidget {
  const _CountProgress({
    required this.label,
    required this.completed,
    required this.total,
  });

  final String label;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final value = total == 0 ? 0.0 : completed / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(
              value: value,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 12),
          Text('$completed of $total'),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: effective.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: effective),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: effective)),
          ],
        ),
      ),
    );
  }
}

class _EmptyRoadmaps extends StatelessWidget {
  const _EmptyRoadmaps({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.route_outlined,
              size: 70,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Build your first roadmap',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Define the outcome, then add editable phases, milestones, checkpoints, and linked tasks',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create roadmap'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showRoadmapEditor(
  BuildContext context,
  WidgetRef ref, {
  LocalRoadmap? roadmap,
}) async {
  final title = TextEditingController(text: roadmap?.title);
  final description = TextEditingController(text: roadmap?.description);
  final outcome = TextEditingController(text: roadmap?.finalOutcome);
  var start = roadmap?.plannedStart ?? DateTime.now();
  var target =
      roadmap?.originalTargetDate ??
      DateTime.now().add(const Duration(days: 90));
  var effortHours = ((roadmap?.requiredEffortMs ?? 144000000) / 3600000)
      .round()
      .clamp(1, 10000);
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(roadmap == null ? 'Create roadmap' : 'Edit roadmap'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Roadmap title',
                    prefixIcon: Icon(Icons.route_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: outcome,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Final measurable outcome',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Start date',
                        value: start,
                        onChanged: (value) => setState(() => start = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateField(
                        label: 'Target date',
                        value: target,
                        onChanged: (value) => setState(() => target = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: '$effortHours',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Estimated total effort',
                    suffixText: 'hours',
                  ),
                  onChanged: (value) =>
                      effortHours = int.tryParse(value) ?? effortHours,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(roadmap == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    ),
  );
  if (saved == true && title.text.trim().isNotEmpty) {
    final draft = RoadmapDraft(
      title: title.text,
      description: description.text,
      finalOutcome: outcome.text,
      plannedStart: start,
      targetDate: target,
      requiredEffort: Duration(hours: effortHours),
    );
    if (roadmap == null) {
      final id = await ref.read(roadmapRepositoryProvider).createRoadmap(draft);
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RoadmapDetailScreen(roadmapId: id),
          ),
        );
      }
    } else {
      await ref
          .read(roadmapRepositoryProvider)
          .updateRoadmap(roadmap, draft: draft);
    }
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  title.dispose();
  description.dispose();
  outcome.dispose();
}

Future<void> _showPhaseEditor(
  BuildContext context,
  WidgetRef ref,
  String roadmapId,
  double position,
) async {
  final title = TextEditingController();
  final description = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add roadmap phase'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Phase title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add phase'),
        ),
      ],
    ),
  );
  if (result == true && title.text.trim().isNotEmpty) {
    await ref
        .read(roadmapRepositoryProvider)
        .addPhase(
          roadmapId: roadmapId,
          title: title.text,
          description: description.text,
          position: position,
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  title.dispose();
  description.dispose();
}

Future<void> _showMilestoneEditor(
  BuildContext context,
  WidgetRef ref,
  String roadmapId,
  String phaseId,
) async {
  final controller = TextEditingController();
  final result = await _simpleTitleDialog(
    context,
    title: 'Add milestone',
    label: 'Milestone title',
    controller: controller,
  );
  if (result) {
    await ref
        .read(roadmapRepositoryProvider)
        .addMilestone(
          roadmapId: roadmapId,
          phaseId: phaseId,
          title: controller.text,
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  controller.dispose();
}

Future<void> _showCheckpointEditor(
  BuildContext context,
  WidgetRef ref,
  String roadmapId,
  String phaseId,
) async {
  final controller = TextEditingController();
  final result = await _simpleTitleDialog(
    context,
    title: 'Add checkpoint',
    label: 'Checkpoint objective',
    controller: controller,
  );
  if (result) {
    await ref
        .read(roadmapRepositoryProvider)
        .addCheckpoint(
          roadmapId: roadmapId,
          phaseId: phaseId,
          title: controller.text,
          objective: controller.text,
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  controller.dispose();
}

Future<bool> _simpleTitleDialog(
  BuildContext context, {
  required String title,
  required String label,
  required TextEditingController controller,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim().isNotEmpty),
              child: const Text('Add'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _showLinkTask(
  BuildContext context,
  WidgetRef ref,
  String roadmapId,
  String? phaseId,
) async {
  final tasks = await ref.read(taskRepositoryProvider).watchTasks().first;
  if (!context.mounted) return;
  final selected = await showDialog<LocalTask>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Link an existing task'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: tasks.isEmpty
            ? const Center(child: Text('Create a task first'))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return ListTile(
                    leading: Icon(
                      task.roadmapId == roadmapId
                          ? Icons.link
                          : Icons.task_alt_outlined,
                    ),
                    title: Text(task.title),
                    subtitle: Text(
                      task.roadmapId == null
                          ? 'Not linked'
                          : task.roadmapId == roadmapId
                          ? 'Already linked to this roadmap'
                          : 'Linked to another roadmap',
                    ),
                    onTap: () => Navigator.pop(context, task),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (selected == null) return;
  await ref
      .read(taskRepositoryProvider)
      .updateRelationships(
        selected,
        roadmapId: roadmapId,
        roadmapPhaseId: phaseId,
      );
  await ref.read(roadmapRepositoryProvider).recalculateProgress(roadmapId);
  unawaited(ref.read(syncServiceProvider).drainOutbox());
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  LocalRoadmap roadmap,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete roadmap?'),
      content: const Text(
        'The roadmap is tombstoned for synchronization. Linked tasks remain available and can be reassigned.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete roadmap'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(roadmapRepositoryProvider).softDelete(roadmap);
    unawaited(ref.read(syncServiceProvider).drainOutbox());
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (date != null) onChanged(date);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(DateFormat.yMMMd().format(value)),
      ),
    );
  }
}

Color _riskColor(BuildContext context, String risk) => switch (risk) {
  'high' => Theme.of(context).colorScheme.error,
  'medium' => const Color(0xFFF28C28),
  _ => const Color(0xFF35A870),
};

String _formatDuration(int milliseconds) {
  final hours = milliseconds / 3600000;
  return hours < 1
      ? '${(milliseconds / 60000).round()} min'
      : '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)} h';
}
