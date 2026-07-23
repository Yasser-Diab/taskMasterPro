import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_services.dart';
import '../../../core/config/supabase_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_controls.dart';
import '../../../core/widgets/section_card.dart';
import '../../tasks/application/task_action_controller.dart';
import '../../tasks/domain/task_activity.dart';
import '../../tasks/domain/task_item.dart';
import '../../tasks/domain/task_support_models.dart';
import '../../tasks/presentation/task_editor_dialog.dart';
import '../../tasks/presentation/task_workspace_screen.dart';

class TodayDashboardScreen extends StatelessWidget {
  const TodayDashboardScreen({
    required this.tasks,
    required this.profile,
    required this.taskController,
    required this.onQuickAdd,
    required this.onStartPomodoro,
    super.key,
  });

  final List<TaskItem> tasks;
  final AppUserProfile? profile;
  final TaskActionController taskController;
  final VoidCallback onQuickAdd;
  final VoidCallback onStartPomodoro;

  @override
  Widget build(BuildContext context) {
    return _DashboardRefresh(builder: _buildDashboard);
  }

  Widget _buildDashboard(BuildContext context) {
    final currentTasks = taskController.tasks.isEmpty
        ? tasks
        : taskController.tasks;
    final todayTasks =
        currentTasks
            .where((task) => task.isDueToday && !task.isCompleted)
            .toList()
          ..sort((a, b) => a.priority.rank.compareTo(b.priority.rank));
    final overdueTasks = currentTasks.where((task) => task.isOverdue).toList();
    final reviewTasks = currentTasks
        .where((task) => task.status == TaskStatus.reviewRequired)
        .toList();
    final focusTask = todayTasks.isNotEmpty
        ? todayTasks.first
        : currentTasks.where((task) => !task.isCompleted).firstOrNull;
    final activeTask = taskController.activeSession?.task;
    final todayRecords = tasks.where((task) => task.isDueToday).toList();
    final plannedMinutes = todayRecords.fold<int>(
      0,
      (total, task) => total + task.estimatedMinutes,
    );
    final recordedMinutes = todayRecords.fold<int>(
      0,
      (total, task) => total + task.actualFocusedMinutes,
    );
    final completedToday = todayRecords
        .where((task) => task.isCompleted)
        .length;
    final inProgressToday = todayRecords
        .where(
          (task) =>
              task.status == TaskStatus.running ||
              task.status == TaskStatus.paused ||
              task.status == TaskStatus.interrupted,
        )
        .length;
    final categoryMinutes = <String, int>{};
    for (final task in todayRecords) {
      categoryMinutes.update(
        task.category,
        (value) => value + task.estimatedMinutes,
        ifAbsent: () => task.estimatedMinutes,
      );
    }
    final categoryEntries = categoryMinutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final interruptions = taskController.interruptionsForDay(DateTime.now());
    final interruptionSeconds = interruptions.fold<int>(
      0,
      (total, interruption) =>
          total + _interruptionDuration(interruption, DateTime.now()),
    );
    final availableMinutes = _configuredAvailableMinutes(context);
    final overCapacityMinutes = (plannedMinutes - availableMinutes).clamp(
      0,
      24 * 60,
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): () =>
            unawaited(_openQuickNote(context, taskController)),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              MaterialLocalizations.of(context).formatFullDate(DateTime.now()),
            ),
            actions: [
              _QuickNoteActionButton(
                onPressed: () =>
                    unawaited(_openQuickNote(context, taskController)),
              ),
              IconButton(
                tooltip: context.text('quickAdd'),
                onPressed: onQuickAdd,
                icon: const Icon(Icons.add_task_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _HeroFocus(
                  focusTask: activeTask ?? focusTask,
                  activeTask: activeTask,
                  profile: profile,
                  onStartPomodoro: onStartPomodoro,
                ),
                const SizedBox(height: 16),
                _ActiveCoachStrip(
                  tasks: currentTasks,
                  controller: taskController,
                  plannedMinutes: plannedMinutes,
                  recordedMinutes: recordedMinutes,
                  completedToday: completedToday,
                  overdueCount: overdueTasks.length,
                  interruptionSeconds: interruptionSeconds,
                  overCapacityMinutes: overCapacityMinutes,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 920;
                    final cards = [
                      SectionCard(
                        title: context.text('focusedTime'),
                        icon: Icons.center_focus_strong_outlined,
                        child: _MetricText(
                          primary: _formatMinutes(recordedMinutes),
                          secondary: context.text('verifiedActive'),
                        ),
                      ),
                      SectionCard(
                        title: context.text('plannedActual'),
                        icon: Icons.compare_arrows_outlined,
                        child: _ProgressLine(
                          label:
                              '${context.text('planned')}: ${_formatMinutes(plannedMinutes)}  •  ${context.text('recorded')}: ${_formatMinutes(recordedMinutes)}',
                          value: plannedMinutes == 0
                              ? 0
                              : (recordedMinutes / plannedMinutes).clamp(0, 1),
                        ),
                      ),
                      SectionCard(
                        title: context.text('taskOutput'),
                        icon: Icons.fact_check_outlined,
                        child: _MetricText(
                          primary:
                              '$completedToday ${context.text('completed').toLowerCase()}',
                          secondary:
                              '$inProgressToday ${context.text('inProgress').toLowerCase()}',
                        ),
                      ),
                      SectionCard(
                        title: context.text('categoryDistribution'),
                        icon: Icons.pie_chart_outline,
                        child: _CategoryBreakdown(entries: categoryEntries),
                      ),
                    ];

                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final card in cards) ...[
                            card,
                            if (!identical(card, cards.last))
                              const SizedBox(height: 12),
                          ],
                        ],
                      );
                    }

