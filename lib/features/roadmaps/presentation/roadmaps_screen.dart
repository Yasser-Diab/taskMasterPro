import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../reports/presentation/performance_report_screen.dart';
import '../../tasks/domain/task_occurrence_policy.dart';
import '../../tasks/presentation/task_card.dart';
import '../../tasks/presentation/task_editor_dialog.dart';
import '../data/roadmap_repository.dart';

final roadmapsProvider = StreamProvider<List<LocalRoadmap>>(
  (ref) => ref.watch(roadmapRepositoryProvider).watchRoadmaps(),
);

class RoadmapsScreen extends ConsumerWidget {
  const RoadmapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roadmaps = ref.watch(roadmapsProvider);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: compact
          ? FloatingActionButton(
              key: const ValueKey('mobile-roadmap-add'),
              tooltip: context.l10n.text('roadmap_new'),
              onPressed: () => _showRoadmapEditor(context, ref),
              child: const Icon(Icons.add_road),
            )
          : FloatingActionButton.extended(
              key: const ValueKey('desktop-roadmap-add'),
              onPressed: () => _showRoadmapEditor(context, ref),
              icon: const Icon(Icons.add_road),
              label: Text(context.l10n.text('roadmap_new')),
            ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              compact ? 16 : 24,
              compact ? 16 : 24,
              10,
            ),
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
                    context.l10n.text('roadmap_intro'),
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
            error: (_, _) => SliverFillRemaining(
              child: Center(
                child: Text(context.l10n.text('roadmap_load_failed')),
              ),
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
              Widget cardAt(int index) => _RoadmapCard(
                roadmap: items[index],
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RoadmapDetailScreen(roadmapId: items[index].id),
                  ),
                ),
                onEdit: () =>
                    _showRoadmapEditor(context, ref, roadmap: items[index]),
              );
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24,
                  10,
                  compact ? 16 : 24,
                  100,
                ),
                sliver: compact
                    ? SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) => cardAt(index),
                      )
                    : SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 520,
                              mainAxisExtent: 292,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) => cardAt(index),
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
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 20),
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
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.l10n.text('roadmap_edit')),
                      ),
                      PopupMenuItem(
                        value: 'pause',
                        child: Text(
                          roadmap.status == 'paused'
                              ? context.l10n.text('roadmap_resume')
                              : context.l10n.text('roadmap_pause'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(context.l10n.text('roadmap_archive')),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                roadmap.description.isEmpty
                    ? context.l10n.text('roadmap_no_description')
                    : roadmap.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Pill(
                          icon: Icons.flag_outlined,
                          label: target == null
                              ? context.l10n.text('roadmap_no_target')
                              : DateFormat.yMMMd(
                                  context.l10n.locale.toLanguageTag(),
                                ).format(target),
                        ),
                        _Pill(
                          icon: Icons.warning_amber_rounded,
                          label: context.l10n.format('roadmap_risk_value', {
                            'risk': context.l10n.text(
                              'roadmap_risk_${roadmap.riskLevel}',
                            ),
                          }),
                          color: color,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                  ),
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
                        final compact = MediaQuery.sizeOf(context).width < 600;
                        return DefaultTabController(
                          length: 5,
                          child: Scaffold(
                            appBar: AppBar(
                              title: compact
                                  ? Text(
                                      roadmap.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          roadmap.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          context.l10n.format(
                                            'roadmap_progress_risk',
                                            {
                                              'progress':
                                                  (roadmap.progress * 100)
                                                      .round(),
                                              'risk': context.l10n.text(
                                                'roadmap_risk_${roadmap.riskLevel}',
                                              ),
                                            },
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                              actions: [
                                PopupMenuButton<String>(
                                  tooltip: context.l10n.text(
                                    'roadmap_add_to_roadmap',
                                  ),
                                  icon: const Icon(Icons.add_circle_outline),
                                  onSelected: (action) async {
                                    switch (action) {
                                      case 'create_task':
                                        await TaskEditorDialog.show(
                                          context,
                                          initialRoadmapId: roadmap.id,
                                        );
                                      case 'link_tasks':
                                        await _showLinkTask(
                                          context,
                                          ref,
                                          roadmap.id,
                                          null,
                                        );
                                      case 'phase':
                                        await _showPhaseEditor(
                                          context,
                                          ref,
                                          roadmap.id,
                                          phases.length.toDouble(),
                                        );
                                      case 'milestone':
                                        await _showMilestoneEditor(
                                          context,
                                          ref,
                                          roadmap.id,
                                          null,
                                        );
                                      case 'checkpoint':
                                        await _showCheckpointEditor(
                                          context,
                                          ref,
                                          roadmap.id,
                                          null,
                                        );
                                      case 'complete_programming_plan':
                                        final result = await repository
                                            .populateProgrammingLearningPlan(
                                              roadmap.id,
                                            );
                                        await ref
                                            .read(syncServiceProvider)
                                            .drainOutbox();
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              context.l10n.format(
                                                'roadmap_programming_plan_completed',
                                                {
                                                  'phases': result.phases,
                                                  'milestones':
                                                      result.milestones,
                                                  'checkpoints':
                                                      result.checkpoints,
                                                  'tasks': result.tasks,
                                                },
                                              ),
                                            ),
                                          ),
                                        );
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'create_task',
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.add_task_outlined,
                                        ),
                                        title: Text(
                                          context.l10n.text(
                                            'roadmap_create_new_task',
                                          ),
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'link_tasks',
                                      child: ListTile(
                                        leading: const Icon(Icons.add_link),
                                        title: Text(
                                          context.l10n.text(
                                            'roadmap_link_existing_tasks',
                                          ),
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'phase',
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.layers_outlined,
                                        ),
                                        title: Text(
                                          context.l10n.text(
                                            'roadmap_add_phase',
                                          ),
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'milestone',
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.flag_outlined,
                                        ),
                                        title: Text(
                                          context.l10n.text(
                                            'roadmap_add_milestone',
                                          ),
                                        ),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'checkpoint',
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.fact_check_outlined,
                                        ),
                                        title: Text(
                                          context.l10n.text(
                                            'roadmap_add_checkpoint',
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (phases.length >= 9 &&
                                        '${roadmap.title} ${roadmap.description}'
                                            .toLowerCase()
                                            .contains('program'))
                                      PopupMenuItem(
                                        value: 'complete_programming_plan',
                                        child: ListTile(
                                          leading: const Icon(
                                            Icons.auto_awesome_outlined,
                                          ),
                                          title: Text(
                                            context.l10n.text(
                                              'roadmap_complete_programming_plan',
                                            ),
                                          ),
                                          subtitle: Text(
                                            context.l10n.text(
                                              'roadmap_complete_programming_plan_detail',
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                IconButton(
                                  tooltip: context.l10n.text('roadmap_analyze'),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PerformanceReportScreen(
                                        roadmapId: widget.roadmapId,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.analytics_outlined),
                                ),
                                IconButton(
                                  tooltip: context.l10n.text(
                                    'roadmap_recalculate',
                                  ),
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
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(
                                        context.l10n.text('roadmap_edit'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        context.l10n.text('roadmap_delete'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              bottom: TabBar(
                                isScrollable: true,
                                tabs: [
                                  Tab(
                                    icon: const Icon(Icons.dashboard_outlined),
                                    text: context.l10n.text('roadmap_overview'),
                                  ),
                                  Tab(
                                    icon: const Icon(
                                      Icons.view_timeline_outlined,
                                    ),
                                    text: context.l10n.text('roadmap_timeline'),
                                  ),
                                  Tab(
                                    icon: const Icon(Icons.layers_outlined),
                                    text: context.l10n.text('roadmap_phases'),
                                  ),
                                  Tab(
                                    icon: const Icon(Icons.task_alt_outlined),
                                    text: context.l10n.text(
                                      'roadmap_linked_work',
                                    ),
                                  ),
                                  Tab(
                                    icon: const Icon(Icons.insights_outlined),
                                    text: context.l10n.text('forecast'),
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

class _RoadmapOverview extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                      label: context.l10n.format('roadmap_phase_count', {
                        'count': phases.length,
                      }),
                    ),
                    _Pill(
                      icon: Icons.flag_outlined,
                      label: context.l10n.format('roadmap_milestone_progress', {
                        'completed': completedMilestones.length,
                        'total': milestones.length,
                      }),
                    ),
                    _Pill(
                      icon: Icons.fact_check_outlined,
                      label: context.l10n
                          .format('roadmap_checkpoint_progress', {
                            'completed': completedCheckpoints.length,
                            'total': checkpoints.length,
                          }),
                    ),
                    _Pill(
                      icon: Icons.task_alt_outlined,
                      label: context.l10n.format('roadmap_task_progress', {
                        'completed': completedTasks.length,
                        'total': tasks.length,
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _RoadmapHierarchySection(
          title: context.l10n.text('roadmap_milestones'),
          emptyText: context.l10n.text('roadmap_no_milestones'),
          icon: Icons.flag_outlined,
          items: milestones
              .where((item) => item.secondaryParentId == null)
              .toList(),
          onAdd: () => _showMilestoneEditor(context, ref, roadmap.id, null),
        ),
        const SizedBox(height: 16),
        _RoadmapHierarchySection(
          title: context.l10n.text('roadmap_checkpoints'),
          emptyText: context.l10n.text('roadmap_no_checkpoints'),
          icon: Icons.fact_check_outlined,
          items: checkpoints
              .where((item) => item.secondaryParentId == null)
              .toList(),
          onAdd: () => _showCheckpointEditor(context, ref, roadmap.id, null),
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

class _RoadmapHierarchySection extends StatelessWidget {
  const _RoadmapHierarchySection({
    required this.title,
    required this.emptyText,
    required this.icon,
    required this.items,
    required this.onAdd,
  });

  final String title;
  final String emptyText;
  final IconData icon;
  final List<LocalEntityRecord> items;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final heading = Row(
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                );
                final add = FilledButton.tonalIcon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.text('add')),
                );
                if (constraints.maxWidth < 380) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [heading, const SizedBox(height: 12), add],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 12),
                    add,
                  ],
                );
              },
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(emptyText),
              )
            else
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.status == 'completed' ? Icons.check_circle : icon,
                    color: item.status == 'completed'
                        ? const Color(0xFF35A870)
                        : null,
                  ),
                  title: Text(item.title),
                  subtitle: Text(_hierarchyStatusLabel(context, item)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (context) => SafeArea(
                      child: ListTile(
                        leading: Icon(icon),
                        title: Text(item.title),
                        subtitle: Text(_hierarchyStatusLabel(context, item)),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

String _hierarchyStatusLabel(BuildContext context, LocalEntityRecord item) {
  final status = switch (item.status) {
    'planned' => 'not_started',
    'active' => 'in_progress',
    final value => value,
  };
  final prefix = item.entityType == 'roadmap_checkpoints'
      ? 'roadmap_checkpoint_status_'
      : 'roadmap_milestone_status_';
  return context.l10n.text('$prefix$status');
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
      return Center(child: Text(context.l10n.text('roadmap_timeline_empty')));
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
                      child: Text(
                        '${index + 1}',
                      ), // localization-audit: allow — localized numeral rendering
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
                              label: context.l10n.format(
                                'roadmap_milestone_count',
                                {'count': phaseMilestones.length},
                              ),
                            ),
                            _Pill(
                              icon: Icons.fact_check_outlined,
                              label: context.l10n.format(
                                'roadmap_checkpoint_count',
                                {'count': phaseCheckpoints.length},
                              ),
                            ),
                            _Pill(
                              icon: Icons.task_alt_outlined,
                              label: context.l10n.format('roadmap_task_count', {
                                'count': phaseTasks.length,
                              }),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final help = Text(context.l10n.text('roadmap_reorder_help'));
              final add = FilledButton.icon(
                onPressed: () => _showPhaseEditor(
                  context,
                  ref,
                  roadmapId,
                  phases.length.toDouble(),
                ),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.text('roadmap_add_phase')),
              );
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [help, const SizedBox(height: 12), add],
                );
              }
              return Row(
                children: [
                  Expanded(child: help),
                  const SizedBox(width: 12),
                  add,
                ],
              );
            },
          ),
        ),
        Expanded(
          child: phases.isEmpty
              ? Center(child: Text(context.l10n.text('roadmap_no_phases')))
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
          context.l10n.format('roadmap_phase_summary', {
            'milestones': milestones.length,
            'checkpoints': checkpoints.length,
            'tasks': tasks.length,
          }),
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
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: PopupMenuButton<String>(
                onSelected: (action) async {
                  switch (action) {
                    case 'create_task':
                      await TaskEditorDialog.show(
                        context,
                        initialRoadmapId: roadmapId,
                        initialRoadmapPhaseId: phase.id,
                      );
                    case 'link_tasks':
                      await _showLinkTask(context, ref, roadmapId, phase.id);
                    case 'milestone':
                      await _showMilestoneEditor(
                        context,
                        ref,
                        roadmapId,
                        phase.id,
                      );
                    case 'checkpoint':
                      await _showCheckpointEditor(
                        context,
                        ref,
                        roadmapId,
                        phase.id,
                      );
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'create_task',
                    child: ListTile(
                      leading: const Icon(Icons.add_task_outlined),
                      title: Text(context.l10n.text('roadmap_create_new_task')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'link_tasks',
                    child: ListTile(
                      leading: const Icon(Icons.add_link),
                      title: Text(
                        context.l10n.text('roadmap_link_existing_tasks'),
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'milestone',
                    child: ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(context.l10n.text('roadmap_add_milestone')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'checkpoint',
                    child: ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(context.l10n.text('roadmap_add_checkpoint')),
                    ),
                  ),
                ],
                child: IgnorePointer(
                  child: FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.text('roadmap_add_to_this_phase')),
                  ),
                ),
              ),
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
                    ? context.l10n.text('roadmap_milestone')
                    : context.l10n.text('roadmap_checkpoint'),
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
    final roadmapLevelTasks = tasks
        .where((task) => task.roadmapPhaseId == null)
        .toList();
    final phaseTasks = tasks
        .where((task) => task.roadmapPhaseId != null)
        .toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.text('roadmap_no_linked_tasks')),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => TaskEditorDialog.show(
                      context,
                      initialRoadmapId: roadmapId,
                    ),
                    icon: const Icon(Icons.add_task_outlined),
                    label: Text(context.l10n.text('roadmap_create_new_task')),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _showLinkTask(context, ref, roadmapId, null),
                    icon: const Icon(Icons.add_link),
                    label: Text(
                      context.l10n.text('roadmap_link_existing_tasks'),
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => TaskEditorDialog.show(
                        context,
                        initialRoadmapId: roadmapId,
                      ),
                      icon: const Icon(Icons.add_task_outlined),
                      label: Text(context.l10n.text('roadmap_create_new_task')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showLinkTask(context, ref, roadmapId, null),
                      icon: const Icon(Icons.add_link),
                      label: Text(
                        context.l10n.text('roadmap_link_existing_tasks'),
                      ),
                    ),
                  ],
                ),
                if (roadmapLevelTasks.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    context.l10n.text('roadmap_level_tasks'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final task in roadmapLevelTasks) ...[
                    TaskCard(task: task),
                    const SizedBox(height: 10),
                  ],
                ],
                if (phaseTasks.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    context.l10n.text('roadmap_phase_tasks'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final task in phaseTasks) ...[
                    TaskCard(task: task),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }
}

class StoredRoadmapForecastRange {
  const StoredRoadmapForecastRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// Builds a cautious display range around the persisted forecast date. The UI
/// never recomputes velocity or advertises a precise day delta; it only widens
/// the stored estimate according to its persisted evidence confidence.
StoredRoadmapForecastRange? storedRoadmapForecastRange(LocalRoadmap roadmap) {
  final forecast = roadmap.forecastTargetDate;
  if (forecast == null || roadmap.forecastConfidence == 'insufficient') {
    return null;
  }
  final radius = switch (roadmap.forecastConfidence) {
    'high' => 7,
    'medium' => 14,
    _ => 28,
  };
  return StoredRoadmapForecastRange(
    start: forecast.subtract(Duration(days: radius)),
    end: forecast.add(Duration(days: radius)),
  );
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
    final insufficientEvidence = roadmap.forecastConfidence == 'insufficient';
    final range = storedRoadmapForecastRange(roadmap);
    final completedOccurrences = tasks
        .where(TaskOccurrencePolicy.isCompletedOccurrence)
        .length;
    final earlyEstimate =
        !insufficientEvidence &&
        (roadmap.forecastConfidence == 'low' || completedOccurrences < 5);
    final requiredEffortMs = effectiveRoadmapRequiredEffortMs(roadmap, tasks);
    final rangeStart = range == null
        ? null
        : DateFormat.yMMMd(
            context.l10n.locale.toLanguageTag(),
          ).format(range.start);
    final rangeEnd = range == null
        ? null
        : DateFormat.yMMMd(
            context.l10n.locale.toLanguageTag(),
          ).format(range.end);
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
                  context.l10n.text('roadmap_explainable_forecast'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  insufficientEvidence
                      ? context.l10n.text('roadmap_forecast_insufficient')
                      : forecast == null
                      ? context.l10n.text('roadmap_forecast_missing')
                      : earlyEstimate
                      ? context.l10n.format('roadmap_forecast_early_estimate', {
                          'start': rangeStart!,
                          'end': rangeEnd!,
                        })
                      : context.l10n.format('roadmap_forecast_range', {
                          'start': rangeStart!,
                          'end': rangeEnd!,
                        }),
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
                          ? context.l10n.text('roadmap_no_original_target')
                          : context.l10n.format('roadmap_original_target', {
                              'date': DateFormat.yMMMd(
                                context.l10n.locale.toLanguageTag(),
                              ).format(original),
                            }),
                    ),
                    _Pill(
                      icon: Icons.auto_graph,
                      label: forecast == null
                          ? context.l10n.text('roadmap_forecast_unavailable')
                          : context.l10n.format('roadmap_forecast_date', {
                              'date': DateFormat.yMMMd(
                                context.l10n.locale.toLanguageTag(),
                              ).format(forecast),
                            }),
                    ),
                    _Pill(
                      icon: Icons.verified_outlined,
                      label: insufficientEvidence
                          ? context.l10n.text('roadmap_confidence_insufficient')
                          : context.l10n.format('roadmap_forecast_confidence', {
                              'confidence': context.l10n.text(
                                'roadmap_confidence_${roadmap.forecastConfidence}',
                              ),
                            }),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  context.l10n.text('roadmap_evidence_used'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.format('roadmap_evidence_summary', {
                    'phases': phaseCount,
                    'milestones': milestoneCount,
                    'checkpoints': checkpointCount,
                    'tasks': tasks.length,
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  roadmapEffortSummary(
                    context.l10n,
                    recordedEffortMs: roadmap.completedEffortMs,
                    requiredEffortMs: requiredEffortMs,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String roadmapEffortSummary(
  AppLocalizations l10n, {
  required int recordedEffortMs,
  required int? requiredEffortMs,
}) {
  final recorded = l10n.duration(
    Duration(milliseconds: recordedEffortMs.clamp(0, 1 << 62)),
  );
  if (requiredEffortMs == null || requiredEffortMs <= 0) {
    return l10n.format('roadmap_effort_summary_unavailable', {
      'recorded': recorded,
    });
  }
  return l10n.format('roadmap_effort_summary', {
    'recorded': recorded,
    'planned': l10n.duration(
      Duration(milliseconds: requiredEffortMs.clamp(0, 1 << 62)),
    ),
  });
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
              context.l10n.text('roadmap_progress_explanation'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _CountProgress(
              label: context.l10n.text('roadmap_phases'),
              completed: phases
                  .where((item) => item.status == 'completed')
                  .length,
              total: phases.length,
            ),
            _CountProgress(
              label: context.l10n.text('roadmap_milestones'),
              completed: milestones
                  .where((item) => item.status == 'completed')
                  .length,
              total: milestones.length,
            ),
            _CountProgress(
              label: context.l10n.text('roadmap_checkpoints'),
              completed: checkpoints
                  .where((item) => item.status == 'completed')
                  .length,
              total: checkpoints.length,
            ),
            _CountProgress(
              label: context.l10n.text('roadmap_linked_tasks'),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = context.l10n.format('roadmap_count_of', {
            'completed': completed,
            'total': total,
          });
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label)),
                    const SizedBox(width: 12),
                    Text(count),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: value,
                  borderRadius: BorderRadius.circular(99),
                ),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 110, child: Text(label)),
              Expanded(
                child: LinearProgressIndicator(
                  value: value,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 12),
              Text(count),
            ],
          );
        },
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
            Flexible(
              child: Text(
                label,
                softWrap: true,
                style: TextStyle(color: effective),
              ),
            ),
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
            Text(
              context.l10n.text('roadmap_first_heading'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.text('roadmap_first_description'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.text('roadmap_create')),
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
        title: Text(
          context.l10n.text(
            roadmap == null ? 'roadmap_create' : 'roadmap_edit',
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('roadmap_title'),
                    prefixIcon: const Icon(Icons.route_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('description'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: outcome,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('roadmap_final_outcome'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: context.l10n.text('roadmap_start_date'),
                        value: start,
                        onChanged: (value) => setState(() => start = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateField(
                        label: context.l10n.text('roadmap_target_date'),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.text('roadmap_estimated_effort'),
                    suffixText: context.l10n.text('unit_hours'),
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
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.text(roadmap == null ? 'roadmap_create' : 'save'),
            ),
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
      title: Text(context.l10n.text('roadmap_add_phase')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.text('roadmap_phase_title'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.l10n.text('description'),
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
          child: Text(context.l10n.text('roadmap_add_phase')),
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
  String? phaseId,
) async {
  final title = TextEditingController();
  final description = TextEditingController();
  final notes = TextEditingController();
  DateTime? targetDate;
  var status = 'not_started';
  var completionRule = 'manual';
  final result =
      await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(context.l10n.text('roadmap_add_milestone')),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('roadmap_milestone_title'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('description'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        targetDate == null
                            ? context.l10n.text('roadmap_target_date')
                            : DateFormat.yMMMd(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).format(targetDate!),
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                          initialDate: targetDate ?? DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => targetDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('status'),
                      ),
                      items: [
                        for (final value in const [
                          'not_started',
                          'in_progress',
                          'at_risk',
                          'completed',
                          'missed',
                          'paused',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(
                              context.l10n.text(
                                'roadmap_milestone_status_$value',
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => status = value ?? status),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: completionRule,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('roadmap_completion_rule'),
                      ),
                      items: [
                        for (final value in const [
                          'manual',
                          'all_checkpoints',
                          'all_required_tasks',
                          'progress_threshold',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(
                              context.l10n.text(
                                'roadmap_milestone_rule_$value',
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) => setDialogState(
                        () => completionRule = value ?? completionRule,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('notes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, title.text.trim().isNotEmpty),
                child: Text(context.l10n.text('add')),
              ),
            ],
          ),
        ),
      ) ??
      false;
  if (result) {
    await ref
        .read(roadmapRepositoryProvider)
        .addMilestone(
          roadmapId: roadmapId,
          phaseId: phaseId,
          title: title.text,
          description: description.text,
          targetDate: targetDate,
          status: status,
          completionRule: completionRule,
          notes: notes.text,
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  title.dispose();
  description.dispose();
  notes.dispose();
}

Future<void> _showCheckpointEditor(
  BuildContext context,
  WidgetRef ref,
  String roadmapId,
  String? phaseId,
) async {
  final milestones =
      (await ref
              .read(roadmapRepositoryProvider)
              .watchMilestones(roadmapId)
              .first)
          .where(
            (milestone) =>
                milestone.secondaryParentId == null ||
                milestone.secondaryParentId == phaseId,
          )
          .toList();
  if (!context.mounted) return;
  final title = TextEditingController();
  final objective = TextEditingController();
  final notes = TextEditingController();
  DateTime? targetDate;
  String? milestoneId;
  var status = 'not_started';
  var required = true;
  var completionRule = 'manual';
  final result =
      await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(context.l10n.text('roadmap_add_checkpoint')),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.text(
                          'roadmap_checkpoint_title',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: objective,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.l10n.text(
                          'roadmap_checkpoint_objective',
                        ),
                      ),
                    ),
                    if (milestones.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: milestoneId,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('roadmap_milestone'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              context.l10n.text('roadmap_no_milestone'),
                            ),
                          ),
                          for (final milestone in milestones)
                            DropdownMenuItem(
                              value: milestone.id,
                              child: Text(milestone.title),
                            ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => milestoneId = value),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        targetDate == null
                            ? context.l10n.text('roadmap_target_date')
                            : DateFormat.yMMMd(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).format(targetDate!),
                      ),
                      trailing: const Icon(Icons.edit_calendar_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 365),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                          initialDate: targetDate ?? DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => targetDate = picked);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: required,
                      title: Text(
                        context.l10n.text('roadmap_checkpoint_required'),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => required = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('status'),
                      ),
                      items: [
                        for (final value in const [
                          'not_started',
                          'in_progress',
                          'ready_for_review',
                          'completed',
                          'blocked',
                          'missed',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(
                              context.l10n.text(
                                'roadmap_checkpoint_status_$value',
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => status = value ?? status),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: completionRule,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('roadmap_completion_rule'),
                      ),
                      items: [
                        for (final value in const [
                          'manual',
                          'linked_tasks',
                          'user_review',
                          'approved_rule',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(
                              context.l10n.text(
                                'roadmap_checkpoint_rule_$value',
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) => setDialogState(
                        () => completionRule = value ?? completionRule,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('notes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, title.text.trim().isNotEmpty),
                child: Text(context.l10n.text('add')),
              ),
            ],
          ),
        ),
      ) ??
      false;
  if (result) {
    await ref
        .read(roadmapRepositoryProvider)
        .addCheckpoint(
          roadmapId: roadmapId,
          phaseId: phaseId,
          milestoneId: milestoneId,
          title: title.text,
          objective: objective.text,
          targetDate: targetDate,
          required: required,
          status: status,
          completionRule: completionRule,
          notes: notes.text,
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
  title.dispose();
  objective.dispose();
  notes.dispose();
}

Future<void> _showLinkTask(
  BuildContext context,
  WidgetRef ref,
  String roadmapId,
  String? phaseId,
) async {
  final tasks = await ref.read(taskRepositoryProvider).watchTasks().first;
  if (!context.mounted) return;
  final search = TextEditingController();
  final selectedIds = <String>{};
  var statusFilter = 'all';
  final selected = await showDialog<Set<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final query = search.text.trim().toLowerCase();
        final filtered = tasks.where((task) {
          final matchesSearch =
              query.isEmpty || task.title.toLowerCase().contains(query);
          final matchesStatus =
              statusFilter == 'all' || task.status == statusFilter;
          return matchesSearch && matchesStatus;
        }).toList();
        return AlertDialog(
          title: Text(context.l10n.text('roadmap_link_existing_tasks')),
          content: SizedBox(
            width: 620,
            height: 540,
            child: Column(
              children: [
                TextField(
                  controller: search,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('roadmap_search_tasks'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: statusFilter,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('roadmap_filter_status'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(context.l10n.text('filter_all')),
                    ),
                    for (final status in const [
                      'ready',
                      'in_progress',
                      'paused',
                      'completed',
                      'overdue',
                    ])
                      DropdownMenuItem(
                        value: status,
                        child: Text(context.l10n.taskStatus(status)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => statusFilter = value ?? 'all'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.l10n.format('roadmap_selected_task_count', {
                      'count': selectedIds.length,
                    }),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: tasks.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.text('roadmap_create_task_first'),
                          ),
                        )
                      : filtered.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.text('roadmap_no_matching_tasks'),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final task = filtered[index];
                            final alreadyHere =
                                task.roadmapId == roadmapId &&
                                task.roadmapPhaseId == phaseId;
                            final selected = selectedIds.contains(task.id);
                            final relationshipLabel = alreadyHere
                                ? context.l10n.text(
                                    phaseId == null
                                        ? 'roadmap_already_linked'
                                        : 'roadmap_already_linked_phase',
                                  )
                                : task.roadmapId == roadmapId
                                ? context.l10n.text(
                                    'roadmap_linked_another_phase',
                                  )
                                : task.roadmapId == null
                                ? context.l10n.text('roadmap_not_linked')
                                : context.l10n.text('roadmap_linked_other');
                            return CheckboxListTile(
                              value: alreadyHere || selected,
                              onChanged: alreadyHere
                                  ? null
                                  : (value) => setDialogState(() {
                                      if (value == true) {
                                        selectedIds.add(task.id);
                                      } else {
                                        selectedIds.remove(task.id);
                                      }
                                    }),
                              secondary: Icon(
                                alreadyHere
                                    ? Icons.link
                                    : Icons.task_alt_outlined,
                              ),
                              title: Text(task.title),
                              subtitle: Text(relationshipLabel),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton.icon(
              onPressed: selectedIds.isEmpty
                  ? null
                  : () => Navigator.pop(context, {...selectedIds}),
              icon: const Icon(Icons.add_link),
              label: Text(
                context.l10n.format('roadmap_link_selected_tasks', {
                  'count': selectedIds.length,
                }),
              ),
            ),
          ],
        );
      },
    ),
  );
  search.dispose();
  if (selected == null || selected.isEmpty) return;
  if (!context.mounted) return;
  final selectedTasks = tasks
      .where((task) => selected.contains(task.id))
      .toList();
  final movingExisting = selectedTasks.any(
    (task) =>
        task.roadmapId != null &&
        (task.roadmapId != roadmapId || task.roadmapPhaseId != phaseId),
  );
  if (movingExisting) {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.text('roadmap_move_tasks_title')),
            content: Text(context.l10n.text('roadmap_move_tasks_description')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.text('roadmap_move_selected_tasks')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
  }
  for (final task in selectedTasks) {
    await ref
        .read(taskRepositoryProvider)
        .updateRelationships(
          task,
          roadmapId: roadmapId,
          roadmapPhaseId: phaseId,
        );
    await ref
        .read(roadmapRepositoryProvider)
        .upsertTaskLink(
          roadmapId: roadmapId,
          taskId: task.id,
          phaseId: phaseId,
        );
  }
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
      title: Text(context.l10n.text('roadmap_delete_title')),
      content: Text(context.l10n.text('roadmap_delete_description')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.text('roadmap_delete')),
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
        child: Text(
          DateFormat.yMMMd(context.l10n.locale.toLanguageTag()).format(value),
        ),
      ),
    );
  }
}

Color _riskColor(BuildContext context, String risk) => switch (risk) {
  'high' => Theme.of(context).colorScheme.error,
  'medium' => const Color(0xFFF28C28),
  _ => const Color(0xFF35A870),
};
