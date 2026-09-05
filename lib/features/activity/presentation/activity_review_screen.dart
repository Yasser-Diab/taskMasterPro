import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/learning/application_system_learning.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/activity_aggregation_service.dart';
import '../data/activity_repository.dart';
import 'activity_badges.dart';
import 'break_activity_check_in.dart';

final activityReviewProvider = StreamProvider<List<ActivityReviewEntry>>(
  (ref) => ref.watch(activityRepositoryProvider).watchReviewQueue(),
);

Set<String> pendingReviewSegmentIdsForFilter(
  String filter,
  Iterable<ActivityReviewEntry> entries,
) => entries
    .where(
      (entry) => switch (filter) {
        'pending_cross_task' =>
          activityAttentionKind(entry) == ActivityAttentionKind.crossTask,
        'pending_idle' =>
          activityAttentionKind(entry) == ActivityAttentionKind.inactive,
        'pending_other' =>
          activityAttentionKind(entry) == ActivityAttentionKind.other,
        _ => true,
      },
    )
    .map((entry) => entry.segment.id)
    .toSet();

ActivityGroupSummary _activityGroupSubset(
  ActivityGroupSummary group,
  List<ActivityPeriodSummary> periods,
  String filter,
) {
  var activeMs = 0;
  var idleMs = 0;
  var uncertainMs = 0;
  for (final period in periods) {
    switch (period.kind) {
      case ActivityTimeKind.active:
        activeMs += period.durationMs;
      case ActivityTimeKind.idle:
        idleMs += period.durationMs;
      case ActivityTimeKind.uncertain:
        uncertainMs += period.durationMs;
    }
  }
  return ActivityGroupSummary(
    key: '${group.key}::$filter',
    name: group.name,
    sourceType: group.sourceType,
    totalMs: activeMs + idleMs + uncertainMs,
    activeMs: activeMs,
    idleMs: idleMs,
    uncertainMs: uncertainMs,
    classification: group.classification,
    relatedTaskId: group.relatedTaskId,
    periods: periods,
    containsBreak: periods.any((period) => period.isBreak),
    containsCrossTask: periods.any((period) => period.isCrossTask),
    suggestionSource: group.suggestionSource,
  );
}

/// Applies the exact visual filter to the periods shown and reviewed.
///
/// Pending filters use the durable review queue. History filters such as
/// Cross-task and Inactive subset the periods inside a mixed application group
/// instead of showing every period merely because one period matched.
List<ActivityGroupSummary> activityGroupsForFilter({
  required ActivityAggregation aggregation,
  required String filter,
  required Map<String, ActivityReviewEntry> pendingBySegment,
  required bool hideConfirmedSystem,
  required bool showPossibleSystem,
}) {
  final pendingFilter = const {
    'needs_review',
    'pending_cross_task',
    'pending_idle',
    'pending_other',
  }.contains(filter);
  final result = <ActivityGroupSummary>[];
  for (final group in aggregation.groups) {
    if (!pendingFilter) {
      if (filter == 'hidden_system') {
        if (group.classification == 'system_activity') result.add(group);
        continue;
      }
      if (hideConfirmedSystem && group.classification == 'system_activity') {
        continue;
      }
      if (!showPossibleSystem &&
          group.classification == 'possible_system_activity') {
        continue;
      }
    }

    final periods = switch (filter) {
      'breaks' => group.periods.where((period) => period.isBreak).toList(),
      'cross_task' =>
        group.periods.where((period) => period.isCrossTask).toList(),
      'idle' =>
        group.periods
            .where((period) => period.kind != ActivityTimeKind.active)
            .toList(),
      'needs_review' =>
        group.periods
            .where((period) => pendingBySegment.containsKey(period.segmentId))
            .toList(),
      'pending_cross_task' => group.periods.where((period) {
        final entry = pendingBySegment[period.segmentId];
        return entry != null &&
            activityAttentionKind(entry) == ActivityAttentionKind.crossTask;
      }).toList(),
      'pending_idle' => group.periods.where((period) {
        final entry = pendingBySegment[period.segmentId];
        return entry != null &&
            activityAttentionKind(entry) == ActivityAttentionKind.inactive;
      }).toList(),
      'pending_other' => group.periods.where((period) {
        final entry = pendingBySegment[period.segmentId];
        return entry != null &&
            activityAttentionKind(entry) == ActivityAttentionKind.other;
      }).toList(),
      _ => const <ActivityPeriodSummary>[],
    };

    if (const {
      'breaks',
      'cross_task',
      'idle',
      'needs_review',
      'pending_cross_task',
      'pending_idle',
      'pending_other',
    }.contains(filter)) {
      if (periods.isNotEmpty) {
        result.add(_activityGroupSubset(group, periods, filter));
      }
      continue;
    }

    final include = switch (filter) {
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
      _ => true,
    };
    if (include) result.add(group);
  }
  return result;
}

