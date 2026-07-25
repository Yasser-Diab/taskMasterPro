import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../../roadmaps/presentation/roadmaps_screen.dart';
import 'task_browser_workspace.dart';
import 'task_document_workspace.dart';
import 'task_editor_dialog.dart';

class TaskWorkspaceScreen extends ConsumerStatefulWidget {
  const TaskWorkspaceScreen({required this.taskId, super.key});

  final String taskId;

  static Future<void> open(BuildContext context, LocalTask task) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskWorkspaceScreen(taskId: task.id),
      ),
    );
  }

  @override
  ConsumerState<TaskWorkspaceScreen> createState() =>
      _TaskWorkspaceScreenState();
}

class _TaskWorkspaceScreenState extends ConsumerState<TaskWorkspaceScreen> {
  int _section = 0;

  static const _sections = <(String, IconData)>[
    ('Overview', Icons.dashboard_outlined),
    ('Execute', Icons.play_circle_outline),
    ('Checklist', Icons.checklist),
    ('Browser', Icons.language),
    ('Resources', Icons.folder_copy_outlined),
    ('Connections', Icons.hub_outlined),
    ('Notes', Icons.notes_outlined),
    ('History', Icons.history),
    ('Settings', Icons.tune),
  ];

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final taskStream =
        (db.select(db.localTasks)..where(
              (row) => row.id.equals(widget.taskId) & row.deletedAt.isNull(),
            ))
            .watchSingleOrNull();
    return StreamBuilder<LocalTask?>(
      stream: taskStream,
      builder: (context, snapshot) {
        final task = snapshot.data;
        if (task == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final wide = MediaQuery.sizeOf(context).width >= 920;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${_titleCase(task.executionMode)} · ${_titleCase(task.status)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Edit task',
                onPressed: () => TaskEditorDialog.show(context, task: task),
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'Task actions',
                onSelected: (action) => _taskAction(task, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplicate task'),
                  ),
                  PopupMenuItem(
                    value: 'postpone',
                    child: Text('Postpone to another day'),
                  ),
                  PopupMenuItem(
                    value: 'complete',
                    child: Text('Mark complete'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Delete task')),
                ],
              ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _section,
                      onDestinationSelected: (value) =>
                          setState(() => _section = value),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final section in _sections)
                          NavigationRailDestination(
                            icon: Icon(section.$2),
                            selectedIcon: Icon(section.$2),
                            label: Text(section.$1),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _page(task)),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 54,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemBuilder: (context, index) => ChoiceChip(
                          selected: _section == index,
                          avatar: Icon(_sections[index].$2, size: 18),
                          label: Text(_sections[index].$1),
                          onSelected: (_) => setState(() => _section = index),
                        ),
                        separatorBuilder: (_, _) => const SizedBox(width: 7),
                        itemCount: _sections.length,
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _page(task)),
                  ],
                ),
        );
      },
    );
  }

  Widget _page(LocalTask task) {
    return switch (_section) {
      0 => _TaskOverview(task: task, onOpenSection: _openSection),
      1 => _TaskExecutionPanel(task: task),
      2 => _ChecklistPanel(task: task),
      3 => TaskBrowserWorkspace(task: task),
      4 => _ResourcesPanel(task: task),
      5 => _ConnectionsPanel(task: task),
      6 => _NotesPanel(task: task),
      7 => _HistoryPanel(task: task),
      _ => _TaskSettingsPanel(task: task),
    };
  }

  void _openSection(int index) => setState(() => _section = index);

  Future<void> _taskAction(LocalTask task, String action) async {
    final repository = ref.read(taskRepositoryProvider);
    switch (action) {
      case 'duplicate':
        await repository.duplicate(task);
      case 'postpone':
        final date = await showDatePicker(
          context: context,
          initialDate: (task.scheduledDate ?? DateTime.now()).add(
            const Duration(days: 1),
          ),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (date != null) await repository.reschedule(task, date);
      case 'complete':
        await repository.complete(task);
      case 'delete':
        final confirmed = await _confirm(
          context,
          title: 'Delete this task?',
          body:
              'The task is kept as a synchronized tombstone so other devices '
              'do not restore it.',
          confirmLabel: 'Delete',
        );
        if (confirmed) {
          await repository.softDelete(task);
          if (mounted) Navigator.pop(context);
        }
    }
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
}

class _TaskOverview extends ConsumerWidget {
  const _TaskOverview({required this.task, required this.onOpenSection});

  final LocalTask task;
  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = MaterialLocalizations.of(context);
    final planned = task.plannedStart?.toLocal();
    final due = task.dueAt?.toLocal();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Progress',
              value: '${(task.progress * 100).round()}%',
              icon: Icons.donut_large,
            ),
            _MetricCard(
              label: 'Planned effort',
              value: _duration(task.estimatedDurationMs),
              icon: Icons.schedule,
            ),
            _MetricCard(
              label: 'Recorded work',
              value: _duration(task.activeDurationMs),
              icon: Icons.timer_outlined,
            ),
            _MetricCard(
              label: 'Priority',
              value: _priority(task.priority),
              icon: Icons.flag_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (task.description.isNotEmpty) ...[
                  Text(task.description),
                  const SizedBox(height: 16),
                ],
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Scheduled',
                  value: task.scheduledDate == null
                      ? 'Flexible'
                      : local.formatFullDate(task.scheduledDate!.toLocal()),
                ),
                _InfoRow(
                  icon: Icons.access_time,
                  label: 'Local start',
                  value: planned == null
                      ? 'Not fixed'
                      : '${local.formatMediumDate(planned)} · '
                            '${local.formatTimeOfDay(TimeOfDay.fromDateTime(planned))}',
                ),
                _InfoRow(
                  icon: Icons.event_available_outlined,
                  label: 'Due',
                  value: due == null
                      ? 'No deadline'
                      : '${local.formatMediumDate(due)} · '
                            '${local.formatTimeOfDay(TimeOfDay.fromDateTime(due))}',
                ),
                _InfoRow(
                  icon: Icons.public,
                  label: 'Synchronization time',
                  value:
                      'Saved as UTC instants and rendered in this device’s local time',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Task workspace',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.65,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _WorkspaceShortcut(
              icon: Icons.play_circle_outline,
              title: 'Execute',
              subtitle: 'Timer, focus and task state',
              onTap: () => onOpenSection(1),
            ),
            _WorkspaceShortcut(
              icon: Icons.language,
              title: 'Task browser',
              subtitle: 'Persistent tabs and bookmarks',
              onTap: () => onOpenSection(3),
            ),
            _WorkspaceShortcut(
              icon: Icons.folder_copy_outlined,
              title: 'Resources',
              subtitle: 'Files, PDFs, URLs and books',
              onTap: () => onOpenSection(4),
            ),
            _WorkspaceShortcut(
              icon: Icons.hub_outlined,
              title: 'Connections',
              subtitle: 'Roadmap, apps, sites and tasks',
              onTap: () => onOpenSection(5),
            ),
            _WorkspaceShortcut(
              icon: Icons.checklist,
              title: 'Requirements',
              subtitle: 'Required and optional items',
              onTap: () => onOpenSection(2),
            ),
            _WorkspaceShortcut(
              icon: Icons.history,
              title: 'Evidence history',
              subtitle: 'Status, notes and execution events',
              onTap: () => onOpenSection(7),
            ),
          ],
        ),
      ],
    );
  }
}