                    final cardWidth = (constraints.maxWidth - 36) / 4;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final card in cards)
                          SizedBox(
                            width: cardWidth.clamp(220, 420),
                            child: card,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SmallStatus(
                      title: context.text('overdue'),
                      text:
                          '${overdueTasks.length} ${context.text('tasks').toLowerCase()}',
                      icon: Icons.warning_amber_outlined,
                      important: overdueTasks.isNotEmpty,
                      onTap: () => _showOverduePanel(context),
                    ),
                    _SmallStatus(
                      title: context.text('waitingReview'),
                      text: reviewTasks.isEmpty
                          ? context.text('allReviewsCompleted')
                          : '${reviewTasks.length} ${context.text('items')}',
                      icon: Icons.rate_review_outlined,
                      onTap: () => _showReviewPanel(context),
                    ),
                    _SmallStatus(
                      title: context.text('interruptedTime'),
                      text: interruptionSeconds == 0
                          ? context.text('noInterruptionsToday')
                          : '${_formatSecondsCompact(interruptionSeconds)} ${context.text('today').toLowerCase()}',
                      icon: Icons.search_outlined,
                      onTap: () => _showInterruptionPanel(context),
                    ),
                    _SmallStatus(
                      title: context.text('dailyWorkload'),
                      text: overCapacityMinutes > 0
                          ? '${_formatMinutes(overCapacityMinutes)} ${context.text('overCapacity').toLowerCase()}'
                          : context.text('withinCapacity'),
                      icon: Icons.balance_outlined,
                      important: overCapacityMinutes > 0,
                      onTap: () => _showWorkloadPanel(
                        context,
                        availableMinutes: availableMinutes,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: context.text('today'),
                  icon: Icons.today_outlined,
                  action: TextButton.icon(
                    onPressed: onQuickAdd,
                    icon: const Icon(Icons.add_outlined),
                    label: Text(context.text('quickAdd')),
                  ),
                  child: Column(
                    children: [
                      if (todayTasks.isEmpty)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(context.text('nextAction')),
                        )
                      else
                        for (final task in todayTasks.take(5))
                          _TaskLine(task: task, controller: taskController),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: context.text('roadmapPhase'),
                  icon: Icons.route_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.text('nextRoadmapTarget'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(context.text('roadmapPlaceholder')),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton.filled(
                        onPressed: onStartPomodoro,
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: Text(context.text('startPomodoro')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppButton.outlined(
                      onPressed: onQuickAdd,
                      icon: const Icon(Icons.add_outlined),
                      label: Text(context.text('quickAdd')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showOverduePanel(BuildContext context) {
    return _showResponsiveDashboardPanel(
      context,
      title: context.text('overdueTasks'),
      controller: taskController,
      builder: (panelContext) => _OverdueTasksPanel(
        controller: taskController,
        onOpenTask: (task) => _openTaskFromPanel(panelContext, task),
      ),
    );
  }

  Future<void> _showReviewPanel(BuildContext context) {
    return _showResponsiveDashboardPanel(
      context,
      title: context.text('waitingReview'),
      controller: taskController,
      builder: (panelContext) => _ReviewTasksPanel(
        controller: taskController,
        onOpenTask: (task) => _openTaskFromPanel(panelContext, task),
      ),
    );
  }

  Future<void> _showInterruptionPanel(BuildContext context) {
    return _showResponsiveDashboardPanel(
      context,
      title: context.text('interruptionsToday'),
      controller: taskController,
      builder: (panelContext) => _InterruptionReportPanel(
        controller: taskController,
        onOpenTask: (task) => _openTaskFromPanel(panelContext, task),
      ),
    );
  }

  Future<void> _showWorkloadPanel(
    BuildContext context, {
    required int availableMinutes,
  }) {
    return _showResponsiveDashboardPanel(
      context,
      title: context.text('dailyWorkload'),
      controller: taskController,
      builder: (panelContext) => _WorkloadAdjustmentPanel(
        controller: taskController,
        availableMinutes: availableMinutes,
        onOpenTask: (task) => _openTaskFromPanel(panelContext, task),
      ),
    );
  }

  void _openTaskFromPanel(BuildContext panelContext, TaskItem task) {
    final navigator = Navigator.of(panelContext);
    navigator.pop();
    Future<void>.delayed(Duration.zero, () {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TaskWorkspaceScreen(controller: taskController, task: task),
        ),
      );
    });
  }
}

class _ActiveCoachStrip extends StatelessWidget {
  const _ActiveCoachStrip({
    required this.tasks,
    required this.controller,
    required this.plannedMinutes,
    required this.recordedMinutes,
    required this.completedToday,
    required this.overdueCount,
    required this.interruptionSeconds,
    required this.overCapacityMinutes,
  });

  final List<TaskItem> tasks;
  final TaskActionController controller;
  final int plannedMinutes;
  final int recordedMinutes;
  final int completedToday;
  final int overdueCount;
  final int interruptionSeconds;
  final int overCapacityMinutes;

  @override
  Widget build(BuildContext context) {
    final usage = _todayUsage(controller.cachedUsageRecords);
    final webSeconds = usage
        .where((record) => record.type == TaskActivityType.website)
        .fold<int>(0, (total, record) => total + record.reportSeconds);
    final topDomain = _topDomain(usage);
    final active = controller.activeSession;
    final activeTitle = active?.task.title;
    final activePaused = active?.isPaused == true;
    final messages = <String>[
      if (activeTitle != null)
        context.textWith(
          activePaused ? 'coachPausedTask' : 'coachRunningTask',
          {'task': activeTitle},
        ),
      if (completedToday > 0)
        context.textWith('coachCompletedToday', {'count': '$completedToday'}),
      if (overdueCount > 0)
        context.textWith('coachOverdueTasks', {'count': '$overdueCount'}),
      if (overCapacityMinutes > 0)
        context.textWith('coachOverCapacity', {
          'duration': _formatMinutes(overCapacityMinutes),
        }),
      if (webSeconds >= 60 && topDomain != null)
        context.textWith('coachResearchDomain', {
          'duration': _formatSecondsCompact(webSeconds),
          'domain': topDomain,
        }),
      if (interruptionSeconds > 0)
        context.textWith('coachInterrupted', {
          'duration': _formatSecondsCompact(interruptionSeconds),
        }),
    ];

    if (messages.isEmpty) {
      messages.add(
        plannedMinutes == 0
            ? context.text('coachClearDay')
            : context.text('coachStartNext'),
      );
    }

    final progress = plannedMinutes == 0
        ? 0.0
        : (recordedMinutes / plannedMinutes).clamp(0.0, 1.0);
    return SectionCard(
      title: context.text('activeCoach'),
      icon: Icons.psychology_alt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(messages.first, style: Theme.of(context).textTheme.titleSmall),
          if (messages.length > 1) ...[
            const SizedBox(height: 8),
            for (final message in messages.skip(1).take(3))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(message),
              ),
          ],
          const SizedBox(height: 12),
          _ProgressLine(
            label:
                '${context.text('recorded')}: ${_formatMinutes(recordedMinutes)}  •  ${context.text('planned')}: ${_formatMinutes(plannedMinutes)}',
            value: progress,
          ),
        ],
      ),
    );
  }

  List<TaskUsageActivity> _todayUsage(List<TaskUsageActivity> records) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return [
      for (final record in records)
        if (!record.startedAt.isBefore(start) && record.startedAt.isBefore(end))
          record,
    ];
  }

  String? _topDomain(List<TaskUsageActivity> records) {
    final totals = <String, int>{};
    for (final record in records) {
      if (record.type != TaskActivityType.website) continue;
      final domain =
          (record.registrableDomain ??
                  record.normalizedDomain ??
                  record.domain ??
                  '')
              .toLowerCase()
              .replaceFirst(RegExp(r'^www\.'), '');
      if (domain.isEmpty) continue;
      totals.update(
        domain,
        (value) => value + record.reportSeconds,
        ifAbsent: () => record.reportSeconds,
      );
    }
    if (totals.isEmpty) return null;
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }
}

class _DashboardRefresh extends StatefulWidget {
  const _DashboardRefresh({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_DashboardRefresh> createState() => _DashboardRefreshState();
}

class _DashboardRefreshState extends State<_DashboardRefresh> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class _HeroFocus extends StatelessWidget {
  const _HeroFocus({
    required this.focusTask,
    required this.activeTask,
    required this.profile,
    required this.onStartPomodoro,
  });

  final TaskItem? focusTask;
  final TaskItem? activeTask;
  final AppUserProfile? profile;
  final VoidCallback onStartPomodoro;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(context, profile),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              activeTask == null
                  ? context.text('currentFocus')
                  : context.text('currentActiveTask'),
              style: TextStyle(color: colors.mutedText),
            ),
            const SizedBox(height: 8),
            Text(
              focusTask?.title ?? context.text('nextAction'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (focusTask?.notes.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(focusTask!.notes),
            ],
          ],
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      textBlock,
                      const SizedBox(height: 16),
                      AppButton.filled(
                        onPressed: onStartPomodoro,
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: Text(context.text('startPomodoro')),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: textBlock),
                      const SizedBox(width: 16),
                      AppButton.filled(
                        onPressed: onStartPomodoro,
                        icon: const Icon(Icons.play_arrow_outlined),
                        label: Text(context.text('startPomodoro')),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  String _greeting(BuildContext context, AppUserProfile? profile) {
    final name = profile?.preferredName;
    if (name == null || name.trim().isEmpty) {
      return context.text('greeting');
    }
    final hour = DateTime.now().hour;
    final language = Localizations.localeOf(context).languageCode;
    final greeting = switch (language) {
      'ar' => hour < 12 ? 'صباح الخير' : 'مساء الخير',
      'de' =>
        hour < 12
            ? 'Guten Morgen'
            : hour < 18
            ? 'Guten Tag'
            : 'Guten Abend',
      _ =>
        hour < 12
            ? 'Good morning'
            : hour < 18
            ? 'Good afternoon'
            : 'Good evening',
    };
    return '$greeting, $name';
  }
}

class _MetricText extends StatelessWidget {
  const _MetricText({required this.primary, required this.secondary});

  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(primary, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(secondary, style: TextStyle(color: context.appColors.mutedText)),
      ],
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.entries});

  final List<MapEntry<String, int>> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text(context.text('noCategoryTime'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries.take(5))
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatMinutes(entry.value),
                    textAlign: TextAlign.end,
                    softWrap: false,
                  ),
                ],
              ),
            ),
          ),
        if (entries.length > 5)
          TextButton(
            onPressed: () => _showAllCategories(context, entries),
            child: Text(context.text('viewAllCategories')),
          ),
      ],
    );
  }

  void _showAllCategories(
    BuildContext context,
    List<MapEntry<String, int>> entries,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.key),
              trailing: Text(_formatMinutes(entry.value)),
            );
          },
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: value),
      ],
    );
  }
}

