import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_services.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/platform/health_data_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_controls.dart';
import '../../sessions/application/time_analytics_service.dart';
import '../../sessions/domain/session_models.dart';
import '../../pomodoro/domain/pomodoro_controller.dart';
import '../../pomodoro/domain/pomodoro_models.dart';
import '../application/task_action_controller.dart';
import '../data/learning_activity_repository.dart';
import '../domain/task_activity.dart';
import '../domain/task_item.dart';
import '../domain/learning_activity_models.dart';
import '../domain/task_support_models.dart';
import '../domain/task_workspace_config.dart';
import 'task_editor_dialog.dart';
import 'task_browser_workspace.dart';

class TaskWorkspaceScreen extends StatefulWidget {
  const TaskWorkspaceScreen({
    required this.controller,
    required this.task,
    this.initialTab = 0,
    super.key,
  });

  final TaskActionController controller;
  final TaskItem task;
  final int initialTab;

  @override
  State<TaskWorkspaceScreen> createState() => _TaskWorkspaceScreenState();
}

class _TaskWorkspaceScreenState extends State<TaskWorkspaceScreen> {
  late TaskItem _currentTask;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(TaskWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.task.id != widget.task.id) {
      _currentTask = widget.task;
    }
    _handleControllerChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final next = widget.controller.tasks.firstWhere(
      (item) => item.id == widget.task.id,
      orElse: () => widget.task,
    );
    if (identical(next, _currentTask)) {
      return;
    }
    if (!mounted) {
      _currentTask = next;
      return;
    }
    setState(() => _currentTask = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTask.title, overflow: TextOverflow.ellipsis),
      ),
      body: _TaskWorkspaceLayout(
        controller: widget.controller,
        task: _currentTask,
        initialPanel: widget.initialTab,
      ),
    );
  }
}

class _TaskWorkspaceLayout extends StatefulWidget {
  const _TaskWorkspaceLayout({
    required this.controller,
    required this.task,
    required this.initialPanel,
  });

  final TaskActionController controller;
  final TaskItem task;
  final int initialPanel;

  @override
  State<_TaskWorkspaceLayout> createState() => _TaskWorkspaceLayoutState();
}

class _TaskWorkspaceLayoutState extends State<_TaskWorkspaceLayout> {
  late int _panelIndex;
  TaskBrowserLayoutMode _browserMode = TaskBrowserLayoutMode.collapsed;
  double _browserWidth = 480;
  int _lastTaskPanelIndex = 0;
  Timer? _applicationTimer;
  bool _samplingApplication = false;
  bool _stateLoaded = false;
  List<Map<String, dynamic>> _browserTabs = const [];
  int _selectedBrowserTab = 0;
  List<TaskResource> _taskResources = const [];

  @override
  void initState() {
    super.initState();
    _panelIndex = widget.initialPanel.clamp(0, 9);
    _browserMode = widget.task.workspaceStartingUrl?.isNotEmpty == true
        ? TaskBrowserLayoutMode.split
        : TaskBrowserLayoutMode.collapsed;
    if (_panelIndex != 4) _lastTaskPanelIndex = _panelIndex;
    _applicationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_sampleExternalApplication()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stateLoaded) return;
    _stateLoaded = true;
    unawaited(_restoreLayout());
    unawaited(_loadTaskResources());
  }

  Future<void> _loadTaskResources() async {
    final resources = await widget.controller.resourcesForTask(widget.task);
    if (mounted) setState(() => _taskResources = resources);
  }

  @override
  void dispose() {
    _applicationTimer?.cancel();
    unawaited(_saveLayout());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final main = _TaskBrowserSlot(
      task: widget.task,
      controller: widget.controller,
      layoutMode: _browserMode,
      resources: _taskResources,
      onCollapse: _collapseBrowser,
      onToggleFull: _toggleFullBrowser,
      onEditTask: () =>
          _editTaskDialog(context, widget.controller, widget.task),
      onAddNote: () => _addNote(context, widget.controller, widget.task),
      onStartWithoutWorkspace: () => widget.controller.startTask(widget.task),
      onAddCurrentPage: (url, title) => _addCurrentPageToTask(
        context,
        widget.controller,
        widget.task,
        url,
        title,
      ),
      onUsage: (url, title, startedAt, endedAt, activeSeconds) {
        unawaited(
          _recordBrowserUsage(
            url: url,
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            activeSeconds: activeSeconds,
          ),
        );
      },
      onCheckpoint: (tabs, selectedTab) {
        _browserTabs = tabs;
        _selectedBrowserTab = selectedTab;
        unawaited(_checkpointBrowserState());
      },
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _exitFullBrowser,
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          shift: true,
        ): _toggleBrowserShortcut,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final wide = constraints.maxWidth >= 980;
            if (compact) {
              return _buildCompactLayout(context, main);
            }
            return Column(
              children: [
                _LiveTaskWorkspaceControlBar(
                  controller: widget.controller,
                  task: widget.task,
                  browserExpanded: _browserMode.isVisible,
                  onToggleBrowser: _toggleBrowserShortcut,
                ),
                const Divider(height: 1),
                Expanded(
                  child: wide
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final browserWidth = _browserWidth.clamp(
                              360.0,
                              (constraints.maxWidth * 0.55).clamp(360.0, 760.0),
                            );
                            return Row(
                              children: [
                                SizedBox(
                                  width: 188,
                                  child: _TaskPanelNavigation(
                                    selectedIndex: _panelIndex,
                                    onSelected: _selectPanel,
                                  ),
                                ),
                                const VerticalDivider(width: 1),
                                if (!_browserMode.isFull)
                                  Expanded(
                                    child: _LiveTaskPanelContent(
                                      selectedIndex: _panelIndex == 4
                                          ? _lastTaskPanelIndex
                                          : _panelIndex,
                                      controller: widget.controller,
                                      task: widget.task,
                                    ),
                                  ),
                                if (_browserMode == TaskBrowserLayoutMode.split)
                                  _BrowserResizeHandle(
                                    onDrag: (delta) {
                                      setState(() {
                                        _browserWidth = (_browserWidth - delta)
                                            .clamp(
                                              360.0,
                                              constraints.maxWidth * 0.55,
                                            );
                                      });
                                    },
                                    onDragEnd: _saveLayout,
                                  ),
                                if (_browserMode == TaskBrowserLayoutMode.split)
                                  SizedBox(width: browserWidth, child: main),
                                if (_browserMode.isFull) Expanded(child: main),
                              ],
                            );
                          },
                        )
                      : Row(
                          children: [
                            SizedBox(
                              width: 96,
                              child: _TaskPanelNavigation(
                                selectedIndex: _panelIndex,
                                onSelected: _selectPanel,
                                iconOnly: true,
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: _browserMode.isFull || _panelIndex == 4
                                  ? main
                                  : _LiveTaskPanelContent(
                                      selectedIndex: _panelIndex,
                                      controller: widget.controller,
                                      task: widget.task,
                                    ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompactLayout(BuildContext context, Widget browser) {
    final showingBrowser = _panelIndex == 4 || _browserMode.isFull;
    if (showingBrowser && _browserMode.isFull) {
      return SafeArea(
        child: Column(
          children: [
            _LiveCompactBrowserTaskIndicator(
              controller: widget.controller,
              task: widget.task,
              onBackToTask: () => _selectPanel(_lastTaskPanelIndex),
            ),
            Expanded(child: browser),
          ],
        ),
      );
    }
    return Column(
      children: [
        _LiveCompactTaskHeader(
          controller: widget.controller,
          task: widget.task,
          onMore: () => _showTaskActions(context),
        ),
        const Divider(height: 1),
        _CompactTaskSectionBar(
          selectedIndex: _panelIndex,
          onSelected: _selectPanel,
          onMore: () => _showSectionSheet(context),
        ),
        Expanded(
          child: showingBrowser
              ? Column(
                  children: [
                    _LiveCompactBrowserTaskIndicator(
                      controller: widget.controller,
                      task: widget.task,
                      onBackToTask: () => _selectPanel(_lastTaskPanelIndex),
                    ),
                    Expanded(child: browser),
                  ],
                )
              : _LiveTaskPanelContent(
                  selectedIndex: _panelIndex,
                  controller: widget.controller,
                  task: widget.task,
                ),
        ),
        _LiveMobileTaskActionBar(
          controller: widget.controller,
          task: widget.task,
          onInternet: () => _selectPanel(4),
          onMore: () => _showTaskActions(context),
        ),
      ],
    );
  }

  void _selectPanel(int index) {
    setState(() {
      _panelIndex = index;
      if (index == 4) {
        _browserMode = TaskBrowserLayoutMode.full;
      } else {
        _lastTaskPanelIndex = index;
        if (_browserMode.isVisible) {
          _browserMode = TaskBrowserLayoutMode.collapsed;
        }
      }
    });
    unawaited(_saveLayout());
  }

  Future<void> _showSectionSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _TaskPanelNavigation(
          selectedIndex: _panelIndex,
          onSelected: (index) => Navigator.of(context).pop(index),
        ),
      ),
    );
    if (selected != null) _selectPanel(selected);
  }

  Future<void> _showTaskActions(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.text('editTask')),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: Text(context.text('addNote')),
              onTap: () => Navigator.of(context).pop('note'),
            ),
            ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: Text(context.text('addInterruption')),
              onTap: () => Navigator.of(context).pop('interrupt'),
            ),
            ListTile(
              leading: const Icon(Icons.done_all_outlined),
              title: Text(context.text('completeTask')),
              onTap: () => Navigator.of(context).pop('complete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || selected == null) return;
    switch (selected) {
      case 'edit':
        _editTaskDialog(context, widget.controller, widget.task);
        break;
      case 'note':
        _addNote(context, widget.controller, widget.task);
        break;
      case 'interrupt':
        _addInterruption(context, widget.controller, widget.task);
        break;
      case 'complete':
        widget.controller.completeTask(widget.task);
        break;
    }
  }

  void _collapseBrowser() {
    setState(() {
      _browserMode = TaskBrowserLayoutMode.collapsed;
      if (_panelIndex == 4) _panelIndex = _lastTaskPanelIndex;
    });
    unawaited(_saveLayout());
  }

  void _toggleFullBrowser() {
    setState(() {
      if (_browserMode.isFull) {
        _browserMode = TaskBrowserLayoutMode.split;
        if (_panelIndex == 4) _panelIndex = _lastTaskPanelIndex;
      } else {
        _browserMode = TaskBrowserLayoutMode.full;
        _panelIndex = 4;
      }
    });
    unawaited(_saveLayout());
  }

  void _exitFullBrowser() {
    if (!_browserMode.isFull) return;
    _toggleFullBrowser();
  }

  void _toggleBrowserShortcut() {
    setState(() {
      if (_browserMode == TaskBrowserLayoutMode.collapsed) {
        _browserMode = MediaQuery.sizeOf(context).width < 600
            ? TaskBrowserLayoutMode.full
            : TaskBrowserLayoutMode.split;
        if (_browserMode.isFull) _panelIndex = 4;
      } else {
        _browserMode = TaskBrowserLayoutMode.collapsed;
        if (_panelIndex == 4) _panelIndex = _lastTaskPanelIndex;
      }
    });
    unawaited(_saveLayout());
  }

  Future<void> _restoreLayout() async {
    final state = await _TaskWorkspaceLayoutStore.load(widget.task.id);
    if (!mounted || state == null) return;
    setState(() {
      _panelIndex = state.selectedPanel.clamp(0, 9);
      _browserMode = state.browserMode;
      _browserWidth = state.browserWidth.clamp(360, 760);
      if (_panelIndex != 4) _lastTaskPanelIndex = _panelIndex;
      if (_panelIndex != 4 && _browserMode.isVisible) {
        _browserMode = TaskBrowserLayoutMode.collapsed;
      }
    });
  }

  Future<void> _saveLayout() {
    final save = _TaskWorkspaceLayoutStore.save(
      widget.task.id,
      browserMode: _browserMode,
      browserWidth: _browserWidth,
      selectedPanel: _panelIndex,
    );
    unawaited(_checkpointBrowserState());
    return save;
  }

  Future<void> _checkpointBrowserState() async {
    if (!AppServices.of(context).config.syncBrowserTabsAndUrls) return;
    await widget.controller.checkpointBrowserState(
      task: widget.task,
      tabs: _browserTabs,
      selectedTab: _selectedBrowserTab,
      browserExpanded: _browserMode.isVisible,
      browserMode: _browserMode.storageValue,
      browserWidth: _browserWidth,
      selectedPanel: _panelIndex,
    );
  }

  Future<void> _recordBrowserUsage({
    required String url,
    required String? title,
    required DateTime startedAt,
    required DateTime endedAt,
    required int activeSeconds,
  }) async {
    final active = widget.controller.activeSession;
    if (active == null ||
        active.task.id != widget.task.id ||
        active.isPaused ||
        !_browserMode.isVisible ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final services = AppServices.of(context);
    final lifecycleService = services.lifecycleService;
    final config = services.config;
    if (Platform.isWindows && !await lifecycleService.isWindowFocused()) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    final domain = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final registrableDomain = _registrableDomain(domain);
    if (domain.isEmpty ||
        _isSensitiveActivityDomain(domain) ||
        config.excludedActivityDomains.any(
          (excluded) => domain == excluded || domain.endsWith('.$excluded'),
        )) {
      return;
    }
    final relatedTaskId = await widget.controller.relatedTaskForDomain(
      domain,
      excludingTaskId: widget.task.id,
    );
    PomodoroController.observeWebsiteDuringBreak(
      domain,
      relatedTaskId: relatedTaskId,
    );
    TaskItem? relatedTask;
    if (relatedTaskId != null) {
      for (final task in widget.controller.tasks) {
        if (task.id == relatedTaskId) {
          relatedTask = task;
          break;
        }
      }
    }
    final storedUrl = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: config.trackFullUrls ? uri.path : '/',
      query: config.trackFullUrls && config.trackSearchQueries
          ? _safeActivityQuery(uri)
          : null,
    ).toString();
    final resources = await widget.controller.resourcesForTask(widget.task);
    final currentTaskResource = resources.any(
      (resource) => resource.domain == domain,
    );
    final records = <TaskUsageActivity>[
      TaskUsageActivity(
        taskId: widget.task.id,
        sessionId: active.session.id,
        type: TaskActivityType.website,
        domain: domain,
        url: storedUrl,
        pageTitle: config.trackPageTitles ? title : null,
        sourceTaskId: widget.task.id,
        relatedTaskId: relatedTask?.id,
        relatedRoadmapId: relatedTask?.roadmapId,
        relatedPhaseId: relatedTask?.roadmapPhaseId,
        normalizedDomain: domain,
        registrableDomain: registrableDomain,
        startedAt: startedAt,
        endedAt: endedAt,
        activeSeconds: activeSeconds,
        creditedSeconds: activeSeconds,
        isSavedResource: currentTaskResource,
      ),
      if (relatedTask != null)
        TaskUsageActivity(
          taskId: relatedTask.id,
          sessionId: active.session.id,
          type: TaskActivityType.website,
          domain: domain,
          url: storedUrl,
          pageTitle: config.trackPageTitles ? title : null,
          sourceTaskId: widget.task.id,
          relatedTaskId: relatedTask.id,
          relatedRoadmapId: relatedTask.roadmapId,
          relatedPhaseId: relatedTask.roadmapPhaseId,
          normalizedDomain: domain,
          registrableDomain: registrableDomain,
          startedAt: startedAt,
          endedAt: endedAt,
          activeSeconds: 0,
          creditedSeconds: activeSeconds,
          isSavedResource: true,
          attributionMethod: 'resource_domain_match',
          isCrossTaskContribution: true,
        ),
    ];
    await widget.controller.recordUsage(records);
  }

  Future<void> _sampleExternalApplication() async {
    if (_samplingApplication || !Platform.isWindows) return;
    final services = AppServices.of(context);
    final config = services.config;
    final active = widget.controller.activeSession;
    if (!config.trackExternalApplications ||
        active == null ||
        active.task.id != widget.task.id ||
        active.isPaused) {
      return;
    }
    _samplingApplication = true;
    try {
      final sample = await services.lifecycleService.sampleForegroundActivity();
      if (sample == null || sample['isTaskMasterWindow'] == true) return;
      final application = sample['applicationName']?.toString().trim() ?? '';
      if (application.isEmpty ||
          config.excludedActivityApplications.any(
            (excluded) => application.toLowerCase() == excluded.toLowerCase(),
          )) {
        return;
      }
      final idleSeconds = (sample['idleSeconds'] as num?)?.toInt() ?? 0;
      final now = DateTime.now();
      await widget.controller.recordUsage([
        TaskUsageActivity(
          taskId: widget.task.id,
          sessionId: active.session.id,
          type: TaskActivityType.application,
          applicationName: application,
          windowTitle: sample['windowTitle']?.toString(),
          startedAt: now.subtract(const Duration(seconds: 20)),
          endedAt: now,
          activeSeconds: idleSeconds >= 120 ? 0 : 20,
          idleSeconds: idleSeconds >= 120 ? 20 : 0,
        ),
      ]);
    } finally {
      _samplingApplication = false;
    }
  }
}

String? _safeActivityQuery(Uri uri) {
  const sensitiveNames = {
    'code',
    'state',
    'token',
    'channel_id',
    'authuser',
    'session_state',
    'id_token',
    'access_token',
  };
  final safe = <String, String>{};
  for (final entry in uri.queryParameters.entries) {
    if (!sensitiveNames.contains(entry.key.toLowerCase())) {
      safe[entry.key] = entry.value;
    }
  }
  return safe.isEmpty ? null : Uri(queryParameters: safe).query;
}

bool _isSensitiveActivityDomain(String domain) {
  const protected = <String>{
    'accounts.google.com',
    'appleid.apple.com',
    'login.microsoftonline.com',
    'login.live.com',
  };
  return protected.any(
    (value) => domain == value || domain.endsWith('.$value'),
  );
}

String _registrableDomain(String domain) {
  final normalized = domain.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final labels = normalized.split('.').where((label) => label.isNotEmpty);
  if (labels.length <= 2) {
    return normalized;
  }
  final list = labels.toList(growable: false);
  return '${list[list.length - 2]}.${list.last}';
}

class _TaskBrowserSlot extends StatefulWidget {
  const _TaskBrowserSlot({
    required this.controller,
    required this.task,
    required this.layoutMode,
    required this.resources,
    required this.onCollapse,
    required this.onToggleFull,
    required this.onEditTask,
    required this.onAddNote,
    required this.onStartWithoutWorkspace,
    required this.onAddCurrentPage,
    required this.onUsage,
    required this.onCheckpoint,
  });

  final TaskActionController controller;
  final TaskItem task;
  final TaskBrowserLayoutMode layoutMode;
  final List<TaskResource> resources;
  final VoidCallback onCollapse;
  final VoidCallback onToggleFull;
  final VoidCallback onEditTask;
  final VoidCallback onAddNote;
  final VoidCallback onStartWithoutWorkspace;
  final void Function(String url, String? title) onAddCurrentPage;
  final void Function(
    String url,
    String? title,
    DateTime startedAt,
    DateTime endedAt,
    int activeSeconds,
  )
  onUsage;
  final void Function(List<Map<String, dynamic>> tabs, int selectedTab)
  onCheckpoint;

  @override
  State<_TaskBrowserSlot> createState() => _TaskBrowserSlotState();
}

class _TaskBrowserSlotState extends State<_TaskBrowserSlot> {
  late bool _trackingActive;

  @override
  void initState() {
    super.initState();
    _trackingActive = false;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTrackingActive(notify: false);
  }

  @override
  void didUpdateWidget(_TaskBrowserSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.layoutMode != widget.layoutMode) {
      _updateTrackingActive(notify: false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    _updateTrackingActive();
  }

  void _updateTrackingActive({bool notify = true}) {
    final active = widget.controller.activeSession;
    final next =
        AppServices.of(context).config.trackBrowserActivity &&
        active?.task.id == widget.task.id &&
        active?.isPaused == false;
    if (next == _trackingActive) {
      return;
    }
    if (!mounted || !notify) {
      _trackingActive = next;
      return;
    }
    setState(() => _trackingActive = next);
  }

  @override
  Widget build(BuildContext context) {
    return TaskBrowserWorkspace(
      key: ValueKey('retained-task-browser-${widget.task.id}'),
      task: widget.task,
      layoutMode: widget.layoutMode,
      trackingActive: _trackingActive,
      resources: widget.resources,
      onCollapse: widget.onCollapse,
      onToggleFull: widget.onToggleFull,
      onEditTask: widget.onEditTask,
      onAddNote: widget.onAddNote,
      onStartWithoutWorkspace: widget.onStartWithoutWorkspace,
      onAddCurrentPage: widget.onAddCurrentPage,
      onUsage: widget.onUsage,
      onCheckpoint: widget.onCheckpoint,
    );
  }
}

class _LiveTaskWorkspaceControlBar extends StatelessWidget {
  const _LiveTaskWorkspaceControlBar({
    required this.controller,
    required this.task,
    required this.browserExpanded,
    required this.onToggleBrowser,
  });

  final TaskActionController controller;
  final TaskItem task;
  final bool browserExpanded;
  final VoidCallback onToggleBrowser;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _TaskWorkspaceControlBar(
        controller: controller,
        task: task,
        browserExpanded: browserExpanded,
        onToggleBrowser: onToggleBrowser,
      ),
    );
  }
}

class _LiveTaskPanelContent extends StatelessWidget {
  const _LiveTaskPanelContent({
    required this.selectedIndex,
    required this.controller,
    required this.task,
  });

  final int selectedIndex;
  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _TaskPanelContent(
        selectedIndex: selectedIndex,
        controller: controller,
        task: task,
      ),
    );
  }
}

