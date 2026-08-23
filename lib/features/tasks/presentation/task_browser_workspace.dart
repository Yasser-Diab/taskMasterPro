import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../vault/data/vault_repository.dart';
import '../../vault/presentation/password_vault_screen.dart';
import '../../activity/presentation/break_activity_check_in.dart';
import '../data/task_execution_commands.dart';
import '../data/task_execution_providers.dart';
import '../data/website_rule_service.dart';
import '../domain/browser_handoff.dart';
import '../domain/browser_workspace_checkpoint.dart';
import '../domain/pomodoro_execution_state.dart';
import 'cross_platform_webview.dart';
import 'task_completion_flow.dart';
import 'task_start_flow.dart';

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
  const TaskBrowserWorkspace({
    required this.task,
    required this.onFullScreenChanged,
    this.initialUrl,
    this.fullScreen = false,
    super.key,
  });

  final LocalTask task;
  final String? initialUrl;
  final bool fullScreen;
  final ValueChanged<bool> onFullScreenChanged;

  @override
  ConsumerState<TaskBrowserWorkspace> createState() =>
      _TaskBrowserWorkspaceState();
}

class _TaskBrowserWorkspaceState extends ConsumerState<TaskBrowserWorkspace>
    with WidgetsBindingObserver {
  final _address = TextEditingController();
  final _browserControllers = <String, TaskBrowserController>{};
  final _liveUrls = <String, String>{};
  final _liveTitles = <String, String>{};
  final _metadataDebounces = <String, Timer>{};
  final _pendingMetadataUrls = <String, String>{};
  final _pendingMetadataTitles = <String, String>{};
  final _metadataDirtyTabs = <String>{};
  final _checkpointDebounces = <String, Timer>{};
  final _pendingCheckpoints = <String, BrowserWorkspaceCheckpoint>{};
  final _liveCheckpoints = <String, BrowserWorkspaceCheckpoint>{};
  final _checkpointDirtyTabs = <String>{};
  final _tabSyncGenerations = <String, int>{};
  Future<void> _checkpointWriteChain = Future<void>.value();
  Timer? _checkpointCaptureTimer;
  bool _checkpointLifecycleFlushInFlight = false;
  String? _workspaceId;
  String? _selectedTabId;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ensureWorkspace());
  }

  @override
  void didUpdateWidget(covariant TaskBrowserWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUrl != oldWidget.initialUrl) {
      unawaited(_openRequestedUrl(widget.initialUrl));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // A task workspace exit is an explicit synchronization boundary. Page
    // navigation itself deliberately remains local so following a lesson does
    // not turn browser history into an egress stream.
    unawaited(_checkpointBeforeTaskExit());
    _checkpointCaptureTimer?.cancel();
    for (final timer in _metadataDebounces.values) {
      timer.cancel();
    }
    for (final timer in _checkpointDebounces.values) {
      timer.cancel();
    }
    _address.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    unawaited(_checkpointBeforeBackground());
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
                title: widget.task.title,
                data: {
                  'task_occurrence_id': widget.task.id,
                  'persistence_mode': 'keep_pinned',
                  'search_engine': 'google',
                },
                syncPayload: {
                  'task_occurrence_id': widget.task.id,
                  'task_template_id': null,
                  'title': widget.task.title,
                  'persistence_mode': 'keep_pinned',
                  'selected_tab_id': null,
                  'search_engine': 'google',
                },
              ),
            )
          : workspaces.first.id;
      final workspace = workspaces.isEmpty
          ? await entities.get(workspaceId)
          : workspaces.first;
      var tabs = await entities.list(
        entityType: 'browser_tabs',
        parentId: workspaceId,
      );
      final requestedUrl = widget.initialUrl?.trim().isNotEmpty == true
          ? normalizeBrowserAddress(widget.initialUrl!)
          : null;
      if (tabs.isEmpty) {
        final id = await _createTab(
          workspaceId: workspaceId,
          url: requestedUrl ?? 'https://www.google.com',
          selected: true,
        );
        tabs = [(await entities.get(id))!];
      }
      LocalEntityRecord? selected;
      if (requestedUrl != null) {
        selected = tabs
            .where(
              (tab) =>
                  normalizeBrowserAddress(_data(tab)['url'] as String? ?? '') ==
                  requestedUrl,
            )
            .firstOrNull;
        if (selected == null) {
          for (final tab in tabs) {
            final data = _data(tab);
            if (data['is_selected'] != true) continue;
            data['is_selected'] = false;
            await entities.update(
              tab,
              data: data,
              syncPayload: const {'is_selected': false},
            );
          }
          final id = await _createTab(
            workspaceId: workspaceId,
            url: requestedUrl,
            selected: true,
            position: tabs.length.toDouble(),
          );
          selected = await entities.get(id);
        }
      }
      final persistedSelectedId =
          _data(workspace ?? tabs.first)['selected_tab_id'] as String?;
      final resolvedSelected =
          selected ??
          tabs.where((tab) => tab.id == persistedSelectedId).firstOrNull ??
          tabs.where((tab) => _data(tab)['is_selected'] == true).firstOrNull ??
          tabs.first;
      for (final tab in tabs) {
        _liveCheckpoints.putIfAbsent(tab.id, () => _checkpointFor(tab));
      }
      if (!mounted) return;
      setState(() {
        _workspaceId = workspaceId;
        _selectedTabId = resolvedSelected.id;
        final url =
            _data(resolvedSelected)['url'] as String? ??
            'https://www.google.com';
        _liveUrls[resolvedSelected.id] = url;
        _address.text = url;
        _initializing = false;
      });
      _startCheckpointCapture();
      unawaited(_persistSelectedTab(resolvedSelected.id));
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    } catch (_) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'browser_workspace_unavailable';
        });
      }
    }
  }

  Map<String, Object?> _data(LocalEntityRecord record) {
    return ref.read(entityRecordRepositoryProvider).decode(record);
  }

  BrowserWorkspaceCheckpoint _checkpointFor(LocalEntityRecord tab) {
    final data = _data(tab);
    final fallback = BrowserWorkspaceCheckpoint(
      url: _tabUrl(tab),
      title: data['title'] as String? ?? tab.title,
    );
    return fallback.mergedWith(
      BrowserWorkspaceCheckpoint.fromStored(data['checkpoint']),
    );
  }

  void _startCheckpointCapture() {
    if (_checkpointCaptureTimer != null) return;
    _checkpointCaptureTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final tabId = _selectedTabId;
      if (tabId != null) unawaited(_captureCheckpointForTab(tabId));
    });
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () async {
        final tabId = _selectedTabId;
        if (tabId != null) await _captureCheckpointForTab(tabId);
      }),
    );
  }

  Future<void> _captureCheckpointForTab(String tabId) async {
    // Do not create a controller solely for a background checkpoint. A tab
    // that has not mounted yet has its durable data already and cannot report
    // a newer browser position.
    await _browserControllers[tabId]?.captureCheckpoint();
  }

  void _queueCheckpointForLocalWrite(
    String tabId,
    BrowserWorkspaceCheckpoint checkpoint,
  ) {
    _markTabSyncDirty(tabId);
    _liveCheckpoints[tabId] = checkpoint;
    _pendingCheckpoints[tabId] = checkpoint;
    _checkpointDirtyTabs.add(tabId);
    _checkpointDebounces.remove(tabId)?.cancel();
    _checkpointDebounces[tabId] = Timer(
      const Duration(milliseconds: 850),
      () => unawaited(_flushLocalCheckpoint(tabId)),
    );
  }

  void _replaceCheckpointForNavigation(
    String tabId, {
    required String url,
    String? title,
  }) {
    final existing =
        _liveCheckpoints[tabId] ?? const BrowserWorkspaceCheckpoint();
    _queueCheckpointForLocalWrite(
      tabId,
      BrowserWorkspaceCheckpoint(
        url: url,
        title: title ?? existing.title ?? url,
        scrollX: 0,
        scrollY: 0,
        zoomScale: 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void _scheduleCheckpointUpdate(
    String tabId,
    BrowserWorkspaceCheckpoint checkpoint,
  ) {
    final liveUrl = _liveUrls[tabId];
    if (liveUrl != null &&
        checkpoint.url != null &&
        checkpoint.url != liveUrl) {
      // A periodic JavaScript result can arrive just after navigation. The
      // URL listener already owns the newer page; do not let an old document
      // overwrite it.
      return;
    }
    final current =
        _liveCheckpoints[tabId] ?? const BrowserWorkspaceCheckpoint();
    final next = current.mergedWith(checkpoint);
    if (current.sameContent(next)) return;
    _queueCheckpointForLocalWrite(tabId, next);
  }

  Future<void> _flushLocalCheckpoint(
    String tabId, {
    EntityRecordRepository? repository,
  }) async {
    _checkpointDebounces.remove(tabId)?.cancel();
    final checkpoint = _pendingCheckpoints.remove(tabId);
    if (checkpoint == null) return;
    final EntityRecordRepository entities =
        repository ?? ref.read(entityRecordRepositoryProvider);
    await _queueCheckpointWrite(() async {
      final latest = await entities.get(tabId);
      if (latest == null || latest.deletedAt != null) return;
      final data = _data(latest);
      final stored = BrowserWorkspaceCheckpoint.fromStored(data['checkpoint']);
      if (stored.sameContent(checkpoint)) return;
      data['checkpoint'] = checkpoint.toStorage();
      // This is intentionally a device-local durable update. It does not
      // increment revision or enqueue a network command for page scrolling.
      await entities.updateLocalData(latest, data: data);
    });
  }

  Future<bool> _synchronizeCheckpoint(
    String tabId, {
    EntityRecordRepository? repository,
  }) async {
    // Metadata and resume position are one compact tab snapshot at a boundary.
    // Never turn URL/title changes or reading movement into separate commands.
    final EntityRecordRepository entities =
        repository ?? ref.read(entityRecordRepositoryProvider);
    await _flushMetadataUpdate(tabId, repository: entities);
    await _flushLocalCheckpoint(tabId, repository: entities);
    final metadataDirty = _metadataDirtyTabs.contains(tabId);
    var checkpointDirty = _checkpointDirtyTabs.contains(tabId);
    if (!metadataDirty && !checkpointDirty) return false;
    final checkpoint = _liveCheckpoints[tabId];
    if (checkpointDirty && checkpoint == null) {
      // A tab can disappear between a WebView callback and its local flush.
      // Metadata may still need the boundary write, but a missing checkpoint
      // must never block that compact update forever.
      _checkpointDirtyTabs.remove(tabId);
      checkpointDirty = false;
    }
    if (!metadataDirty && !checkpointDirty) return false;
    final generation = _tabSyncGenerations[tabId] ?? 0;
    var synchronized = false;
    await _queueCheckpointWrite(() async {
      final latest = await entities.get(tabId);
      if (latest == null || latest.deletedAt != null) {
        _metadataDirtyTabs.remove(tabId);
        _checkpointDirtyTabs.remove(tabId);
        return;
      }
      final data = _data(latest);
      final payload = <String, Object?>{};
      if (metadataDirty) {
        payload.addAll(
          _tabVisitPayload(
            url: data['url'] as String?,
            title: data['title'] as String?,
            lastVisitedAt: data['last_visited_at'],
          ),
        );
      }
      if (checkpointDirty) {
        data['checkpoint'] = checkpoint!.toStorage();
        payload['checkpoint'] = checkpoint.toStorage();
      }
      await entities.update(
        latest,
        title: metadataDirty
            ? (data['title'] as String? ?? data['url'] as String?)
            : null,
        data: data,
        syncPayload: payload,
      );
      synchronized = true;
      // If the WebView navigated while this snapshot was being persisted, it
      // remains dirty for the next deliberate boundary. Never let an older
      // response erase a newer local URL or reading checkpoint.
      if ((_tabSyncGenerations[tabId] ?? 0) == generation) {
        _metadataDirtyTabs.remove(tabId);
        _checkpointDirtyTabs.remove(tabId);
      }
    });
    return synchronized;
  }

  Future<void> _checkpointBeforeBackground() async {
    if (_checkpointLifecycleFlushInFlight) return;
    _checkpointLifecycleFlushInFlight = true;
    // Read providers before the first await so the route-exit flush can finish
    // even when this state has already left the widget tree.
    final entities = ref.read(entityRecordRepositoryProvider);
    final synchronizer = ref.read(syncServiceProvider);
    try {
      final tabId = _selectedTabId;
      if (tabId == null) return;
      await _captureCheckpointForTab(tabId);
      if (await _synchronizeCheckpoint(tabId, repository: entities)) {
        unawaited(synchronizer.drainOutbox());
      }
    } finally {
      _checkpointLifecycleFlushInFlight = false;
    }
  }

  /// The enclosing task workspace disposes this browser only when the user
  /// leaves the task. It is deliberately separate from normal navigation so
  /// the current tab snapshot is synchronized once, not once per page.
  Future<void> _checkpointBeforeTaskExit() => _checkpointBeforeBackground();

  Future<void> _persistSelectedTab(String tabId) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null) return;
    final entities = ref.read(entityRecordRepositoryProvider);
    final workspace = await entities.get(workspaceId);
    if (workspace == null || workspace.deletedAt != null) return;
    final data = _data(workspace);
    if (data['selected_tab_id'] == tabId) return;
    data['selected_tab_id'] = tabId;
    await entities.update(
      workspace,
      data: data,
      syncPayload: {'selected_tab_id': tabId},
    );
  }

  Future<void> _queueCheckpointWrite(Future<void> Function() action) {
    final queued = _checkpointWriteChain.then<void>(
      (_) => action(),
      onError: (Object _, StackTrace _) => action(),
    );
    _checkpointWriteChain = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return queued;
  }

  TaskBrowserController _browserFor(String tabId) {
    return _browserControllers.putIfAbsent(tabId, TaskBrowserController.new);
  }

  TaskBrowserController _browserForSelectedTab() {
    final tabId = _selectedTabId;
    return tabId == null ? TaskBrowserController() : _browserFor(tabId);
  }

  String _tabUrl(LocalEntityRecord tab) {
    return _liveUrls[tab.id] ??
        _data(tab)['url'] as String? ??
        'https://www.google.com';
  }

  Map<String, Object?> _displayData(LocalEntityRecord tab) {
    final data = Map<String, Object?>.from(_data(tab));
    final liveTitle = _liveTitles[tab.id];
    if (liveTitle != null && liveTitle.trim().isNotEmpty) {
      data['title'] = liveTitle;
    }
    return data;
  }

  void _discardTabRuntimeState(String tabId) {
    _metadataDebounces.remove(tabId)?.cancel();
    _pendingMetadataUrls.remove(tabId);
    _pendingMetadataTitles.remove(tabId);
    _metadataDirtyTabs.remove(tabId);
    _checkpointDebounces.remove(tabId)?.cancel();
    _pendingCheckpoints.remove(tabId);
    _liveCheckpoints.remove(tabId);
    _checkpointDirtyTabs.remove(tabId);
    _tabSyncGenerations.remove(tabId);
    _browserControllers.remove(tabId);
    _liveUrls.remove(tabId);
    _liveTitles.remove(tabId);
  }

  Future<void> _openRequestedUrl(String? rawUrl) async {
    final workspaceId = _workspaceId;
    if (workspaceId == null || rawUrl?.trim().isNotEmpty != true) return;
    final requestedUrl = normalizeBrowserAddress(rawUrl!);
    if (_address.text == requestedUrl) return;
    final entities = ref.read(entityRecordRepositoryProvider);
    try {
      final tabs = await entities.list(
        entityType: 'browser_tabs',
        parentId: workspaceId,
      );
      final existing = tabs
          .where(
            (tab) =>
                normalizeBrowserAddress(_data(tab)['url'] as String? ?? '') ==
                requestedUrl,
          )
          .firstOrNull;
      if (existing != null) {
        await _selectTab(existing, tabs);
        return;
      }
      for (final tab in tabs) {
        final data = _data(tab);
        if (data['is_selected'] != true) continue;
        data['is_selected'] = false;
        await entities.update(
          tab,
          data: data,
          syncPayload: const {'is_selected': false},
        );
      }
      final id = await _createTab(
        workspaceId: workspaceId,
        url: requestedUrl,
        selected: true,
        position: tabs.length.toDouble(),
      );
      if (!mounted) return;
      setState(() {
        _selectedTabId = id;
        _liveUrls[id] = requestedUrl;
        _liveCheckpoints[id] = BrowserWorkspaceCheckpoint(
          url: requestedUrl,
          title: requestedUrl,
          scrollX: 0,
          scrollY: 0,
          zoomScale: 1,
          updatedAt: DateTime.now().toUtc(),
        );
        _address.text = requestedUrl;
      });
      await _persistSelectedTab(id);
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    } catch (_) {
      // Keep the current tab usable. The resource remains available from the
      // task's resource panel for a later retry.
    }
  }

  Future<String> _createTab({
    required String workspaceId,
    required String url,
    bool selected = false,
    double position = 0,
    bool pinned = false,
  }) {
    final now = DateTime.now().toUtc();
    final checkpoint = BrowserWorkspaceCheckpoint(
      url: url,
      title: url,
      scrollX: 0,
      scrollY: 0,
      zoomScale: 1,
      updatedAt: now,
    );
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
              'last_visited_at': now.toIso8601String(),
              'checkpoint': checkpoint.toStorage(),
            },
            syncPayload: {
              'workspace_id': workspaceId,
              'url': url,
              'title': url,
              'custom_title': null,
              'position': position,
              'is_pinned': pinned,
              'is_selected': selected,
              'last_visited_at': now.toIso8601String(),
              'checkpoint': checkpoint.toStorage(),
            },
          ),
        );
  }

  Future<void> _selectTab(
    LocalEntityRecord selected,
    List<LocalEntityRecord> tabs,
  ) async {
    if (_selectedTabId == selected.id) return;
    final previousTabId = _selectedTabId;
    if (previousTabId != null) {
      await _captureCheckpointForTab(previousTabId);
      await _synchronizeCheckpoint(previousTabId);
    }
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
    setState(() {
      _selectedTabId = selected.id;
      _address.text = _tabUrl(selected);
    });
    await _persistSelectedTab(selected.id);
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  Future<void> _newTab(
    List<LocalEntityRecord> tabs, {
    String url = 'https://www.google.com',
  }) async {
    final id = await _createTab(
      workspaceId: _workspaceId!,
      url: url,
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
        _liveUrls[id] = url;
        _liveCheckpoints[id] = BrowserWorkspaceCheckpoint(
          url: url,
          title: url,
          scrollX: 0,
          scrollY: 0,
          zoomScale: 1,
          updatedAt: DateTime.now().toUtc(),
        );
        _address.text = url;
      });
    }
    await _persistSelectedTab(id);
  }

  Future<void> _openNewTabFromBrowser(String rawUrl) async {
    final workspaceId = _workspaceId;
    if (!mounted || !isTaskBrowserWebUrl(rawUrl) || workspaceId == null) return;
    final tabs = await ref
        .read(entityRecordRepositoryProvider)
        .list(entityType: 'browser_tabs', parentId: workspaceId);
    if (!mounted || _workspaceId != workspaceId) return;
    await _newTab(tabs, url: normalizeBrowserAddress(rawUrl));
  }

  Future<void> _closeTab(
    LocalEntityRecord tab,
    List<LocalEntityRecord> tabs,
  ) async {
    final data = _data(tab);
    final closedTabTitle = context.l10n.text('browser_closed_tab');
    if (data['is_pinned'] == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.text('browser_close_pinned')),
          content: Text(context.l10n.text('browser_pinned_detail')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('browser_keep_tab')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.text('close')),
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
            data['title'] as String? ??
            data['url'] as String? ??
            closedTabTitle,
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
    _discardTabRuntimeState(tab.id);
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
    if (url != null && url.trim().isNotEmpty) {
      _markTabSyncDirty(tab.id);
      _liveUrls[tab.id] = url;
      _pendingMetadataUrls[tab.id] = url;
      _metadataDirtyTabs.add(tab.id);
      // A new document must never inherit the previous lesson's scroll or
      // media time. Its fresh checkpoint begins at the top until JavaScript
      // reports a more precise position.
      _replaceCheckpointForNavigation(tab.id, url: url, title: title);
    }
    if (title != null && title.trim().isNotEmpty) {
      _markTabSyncDirty(tab.id);
      _liveTitles[tab.id] = title;
      _pendingMetadataTitles[tab.id] = title;
      _metadataDirtyTabs.add(tab.id);
      if (url == null) {
        _scheduleCheckpointUpdate(
          tab.id,
          BrowserWorkspaceCheckpoint(
            title: title,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      }
    }
    if (tab.id == _selectedTabId && url != null && _address.text != url) {
      _address.text = url;
    }
    _metadataDebounces.remove(tab.id)?.cancel();
    _metadataDebounces[tab.id] = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_flushMetadataUpdate(tab.id)),
    );
  }

  void _markTabSyncDirty(String tabId) {
    _tabSyncGenerations.update(tabId, (value) => value + 1, ifAbsent: () => 1);
  }

  Future<void> _flushMetadataUpdate(
    String tabId, {
    EntityRecordRepository? repository,
  }) async {
    _metadataDebounces.remove(tabId)?.cancel();
    final url = _pendingMetadataUrls.remove(tabId);
    final title = _pendingMetadataTitles.remove(tabId);
    if (url == null && title == null) return;
    final EntityRecordRepository entities =
        repository ?? ref.read(entityRecordRepositoryProvider);

    await _queueCheckpointWrite(() async {
      final latest = await entities.get(tabId);
      if (latest == null || latest.deletedAt != null) return;
      final data = _data(latest);
      if (url != null) data['url'] = url;
      if (title != null) data['title'] = title;
      final visitedAt = url == null
          ? data['last_visited_at']?.toString() ??
                DateTime.now().toUtc().toIso8601String()
          : DateTime.now().toUtc().toIso8601String();
      data['last_visited_at'] = visitedAt;
      final checkpoint = (_liveCheckpoints[tabId] ?? _checkpointFor(latest))
          .withMetadata(url: url, title: title)
          .stamped(DateTime.parse(visitedAt));
      _liveCheckpoints[tabId] = checkpoint;
      data['checkpoint'] = checkpoint.toStorage();
      // Navigation is frequent, especially through lessons and redirects.
      // Keep its current URL/title/resume point durable on this device without
      // creating a revision, outbox command, or one history row per page.
      await entities.updateLocalData(latest, data: data);
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
    final url = data['url'] as String? ?? '';
    if (NormalizedWebsiteAddress.tryParse(url) == null) return;
    // The Browser shortcut is intentionally the broad, durable choice. The
    // Connections panel offers all four scopes when a narrower rule is wanted.
    await ref
        .read(websiteRuleServiceProvider)
        .connectToTask(
          taskId: widget.task.id,
          url: url,
          scope: WebsiteMatchScope.site,
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  Future<void> _saveSignInToVault(String url) async {
    final repository = VaultRepository(
      ref.read(entityRecordRepositoryProvider),
    );
    final vault = await repository.currentVault();
    if (vault != null &&
        !repository.preferences(vault).credentialSavingEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('browser_vault_saving_disabled')),
        ),
      );
      return;
    }
    final captured = await _browserForSelectedTab().captureCredentials();
    if (captured == null ||
        !websiteMatchesForCredential(
          savedWebsite: captured.website,
          pageUrl: url,
        )) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.text('browser_vault_capture_fields_not_found'),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PasswordVaultScreen(
          initialWebsite: captured.website,
          initialAccountName: captured.suggestedName,
          initialUsername: captured.username,
          initialPassword: captured.password,
          openAddWhenUnlocked: true,
          closeAfterInitialSave: true,
        ),
      ),
    );
  }

  Future<void> _fillFromVault(String url) async {
    final repository = VaultRepository(
      ref.read(entityRecordRepositoryProvider),
    );
    final vault = await repository.currentVault();
    if (vault != null && !repository.preferences(vault).autofillEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('browser_vault_autofill_disabled')),
        ),
      );
      return;
    }
    if (!mounted) return;
    final credential = await Navigator.of(context)
        .push<VaultAutofillCredential>(
          MaterialPageRoute<VaultAutofillCredential>(
            builder: (_) => PasswordVaultScreen(autofillForWebsite: url),
          ),
        );
    if (credential == null || !mounted) return;
    if (!websiteMatchesForCredential(
      savedWebsite: credential.website,
      pageUrl: url,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('browser_vault_origin_changed')),
        ),
      );
      return;
    }
    final filled = await _browserForSelectedTab().fillCredentials(
      username: credential.username,
      password: credential.password,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.text(
            filled
                ? 'browser_vault_fields_filled'
                : 'browser_vault_fields_not_found',
          ),
        ),
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
        title: Text(context.l10n.text('browser_rename_task_tab')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.text('browser_custom_title'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.l10n.text('save')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('browser_no_closed_tab'))),
        );
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
        title: Text(context.l10n.text('browser_move_tab')),
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
                    subtitle: Text(context.l10n.taskStatus(task.status)),
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
              title: target.title,
              data: {
                'task_occurrence_id': target.id,
                'persistence_mode': 'keep_pinned',
                'search_engine': 'google',
              },
              syncPayload: {
                'task_occurrence_id': target.id,
                'task_template_id': null,
                'title': target.title,
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
    _discardTabRuntimeState(tab.id);
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
            ? Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Text(context.l10n.text('browser_no_bookmarks')),
                ),
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
                        _browserForSelectedTab().load(
                          _data(bookmark)['url'] as String? ??
                              'https://www.google.com',
                        );
                      },
                      trailing: IconButton(
                        tooltip: context.l10n.text('browser_delete_bookmark'),
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

  void _toggleFullScreen() => widget.onFullScreenChanged(!widget.fullScreen);

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _workspaceId == null) {
      return Center(
        child: Text(
          context.l10n.text(_error ?? 'browser_workspace_unavailable'),
        ),
      );
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
        final selectedData = _displayData(selected);
        final selectedUrl = _tabUrl(selected);
        final selectedBrowser = _browserFor(selected.id);
        final phone = MediaQuery.sizeOf(context).width < 520;
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Column(
                children: [
                  if (phone)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 4, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _BrowserTabChip(
                              tab: selected,
                              data: selectedData,
                              selected: true,
                              compact: true,
                              onSelect: () => _selectTab(selected, tabs),
                              onClose: () => _closeTab(selected, tabs),
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.text('browser_new_tab'),
                            onPressed: () => _newTab(tabs),
                            icon: const Icon(Icons.add),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: context.l10n.text(
                              widget.fullScreen
                                  ? 'browser_exit_full_screen'
                                  : 'browser_full_screen',
                            ),
                            onPressed: _toggleFullScreen,
                            icon: Icon(
                              widget.fullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Expanded(
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
                              children: [
                                for (final tab in tabs)
                                  _BrowserTabChip(
                                    tab: tab,
                                    data: _displayData(tab),
                                    selected: tab.id == selected.id,
                                    onSelect: () => _selectTab(tab, tabs),
                                    onClose: () => _closeTab(tab, tabs),
                                  ),
                                IconButton(
                                  tooltip: context.l10n.text('browser_new_tab'),
                                  onPressed: () => _newTab(tabs),
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            ),
                          ),
                          _BrowserTaskControlPill(task: widget.task),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: context.l10n.text(
                              widget.fullScreen
                                  ? 'browser_exit_full_screen'
                                  : 'browser_full_screen',
                            ),
                            onPressed: _toggleFullScreen,
                            icon: Icon(
                              widget.fullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  if (phone)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
                      child: _BrowserTaskControlPill(
                        task: widget.task,
                        fillAvailableWidth: true,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 620;
                        final veryCompact = constraints.maxWidth < 380;
                        return Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: context.l10n.text('back'),
                              onPressed: selectedBrowser.back,
                              icon: const Icon(Icons.arrow_back),
                            ),
                            if (!compact)
                              IconButton(
                                tooltip: context.l10n.text('browser_forward'),
                                onPressed: selectedBrowser.forward,
                                icon: const Icon(Icons.arrow_forward),
                              ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: context.l10n.text('browser_refresh'),
                              onPressed: selectedBrowser.reload,
                              icon: const Icon(Icons.refresh),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _address,
                                textInputAction: TextInputAction.go,
                                onSubmitted: selectedBrowser.load,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: context.l10n.text(
                                    'browser_search_address',
                                  ),
                                  prefixIcon: veryCompact
                                      ? null
                                      : const Icon(Icons.search),
                                ),
                              ),
                            ),
                            if (!compact)
                              IconButton(
                                tooltip: context.l10n.text(
                                  'browser_bookmark_task',
                                ),
                                onPressed: () => _addBookmark(selected),
                                icon: const Icon(Icons.bookmark_add_outlined),
                              ),
                            if (!compact)
                              IconButton(
                                tooltip: context.l10n.text(
                                  'browser_task_bookmarks',
                                ),
                                onPressed: _showBookmarks,
                                icon: const Icon(Icons.bookmarks_outlined),
                              ),
                            if (compact)
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                tooltip: context.l10n.text(
                                  'browser_tab_actions',
                                ),
                                onSelected: (action) async {
                                  switch (action) {
                                    case 'forward':
                                      await selectedBrowser.forward();
                                    case 'bookmark':
                                      await _addBookmark(selected);
                                    case 'bookmarks':
                                      await _showBookmarks();
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'forward',
                                    child: Text(
                                      context.l10n.text('browser_forward'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'bookmark',
                                    child: Text(
                                      context.l10n.text(
                                        'browser_bookmark_task',
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'bookmarks',
                                    child: Text(
                                      context.l10n.text(
                                        'browser_task_bookmarks',
                                      ),
                                    ),
                                  ),
                                ],
                                icon: const Icon(Icons.more_horiz),
                              ),
                            if (!veryCompact)
                              PopupMenuButton<String>(
                                tooltip: context.l10n.text(
                                  'browser_tab_actions',
                                ),
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
                                    case 'save_sign_in':
                                      await _saveSignInToVault(selectedUrl);
                                    case 'fill_sign_in':
                                      await _fillFromVault(selectedUrl);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'pin',
                                    child: Text(
                                      selectedData['is_pinned'] == true
                                          ? context.l10n.text(
                                              'browser_unpin_tab',
                                            )
                                          : context.l10n.text(
                                              'browser_pin_tab',
                                            ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text(
                                      context.l10n.text('browser_rename_tab'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'duplicate',
                                    child: Text(
                                      context.l10n.text(
                                        'browser_duplicate_tab',
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'close_others',
                                    child: Text(
                                      context.l10n.text('browser_close_others'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'reopen',
                                    child: Text(
                                      context.l10n.text('browser_reopen_tab'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'move',
                                    child: Text(
                                      context.l10n.text('browser_move_tab'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'remember',
                                    child: Text(
                                      context.l10n.text(
                                        'browser_connect_website',
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'save_sign_in',
                                    child: Text(
                                      context.l10n.text(
                                        'browser_save_sign_in_vault',
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'fill_sign_in',
                                    child: Text(
                                      context.l10n.text(
                                        'browser_fill_sign_in_vault',
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'external',
                                    child: Text(
                                      context.l10n.text(
                                        'browser_open_external',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              // Each native WebView stays mounted under its stable tab key.
              // IndexedStack is supported by the Windows and Android browser
              // implementations and prevents a tab switch from reloading a
              // lesson, discarding its navigation stack, or losing media.
              child: (Platform.isWindows || Platform.isAndroid)
                  ? IndexedStack(
                      index: tabs.indexWhere((tab) => tab.id == selected.id),
                      children: [
                        for (final tab in tabs)
                          CrossPlatformWebView(
                            key: ValueKey('task-browser-tab-${tab.id}'),
                            controller: _browserFor(tab.id),
                            initialUrl: _tabUrl(tab),
                            profileId:
                                ref
                                    .read(supabaseClientProvider)
                                    .auth
                                    .currentUser
                                    ?.id ??
                                'local',
                            onUrlChanged: (url) =>
                                _scheduleMetadataUpdate(tab, url: url),
                            onTitleChanged: (title) =>
                                _scheduleMetadataUpdate(tab, title: title),
                            restoreCheckpoint: _checkpointFor(tab),
                            onCheckpoint: (checkpoint) =>
                                _scheduleCheckpointUpdate(tab.id, checkpoint),
                            onOpenNewTab: (url) =>
                                unawaited(_openNewTabFromBrowser(url)),
                          ),
                      ],
                    )
                  : CrossPlatformWebView(
                      key: ValueKey('task-browser-tab-${selected.id}'),
                      controller: selectedBrowser,
                      initialUrl: selectedUrl,
                      profileId:
                          ref
                              .read(supabaseClientProvider)
                              .auth
                              .currentUser
                              ?.id ??
                          'local',
                      onUrlChanged: (url) =>
                          _scheduleMetadataUpdate(selected, url: url),
                      onTitleChanged: (title) =>
                          _scheduleMetadataUpdate(selected, title: title),
                      restoreCheckpoint: _checkpointFor(selected),
                      onCheckpoint: (checkpoint) =>
                          _scheduleCheckpointUpdate(selected.id, checkpoint),
                      onOpenNewTab: (url) =>
                          unawaited(_openNewTabFromBrowser(url)),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _BrowserTaskControlPill extends ConsumerStatefulWidget {
  const _BrowserTaskControlPill({
    required this.task,
    this.fillAvailableWidth = false,
  });

  final LocalTask task;
  final bool fillAvailableWidth;

  @override
  ConsumerState<_BrowserTaskControlPill> createState() =>
      _BrowserTaskControlPillState();
}

class _BrowserTaskControlPillState
    extends ConsumerState<_BrowserTaskControlPill> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final task =
        ref.watch(taskExecutionTaskProvider(widget.task.id)).value ??
        widget.task;
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    final ownsTask =
        runtime?.activeTaskId == task.id && runtime?.sessionId != null;
    final ticking =
        ownsTask && (runtime?.state == 'running' || runtime?.state == 'break');
    final now = ticking
        ? ref.watch(taskExecutionClockProvider).value ?? DateTime.now().toUtc()
        : DateTime.now().toUtc();
    final pomodoro = task.executionMode == 'pomodoro'
        ? PomodoroExecutionSnapshot.fromTask(
            task: task,
            runtime: ownsTask ? runtime : null,
            now: now,
          )
        : null;
    final controls = TaskExecutionControlState.from(
      taskId: task.id,
      executionMode: task.executionMode,
      runtime: runtime,
      pomodoro: pomodoro,
    );
    final paused = ownsTask && runtime?.state == 'paused';
    final onBreak = ownsTask && runtime?.state == 'break';
    final running = ownsTask && runtime?.state == 'running';
    final accent = onBreak
        ? const Color(0xFF2DD4BF)
        : paused
        ? const Color(0xFF8B5CF6)
        : running
        ? const Color(0xFF38D889)
        : Theme.of(context).colorScheme.primary;
    final compact = MediaQuery.sizeOf(context).width < 680;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final time = _browserTaskTime(
      task: task,
      runtime: ownsTask ? runtime : null,
      pomodoro: pomodoro,
      now: now,
    );
    final actionLabel = _browserControlLabel(context, controls.primary);
    final secondaryActions = <_BrowserTimerAction>[
      if (controls.canStartBreakEarly) _BrowserTimerAction.startBreakEarly,
      if (controls.canSkipBreak) _BrowserTimerAction.skipOfferedBreak,
      if (controls.canExtendBreak) _BrowserTimerAction.extendBreak,
      if (controls.ownsTask) _BrowserTimerAction.finishTask,
    ];
    final status = ownsTask ? runtime!.state : task.status;
    final pillWidth = widget.fillAvailableWidth
        ? double.infinity
        : compact
        ? 118.0
        : 250.0;
    return Semantics(
      label:
          '${task.title}, $time, ${context.l10n.taskStatus(status)}. '
          '$actionLabel',
      button: true,
      enabled: !_busy,
      child: Tooltip(
        message: '${context.l10n.text('browser_task_tracking')} · $actionLabel',
        child: SizedBox(
          width: pillWidth,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              width: pillWidth,
              height: 34,
              padding: const EdgeInsetsDirectional.only(start: 10, end: 7),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withValues(alpha: 0.62)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const ValueKey('browser-task-primary-control'),
                      borderRadius: BorderRadius.circular(999),
                      onTap: _busy
                          ? null
                          : () => _runPrimary(task, controls.primary),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.7),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          if (!compact) ...[
                            Expanded(
                              child: Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                time,
                                maxLines: 1,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: accent,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (_busy)
                            const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              _browserControlIcon(controls.primary),
                              size: 18,
                              color: accent,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (secondaryActions.isNotEmpty)
                    PopupMenuButton<_BrowserTimerAction>(
                      key: const ValueKey('browser-task-more-controls'),
                      enabled: !_busy,
                      tooltip: context.l10n.text('more'),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: accent,
                      ),
                      onSelected: (action) => _runSecondary(task, action),
                      itemBuilder: (context) => [
                        for (final action in secondaryActions)
                          PopupMenuItem<_BrowserTimerAction>(
                            value: action,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_browserTimerActionIcon(action)),
                              title: Text(
                                context.l10n.text(
                                  _browserTimerActionLabel(action),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runPrimary(
    LocalTask task,
    TaskExecutionPrimaryAction action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: () async {
          final repository = ref.read(taskRepositoryProvider);
          switch (action) {
            case TaskExecutionPrimaryAction.start:
              await startTaskWithConfirmation(
                context,
                ref,
                task,
                launchPreferredResource: false,
              );
            case TaskExecutionPrimaryAction.pause:
              await repository.pause(task);
            case TaskExecutionPrimaryAction.resume:
              await repository.resume(task);
            case TaskExecutionPrimaryAction.startBreak:
              await TaskExecutionCommands.startOfferedBreak(repository, task);
            case TaskExecutionPrimaryAction.startFocus:
              await finishBreakWithOptionalActivityCheckIn(
                context: context,
                ref: ref,
                task: task,
              );
          }
        },
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSecondary(LocalTask task, _BrowserTimerAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    var extended = false;
    try {
      await TaskExecutionCommands.commitLocallyAndSynchronize(
        localCommand: () async {
          final repository = ref.read(taskRepositoryProvider);
          switch (action) {
            case _BrowserTimerAction.startBreakEarly:
              await repository.startBreak(task);
            case _BrowserTimerAction.skipOfferedBreak:
              await TaskExecutionCommands.skipOfferedBreak(repository, task);
            case _BrowserTimerAction.extendBreak:
              extended = await TaskExecutionCommands.extendBreak(
                repository: repository,
                task: task,
              );
            case _BrowserTimerAction.finishTask:
              await completeTaskWithUndo(context, ref, task);
          }
        },
        synchronize: () => ref.read(syncServiceProvider).drainOutbox(),
      );
      if (extended && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('break_extended_five'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

enum _BrowserTimerAction {
  startBreakEarly,
  skipOfferedBreak,
  extendBreak,
  finishTask,
}

String _browserTimerActionLabel(_BrowserTimerAction action) => switch (action) {
  _BrowserTimerAction.startBreakEarly => 'notification_start_break',
  _BrowserTimerAction.skipOfferedBreak => 'pomodoro_skip_break',
  _BrowserTimerAction.extendBreak => 'notification_extend_break',
  _BrowserTimerAction.finishTask => 'finish_task',
};

IconData _browserTimerActionIcon(_BrowserTimerAction action) =>
    switch (action) {
      _BrowserTimerAction.startBreakEarly => Icons.coffee_outlined,
      _BrowserTimerAction.skipOfferedBreak => Icons.skip_next_rounded,
      _BrowserTimerAction.extendBreak => Icons.more_time,
      _BrowserTimerAction.finishTask => Icons.check_rounded,
    };

String _browserTaskTime({
  required LocalTask task,
  required LocalRuntime? runtime,
  required PomodoroExecutionSnapshot? pomodoro,
  required DateTime now,
}) {
  if (pomodoro != null) {
    return formatPomodoroCountdown(pomodoro.remainingMs);
  }
  final recordedMs = liveTaskRecordedWorkMs(
    recordedMs: runtime?.accumulatedActiveMs ?? task.activeDurationMs,
    running: runtime?.state == 'running',
    segmentStartedAt: runtime?.segmentStartedAt,
    now: now,
  );
  final overtimeMs = taskEffortOvertimeMs(
    plannedMs: task.estimatedDurationMs,
    recordedMs: recordedMs,
  );
  if (runtime?.state == 'running' && overtimeMs > 0) {
    return formatTaskEffortOvertime(overtimeMs);
  }
  return formatTaskEffortCountdown(
    taskEffortRemainingMs(
      plannedMs: task.estimatedDurationMs,
      recordedMs: recordedMs,
    ),
  );
}

String _browserControlLabel(
  BuildContext context,
  TaskExecutionPrimaryAction action,
) {
  return context.l10n.text(switch (action) {
    TaskExecutionPrimaryAction.start => 'start',
    TaskExecutionPrimaryAction.pause => 'pause',
    TaskExecutionPrimaryAction.resume => 'resume',
    TaskExecutionPrimaryAction.startBreak => 'notification_start_break',
    TaskExecutionPrimaryAction.startFocus => 'notification_start_focus',
  });
}

IconData _browserControlIcon(TaskExecutionPrimaryAction action) {
  return switch (action) {
    TaskExecutionPrimaryAction.start ||
    TaskExecutionPrimaryAction.resume ||
    TaskExecutionPrimaryAction.startFocus => Icons.play_arrow_rounded,
    TaskExecutionPrimaryAction.pause => Icons.pause_rounded,
    TaskExecutionPrimaryAction.startBreak => Icons.free_breakfast_outlined,
  };
}

class _BrowserTabChip extends StatelessWidget {
  const _BrowserTabChip({
    required this.tab,
    required this.data,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    this.compact = false,
  });

  final LocalEntityRecord tab;
  final Map<String, Object?> data;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final bool compact;

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
          width: compact ? null : 190,
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
                tooltip: context.l10n.text('browser_close_tab'),
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
