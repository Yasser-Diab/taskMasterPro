import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/config/supabase_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/platform/app_lifecycle_service.dart';
import '../../../core/platform/task_browser_surface_controller.dart';
import '../../../core/theme/app_brand.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/time_zone_service.dart';
import '../../history/presentation/history_screen.dart';
import '../../pomodoro/domain/pomodoro_controller.dart';
import '../../pomodoro/domain/pomodoro_models.dart';
import '../../pomodoro/presentation/pomodoro_screen.dart';
import '../../roadmap/domain/roadmap_overview_screen.dart';
import '../../settings/presentation/account_profile_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../tasks/application/task_action_controller.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_item.dart';
import '../../tasks/presentation/task_editor_dialog.dart';
import '../../tasks/presentation/task_list_screen.dart';
import '../../tasks/presentation/task_workspace_screen.dart';
import 'today_dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({required this.supabaseService, super.key});

  final SupabaseService supabaseService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final TaskActionController _taskController;
  late final PomodoroController _pomodoroController;
  late Future<void> _taskFuture;
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  AppLifecycleService? _lifecycleService;
  bool _listeningToTimeZone = false;
  TimeZoneService? _timeZoneService;
  StreamSubscription<AppLifecycleCommand>? _lifecycleCommandSubscription;
  StreamSubscription<void>? _exitRequestSubscription;
  Timer? _activeNotificationTimer;
  PomodoroPhase _lastPomodoroPhase = PomodoroPhase.focus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _taskController = TaskActionController(
      TaskRepository(widget.supabaseService),
    );
    _taskController.addListener(_syncTaskActiveSession);
    widget.supabaseService.addListener(_handleProfileUpdate);
    _pomodoroController = PomodoroController();
    _pomodoroController.addListener(_syncActiveSession);
    _taskFuture = _taskController.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lifecycleService = AppServices.of(context).lifecycleService;
    if (!_listeningToTimeZone) {
      _timeZoneService = AppServices.of(context).timeZoneService;
      _timeZoneService!.addListener(_handleTimeZoneChange);
      _listeningToTimeZone = true;
    }
    if (_lifecycleService == lifecycleService) {
      return;
    }

    _lifecycleCommandSubscription?.cancel();
    _exitRequestSubscription?.cancel();
    _lifecycleService = lifecycleService;
    _lifecycleCommandSubscription = lifecycleService.commands.listen(
      _handleLifecycleCommand,
    );
    _exitRequestSubscription = lifecycleService.exitRequests.listen(
      (_) => _handleExitRequest(),
    );
    _syncActiveSession();
    _syncTaskActiveSession();
    unawaited(_drainPendingWidgetCommand());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_hideTaskBrowserSurface());
    _lifecycleCommandSubscription?.cancel();
    _exitRequestSubscription?.cancel();
    widget.supabaseService.removeListener(_handleProfileUpdate);
    _taskController.removeListener(_syncTaskActiveSession);
    _pomodoroController.removeListener(_syncActiveSession);
    _activeNotificationTimer?.cancel();
    if (_listeningToTimeZone) {
      _timeZoneService?.removeListener(_handleTimeZoneChange);
    }
    _taskController.dispose();
    final lifecycleService = _lifecycleService;
    if (lifecycleService != null) {
      unawaited(
        lifecycleService.updateActiveSession(
          const ActiveSessionStatus.inactive(),
        ),
      );
    }
    _pomodoroController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_drainPendingWidgetCommand());
    }
  }

  void _handleTimeZoneChange() {
    unawaited(_taskController.rescheduleRemindersForTimeZoneChange());
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.text('dashboard'),
      context.text('tasks'),
      context.text('pomodoro'),
      context.text('history'),
      context.text('roadmap'),
      context.text('settings'),
    ];

    final icons = [
      Icons.today_outlined,
      Icons.checklist_rtl_outlined,
      Icons.timer_outlined,
      Icons.calendar_month_outlined,
      Icons.route_outlined,
      Icons.settings_outlined,
    ];

    return FutureBuilder<void>(
      future: _taskFuture,
      builder: (context, snapshot) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final page = PageStorage(
              bucket: _pageStorageBucket,
              child: _HomePageSlot(
                selectedIndex: _selectedIndex,
                taskController: _taskController,
                pomodoroController: _pomodoroController,
                supabaseService: widget.supabaseService,
                onQuickAdd: _openQuickAdd,
                onStartPomodoro: () => _selectNavigationIndex(2),
              ),
            );
            if (wide) {
              return Scaffold(
                body: Row(
                  children: [
                    _DesktopRail(
                      selectedIndex: _selectedIndex,
                      labels: labels,
                      icons: icons,
                      profile: widget.supabaseService.profile,
                      controller: _taskController,
                      onOpenProfile: _openProfileSettings,
                      onOpenRunningTask: _openRunningTask,
                      onSelected: _selectNavigationIndex,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _SessionControlConflictBanner(
                            controller: _taskController,
                            onView: _openRunningTask,
                          ),
                          Expanded(
                            child: ColoredBox(
                              color: Theme.of(
                                context,
                              ).scaffoldBackgroundColor,
                              child: page,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              body: Column(
                children: [
                  _SessionControlConflictBanner(
                    controller: _taskController,
                    onView: _openRunningTask,
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: page,
                    ),
                  ),
                  _MobileRunningTaskBar(
                    controller: _taskController,
                    onOpen: _openRunningTask,
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectNavigationIndex,
                destinations: [
                  for (var i = 0; i < labels.length; i += 1)
                    NavigationDestination(
                      icon: Icon(icons[i]),
                      label: labels[i],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _selectNavigationIndex(int index) {
    if (index == _selectedIndex) return;
    unawaited(_hideTaskBrowserSurface());
    setState(() => _selectedIndex = index);
  }

  Future<void> _openQuickAdd() async {
    final editorLinks = await _taskController.taskEditorLinks();
    if (!mounted) return;
    final result = await showDialog<TaskEditorResult>(
      context: context,
      builder: (context) => TaskEditorDialog(
        categories: _taskController.categories,
        editorLinks: editorLinks,
      ),
    );
    if (result == null) {
      return;
    }
    await _taskController.addTaskBundle(
      task: result.task,
      resources: result.resources,
      reminders: result.reminders,
    );
    if (mounted) {
      setState(() {
        _taskFuture = Future.value();
      });
    }
  }

  void _handleProfileUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openProfileSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountProfileScreen(
          taskController: _taskController,
          pomodoroController: _pomodoroController,
        ),
      ),
    );
  }

  void _openRunningTask(TaskItem task) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TaskWorkspaceScreen(controller: _taskController, task: task),
      ),
    );
  }

  void _handleLifecycleCommand(AppLifecycleCommand command) {
    if (!mounted) {
      return;
    }

    final nextIndex = switch (command) {
      AppLifecycleCommand.restore => _selectedIndex,
      AppLifecycleCommand.tasks => 1,
      AppLifecycleCommand.pomodoro => 2,
      AppLifecycleCommand.workSession => 0,
      AppLifecycleCommand.learningSession => 4,
      AppLifecycleCommand.notifications => 5,
      AppLifecycleCommand.synchronization => 5,
      AppLifecycleCommand.settings => 5,
    };

    if (nextIndex != _selectedIndex) {
      unawaited(_hideTaskBrowserSurface());
      setState(() => _selectedIndex = nextIndex);
    }
  }

  Future<void> _drainPendingWidgetCommand() async {
    final lifecycleService = _lifecycleService;
    if (lifecycleService == null) {
      return;
    }
    final command = await lifecycleService.takePendingWidgetCommand();
    if (!mounted || command == null) {
      return;
    }
    final active = _taskController.activeSession;
    var status = 'ignored';
    String? errorMessage;
    try {
      switch (command.command) {
        case 'pause':
          if (active != null && !active.isPaused) {
            await _taskController.pauseTask(active.task);
            status = 'applied';
          }
          break;
        case 'resume':
        case 'start':
        case 'return_to_focus':
          if (active != null && active.isPaused) {
            await _taskController.resumeTask(active.task);
            status = 'applied';
          } else if (active != null &&
              active.pomodoroStage == PomodoroStage.focusReady) {
            await _taskController.startPomodoroFocus(reason: 'widget_command');
            status = 'applied';
          }
          break;
        case 'finish_focus':
          if (active?.pomodoroStage == PomodoroStage.focusRunning ||
              active?.pomodoroStage == PomodoroStage.focusPaused) {
            await _taskController.finishPomodoroFocus(reason: 'widget_command');
            status = 'applied';
          }
          break;
        case 'finish_break':
          if (active?.pomodoroStage == PomodoroStage.breakRunning ||
              active?.pomodoroStage == PomodoroStage.breakPaused) {
            await _taskController.finishPomodoroBreak(reason: 'widget_command');
            status = 'applied';
          }
          break;
        case 'open':
        case 'refresh':
          _syncTaskActiveSession();
          status = 'applied';
          break;
        default:
          break;
      }
    } on Object catch (error) {
      status = 'failed';
      errorMessage = error.toString();
    }
    final current = _taskController.activeSession ?? active;
    await _taskController.recordWidgetAction(
      commandType: command.command,
      localOccurredAt: command.occurredAt,
      sessionId: current?.session.id,
      taskId: current?.task.id,
      status: status,
      errorMessage: errorMessage,
      payload: {
        'source': 'android_home_widget',
        'handled_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _hideTaskBrowserSurface() async {
    await TaskBrowserSurfaceController.hideAll();
  }

  Future<void> _handleExitRequest() async {
    final lifecycleService = _lifecycleService;
    if (lifecycleService == null || !mounted) {
      return;
    }

    final canExit = await _confirmExitIfNeeded();
    if (canExit) {
      await _taskController.flushForShutdown();
      await lifecycleService.exitApplication();
    }
  }

  Future<bool> _confirmExitIfNeeded() async {
    if (_pomodoroController.state.isInactive &&
        _taskController.activeSession == null) {
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.text('exitActiveSessionTitle')),
          content: Text(context.text('exitActiveSessionMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.text('exitTaskMasterPro')),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  void _syncActiveSession() {
    final lifecycleService = _lifecycleService;
    if (lifecycleService == null || !mounted) {
      return;
    }

    final phase = _pomodoroController.phase;
    if (phase != _lastPomodoroPhase) {
      final wasFocus = _lastPomodoroPhase == PomodoroPhase.focus;
      final isFocus = phase == PomodoroPhase.focus;
      if (!_pomodoroController.state.isInactive) {
        if (wasFocus && !isFocus) {
          unawaited(_taskController.beginPomodoroBreak());
        } else if (!wasFocus && isFocus) {
          unawaited(_taskController.endPomodoroBreak());
        }
      }
      _lastPomodoroPhase = phase;
    }

    if (_pomodoroController.state.isInactive) {
      unawaited(
        lifecycleService.updateActiveSession(
          const ActiveSessionStatus.inactive(),
        ),
      );
      return;
    }

    final phaseLabel = switch (_pomodoroController.phase) {
      PomodoroPhase.focus => context.text('focus'),
      PomodoroPhase.shortBreak => context.text('shortBreak'),
      PomodoroPhase.longBreak => context.text('longBreak'),
    };
    final minutesRemaining = (_pomodoroController.remainingSeconds + 59) ~/ 60;
    final stateLabel = _pomodoroController.state.isPaused
        ? context.text('pausedSession')
        : _pomodoroController.state.isWaitingForUser
        ? context.text('waitingForYou')
        : phaseLabel;

    unawaited(
      lifecycleService.updateActiveSession(
        ActiveSessionStatus(
          active: true,
          title: context.text('activePomodoroTitle'),
          summary:
              '$stateLabel - $minutesRemaining ${context.text('minutesRemaining')}',
        ),
      ),
    );
  }

  void _syncTaskActiveSession() {
    if (!_pomodoroController.state.isInactive) {
      return;
    }
    _activeNotificationTimer?.cancel();
    _activeNotificationTimer = null;
    final lifecycleService = _lifecycleService;
    if (lifecycleService == null || !mounted) {
      return;
    }
    final active = _taskController.activeSession;
    if (active == null) {
      unawaited(
        lifecycleService.updateActiveSession(
          const ActiveSessionStatus.inactive(),
        ),
      );
      return;
    }

    void pushStatus() {
      if (!mounted || !_pomodoroController.state.isInactive) {
        return;
      }
      final current = _taskController.activeSession;
      if (current == null) {
        unawaited(
          lifecycleService.updateActiveSession(
            const ActiveSessionStatus.inactive(),
          ),
        );
        return;
      }
      final timing = current.timingAt(DateTime.now());
      final summary = current.isPaused
          ? '${context.text('paused')} - ${_compactDuration(timing.activeSeconds)}'
          : timing.isFocusTask
          ? '${_compactDuration(timing.pomodoroRemainingSeconds)} ${context.text('remaining')}'
          : timing.isOvertime
          ? '${_compactDuration(timing.overtimeSeconds)} ${context.text('overtime')}'
          : '${_compactDuration(timing.activeSeconds)} ${context.text('elapsedTime')}';
      unawaited(
        lifecycleService.updateActiveSession(
          ActiveSessionStatus(
            active: true,
            title: current.task.title,
            summary: summary,
          ),
        ),
      );
    }

    pushStatus();
    _activeNotificationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => pushStatus(),
    );
  }
}

class _HomePageSlot extends StatelessWidget {
  const _HomePageSlot({
    required this.selectedIndex,
    required this.taskController,
    required this.pomodoroController,
    required this.supabaseService,
    required this.onQuickAdd,
    required this.onStartPomodoro,
  });

  final int selectedIndex;
  final TaskActionController taskController;
  final PomodoroController pomodoroController;
  final SupabaseService supabaseService;
  final VoidCallback onQuickAdd;
  final VoidCallback onStartPomodoro;

  @override
  Widget build(BuildContext context) {
    if (selectedIndex == 5) {
      return SettingsScreen(
        key: const PageStorageKey('settings-page'),
        taskController: taskController,
        pomodoroController: pomodoroController,
      );
    }

    return AnimatedBuilder(
      animation: taskController,
      builder: (context, _) {
        final tasks = taskController.tasks;
        return KeyedSubtree(
          key: PageStorageKey('home-page-$selectedIndex'),
          child: switch (selectedIndex) {
            0 => TodayDashboardScreen(
              tasks: tasks,
              profile: supabaseService.profile,
              taskController: taskController,
              onQuickAdd: onQuickAdd,
              onStartPomodoro: onStartPomodoro,
            ),
            1 => TaskListScreen(
              tasks: tasks,
              controller: taskController,
              onAddTask: onQuickAdd,
            ),
            2 => PomodoroScreen(
              tasks: tasks,
              controller: pomodoroController,
              taskController: taskController,
            ),
            3 => HistoryScreen(controller: taskController, tasks: tasks),
            4 => RoadmapOverviewScreen(
              phases: const [],
              tasks: tasks,
              sessions: taskController.sessions,
              taskController: taskController,
            ),
            _ => TodayDashboardScreen(
              tasks: tasks,
              profile: supabaseService.profile,
              taskController: taskController,
              onQuickAdd: onQuickAdd,
              onStartPomodoro: onStartPomodoro,
            ),
          },
        );
      },
    );
  }
}

class _SessionControlConflictBanner extends StatelessWidget {
  const _SessionControlConflictBanner({
    required this.controller,
    required this.onView,
  });

  final TaskActionController controller;
  final ValueChanged<TaskItem> onView;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final task = controller.blockedSessionTask;
        if (task == null || controller.blockedSessionClaim == null) {
          return const SizedBox.shrink();
        }
        return Material(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.devices_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.text('taskRunningOnAnotherDevice')),
                  ),
                  TextButton(
                    onPressed: () => onView(task),
                    child: Text(context.text('view')),
                  ),
                  IconButton(
                    tooltip: context.text('close'),
                    onPressed: controller.dismissSessionControlConflict,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.profile,
    required this.controller,
    required this.onOpenProfile,
    required this.onOpenRunningTask,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final AppUserProfile? profile;
  final TaskActionController controller;
  final VoidCallback onOpenProfile;
  final ValueChanged<TaskItem> onOpenRunningTask;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: BorderDirectional(
          end: BorderSide(color: context.appColors.border),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          width: services.config.compactDesktop ? 88 : 236,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Image.asset(
                  AppBrand.logoAssetForTheme(services.config.themeChoice),
                  height: services.config.compactDesktop ? 42 : 64,
                  fit: BoxFit.contain,
                ),
              ),
              _SidebarProfileCard(
                profile: profile,
                collapsed: services.config.compactDesktop,
                onTap: onOpenProfile,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: NavigationRail(
                  extended: !services.config.compactDesktop,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  destinations: [
                    for (var i = 0; i < labels.length; i += 1)
                      NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(labels[i]),
                      ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final active = controller.activeSession;
                  if (active == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                    child: _PersistentRunningTaskCard(
                      controller: controller,
                      active: active,
                      sidebarCollapsed: services.config.compactDesktop,
                      onOpen: () => onOpenRunningTask(active.task),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersistentRunningTaskCard extends StatefulWidget {
  const _PersistentRunningTaskCard({
    required this.controller,
    required this.active,
    required this.sidebarCollapsed,
    required this.onOpen,
  });

  final TaskActionController controller;
  final ActiveTaskSession active;
  final bool sidebarCollapsed;
  final VoidCallback onOpen;

  @override
  State<_PersistentRunningTaskCard> createState() =>
      _PersistentRunningTaskCardState();
}

class _PersistentRunningTaskCardState
    extends State<_PersistentRunningTaskCard> {
  bool _manuallyCollapsed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final mini = widget.sidebarCollapsed || _manuallyCollapsed;
    return ValueListenableBuilder<DateTime>(
      valueListenable: widget.controller.activeSessionClock,
      builder: (context, _, child) {
        final active = widget.controller.activeSession ?? widget.active;
        final timing = active.timingAt(
          widget.controller.activeSessionClock.value,
        );
        final timerText = _runningTimerText(context, active, timing);
        final semanticLabel =
            '${context.text('runningNow')}, ${active.task.title}, $timerText';
        return Semantics(
          button: true,
          label: semanticLabel,
          child: Focus(
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _focused
                        ? Theme.of(context).colorScheme.primary
                        : context.appColors.border,
                    width: _focused ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onOpen,
                  canRequestFocus: true,
                  child: mini
                      ? _MiniRunningTaskCard(
                          active: active,
                          timing: timing,
                          onTogglePause: () => _togglePause(active),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const _RunningIndicator(),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      context.text('runningNow'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelMedium,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: context.text('collapse'),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(
                                      () => _manuallyCollapsed = true,
                                    ),
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                              Tooltip(
                                message: active.task.title,
                                child: Text(
                                  active.task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                timerText,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                              Text(
                                _runningTaskDetail(context, active, timing),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.appColors.mutedText,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _togglePause(active),
                                      icon: Icon(
                                        active.isPaused
                                            ? Icons.play_arrow_outlined
                                            : Icons.pause_outlined,
                                        size: 17,
                                      ),
                                      label: Text(
                                        active.isPaused
                                            ? context.text('resume')
                                            : context.text('pause'),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton.filledTonal(
                                    tooltip: context.text('openTask'),
                                    onPressed: widget.onOpen,
                                    icon: const Icon(
                                      Icons.open_in_new_outlined,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _togglePause(ActiveTaskSession active) {
    unawaited(
      active.isPaused
          ? widget.controller.resumeTask(active.task)
          : widget.controller.pauseTask(active.task),
    );
  }
}

class _MiniRunningTaskCard extends StatelessWidget {
  const _MiniRunningTaskCard({
    required this.active,
    required this.timing,
    required this.onTogglePause,
  });

  final ActiveTaskSession active;
  final ActiveSessionTiming timing;
  final VoidCallback onTogglePause;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _RunningIndicator(),
              if (active.task.title.isNotEmpty) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _shortClock(timing.activeSeconds),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
          IconButton(
            tooltip: active.isPaused
                ? context.text('resume')
                : context.text('pause'),
            visualDensity: VisualDensity.compact,
            onPressed: onTogglePause,
            icon: Icon(
              active.isPaused
                  ? Icons.play_arrow_outlined
                  : Icons.pause_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileRunningTaskBar extends StatelessWidget {
  const _MobileRunningTaskBar({required this.controller, required this.onOpen});

  final TaskActionController controller;
  final ValueChanged<TaskItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.activeSession;
        if (active == null) return const SizedBox.shrink();
        return ValueListenableBuilder<DateTime>(
          valueListenable: controller.activeSessionClock,
          builder: (context, _, child) {
            final current = controller.activeSession ?? active;
            final timing = current.timingAt(
              controller.activeSessionClock.value,
            );
            return SafeArea(
              top: false,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: InkWell(
                  onTap: () => onOpen(current.task),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
                    child: Row(
                      children: [
                        const _RunningIndicator(),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current.task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _runningTimerText(context, current, timing),
                                style: const TextStyle(
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: current.isPaused
                              ? context.text('resume')
                              : context.text('pause'),
                          onPressed: () => unawaited(
                            current.isPaused
                                ? controller.resumeTask(current.task)
                                : controller.pauseTask(current.task),
                          ),
                          icon: Icon(
                            current.isPaused
                                ? Icons.play_arrow_outlined
                                : Icons.pause_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: context.text('openTask'),
                          onPressed: () => onOpen(current.task),
                          icon: const Icon(Icons.open_in_new_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RunningIndicator extends StatefulWidget {
  const _RunningIndicator();

  @override
  State<_RunningIndicator> createState() => _RunningIndicatorState();
}

class _RunningIndicatorState extends State<_RunningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.65,
      upperBound: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations ||
        AppServices.of(context).config.reducedMotion) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

String _runningTimerText(
  BuildContext context,
  ActiveTaskSession active,
  ActiveSessionTiming timing,
) {
  if (active.isPaused) {
    return '${context.text('pausedAt')} ${_compactDuration(timing.activeSeconds)}';
  }
  if (timing.isFocusTask) {
    return '${_shortClock(timing.pomodoroRemainingSeconds)} ${context.text('remaining').toLowerCase()}';
  }
  if (timing.isOvertime) {
    return '${_compactDuration(timing.overtimeSeconds)} ${context.text('overtime').toLowerCase()}';
  }
  return _shortClock(timing.activeSeconds);
}

String _runningTaskDetail(
  BuildContext context,
  ActiveTaskSession active,
  ActiveSessionTiming timing,
) {
  if (timing.isFocusTask) {
    final planned = active.task.estimatedPomodoros.clamp(1, 999);
    final current = (timing.completedPomodoros + 1).clamp(1, planned);
    return '${context.text('focusSession')} $current ${context.text('of')} $planned';
  }
  return '${context.text('continuousTimer')} • ${_compactDuration(timing.plannedSeconds)} ${context.text('planned').toLowerCase()}';
}

String _shortClock(int seconds) {
  final safe = seconds.clamp(0, 359999);
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final remainder = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String _compactDuration(int seconds) {
  final safe = seconds.clamp(0, 1 << 31);
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h';
  return '${minutes}m';
}

class _SidebarProfileCard extends StatelessWidget {
  const _SidebarProfileCard({
    required this.profile,
    required this.collapsed,
    required this.onTap,
  });

  final AppUserProfile? profile;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = profile?.preferredName ?? context.text('profile');
    final avatar = _SidebarAvatar(
      profile: profile,
      radius: collapsed ? 22 : 24,
    );
    if (collapsed) {
      return Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Center(child: avatar),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              avatar,
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (profile?.username?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(
                  '@${profile!.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.mutedText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarAvatar extends StatelessWidget {
  const _SidebarAvatar({required this.profile, required this.radius});

  final AppUserProfile? profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = profile?.avatarSignedUrl;
    final initials = profile?.initials ?? 'TP';
    return CircleAvatar(
      key: ValueKey(profile?.avatarPath ?? profile?.id ?? 'signed-out'),
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: url == null || url.isEmpty
          ? Text(
              initials,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
