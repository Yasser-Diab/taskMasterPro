import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import 'task_card.dart';
import 'task_editor_dialog.dart';

final allTasksProvider = StreamProvider<List<LocalTask>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTasks(),
);

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(allTasksProvider);
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
                onQuery: (value) => setState(() => _query = value),
                onFilter: (value) => setState(() => _filter = value),
              ),
            ),
          ),
          tasksAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(child: Text(error.toString())),
            ),
            data: (tasks) {
              final filtered = tasks.where((task) {
                final matchesQuery =
                    _query.isEmpty ||
                    task.title.toLowerCase().contains(_query.toLowerCase()) ||
                    task.description.toLowerCase().contains(
                      _query.toLowerCase(),
                    );
                final matchesFilter =
                    _filter == 'all' || task.status == _filter;
                return matchesQuery && matchesFilter;
              }).toList();
              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyTasks(
                    onAdd: () => TaskEditorDialog.show(context),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 96),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      TaskCard(task: filtered[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.search,
    required this.filter,
    required this.onQuery,
    required this.onFilter,
  });

  final TextEditingController search;
  final String filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onFilter;

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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                onChanged: onQuery,
                decoration: InputDecoration(
                  hintText: context.l10n.text('search'),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: filter,
              borderRadius: BorderRadius.circular(14),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'ready', child: Text('Ready')),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text('In progress'),
                ),
                DropdownMenuItem(value: 'paused', child: Text('Paused')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
              ],
              onChanged: (value) => onFilter(value ?? 'all'),
            ),
          ],
        ),
      ],
    );
  }
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
