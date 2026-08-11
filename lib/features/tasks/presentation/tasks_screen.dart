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
  const TasksScreen({this.initialFilter = TaskListFilter.all, super.key});

  /// Allows Dashboard and coaching cards to open the exact canonical subset
  /// whose count they display.
  final TaskListFilter initialFilter;

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
    final tasksAsync = ref.watch(allTasksProvider);
    final domains = ref.watch(taskDomainsProvider).value ?? const [];
    final roadmaps = ref.watch(taskRoadmapsProvider).value ?? const [];
    final settings = ref.watch(appSettingsProvider).value;
    final timeZone = settings?.timeZone ?? 'UTC';
    final userId =
        ref.watch(supabaseClientProvider).auth.currentUser?.id ?? 'local';
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskEditorDialog.show(context),
        icon: const Icon(Icons.add_task),
        label: Text(context.l10n.text('add_task')),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            sliver: SliverToBoxAdapter(
              child: _Header(
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
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyTasks(
                    onAdd: () => TaskEditorDialog.show(context),
                  ),
                );
              }
              final domainNames = {
                for (final domain in domains)
                  domain.id: _localizedDomainName(context, userId, domain),
              };
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 96),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.text('tasks'),
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: search,
          onChanged: onQuery,
          decoration: InputDecoration(
            hintText: context.l10n.text('search'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
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
                    child: Text(_localizedDomainName(context, userId, domain)),
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
                  child: Text(context.l10n.text('task_filter_all_priorities')),
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

class _FilterField<T> extends StatelessWidget {
  const _FilterField({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
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
  const _EmptyTasks({required this.onAdd});

  final VoidCallback onAdd;

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
              size: 64,
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.text('add_task')),
            ),
          ],
        ),
      ),
    );
  }
}
