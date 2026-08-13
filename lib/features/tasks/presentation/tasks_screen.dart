import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../domain/task_domain_catalog.dart';
import '../domain/task_list_projection.dart';
import 'task_card.dart';
import 'task_editor_dialog.dart';

final allTasksProvider = StreamProvider<List<LocalTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTasks(),
);

final taskDomainsProvider = StreamProvider<List<LocalDomain>>(
  (ref) => ref.watch(taskRepositoryProvider).watchDomains(),
);

final taskRoadmapsProvider = StreamProvider<List<LocalRoadmap>>((ref) {
  final database = ref.watch(databaseProvider);
  final userId =
      ref.watch(supabaseClientProvider).auth.currentUser?.id ?? 'local';
  final query = database.select(database.localRoadmaps)
    ..where((row) => row.userId.equals(userId) & row.deletedAt.isNull())
    ..orderBy([(row) => OrderingTerm.asc(row.title)]);
  return query.watch();
});

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({
    this.initialFilter = TaskListFilter.all,
    this.showRouteAppBar = false,
    super.key,
  });

  /// Allows Dashboard and coaching cards to open the exact canonical subset
  /// whose count they display.
  final TaskListFilter initialFilter;

  /// True when this screen is pushed above the shell from a settings shortcut.
  /// Shell destinations supply their own navigation; pushed routes must always
  /// expose an explicit way back.
  final bool showRouteAppBar;

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _search = TextEditingController();
  String _query = '';
  late TaskListFilter _filter;
  String? _domainId;
  String? _roadmapId;
  String? _executionMode;
  int? _priority;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  void didUpdateWidget(covariant TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      setState(() => _filter = widget.initialFilter);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final tasksAsync = ref.watch(allTasksProvider);
    final domains = ref.watch(taskDomainsProvider).value ?? const [];
    final roadmaps = ref.watch(taskRoadmapsProvider).value ?? const [];
    final settings = ref.watch(appSettingsProvider).value;
    final timeZone = settings?.timeZone ?? 'UTC';
    final userId =
        ref.watch(supabaseClientProvider).auth.currentUser?.id ?? 'local';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.showRouteAppBar
          ? AppBar(
              leading: const BackButton(),
              title: Text(context.l10n.text('tasks')),
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskEditorDialog.show(context),
        icon: const Icon(Icons.add_task),
        label: Text(context.l10n.text('add_task')),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              compact ? 16 : 24,
              compact ? 16 : 24,
              compact ? 8 : 12,
            ),
            sliver: SliverToBoxAdapter(
              child: _Header(
                showTitle: !widget.showRouteAppBar,
                search: _search,
                filter: _filter,
                domainId: _domainId,
                roadmapId: _roadmapId,
                executionMode: _executionMode,
                priority: _priority,
                domains: domains,
                roadmaps: roadmaps,
                userId: userId,
                onQuery: (value) => setState(() => _query = value),
                onFilter: (value) => setState(() => _filter = value),
                onDomain: (value) => setState(() => _domainId = value),
                onRoadmap: (value) => setState(() => _roadmapId = value),
                onExecution: (value) => setState(() => _executionMode = value),
                onPriority: (value) => setState(() => _priority = value),
              ),
            ),
          ),
          tasksAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => SliverFillRemaining(
              child: Center(
                child: Text(context.l10n.text('tasks_load_failed')),
              ),
            ),
            data: (tasks) {
              final entries = TaskListQuery(
                filter: _filter,
                search: _query,
                domainId: _domainId,
                roadmapId: _roadmapId,
                executionMode: _executionMode,
                priority: _priority,
              ).apply(tasks, now: DateTime.now(), timeZone: timeZone);
              if (entries.isEmpty) {
                if (compact) {
                  return const SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 44, 20, 112),
                    sliver: SliverToBoxAdapter(child: _EmptyTasks()),
                  );
                }
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: const _EmptyTasks(),
                );
              }
              final domainNames = {
                for (final domain in domains)
                  domain.id: _localizedDomainName(context, userId, domain),
              };
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24,
                  4,
                  compact ? 16 : 24,
                  96,
                ),
                sliver: SliverList.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return TaskCard(
                      task: entry.task,
                      domainLabel: entry.task.domainId == null
                          ? null
                          : domainNames[entry.task.domainId],
                      recurrenceLabel: entry.isRecurringTemplate
                          ? _recurrenceLabel(context, entry)
                          : null,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _recurrenceLabel(BuildContext context, TaskListEntry entry) {
    final next = entry.nextOccurrence;
    if (next == null) return context.l10n.text('task_recurring');
    final formatted = DateFormat.MMMEd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_jm().format(next.toLocal());
    return context.l10n.format('task_recurring_next', {'date': formatted});
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.showTitle,
    required this.search,
    required this.filter,
    required this.domainId,
    required this.roadmapId,
    required this.executionMode,
    required this.priority,
    required this.domains,
    required this.roadmaps,
    required this.userId,
    required this.onQuery,
    required this.onFilter,
    required this.onDomain,
    required this.onRoadmap,
    required this.onExecution,
    required this.onPriority,
  });

  final bool showTitle;

  final TextEditingController search;
  final TaskListFilter filter;
  final String? domainId;
  final String? roadmapId;
  final String? executionMode;
  final int? priority;
  final List<LocalDomain> domains;
  final List<LocalRoadmap> roadmaps;
  final String userId;
  final ValueChanged<String> onQuery;
  final ValueChanged<TaskListFilter> onFilter;
  final ValueChanged<String?> onDomain;
  final ValueChanged<String?> onRoadmap;
  final ValueChanged<String?> onExecution;
  final ValueChanged<int?> onPriority;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text(
            context.l10n.text('tasks'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: compact ? 28 : null,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
        ],
        if (compact)
          _MobileSearchAndFilters(
            search: search,
            filter: filter,
            domainId: domainId,
            roadmapId: roadmapId,
            executionMode: executionMode,
            priority: priority,
            domains: domains,
            roadmaps: roadmaps,
            userId: userId,
            onQuery: onQuery,
            onFilter: onFilter,
            onDomain: onDomain,
            onRoadmap: onRoadmap,
            onExecution: onExecution,
            onPriority: onPriority,
          )
        else
          TextField(
            controller: search,
            onChanged: onQuery,
            decoration: InputDecoration(
              hintText: context.l10n.text('search'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        const SizedBox(height: 12),
        if (!compact)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FilterField<TaskListFilter>(
                value: filter,
                label: context.l10n.text('task_filter_status'),
                items: [
                  for (final value in TaskListFilter.values.where(
                    (value) =>
                        value != TaskListFilter.completedToday ||
                        filter == TaskListFilter.completedToday,
                  ))
                    DropdownMenuItem(
                      value: value,
                      child: Text(context.l10n.text(value.localizationKey)),
                    ),
                ],
                onChanged: (value) => onFilter(value ?? TaskListFilter.all),
              ),
              _FilterField<String?>(
                value: domainId,
                label: context.l10n.text('task_domain'),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.text('task_filter_all_domains')),
                  ),
                  for (final domain in domains)
                    DropdownMenuItem(
                      value: domain.id,
                      child: Text(
                        _localizedDomainName(context, userId, domain),
                      ),
                    ),
                ],
                onChanged: onDomain,
              ),
              _FilterField<String?>(
                value: roadmapId,
                label: context.l10n.text('roadmaps'),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.text('task_filter_all_roadmaps')),
                  ),
                  for (final roadmap in roadmaps)
                    DropdownMenuItem(
                      value: roadmap.id,
                      child: Text(roadmap.title),
                    ),
                ],
                onChanged: onRoadmap,
              ),
              _FilterField<String?>(
                value: executionMode,
                label: context.l10n.text('execution_mode'),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.text('task_filter_all_methods')),
                  ),
                  for (final mode in const [
                    'manual',
                    'pomodoro',
                    'continuous',
                    'checklist',
                    'reading',
                    'habit',
                    'event',
                    'hybrid',
                  ])
                    DropdownMenuItem(
                      value: mode,
                      child: Text(context.l10n.executionMode(mode)),
                    ),
                ],
                onChanged: onExecution,
              ),
              _FilterField<int?>(
                value: priority,
                label: context.l10n.text('priority'),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      context.l10n.text('task_filter_all_priorities'),
                    ),
                  ),
                  for (var value = 0; value <= 4; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        context.l10n.text(
                          const [
                            'priority_low',
                            'priority_normal',
                            'priority_important',
                            'priority_high',
                            'priority_critical',
                          ][value],
                        ),
                      ),
                    ),
                ],
                onChanged: onPriority,
              ),
            ],
          ),
      ],
    );
  }
}

