import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';

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
        onPressed: () => _showProposalNotice(context),
        icon: const Icon(Icons.add_road),
        label: const Text('New roadmap'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.text('roadmaps'),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Long-term outcomes with explainable progress and forecasts.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showProposalNotice(context),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Ask AI for a proposal'),
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
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyRoadmaps(),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 520,
                    mainAxisExtent: 286,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _RoadmapCard(roadmap: items[index]),
                    childCount: items.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showProposalNotice(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: const Text('Roadmap proposals stay proposals'),
        content: const Text(
          'AI may propose phases, milestones, and estimated effort. '
          'Nothing changes your roadmap until you review and confirm it.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }
}

class _RoadmapCard extends StatelessWidget {
  const _RoadmapCard({required this.roadmap});

  final LocalRoadmap roadmap;

  @override
  Widget build(BuildContext context) {
    final percent = (roadmap.progress * 100).round();
    final forecast = roadmap.forecastTargetDate;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showExplanation(context),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: const Icon(Icons.route),
                  ),
                  const Spacer(),
                  _RiskPill(risk: roadmap.riskLevel),
                  const SizedBox(width: 4),
                  const Icon(Icons.more_horiz),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                roadmap.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                roadmap.description,
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
                    context.l10n.text('roadmap_progress'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  Text(
                    '$percent%',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: roadmap.progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(99),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.event_available_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    forecast == null
                        ? 'Forecast pending'
                        : 'Forecast ${MaterialLocalizations.of(context).formatMediumDate(forecast)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExplanation(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                roadmap.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Progress: ${(roadmap.progress * 100).round()}%',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'No percentage is inferred yet. Complete milestones, '
                'checkpoints, tasks, or accepted contribution rules to build '
                'an explainable breakdown.',
              ),
              const SizedBox(height: 18),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.flag_outlined),
                title: Text('Milestones'),
                trailing: Text('0 of 0'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.checklist),
                title: Text('Checkpoints'),
                trailing: Text('0 of 0'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.timer_outlined),
                title: Text('Accepted effort'),
                trailing: Text('0 min'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.risk});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final color = switch (risk) {
      'high' => Theme.of(context).colorScheme.error,
      'medium' => const Color(0xFFF28C28),
      _ => const Color(0xFF35A870),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '${risk.toUpperCase()} RISK',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _EmptyRoadmaps extends StatelessWidget {
  const _EmptyRoadmaps();

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
              size: 68,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.text('no_roadmaps'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.text('no_roadmaps_hint'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
