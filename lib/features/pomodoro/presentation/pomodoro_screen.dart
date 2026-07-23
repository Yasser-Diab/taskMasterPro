import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../tasks/application/task_action_controller.dart';
import '../../tasks/domain/task_item.dart';
import '../../tasks/data/learning_activity_repository.dart';
import '../../tasks/domain/learning_activity_models.dart';
import '../domain/pomodoro_controller.dart';
import '../domain/pomodoro_models.dart';

class PomodoroScreen extends StatelessWidget {
  const PomodoroScreen({
    required this.tasks,
    required this.controller,
    required this.taskController,
    super.key,
  });

  final List<TaskItem> tasks;
  final PomodoroController controller;
  final TaskActionController taskController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.text('pomodoro'))),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final phaseLabel = switch (controller.phase) {
              PomodoroPhase.focus => context.text('focus'),
              PomodoroPhase.shortBreak => context.text('shortBreak'),
              PomodoroPhase.longBreak => context.text('longBreak'),
            };

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Text(
                          phaseLabel,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          controller.clockText,
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(fontFeatures: const []),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            if (controller.state.isInactive ||
                                controller.state == PomodoroRunState.focusReady)
                              FilledButton.icon(
                                onPressed: () => _start(context),
                                icon: const Icon(Icons.play_arrow_outlined),
                                label: Text(context.text('start')),
                              ),
                            if (controller.state.isRunning)
                              FilledButton.icon(
                                onPressed: _pause,
                                icon: const Icon(Icons.pause_outlined),
                                label: Text(context.text('pause')),
                              ),
                            if (controller.state.isPaused)
                              FilledButton.icon(
                                onPressed: _resume,
                                icon: const Icon(Icons.play_arrow_outlined),
                                label: Text(context.text('resume')),
                              ),
                            if (controller.state.isRunning ||
                                controller.state.isPaused)
                              OutlinedButton.icon(
                                onPressed: controller.completeEarly,
                                icon: const Icon(Icons.done_all_outlined),
                                label: Text(context.text('completeEarly')),
                              ),
                            if (controller.state ==
                                    PomodoroRunState.breakRunning ||
                                controller.state ==
                                    PomodoroRunState.breakPaused)
                              OutlinedButton.icon(
                                onPressed: () => _returnToFocus(context),
                                icon: const Icon(Icons.play_circle_outline),
                                label: Text(context.text('returnToFocus')),
                              ),
                            if (controller.state ==
                                PomodoroRunState.focusFinishedWaitingForUser)
                              FilledButton.icon(
                                onPressed: () => _startBreak(context),
                                icon: const Icon(Icons.self_improvement),
                                label: Text(context.text('startBreak')),
                              ),
                            if (controller.state ==
                                PomodoroRunState.focusFinishedWaitingForUser)
                              OutlinedButton.icon(
                                onPressed: () => controller.continueWorking(),
                                icon: const Icon(Icons.more_time_outlined),
                                label: Text(context.text('continueWorking')),
                              ),
                            if (controller.state ==
                                    PomodoroRunState
                                        .breakFinishedWaitingForUser ||
                                controller.state == PomodoroRunState.breakReady)
                              FilledButton.icon(
                                onPressed: () => _startNextFocus(context),
                                icon: const Icon(Icons.play_arrow_outlined),
                                label: Text(context.text('startFocus')),
                              ),
                            if (controller.phase != PomodoroPhase.focus)
                              OutlinedButton.icon(
                                onPressed: () => _skipBreak(context),
                                icon: const Icon(Icons.skip_next_outlined),
                                label: Text(context.text('skipBreak')),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => controller.addTime(),
                              icon: const Icon(Icons.more_time_outlined),
                              label: Text(context.text('addTime')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 840;
                    final children = [
                      _TimerSettings(controller: controller, tasks: tasks),
                      _SessionActions(
                        controller: controller,
                        taskController: taskController,
                      ),
                    ];
                    if (!twoColumns) {
                      return Column(
                        children: [
                          children[0],
                          const SizedBox(height: 14),
                          children[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: children[0]),
                        const SizedBox(width: 14),
                        Expanded(child: children[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                if (controller.phase != PomodoroPhase.focus)
                  _BreakActivityCard(controller: controller, tasks: tasks),
                if (controller.pendingBreakReview != null &&
                    AppServices.of(context).config.askBreakActivityReview)
                  _BreakReviewCard(controller: controller, tasks: tasks),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final activeTasks = tasks.where((task) => !task.isCompleted).toList();
    final selectedId =
        controller.selectedTaskId ??
        (activeTasks.isEmpty ? null : activeTasks.first.id);
    if (selectedId == null) {
      AppServices.of(
        context,
      ).notificationService.showWarning(context.text('selectTaskFirst'));
      return;
    }
    controller.selectTask(selectedId);
    final task = activeTasks.where((item) => item.id == selectedId).firstOrNull;
    if (task == null) return;
    controller.start();
    await taskController.startTask(task);
    final active = taskController.activeSession;
    if (active == null || active.task.id != task.id) return;
    controller.attachSession(active.session.id);
  }

  void _pause() {
    controller.pause();
    final active = taskController.activeSession;
    if (active != null) taskController.pauseTask(active.task);
  }

  void _resume() {
    controller.resume();
    final active = taskController.activeSession;
    if (active != null) taskController.resumeTask(active.task);
  }

  void _startBreak(BuildContext context) {
    controller.startBreak();
    final active = taskController.activeSession;
    if (active != null) {
      unawaited(taskController.beginPomodoroBreak());
    }
  }

  void _returnToFocus(BuildContext context) {
    controller.returnToFocus();
    final active = taskController.activeSession;
    if (active != null) {
      unawaited(taskController.preparePomodoroFocus());
    }
  }

  void _startNextFocus(BuildContext context) {
    controller.startFocus(sessionId: taskController.activeSession?.session.id);
    final active = taskController.activeSession;
    if (active != null) {
      unawaited(taskController.startPomodoroFocus());
    }
  }

  void _skipBreak(BuildContext context) {
    controller.skipBreak();
    final active = taskController.activeSession;
    if (active != null) {
      unawaited(taskController.endPomodoroBreak());
    }
  }
}

class _BreakActivityCard extends StatelessWidget {
  const _BreakActivityCard({required this.controller, required this.tasks});

  final PomodoroController controller;
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final activity = controller.breakActivity;
    if (activity == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.self_improvement_outlined,
                  color: context.appColors.info,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.text('breakActivityQuestion'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final use in PomodoroBreakUse.values)
                  if (use != PomodoroBreakUse.undecided)
                    ChoiceChip(
                      selected: activity.use == use,
                      label: Text(context.text('breakUse_${use.name}')),
                      onSelected: (_) => controller.classifyBreak(
                        use,
                        relatedTaskId: _suggestRelatedTask(use, tasks),
                      ),
                    ),
              ],
            ),
            if (activity.use == PomodoroBreakUse.anotherTask) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: activity.relatedTaskId,
                decoration: InputDecoration(
                  labelText: context.text('relatedTask'),
                ),
                items: [
                  for (final task in tasks.where((task) => !task.isCompleted))
                    DropdownMenuItem(value: task.id, child: Text(task.title)),
                ],
                onChanged: (taskId) => controller.classifyBreak(
                  PomodoroBreakUse.anotherTask,
                  relatedTaskId: taskId,
                ),
              ),
            ],
            if (activity.evidenceDomain != null) ...[
              const SizedBox(height: 10),
              Text(
                context.textWith('breakWebsiteDetected', {
                  'domain': activity.evidenceDomain!,
                }),
                textDirection: TextDirection.ltr,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BreakReviewCard extends StatelessWidget {
  const _BreakReviewCard({required this.controller, required this.tasks});

  final PomodoroController controller;
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final review = controller.pendingBreakReview;
    if (review == null) return const SizedBox.shrink();
    final relatedId =
        review.relatedTaskId ??
        _suggestRelatedTaskForEvidence(review, tasks) ??
        _suggestRelatedTask(review.use, tasks);
    final related = tasks.where((task) => task.id == relatedId).firstOrNull;
    final useful =
        review.use != PomodoroBreakUse.rest &&
        review.use != PomodoroBreakUse.undecided &&
        related != null;
    final minutes = (review.durationSeconds / 60).ceil();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.text('classifyBreakActivity'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              useful
                  ? context.textWith('breakCreditSummary', {
                      'minutes': '$minutes',
                      'task': related.title,
                    })
                  : context.text('breakRestRecorded'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (useful)
                  FilledButton(
                    onPressed: () => _credit(context, review, related),
                    child: Text(context.text('creditProgress')),
                  ),
                TextButton(
                  onPressed: controller.clearBreakReview,
                  child: Text(context.text('ignore')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _credit(
    BuildContext context,
    PomodoroBreakActivity review,
    TaskItem related,
  ) async {
    final sourceTaskId = controller.selectedTaskId;
    final sessionId = controller.sessionId;
    if (sourceTaskId == null || sessionId == null) return;
    await LearningActivityRepository(
      AppServices.of(context).supabaseService,
    ).recordBreakContribution(
      BreakContribution(
        sourceTaskId: sourceTaskId,
        sourceSessionId: sessionId,
        relatedTaskId: related.id,
        type: _contributionType(review.use),
        durationSeconds: review.durationSeconds,
        evidenceType: review.evidenceDomain == null
            ? 'manual_break_classification'
            : 'website_domain',
        evidenceReference: review.evidenceDomain,
        userConfirmed: true,
        startedAt: review.startedAt,
        endedAt: review.endedAt ?? DateTime.now(),
      ),
    );
    controller.clearBreakReview();
  }
}

String? _suggestRelatedTaskForEvidence(
  PomodoroBreakActivity activity,
  List<TaskItem> tasks,
) {
  final domain = activity.evidenceDomain;
  if (domain == null || domain.isEmpty) return null;
  for (final task in tasks.where((task) => !task.isCompleted)) {
    final candidates = [
      task.workspaceStartingUrl,
      task.workspaceHomeUrl,
      task.learningResourceLink,
    ];
    for (final candidate in candidates) {
      final host = Uri.tryParse(
        candidate ?? '',
      )?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      if (host == domain) return task.id;
    }
  }
  return null;
}

String? _suggestRelatedTask(PomodoroBreakUse use, List<TaskItem> tasks) {
  return switch (use) {
    PomodoroBreakUse.learning =>
      tasks
          .where(
            (task) =>
                task.taskDomain == TaskDomain.learning && !task.isCompleted,
          )
          .firstOrNull
          ?.id,
    PomodoroBreakUse.reading =>
      tasks
          .where(
            (task) =>
                task.taskType == TaskType.reading ||
                task.taskDomain == TaskDomain.reading,
          )
          .firstOrNull
          ?.id,
    PomodoroBreakUse.exercise =>
      tasks
          .where((task) => task.taskDomain == TaskDomain.sport)
          .firstOrNull
          ?.id,
    PomodoroBreakUse.housework =>
      tasks
          .where((task) => task.taskDomain == TaskDomain.household)
          .firstOrNull
          ?.id,
    _ => null,
  };
}

BreakContributionType _contributionType(PomodoroBreakUse use) => switch (use) {
  PomodoroBreakUse.learning => BreakContributionType.learning,
  PomodoroBreakUse.reading => BreakContributionType.reading,
  PomodoroBreakUse.exercise => BreakContributionType.exercise,
  PomodoroBreakUse.housework => BreakContributionType.housework,
  PomodoroBreakUse.anotherTask => BreakContributionType.anotherTask,
  PomodoroBreakUse.rest => BreakContributionType.rest,
  PomodoroBreakUse.custom ||
  PomodoroBreakUse.undecided => BreakContributionType.other,
};

class _TimerSettings extends StatelessWidget {
  const _TimerSettings({required this.controller, required this.tasks});

  final PomodoroController controller;
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context) {
    final activeTasks = tasks.where((task) => !task.isCompleted).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.text('currentFocus'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  controller.selectedTaskId ??
                  (activeTasks.isEmpty ? null : activeTasks.first.id),
              items: [
                for (final task in activeTasks)
                  DropdownMenuItem(
                    value: task.id,
                    child: Text(task.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: controller.selectTask,
              decoration: InputDecoration(labelText: context.text('tasks')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PomodoroPreset>(
              initialValue: controller.preset,
              items: [
                for (final preset in defaultPomodoroPresets)
                  DropdownMenuItem(value: preset, child: Text(preset.name)),
              ],
              onChanged: (preset) {
                if (preset != null) {
                  controller.selectPreset(preset);
                }
              },
              decoration: InputDecoration(labelText: context.text('preset')),
            ),
            const SizedBox(height: 12),
            SegmentedButton<TrackingMode>(
              selected: {controller.trackingMode},
              onSelectionChanged: (selection) {
                controller.setTrackingMode(selection.first);
              },
              segments: [
                ButtonSegment(
                  value: TrackingMode.interactive,
                  icon: const Icon(Icons.keyboard_outlined),
                  label: Text(context.text('interactiveMode')),
                ),
                ButtonSegment(
                  value: TrackingMode.video,
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(context.text('videoMode')),
                ),
                ButtonSegment(
                  value: TrackingMode.reading,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(context.text('readingMode')),
                ),
                ButtonSegment(
                  value: TrackingMode.manual,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(context.text('manualMode')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionActions extends StatelessWidget {
  const _SessionActions({
    required this.controller,
    required this.taskController,
  });

  final PomodoroController controller;
  final TaskActionController taskController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.text('sessionNote'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              minLines: 3,
              maxLines: 5,
              onChanged: controller.updateNote,
              decoration: InputDecoration(labelText: context.text('notes')),
            ),
            const SizedBox(height: 12),
            PopupMenuButton<InterruptionReason>(
              onSelected: controller.markInterruption,
              itemBuilder: (context) => [
                for (final reason in InterruptionReason.values)
                  PopupMenuItem(
                    value: reason,
                    child: Text(context.text('interruption_${reason.name}')),
                  ),
              ],
              child: IgnorePointer(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.report_problem_outlined),
                  label: Text(context.text('markInterruption')),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: controller.markUnsuccessful,
              icon: const Icon(Icons.flag_outlined),
              label: Text(context.text('unsuccessful')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                final summary = controller.stopAndSave();
                final message = summary == null
                    ? context.text('stopAndSave')
                    : context.text('changesSaved');
                final notifications = AppServices.of(
                  context,
                ).notificationService;
                await taskController.stopActiveSession();
                notifications.showSuccess(message);
              },
              icon: const Icon(Icons.save_outlined),
              label: Text(context.text('stopAndSave')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                controller.stopWithoutSaving();
                await taskController.stopActiveSession(discard: true);
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(context.text('stopNoSave')),
            ),
          ],
        ),
      ),
    );
  }
}