class _MobileSearchAndFilters extends StatelessWidget {
  const _MobileSearchAndFilters({
    required this.search,
    required this.filter,
    required this.domainId,
    required this.roadmapId,
    required this.executionMode,
    required this.priority,
    required this.domains,
    required this.roadmaps,
    required this.userId,
    required this.onQuery,
    required this.onFilter,
    required this.onDomain,
    required this.onRoadmap,
    required this.onExecution,
    required this.onPriority,
  });

  final TextEditingController search;
  final TaskListFilter filter;
  final String? domainId;
  final String? roadmapId;
  final String? executionMode;
  final int? priority;
  final List<LocalDomain> domains;
  final List<LocalRoadmap> roadmaps;
  final String userId;
  final ValueChanged<String> onQuery;
  final ValueChanged<TaskListFilter> onFilter;
  final ValueChanged<String?> onDomain;
  final ValueChanged<String?> onRoadmap;
  final ValueChanged<String?> onExecution;
  final ValueChanged<int?> onPriority;

  int get _advancedFilterCount =>
      [domainId, roadmapId, executionMode, priority].nonNulls.length;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('mobile-task-filter-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: TextField(
                  controller: search,
                  onChanged: onQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: context.l10n.text('search'),
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: _advancedFilterCount > 0,
              label: Text('$_advancedFilterCount'),
              child: IconButton.filledTonal(
                key: const ValueKey('mobile-task-filter-button'),
                onPressed: () => _showFilterSheet(context),
                tooltip: context.l10n.text('task_filters'),
                icon: const Icon(Icons.tune_rounded),
                style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          key: const ValueKey('mobile-task-status-strip'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final value in const [
                TaskListFilter.all,
                TaskListFilter.today,
                TaskListFilter.upcoming,
                TaskListFilter.recurring,
                TaskListFilter.active,
                TaskListFilter.completed,
              ]) ...[
                ChoiceChip(
                  label: Text(context.l10n.text(value.localizationKey)),
                  selected: filter == value,
                  onSelected: (_) => onFilter(value),
                  showCheckmark: false,
                  selectedColor: colors.primaryContainer,
                  tooltip: context.l10n.text(value.localizationKey),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    var draftFilter = filter;
    var draftDomainId = domainId;
    var draftRoadmapId = roadmapId;
    var draftExecutionMode = executionMode;
    var draftPriority = priority;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void clear() => setSheetState(() {
            draftFilter = TaskListFilter.all;
            draftDomainId = null;
            draftRoadmapId = null;
            draftExecutionMode = null;
            draftPriority = null;
          });

          void apply() {
            onFilter(draftFilter);
            onDomain(draftDomainId);
            onRoadmap(draftRoadmapId);
            onExecution(draftExecutionMode);
            onPriority(draftPriority);
            Navigator.pop(sheetContext);
          }

          return FractionallySizedBox(
            key: const ValueKey('task-filter-sheet'),
            heightFactor: .86,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.text('task_filters'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      TextButton(
                        onPressed: clear,
                        child: Text(context.l10n.text('clear')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      Text(
                        context.l10n.text('task_filter_status'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in TaskListFilter.values.where(
                            (value) =>
                                value != TaskListFilter.completedToday ||
                                filter == TaskListFilter.completedToday,
                          ))
                            ChoiceChip(
                              label: Text(
                                context.l10n.text(value.localizationKey),
                              ),
                              selected: draftFilter == value,
                              onSelected: (_) =>
                                  setSheetState(() => draftFilter = value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _FilterField<String?>(
                        fillWidth: true,
                        value: draftDomainId,
                        label: context.l10n.text('task_domain'),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              context.l10n.text('task_filter_all_domains'),
                            ),
                          ),
                          for (final domain in domains)
                            DropdownMenuItem(
                              value: domain.id,
                              child: Text(
                                _localizedDomainName(context, userId, domain),
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => draftDomainId = value),
                      ),
                      const SizedBox(height: 12),
                      _FilterField<String?>(
                        fillWidth: true,
                        value: draftRoadmapId,
                        label: context.l10n.text('roadmaps'),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              context.l10n.text('task_filter_all_roadmaps'),
                            ),
                          ),
                          for (final roadmap in roadmaps)
                            DropdownMenuItem(
                              value: roadmap.id,
                              child: Text(roadmap.title),
                            ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => draftRoadmapId = value),
                      ),
                      const SizedBox(height: 12),
                      _FilterField<String?>(
                        fillWidth: true,
                        value: draftExecutionMode,
                        label: context.l10n.text('execution_mode'),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              context.l10n.text('task_filter_all_methods'),
                            ),
                          ),
                          for (final mode in const [
                            'manual',
                            'pomodoro',
                            'continuous',
                            'checklist',
                            'reading',
                            'habit',
                            'event',
                            'hybrid',
                          ])
                            DropdownMenuItem(
                              value: mode,
                              child: Text(context.l10n.executionMode(mode)),
                            ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => draftExecutionMode = value),
                      ),
                      const SizedBox(height: 12),
                      _FilterField<int?>(
                        fillWidth: true,
                        value: draftPriority,
                        label: context.l10n.text('priority'),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              context.l10n.text('task_filter_all_priorities'),
                            ),
                          ),
                          for (var value = 0; value <= 4; value++)
                            DropdownMenuItem(
                              value: value,
                              child: Text(
                                context.l10n.text(
                                  const [
                                    'priority_low',
                                    'priority_normal',
                                    'priority_important',
                                    'priority_high',
                                    'priority_critical',
                                  ][value],
                                ),
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => draftPriority = value),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: apply,
                      child: Text(context.l10n.text('done')),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilterField<T> extends StatelessWidget {
  const _FilterField({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    this.fillWidth = false,
  });

  final T value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fillWidth ? double.infinity : 210,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

String _localizedDomainName(
  BuildContext context,
  String userId,
  LocalDomain domain,
) {
  final key = TaskDomainCatalog.builtInKeyForId(userId, domain.id);
  return key == null
      ? domain.name
      : context.l10n.text(TaskDomainCatalog.localizationKey(key));
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.text('empty_tasks'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.text('empty_tasks_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