ActivityAggregation activityAggregationWithPendingReviews(
  ActivityAggregation aggregation,
  Set<String> pendingSegmentIds,
) {
  final counted = <String>{};
  var needsReviewMs = 0;
  for (final group in aggregation.groups) {
    for (final period in group.periods) {
      if (pendingSegmentIds.contains(period.segmentId) &&
          counted.add(period.segmentId)) {
        needsReviewMs += period.durationMs;
      }
    }
  }
  return ActivityAggregation(
    groups: aggregation.groups,
    totalMs: aggregation.totalMs,
    activeMs: aggregation.activeMs,
    idleMs: aggregation.idleMs,
    uncertainMs: aggregation.uncertainMs,
    needsReviewMs: needsReviewMs,
  );
}

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
    final pendingReviews =
        ref.watch(activityReviewProvider).value ??
        const <ActivityReviewEntry>[];
    final pendingBySegment = <String, ActivityReviewEntry>{
      for (final entry in pendingReviews) entry.segment.id: entry,
    };
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
                  final rawAggregation = aggregationSnapshot.data;
                  final aggregation = rawAggregation == null
                      ? null
                      : activityAggregationWithPendingReviews(
                          rawAggregation,
                          pendingReviewSegmentIdsForFilter(
                            _filter,
                            pendingReviews,
                          ),
                        );
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
                            pendingBySegment: pendingBySegment,
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
    required Map<String, ActivityReviewEntry> pendingBySegment,
  }) {
    final groups = activityGroupsForFilter(
      aggregation: aggregation,
      filter: _filter,
      pendingBySegment: pendingBySegment,
      hideConfirmedSystem: hideConfirmedSystem,
      showPossibleSystem: showPossibleSystem,
    );
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
    final repository = ref.read(activityRepositoryProvider);
    final entries = <ActivityReviewEntry>[];
    for (final period in group.periods) {
      final entry = await repository.reviewEntryForSegment(period.segmentId);
      if (entry != null) entries.add(entry);
    }
    if (entries.isNotEmpty &&
        entries.every(
          (entry) => entry.review.reviewReason == breakActivityReviewReason,
        )) {
      final tasks = await repository.listTaskTargets();
      if (!mounted) return;
      final choice = await showBreakActivityCheckInSheet(
        context: context,
        tasks: tasks,
      );
      if (choice != null && mounted) {
        await _applyResolution(
          entries.map((entry) => entry.segment.id).toSet(),
          choice,
        );
      }
      return;
    }
    final choice = await _showClassificationSheet(group.name);
    if (choice == null || !mounted) return;
    final applyFuture = await _chooseApplicationScope(
      allowRemember: activityResolutionCanRememberForFuture(choice),
    );
    if (applyFuture == null || !mounted) return;
    final ids = group.periods.map((period) => period.segmentId).toSet();
    await _applyResolution(ids, choice.copyWith(rememberRule: applyFuture));
  }

  Future<void> _reviewPeriod(ActivityPeriodSummary period) async {
    final repository = ref.read(activityRepositoryProvider);
    final entry = await repository.reviewEntryForSegment(period.segmentId);
    if (entry?.review.reviewReason == breakActivityReviewReason) {
      final tasks = await repository.listTaskTargets();
      if (!mounted) return;
      final choice = await showBreakActivityCheckInSheet(
        context: context,
        tasks: tasks,
      );
      if (choice != null && mounted) {
        await _applyResolution({period.segmentId}, choice);
      }
      return;
    }
    final choice = await _showClassificationSheet(period.detail);
    if (choice == null || !mounted) return;
    final applyFuture = await _chooseApplicationScope(
      allowRemember: activityResolutionCanRememberForFuture(choice),
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
                final allocations =
                    await showDialog<List<ActivityTaskAllocation>>(
                      context: context,
                      builder: (context) =>
                          _TaskPickerDialog(tasks: tasks, copy: copy),
                    );
                if (allocations != null && context.mounted) {
                  Navigator.pop(
                    context,
                    ActivityResolution(
                      status: 'confirmed',
                      classification: 'direct_task_work',
                      contributionType: 'active_work_seconds',
                      taskAllocations: allocations,
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
        title: Text(allowRemember ? copy.applyQuestion : copy.applyAllocation),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(copy.selectedOnly, textAlign: TextAlign.center),
              ),
              if (allowRemember) ...[
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(copy.rememberFuture, textAlign: TextAlign.center),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  copy.multiTaskSelectedOnly,
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(copy.cancel),
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
      final communityChoices = <String, ApplicationLearningSource>{};
      for (final segmentId in segmentIds) {
        final entry = await repository.reviewEntryForSegment(segmentId);
        if (entry != null) {
          await repository.resolve(entry, resolution);
          final source = applicationLearningSourceForCapture(
            sourceType: entry.segment.sourceType,
            processName: entry.segment.processName,
            rawMetadataJson: entry.segment.rawMetadataJson,
          );
          if (source != null) {
            communityChoices['${source.platform}:${source.applicationIdentifier.toLowerCase()}'] =
                source;
          }
        }
      }
      unawaited(_submitCommunityChoice(communityChoices.values, resolution));
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

  Future<void> _submitCommunityChoice(
    Iterable<ApplicationLearningSource> sources,
    ActivityResolution resolution,
  ) async {
    try {
      final service = await ref.read(
        applicationSystemLearningServiceProvider.future,
      );
      if (service == null) return;
      for (final source in sources) {
        await service.submitExplicitClassification(
          platform: source.platform,
          applicationIdentifier: source.applicationIdentifier,
          classification: resolution.classification,
        );
      }
    } catch (_) {
      // The local Activity decision is already saved. Optional community
      // learning can never turn a successful review into an error.
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
    final compact = MediaQuery.sizeOf(context).width < 600;
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
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 24,
            compact ? 16 : 24,
            compact ? 12 : 24,
            12,
          ),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                            label: Text(
                              dateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                        if (!compact && !isToday)
                          TextButton(
                            onPressed: onToday,
                            child: Text(copy.today),
                          ),
                      ],
                    ),
                    if (compact && !isToday)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: onToday,
                          child: Text(copy.today),
                        ),
                      ),
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
                _ActivityFilterStrip(
                  compact: compact,
                  copy: copy,
                  filter: filter,
                  onFilterChanged: onFilterChanged,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 24,
            8,
            compact ? 12 : 24,
            32,
          ),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}

class _ActivityFilterStrip extends StatefulWidget {
  const _ActivityFilterStrip({
    required this.compact,
    required this.copy,
    required this.filter,
    required this.onFilterChanged,
  });

  final bool compact;
  final _ActivityCopy copy;
  final String filter;
  final ValueChanged<String> onFilterChanged;

  @override
  State<_ActivityFilterStrip> createState() => _ActivityFilterStripState();
}

class _ActivityFilterStripState extends State<_ActivityFilterStrip> {
  final _scrollController = ScrollController();
  final _optionKeys = <String, GlobalKey>{};

  String get _selectedFilter => widget.filter;

  List<(String, String)> get _options => [
    ('all', widget.copy.all),
    ('related', widget.copy.related),
    ('breaks', widget.copy.breaks),
    widget.filter == 'pending_cross_task'
        ? ('pending_cross_task', widget.copy.crossTaskReview)
        : ('cross_task', widget.copy.crossTask),
    widget.filter == 'pending_idle'
        ? ('pending_idle', widget.copy.inactiveReview)
        : ('idle', widget.copy.idle),
    widget.filter == 'pending_other'
        ? ('pending_other', widget.copy.otherActivityReview)
        : ('needs_review', widget.copy.needsReview),
    ('hidden_system', widget.copy.hiddenSystemActivity),
  ];

  @override
  void initState() {
    super.initState();
    _scheduleSelectedIntoView(animate: false);
  }

  @override
  void didUpdateWidget(covariant _ActivityFilterStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compact &&
        (oldWidget.filter != widget.filter || !oldWidget.compact)) {
      _scheduleSelectedIntoView(animate: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSelectedIntoView({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.compact || !_scrollController.hasClients) return;
      final renderObject = _optionKeys[_selectedFilter]?.currentContext
          ?.findRenderObject();
      if (renderObject == null) return;
      _scrollController.position.ensureVisible(
        renderObject,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    if (!widget.compact) {
      return SingleChildScrollView(
        key: const ValueKey('desktop-activity-filter-strip'),
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          segments: [
            for (final option in options)
              ButtonSegment(value: option.$1, label: Text(option.$2)),
          ],
          selected: {_selectedFilter},
          onSelectionChanged: (values) => widget.onFilterChanged(values.first),
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('mobile-activity-filter-strip'),
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Row(
        children: [
          for (final option in options) ...[
            ChoiceChip(
              key: _optionKeys.putIfAbsent(option.$1, GlobalKey.new),
              label: Text(option.$2),
              selected: _selectedFilter == option.$1,
              onSelected: (_) => widget.onFilterChanged(option.$1),
              selectedColor: colors.primaryContainer,
              tooltip: option.$2,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
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
    final compact = MediaQuery.sizeOf(context).width < 600;
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
        title: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  ActivityClassificationBadge(
                    classification: group.classification,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ActivityClassificationBadge(
                    classification: group.classification,
                  ),
                ],
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
                copy.storageState(group.classification),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (activitySuggestionLabel(copy.l10n, group.suggestionSource)
                  case final tag?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(children: [ActivitySuggestionBadge(label: tag)]),
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

class _TaskPickerDialog extends StatefulWidget {
  const _TaskPickerDialog({required this.tasks, required this.copy});

  final List<LocalTask> tasks;
  final _ActivityCopy copy;

  @override
  State<_TaskPickerDialog> createState() => _TaskPickerDialogState();
}

class _TaskPickerDialogState extends State<_TaskPickerDialog> {
  final Map<String, int> _percentages = {};

  int get _total => _percentages.values.fold(0, (sum, value) => sum + value);

  void _toggle(LocalTask task, bool selected) {
    setState(() {
      if (!selected) {
        _percentages.remove(task.id);
        return;
      }
      final remaining = 100 - _total;
      if (remaining <= 0) return;
      _percentages[task.id] = remaining;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.copy.creditToTasks),
      content: SizedBox(
        width: 480,
        child: widget.tasks.isEmpty
            ? Text(widget.copy.noTaskTargets)
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.copy.allocationHelp),
                      const SizedBox(height: 8),
                      for (final task in widget.tasks) ...[
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _percentages.containsKey(task.id),
                          title: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(context.l10n.taskStatus(task.status)),
                          onChanged: (value) => _toggle(task, value ?? false),
                        ),
                        if (_percentages.containsKey(task.id))
                          Row(
                            children: [
                              Expanded(
                                child: Slider(
                                  value: _percentages[task.id]!.toDouble(),
                                  min: 1,
                                  max: 100,
                                  divisions: 99,
                                  label: '${_percentages[task.id]}%',
                                  onChanged: (value) {
                                    final otherTotal =
                                        _total - _percentages[task.id]!;
                                    final maximum = 100 - otherTotal;
                                    setState(() {
                                      _percentages[task.id] = value
                                          .round()
                                          .clamp(1, maximum);
                                    });
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '${_percentages[task.id]}%',
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        widget.copy.allocatedTotal(_total),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.copy.cancel),
        ),
        FilledButton(
          onPressed: _percentages.isEmpty || _total > 100
              ? null
              : () => Navigator.pop(context, [
                  for (final entry in _percentages.entries)
                    ActivityTaskAllocation(
                      targetTaskId: entry.key,
                      percentage: entry.value,
                    ),
                ]),
          child: Text(widget.copy.applyAllocation),
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
    taskAllocations: taskAllocations,
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
  String get crossTaskReview => l10n.text('activity_pending_cross_task');
  String get idle => l10n.text('activity_inactive');
  String get inactiveReview => l10n.text('activity_pending_idle');
  String get otherActivityReview => l10n.text('activity_pending_other');
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
  String get creditToTasks => l10n.text('activity_credit_to_tasks');
  String get allocationHelp => l10n.text('activity_allocation_help');
  String allocatedTotal(int percentage) =>
      l10n.format('activity_allocated_total', {'percentage': percentage});
  String get applyAllocation => l10n.text('activity_apply_allocation');
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
  String get multiTaskSelectedOnly =>
      l10n.text('activity_multi_task_selected_only');
  String get cancel => l10n.text('cancel');
  String get reviewSaved => l10n.text('activity_review_saved');
  String get couldNotSave => l10n.text('activity_save_failed');
  String get couldNotLoad => l10n.text('activity_load_failed');
  String get noTaskTargets => l10n.text('activity_no_task_targets');
  String get noActivityToday => l10n.text('activity_none_day');
  String get noReview => l10n.text('activity_none_review');
  String get noReviewDetail => l10n.text('activity_none_review_detail');

  String classificationName(String value) {
    return activityClassificationLabel(l10n, value);
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
