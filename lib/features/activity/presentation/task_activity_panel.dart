import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../../tasks/data/task_execution_providers.dart';
import '../../tasks/presentation/interruption_editor_dialog.dart';
import '../data/activity_aggregation_service.dart';
import 'activity_badges.dart';
import 'activity_review_screen.dart';

class TaskActivityPanel extends ConsumerStatefulWidget {
  const TaskActivityPanel({required this.task, super.key});

  final LocalTask task;

  @override
  ConsumerState<TaskActivityPanel> createState() => _TaskActivityPanelState();
}

class _TaskActivityPanelState extends ConsumerState<TaskActivityPanel>
    with SingleTickerProviderStateMixin {
  String? _range;
  DateTimeRange? _customRange;
  bool _reviewOpened = false;
  bool _notificationChecked = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    lowerBound: 0.82,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final database = ref.watch(databaseProvider);
    final settings = ref.watch(appSettingsProvider).value;
    final location = _location(settings?.timeZone);
    final now = tz.TZDateTime.now(location);
    final active =
        widget.task.status == 'in_progress' || widget.task.status == 'paused';
    final range = _range ?? (active ? 'session' : 'today');
    final bounds = _bounds(range, location, now);
    final segmentQuery = database.select(database.localActivitySegments)
      ..where(
        (row) =>
            row.deletedAt.isNull() &
            row.endedAt.isBiggerThanValue(bounds.$1) &
            row.startedAt.isSmallerThanValue(bounds.$2),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]);

    return StreamBuilder<List<LocalActivitySegment>>(
      stream: segmentQuery.watch(),
      builder: (context, segmentSnapshot) {
        if (!segmentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allSegments = segmentSnapshot.data!;
        if (allSegments.isEmpty) return _empty(context, range);
        final attributionQuery = database.select(database.localAttributions)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.activitySegmentId.isIn(
                  allSegments.map((item) => item.id).toList(),
                ),
          );
        return StreamBuilder<List<LocalAttribution>>(
          stream: attributionQuery.watch(),
          builder: (context, attributionSnapshot) {
            if (!attributionSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final attributions = attributionSnapshot.data!;
            final targetIds = attributions
                .where((item) => item.targetId == widget.task.id)
                .map((item) => item.activitySegmentId)
                .toSet();
            final segments = range == 'session'
                ? allSegments
                : allSegments
                      .where(
                        (segment) =>
                            targetIds.contains(segment.id) ||
                            _sourceTaskId(segment) == widget.task.id,
                      )
                      .toList();
            if (segments.isEmpty) return _empty(context, range);
            return FutureBuilder<ActivityAggregation>(
              future: ActivityAggregationService().aggregate(
                segments: segments,
                attributions: attributions,
                rangeStartUtc: bounds.$1,
                rangeEndUtc: bounds.$2,
                taskId: widget.task.id,
              ),
              builder: (context, snapshot) {
                final aggregation = snapshot.data;
                if (aggregation == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _content(context, aggregation, range, location);
              },
            );
          },
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    ActivityAggregation aggregation,
    String range,
    tz.Location location,
  ) {
    final unresolved = aggregation.groups
        .where(
          (group) => const {
            'unclassified',
            'unknown',
            'requires_review',
            'distraction',
            'unrelated',
          }.contains(group.classification),
        )
        .fold<int>(0, (total, group) => total + group.totalMs);
    final needsReview =
        aggregation.totalMs > 0 &&
        unresolved / aggregation.totalMs > 0.5 &&
        !_reviewOpened;
    if (needsReview) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyOnce());
    }
    final related = aggregation.groups
        .where(
          (group) => const {
            'direct_task_work',
            'learning',
            'reading',
          }.contains(group.classification),
        )
        .fold<int>(0, (value, group) => value + group.totalMs);
    final supporting = aggregation.groups
        .where((group) => group.classification == 'supporting_work')
        .fold<int>(0, (value, group) => value + group.totalMs);
    final distracting = aggregation.groups
        .where((group) => group.classification == 'distraction')
        .fold<int>(0, (value, group) => value + group.totalMs);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('task_activity'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(widget.task.title),
                ],
              ),
            ),
            IconButton.outlined(
              tooltip: context.l10n.text('add_interruption'),
              onPressed: _addInterruption,
              icon: const Icon(Icons.flash_on_outlined),
            ),
            const SizedBox(width: 8),
            _RangeMenu(value: range, onChanged: _changeRange),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                _TaskMetric(
                  context.l10n.text('task_total_time'),
                  context.l10n.duration(
                    Duration(milliseconds: aggregation.totalMs),
                  ),
                ),
                _TaskMetric(
                  context.l10n.text('task_related_activity'),
                  context.l10n.duration(Duration(milliseconds: related)),
                ),
                _TaskMetric(
                  context.l10n.text('activity_supporting_work'),
                  context.l10n.duration(Duration(milliseconds: supporting)),
                ),
                _TaskMetric(
                  context.l10n.text('activity_needs_review'),
                  context.l10n.duration(Duration(milliseconds: unresolved)),
                ),
                _TaskMetric(
                  context.l10n.text('task_distracting'),
                  context.l10n.duration(Duration(milliseconds: distracting)),
                ),
              ],
            ),
          ),
        ),
        if (needsReview) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(
              context,
            ).colorScheme.errorContainer.withValues(alpha: 0.65),
            child: ListTile(
              leading: ScaleTransition(
                scale: _pulse,
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              title: Text(
                context.l10n.text('activity_review_recommended'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(context.l10n.text('activity_review_over_half')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openReview,
            ),
          ),
        ],
        _TaskInterruptionsList(task: widget.task),
        const SizedBox(height: 12),
        for (final group in aggregation.groups)
          Card(
            child: ExpansionTile(
              leading: Icon(
                group.sourceType == 'website'
                    ? Icons.public
                    : group.sourceType == 'document'
                    ? Icons.description_outlined
                    : Icons.apps,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ActivityClassificationBadge(
                    classification: group.classification,
                    maxWidth: 132,
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${context.l10n.duration(Duration(milliseconds: group.totalMs))} · '
                    '${group.periods.length} '
                    '${context.l10n.text('activity_periods')}',
                  ),
                  if (activitySuggestionLabel(
                        context.l10n,
                        group.suggestionSource,
                      )
                      case final tag?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ActivitySuggestionBadge(label: tag),
                    ),
                ],
              ),
              children: [
                for (final period in group.periods.take(50))
                  ListTile(
                    dense: true,
                    title: Text(
                      '${DateFormat.jm(Localizations.localeOf(context).toLanguageTag()).format(tz.TZDateTime.from(period.startedAt, location))}'
                      '–${DateFormat.jm(Localizations.localeOf(context).toLanguageTag()).format(tz.TZDateTime.from(period.endedAt, location))}',
                    ),
                    subtitle: Text(period.detail),
                    trailing: Text(
                      context.l10n.duration(
                        Duration(milliseconds: period.durationMs),
                      ),
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextButton.icon(
                      onPressed: _openReview,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(context.l10n.text('activity_review')),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context, String range) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: _addInterruption,
              icon: const Icon(Icons.flash_on_outlined),
              label: Text(context.l10n.text('add_interruption')),
            ),
            const SizedBox(width: 8),
            _RangeMenu(value: range, onChanged: _changeRange),
          ],
        ),
        _TaskInterruptionsList(task: widget.task),
        const SizedBox(height: 80),
        Icon(
          Icons.insights_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          context.l10n.text('task_activity_empty'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.text('task_activity_empty_detail'),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _addInterruption() async {
    final runtime = ref.read(taskExecutionRuntimeProvider).value;
    await InterruptionEditorDialog.show(
      context,
      task: widget.task,
      sessionId: runtime?.activeTaskId == widget.task.id
          ? runtime?.sessionId
          : null,
    );
  }

  Future<void> _changeRange(String value) async {
    if (value == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _customRange,
      );
      if (picked == null) return;
      setState(() {
        _customRange = picked;
        _range = value;
      });
      return;
    }
    setState(() => _range = value);
  }

  (DateTime, DateTime) _bounds(
    String range,
    tz.Location location,
    tz.TZDateTime now,
  ) {
    if (range == 'session' && widget.task.actualStart != null) {
      return (widget.task.actualStart!.toUtc(), DateTime.now().toUtc());
    }
    if (range == 'week') {
      final start = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day - now.weekday + 1,
      );
      return (start.toUtc(), now.toUtc());
    }
    if (range == 'history') {
      return (widget.task.createdAt.toUtc(), DateTime.now().toUtc());
    }
    if (range == 'custom' && _customRange != null) {
      final start = tz.TZDateTime(
        location,
        _customRange!.start.year,
        _customRange!.start.month,
        _customRange!.start.day,
      );
      final end = tz.TZDateTime(
        location,
        _customRange!.end.year,
        _customRange!.end.month,
        _customRange!.end.day + 1,
      );
      return (start.toUtc(), end.toUtc());
    }
    final start = tz.TZDateTime(location, now.year, now.month, now.day);
    return (start.toUtc(), now.toUtc());
  }

  String? _sourceTaskId(LocalActivitySegment segment) {
    try {
      final value = jsonDecode(segment.rawMetadataJson);
      return value is Map ? value['source_task_id'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _notifyOnce() async {
    if (_notificationChecked) return;
    _notificationChecked = true;
    final preferences = await SharedPreferences.getInstance();
    final sessionKey =
        widget.task.actualStart?.millisecondsSinceEpoch.toString() ?? 'task';
    final key = 'taskmaster.activity_alert.${widget.task.id}.$sessionKey';
    if (preferences.getBool(key) == true) return;
    await preferences.setBool(key, true);
    final settings = ref.read(appSettingsProvider).value;
    if (!mounted) return;
    final localeCode = Localizations.localeOf(context).languageCode;
    final preferencesJson = settings?.notificationPreferencesJson ?? '{}';
    await localNotificationService.showActivityReviewAlert(
      taskId: widget.task.id,
      sound: NotificationSounds.forCategory(
        preferencesJson: preferencesJson,
        category: 'activity_review',
        fallbackKey: settings?.notificationSoundKey ?? 'system',
      ),
      enabled: NotificationSounds.categoryEnabled(
        preferencesJson: preferencesJson,
        category: 'activity_review',
      ),
      vibration: NotificationSounds.vibrationForCategory(
        preferencesJson: preferencesJson,
        category: 'activity_review',
      ),
      localeCode: localeCode,
    );
  }

  Future<void> _openReview() async {
    setState(() => _reviewOpened = true);
    _pulse.stop();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ActivityReviewScreen()),
    );
  }

  static tz.Location _location(String? name) {
    try {
      return tz.getLocation(name ?? 'UTC');
    } catch (_) {
      return tz.UTC;
    }
  }
}

class _TaskInterruptionsList extends ConsumerWidget {
  const _TaskInterruptionsList({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: repository.watch(entityType: 'interruptions', parentId: task.id),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const [];
        if (records.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.flash_on_outlined),
                title: Text(
                  context.l10n.text('report_interruptions'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  context.l10n.format('report_record_basis', {
                    'count': records.length,
                  }),
                ),
              ),
              const Divider(height: 1),
              for (final record in records.reversed)
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: Text(record.title),
                  subtitle: Text(_interruptionDescription(context, record)),
                  onTap: () => InterruptionEditorDialog.show(
                    context,
                    task: task,
                    existing: record,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') {
                        await InterruptionEditorDialog.show(
                          context,
                          task: task,
                          existing: record,
                        );
                        return;
                      }
                      await repository.softDelete(record);
                      unawaited(ref.read(syncServiceProvider).drainOutbox());
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.text('interruption_deleted'),
                          ),
                          duration: const Duration(seconds: 15),
                          action: SnackBarAction(
                            label: context.l10n.text('undo'),
                            onPressed: () => unawaited(() async {
                              await repository.restore(record.id);
                              await ref.read(syncServiceProvider).drainOutbox();
                            }()),
                          ),
                        ),
                      );
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.l10n.text('edit_interruption')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.l10n.text('delete')),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _interruptionDescription(
  BuildContext context,
  LocalEntityRecord record,
) {
  try {
    final raw = jsonDecode(record.dataJson);
    final data = raw is Map ? raw : const {};
    final durationMs = (data['duration_ms'] as num?)?.toInt() ?? 0;
    final notes = data['notes']?.toString().trim();
    return [
      context.l10n.duration(Duration(milliseconds: durationMs)),
      if (notes?.isNotEmpty == true) notes!,
    ].join(' · ');
  } catch (_) {
    return context.l10n.text('report_record_unavailable');
  }
}

class _RangeMenu extends StatelessWidget {
  const _RangeMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      'session': context.l10n.text('range_current_session'),
      'today': context.l10n.text('today'),
      'week': context.l10n.text('range_this_week'),
      'history': context.l10n.text('range_task_history'),
      'custom': context.l10n.text('range_custom'),
    };
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      child: Chip(
        avatar: const Icon(Icons.date_range, size: 18),
        label: Text(labels[value]!),
      ),
      itemBuilder: (context) => [
        for (final entry in labels.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
    );
  }
}

class _TaskMetric extends StatelessWidget {
  const _TaskMetric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}