class _SmallStatus extends StatelessWidget {
  const _SmallStatus({
    required this.title,
    required this.text,
    required this.icon,
    required this.onTap,
    this.important = false,
  });

  final String title;
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final bool important;

  @override
  Widget build(BuildContext context) {
    final color = important
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 260,
      child: Semantics(
        button: true,
        label: '$title, $text',
        child: Tooltip(
          message: context.text('openDetails'),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                canRequestFocus: true,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(icon, color: color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            Text(text, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_outlined, size: 19),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showResponsiveDashboardPanel(
  BuildContext context, {
  required String title,
  required TaskActionController controller,
  required Widget Function(BuildContext panelContext) builder,
}) {
  final desktop = MediaQuery.sizeOf(context).width >= 700;
  if (desktop) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (panelContext) => Dialog(
        alignment: AlignmentDirectional.centerEnd,
        insetPadding: const EdgeInsets.all(18),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(panelContext).height - 36,
          child: _DashboardPanelFrame(
            title: title,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => builder(panelContext),
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (panelContext) => SizedBox(
      height: MediaQuery.sizeOf(panelContext).height * 0.88,
      child: _DashboardPanelFrame(
        title: title,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => builder(panelContext),
        ),
      ),
    ),
  );
}

class _DashboardPanelFrame extends StatelessWidget {
  const _DashboardPanelFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: context.text('close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_outlined),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: child),
      ],
    );
  }
}

class _OverdueTasksPanel extends StatefulWidget {
  const _OverdueTasksPanel({
    required this.controller,
    required this.onOpenTask,
  });

  final TaskActionController controller;
  final ValueChanged<TaskItem> onOpenTask;

  @override
  State<_OverdueTasksPanel> createState() => _OverdueTasksPanelState();
}

class _OverdueTasksPanelState extends State<_OverdueTasksPanel> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final zoneService = AppServices.of(context).timeZoneService;
    final now = DateTime.now().toUtc();
    final localNow = zoneService.convertInstantToAppZone(now);
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final all = widget.controller.tasks.where((task) => task.isOverdue).toList()
      ..sort((a, b) {
        final priority = a.priority.rank.compareTo(b.priority.rank);
        if (priority != 0) return priority;
        return (a.effectiveDueUtc ?? now).compareTo(b.effectiveDueUtc ?? now);
      });
    final tasks = all.where((task) {
      final due = task.effectiveDueUtc == null
          ? null
          : zoneService.convertInstantToAppZone(task.effectiveDueUtc!);
      return switch (_filter) {
        'today' =>
          due?.year == today.year &&
              due?.month == today.month &&
              due?.day == today.day,
        'previous' => due?.isBefore(today) ?? false,
        'critical' => task.priority == TaskPriority.critical,
        'recurring' => task.recurrenceId != null || task.seriesTaskId != null,
        'roadmap' => task.roadmapId != null,
        _ => true,
      };
    }).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              for (final filter in const [
                'all',
                'today',
                'previous',
                'critical',
                'recurring',
                'roadmap',
              ]) ...[
                ChoiceChip(
                  label: Text(context.text('filter_$filter')),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? _PanelEmptyState(
                  icon: Icons.task_alt_outlined,
                  title: context.text('noOverdueTasks'),
                  message: context.text('noOverdueTasksHelp'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                  itemCount: tasks.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _DashboardTaskCard(
                      task: task,
                      subtitle: _overdueDescription(context, task, now),
                      onOpen: () => widget.onOpenTask(task),
                      actions: [
                        _PanelAction(
                          context.text('openTask'),
                          Icons.open_in_new_outlined,
                          () => widget.onOpenTask(task),
                        ),
                        _PanelAction(
                          context.text('start'),
                          Icons.play_arrow_outlined,
                          widget.controller.activeSession == null
                              ? () => widget.controller.startTask(task)
                              : null,
                        ),
                        _PanelAction(
                          context.text('reschedule'),
                          Icons.event_repeat_outlined,
                          () => _editTaskFromDashboard(
                            context,
                            widget.controller,
                            task,
                          ),
                        ),
                        _PanelAction(
                          context.text('completeTask'),
                          Icons.done_all_outlined,
                          () => widget.controller.completeTask(task),
                        ),
                        if (task.recurrenceId != null ||
                            task.seriesTaskId != null)
                          _PanelAction(
                            context.text('skipToday'),
                            Icons.skip_next_outlined,
                            () => widget.controller.skipToday(task),
                          ),
                        _PanelAction(
                          context.text('edit'),
                          Icons.edit_outlined,
                          () => _editTaskFromDashboard(
                            context,
                            widget.controller,
                            task,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ReviewTasksPanel extends StatelessWidget {
  const _ReviewTasksPanel({required this.controller, required this.onOpenTask});

  final TaskActionController controller;
  final ValueChanged<TaskItem> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final tasks = controller.tasks
        .where((task) => task.status == TaskStatus.reviewRequired)
        .toList();
    if (tasks.isEmpty) {
      return _PanelEmptyState(
        icon: Icons.verified_outlined,
        title: context.text('nothingWaitingReview'),
        message: context.text('nothingWaitingReviewHelp'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: tasks.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _DashboardTaskCard(
          task: task,
          subtitle: context.text('completionReviewRequired'),
          onOpen: () => onOpenTask(task),
          actions: [
            _PanelAction(
              context.text('review'),
              Icons.rate_review_outlined,
              () => onOpenTask(task),
            ),
            _PanelAction(
              context.text('approve'),
              Icons.done_all_outlined,
              () => controller.completeTask(task),
            ),
            _PanelAction(
              context.text('reopen'),
              Icons.restart_alt_outlined,
              () => controller.editTask(
                task.copyWith(status: TaskStatus.notStarted),
              ),
            ),
            _PanelAction(
              context.text('addNote'),
              Icons.note_add_outlined,
              () => _addDashboardNote(context, controller, task),
            ),
          ],
        );
      },
    );
  }
}

class _InterruptionReportPanel extends StatelessWidget {
  const _InterruptionReportPanel({
    required this.controller,
    required this.onOpenTask,
  });

  final TaskActionController controller;
  final ValueChanged<TaskItem> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final interruptions = controller.interruptionsForDay(now);
    final total = interruptions.fold<int>(
      0,
      (sum, item) => sum + _interruptionDuration(item, now),
    );
    if (interruptions.isEmpty) {
      return _PanelEmptyState(
        icon: Icons.do_not_disturb_on_outlined,
        title: context.text('noInterruptionsToday'),
        message: context.text('noInterruptionsTodayHelp'),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '${context.text('totalInterruptionTime')}: ${_formatSecondsCompact(total)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
            itemCount: interruptions.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final interruption = interruptions[index];
              final task = controller.tasks
                  .where((item) => item.id == interruption.taskId)
                  .firstOrNull;
              final duration = _interruptionDuration(interruption, now);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task?.title ?? context.text('deletedTask'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(interruption.startedAt))} • ${_formatSecondsCompact(duration)}',
                      ),
                      Text(
                        interruption.description.trim().isNotEmpty
                            ? interruption.description
                            : interruption.type.label,
                      ),
                      Text(
                        interruption.isResolved
                            ? context.text('taskResumed')
                            : context.text('notResolved'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (task != null)
                            TextButton.icon(
                              onPressed: () => onOpenTask(task),
                              icon: const Icon(Icons.open_in_new_outlined),
                              label: Text(context.text('openTask')),
                            ),
                          TextButton.icon(
                            onPressed: () => _editInterruptionReason(
                              context,
                              controller,
                              interruption,
                            ),
                            icon: const Icon(Icons.edit_note_outlined),
                            label: Text(context.text('editReason')),
                          ),
                          TextButton.icon(
                            onPressed: () => _reclassifyInterruption(
                              context,
                              controller,
                              interruption,
                            ),
                            icon: const Icon(Icons.category_outlined),
                            label: Text(context.text('reclassify')),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                controller.deleteInterruption(interruption),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(context.text('delete')),
                          ),
                          if (task != null &&
                              controller.activeSession?.task.id == task.id &&
                              controller.activeSession?.isPaused == true)
                            TextButton.icon(
                              onPressed: () => controller.resumeTask(task),
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: Text(context.text('resumeTask')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WorkloadAdjustmentPanel extends StatelessWidget {
  const _WorkloadAdjustmentPanel({
    required this.controller,
    required this.availableMinutes,
    required this.onOpenTask,
  });

  final TaskActionController controller;
  final int availableMinutes;
  final ValueChanged<TaskItem> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final tasks =
        controller.tasks
            .where((task) => task.isDueToday && !task.isCompleted)
            .toList()
          ..sort((a, b) => a.priority.rank.compareTo(b.priority.rank));
    final planned = tasks.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes,
    );
    final over = (planned - availableMinutes).clamp(0, 24 * 60);
    final suggestion = tasks
        .where((task) => task.priority != TaskPriority.critical)
        .lastOrNull;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          over > 0
              ? context.text('todayOverloaded')
              : context.text('todayWithinCapacity'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _WorkloadMetric(
          label: context.text('plannedWork'),
          value: _formatMinutes(planned),
        ),
        _WorkloadMetric(
          label: context.text('availableTime'),
          value: _formatMinutes(availableMinutes),
        ),
        _WorkloadMetric(
          label: context.text('overCapacity'),
          value: _formatMinutes(over),
          important: over > 0,
        ),
        const SizedBox(height: 16),
        for (final task in tasks)
          _DashboardTaskCard(
            task: task,
            subtitle:
                '${context.text('planned')}: ${_formatMinutes(task.estimatedMinutes)}',
            onOpen: () => onOpenTask(task),
            actions: [
              _PanelAction(
                context.text('moveTomorrow'),
                Icons.redo_outlined,
                () => _moveTaskToTomorrow(controller, task),
              ),
              _PanelAction(
                context.text('shortenDuration'),
                Icons.compress_outlined,
                task.estimatedMinutes > 5
                    ? () => _shortenTaskDuration(context, controller, task)
                    : null,
              ),
              if (task.recurrenceId != null || task.seriesTaskId != null)
                _PanelAction(
                  context.text('skipToday'),
                  Icons.skip_next_outlined,
                  () => controller.skipToday(task),
                ),
              _PanelAction(
                context.text('lowerPriority'),
                Icons.low_priority_outlined,
                task.priority == TaskPriority.low
                    ? null
                    : () => _saveOccurrenceEdit(
                        controller,
                        task.copyWith(
                          priority: _lowerPriority(task.priority),
                          isRecurrenceException:
                              task.recurrenceId != null ||
                              task.isRecurrenceException,
                        ),
                      ),
              ),
            ],
          ),
        if (suggestion != null && over > 0) ...[
          const SizedBox(height: 16),
          Text(
            context.text('suggestedAdjustment'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text('${context.text('moveTomorrow')}: ${suggestion.title}'),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () =>
                _confirmWorkloadSuggestion(context, controller, suggestion),
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: Text(context.text('reviewAndApply')),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.text('keepSchedule')),
        ),
      ],
    );
  }
}

class _WorkloadMetric extends StatelessWidget {
  const _WorkloadMetric({
    required this.label,
    required this.value,
    this.important = false,
  });

  final String label;
  final String value;
  final bool important;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: important ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTaskCard extends StatelessWidget {
  const _DashboardTaskCard({
    required this.task,
    required this.subtitle,
    required this.onOpen,
    required this.actions,
  });

  final TaskItem task;
  final String subtitle;
  final VoidCallback onOpen;
  final List<_PanelAction> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(context.text('priority_${task.priority.name}')),
                ],
              ),
              const SizedBox(height: 4),
              Text(subtitle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final action in actions)
                    TextButton.icon(
                      onPressed: action.onPressed,
                      icon: Icon(action.icon, size: 17),
                      label: Text(action.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelAction {
  const _PanelAction(this.label, this.icon, this.onPressed);

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class _PanelEmptyState extends StatelessWidget {
  const _PanelEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.task, required this.controller});

  final TaskItem task;
  final TaskActionController controller;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        task.priority == TaskPriority.critical
            ? Icons.priority_high_outlined
            : Icons.radio_button_unchecked,
      ),
      title: Text(task.title),
      subtitle: Text(task.category),
      trailing: Text(task.priority.name),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TaskWorkspaceScreen(
            controller: controller,
            task: task,
            initialTab: task.isCompleted ? 5 : 0,
          ),
        ),
      ),
    );
  }
}

class _QuickNoteActionButton extends StatelessWidget {
  const _QuickNoteActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (wide) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: TextButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.note_add_outlined),
          label: Text(context.text('quickNote')),
        ),
      );
    }
    return Semantics(
      button: true,
      label: context.text('quickNote'),
      child: IconButton(
        tooltip: context.text('quickNote'),
        onPressed: onPressed,
        icon: const Icon(Icons.note_add_outlined),
      ),
    );
  }
}

class _QuickNoteResult {
  const _QuickNoteResult({required this.note, required this.convertToTask});

  final QuickNote note;
  final bool convertToTask;
}

class _QuickNoteComposer extends StatefulWidget {
  const _QuickNoteComposer({
    required this.categories,
    required this.roadmaps,
    required this.sheet,
  });

  final List<String> categories;
  final Map<String, String> roadmaps;
  final bool sheet;

  @override
  State<_QuickNoteComposer> createState() => _QuickNoteComposerState();
}

class _QuickNoteComposerState extends State<_QuickNoteComposer> {
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  String? _category;
  String? _roadmapId;
  bool _submitted = false;

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _submit({required bool convertToTask}) {
    if (_submitted) return;
    final title = _titleController.text.trim();
    final details = _detailsController.text.trim();
    if (title.isEmpty && details.isEmpty) {
      return;
    }
    _submitted = true;
    Navigator.of(context).pop(
      _QuickNoteResult(
        note: QuickNote(
          title: title,
          body: title.isEmpty ? details : title,
          details: details,
          category: _category,
          roadmapId: _roadmapId,
        ),
        convertToTask: convertToTask,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleController,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: context.text('quickNoteTitle'),
          ),
          onSubmitted: (_) => _submit(convertToTask: false),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _detailsController,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: context.text('quickNoteDetails'),
          ),
        ),
        if (widget.categories.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: InputDecoration(labelText: context.text('category')),
            items: [
              for (final category in widget.categories)
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
        ],
        if (widget.roadmaps.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _roadmapId,
            decoration: InputDecoration(labelText: context.text('roadmap')),
            items: [
              for (final entry in widget.roadmaps.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _roadmapId = value),
          ),
        ],
      ],
    );

    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.text('cancel')),
      ),
      AppButton.outlined(
        onPressed: () => _submit(convertToTask: true),
        icon: const Icon(Icons.add_task_outlined),
        label: Text(context.text('saveAndConvertToTask')),
      ),
      AppButton.filled(
        onPressed: () => _submit(convertToTask: false),
        icon: const Icon(Icons.save_outlined),
        label: Text(context.text('saveNote')),
      ),
    ];

    if (widget.sheet) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.text('quickNote'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                content,
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(context.text('quickNote')),
      content: SizedBox(width: 460, child: content),
      actions: actions,
    );
  }
}