class _LiveCompactTaskHeader extends StatelessWidget {
  const _LiveCompactTaskHeader({
    required this.controller,
    required this.task,
    required this.onMore,
  });

  final TaskActionController controller;
  final TaskItem task;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _CompactTaskHeader(
        controller: controller,
        task: task,
        onMore: onMore,
      ),
    );
  }
}

class _LiveMobileTaskActionBar extends StatelessWidget {
  const _LiveMobileTaskActionBar({
    required this.controller,
    required this.task,
    required this.onInternet,
    required this.onMore,
  });

  final TaskActionController controller;
  final TaskItem task;
  final VoidCallback onInternet;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _MobileTaskActionBar(
        controller: controller,
        task: task,
        onInternet: onInternet,
        onMore: onMore,
      ),
    );
  }
}

class _LiveCompactBrowserTaskIndicator extends StatelessWidget {
  const _LiveCompactBrowserTaskIndicator({
    required this.controller,
    required this.task,
    required this.onBackToTask,
  });

  final TaskActionController controller;
  final TaskItem task;
  final VoidCallback onBackToTask;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _CompactBrowserTaskIndicator(
        controller: controller,
        task: task,
        onBackToTask: onBackToTask,
      ),
    );
  }
}

class _TaskWorkspaceControlBar extends StatelessWidget {
  const _TaskWorkspaceControlBar({
    required this.controller,
    required this.task,
    required this.browserExpanded,
    required this.onToggleBrowser,
  });

