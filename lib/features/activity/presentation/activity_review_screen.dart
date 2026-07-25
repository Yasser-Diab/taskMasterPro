import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/activity_repository.dart';

final activityReviewProvider = StreamProvider<List<ActivityReviewEntry>>(
  (ref) => ref.watch(activityRepositoryProvider).watchReviewQueue(),
);

class ActivityReviewScreen extends ConsumerStatefulWidget {
  const ActivityReviewScreen({super.key});

  @override
  ConsumerState<ActivityReviewScreen> createState() =>
      _ActivityReviewScreenState();
}

class _ActivityReviewScreenState extends ConsumerState<ActivityReviewScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(activityReviewProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('activity'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Capture first. Classify second. Credit only under an approved rule.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('All')),
                        ButtonSegment(value: 'break', label: Text('Breaks')),
                        ButtonSegment(
                          value: 'cross_task',
                          label: Text('Cross-task'),
                        ),
                        ButtonSegment(value: 'idle', label: Text('Idle')),
                        ButtonSegment(value: 'unknown', label: Text('Unknown')),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (values) =>
                          setState(() => _filter = values.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          review.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(child: Text(error.toString())),
            ),
            data: (items) {
              final filtered = items.where((entry) {
                if (_filter == 'all') return true;
                return entry.review.reviewReason.contains(_filter) ||
                    entry.segment.idleState == _filter;
              }).toList();
              if (filtered.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyReview(),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _ReviewCard(entry: filtered[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.entry});

  final ActivityReviewEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source =
        entry.segment.processName ??
        entry.segment.domain ??
        entry.segment.pageTitle ??
        'Unknown activity';
    final seconds = entry.duration.inSeconds;
    final duration =
        '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  child: const Icon(Icons.manage_search),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text('$duration • ${entry.review.reviewReason}'),
                    ],
                  ),
                ),
                Text(
                  '${((entry.review.confidence ?? 0) * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (entry.review.suggestedTargetTitle != null) ...[
              const SizedBox(height: 16),
              Text(
                'Likely related to ${entry.review.suggestedTargetTitle}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => ref
                      .read(activityRepositoryProvider)
                      .resolve(entry, status: 'confirmed'),
                  icon: const Icon(Icons.add_task),
                  label: Text(context.l10n.text('credit_suggestion')),
                ),
                OutlinedButton(
                  onPressed: () => ref
                      .read(activityRepositoryProvider)
                      .resolve(entry, status: 'rejected'),
                  child: Text(context.l10n.text('mark_distraction')),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(activityRepositoryProvider)
                      .resolve(entry, status: 'ignored'),
                  child: Text(context.l10n.text('mark_unrelated')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 68,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.text('review_empty'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Unknown and unresolved activity remains stored until it can be reviewed.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