Future<void> _openQuickNote(
  BuildContext context,
  TaskActionController controller,
) async {
  final categories = controller.categories.map((item) => item.name).toList()
    ..sort();
  const roadmaps = <String, String>{};
  final sheet =
      Theme.of(context).platform == TargetPlatform.android ||
      MediaQuery.sizeOf(context).width < 760;
  final result = sheet
      ? await showModalBottomSheet<_QuickNoteResult>(
          context: context,
          isScrollControlled: true,
          showDragHandle: false,
          builder: (context) => _QuickNoteComposer(
            categories: categories,
            roadmaps: roadmaps,
            sheet: true,
          ),
        )
      : await showDialog<_QuickNoteResult>(
          context: context,
          builder: (context) => _QuickNoteComposer(
            categories: categories,
            roadmaps: roadmaps,
            sheet: false,
          ),
        );
  if (!context.mounted || result == null) return;

  final pendingTask = result.convertToTask
      ? TaskItem(
          title: result.note.title.isEmpty
              ? result.note.body
              : result.note.title,
          description: result.note.details,
          taskType: TaskType.manual,
          executionMode: TaskExecutionMode.manualCompletion,
          category: result.note.category ?? 'Personal',
          roadmapId: result.note.roadmapId,
          notes: result.note.details,
          estimatedMinutes: 5,
          timerEnabled: false,
        )
      : null;
  final noteToSave = pendingTask == null
      ? result.note
      : result.note.copyWith(convertedTaskId: pendingTask.id);
  final saved = await controller.addQuickNote(noteToSave);
  if (!context.mounted) return;
  if (saved == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.text('quickNoteSaveFailed'))),
    );
    return;
  }

  if (pendingTask != null) {
    await controller.addTask(pendingTask);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.text('quickNoteConverted'))));
    return;
  }

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.text('quickNoteSaved'))));
}

