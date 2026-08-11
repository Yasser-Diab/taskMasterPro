import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/activity_aggregation_service.dart';
import '../data/activity_repository.dart';

final activityReviewProvider = StreamProvider<List<ActivityReviewEntry>>(
  (ref) => ref.watch(activityRepositoryProvider).watchReviewQueue(),
);

class ActivityReviewScreen extends ConsumerStatefulWidget {
  const ActivityReviewScreen({
    this.onBack,
    this.initialFilter = 'all',
    super.key,
  });

  final VoidCallback? onBack;
  final String initialFilter;

  @override
  ConsumerState<ActivityReviewScreen> createState() =>
      _ActivityReviewScreenState();
}

class _ActivityReviewScreenState extends ConsumerState<ActivityReviewScreen> {
  DateTime? _selectedDate;
  late String _filter;
  String? _aggregationSignature;
  Future<ActivityAggregation>? _aggregationFuture;
  final Map<String, int> _visiblePeriods = {};

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    final copy = _ActivityCopy.of(context);
    final location = _location(settings?.timeZone);
    final now = tz.TZDateTime.now(location);
    final selected = _selectedDate ?? DateTime(now.year, now.month, now.day);
    final today = DateTime(now.year, now.month, now.day);
    final isToday = _sameDay(selected, today);
    final start = tz.TZDateTime(
      location,
      selected.year,
      selected.month,
      selected.day,
    );
    final nextStart = tz.TZDateTime(
      location,
      selected.year,
      selected.month,
      selected.day + 1,
    );
    final rangeEndUtc = isToday ? now.toUtc() : nextStart.toUtc();
    final database = ref.watch(databaseProvider);
    final segmentQuery = database.select(database.localActivitySegments)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.endedAt.isBiggerThanValue(start.toUtc()) &
            row.startedAt.isSmallerThanValue(rangeEndUtc),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<List<LocalActivitySegment>>(
        stream: segmentQuery.watch(),
        builder: (context, segmentSnapshot) {
          if (segmentSnapshot.hasError) {
            return _ErrorState(message: copy.couldNotLoad);
          }
          if (!segmentSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final segments = segmentSnapshot.data!;
          if (segments.isEmpty) {
            return _ActivityPage(
              copy: copy,
              selected: selected,
              today: today,
              isToday: isToday,
              location: location,
              filter: _filter,
              onFilterChanged: (value) => setState(() => _filter = value),
              onPrevious: () => _moveDay(selected, -1),
              onNext: isToday ? null : () => _moveDay(selected, 1),
              onToday: () => setState(() => _selectedDate = today),
              onPickDate: () => _pickDate(selected, today),
              onBack: widget.onBack,
              child: const _NoActivity(),
            );
          }
          final ids = segments.map((segment) => segment.id).toList();
          final attributionQuery = database.select(database.localAttributions)
            ..where(
              (row) => row.deletedAt.isNull() & row.activitySegmentId.isIn(ids),
            );
          return StreamBuilder<List<LocalAttribution>>(
            stream: attributionQuery.watch(),
            builder: (context, attributionSnapshot) {
              if (!attributionSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final attributions = attributionSnapshot.data!;
              final future = _aggregationFor(
                segments,
                attributions,
                start.toUtc(),
                rangeEndUtc,
              );
              return FutureBuilder<ActivityAggregation>(
                future: future,
                builder: (context, aggregationSnapshot) {
                  final aggregation = aggregationSnapshot.data;
                  return _ActivityPage(
                    copy: copy,
                    selected: selected,
                    today: today,
                    isToday: isToday,
                    location: location,
                    filter: _filter,
                    onFilterChanged: (value) => setState(() => _filter = value),
                    onPrevious: () => _moveDay(selected, -1),
                    onNext: isToday ? null : () => _moveDay(selected, 1),
                    onToday: () => setState(() => _selectedDate = today),
                    onPickDate: () => _pickDate(selected, today),
                    onBack: widget.onBack,
                    summary: aggregation,
                    child: aggregation == null
                        ? const Center(child: CircularProgressIndicator())
                        : _buildGroups(
                            context,
                            copy,
                            aggregation,
                            location,
                            isToday,
                            hideConfirmedSystem:
                                settings?.hideConfirmedSystemActivity ?? true,
                            showPossibleSystem:
                                settings?.showPossibleSystemActivity ?? true,
                          ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGroups(
    BuildContext context,
    _ActivityCopy copy,
    ActivityAggregation aggregation,
    tz.Location location,
    bool isToday, {
    required bool hideConfirmedSystem,
    required bool showPossibleSystem,
  }) {
    final groups = aggregation.groups.where((group) {
      if (_filter == 'hidden_system') {
        return group.classification == 'system_activity';
      }
      if (hideConfirmedSystem && group.classification == 'system_activity') {
        return false;
      }
      if (!showPossibleSystem &&
          group.classification == 'possible_system_activity') {
        return false;
      }
      return switch (_filter) {
        'related' => !const {
          'unclassified',
          'unknown',
          'requires_review',
          'distraction',
          'unrelated',
          'generally_unrelated',
          'possible_system_activity',
          'system_activity',
        }.contains(group.classification),
        'breaks' => group.containsBreak,
        'cross_task' => group.containsCrossTask,
        'idle' => group.idleMs > 0 || group.uncertainMs > 0,
        'needs_review' => const {
          'unclassified',
          'unknown',
          'requires_review',
          'distraction',
          'unrelated',
          'generally_unrelated',
          'possible_system_activity',
        }.contains(group.classification),
        _ => true,
      };
    }).toList();
    if (groups.isEmpty) {
      return _EmptyReview(copy: copy);
    }
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            copy.groupedMessage,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final group in groups) ...[
          _GroupedActivityCard(
            group: group,
            copy: copy,
            location: location,
            totalLabel: isToday ? copy.totalToday : copy.totalRecorded,
            visiblePeriods: _visiblePeriods[group.key] ?? 25,
            onLoadMore:
                group.periods.length > (_visiblePeriods[group.key] ?? 25)
                ? () {
                    setState(() {
                      _visiblePeriods[group.key] =
                          (_visiblePeriods[group.key] ?? 25) + 25;
                    });
                  }
                : null,
            onReviewGroup: () => _reviewGroup(group),
            onReviewPeriod: (period) => _reviewPeriod(period),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<ActivityAggregation> _aggregationFor(
    List<LocalActivitySegment> segments,
    List<LocalAttribution> attributions,
    DateTime start,
    DateTime end,
  ) {
    final latestSegment = segments.fold<int>(
      0,
      (value, item) => item.updatedAt.microsecondsSinceEpoch > value
          ? item.updatedAt.microsecondsSinceEpoch
          : value,
    );
    final latestAttribution = attributions.fold<int>(
      0,
      (value, item) => item.updatedAt.microsecondsSinceEpoch > value
          ? item.updatedAt.microsecondsSinceEpoch
          : value,
    );
    final signature =
        '${start.microsecondsSinceEpoch}:${end.microsecondsSinceEpoch}:'
        '${segments.length}:$latestSegment:${attributions.length}:'
        '$latestAttribution';
    if (_aggregationSignature != signature || _aggregationFuture == null) {
      _aggregationSignature = signature;
      _aggregationFuture = ActivityAggregationService().aggregate(
        segments: segments,
        attributions: attributions,
        rangeStartUtc: start,
        rangeEndUtc: end,
      );
    }
    return _aggregationFuture!;
  }

  Future<void> _reviewGroup(ActivityGroupSummary group) async {
    final choice = await _showClassificationSheet(group.name);
    if (choice == null || !mounted) return;
    final applyFuture = await _chooseApplicationScope(
      allowRemember:
          choice.targetId != null ||
          const {
            'system_activity',
            'user_application',
            'generally_unrelated',
            'unrelated',
          }.contains(choice.classification),
    );
    if (applyFuture == null || !mounted) return;
    final ids = group.periods.map((period) => period.segmentId).toSet();
    await _applyResolution(ids, choice.copyWith(rememberRule: applyFuture));
  }

  Future<void> _reviewPeriod(ActivityPeriodSummary period) async {
    final choice = await _showClassificationSheet(period.detail);
    if (choice == null || !mounted) return;
    final applyFuture = await _chooseApplicationScope(
      allowRemember:
          choice.targetId != null ||
          const {
            'system_activity',
            'user_application',
            'generally_unrelated',
            'unrelated',
          }.contains(choice.classification),
    );
    if (applyFuture == null || !mounted) return;
    await _applyResolution({
      period.segmentId,
    }, choice.copyWith(rememberRule: applyFuture));
  }

  Future<ActivityResolution?> _showClassificationSheet(String title) {
    final copy = _ActivityCopy.of(context);
    return showModalBottomSheet<ActivityResolution>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: Text(copy.assignAnotherTask),
              onTap: () async {
                final tasks = await ref
                    .read(activityRepositoryProvider)
                    .listTaskTargets();
                if (!context.mounted) return;
                final taskId = await showDialog<String>(
                  context: context,
                  builder: (context) =>
                      _TaskPickerDialog(tasks: tasks, copy: copy),
                );
                if (taskId != null && context.mounted) {
                  Navigator.pop(
                    context,
                    ActivityResolution(
                      status: 'confirmed',
                      classification: 'direct_task_work',
                      targetType: 'task_occurrence',
                      targetId: taskId,
                      contributionType: 'active_work_seconds',
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(copy.usefulReading),
              onTap: () => Navigator.pop(
                context,
                const ActivityResolution(
                  status: 'confirmed',
                  classification: 'passive_useful_activity',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: Text(copy.supportingWork),
              onTap: () => Navigator.pop(
                context,
                const ActivityResolution(
                  status: 'confirmed',
                  classification: 'supporting_work',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text(copy.markDistraction),
              onTap: () => Navigator.pop(
                context,
                const ActivityResolution(
                  status: 'rejected',
                  classification: 'distraction',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link_off),
              title: Text(copy.notRelated),
              onTap: () => Navigator.pop(
                context,
                const ActivityResolution(
                  status: 'ignored',
                  classification: 'unrelated',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.do_not_disturb_alt_outlined),
              title: Text(copy.generallyUnrelated),
              onTap: () => Navigator.pop(
                context,
                const ActivityResolution(
                  status: 'rejected',
                  classification: 'generally_unrelated',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_suggest_outlined),
              title: Text(copy.treatAsSystem),
              onTap: () => Navigator.pop(
                context,
                const ActivityResolution(
                  status: 'ignored',
                  classification: 'system_activity',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.apps_outlined),
              title: Text(copy.thisIsUserApplication),
              onTap: () => Navigator.pop(
                context,
                const ActivityResolution(
                  status: 'confirmed',
                  classification: 'user_application',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _chooseApplicationScope({required bool allowRemember}) {
    final copy = _ActivityCopy.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.applyQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(copy.selectedOnly),
          ),
          if (allowRemember)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy.rememberFuture),
            ),
        ],
      ),
    );
  }

  Future<void> _applyResolution(
    Set<String> segmentIds,
    ActivityResolution resolution,
  ) async {
    final repository = ref.read(activityRepositoryProvider);
    try {
      for (final segmentId in segmentIds) {
        final entry = await repository.reviewEntryForSegment(segmentId);
        if (entry != null) await repository.resolve(entry, resolution);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_ActivityCopy.of(context).reviewSaved)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_ActivityCopy.of(context).couldNotSave)),
      );
    }
  }

  void _moveDay(DateTime selected, int days) {
    setState(() {
      _selectedDate = DateTime(
        selected.year,
        selected.month,
        selected.day + days,
      );
      _aggregationSignature = null;
    });
  }

  Future<void> _pickDate(DateTime selected, DateTime today) async {
    final value = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (value != null) {
      setState(() {
        _selectedDate = value;
        _aggregationSignature = null;
      });
    }
  }

  static tz.Location _location(String? value) {
    try {
      return tz.getLocation(value ?? 'UTC');
    } catch (_) {
      return tz.UTC;
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({
    required this.copy,
    required this.selected,
    required this.today,
    required this.isToday,
    required this.location,
    required this.filter,
    required this.onFilterChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onPickDate,
    required this.onBack,
    required this.child,
    this.summary,
  });

  final _ActivityCopy copy;
  final DateTime selected;
  final DateTime today;
  final bool isToday;
  final tz.Location location;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onToday;
  final VoidCallback onPickDate;
  final VoidCallback? onBack;
  final ActivityAggregation? summary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final direction = Directionality.of(context);
    final dateLabel = isToday
        ? copy.today
        : DateFormat.yMMMMd(locale).format(selected);
    final routeBack = Navigator.of(context).canPop()
        ? () => Navigator.maybePop(context)
        : null;
    final backAction = onBack ?? routeBack;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (backAction != null) ...[
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: backAction,
                        icon: Icon(
                          direction == TextDirection.rtl
                              ? Icons.arrow_forward
                              : Icons.arrow_back,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        context.l10n.text('activity'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  copy.subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    IconButton(
                      tooltip: copy.previousDay,
                      onPressed: onPrevious,
                      icon: Icon(
                        direction == TextDirection.rtl
                            ? Icons.chevron_right
                            : Icons.chevron_left,
                      ),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPickDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(dateLabel),
                      ),
                    ),
                    IconButton(
                      tooltip: copy.nextDay,
                      onPressed: onNext,
                      icon: Icon(
                        direction == TextDirection.rtl
                            ? Icons.chevron_left
                            : Icons.chevron_right,
                      ),
                    ),
                    if (!isToday)
                      TextButton(onPressed: onToday, child: Text(copy.today)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${copy.range}: 00:00–${isToday ? copy.now : '24:00'} · '
                  '${location.name}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (summary != null) ...[
                  const SizedBox(height: 16),
                  _SummaryPanel(summary: summary!, copy: copy),
                ],
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'all', label: Text(copy.all)),
                      ButtonSegment(
                        value: 'related',
                        label: Text(copy.related),
                      ),
                      ButtonSegment(value: 'breaks', label: Text(copy.breaks)),
                      ButtonSegment(
                        value: 'cross_task',
                        label: Text(copy.crossTask),
                      ),
                      ButtonSegment(value: 'idle', label: Text(copy.idle)),
                      ButtonSegment(
                        value: 'needs_review',
                        label: Text(copy.needsReview),
                      ),
                      ButtonSegment(
                        value: 'hidden_system',
                        label: Text(copy.hiddenSystemActivity),
                      ),
                    ],
                    selected: {filter},
                    onSelectionChanged: (values) =>
                        onFilterChanged(values.first),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.summary, required this.copy});

  final ActivityAggregation summary;
  final _ActivityCopy copy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _Metric(
              copy.totalObserved,
              context.l10n.duration(Duration(milliseconds: summary.totalMs)),
            ),
            _Metric(
              copy.active,
              context.l10n.duration(Duration(milliseconds: summary.activeMs)),
            ),
            _Metric(
              copy.idle,
              context.l10n.duration(Duration(milliseconds: summary.idleMs)),
            ),
            _Metric(
              copy.uncertain,
              context.l10n.duration(
                Duration(milliseconds: summary.uncertainMs),
              ),
            ),
            _Metric(
              copy.needsReview,
              context.l10n.duration(
                Duration(milliseconds: summary.needsReviewMs),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _GroupedActivityCard extends StatelessWidget {
  const _GroupedActivityCard({
    required this.group,
    required this.copy,
    required this.location,
    required this.totalLabel,
    required this.visiblePeriods,
    required this.onReviewGroup,
    required this.onReviewPeriod,
    this.onLoadMore,
  });

  final ActivityGroupSummary group;
  final _ActivityCopy copy;
  final tz.Location location;
  final String totalLabel;
  final int visiblePeriods;
  final VoidCallback onReviewGroup;
  final ValueChanged<ActivityPeriodSummary> onReviewPeriod;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final first = tz.TZDateTime.from(group.firstDetected, location);
    final last = tz.TZDateTime.from(group.lastDetected, location);
    final displayedPeriods = group.periods.take(visiblePeriods);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(group.key),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(_iconFor(group.sourceType)),
        ),
        title: Text(
          group.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$totalLabel: ${context.l10n.duration(Duration(milliseconds: group.totalMs))}',
              ),
              Text(
                '${copy.active}: ${context.l10n.duration(Duration(milliseconds: group.activeMs))} · '
                '${copy.idle}: ${context.l10n.duration(Duration(milliseconds: group.idleMs))}'
                '${group.uncertainMs > 0 ? ' · ${copy.uncertain}: ${context.l10n.duration(Duration(milliseconds: group.uncertainMs))}' : ''}',
              ),
              Text(
                '${group.periods.length} ${copy.activityPeriods} · '
                '${copy.lastUsed}: ${DateFormat.jm(locale).format(last)}',
              ),
              Text(
                '${copy.classification}: '
                '${copy.classificationName(group.classification)}',
              ),
              Text(
                copy.storageState(group.classification),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          Text(
            '${copy.firstDetected}: ${DateFormat.jm(locale).format(first)} · '
            '${copy.lastDetected}: ${DateFormat.jm(locale).format(last)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final period in displayedPeriods)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${DateFormat.jm(locale).format(tz.TZDateTime.from(period.startedAt, location))}'
                '–${DateFormat.jm(locale).format(tz.TZDateTime.from(period.endedAt, location))}',
              ),
              subtitle: Text(
                '${period.detail} · '
                '${copy.classificationName(period.classification)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.duration(
                      Duration(milliseconds: period.durationMs),
                    ),
                  ),
                  IconButton(
                    tooltip: copy.reviewActivity,
                    onPressed: () => onReviewPeriod(period),
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
            ),
          if (onLoadMore != null)
            TextButton(onPressed: onLoadMore, child: Text(copy.loadMore)),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              onPressed: onReviewGroup,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(copy.reviewActivity),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String sourceType) {
    return switch (sourceType) {
      'website' => Icons.public,
      'document' => Icons.description_outlined,
      'application' => Icons.apps,
      _ => Icons.timeline,
    };
  }
}

class _TaskPickerDialog extends StatelessWidget {
  const _TaskPickerDialog({required this.tasks, required this.copy});

  final List<LocalTask> tasks;
  final _ActivityCopy copy;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(copy.assignAnotherTask),
      content: SizedBox(
        width: 480,
        child: tasks.isEmpty
            ? Text(copy.noTaskTargets)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final task in tasks)
                    ListTile(
                      title: Text(task.title),
                      subtitle: Text(task.status),
                      onTap: () => Navigator.pop(context, task.id),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(copy.cancel),
        ),
      ],
    );
  }
}

class _NoActivity extends StatelessWidget {
  const _NoActivity();

  @override
  Widget build(BuildContext context) {
    final copy = _ActivityCopy.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              copy.noActivityToday,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({required this.copy});

  final _ActivityCopy copy;

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
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(copy.noReview, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(copy.noReviewDetail, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}

extension on ActivityResolution {
  ActivityResolution copyWith({bool? rememberRule}) => ActivityResolution(
    status: status,
    classification: classification,
    targetType: targetType,
    targetId: targetId,
    contributionType: contributionType,
    creditedDuration: creditedDuration,
    rememberRule: rememberRule ?? this.rememberRule,
    isAutomatic: isAutomatic,
  );
}

class _ActivityCopy {
  const _ActivityCopy(this.l10n);

  final AppLocalizations l10n;

  static _ActivityCopy of(BuildContext context) => _ActivityCopy(context.l10n);

  String get subtitle => l10n.text('activity_subtitle');
  String get today => l10n.text('today');
  String get previousDay => l10n.text('activity_previous_day');
  String get nextDay => l10n.text('activity_next_day');
  String get range => l10n.text('activity_daily_range');
  String get now => l10n.text('activity_now');
  String get all => l10n.text('activity_all');
  String get related => l10n.text('activity_related');
  String get breaks => l10n.text('activity_breaks');
  String get crossTask => l10n.text('activity_cross_task');
  String get idle => l10n.text('activity_inactive');
  String get needsReview => l10n.text('activity_needs_review');
  String get totalObserved => l10n.text('activity_total_observed');
  String get active => l10n.text('activity_active');
  String get uncertain => l10n.text('activity_uncertain');
  String get groupedMessage => l10n.text('activity_grouped_message');
  String get totalToday => l10n.text('activity_total_today');
  String get totalRecorded => l10n.text('activity_total_recorded');
  String get activityPeriods => l10n.text('activity_periods');
  String get lastUsed => l10n.text('activity_last_used');
  String get classification => l10n.text('activity_classification');
  String get firstDetected => l10n.text('activity_first_detected');
  String get lastDetected => l10n.text('activity_last_detected');
  String get reviewActivity => l10n.text('activity_review');
  String get loadMore => l10n.text('activity_load_more');
  String get assignAnotherTask => l10n.text('activity_assign_task');
  String get usefulReading => l10n.text('activity_useful_reading');
  String get supportingWork => l10n.text('activity_supporting_work');
  String get markDistraction => l10n.text('activity_mark_distraction');
  String get notRelated => l10n.text('activity_not_related');
  String get generallyUnrelated => l10n.text('activity_generally_unrelated');
  String get treatAsSystem => l10n.text('activity_treat_as_system');
  String get thisIsUserApplication =>
      l10n.text('activity_this_is_user_application');
  String get hiddenSystemActivity => l10n.text('hidden_system_activity');
  String get applyQuestion => l10n.text('activity_apply_scope');
  String get selectedOnly => l10n.text('activity_selected_only');
  String get rememberFuture => l10n.text('activity_remember_future');
  String get cancel => l10n.text('cancel');
  String get reviewSaved => l10n.text('activity_review_saved');
  String get couldNotSave => l10n.text('activity_save_failed');
  String get couldNotLoad => l10n.text('activity_load_failed');
  String get noTaskTargets => l10n.text('activity_no_task_targets');
  String get noActivityToday => l10n.text('activity_none_day');
  String get noReview => l10n.text('activity_none_review');
  String get noReviewDetail => l10n.text('activity_none_review_detail');

  String classificationName(String value) {
    return switch (value) {
      'direct_task_work' => l10n.text('classification_related'),
      'supporting_work' => supportingWork,
      'research' => l10n.text('classification_research'),
      'communication' => l10n.text('classification_communication'),
      'learning' => l10n.text('classification_learning'),
      'reading' || 'passive_useful_activity' => usefulReading,
      'distraction' => markDistraction,
      'unrelated' => l10n.text('classification_not_related'),
      'generally_unrelated' => generallyUnrelated,
      'system_activity' => l10n.text('system_activity'),
      'possible_system_activity' => l10n.text('possible_system_activity'),
      'user_application' => l10n.text('user_application'),
      'idle' || 'technical_idle' => idle,
      _ => needsReview,
    };
  }

  String storageState(String classification) {
    return switch (classification) {
      'direct_task_work' ||
      'supporting_work' ||
      'research' ||
      'communication' ||
      'learning' => l10n.text('contribution_synchronized'),
      _ => l10n.text('stored_on_this_device'),
    };
  }
}
