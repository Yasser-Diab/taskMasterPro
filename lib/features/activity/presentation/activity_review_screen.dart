import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/database/app_database.dart';
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
                  onPressed: () => _showCreditDialog(context, ref),
                  icon: const Icon(Icons.add_task),
                  label: Text(context.l10n.text('credit_suggestion')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _resolve(
                    context,
                    ref,
                    const ActivityResolution(
                      status: 'confirmed',
                      classification: 'passive_useful_activity',
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Reading / useful idle'),
                ),
                OutlinedButton(
                  onPressed: () => _resolve(
                    context,
                    ref,
                    const ActivityResolution(
                      status: 'rejected',
                      classification: 'distraction',
                    ),
                  ),
                  child: Text(context.l10n.text('mark_distraction')),
                ),
                TextButton(
                  onPressed: () => _resolve(
                    context,
                    ref,
                    const ActivityResolution(
                      status: 'ignored',
                      classification: 'unrelated',
                    ),
                  ),
                  child: Text(context.l10n.text('mark_unrelated')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreditDialog(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(activityRepositoryProvider);
    final tasks = await repository.listTaskTargets();
    if (!context.mounted) return;
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a task before assigning activity credit.'),
        ),
      );
      return;
    }
    final resolution = await showDialog<ActivityResolution>(
      context: context,
      builder: (context) => _CreditActivityDialog(entry: entry, tasks: tasks),
    );
    if (resolution == null || !context.mounted) return;
    await _resolve(context, ref, resolution);
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    ActivityResolution resolution,
  ) async {
    try {
      await ref.read(activityRepositoryProvider).resolve(entry, resolution);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resolution.status == 'confirmed' && resolution.targetId != null
                ? 'Activity credited without duplicating the physical timeline.'
                : 'Activity review saved.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save this review: $error')),
      );
    }
  }
}

class _CreditActivityDialog extends StatefulWidget {
  const _CreditActivityDialog({required this.entry, required this.tasks});

  final ActivityReviewEntry entry;
  final List<LocalTask> tasks;

  @override
  State<_CreditActivityDialog> createState() => _CreditActivityDialogState();
}

class _CreditActivityDialogState extends State<_CreditActivityDialog> {
  late String _taskId = widget.tasks.first.id;
  String _classification = 'direct_task_work';
  String _contributionType = 'active_work_seconds';
  late final TextEditingController _minutesController = TextEditingController(
    text: (widget.entry.duration.inSeconds / 60).toStringAsFixed(1),
  );
  bool _rememberRule = false;

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Credit activity to a task'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _taskId,
                decoration: const InputDecoration(
                  labelText: 'Task that benefited',
                  prefixIcon: Icon(Icons.add_task),
                ),
                items: [
                  for (final task in widget.tasks)
                    DropdownMenuItem(value: task.id, child: Text(task.title)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _taskId = value);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _classification,
                decoration: const InputDecoration(
                  labelText: 'What kind of activity was this?',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'direct_task_work',
                    child: Text('Direct task work'),
                  ),
                  DropdownMenuItem(
                    value: 'supporting_work',
                    child: Text('Supporting work'),
                  ),
                  DropdownMenuItem(value: 'research', child: Text('Research')),
                  DropdownMenuItem(
                    value: 'learning',
                    child: Text('Learning / practice'),
                  ),
                  DropdownMenuItem(value: 'reading', child: Text('Reading')),
                  DropdownMenuItem(
                    value: 'communication',
                    child: Text('Communication'),
                  ),
                  DropdownMenuItem(
                    value: 'passive_useful_activity',
                    child: Text('Passive useful activity'),
                  ),
                  DropdownMenuItem(
                    value: 'off_device_activity',
                    child: Text('Work away from the device'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _classification = value;
                    _contributionType = switch (value) {
                      'learning' => 'practice_seconds',
                      'reading' || 'passive_useful_activity' => 'reading_time',
                      'research' => 'research_time',
                      _ => 'active_work_seconds',
                    };
                  });
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _minutesController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Credited minutes',
                  helperText: 'Cannot exceed the captured physical duration.',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _rememberRule,
                title: const Text('Remember this assignment'),
                subtitle: const Text(
                  'Stores your decision as feedback for future suggestions.',
                ),
                onChanged: (value) =>
                    setState(() => _rememberRule = value ?? false),
              ),
              const SizedBox(height: 6),
              const Text(
                'Task and roadmap credit are attribution layers. The daily '
                'physical timeline keeps this period only once.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final minutes = double.tryParse(_minutesController.text.trim());
            if (minutes == null || minutes <= 0) return;
            final requested = Duration(milliseconds: (minutes * 60000).round());
            final duration = requested > widget.entry.duration
                ? widget.entry.duration
                : requested;
            Navigator.pop(
              context,
              ActivityResolution(
                status: 'confirmed',
                classification: _classification,
                targetType: 'task_occurrence',
                targetId: _taskId,
                contributionType: _contributionType,
                creditedDuration: duration,
                rememberRule: _rememberRule,
              ),
            );
          },
          child: const Text('Credit activity'),
        ),
      ],
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