Future<void> _editTaskFromDashboard(
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
}

Future<void> _addDashboardNote(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
) async {
  final textController = TextEditingController();
  final note = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.text('addNote')),
      content: TextField(
        controller: textController,
        minLines: 3,
        maxLines: 5,
        decoration: InputDecoration(labelText: context.text('notes')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(textController.text),
          child: Text(context.text('save')),
        ),
      ],
    ),
  );
  textController.dispose();
  if (note == null || note.trim().isEmpty) return;
  await controller.addNote(TaskNote(taskId: task.id, body: note.trim()));
}

Future<void> _editInterruptionReason(
  BuildContext context,
  TaskActionController controller,
  TaskInterruption interruption,
) async {
  final textController = TextEditingController(text: interruption.description);
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.text('editReason')),
      content: TextField(
        controller: textController,
        autofocus: true,
        decoration: InputDecoration(labelText: context.text('reason')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(textController.text),
          child: Text(context.text('save')),
        ),
      ],
    ),
  );
  textController.dispose();
  if (reason == null) return;
  await controller.updateInterruption(
    interruption.copyWith(description: reason.trim()),
  );
}

Future<void> _reclassifyInterruption(
  BuildContext context,
  TaskActionController controller,
  TaskInterruption interruption,
) async {
  final type = await showDialog<TaskInterruptionType>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.text('reclassify')),
      children: [
        for (final value in TaskInterruptionType.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(value),
            child: Text(value.label),
          ),
      ],
    ),
  );
  if (type == null) return;
  await controller.updateInterruption(interruption.copyWith(type: type));
}

