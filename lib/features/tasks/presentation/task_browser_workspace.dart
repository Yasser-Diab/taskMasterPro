import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import 'cross_platform_webview.dart';

Map<String, Object?> _tabVisitPayload({
  required String? url,
  required String? title,
  required Object? lastVisitedAt,
}) {
  final payload = <String, Object?>{'last_visited_at': lastVisitedAt};
  if (url != null) payload['url'] = url;
  if (title != null) payload['title'] = title;
  return payload;
}

class TaskBrowserWorkspace extends ConsumerStatefulWidget {
  const TaskBrowserWorkspace({required this.task, super.key});

  final LocalTask task;

  @override
  ConsumerState<TaskBrowserWorkspace> createState() =>
      _TaskBrowserWorkspaceState();
}

class _TaskBrowserWorkspaceState extends ConsumerState<TaskBrowserWorkspace> {
  final _address = TextEditingController();
  final _browser = TaskBrowserController();
  String? _workspaceId;
  String? _selectedTabId;
  bool _initializing = true;
  String? _error;
  Timer? _metadataDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureWorkspace());
  }

  @override
  void dispose() {
    _metadataDebounce?.cancel();
    _address.dispose();
    super.dispose();
  }

  Future<void> _ensureWorkspace() async {
    final entities = ref.read(entityRecordRepositoryProvider);
    try {
      final workspaces = await entities.list(
        entityType: 'browser_workspaces',
        parentId: widget.task.id,
      );
      final workspaceId = workspaces.isEmpty
          ? await entities.create(
              EntityRecordDraft(
                entityType: 'browser_workspaces',
                parentId: widget.task.id,
                title: '${widget.task.title} workspace',
                data: {
                  'task_occurrence_id': widget.task.id,
                  'persistence_mode': 'keep_pinned',
                  'search_engine': 'google',
                },
                syncPayload: {
                  'task_occurrence_id': widget.task.id,
                  'task_template_id': null,
                  'title': '${widget.task.title} workspace',
                  'persistence_mode': 'keep_pinned',
                  'selected_tab_id': null,
                  'search_engine': 'google',
                },
              ),
            )
          : workspaces.first.id;
      var tabs = await entities.list(
        entityType: 'browser_tabs',
        parentId: workspaceId,
      );
      if (tabs.isEmpty) {
        final id = await _createTab(
          workspaceId: workspaceId,
          url: 'https://www.google.com',
          selected: true,
        );
        tabs = [(await entities.get(id))!];
      }
      final selected =
          tabs.where((tab) => _data(tab)['is_selected'] == true).firstOrNull ??
          tabs.first;
      if (!mounted) return;
      setState(() {
        _workspaceId = workspaceId;
        _selectedTabId = selected.id;
        _address.text =
            _data(selected)['url'] as String? ?? 'https://www.google.com';
        _initializing = false;
      });
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    } catch (error) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = error.toString();
        });
      }
    }
  }

  Map<String, Object?> _data(LocalEntityRecord record) {
    return ref.read(entityRecordRepositoryProvider).decode(record);
  }

  Future<String> _createTab({
    required String workspaceId,
    required String url,
    bool selected = false,
    double position = 0,
    bool pinned = false,
  }) {
    return ref
        .read(entityRecordRepositoryProvider)
        .create(
          EntityRecordDraft(
            entityType: 'browser_tabs',
            parentId: workspaceId,
            title: url,
            position: position,
            data: {
              'workspace_id': workspaceId,
              'url': url,
              'title': url,
              'position': position,
              'is_pinned': pinned,
              'is_selected': selected,
              'last_visited_at': DateTime.now().toUtc().toIso8601String(),
            },
            syncPayload: {
              'workspace_id': workspaceId,
              'url': url,
              'title': url,
              'custom_title': null,
              'position': position,
              'is_pinned': pinned,
              'is_selected': selected,
              'last_visited_at': DateTime.now().toUtc().toIso8601String(),
            },
          ),
        );
  }

  Future<void> _selectTab(
    LocalEntityRecord selected,
    List<LocalEntityRecord> tabs,
  ) async {
    if (_selectedTabId == selected.id) return;
    final entities = ref.read(entityRecordRepositoryProvider);
    for (final tab in tabs) {
      final data = _data(tab);
      final shouldSelect = tab.id == selected.id;
      if (data['is_selected'] == shouldSelect) continue;
      data['is_selected'] = shouldSelect;
      await entities.update(
        tab,
        data: data,
        syncPayload: {'is_selected': shouldSelect},
      );
    }
    final data = _data(selected);
    setState(() {
      _selectedTabId = selected.id;
      _address.text = data['url'] as String? ?? 'https://www.google.com';
    });
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  Future<void> _newTab(List<LocalEntityRecord> tabs) async {
    final id = await _createTab(
      workspaceId: _workspaceId!,
      url: 'https://www.google.com',
      selected: true,
      position: tabs.length.toDouble(),
    );
    final entities = ref.read(entityRecordRepositoryProvider);
    for (final tab in tabs) {
      final data = _data(tab)..['is_selected'] = false;
      await entities.update(
        tab,
        data: data,
        syncPayload: const {'is_selected': false},
      );
    }
    if (mounted) {
      setState(() {
        _selectedTabId = id;
        _address.text = 'https://www.google.com';
      });
    }
  }

  Future<void> _closeTab(
    LocalEntityRecord tab,
    List<LocalEntityRecord> tabs,
  ) async {
    final data = _data(tab);
    if (data['is_pinned'] == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close pinned tab?'),
          content: const Text('This tab is marked to remain with the task'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep tab'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final entities = ref.read(entityRecordRepositoryProvider);
    await entities.create(
      EntityRecordDraft(
        entityType: 'browser_closed_tabs',
        parentId: _workspaceId,
        title:
            data['title'] as String? ?? data['url'] as String? ?? 'Closed tab',
        data: {
          'workspace_id': _workspaceId,
          'url': data['url'],
          'title': data['title'],
          'was_pinned': data['is_pinned'] == true,
          'previous_position': tab.position,
          'closed_at': DateTime.now().toUtc().toIso8601String(),
        },
        syncPayload: {
          'workspace_id': _workspaceId,
          'url': data['url'],
          'title': data['title'],
          'was_pinned': data['is_pinned'] == true,
          'previous_position': tab.position,
          'closed_at': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
    await entities.softDelete(tab);
    final remaining = tabs.where((item) => item.id != tab.id).toList();
    if (remaining.isEmpty) {
      await _newTab(const []);
    } else if (_selectedTabId == tab.id) {
      await _selectTab(remaining.last, remaining);
    }
  }

  void _scheduleMetadataUpdate(
    LocalEntityRecord tab, {
    String? url,
    String? title,
  }) {
    _metadataDebounce?.cancel();
    _metadataDebounce = Timer(const Duration(milliseconds: 700), () async {
      final latest = await ref.read(entityRecordRepositoryProvider).get(tab.id);
      if (latest == null) return;
      final data = _data(latest);
      if (url != null) data['url'] = url;
      if (title != null && title.trim().isNotEmpty) data['title'] = title;
      data['last_visited_at'] = DateTime.now().toUtc().toIso8601String();
      await ref
          .read(entityRecordRepositoryProvider)
          .update(
            latest,
            title: data['title'] as String? ?? data['url'] as String?,
            data: data,
            syncPayload: _tabVisitPayload(
              url: url,
              title: title,
              lastVisitedAt: data['last_visited_at'],
            ),
          );
      if (url != null) {
        await ref
            .read(entityRecordRepositoryProvider)
            .create(
              EntityRecordDraft(
                entityType: 'browser_history_events',
                parentId: _workspaceId,
                secondaryParentId: tab.id,
                title: title ?? url,
                data: {
                  'workspace_id': _workspaceId,
                  'tab_id': tab.id,
                  'url': url,
                  'title': title,
                  'visited_at': DateTime.now().toUtc().toIso8601String(),
                  'duration_ms': 0,
                  'device_event_id':
                      '${tab.id}:${DateTime.now().microsecondsSinceEpoch}',
                },
                syncPayload: {
                  'workspace_id': _workspaceId,
                  'tab_id': tab.id,
                  'url': url,
                  'title': title,
                  'visited_at': DateTime.now().toUtc().toIso8601String(),
                  'duration_ms': 0,
                  'device_event_id':
                      '${tab.id}:${DateTime.now().microsecondsSinceEpoch}',
                },
              ),
            );
      }
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    });
  }

  Future<void> _addBookmark(LocalEntityRecord tab) async {
    final data = _data(tab);
    await ref
        .read(entityRecordRepositoryProvider)
        .create(
          EntityRecordDraft(
            entityType: 'browser_bookmarks',
            parentId: _workspaceId,
            secondaryParentId: widget.task.id,
            title: data['title'] as String? ?? data['url'] as String? ?? '',
            data: {
              'workspace_id': _workspaceId,
              'task_occurrence_id': widget.task.id,
              'url': data['url'],
              'title': data['title'],
              'position': 0,
            },
            syncPayload: {
              'workspace_id': _workspaceId,
              'task_occurrence_id': widget.task.id,
              'url': data['url'],
              'title': data['title'],
              'position': 0,
            },
          ),
        );
  }

  Future<void> _rememberWebsite(LocalEntityRecord tab) async {
    final data = _data(tab);
    final uri = Uri.tryParse(data['url'] as String? ?? '');
    if (uri == null || uri.host.isEmpty) return;
    await ref
        .read(entityRecordRepositoryProvider)
        .create(
          EntityRecordDraft(
            entityType: 'website_rules',
            parentId: widget.task.id,
            title: uri.host,
            status: 'trusted',
            data: {
              'domain': uri.host,
              'scope_type': 'task',
              'scope_id': widget.task.id,
              'classification': 'direct_task_work',
              'target_type': 'task_occurrence',
              'target_id': widget.task.id,
              'contribution_type': 'active_work_seconds',
              'automatic_credit': false,
              'priority': 100,
            },
            syncPayload: {
              'domain': uri.host,
              'url_pattern': null,
              'scope_type': 'task',
              'scope_id': widget.task.id,
              'classification': 'direct_task_work',
              'target_type': 'task_occurrence',
              'target_id': widget.task.id,
              'contribution_type': 'active_work_seconds',
              'automatic_credit': false,
              'priority': 100,
            },
          ),
        );
  }

  Future<void> _renameTab(LocalEntityRecord tab) async {
    final current = _data(tab);
    final controller = TextEditingController(
      text:
          current['custom_title'] as String? ??
          current['title'] as String? ??
          '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename task tab'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Custom title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    current['custom_title'] = value.isEmpty ? null : value;
    await ref
        .read(entityRecordRepositoryProvider)
        .update(
          tab,
          data: current,
          syncPayload: {'custom_title': current['custom_title']},
        );
  }

  Future<void> _closeOtherTabs(
    LocalEntityRecord selected,
    List<LocalEntityRecord> tabs,
  ) async {
    for (final tab in tabs) {
      if (tab.id == selected.id) continue;
      await _closeTab(tab, tabs);
    }
  }

  Future<void> _reopenClosedTab() async {
    final entities = ref.read(entityRecordRepositoryProvider);
    final closed = await entities.list(
      entityType: 'browser_closed_tabs',
      parentId: _workspaceId,
    );
    if (closed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No recently closed tab')));
      }
      return;
    }
    final latest = closed.last;
    final data = _data(latest);
    final id = await _createTab(
      workspaceId: _workspaceId!,
      url: data['url'] as String? ?? 'https://www.google.com',
      selected: true,
      position: (data['previous_position'] as num?)?.toDouble() ?? 0,
      pinned: data['was_pinned'] == true,
    );
    final tabs = await entities.list(
      entityType: 'browser_tabs',
      parentId: _workspaceId,
    );
    for (final tab in tabs) {
      if (tab.id == id) continue;
      final tabData = _data(tab)..['is_selected'] = false;
      await entities.update(
        tab,
        data: tabData,
        syncPayload: const {'is_selected': false},
      );
    }
    await entities.softDelete(latest);
    if (mounted) setState(() => _selectedTabId = id);
  }

  Future<void> _moveTabToTask(LocalEntityRecord tab) async {
    final tasks = await ref.read(taskRepositoryProvider).watchTasks().first;
    if (!mounted) return;
    final target = await showDialog<LocalTask>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move tab to another task'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: ListView(
            children: [
              for (final task in tasks)
                if (task.id != widget.task.id)
                  ListTile(
                    leading: const Icon(Icons.task_alt_outlined),
                    title: Text(task.title),
                    subtitle: Text(task.status.replaceAll('_', ' ')),
                    onTap: () => Navigator.pop(context, task),
                  ),
            ],
          ),
        ),
      ),
    );
    if (target == null) return;
    final entities = ref.read(entityRecordRepositoryProvider);
    final workspaces = await entities.list(
      entityType: 'browser_workspaces',
      parentId: target.id,
    );
    final targetWorkspace = workspaces.isNotEmpty
        ? workspaces.first.id
        : await entities.create(
            EntityRecordDraft(
              entityType: 'browser_workspaces',
              parentId: target.id,
              title: '${target.title} workspace',
              data: {
                'task_occurrence_id': target.id,
                'persistence_mode': 'keep_pinned',
                'search_engine': 'google',
              },
              syncPayload: {
                'task_occurrence_id': target.id,
                'task_template_id': null,
                'title': '${target.title} workspace',
                'persistence_mode': 'keep_pinned',
                'selected_tab_id': null,
                'search_engine': 'google',
              },
            ),
          );
    final data = _data(tab)
      ..['workspace_id'] = targetWorkspace
      ..['is_selected'] = false;
    await entities.update(
      tab,
      parentId: targetWorkspace,
      data: data,
      syncPayload: {'workspace_id': targetWorkspace, 'is_selected': false},
    );
    final remaining = await entities.list(
      entityType: 'browser_tabs',
      parentId: _workspaceId,
    );
    if (remaining.isEmpty) {
      await _newTab(const []);
    } else {
      await _selectTab(remaining.first, remaining);
    }
  }

  Future<void> _showBookmarks() async {
    final entities = ref.read(entityRecordRepositoryProvider);
    final bookmarks = await entities.list(
      entityType: 'browser_bookmarks',
      parentId: _workspaceId,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: bookmarks.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Text('No task bookmarks yet')),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final bookmark in bookmarks)
                    ListTile(
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text(bookmark.title),
                      subtitle: Text(_data(bookmark)['url'] as String? ?? ''),
                      onTap: () {
                        Navigator.pop(context);
                        _browser.load(
                          _data(bookmark)['url'] as String? ??
                              'https://www.google.com',
                        );
                      },
                      trailing: IconButton(
                        tooltip: 'Delete bookmark',
                        onPressed: () async {
                          await entities.softDelete(bookmark);
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _workspaceId == null) {
      return Center(child: Text(_error ?? 'Browser workspace unavailable'));
    }
    return StreamBuilder<List<LocalEntityRecord>>(
      stream: ref
          .watch(entityRecordRepositoryProvider)
          .watch(entityType: 'browser_tabs', parentId: _workspaceId),
      builder: (context, snapshot) {
        final tabs = snapshot.data ?? const [];
        final selected =
            tabs.where((tab) => tab.id == _selectedTabId).firstOrNull ??
            tabs.firstOrNull;
        if (selected == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final selectedData = _data(selected);
        final selectedUrl =
            selectedData['url'] as String? ?? 'https://www.google.com';
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Column(
                children: [
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      children: [
                        for (final tab in tabs)
                          _BrowserTabChip(
                            tab: tab,
                            data: _data(tab),
                            selected: tab.id == selected.id,
                            onSelect: () => _selectTab(tab, tabs),
                            onClose: () => _closeTab(tab, tabs),
                          ),
                        IconButton(
                          tooltip: 'New tab',
                          onPressed: () => _newTab(tabs),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: _browser.back,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        IconButton(
                          tooltip: 'Forward',
                          onPressed: _browser.forward,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: _browser.reload,
                          icon: const Icon(Icons.refresh),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _address,
                            textInputAction: TextInputAction.go,
                            onSubmitted: _browser.load,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Search or enter address',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Bookmark for this task',
                          onPressed: () => _addBookmark(selected),
                          icon: const Icon(Icons.bookmark_add_outlined),
                        ),
                        IconButton(
                          tooltip: 'Task bookmarks',
                          onPressed: _showBookmarks,
                          icon: const Icon(Icons.bookmarks_outlined),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Tab and task browser actions',
                          onSelected: (action) async {
                            final data = _data(selected);
                            switch (action) {
                              case 'pin':
                                data['is_pinned'] =
                                    !(data['is_pinned'] == true);
                                await ref
                                    .read(entityRecordRepositoryProvider)
                                    .update(
                                      selected,
                                      data: data,
                                      syncPayload: {
                                        'is_pinned': data['is_pinned'],
                                      },
                                    );
                              case 'rename':
                                await _renameTab(selected);
                              case 'duplicate':
                                await _createTab(
                                  workspaceId: _workspaceId!,
                                  url: selectedUrl,
                                  position: tabs.length.toDouble(),
                                );
                              case 'close_others':
                                await _closeOtherTabs(selected, tabs);
                              case 'reopen':
                                await _reopenClosedTab();
                              case 'move':
                                await _moveTabToTask(selected);
                              case 'external':
                                await launchUrl(
                                  Uri.parse(selectedUrl),
                                  mode: LaunchMode.externalApplication,
                                );
                              case 'remember':
                                await _rememberWebsite(selected);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'pin',
                              child: Text(
                                selectedData['is_pinned'] == true
                                    ? 'Unpin tab'
                                    : 'Pin tab',
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename tab'),
                            ),
                            const PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicate tab'),
                            ),
                            const PopupMenuItem(
                              value: 'close_others',
                              child: Text('Close other tabs'),
                            ),
                            const PopupMenuItem(
                              value: 'reopen',
                              child: Text('Reopen closed tab'),
                            ),
                            const PopupMenuItem(
                              value: 'move',
                              child: Text('Move tab to another task'),
                            ),
                            const PopupMenuItem(
                              value: 'remember',
                              child: Text('Connect website to this task'),
                            ),
                            const PopupMenuItem(
                              value: 'external',
                              child: Text('Open externally'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CrossPlatformWebView(
                key: ValueKey(selected.id),
                controller: _browser,
                initialUrl: selectedUrl,
                onUrlChanged: (url) {
                  if (_address.text != url) _address.text = url;
                  _scheduleMetadataUpdate(selected, url: url);
                },
                onTitleChanged: (title) =>
                    _scheduleMetadataUpdate(selected, title: title),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BrowserTabChip extends StatelessWidget {
  const _BrowserTabChip({
    required this.tab,
    required this.data,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final LocalEntityRecord tab;
  final Map<String, Object?> data;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.surface
          : Colors.transparent,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: InkWell(
        onTap: onSelect,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: SizedBox(
          width: 190,
          child: Row(
            children: [
              const SizedBox(width: 10),
              if (data['is_pinned'] == true)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 5),
                  child: Icon(Icons.push_pin, size: 14),
                ),
              Expanded(
                child: Text(
                  data['custom_title'] as String? ??
                      data['title'] as String? ??
                      tab.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Close tab',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