  final TaskActionController controller;
  final TaskItem task;
  final bool browserExpanded;
  final VoidCallback onToggleBrowser;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeSession;
    final isActive = active?.task.id == task.id;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: isActive
                        ? ValueListenableBuilder<DateTime>(
                            valueListenable: controller.activeSessionClock,
                            builder: (context, _, child) {
                              final current = controller.activeSession;
                              if (current == null ||
                                  current.task.id != task.id) {
                                return Text(context.text('notRunning'));
                              }
                              final timing = current.timingAt(
                                controller.activeSessionClock.value,
                              );
                              return Text(
                                _headerTimerLabel(context, current, timing),
                              );
                            },
                          )
                        : Text(context.text('notRunning')),
                  ),
                  Chip(
                    avatar: const Icon(Icons.radar_outlined, size: 16),
                    label: Text(
                      task.taskType == TaskType.timed
                          ? context.text('continuousTimer')
                          : context.text(
                              'trackingMode_${task.workspaceBrowserMode.name}',
                            ),
                    ),
                  ),
                  Chip(label: Text('${task.progressPercentage}%')),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isActive)
                  AppButton.filled(
                    onPressed: () => controller.startTask(task),
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: Text(context.text('start')),
                  ),
                if (isActive && task.taskType == TaskType.focus)
                  ..._pomodoroActionButtons(
                    context,
                    controller,
                    task,
                    active!,
                    compact: false,
                  ),
                if (isActive &&
                    task.taskType != TaskType.focus &&
                    !active!.isPaused)
                  AppButton.filled(
                    onPressed: () => controller.pauseTask(task),
                    icon: const Icon(Icons.pause_outlined),
                    label: Text(context.text('pause')),
                  ),
                if (isActive &&
                    task.taskType != TaskType.focus &&
                    active!.isPaused)
                  AppButton.filled(
                    onPressed: () => controller.resumeTask(task),
                    icon: const Icon(Icons.play_arrow_outlined),
                    label: Text(context.text('resume')),
                  ),
                AppIconButton(
                  tooltip: context.text('editTask'),
                  onPressed: () => _editTaskDialog(context, controller, task),
                  icon: const Icon(Icons.edit_outlined),
                ),
                AppIconButton(
                  tooltip: context.text('addNote'),
                  onPressed: () => _addNote(context, controller, task),
                  icon: const Icon(Icons.note_add_outlined),
                ),
                AppIconButton(
                  tooltip: context.text('addInterruption'),
                  onPressed: () => _addInterruption(context, controller, task),
                  icon: const Icon(Icons.report_problem_outlined),
                ),
                AppButton.outlined(
                  onPressed: onToggleBrowser,
                  icon: const Icon(Icons.public_outlined),
                  label: Text(context.text('internet')),
                ),
                if (!(isActive && task.taskType == TaskType.focus))
                  AppButton.text(
                    onPressed: () => controller.completeTask(task),
                    icon: const Icon(Icons.done_all_outlined),
                    label: Text(context.text('completeTask')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactTaskHeader extends StatelessWidget {
  const _CompactTaskHeader({
    required this.controller,
    required this.task,
    required this.onMore,
  });

  final TaskActionController controller;
  final TaskItem task;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeSession;
    final isActive = active?.task.id == task.id;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: task.title,
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _CompactMetaChip(
                        icon: Icons.circle,
                        text: _humanStatus(context, task.status),
                      ),
                      if (task.displayStart != null)
                        _CompactMetaChip(
                          icon: Icons.schedule_outlined,
                          text: _formatTaskRange(
                            context,
                            task.displayStart,
                            task.displayEnd,
                          ),
                        ),
                      _CompactMetaChip(
                        icon: Icons.trending_up_outlined,
                        text: '${task.progressPercentage}%',
                      ),
                      if (isActive)
                        ValueListenableBuilder<DateTime>(
                          valueListenable: controller.activeSessionClock,
                          builder: (context, _, child) {
                            final current = controller.activeSession;
                            if (current == null || current.task.id != task.id) {
                              return const SizedBox.shrink();
                            }
                            return _CompactMetaChip(
                              icon: Icons.timer_outlined,
                              text: _headerTimerLabel(
                                context,
                                current,
                                current.timingAt(
                                  controller.activeSessionClock.value,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.text('moreOptions'),
              onPressed: onMore,
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactMetaChip extends StatelessWidget {
  const _CompactMetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTaskSectionBar extends StatelessWidget {
  const _CompactTaskSectionBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onMore,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final entries = <(int, IconData, String)>[
      (0, Icons.dashboard_outlined, context.text('overview')),
      (1, Icons.timer_outlined, context.text('timer')),
      (3, Icons.monitor_heart_outlined, context.text('activity')),
      (4, Icons.public_outlined, context.text('internet')),
    ];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ChoiceChip(
                    selected: selectedIndex == entry.$1,
                    avatar: Icon(entry.$2, size: 18),
                    label: Text(entry.$3),
                    onSelected: (_) => onSelected(entry.$1),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemCount: entries.length,
              ),
            ),
            IconButton(
              tooltip: context.text('moreOptions'),
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactBrowserTaskIndicator extends StatelessWidget {
  const _CompactBrowserTaskIndicator({
    required this.controller,
    required this.task,
    required this.onBackToTask,
  });

  final TaskActionController controller;
  final TaskItem task;
  final VoidCallback onBackToTask;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onBackToTask,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.arrow_back, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: controller.activeSessionClock,
                  builder: (context, _, child) {
                    final active = controller.activeSession;
                    final timer = active?.task.id == task.id
                        ? _headerTimerLabel(
                            context,
                            active!,
                            active.timingAt(
                              controller.activeSessionClock.value,
                            ),
                          )
                        : _humanStatus(context, task.status);
                    return Text(
                      '${task.title} · $timer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTaskActionBar extends StatelessWidget {
  const _MobileTaskActionBar({
    required this.controller,
    required this.task,
    required this.onInternet,
    required this.onMore,
  });

  final TaskActionController controller;
  final TaskItem task;
  final VoidCallback onInternet;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: ValueListenableBuilder<DateTime>(
            valueListenable: controller.activeSessionClock,
            builder: (context, _, child) {
              final active = controller.activeSession;
              final isActive = active?.task.id == task.id;
              final actions = isActive && task.taskType == TaskType.focus
                  ? _mobilePomodoroActions(
                      context,
                      controller,
                      task,
                      active!,
                      onInternet,
                      onMore,
                    )
                  : isActive
                  ? _mobileRunningActions(
                      context,
                      controller,
                      task,
                      active!,
                      onInternet,
                      onMore,
                    )
                  : <_MobileAction>[
                      _MobileAction(
                        Icons.play_arrow_outlined,
                        context.text('start'),
                        () => controller.startTask(task),
                      ),
                      _MobileAction(
                        Icons.note_add_outlined,
                        context.text('addNote'),
                        onMore,
                      ),
                      _MobileAction(
                        Icons.public_outlined,
                        context.text('internet'),
                        onInternet,
                      ),
                      _MobileAction(
                        Icons.more_horiz,
                        context.text('moreOptions'),
                        onMore,
                      ),
                    ];
              return Row(
                children: [
                  for (final action in actions)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Tooltip(
                          message: action.label,
                          child: TextButton.icon(
                            onPressed: action.onPressed,
                            icon: Icon(action.icon),
                            label: Text(
                              action.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobileAction {
  const _MobileAction(this.icon, this.label, this.onPressed);

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

List<_MobileAction> _mobileRunningActions(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
  ActiveTaskSession active,
  VoidCallback onInternet,
  VoidCallback onMore,
) {
  final isPaused = active.isPaused;
  return [
    _MobileAction(
      isPaused ? Icons.play_arrow_outlined : Icons.pause_outlined,
      isPaused ? context.text('resume') : context.text('pause'),
      () => isPaused ? controller.resumeTask(task) : controller.pauseTask(task),
    ),
    _MobileAction(
      Icons.done_all_outlined,
      context.text('finish'),
      () => controller.completeTask(task),
    ),
    _MobileAction(
      Icons.report_problem_outlined,
      context.text('interrupt'),
      onMore,
    ),
    _MobileAction(Icons.public_outlined, context.text('internet'), onInternet),
  ];
}

List<_MobileAction> _mobilePomodoroActions(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
  ActiveTaskSession active,
  VoidCallback onInternet,
  VoidCallback onMore,
) {
  return switch (active.pomodoroStage) {
    PomodoroStage.focusRunning => [
      _MobileAction(
        Icons.pause_outlined,
        context.text('pause'),
        () => controller.pauseTask(task),
      ),
      _MobileAction(
        Icons.done_all_outlined,
        context.text('finishFocus'),
        () => controller.finishPomodoroFocus(reason: 'finished_early'),
      ),
      _MobileAction(
        Icons.self_improvement_outlined,
        context.text('goToBreak'),
        () => controller.goToPomodoroBreak(),
      ),
      _MobileAction(
        Icons.public_outlined,
        context.text('internet'),
        onInternet,
      ),
    ],
    PomodoroStage.focusPaused => [
      _MobileAction(
        Icons.play_arrow_outlined,
        context.text('resume'),
        () => controller.resumeTask(task),
      ),
      _MobileAction(
        Icons.self_improvement_outlined,
        context.text('goToBreak'),
        () => controller.goToPomodoroBreak(),
      ),
      _MobileAction(
        Icons.public_outlined,
        context.text('internet'),
        onInternet,
      ),
      _MobileAction(Icons.more_horiz, context.text('moreOptions'), onMore),
    ],
    PomodoroStage.focusCompletedWaiting => [
      _MobileAction(
        Icons.self_improvement_outlined,
        context.text('startBreak'),
        () => controller.beginPomodoroBreak(),
      ),
      _MobileAction(
        Icons.skip_next_outlined,
        context.text('skipBreak'),
        () => controller.skipPomodoroBreak(),
      ),
      _MobileAction(
        Icons.public_outlined,
        context.text('internet'),
        onInternet,
      ),
      _MobileAction(Icons.more_horiz, context.text('moreOptions'), onMore),
    ],
    PomodoroStage.breakReady => [
      _MobileAction(
        Icons.self_improvement_outlined,
        context.text('startBreak'),
        () => controller.beginPomodoroBreak(),
      ),
      _MobileAction(
        Icons.skip_next_outlined,
        context.text('skipBreak'),
        () => controller.skipPomodoroBreak(),
      ),
      _MobileAction(
        Icons.public_outlined,
        context.text('internet'),
        onInternet,
      ),
      _MobileAction(Icons.more_horiz, context.text('moreOptions'), onMore),
    ],
    PomodoroStage.breakRunning => [
      _MobileAction(
        Icons.pause_outlined,
        context.text('pauseBreak'),
        () => controller.pauseTask(task),
      ),
      _MobileAction(
        Icons.done_all_outlined,
        context.text('finishBreak'),
        () => controller.finishPomodoroBreak(reason: 'finished_early'),
      ),
      _MobileAction(
        Icons.category_outlined,
        context.text('classifyActivity'),
        () => _showBreakActivityDialog(context, controller, task),
      ),
      _MobileAction(
        Icons.public_outlined,
        context.text('internet'),
        onInternet,
      ),
    ],
    PomodoroStage.breakPaused => [
      _MobileAction(
        Icons.play_arrow_outlined,
        context.text('resume'),
        () => controller.resumeTask(task),
      ),
      _MobileAction(
        Icons.play_circle_outline,
        context.text('returnToFocus'),
        () => controller.preparePomodoroFocus(),
      ),
      _MobileAction(
        Icons.public_outlined,
        context.text('internet'),
        onInternet,
      ),
      _MobileAction(Icons.more_horiz, context.text('moreOptions'), onMore),
    ],
    PomodoroStage.breakCompletedWaiting => [
      _MobileAction(
        Icons.play_arrow_outlined,
        context.text('startFocus'),
        () => controller.startPomodoroFocus(),
      ),
      _MobileAction(
        Icons.more_time_outlined,
        context.text('extendBreak'),
        () => controller.extendPomodoroBreak(),
      ),
      _MobileAction(
        Icons.category_outlined,
        context.text('classifyActivity'),
        () => _showBreakActivityDialog(context, controller, task),
      ),
      _MobileAction(Icons.more_horiz, context.text('moreOptions'), onMore),
    ],
    PomodoroStage.focusReady ||
    PomodoroStage.idle ||
    PomodoroStage.taskCompleted ||
    PomodoroStage.cancelled => [
      _MobileAction(
        Icons.play_arrow_outlined,
        context.text('startFocus'),
        () => controller.startPomodoroFocus(),
      ),
      _MobileAction(
        Icons.public_outlined,
        context.text('internet'),
        onInternet,
      ),
      _MobileAction(Icons.more_horiz, context.text('moreOptions'), onMore),
      _MobileAction(
        Icons.stop_circle_outlined,
        context.text('stopTask'),
        () => controller.stopActiveSession(),
      ),
    ],
  };
}

class _TaskPanelNavigation extends StatelessWidget {
  const _TaskPanelNavigation({
    required this.selectedIndex,
    required this.onSelected,
    this.iconOnly = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final entries = <(IconData, String)>[
      (Icons.dashboard_outlined, context.text('overview')),
      (Icons.timer_outlined, context.text('timer')),
      (Icons.insights_outlined, context.text('analytics')),
      (Icons.monitor_heart_outlined, context.text('activity')),
      (Icons.public_outlined, context.text('internet')),
      (Icons.link_outlined, context.text('resources')),
      (Icons.note_alt_outlined, context.text('notes')),
      (Icons.history_outlined, context.text('history')),
      (Icons.attach_file_outlined, context.text('attachments')),
      (Icons.settings_outlined, context.text('settings')),
    ];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) => Tooltip(
        message: entries[index].$2,
        child: ListTile(
          dense: true,
          selected: selectedIndex == index,
          leading: Icon(entries[index].$1),
          title: iconOnly ? null : Text(entries[index].$2),
          onTap: () => onSelected(index),
        ),
      ),
    );
  }
}

class _TaskPanelContent extends StatelessWidget {
  const _TaskPanelContent({
    required this.selectedIndex,
    required this.controller,
    required this.task,
  });

  final int selectedIndex;
  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return switch (selectedIndex) {
      0 => _TaskExecutionDashboard(controller: controller, task: task),
      1 => _TimerTab(controller: controller, task: task),
      2 => _TaskAnalyticsPanel(controller: controller, task: task),
      3 => _TaskActivityPanel(controller: controller, task: task),
      4 => const SizedBox.shrink(),
      5 => _ResourcesTab(controller: controller, task: task),
      6 => _NotesTab(controller: controller, task: task),
      7 => _HistoryTab(controller: controller, task: task),
      8 => _AttachmentsPanel(task: task),
      _ => _TaskSettingsPanel(controller: controller, task: task),
    };
  }
}

class _BrowserResizeHandle extends StatelessWidget {
  const _BrowserResizeHandle({required this.onDrag, required this.onDragEnd});

  final ValueChanged<double> onDrag;
  final Future<void> Function() onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      onHorizontalDragEnd: (_) => onDragEnd(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 8,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _TaskExecutionDashboard extends StatefulWidget {
  const _TaskExecutionDashboard({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  State<_TaskExecutionDashboard> createState() =>
      _TaskExecutionDashboardState();
}

class _TaskExecutionDashboardState extends State<_TaskExecutionDashboard> {
  late Future<_ExecutionData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _TaskExecutionDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.updatedAt != widget.task.updatedAt) {
      _future = _load();
    }
  }

  Future<_ExecutionData> _load() async {
    final sessions = await widget.controller.sessionsForTask(widget.task.id);
    final usage = await widget.controller.usageForTask(widget.task.id);
    return _ExecutionData(sessions: sessions, usage: usage);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ExecutionData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _ExecutionData();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _TaskTypeDashboard(
              controller: widget.controller,
              task: widget.task,
              data: data,
            ),
            const _TaskHealthContextCard(),
            const SizedBox(height: 20),
            if (data.sessions.isEmpty)
              _FirstSessionGuidance(
                controller: widget.controller,
                task: widget.task,
              )
            else
              _LiveExecutionSummary(
                controller: widget.controller,
                task: widget.task,
                data: data,
              ),
          ],
        );
      },
    );
  }
}

class _TaskHealthContextCard extends StatelessWidget {
  const _TaskHealthContextCard();

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).healthDataService;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final summary = service.summary;
        if (summary == null || !service.healthConnectStatus.hasConnection) {
          return const SizedBox.shrink();
        }
        final metrics = <_MetricValue>[
          _MetricValue(context.text('steps'), '${summary.steps}'),
          _MetricValue(
            context.text('activeMinutes'),
            '${summary.activeMinutes} min',
          ),
          if (summary.lastSleepMinutes != null)
            _MetricValue(
              context.text('lastSleep'),
              formatDurationCompact(summary.lastSleepMinutes! * 60),
            ),
          if (summary.latestHeartRate != null)
            _MetricValue(
              context.text('latestHeartRate'),
              '${summary.latestHeartRate} bpm',
            ),
        ];
        if (metrics.every(
          (metric) => metric.value == '0' || metric.value == '0 min',
        )) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.health_and_safety_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        context.text('healthAndActivity'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final metric in metrics)
                        _SummaryMetric(
                          label: metric.label,
                          value: metric.value,
                        ),
                    ],
                  ),
                  if (summary.dataSources.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      summary.dataSources.take(3).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appColors.mutedText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TaskTypeDashboard extends StatelessWidget {
  const _TaskTypeDashboard({
    required this.controller,
    required this.task,
    required this.data,
  });

  final TaskActionController controller;
  final TaskItem task;
  final _ExecutionData data;

  @override
  Widget build(BuildContext context) {
    return switch (task.taskType) {
      TaskType.focus => _FocusExecutionCard(
        controller: controller,
        task: task,
        data: data,
      ),
      TaskType.timed => _TimedExecutionCard(
        controller: controller,
        task: task,
        data: data,
      ),
      TaskType.event => _EventExecutionCard(controller: controller, task: task),
      TaskType.habit => _HabitExecutionCard(controller: controller, task: task),
      TaskType.reading => _ReadingExecutionCard(task: task),
      TaskType.manual => _ManualExecutionCard(
        controller: controller,
        task: task,
      ),
    };
  }
}

class _FocusExecutionCard extends StatelessWidget {
  const _FocusExecutionCard({
    required this.controller,
    required this.task,
    required this.data,
  });

  final TaskActionController controller;
  final TaskItem task;
  final _ExecutionData data;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: controller.activeSessionClock,
      builder: (context, _, child) {
        final active = controller.activeSession;
        final running = active?.task.id == task.id;
        final timing = running
            ? active!.timingAt(controller.activeSessionClock.value)
            : null;
        final sessionSeconds = timing?.pomodoroSeconds ?? 25 * 60;
        final historicalSeconds = data.sessions
            .where((session) => session.id != active?.session.id)
            .fold<int>(0, (sum, session) => sum + session.activeSeconds);
        final completedPomodoros =
            (historicalSeconds ~/ sessionSeconds) +
            (timing?.completedPomodoros ?? 0);
        final planned = task.estimatedPomodoros.clamp(1, 999);
        final safeCompleted = completedPomodoros.clamp(0, planned);
        final isBreak = timing?.pomodoroStage.isBreakStage == true;
        final waitingForUser =
            timing?.pomodoroStage == PomodoroStage.focusCompletedWaiting ||
            timing?.pomodoroStage == PomodoroStage.breakCompletedWaiting ||
            timing?.pomodoroStage == PomodoroStage.breakReady;
        final remaining = isBreak
            ? timing?.breakRemainingSeconds ?? 5 * 60
            : timing?.pomodoroRemainingSeconds ?? sessionSeconds;
        final totalFocused = historicalSeconds + (timing?.activeSeconds ?? 0);
        return _ExecutionCard(
          title: task.title,
          subtitle: running
              ? _pomodoroExecutionSubtitle(
                  context,
                  timing!,
                  safeCompleted,
                  planned,
                )
              : '$planned ${context.text('pomodorosPlanned')}',
          timerSeconds: remaining,
          progress: isBreak
              ? (timing == null || timing.breakPlannedSeconds <= 0
                    ? 0
                    : (timing.currentBreakElapsedSeconds /
                              timing.breakPlannedSeconds)
                          .clamp(0.0, 1.0))
              : timing?.pomodoroProgress ?? 0,
          progressLabel: waitingForUser
              ? context.text('waitingForYou')
              : '${((1 - (isBreak ? ((timing?.currentBreakElapsedSeconds ?? 0) / ((timing?.breakPlannedSeconds ?? 300).clamp(1, 1 << 31))) : (timing?.pomodoroProgress ?? 0))) * 100).round()}% ${context.text('remaining').toLowerCase()}',
          visualState: waitingForUser
              ? _TimerVisualState.nearEnd
              : active?.isPaused == true
              ? _TimerVisualState.paused
              : running
              ? _TimerVisualState.running
              : _TimerVisualState.idle,
          metrics: [
            _MetricValue(
              context.text('completedPomodoros'),
              '$safeCompleted / $planned',
            ),
            _MetricValue(
              context.text('remaining'),
              '${(planned - safeCompleted).clamp(0, planned)}',
            ),
            _MetricValue(
              context.text('totalFocusedToday'),
              formatDurationCompact(totalFocused),
            ),
            _MetricValue(
              context.text('nextBreak'),
              '${task.reminderRules['break_minutes'] ?? 5} ${context.text('minutes')}',
            ),
          ],
          controls: _ExecutionControls(controller: controller, task: task),
        );
      },
    );
  }
}

String _pomodoroExecutionSubtitle(
  BuildContext context,
  ActiveSessionTiming timing,
  int completed,
  int planned,
) {
  return switch (timing.pomodoroStage) {
    PomodoroStage.focusCompletedWaiting => context.text('focusCompleted'),
    PomodoroStage.breakReady => context.text('breakReady'),
    PomodoroStage.breakRunning ||
    PomodoroStage.breakPaused => context.text('break'),
    PomodoroStage.breakCompletedWaiting => context.text('breakCompleted'),
    _ =>
      '${context.text('focusSession')} ${(completed + 1).clamp(1, planned)} ${context.text('of')} $planned',
  };
}

class _TimedExecutionCard extends StatelessWidget {
  const _TimedExecutionCard({
    required this.controller,
    required this.task,
    required this.data,
  });

  final TaskActionController controller;
  final TaskItem task;
  final _ExecutionData data;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: controller.activeSessionClock,
      builder: (context, _, child) {
        final active = controller.activeSession;
        final running = active?.task.id == task.id;
        final timing = running
            ? active!.timingAt(controller.activeSessionClock.value)
            : null;
        final elapsed = timing?.activeSeconds ?? data.activeSeconds;
        final planned = timing?.plannedSeconds ?? task.estimatedMinutes * 60;
        final remaining = (planned - elapsed).clamp(0, planned);
        final overtime = (elapsed - planned).clamp(0, 1 << 31);
        final variance = elapsed - planned;
        final progress = planned <= 0
            ? 0.0
            : (elapsed / planned).clamp(0.0, 1.0);
        final visualState = active?.isPaused == true
            ? _TimerVisualState.paused
            : overtime > 0
            ? _TimerVisualState.overtime
            : running && progress >= 0.85
            ? _TimerVisualState.nearEnd
            : running
            ? _TimerVisualState.running
            : task.isCompleted
            ? _TimerVisualState.completed
            : _TimerVisualState.idle;
        return _ExecutionCard(
          title: task.title,
          subtitle: active?.isPaused == true
              ? context.text('paused')
              : overtime > 0
              ? context.text('overtime')
              : running
              ? context.text('elapsedTime')
              : '${context.text('plannedDuration')}: ${formatDurationCompact(planned)}',
          timerSeconds: elapsed,
          countUp: true,
          progress: progress,
          visualState: visualState,
          progressLabel: planned <= 0
              ? null
              : '${(elapsed * 100 / planned).round()}% ${context.text('ofPlannedTime')}',
          metrics: [
            _MetricValue(
              context.text('planned'),
              formatDurationCompact(planned),
            ),
            if (overtime == 0)
              _MetricValue(
                context.text('remainingPlannedTime'),
                formatDurationCompact(remaining),
              )
            else
              _MetricValue(
                context.text('overtime'),
                '+${formatDurationCompact(overtime)}',
              ),
            if (running && remaining > 0)
              _MetricValue(
                context.text('expectedFinish'),
                MaterialLocalizations.of(context).formatTimeOfDay(
                  TimeOfDay.fromDateTime(
                    (timing?.observedAt ?? DateTime.now()).add(
                      Duration(seconds: remaining),
                    ),
                  ),
                ),
              ),
            if (task.isCompleted)
              _MetricValue(
                variance <= 0
                    ? context.text('finishedEarly')
                    : context.text('exceededPlan'),
                formatDurationCompact(variance.abs()),
              ),
          ],
          controls: _ExecutionControls(controller: controller, task: task),
        );
      },
    );
  }
}

class _EventExecutionCard extends StatelessWidget {
  const _EventExecutionCard({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final start = task.displayStart;
    final seconds = start == null
        ? 0
        : start.difference(DateTime.now()).inSeconds.clamp(0, 8640000);
    return _ExecutionCard(
      title: task.title,
      subtitle: context.text('startsIn'),
      timerSeconds: seconds,
      progress: 0,
      metrics: [
        _MetricValue(
          context.text('scheduled'),
          _formatTaskRange(context, task.displayStart, task.displayEnd),
        ),
        if (task.location?.isNotEmpty == true)
          _MetricValue(context.text('location'), task.location!),
        if (task.arrivalAt != null)
          _MetricValue(
            context.text('arrivalTime'),
            _formatTaskDateTime(context, task.arrivalAt),
          ),
      ],
      controls: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          AppButton.outlined(
            onPressed: task.arrivalAt == null
                ? () => controller.markEventArrived(task)
                : null,
            icon: const Icon(Icons.location_on_outlined),
            label: Text(context.text('markArrived')),
          ),
          _ExecutionControls(controller: controller, task: task),
        ],
      ),
    );
  }
}

class _HabitExecutionCard extends StatelessWidget {
  const _HabitExecutionCard({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return _ExecutionCard(
      title: task.title,
      subtitle: _formatTaskRange(context, task.displayStart, task.displayEnd),
      timerSeconds: null,
      progress: task.habitLongestStreak <= 0
          ? 0
          : (task.habitCurrentStreak / task.habitLongestStreak).clamp(0.0, 1.0),
      metrics: [
        _MetricValue(
          context.text('currentStreak'),
          '${task.habitCurrentStreak} ${context.text('days')}',
        ),
        _MetricValue(
          context.text('longestStreak'),
          '${task.habitLongestStreak} ${context.text('days')}',
        ),
      ],
      controls: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          AppButton.filled(
            onPressed: () => controller.completeTask(task),
            icon: const Icon(Icons.done_outlined),
            label: Text(context.text('done')),
          ),
          AppButton.outlined(
            onPressed: () => controller.skipToday(task),
            icon: const Icon(Icons.skip_next_outlined),
            label: Text(context.text('skipToday')),
          ),
          if (task.timerEnabled)
            _ExecutionControls(controller: controller, task: task),
        ],
      ),
    );
  }
}

class _ReadingExecutionCard extends StatefulWidget {
  const _ReadingExecutionCard({required this.task});

  final TaskItem task;

  @override
  State<_ReadingExecutionCard> createState() => _ReadingExecutionCardState();
}

class _ReadingExecutionCardState extends State<_ReadingExecutionCard> {
  Future<List<ReadingBook>>? _books;

  Future<List<ReadingBook>> _load() {
    return LearningActivityRepository(
      AppServices.of(context).supabaseService,
    ).loadBooks(widget.task.id);
  }

  void _refresh() => setState(() => _books = _load());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _books ??= _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReadingBook>>(
      future: _books,
      builder: (context, snapshot) {
        final books = snapshot.data ?? const <ReadingBook>[];
        final current =
            books
                .where((book) => book.status != BookStatus.completed)
                .firstOrNull ??
            books.firstOrNull;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.text('readingDashboard'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    AppButton.outlined(
                      onPressed: _addBook,
                      icon: const Icon(Icons.add),
                      label: Text(context.text('addBook')),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (current == null)
                  _ReadingEmptyState(onAddBook: _addBook)
                else ...[
                  Text(
                    context.text('currentBook'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    current.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  if (current.author.isNotEmpty) Text(current.author),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: current.progress),
                  const SizedBox(height: 8),
                  Text(
                    '${current.currentPage} / ${current.totalPages} · '
                    '${(current.progress * 100).toStringAsFixed(1)}%',
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      AppButton.filled(
                        onPressed: () => _recordSession(current),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(context.text('startExternalReading')),
                      ),
                      if (current.webUrl?.isNotEmpty == true)
                        AppButton.outlined(
                          onPressed: () => _openBookUrl(current.webUrl!),
                          icon: const Icon(Icons.language),
                          label: Text(context.text('open')),
                        ),
                      if (current.localFileReference?.isNotEmpty == true)
                        AppButton.outlined(
                          onPressed: () =>
                              _openLocalBook(current.localFileReference!),
                          icon: const Icon(Icons.file_open_outlined),
                          label: Text(context.text('openBook')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.text('books'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final book in books)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.book_outlined),
                      title: Text(book.title),
                      subtitle: Text(
                        '${book.currentPage} / ${book.totalPages}',
                      ),
                      trailing: Text('${(book.progress * 100).round()}%'),
                      onTap: () => _recordSession(book),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addBook() async {
    final book = await showDialog<ReadingBook>(
      context: context,
      builder: (context) => _AddBookDialog(taskId: widget.task.id),
    );
    if (book == null || !mounted) return;
    await LearningActivityRepository(
      AppServices.of(context).supabaseService,
    ).saveBook(book);
    if (mounted) _refresh();
  }

  Future<void> _recordSession(ReadingBook book) async {
    final session = await showDialog<ReadingSession>(
      context: context,
      builder: (context) => _ReadingSessionDialog(book: book),
    );
    if (session == null || !mounted) return;
    await LearningActivityRepository(
      AppServices.of(context).supabaseService,
    ).recordReadingSession(book: book, session: session);
    if (mounted) _refresh();
  }

  void _openBookUrl(String url) {
    const channel = MethodChannel('taskmasterpro/task_browser');
    channel.invokeMethod<void>('openExternal', {'url': url});
  }

  Future<void> _openLocalBook(String reference) async {
    const channel = MethodChannel('taskmasterpro/profile_files');
    await channel.invokeMethod<void>('openReadingFile', {
      'reference': reference,
    });
  }
}

class _ReadingEmptyState extends StatelessWidget {
  const _ReadingEmptyState({required this.onAddBook});

  final VoidCallback onAddBook;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.auto_stories_outlined, size: 72),
          const SizedBox(height: 16),
          Text(
            context.text('books'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AppButton.filled(
            onPressed: onAddBook,
            icon: const Icon(Icons.add),
            label: Text(context.text('addBook')),
          ),
        ],
      ),
    );
  }
}

class _AddBookDialog extends StatefulWidget {
  const _AddBookDialog({required this.taskId});

  final String taskId;

  @override
  State<_AddBookDialog> createState() => _AddBookDialogState();
}

class _AddBookDialogState extends State<_AddBookDialog> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _pages = TextEditingController();
  final _webUrl = TextEditingController();
  BookFormat _format = BookFormat.physical;
  String? _localReference;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _pages.dispose();
    _webUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.text('addBook')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: context.text('bookTitle'),
                ),
              ),
              TextField(
                controller: _author,
                decoration: InputDecoration(
                  labelText: context.text('bookAuthor'),
                ),
              ),
              TextField(
                controller: _pages,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.text('totalPages'),
                ),
              ),
              DropdownButtonFormField<BookFormat>(
                initialValue: _format,
                decoration: InputDecoration(
                  labelText: context.text('bookFormat'),
                ),
                items: [
                  for (final format in BookFormat.values)
                    DropdownMenuItem(
                      value: format,
                      child: Text(context.text('bookFormat_${format.name}')),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _format = value ?? _format),
              ),
              if (_format == BookFormat.pdf || _format == BookFormat.epub)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file_outlined),
                  title: Text(context.text('chooseBookFile')),
                  subtitle: Text(
                    _localReference ?? context.text('bookStaysOnDevice'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                  ),
                  onTap: () async {
                    const channel = MethodChannel(
                      'taskmasterpro/profile_files',
                    );
                    final path = await channel.invokeMethod<String>(
                      'pickReadingFile',
                    );
                    if (mounted && path != null) {
                      setState(() => _localReference = path);
                    }
                  },
                ),
              TextField(
                controller: _webUrl,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.text('webReadingUrl'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton.text(
          onPressed: () => Navigator.pop(context),
          label: Text(context.text('cancel')),
        ),
        AppButton.filled(
          onPressed: () {
            final pages = int.tryParse(_pages.text.trim());
            if (_title.text.trim().isEmpty || pages == null || pages <= 0) {
              return;
            }
            Navigator.pop(
              context,
              ReadingBook(
                readingTaskId: widget.taskId,
                title: _title.text.trim(),
                author: _author.text.trim(),
                totalPages: pages,
                format: _format,
                localFileReference: _localReference,
                localDeviceId: Platform.operatingSystem,
                webUrl: _webUrl.text.trim().isEmpty
                    ? null
                    : _webUrl.text.trim(),
              ),
            );
          },
          label: Text(context.text('save')),
        ),
      ],
    );
  }
}

class _ReadingSessionDialog extends StatefulWidget {
  const _ReadingSessionDialog({required this.book});

  final ReadingBook book;

  @override
  State<_ReadingSessionDialog> createState() => _ReadingSessionDialogState();
}

class _ReadingSessionDialogState extends State<_ReadingSessionDialog> {
  late final TextEditingController _startPage;
  late final TextEditingController _endPage;
  final _minutes = TextEditingController(text: '25');

  @override
  void initState() {
    super.initState();
    _startPage = TextEditingController(
      text: widget.book.currentPage.toString(),
    );
    _endPage = TextEditingController(text: widget.book.currentPage.toString());
  }

  @override
  void dispose() {
    _startPage.dispose();
    _endPage.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.book.title),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _startPage,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.text('startedAtPage'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _endPage,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.text('finishedAtPage'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.text('readingMinutes'),
              ),
            ),
          ),
        ],
      ),
      actions: [
        AppButton.text(
          onPressed: () => Navigator.pop(context),
          label: Text(context.text('cancel')),
        ),
        AppButton.filled(
          onPressed: () {
            final start = int.tryParse(_startPage.text) ?? -1;
            final end = int.tryParse(_endPage.text) ?? -1;
            final minutes = int.tryParse(_minutes.text) ?? 0;
            if (start < 0 ||
                end < start ||
                end > widget.book.totalPages ||
                minutes <= 0) {
              return;
            }
            final ended = DateTime.now();
            Navigator.pop(
              context,
              ReadingSession(
                taskId: widget.book.readingTaskId,
                bookId: widget.book.id,
                startPage: start,
                endPage: end,
                previousBookPage: widget.book.currentPage,
                durationSeconds: minutes * 60,
                startedAt: ended.subtract(Duration(minutes: minutes)),
                endedAt: ended,
              ),
            );
          },
          label: Text(context.text('save')),
        ),
      ],
    );
  }
}

class _ManualExecutionCard extends StatelessWidget {
  const _ManualExecutionCard({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return _ExecutionCard(
      title: task.title,
      subtitle: context.text('completionOnlyTask'),
      timerSeconds: null,
      progress: task.progressPercentage / 100,
      metrics: const [],
      controls: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          AppButton.filled(
            onPressed: () => controller.completeTask(task),
            icon: const Icon(Icons.done_outlined),
            label: Text(context.text('done')),
          ),
          AppButton.outlined(
            onPressed: () => controller.skipToday(task),
            icon: const Icon(Icons.skip_next_outlined),
            label: Text(context.text('skipToday')),
          ),
          AppButton.text(
            onPressed: () => controller.cancelTask(task),
            label: Text(context.text('cancelTask')),
          ),
        ],
      ),
    );
  }
}

class _ExecutionCard extends StatelessWidget {
  const _ExecutionCard({
    required this.title,
    required this.subtitle,
    required this.timerSeconds,
    required this.progress,
    required this.metrics,
    required this.controls,
    this.countUp = false,
    this.visualState = _TimerVisualState.idle,
    this.progressLabel,
  });

  final String title;
  final String subtitle;
  final int? timerSeconds;
  final double progress;
  final List<_MetricValue> metrics;
  final Widget controls;
  final bool countUp;
  final _TimerVisualState visualState;
  final String? progressLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        if (timerSeconds != null)
          _LiveTimerRing(
            seconds: timerSeconds!,
            progress: progress,
            visualState: visualState,
            progressLabel: progressLabel,
          )
        else
          Icon(
            Icons.check_circle_outline,
            size: 112,
            color: Theme.of(context).colorScheme.primary,
          ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: 170,
                child: Column(
                  children: [
                    Text(
                      metric.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(metric.label, textAlign: TextAlign.center),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        controls,
      ],
    );
  }
}

enum _TimerVisualState { idle, running, nearEnd, overtime, paused, completed }

class _LiveTimerRing extends StatefulWidget {
  const _LiveTimerRing({
    required this.seconds,
    required this.progress,
    required this.visualState,
    this.progressLabel,
  });

  final int seconds;
  final double progress;
  final _TimerVisualState visualState;
  final String? progressLabel;

  @override
  State<_LiveTimerRing> createState() => _LiveTimerRingState();
}

class _LiveTimerRingState extends State<_LiveTimerRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;

  bool get _isMoving => switch (widget.visualState) {
    _TimerVisualState.running ||
    _TimerVisualState.nearEnd ||
    _TimerVisualState.overtime => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant _LiveTimerRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visualState != widget.visualState) _updateAnimation();
  }

  void _updateAnimation() {
    final reduceMotion =
        MediaQuery.of(context).disableAnimations ||
        AppServices.of(context).config.reducedMotion;
    if (_isMoving && !reduceMotion) {
      if (!_sweepController.isAnimating) _sweepController.repeat();
    } else {
      _sweepController.stop();
    }
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (widget.visualState) {
      _TimerVisualState.nearEnd => colors.tertiary,
      _TimerVisualState.overtime => colors.error,
      _TimerVisualState.paused => colors.outline,
      _TimerVisualState.completed => colors.secondary,
      _ => colors.primary,
    };
    final reduceMotion =
        MediaQuery.of(context).disableAnimations ||
        AppServices.of(context).config.reducedMotion;
    return SizedBox.square(
      dimension: 218,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: widget.progress.clamp(0.0, 1.0)),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, progress, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 12,
                color: color,
                strokeCap: StrokeCap.round,
                backgroundColor: colors.surfaceContainerHighest,
              ),
              if (_isMoving && !reduceMotion)
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: RotationTransition(
                    turns: _sweepController,
                    child: CircularProgressIndicator(
                      value: 0.07,
                      strokeWidth: 3,
                      color: color.withValues(alpha: 0.62),
                      backgroundColor: Colors.transparent,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child: Text(
                        _clock(widget.seconds),
                        key: ValueKey(widget.seconds),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    if (widget.progressLabel case final label?) ...[
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ExecutionControls extends StatelessWidget {
  const _ExecutionControls({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeSession;
    final running = active?.task.id == task.id;
    if (running && task.taskType == TaskType.focus) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: _pomodoroActionButtons(
          context,
          controller,
          task,
          active!,
          compact: false,
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!running)
          AppButton.filled(
            onPressed: () => controller.startTask(task),
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(
              context.text(
                task.taskType == TaskType.focus ? 'startFocus' : 'startTask',
              ),
            ),
          ),
        if (running && !active!.isPaused)
          AppButton.filled(
            onPressed: () => controller.pauseTask(task),
            icon: const Icon(Icons.pause_outlined),
            label: Text(context.text('pause')),
          ),
        if (running && active!.isPaused)
          AppButton.filled(
            onPressed: () => controller.resumeTask(task),
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(context.text('resume')),
          ),
        if (running)
          AppButton.outlined(
            onPressed: () => controller.completeTask(task),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(context.text('finish')),
          ),
      ],
    );
  }
}

List<Widget> _pomodoroActionButtons(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
  ActiveTaskSession active, {
  required bool compact,
}) {
  AppButton filled(String key, IconData icon, VoidCallback onPressed) =>
      AppButton.filled(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(context.text(key)),
      );
  AppButton outlined(String key, IconData icon, VoidCallback onPressed) =>
      AppButton.outlined(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(context.text(key)),
      );

  return switch (active.pomodoroStage) {
    PomodoroStage.focusRunning => [
      filled('pause', Icons.pause_outlined, () => controller.pauseTask(task)),
      outlined(
        'finishFocus',
        Icons.done_all_outlined,
        () => controller.finishPomodoroFocus(reason: 'finished_early'),
      ),
      outlined(
        'goToBreak',
        Icons.self_improvement_outlined,
        () => controller.goToPomodoroBreak(),
      ),
      if (!compact)
        outlined(
          'stopTask',
          Icons.stop_circle_outlined,
          () => controller.stopActiveSession(),
        ),
    ],
    PomodoroStage.focusPaused => [
      filled(
        'resume',
        Icons.play_arrow_outlined,
        () => controller.resumeTask(task),
      ),
      outlined(
        'goToBreak',
        Icons.self_improvement_outlined,
        () => controller.goToPomodoroBreak(),
      ),
      if (!compact)
        outlined(
          'stopTask',
          Icons.stop_circle_outlined,
          () => controller.stopActiveSession(),
        ),
    ],
    PomodoroStage.focusCompletedWaiting => [
      filled(
        'startBreak',
        Icons.self_improvement_outlined,
        () => controller.beginPomodoroBreak(),
      ),
      outlined(
        'skipBreak',
        Icons.skip_next_outlined,
        () => controller.skipPomodoroBreak(),
      ),
      outlined(
        'continueWorking',
        Icons.more_time_outlined,
        () => controller.continuePomodoroFocus(),
      ),
      if (!compact)
        outlined(
          'finishTask',
          Icons.done_all_outlined,
          () => controller.completeTask(task),
        ),
    ],
    PomodoroStage.breakReady => [
      filled(
        'startBreak',
        Icons.self_improvement_outlined,
        () => controller.beginPomodoroBreak(),
      ),
      outlined(
        'skipBreak',
        Icons.skip_next_outlined,
        () => controller.skipPomodoroBreak(),
      ),
      outlined(
        'returnToFocus',
        Icons.play_circle_outline,
        () => controller.preparePomodoroFocus(),
      ),
    ],
    PomodoroStage.breakRunning => [
      filled(
        'pauseBreak',
        Icons.pause_outlined,
        () => controller.pauseTask(task),
      ),
      outlined(
        'finishBreak',
        Icons.done_all_outlined,
        () => controller.finishPomodoroBreak(reason: 'finished_early'),
      ),
      outlined(
        'returnToFocus',
        Icons.play_circle_outline,
        () => controller.preparePomodoroFocus(),
      ),
      if (!compact)
        outlined(
          'classifyActivity',
          Icons.category_outlined,
          () => _showBreakActivityDialog(context, controller, task),
        ),
    ],
    PomodoroStage.breakPaused => [
      filled(
        'resume',
        Icons.play_arrow_outlined,
        () => controller.resumeTask(task),
      ),
      outlined(
        'finishBreak',
        Icons.done_all_outlined,
        () => controller.finishPomodoroBreak(reason: 'finished_early'),
      ),
      outlined(
        'returnToFocus',
        Icons.play_circle_outline,
        () => controller.preparePomodoroFocus(),
      ),
    ],
    PomodoroStage.breakCompletedWaiting => [
      filled(
        'startFocus',
        Icons.play_arrow_outlined,
        () => controller.startPomodoroFocus(),
      ),
      outlined(
        'extendBreak',
        Icons.more_time_outlined,
        () => controller.extendPomodoroBreak(),
      ),
      outlined(
        'finishTask',
        Icons.done_all_outlined,
        () => controller.completeTask(task),
      ),
      if (!compact)
        outlined(
          'recordBreakActivity',
          Icons.category_outlined,
          () => _showBreakActivityDialog(context, controller, task),
        ),
    ],
    PomodoroStage.focusReady ||
    PomodoroStage.idle ||
    PomodoroStage.taskCompleted ||
    PomodoroStage.cancelled => [
      filled(
        'startFocus',
        Icons.play_arrow_outlined,
        () => controller.startPomodoroFocus(),
      ),
    ],
  };
}

Future<void> _showBreakActivityDialog(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
) async {
  final active = controller.activeSession;
  if (active == null || active.task.id != task.id) return;
  final result = await showDialog<PomodoroBreakUse>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.text('breakActivityQuestion')),
      children: [
        for (final use in const [
          PomodoroBreakUse.rest,
          PomodoroBreakUse.learning,
          PomodoroBreakUse.reading,
          PomodoroBreakUse.exercise,
          PomodoroBreakUse.housework,
          PomodoroBreakUse.anotherTask,
          PomodoroBreakUse.custom,
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(use),
            child: Text(context.text('breakUse_${use.name}')),
          ),
      ],
    ),
  );
  if (result == null || !context.mounted) return;
  final services = AppServices.of(context);
  final successMessage = context.text('breakActivityRecorded');
  final relatedTask = _suggestBreakRelatedTask(result, controller.tasks);
  await controller.recordPomodoroBreakActivity(
    result,
    relatedTaskId: relatedTask?.id,
  );
  if (relatedTask != null && result != PomodoroBreakUse.rest) {
    final timing = active.timingAt(controller.activeSessionClock.value);
    final duration = timing.currentBreakElapsedSeconds > 0
        ? timing.currentBreakElapsedSeconds
        : 5 * 60;
    await LearningActivityRepository(
      services.supabaseService,
    ).recordBreakContribution(
      BreakContribution(
        sourceTaskId: task.id,
        sourceSessionId: active.session.id,
        relatedTaskId: relatedTask.id,
        type: _breakContributionType(result),
        durationSeconds: duration,
        evidenceType: 'manual_break_classification',
        userConfirmed: true,
        startedAt: DateTime.now().subtract(Duration(seconds: duration)),
        endedAt: DateTime.now(),
      ),
    );
  }
  if (context.mounted) {
    services.notificationService.showSuccess(successMessage);
  }
}

TaskItem? _suggestBreakRelatedTask(PomodoroBreakUse use, List<TaskItem> tasks) {
  bool matches(TaskItem task, List<String> terms) {
    final value = '${task.title} ${task.category}'.toLowerCase();
    return terms.any(value.contains);
  }

  return switch (use) {
    PomodoroBreakUse.learning =>
      tasks
          .where(
            (task) =>
                task.taskType == TaskType.focus &&
                matches(task, const [
                  'learn',
                  'learning',
                  'study',
                  'practice',
                  'تعلم',
                  'lernen',
                  'üben',
                ]),
          )
          .firstOrNull,
    PomodoroBreakUse.reading =>
      tasks
          .where(
            (task) =>
                task.taskType == TaskType.reading ||
                matches(task, const ['reading', 'book', 'قراءة', 'lesen']),
          )
          .firstOrNull,
    PomodoroBreakUse.exercise =>
      tasks
          .where(
            (task) => matches(task, const [
              'exercise',
              'workout',
              'تمرين',
              'training',
            ]),
          )
          .firstOrNull,
    PomodoroBreakUse.housework =>
      tasks
          .where(
            (task) => matches(task, const [
              'house',
              'home',
              'clean',
              'laundry',
              'chores',
              'منزل',
              'تنظيف',
              'haushalt',
            ]),
          )
          .firstOrNull,
    PomodoroBreakUse.anotherTask =>
      tasks.where((task) => !task.isCompleted).firstOrNull,
    PomodoroBreakUse.rest ||
    PomodoroBreakUse.custom ||
    PomodoroBreakUse.undecided => null,
  };
}

BreakContributionType _breakContributionType(PomodoroBreakUse use) {
  return switch (use) {
    PomodoroBreakUse.learning => BreakContributionType.learning,
    PomodoroBreakUse.reading => BreakContributionType.reading,
    PomodoroBreakUse.exercise => BreakContributionType.exercise,
    PomodoroBreakUse.housework => BreakContributionType.housework,
    PomodoroBreakUse.anotherTask => BreakContributionType.anotherTask,
    PomodoroBreakUse.rest => BreakContributionType.rest,
    PomodoroBreakUse.custom ||
    PomodoroBreakUse.undecided => BreakContributionType.other,
  };
}

class _FirstSessionGuidance extends StatelessWidget {
  const _FirstSessionGuidance({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.text('noSessionsYet'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(context.text('firstSessionTrackingHelp')),
            const SizedBox(height: 12),
            AppButton.filled(
              onPressed: () => controller.startTask(task),
              icon: const Icon(Icons.play_arrow_outlined),
              label: Text(context.text('startFirstSession')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveExecutionSummary extends StatelessWidget {
  const _LiveExecutionSummary({
    required this.controller,
    required this.task,
    required this.data,
  });

  final TaskActionController controller;
  final TaskItem task;
  final _ExecutionData data;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: controller.activeSessionClock,
      builder: (context, _, child) {
        final active = controller.activeSession;
        final isActive = active?.task.id == task.id;
        final timing = isActive
            ? active!.timingAt(controller.activeSessionClock.value)
            : null;
        final historical = data.sessions.where(
          (session) => session.id != active?.session.id,
        );
        final historicalActive = historical.fold<int>(
          0,
          (sum, session) => sum + session.activeSeconds,
        );
        final historicalGross = historical.fold<int>(
          0,
          (sum, session) => sum + session.grossSeconds,
        );
        final historicalIdle = historical.fold<int>(
          0,
          (sum, session) => sum + session.idleSeconds,
        );
        final totalActive = historicalActive + (timing?.activeSeconds ?? 0);
        final totalGross = historicalGross + (timing?.grossSeconds ?? 0);
        final totalIdle = historicalIdle + (timing?.idleSeconds ?? 0);
        final taskMasterSeconds =
            (totalActive - data.browserSeconds - data.externalAppSeconds).clamp(
              0,
              totalActive,
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.text('taskPerformance'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryMetric(
                  label: context.text('totalTimeSpent'),
                  value: formatDurationCompact(totalGross),
                ),
                _SummaryMetric(
                  label: context.text('activeWork'),
                  value: formatDurationCompact(totalActive),
                ),
                _SummaryMetric(
                  label: context.text('idle'),
                  value: formatDurationCompact(totalIdle),
                ),
                _SummaryMetric(
                  label: context.text('completedSessions'),
                  value: '${data.sessions.length}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              context.text('whereActiveTimeOccurred'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryMetric(
                  label: context.text('taskMasterInterface'),
                  value: formatDurationCompact(taskMasterSeconds),
                ),
                _SummaryMetric(
                  label: context.text('webResearch'),
                  value: formatDurationCompact(data.browserSeconds),
                ),
                _SummaryMetric(
                  label: context.text('externalApplications'),
                  value: formatDurationCompact(data.externalAppSeconds),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _TaskAnalyticsPanel extends StatelessWidget {
  const _TaskAnalyticsPanel({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.text('insights')),
              Tab(text: context.text('progress')),
              Tab(text: context.text('sessions')),
              Tab(text: context.text('interruptions')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _InsightsTab(controller: controller, task: task),
                _ProgressTab(controller: controller, task: task),
                _SessionsTab(controller: controller, task: task),
                _InterruptionsTab(controller: controller, task: task),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskActivityPanel extends StatelessWidget {
  const _TaskActivityPanel({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskUsageActivity>>(
      future: controller.usageForTask(task.id),
      builder: (context, snapshot) {
        final usage = snapshot.data ?? const <TaskUsageActivity>[];
        if (usage.isEmpty) {
          return Center(child: Text(context.text('noActivityRecorded')));
        }
        final grouped = <String, int>{};
        for (final record in usage) {
          final label = record.type == TaskActivityType.website
              ? record.domain ?? context.text('website')
              : record.applicationName ?? context.text('application');
          grouped[label] = (grouped[label] ?? 0) + record.reportSeconds;
        }
        final entries = grouped.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(entries[index].key),
            trailing: Text(formatDurationCompact(entries[index].value)),
          ),
        );
      },
    );
  }
}

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    if (task.attachments.isEmpty) {
      return Center(child: Text(context.text('noAttachments')));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final attachment in task.attachments)
          ListTile(
            leading: const Icon(Icons.attach_file_outlined),
            title: Text(attachment),
          ),
      ],
    );
  }
}

class _TaskSettingsPanel extends StatelessWidget {
  const _TaskSettingsPanel({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _OverviewTab(task: task)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: AppButton.filled(
            onPressed: () => _editTaskDialog(context, controller, task),
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.text('editTask')),
          ),
        ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _MetricValue {
  const _MetricValue(this.label, this.value);
  final String label;
  final String value;
}

class _ExecutionData {
  const _ExecutionData({this.sessions = const [], this.usage = const []});

  final List<TrackedSession> sessions;
  final List<TaskUsageActivity> usage;

  int get totalSeconds =>
      sessions.fold(0, (sum, item) => sum + item.grossSeconds);
  int get activeSeconds =>
      sessions.fold(0, (sum, item) => sum + item.activeSeconds);
  int get idleSeconds =>
      sessions.fold(0, (sum, item) => sum + item.idleSeconds);
  int get browserSeconds => usage
      .where((item) => item.type == TaskActivityType.website)
      .fold(0, (sum, item) => sum + item.reportSeconds);
  int get externalAppSeconds => usage
      .where((item) => item.type == TaskActivityType.application)
      .fold(0, (sum, item) => sum + item.reportSeconds);
}

String _clock(int seconds) {
  final safe = seconds.clamp(0, 359999);
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final remainder = safe % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String _headerTimerLabel(
  BuildContext context,
  ActiveTaskSession active,
  ActiveSessionTiming timing,
) {
  if (active.isPaused) {
    return '${context.text('pausedAt')} ${formatDurationCompact(timing.activeSeconds)}';
  }
  if (timing.isFocusTask) {
    switch (timing.pomodoroStage) {
      case PomodoroStage.focusCompletedWaiting:
        return context.text('focusCompleted');
      case PomodoroStage.breakReady:
        return context.text('breakReady');
      case PomodoroStage.breakRunning:
        return '${formatDurationCompact(timing.breakRemainingSeconds)} ${context.text('breakRemaining').toLowerCase()}';
      case PomodoroStage.breakCompletedWaiting:
        return context.text('breakCompleted');
      case PomodoroStage.breakPaused:
        return '${context.text('pausedAt')} ${formatDurationCompact(timing.currentBreakElapsedSeconds)}';
      case PomodoroStage.focusReady:
        return context.text('focusReady');
      case PomodoroStage.idle:
      case PomodoroStage.focusRunning:
      case PomodoroStage.focusPaused:
      case PomodoroStage.taskCompleted:
      case PomodoroStage.cancelled:
        break;
    }
    return '${formatDurationCompact(timing.pomodoroRemainingSeconds)} ${context.text('remaining').toLowerCase()}';
  }
  if (timing.isOvertime) {
    return '${formatDurationCompact(timing.overtimeSeconds)} ${context.text('overtime').toLowerCase()}';
  }
  return '${formatDurationCompact(timing.remainingSeconds)} ${context.text('remaining').toLowerCase()}';
}

String _humanStatus(BuildContext context, TaskStatus status) {
  return switch (status) {
    TaskStatus.notStarted => context.text('notStarted'),
    TaskStatus.ready => context.text('ready'),
    TaskStatus.running => context.text('running'),
    TaskStatus.paused => context.text('paused'),
    TaskStatus.interrupted => context.text('interrupted'),
    TaskStatus.completed => context.text('completed'),
    TaskStatus.cancelled => context.text('cancelled'),
    TaskStatus.waiting => context.text('waiting'),
    TaskStatus.overdue => context.text('overdue'),
    TaskStatus.reviewRequired => context.text('reviewRequired'),
    TaskStatus.someday => context.text('someday'),
  };
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.task});

  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoTile(
          label: context.text('status'),
          value: context.text('taskStatus_${task.status.name}'),
        ),
        _InfoTile(
          label: context.text('taskType'),
          value: context.text('taskType_${task.taskType.name}'),
        ),
        _InfoTile(
          label: context.text('priority'),
          value: context.text('priority_${task.priority.name}'),
        ),
        _InfoTile(label: context.text('category'), value: task.category),
        _InfoTile(
          label: context.text('dueDate'),
          value: _formatTaskDateTime(context, task.effectiveDueUtc),
        ),
        _InfoTile(
          label: context.text('plannedTime'),
          value: _formatTaskRange(context, task.displayStart, task.displayEnd),
        ),
        _InfoTile(
          label: context.text('estimatedDuration'),
          value: formatDurationCompact(task.estimatedMinutes * 60),
        ),
        if (task.taskType == TaskType.focus)
          _InfoTile(
            label: context.text('estimatedPomodoros'),
            value: task.estimatedPomodoros.toString(),
          ),
        if (task.location?.isNotEmpty == true)
          _InfoTile(label: context.text('location'), value: task.location!),
        _InfoTile(
          label: context.text('progress'),
          value: '${task.progressPercentage}%',
        ),
        if (task.description.isNotEmpty)
          _InfoTile(
            label: context.text('description'),
            value: task.description,
          ),
        if (task.notes.isNotEmpty)
          _InfoTile(label: context.text('nextAction'), value: task.notes),
      ],
    );
  }
}

class _TimerTab extends StatelessWidget {
  const _TimerTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: controller.activeSessionClock,
      builder: (context, _, child) {
        final active = controller.activeSession;
        final isActive = active?.task.id == task.id;
        final timing = isActive
            ? active!.timingAt(controller.activeSessionClock.value)
            : null;
        final focus = task.taskType == TaskType.focus;
        final seconds = focus
            ? timing?.pomodoroRemainingSeconds ?? 25 * 60
            : timing?.activeSeconds ?? 0;
        final progress = focus
            ? timing?.pomodoroProgress ?? 0
            : timing?.plannedProgress ?? 0;
        final state = active?.isPaused == true
            ? _TimerVisualState.paused
            : timing?.isOvertime == true
            ? _TimerVisualState.overtime
            : isActive
            ? _TimerVisualState.running
            : _TimerVisualState.idle;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _LiveTimerRing(
                      seconds: seconds,
                      progress: progress,
                      visualState: state,
                      progressLabel: isActive
                          ? _headerTimerLabel(context, active!, timing!)
                          : context.text('notRunning'),
                    ),
                    const SizedBox(height: 18),
                    _ExecutionControls(controller: controller, task: task),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        AppButton.outlined(
                          onPressed: () =>
                              _addInterruption(context, controller, task),
                          icon: const Icon(Icons.report_problem_outlined),
                          label: Text(context.text('addInterruption')),
                        ),
                        AppButton.outlined(
                          onPressed: () => _addNote(context, controller, task),
                          icon: const Icon(Icons.note_add_outlined),
                          label: Text(context.text('addNote')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProgressTab extends StatelessWidget {
  const _ProgressTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    var progress = task.progressPercentage.toDouble();
    return StatefulBuilder(
      builder: (context, setState) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${progress.round()}%'),
            Slider(
              value: progress,
              max: 100,
              divisions: 20,
              label: '${progress.round()}%',
              onChanged: (value) => setState(() => progress = value),
            ),
            AppButton.filled(
              onPressed: () =>
                  controller.updateProgress(task, progress.round()),
              icon: const Icon(Icons.save_outlined),
              label: Text(context.text('save')),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<TaskProgressEntry>>(
              future: controller.progressEntriesForTask(task.id),
              builder: (context, snapshot) {
                final entries = snapshot.data ?? const <TaskProgressEntry>[];
                if (entries.isEmpty) {
                  return Text(context.text('noProgressEntries'));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.text('progressHistory'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _ProgressHistoryChart(entries: entries),
                    const SizedBox(height: 8),
                    for (final entry in entries.reversed.take(8))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          child: Text('${entry.progressPercentage}%'),
                        ),
                        title: Text(
                          entry.summary.isEmpty
                              ? context.text('progress')
                              : entry.summary,
                        ),
                        subtitle: Text(entry.recordedAt.toString()),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProgressHistoryChart extends StatelessWidget {
  const _ProgressHistoryChart({required this.entries});

  final List<TaskProgressEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: CustomPaint(
        painter: _ProgressHistoryPainter(
          entries: entries,
          color: Theme.of(context).colorScheme.primary,
          gridColor: Theme.of(context).dividerColor,
        ),
        child: Semantics(
          label:
              '${context.text('progressHistory')}: ${entries.length} ${context.text('entries')}',
        ),
      ),
    );
  }
}

class _ProgressHistoryPainter extends CustomPainter {
  const _ProgressHistoryPainter({
    required this.entries,
    required this.color,
    required this.gridColor,
  });

  final List<TaskProgressEntry> entries;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i += 1) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (entries.length < 2) {
      return;
    }
    final sorted = [...entries]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final path = Path();
    for (var i = 0; i < sorted.length; i += 1) {
      final x = size.width * i / (sorted.length - 1);
      final y =
          size.height - (size.height * sorted[i].progressPercentage / 100);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressHistoryPainter oldDelegate) {
    return entries != oldDelegate.entries ||
        color != oldDelegate.color ||
        gridColor != oldDelegate.gridColor;
  }
}

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskNote>>(
      future: controller.notesForTask(task.id),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const <TaskNote>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppButton.filled(
              onPressed: () => _addNote(context, controller, task),
              icon: const Icon(Icons.note_add_outlined),
              label: Text(context.text('addNote')),
            ),
            const SizedBox(height: 12),
            for (final note in notes)
              Card(
                child: ListTile(
                  leading: Icon(
                    note.isPinned
                        ? Icons.push_pin
                        : Icons.sticky_note_2_outlined,
                  ),
                  title: Text(note.title.isEmpty ? note.type.name : note.title),
                  subtitle: Text(note.body),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editNote(context, controller, note);
                      } else if (value == 'pin') {
                        controller.updateNote(
                          note.copyWith(isPinned: !note.isPinned),
                        );
                      } else if (value == 'delete') {
                        _deleteNote(context, controller, note);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.text('edit')),
                      ),
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(context.text('pin')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.text('delete')),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InterruptionsTab extends StatelessWidget {
  const _InterruptionsTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskInterruption>>(
      future: controller.interruptionsForTask(task.id),
      builder: (context, snapshot) {
        final interruptions = snapshot.data ?? const <TaskInterruption>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppButton.filled(
              onPressed: () => _addInterruption(context, controller, task),
              icon: const Icon(Icons.report_problem_outlined),
              label: Text(context.text('addInterruption')),
            ),
            const SizedBox(height: 12),
            for (final interruption in interruptions)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: Text(interruption.type.label),
                  subtitle: Text(
                    '${interruption.startedAt} • ${interruption.durationSeconds ~/ 60} ${context.text('minutes')}\n${interruption.description}',
                  ),
                  isThreeLine: interruption.description.isNotEmpty,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editInterruption(context, controller, interruption);
                      } else if (value == 'delete') {
                        _deleteInterruption(context, controller, interruption);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.text('edit')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(context.text('delete')),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SessionsTab extends StatelessWidget {
  const _SessionsTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TrackedSession>>(
      future: controller.sessionsForTask(task.id),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <TrackedSession>[];
        if (sessions.isEmpty) {
          return Center(child: Text(context.text('noRecordedSessions')));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final session = sessions[index];
            final end = session.endedAt;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.history_toggle_off_outlined),
                title: Text(_dateLabel(context, session.startedAt)),
                subtitle: Text(
                  '${_timeLabel(session.startedAt)}-${end == null ? context.text('running') : _timeLabel(end)}\n'
                  '${context.text('gross')}: ${formatDurationCompact(session.grossSeconds)}  '
                  '${context.text('active')}: ${formatDurationCompact(session.activeSeconds)}  '
                  '${context.text('idle')}: ${formatDurationCompact(session.idleSeconds)}\n'
                  '${context.text('paused')}: ${formatDurationCompact(session.pausedSeconds)}  '
                  '${context.text('interrupted')}: ${formatDurationCompact(session.interruptedSeconds)}  '
                  '${context.text('mode')}: ${session.trackingMode.name}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right_outlined),
                onTap: () => _showSessionTimeline(context, controller, session),
              ),
            );
          },
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoTile(
          label: context.text('created'),
          value: _formatTaskDateTime(context, task.createdAt),
        ),
        _InfoTile(
          label: context.text('updated'),
          value: _formatTaskDateTime(context, task.updatedAt),
        ),
        _InfoTile(
          label: context.text('status'),
          value: context.text('taskStatus_${task.status.name}'),
        ),
        _InfoTile(
          label: context.text('syncStatus'),
          value: controller.syncState.name,
        ),
      ],
    );
  }
}

class _InsightsTab extends StatelessWidget {
  const _InsightsTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TrackedSession>>(
      future: controller.sessionsForTask(task.id),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <TrackedSession>[];
        final analytics = const TimeAnalyticsService();
        final totals = analytics.fromSessions(sessions);
        final estimate = analytics.compareEstimate(
          estimatedMinutes: task.estimatedMinutes,
          actualActiveSeconds: totals.activeSeconds,
        );
        if (sessions.isEmpty) {
          return Center(child: Text(context.text('noTrackingDataHonest')));
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _InfoTile(
              label: context.text('estimatedTime'),
              value: formatDurationCompact(estimate.estimatedSeconds),
            ),
            _InfoTile(
              label: context.text('actualActiveTime'),
              value: formatDurationCompact(estimate.actualActiveSeconds),
            ),
            _InfoTile(
              label: context.text('estimateVariance'),
              value: formatDurationCompact(estimate.varianceSeconds.abs()),
            ),
            _InfoTile(
              label: context.text('estimateAccuracy'),
              value: '${(estimate.accuracy * 100).round()}%',
            ),
            const SizedBox(height: 12),
            Text(
              _insightText(context, estimate, totals),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        );
      },
    );
  }

  String _insightText(
    BuildContext context,
    EstimateComparison estimate,
    TimeBreakdown totals,
  ) {
    if (estimate.estimatedSeconds == 0) {
      return context.text('insightMissingEstimate');
    }
    if (estimate.varianceSeconds > 0) {
      return context.text('insightTookLonger');
    }
    if (totals.interruptedSeconds > 0) {
      return context.text('insightInterrupted');
    }
    return context.text('insightEstimateReasonable');
  }
}

class _ResourcesTab extends StatelessWidget {
  const _ResourcesTab({required this.controller, required this.task});

  final TaskActionController controller;
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskResource>>(
      future: controller.resourcesForTask(task),
      builder: (context, snapshot) {
        final resources = snapshot.data ?? const <TaskResource>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (resources.isEmpty)
              Text(context.text('noTaskResources'))
            else
              for (final resource in resources)
                ListTile(
                  leading: Icon(
                    resource.isDefault
                        ? Icons.home_outlined
                        : Icons.link_outlined,
                  ),
                  title: Text(resource.name),
                  subtitle: Text(resource.domain),
                  trailing: Text(
                    context.text('openMode_${resource.openMode.name}'),
                  ),
                ),
            const SizedBox(height: 12),
            AppButton.outlined(
              onPressed: () => _editTaskDialog(context, controller, task),
              icon: const Icon(Icons.add_link_outlined),
              label: Text(context.text('manageResources')),
            ),
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

Future<void> _editTaskDialog(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
) async {
  final resources = await controller.resourcesForTask(task);
  final reminders = await controller.remindersForTask(task.id);
  final editorLinks = await controller.taskEditorLinks();
  if (!context.mounted) return;
  final result = await showDialog<TaskEditorResult>(
    context: context,
    builder: (context) => TaskEditorDialog(
      task: task,
      categories: controller.categories,
      resources: resources,
      reminders: reminders,
      editorLinks: editorLinks,
    ),
  );
  if (result == null) return;
  await controller.editTaskBundle(
    task: result.task,
    resources: result.resources,
    reminders: result.reminders,
    scope: result.scope,
  );
  if (!context.mounted) return;
  final notifications = AppServices.of(context).notificationService;
  if (controller.syncState == TaskSyncState.failed) {
    notifications.showError(context.text('taskUpdateFailed'));
  } else {
    notifications.showSuccess(context.text('taskUpdated'));
  }
}

Future<void> _addCurrentPageToTask(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
  String url,
  String? title,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
  final resources = await controller.resourcesForTask(task);
  if (resources.any((resource) => resource.url == url)) {
    if (context.mounted) {
      AppServices.of(
        context,
      ).notificationService.showInfo(context.text('resourceAlreadySaved'));
    }
    return;
  }
  final reminders = await controller.remindersForTask(task.id);
  final added = TaskResource(
    taskId: task.id,
    name: title?.trim().isNotEmpty == true ? title!.trim() : uri.host,
    url: url,
    sortOrder: resources.length,
    isDefault: resources.isEmpty,
  );
  await controller.editTaskBundle(
    task: task,
    resources: [...resources, added],
    reminders: reminders,
  );
  if (context.mounted) {
    AppServices.of(
      context,
    ).notificationService.showSuccess(context.text('resourceSaved'));
  }
}

String _formatTaskDateTime(BuildContext context, DateTime? value) {
  if (value == null) return context.text('notSet');
  return AppServices.of(
    context,
  ).timeZoneService.formatTaskDateTime(context, value.toUtc());
}

String _formatTaskRange(BuildContext context, DateTime? start, DateTime? end) {
  if (start == null && end == null) return context.text('notSet');
  if (start == null) return _formatTaskDateTime(context, end);
  return AppServices.of(context).timeZoneService.formatTaskTimeRange(
    context,
    startUtc: start.toUtc(),
    endUtc: end?.toUtc(),
  );
}

class _TaskWorkspaceLayoutData {
  const _TaskWorkspaceLayoutData({
    required this.browserMode,
    required this.browserWidth,
    required this.selectedPanel,
  });

  final TaskBrowserLayoutMode browserMode;
  final double browserWidth;
  final int selectedPanel;
}

class _TaskWorkspaceLayoutStore {
  static Future<_TaskWorkspaceLayoutData?> load(String taskId) async {
    try {
      final file = _file(taskId);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return _TaskWorkspaceLayoutData(
        browserMode: TaskBrowserLayoutModeX.fromStorage(
          decoded['browserMode']?.toString() ??
              (decoded['browserExpanded'] == true ? 'split' : 'collapsed'),
        ),
        browserWidth: (decoded['browserWidth'] as num?)?.toDouble() ?? 480,
        selectedPanel: (decoded['selectedPanel'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      return null;
    }
  }

  static Future<void> save(
    String taskId, {
    required TaskBrowserLayoutMode browserMode,
    required double browserWidth,
    required int selectedPanel,
  }) async {
    try {
      final file = _file(taskId);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'browserMode': browserMode.storageValue,
          'browserExpanded': browserMode.isVisible,
          'browserWidth': browserWidth,
          'selectedPanel': selectedPanel,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    } on Object {
      return;
    }
  }

  static File _file(String taskId) {
    final base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    final safeId = taskId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(
      '$base${Platform.pathSeparator}TaskMaster Pro'
      '${Platform.pathSeparator}TaskWorkspaces'
      '${Platform.pathSeparator}$safeId.json',
    );
  }
}

Future<void> _showSessionTimeline(
  BuildContext context,
  TaskActionController controller,
  TrackedSession session,
) async {
  final segments = await controller.segmentsForSession(session.id);
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(context.text('sessionTimeline')),
        content: SizedBox(
          width: 520,
          child: segments.isEmpty
              ? Text(context.text('noSessionSegments'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: segments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final segment = segments[index];
                    final end = segment.endedAt;
                    return ListTile(
                      leading: Icon(_segmentIcon(segment.type)),
                      title: Text(segment.type.storageValue),
                      subtitle: Text(
                        '${_timeLabel(segment.startedAt)}-${end == null ? context.text('running') : _timeLabel(end)}',
                      ),
                      trailing: Text(
                        formatDurationCompact(segment.durationSeconds),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          AppButton.filled(
            onPressed: () => Navigator.of(context).pop(),
            label: Text(context.text('close')),
          ),
        ],
      );
    },
  );
}

IconData _segmentIcon(SessionSegmentType type) {
  return switch (type) {
    SessionSegmentType.active => Icons.play_circle_outline,
    SessionSegmentType.video => Icons.ondemand_video_outlined,
    SessionSegmentType.reading => Icons.menu_book_outlined,
    SessionSegmentType.manual => Icons.edit_calendar_outlined,
    SessionSegmentType.idle => Icons.hourglass_empty_outlined,
    SessionSegmentType.paused => Icons.pause_circle_outline,
    SessionSegmentType.interruption => Icons.report_problem_outlined,
    SessionSegmentType.breakTime => Icons.free_breakfast_outlined,
    SessionSegmentType.externalResource => Icons.open_in_browser_outlined,
  };
}

String _dateLabel(BuildContext context, DateTime date) {
  return MaterialLocalizations.of(context).formatFullDate(date);
}

String _timeLabel(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Future<void> _addNote(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
) async {
  final note = await _showNoteDialog(context, taskId: task.id);
  if (note != null) {
    await controller.addNote(note);
  }
}

Future<void> _editNote(
  BuildContext context,
  TaskActionController controller,
  TaskNote note,
) async {
  final updated = await _showNoteDialog(context, existing: note);
  if (updated != null) {
    await controller.updateNote(updated);
  }
}

Future<TaskNote?> _showNoteDialog(
  BuildContext context, {
  String? taskId,
  TaskNote? existing,
}) async {
  final titleController = TextEditingController(text: existing?.title ?? '');
  final bodyController = TextEditingController(text: existing?.body ?? '');
  var type = existing?.type ?? TaskNoteType.general;
  var pinned = existing?.isPinned ?? false;
  final result = await showDialog<TaskNote>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.text(existing == null ? 'addNote' : 'editNote')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: context.text('title'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TaskNoteType>(
                    initialValue: type,
                    items: [
                      for (final item in TaskNoteType.values)
                        DropdownMenuItem(value: item, child: Text(item.name)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => type = value);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: context.text('noteType'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: context.text('notes'),
                    ),
                  ),
                  CheckboxListTile(
                    value: pinned,
                    onChanged: (value) =>
                        setState(() => pinned = value ?? false),
                    title: Text(context.text('pin')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AppButton.text(
              onPressed: () => Navigator.of(context).pop(),
              label: Text(context.text('cancel')),
            ),
            AppButton.filled(
              onPressed: () {
                final body = bodyController.text.trim();
                if (body.isEmpty) {
                  return;
                }
                Navigator.of(context).pop(
                  (existing ?? TaskNote(taskId: taskId!, body: body)).copyWith(
                    title: titleController.text.trim(),
                    body: body,
                    type: type,
                    isPinned: pinned,
                  ),
                );
              },
              label: Text(context.text('save')),
            ),
          ],
        ),
      );
    },
  );
  titleController.dispose();
  bodyController.dispose();
  return result;
}

Future<void> _deleteNote(
  BuildContext context,
  TaskActionController controller,
  TaskNote note,
) async {
  final confirmed = await _confirmDelete(context);
  if (confirmed) {
    await controller.deleteNote(note);
  }
}

Future<void> _addInterruption(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
) async {
  final interruption = await _showInterruptionDialog(context, taskId: task.id);
  if (interruption != null) {
    await controller.addInterruption(interruption);
  }
}

Future<void> _editInterruption(
  BuildContext context,
  TaskActionController controller,
  TaskInterruption interruption,
) async {
  final updated = await _showInterruptionDialog(
    context,
    existing: interruption,
  );
  if (updated != null) {
    await controller.updateInterruption(updated);
  }
}

Future<TaskInterruption?> _showInterruptionDialog(
  BuildContext context, {
  String? taskId,
  TaskInterruption? existing,
}) async {
  final descriptionController = TextEditingController(
    text: existing?.description ?? '',
  );
  var type = existing?.type ?? TaskInterruptionType.phoneCall;
  var duration = (existing?.durationSeconds ?? 0) ~/ 60;
  var pausedTask = existing?.pausedTask ?? true;
  var workRelated = existing?.isWorkRelated ?? false;
  final result = await showDialog<TaskInterruption>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.text('addInterruption')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<TaskInterruptionType>(
                    initialValue: type,
                    items: [
                      for (final item in TaskInterruptionType.values)
                        DropdownMenuItem(value: item, child: Text(item.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => type = value);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: context.text('type'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: duration.toString(),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.text('durationMinutes'),
                    ),
                    onChanged: (value) {
                      duration = int.tryParse(value) ?? duration;
                    },
                  ),
                  CheckboxListTile(
                    value: pausedTask,
                    onChanged: (value) =>
                        setState(() => pausedTask = value ?? true),
                    title: Text(context.text('pauseTaskTiming')),
                  ),
                  CheckboxListTile(
                    value: workRelated,
                    onChanged: (value) =>
                        setState(() => workRelated = value ?? false),
                    title: Text(context.text('workRelated')),
                  ),
                  TextField(
                    controller: descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: context.text('description'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AppButton.text(
              onPressed: () => Navigator.of(context).pop(),
              label: Text(context.text('cancel')),
            ),
            AppButton.filled(
              onPressed: () {
                Navigator.of(context).pop(
                  (existing ??
                          TaskInterruption(
                            taskId: taskId!,
                            type: type,
                            durationSeconds: duration * 60,
                          ))
                      .copyWith(
                        type: type,
                        durationSeconds: duration * 60,
                        pausedTask: pausedTask,
                        isWorkRelated: workRelated,
                        description: descriptionController.text.trim(),
                      ),
                );
              },
              label: Text(context.text('save')),
            ),
          ],
        ),
      );
    },
  );
  descriptionController.dispose();
  return result;
}

Future<void> _deleteInterruption(
  BuildContext context,
  TaskActionController controller,
  TaskInterruption interruption,
) async {
  final confirmed = await _confirmDelete(context);
  if (confirmed) {
    await controller.deleteInterruption(interruption);
  }
}

Future<bool> _confirmDelete(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.text('delete')),
          content: Text(context.text('deleteConfirmation')),
          actions: [
            AppButton.text(
              onPressed: () => Navigator.of(context).pop(false),
              label: Text(context.text('cancel')),
            ),
            AppButton.filled(
              onPressed: () => Navigator.of(context).pop(true),
              label: Text(context.text('delete')),
            ),
          ],
        ),
      ) ??
      false;
}