Future<void> _saveOccurrenceEdit(
  TaskActionController controller,
  TaskItem task,
) async {
  final resources = await controller.resourcesForTask(task);
  final reminders = await controller.remindersForTask(task.id);
  await controller.editTaskBundle(
    task: task,
    resources: resources,
    reminders: reminders,
    scope: RecurrenceEditScope.occurrence,
  );
}

Future<void> _moveTaskToTomorrow(
  TaskActionController controller,
  TaskItem task,
) {
  DateTime? shift(DateTime? value) => value?.add(const Duration(days: 1));
  return _saveOccurrenceEdit(
    controller,
    task.copyWith(
      startDate: shift(task.startDate),
      dueDate: shift(task.dueDate),
      plannedDate: shift(task.plannedDate),
      plannedStartAt: shift(task.plannedStartAt),
      plannedEndAt: shift(task.plannedEndAt),
      dueAt: shift(task.dueAt),
      scheduledStartAt: shift(task.scheduledStartAt),
      scheduledEndAt: shift(task.scheduledEndAt),
      isRecurrenceException:
          task.recurrenceId != null || task.isRecurrenceException,
    ),
  );
}

Future<void> _shortenTaskDuration(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
) async {
  var minutes = task.estimatedMinutes.clamp(5, 24 * 60).toDouble();
  final result = await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.text('shortenDuration')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_formatMinutes(minutes.round())),
            Slider(
              value: minutes,
              min: 5,
              max: task.estimatedMinutes.clamp(5, 24 * 60).toDouble(),
              divisions: (task.estimatedMinutes.clamp(5, 24 * 60) ~/ 5).clamp(
                1,
                288,
              ),
              onChanged: (value) => setDialogState(() => minutes = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(minutes.round()),
            child: Text(context.text('save')),
          ),
        ],
      ),
    ),
  );
  if (result == null) return;
  await _saveOccurrenceEdit(
    controller,
    task.copyWith(estimatedMinutes: result),
  );
}