class _TaskExecutionPanel extends ConsumerStatefulWidget {
  const _TaskExecutionPanel({required this.task});

  final LocalTask task;

  @override
  ConsumerState<_TaskExecutionPanel> createState() =>
      _TaskExecutionPanelState();
}

class _TaskExecutionPanelState extends ConsumerState<_TaskExecutionPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LocalRuntime?>(
      stream: ref.watch(taskRepositoryProvider).watchRuntime(),
      builder: (context, snapshot) {
        final runtime = snapshot.data;
        final isThisTask = runtime?.activeTaskId == widget.task.id;
        final running = isThisTask && runtime?.state == 'running';
        final paused = isThisTask && runtime?.state == 'paused';
        final currentSegment = running && runtime?.segmentStartedAt != null
            ? DateTime.now()
                  .toUtc()
                  .difference(runtime!.segmentStartedAt!)
                  .inMilliseconds
            : 0;
        final activeMs =
            (isThisTask ? runtime?.accumulatedActiveMs ?? 0 : 0) +
            currentSegment;
        final remaining = widget.task.estimatedDurationMs - activeMs;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Text(
                          _titleCase(widget.task.executionMode),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _clock(activeMs),
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          remaining >= 0
                              ? '${_duration(remaining)} planned remaining'
                              : '${_duration(-remaining)} overtime',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: remaining >= 0
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant
                                    : Theme.of(context).colorScheme.error,
                              ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            if (!isThisTask || (!running && !paused))
                              FilledButton.icon(
                                onPressed: () => _run(
                                  ref,
                                  () => ref
                                      .read(taskRepositoryProvider)
                                      .start(widget.task),
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Start'),
                              ),
                            if (running)
                              FilledButton.tonalIcon(
                                onPressed: () => _run(
                                  ref,
                                  () => ref
                                      .read(taskRepositoryProvider)
                                      .pause(widget.task),
                                ),
                                icon: const Icon(Icons.pause),
                                label: const Text('Pause'),
                              ),
                            if (paused)
                              FilledButton.icon(
                                onPressed: () => _run(
                                  ref,
                                  () => ref
                                      .read(taskRepositoryProvider)
                                      .resume(widget.task),
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Resume'),
                              ),
                            if (isThisTask)
                              OutlinedButton.icon(
                                onPressed: () => _run(
                                  ref,
                                  () => ref
                                      .read(taskRepositoryProvider)
                                      .complete(widget.task),
                                ),
                                icon: const Icon(Icons.check),
                                label: const Text('Finish task'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _ExecutionModeExplanation(mode: widget.task.executionMode),
          ],
        );
      },
    );
  }
}

class _ChecklistPanel extends ConsumerWidget {
  const _ChecklistPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: entities.watch(entityType: 'checklist_items', parentId: task.id),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        final required = items.where(
          (item) => entities.decode(item)['is_required'] != false,
        );
        final completed = required.where(
          (item) => entities.decode(item)['is_completed'] == true,
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionHeader(
              title: 'Checklist and requirements',
              subtitle:
                  '${completed.length} of ${required.length} required items complete',
              actionLabel: 'Add item',
              icon: Icons.add,
              onAction: () => _addChecklistItem(context, ref, task, items),
            ),
            if (items.isEmpty)
              const _EmptyPanel(
                icon: Icons.checklist,
                title: 'No requirements yet',
                message:
                    'Add required or optional items. Checklist completion '
                    'never changes unrelated task evidence.',
              )
            else
              ...items.map((item) {
                final data = entities.decode(item);
                final checked = data['is_completed'] == true;
                return Card(
                  child: CheckboxListTile(
                    value: checked,
                    title: Text(
                      item.title,
                      style: TextStyle(
                        decoration: checked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(
                      data['is_required'] == false ? 'Optional' : 'Required',
                    ),
                    secondary: IconButton(
                      tooltip: 'Delete item',
                      onPressed: () async {
                        await entities.softDelete(item);
                        unawaited(ref.read(syncServiceProvider).drainOutbox());
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onChanged: (value) async {
                      data['is_completed'] = value == true;
                      data['completed_at'] = value == true
                          ? DateTime.now().toUtc().toIso8601String()
                          : null;
                      await entities.update(
                        item,
                        data: data,
                        syncPayload: {
                          'is_completed': value == true,
                          'completed_at': data['completed_at'],
                        },
                      );
                      unawaited(ref.read(syncServiceProvider).drainOutbox());
                    },
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _ResourcesPanel extends ConsumerWidget {
  const _ResourcesPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: entities.watch(entityType: 'task_resources', parentId: task.id),
      builder: (context, snapshot) {
        final resources = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionHeader(
              title: 'Resources and attachments',
              subtitle:
                  'Files are copied into app storage; private synchronized '
                  'files use your protected resource bucket',
              actionLabel: 'Add',
              icon: Icons.add,
              onAction: () => _showResourceActions(context, ref, task),
            ),
            if (resources.isEmpty)
              const _EmptyPanel(
                icon: Icons.folder_copy_outlined,
                title: 'This task has no resources',
                message:
                    'Attach PDFs, documents, spreadsheets, images, audio, '
                    'video, any other file, a URL, or a physical book.',
              )
            else
              ...resources.map(
                (resource) => _ResourceTile(task: task, resource: resource),
              ),
          ],
        );
      },
    );
  }
}

class _ResourceTile extends ConsumerWidget {
  const _ResourceTile({required this.task, required this.resource});

  final LocalTask task;
  final LocalEntityRecord resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    final data = entities.decode(resource);
    final type = data['resource_type'] as String? ?? 'file';
    final path = data['local_path'] as String?;
    final available = path == null || File(path).existsSync();
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_resourceIcon(type))),
        title: Text(resource.title),
        subtitle: Text(
          [
            _titleCase(type),
            if (data['author'] case final String author when author.isNotEmpty)
              author,
            if (data['pending_upload'] == true) 'Waiting to upload',
            if (!available) 'Unavailable on this device',
          ].join(' · '),
        ),
        onTap: () => _openResource(context, ref, task, resource, data),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'open_external') {
              await ref.read(taskResourceServiceProvider).open(resource);
            } else if (action == 'delete') {
              await entities.softDelete(resource);
            }
          },
          itemBuilder: (_) => [
            if (type != 'url' && type != 'book')
              const PopupMenuItem(
                value: 'open_external',
                child: Text('Open externally'),
              ),
            const PopupMenuItem(value: 'delete', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}

class _ConnectionsPanel extends ConsumerWidget {
  const _ConnectionsPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          title: 'Task connections',
          subtitle:
              'Relationships stay separate from execution mode and are visible '
              'from both the task and roadmap',
        ),
        _RoadmapConnectionCard(task: task),
        const SizedBox(height: 12),
        _ConnectionList(
          title: 'Dependency tasks',
          subtitle: 'Tasks this work depends on or blocks',
          icon: Icons.account_tree_outlined,
          stream: entities.watch(
            entityType: 'task_dependencies',
            parentId: task.id,
          ),
          entities: entities,
          addLabel: 'Connect task',
          onAdd: () => _addDependency(context, ref, task),
        ),
        const SizedBox(height: 12),
        _ConnectionList(
          title: 'Applications',
          subtitle:
              'Rules can recognize activity without silently completing work',
          icon: Icons.apps,
          stream: entities.watch(
            entityType: 'application_rules',
            parentId: task.id,
          ),
          entities: entities,
          addLabel: 'Add application',
          onAdd: () => _addApplication(context, ref, task),
        ),
        const SizedBox(height: 12),
        _ConnectionList(
          title: 'Websites',
          subtitle: 'Task-specific domain rules override broader rules',
          icon: Icons.public,
          stream: entities.watch(
            entityType: 'website_rules',
            parentId: task.id,
          ),
          entities: entities,
          addLabel: 'Add website',
          onAdd: () => _addWebsite(context, ref, task),
        ),
      ],
    );
  }
}

class _NotesPanel extends ConsumerWidget {
  const _NotesPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: entities.watch(entityType: 'task_notes', parentId: task.id),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionHeader(
              title: 'Task notes',
              subtitle:
                  'Notes retain independent versions so conflicting copies can '
                  'be preserved during offline reconciliation',
              actionLabel: 'Add note',
              icon: Icons.add,
              onAction: () => _addNote(context, ref, task),
            ),
            if (notes.isEmpty)
              const _EmptyPanel(
                icon: Icons.notes_outlined,
                title: 'No notes yet',
                message: 'Record decisions, context, evidence or next steps.',
              )
            else
              ...notes.reversed.map((note) {
                final data = entities.decode(note);
                return Card(
                  child: ListTile(
                    title: Text(data['body'] as String? ?? note.title),
                    subtitle: Text(
                      'Version ${(data['note_version'] as num?)?.toInt() ?? 1} · '
                      '${DateFormat.yMMMd().add_jm().format(note.updatedAt.toLocal())}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete note',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => entities.softDelete(note),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _HistoryPanel extends ConsumerWidget {
  const _HistoryPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    return FutureBuilder<List<List<LocalEntityRecord>>>(
      future: Future.wait([
        entities.list(entityType: 'session_events', parentId: task.id),
        entities.list(entityType: 'interruptions', parentId: task.id),
        entities.list(entityType: 'task_notes', parentId: task.id),
        entities.list(entityType: 'activity_contributions', parentId: task.id),
      ]),
      builder: (context, snapshot) {
        final records = snapshot.data?.expand((items) => items).toList() ?? [];
        records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _SectionHeader(
              title: 'Execution and evidence history',
              subtitle:
                  'Planned state, actual task changes, notes, interruptions and '
                  'approved contributions remain distinguishable',
            ),
            Card(
              child: Column(
                children: [
                  _HistoryRow(
                    icon: Icons.add_task,
                    title: 'Task created',
                    time: task.createdAt,
                  ),
                  if (task.actualStart != null)
                    _HistoryRow(
                      icon: Icons.play_arrow,
                      title: 'First started',
                      time: task.actualStart!,
                    ),
                  if (task.actualFinish != null)
                    _HistoryRow(
                      icon: Icons.check,
                      title: 'Completed',
                      time: task.actualFinish!,
                    ),
                  for (final record in records)
                    _HistoryRow(
                      icon: _historyIcon(record.entityType),
                      title: record.title.isEmpty
                          ? _titleCase(record.entityType.replaceAll('_', ' '))
                          : record.title,
                      time: record.updatedAt,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TaskSettingsPanel extends ConsumerWidget {
  const _TaskSettingsPanel({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(entityRecordRepositoryProvider);
    final configuration =
        (jsonDecode(task.dataJson) as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final keepWorkspace =
        configuration['browser_persistence_mode'] != 'start_clean';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _SectionHeader(
          title: 'Task settings',
          subtitle:
              'Planning, reminders, completion and workspace behavior remain '
              'editable for this occurrence',
          actionLabel: 'Edit task',
          icon: Icons.edit_outlined,
          onAction: () => TaskEditorDialog.show(context, task: task),
        ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: keepWorkspace,
                onChanged: (value) async {
                  final updated = Map<String, Object?>.from(configuration);
                  updated['browser_persistence_mode'] = value
                      ? 'keep_all'
                      : 'start_clean';
                  await ref
                      .read(taskRepositoryProvider)
                      .updateConfiguration(task, updated);
                  unawaited(ref.read(syncServiceProvider).drainOutbox());
                },
                title: const Text('Keep browser workspace'),
                subtitle: const Text(
                  'Pinned tabs and task-specific browser metadata persist',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Reminders'),
                subtitle: const Text(
                  'Local notifications continue offline and use the selected sound',
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => _addReminder(context, ref, task),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<LocalEntityRecord>>(
          stream: entities.watch(
            entityType: 'task_reminders',
            parentId: task.id,
          ),
          builder: (context, snapshot) {
            final reminders = snapshot.data ?? const [];
            if (reminders.isEmpty) {
              return const _EmptyPanel(
                icon: Icons.notifications_off_outlined,
                title: 'No task reminders',
                message:
                    'Add before-start, start, planned-end, due, overdue or missed-task reminders.',
              );
            }
            return Column(
              children: [
                for (final reminder in reminders)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(reminder.title),
                      subtitle: Text(
                        _formatReminder(entities.decode(reminder), context),
                      ),
                      trailing: IconButton(
                        onPressed: () => entities.softDelete(reminder),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RoadmapConnectionCard extends ConsumerWidget {
  const _RoadmapConnectionCard({required this.task});

  final LocalTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<LocalRoadmap>>(
      stream: ref.watch(roadmapRepositoryProvider).watchRoadmaps(),
      builder: (context, snapshot) {
        final roadmaps = snapshot.data ?? const [];
        final current = roadmaps
            .where((roadmap) => roadmap.id == task.roadmapId)
            .firstOrNull;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.route_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Roadmap and phase',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            current?.title ?? 'Not linked to a roadmap',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (current != null)
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                RoadmapDetailScreen(roadmapId: current.id),
                          ),
                        ),
                        child: const Text('Open roadmap'),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: current?.id,
                  decoration: const InputDecoration(
                    labelText: 'Roadmap',
                    prefixIcon: Icon(Icons.route_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No roadmap'),
                    ),
                    for (final roadmap in roadmaps)
                      DropdownMenuItem(
                        value: roadmap.id,
                        child: Text(roadmap.title),
                      ),
                  ],
                  onChanged: (roadmapId) async {
                    await ref
                        .read(taskRepositoryProvider)
                        .updateRelationships(
                          task,
                          roadmapId: roadmapId,
                          roadmapPhaseId: null,
                        );
                    unawaited(ref.read(syncServiceProvider).drainOutbox());
                  },
                ),
                if (current != null) ...[
                  const SizedBox(height: 12),
                  StreamBuilder<List<LocalEntityRecord>>(
                    stream: ref
                        .watch(roadmapRepositoryProvider)
                        .watchPhases(current.id),
                    builder: (context, phaseSnapshot) {
                      final phases = phaseSnapshot.data ?? const [];
                      return DropdownButtonFormField<String?>(
                        initialValue:
                            phases.any(
                              (phase) => phase.id == task.roadmapPhaseId,
                            )
                            ? task.roadmapPhaseId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Roadmap phase',
                          prefixIcon: Icon(Icons.view_timeline_outlined),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Roadmap level'),
                          ),
                          for (final phase in phases)
                            DropdownMenuItem(
                              value: phase.id,
                              child: Text(phase.title),
                            ),
                        ],
                        onChanged: (phaseId) async {
                          await ref
                              .read(taskRepositoryProvider)
                              .updateRelationships(
                                task,
                                roadmapId: current.id,
                                roadmapPhaseId: phaseId,
                              );
                          unawaited(
                            ref.read(syncServiceProvider).drainOutbox(),
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionList extends StatelessWidget {
  const _ConnectionList({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.stream,
    required this.entities,
    required this.addLabel,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Stream<List<LocalEntityRecord>> stream;
  final EntityRecordRepository entities;
  final String addLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: stream,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const [];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Icon(icon)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: Text(addLabel),
                    ),
                  ],
                ),
                if (records.isNotEmpty) ...[
                  const Divider(height: 24),
                  for (final record in records)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(record.title),
                      subtitle: Text(
                        _connectionDescription(entities.decode(record)),
                      ),
                      trailing: IconButton(
                        tooltip: 'Remove connection',
                        onPressed: () => entities.softDelete(record),
                        icon: const Icon(Icons.link_off),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.icon,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData? icon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onAction != null && actionLabel != null)
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: Icon(icon ?? Icons.add),
              label: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 205,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _WorkspaceShortcut extends StatelessWidget {
  const _WorkspaceShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExecutionModeExplanation extends StatelessWidget {
  const _ExecutionModeExplanation({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final content = switch (mode) {
      'pomodoro' =>
        'Focus and break segments are distinct. A break can still contain '
            'useful activity credited to another task without duplicating time.',
      'continuous' =>
        'The session measures active, paused, idle, remaining and overtime '
            'without forcing artificial cycles.',
      'checklist' =>
        'Time is supporting evidence; completion follows required checklist rules.',
      'reading' =>
        'Reading duration, unique pages, rereads, saved positions and notes '
            'are tracked independently.',
      'habit' =>
        'Habit outcomes retain completed, skipped and missed states with recovery context.',
      'event' =>
        'Arrival, start, finish, lateness, attendance and follow-up are tracked separately.',
      'hybrid' =>
        'Timer, checklist, checkpoints, resources and evidence can work together.',
      _ =>
        'Manual completion remains available while notes, resources and evidence are retained.',
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text('${_titleCase(mode)} execution'),
        subtitle: Text(content),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.icon,
    required this.title,
    required this.time,
  });

  final IconData icon;
  final String title;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(DateFormat.yMMMd().add_jm().format(time.toLocal())),
    );
  }
}

Future<void> _run(WidgetRef ref, Future<void> Function() action) async {
  await action();
  unawaited(ref.read(syncServiceProvider).drainOutbox());
}

Future<void> _addChecklistItem(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
  List<LocalEntityRecord> existing,
) async {
  final result = await _textAndToggleDialog(
    context,
    title: 'Add checklist item',
    label: 'Requirement',
    toggleLabel: 'Required for completion',
  );
  if (result == null || result.$1.trim().isEmpty) return;
  await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'checklist_items',
          parentId: task.id,
          title: result.$1,
          position: existing.length.toDouble(),
          data: {
            'task_occurrence_id': task.id,
            'description': '',
            'is_required': result.$2,
            'is_completed': false,
            'weight': 1,
          },
          syncPayload: {
            'task_template_id': null,
            'task_occurrence_id': task.id,
            'title': result.$1,
            'description': '',
            'is_required': result.$2,
            'is_completed': false,
            'completed_at': null,
            'due_at': null,
            'weight': 1,
            'position': existing.length,
            'evidence': <Object?>[],
          },
        ),
      );
  unawaited(ref.read(syncServiceProvider).drainOutbox());
}

Future<void> _showResourceActions(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('Attach files'),
            subtitle: const Text(
              'PDF, document, spreadsheet, image, audio, video or any file',
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              await ref
                  .read(taskResourceServiceProvider)
                  .pickAndAddFiles(taskId: task.id, synchronizeFiles: true);
              unawaited(ref.read(syncServiceProvider).drainOutbox());
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Add URL'),
            subtitle: const Text('Open in the task browser or externally'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final value = await _askText(
                context,
                title: 'Add web resource',
                label: 'URL',
                hint: 'https://example.com/resource',
              );
              if (value == null || value.trim().isEmpty) return;
              await ref
                  .read(taskResourceServiceProvider)
                  .addUrl(taskId: task.id, url: value);
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Add book or reading target'),
            subtitle: const Text(
              'Physical books can track pages, duration and last position',
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _addBook(context, ref, task);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _openResource(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
  LocalEntityRecord resource,
  Map<String, Object?> data,
) async {
  final type = data['resource_type'] as String? ?? 'file';
  if (type == 'pdf') {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TaskDocumentWorkspace(task: task, resource: resource),
      ),
    );
  } else if (type == 'url') {
    final value =
        data['url'] as String? ?? data['storage_path'] as String? ?? '';
    final uri = Uri.tryParse(value);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } else if (type == 'book') {
    await _updateReadingPosition(context, ref, task, resource);
  } else {
    await ref.read(taskResourceServiceProvider).open(resource);
  }
}

Future<void> _addBook(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final title = TextEditingController();
  final author = TextEditingController();
  final pages = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add book'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: author,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pages,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total pages (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add book'),
        ),
      ],
    ),
  );
  if (saved == true && title.text.trim().isNotEmpty) {
    await ref
        .read(taskResourceServiceProvider)
        .addBook(
          taskId: task.id,
          title: title.text,
          author: author.text,
          totalPages: int.tryParse(pages.text),
        );
  }
  title.dispose();
  author.dispose();
  pages.dispose();
}

Future<void> _updateReadingPosition(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
  LocalEntityRecord resource,
) async {
  final entities = ref.read(entityRecordRepositoryProvider);
  final targets = await entities.list(
    entityType: 'reading_targets',
    parentId: task.id,
    secondaryParentId: resource.id,
  );
  if (targets.isEmpty || !context.mounted) return;
  final target = targets.first;
  final targetData = entities.decode(target);
  final controller = TextEditingController(
    text: ((targetData['current_page'] as num?)?.toInt() ?? 1).toString(),
  );
  final result = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Update ${resource.title}'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Current page'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, int.tryParse(controller.text)),
          child: const Text('Save progress'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result <= 0) return;
  final uniquePages = List<int>.from(
    (targetData['unique_pages'] as List?)?.whereType<num>().map(
          (value) => value.toInt(),
        ) ??
        const <int>[],
  );
  final previous = (targetData['current_page'] as num?)?.toInt() ?? 1;
  for (var page = previous + 1; page <= result; page++) {
    if (!uniquePages.contains(page)) uniquePages.add(page);
  }
  targetData['current_page'] = result;
  targetData['unique_pages'] = uniquePages;
  await entities.update(target, data: targetData, synchronize: false);
  final now = DateTime.now().toUtc().toIso8601String();
  await entities.create(
    EntityRecordDraft(
      entityType: 'reading_positions',
      parentId: task.id,
      secondaryParentId: resource.id,
      title: '${resource.title} · page $result',
      data: {
        'reading_target_id': target.id,
        'resource_id': resource.id,
        'page_number': result,
        'unique_pages': uniquePages,
        'reread_pages': <int>[],
        'reading_duration_ms': 0,
        'recorded_at': now,
      },
      syncPayload: {
        'reading_target_id': target.id,
        'resource_id': resource.id,
        'page_number': result,
        'position_value': 'page:$result',
        'unique_pages': uniquePages,
        'reread_pages': <int>[],
        'reading_duration_ms': 0,
        'recorded_at': now,
      },
    ),
  );
}

Future<void> _addDependency(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final tasks = await ref.read(taskRepositoryProvider).watchTasks().first;
  if (!context.mounted) return;
  var relation = 'blocks';
  final selected = await showDialog<LocalTask>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Connect another task'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: relation,
                decoration: const InputDecoration(labelText: 'Relationship'),
                items: const [
                  DropdownMenuItem(
                    value: 'blocks',
                    child: Text('This task depends on'),
                  ),
                  DropdownMenuItem(
                    value: 'related',
                    child: Text('Related work'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => relation = value ?? relation),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    for (final candidate in tasks)
                      if (candidate.id != task.id)
                        ListTile(
                          title: Text(candidate.title),
                          subtitle: Text(_titleCase(candidate.status)),
                          onTap: () => Navigator.pop(context, candidate),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (selected == null) return;
  await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'task_dependencies',
          parentId: task.id,
          secondaryParentId: selected.id,
          title: selected.title,
          status: relation,
          data: {
            'task_occurrence_id': task.id,
            'depends_on_task_id': selected.id,
            'dependency_type': relation,
          },
          syncPayload: {
            'task_occurrence_id': task.id,
            'depends_on_task_id': selected.id,
            'dependency_type': relation,
          },
        ),
      );
}

Future<void> _addApplication(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final identifier = await _askText(
    context,
    title: 'Connect application',
    label: 'Application name or executable',
    hint: 'Visual Studio Code or Code.exe',
  );
  if (identifier == null || identifier.trim().isEmpty) return;
  final entities = ref.read(entityRecordRepositoryProvider);
  final applicationId = await entities.create(
    EntityRecordDraft(
      entityType: 'application_catalog',
      title: identifier.trim(),
      status: 'known',
      data: {
        'platform': Platform.isAndroid ? 'android' : 'windows',
        'application_identifier': identifier.trim(),
        'display_name': identifier.trim(),
        'classification': 'direct_task_work',
      },
      syncPayload: {
        'platform': Platform.isAndroid ? 'android' : 'windows',
        'application_identifier': identifier.trim(),
        'display_name': identifier.trim(),
        'publisher': null,
        'icon_path': null,
        'classification': 'direct_task_work',
        'first_seen_at': DateTime.now().toUtc().toIso8601String(),
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      },
    ),
  );
  await entities.create(
    EntityRecordDraft(
      entityType: 'application_rules',
      parentId: task.id,
      secondaryParentId: applicationId,
      title: identifier.trim(),
      status: 'proposed',
      data: {
        'application_id': applicationId,
        'scope_type': 'task',
        'scope_id': task.id,
        'classification': 'direct_task_work',
        'target_type': 'task_occurrence',
        'target_id': task.id,
        'contribution_type': 'active_work_seconds',
        'automatic_credit': false,
        'priority': 100,
      },
      syncPayload: {
        'application_id': applicationId,
        'scope_type': 'task',
        'scope_id': task.id,
        'classification': 'direct_task_work',
        'target_type': 'task_occurrence',
        'target_id': task.id,
        'contribution_type': 'active_work_seconds',
        'automatic_credit': false,
        'priority': 100,
      },
    ),
  );
}

Future<void> _addWebsite(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final value = await _askText(
    context,
    title: 'Connect website',
    label: 'Domain or URL',
    hint: 'docs.flutter.dev',
  );
  if (value == null || value.trim().isEmpty) return;
  final raw = value.trim();
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  if (uri == null || uri.host.isEmpty) return;
  await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'website_rules',
          parentId: task.id,
          title: uri.host,
          status: 'proposed',
          data: {
            'domain': uri.host,
            'scope_type': 'task',
            'scope_id': task.id,
            'classification': 'direct_task_work',
            'target_type': 'task_occurrence',
            'target_id': task.id,
            'contribution_type': 'active_work_seconds',
            'automatic_credit': false,
            'priority': 100,
          },
          syncPayload: {
            'domain': uri.host,
            'url_pattern': null,
            'scope_type': 'task',
            'scope_id': task.id,
            'classification': 'direct_task_work',
            'target_type': 'task_occurrence',
            'target_id': task.id,
            'contribution_type': 'active_work_seconds',
            'automatic_credit': false,
            'priority': 100,
          },
        ),
      );
}

Future<void> _addNote(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final body = await _askText(
    context,
    title: 'Add task note',
    label: 'Note',
    hint: 'Decision, evidence, context or next step',
    lines: 5,
  );
  if (body == null || body.trim().isEmpty) return;
  await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'task_notes',
          parentId: task.id,
          title: body.trim().split('\n').first,
          data: {
            'task_occurrence_id': task.id,
            'body': body.trim(),
            'note_version': 1,
          },
          syncPayload: {
            'task_occurrence_id': task.id,
            'task_template_id': null,
            'session_id': null,
            'body': body.trim(),
            'note_version': 1,
            'conflicting_copy_of': null,
          },
        ),
      );
}

Future<void> _addReminder(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  var type = 'before_start';
  var date =
      task.plannedStart?.toLocal() ??
      task.scheduledDate?.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  var sound = 'system';
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add task reminder'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Reminder type'),
                items: const [
                  DropdownMenuItem(
                    value: 'before_start',
                    child: Text('Before start'),
                  ),
                  DropdownMenuItem(
                    value: 'start',
                    child: Text('At planned start'),
                  ),
                  DropdownMenuItem(
                    value: 'planned_end',
                    child: Text('At planned end'),
                  ),
                  DropdownMenuItem(value: 'due', child: Text('Due reminder')),
                  DropdownMenuItem(
                    value: 'overdue',
                    child: Text('Overdue reminder'),
                  ),
                  DropdownMenuItem(
                    value: 'missed',
                    child: Text('Missed-task reminder'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => type = value ?? type),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Local date and time'),
                subtitle: Text(DateFormat.yMMMd().add_jm().format(date)),
                onTap: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (day == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(date),
                  );
                  if (time == null) return;
                  setDialogState(() {
                    date = DateTime(
                      day.year,
                      day.month,
                      day.day,
                      time.hour,
                      time.minute,
                    );
                  });
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: sound,
                decoration: const InputDecoration(labelText: 'Sound'),
                items: const [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text('Android / system default'),
                  ),
                  DropdownMenuItem(
                    value: 'selected',
                    child: Text('TaskMaster Pro selected sound'),
                  ),
                  DropdownMenuItem(value: 'silent', child: Text('Silent')),
                ],
                onChanged: (value) =>
                    setDialogState(() => sound = value ?? sound),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Schedule'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final utc = date.toUtc().toIso8601String();
  final reminderId = await ref
      .read(entityRecordRepositoryProvider)
      .create(
        EntityRecordDraft(
          entityType: 'task_reminders',
          parentId: task.id,
          title: '${_titleCase(type.replaceAll('_', ' '))} reminder',
          status: 'enabled',
          data: {
            'task_occurrence_id': task.id,
            'reminder_type': type,
            'scheduled_at': utc,
            'sound_key': sound,
            'enabled': true,
          },
          syncPayload: {
            'task_template_id': null,
            'task_occurrence_id': task.id,
            'reminder_type': type,
            'scheduled_at': utc,
            'offset_ms': null,
            'repeat_rule': <String, Object?>{},
            'sound_key': sound,
            'enabled': true,
          },
        ),
      );
  final selectedSoundKey =
      ref.read(appSettingsProvider).value?.notificationSoundKey ?? 'system';
  final effectiveSoundKey = switch (sound) {
    'selected' => selectedSoundKey,
    _ => sound,
  };
  await localNotificationService.requestPermission();
  await localNotificationService.scheduleTaskReminder(
    id: reminderId.hashCode & 0x7fffffff,
    taskId: task.id,
    taskTitle: task.title,
    reminderType: type,
    scheduledAtUtc: date.toUtc(),
    sound: NotificationSounds.byKey(effectiveSoundKey),
  );
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  int lines = 1,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: lines == 1
              ? (value) => Navigator.pop(context, value)
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<(String, bool)?> _textAndToggleDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String toggleLabel,
}) async {
  final controller = TextEditingController();
  var enabled = true;
  final result = await showDialog<(String, bool)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: label),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: Text(toggleLabel),
                onChanged: (value) => setDialogState(() => enabled = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, (controller.text, enabled)),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

String _formatReminder(Map<String, Object?> data, BuildContext context) {
  final value = DateTime.tryParse(data['scheduled_at'] as String? ?? '');
  return [
    if (value != null)
      DateFormat.yMMMd().add_jm().format(value.toLocal())
    else
      'No time',
    data['sound_key'] as String? ?? 'system',
  ].join(' · ');
}

String _connectionDescription(Map<String, Object?> data) {
  return [
    data['classification'],
    if (data['dependency_type'] != null) data['dependency_type'],
    if (data['automatic_credit'] == true)
      'automatic credit'
    else if (data.containsKey('automatic_credit'))
      'confirmation required',
  ].whereType<Object>().join(' · ');
}

IconData _resourceIcon(String type) {
  return switch (type) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'book' => Icons.menu_book_outlined,
    'url' => Icons.link,
    'image' => Icons.image_outlined,
    'audio' => Icons.audio_file_outlined,
    'video' => Icons.video_file_outlined,
    'spreadsheet' => Icons.table_chart_outlined,
    'document' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

IconData _historyIcon(String type) {
  return switch (type) {
    'task_notes' => Icons.notes_outlined,
    'interruptions' => Icons.warning_amber,
    'activity_contributions' => Icons.call_merge,
    _ => Icons.bolt,
  };
}

String _titleCase(String input) {
  if (input.isEmpty) return input;
  return input
      .split(RegExp(r'[_ ]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _duration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${duration.inMinutes}m';
}

String _clock(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String _priority(int value) {
  return switch (value) {
    4 => 'Critical',
    3 => 'High',
    2 => 'Important',
    1 => 'Normal',
    _ => 'Low',
  };
}