Future<void> _confirmWorkloadSuggestion(
  BuildContext context,
  TaskActionController controller,
  TaskItem task,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.text('confirmScheduleChange')),
      content: Text('${context.text('moveTomorrow')}: ${task.title}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.text('applyChange')),
        ),
      ],
    ),
  );
  if (confirmed == true) await _moveTaskToTomorrow(controller, task);
}

TaskPriority _lowerPriority(TaskPriority priority) {
  return switch (priority) {
    TaskPriority.critical => TaskPriority.high,
    TaskPriority.high => TaskPriority.normal,
    TaskPriority.normal || TaskPriority.low => TaskPriority.low,
  };
}

int _configuredAvailableMinutes(BuildContext context) {
  final config = AppServices.of(context).config;
  int parse(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  final start = parse(config.workStartTime);
  var end = parse(config.workEndTime);
  if (end <= start) end += 24 * 60;
  return (end - start - config.lunchDurationMinutes).clamp(0, 24 * 60);
}

int _interruptionDuration(TaskInterruption interruption, DateTime now) {
  if (interruption.durationSeconds > 0) return interruption.durationSeconds;
  final end = interruption.endedAt ?? now;
  return end.difference(interruption.startedAt).inSeconds.clamp(0, 1 << 31);
}

String _overdueDescription(BuildContext context, TaskItem task, DateTime now) {
  final due = task.effectiveDueUtc;
  if (due == null) return context.text('overdue');
  final when = AppServices.of(
    context,
  ).timeZoneService.formatTaskDateTime(context, due);
  final overdue = now.toUtc().difference(due).inSeconds.clamp(0, 1 << 31);
  return '${context.text('due')}: $when • ${context.text('overdueBy')} ${_formatSecondsCompact(overdue)}';
}

String _formatSecondsCompact(int seconds) {
  final safe = seconds.clamp(0, 1 << 31);
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h';
  return '${minutes}m';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }

  T? get lastOrNull {
    T? value;
    for (final item in this) {
      value = item;
    }
    return value;
  }
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) {
    return '${remaining}m';
  }
  if (remaining == 0) {
    return '${hours}h';
  }
  return '${hours}h ${remaining}m';
}
