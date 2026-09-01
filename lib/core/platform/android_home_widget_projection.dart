import 'dart:ui' show Locale;

import '../../features/tasks/data/task_repository.dart';
import '../../features/tasks/domain/pomodoro_execution_state.dart';
import '../database/app_database.dart';
import '../localization/app_localizations.dart';
import 'android_home_widget_service.dart';

/// Builds the launcher projection from the same canonical local task/runtime
/// rows whether TaskMaster is visible or a headless widget command just ran.
abstract final class AndroidHomeWidgetProjection {
  static Future<AndroidHomeWidgetState> build({
    required TaskRepository repository,
    required String ownerId,
    required String localeCode,
    DateTime? now,
  }) async {
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final l10n = AppLocalizations(Locale(localeCode));
    LocalRuntime? runtime;
    LocalTask? task;

    // Runtime and task are separate Drift rows. A hand-off can commit between
    // the two reads, so never publish a task fetched for an older runtime
    // revision. Retry from the canonical runtime until the aggregate is one
    // coherent snapshot; the native store supplies the final monotonic guard.
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final candidateRuntime = await repository.getRuntimeIncludingIdle();
      final candidateTask = candidateRuntime?.activeTaskId == null
          ? null
          : await repository.getTask(candidateRuntime!.activeTaskId!);
      final confirmedRuntime = await repository.getRuntimeIncludingIdle();
      if (sameWidgetRuntimeProjection(candidateRuntime, confirmedRuntime)) {
        runtime = confirmedRuntime;
        task = candidateTask;
        break;
      }
    }
    runtime ??= await repository.getRuntimeIncludingIdle();
    task = runtime?.activeTaskId == null
        ? null
        : await repository.getTask(runtime!.activeTaskId!);

    if (task == null || runtime == null) {
      final eligibleTasks = _eligibleTasks(await repository.watchTasks().first);
      final suggestions = _selectSuggestions(
        eligibleTasks,
        effectiveNow.toLocal(),
      );
      return AndroidHomeWidgetState(
        mode: AndroidHomeWidgetMode.idle,
        localeCode: localeCode,
        statusLabel: 'DayVector',
        title: l10n.text('widget_idle_title'),
        message: suggestions.isEmpty
            ? l10n.text('widget_no_suggestions')
            : l10n.text('widget_idle_message'),
        timerLabel: l10n.format('widget_tasks_ready', {
          'count': eligibleTasks.length,
        }),
        timerMode: AndroidHomeWidgetTimerMode.fixed,
        actionLabel: l10n.text('widget_open_app'),
        completionLabel: l10n.text('widget_idle_message'),
        ownerId: ownerId,
        runtimeRevision: runtime?.revision,
        runtimeUpdatedAt: runtime?.updatedAt,
        suggestions: [
          for (final suggestion in suggestions)
            AndroidHomeWidgetSuggestion(
              id: suggestion.id,
              title: suggestion.title,
            ),
        ],
      );
    }

    final recordedMs = liveTaskRecordedWorkMs(
      recordedMs: runtime.accumulatedActiveMs,
      running: runtime.state == 'running',
      segmentStartedAt: runtime.segmentStartedAt,
      now: effectiveNow,
    );
    final pomodoro = task.executionMode == 'pomodoro'
        ? PomodoroExecutionSnapshot.fromTask(
            task: task,
            runtime: runtime,
            now: effectiveNow,
          )
        : null;
    final widgetMode = switch (runtime.state) {
      'break' => AndroidHomeWidgetMode.breakTime,
      'paused' => AndroidHomeWidgetMode.paused,
      _ => AndroidHomeWidgetMode.running,
    };
    final controls = switch (runtime.state) {
      'break' => [
        AndroidHomeWidgetControl(
          id: 'start_focus',
          label: l10n.text('widget_action_focus'),
        ),
        AndroidHomeWidgetControl(
          id: 'extend_break',
          label: l10n.text('widget_action_extend'),
        ),
        AndroidHomeWidgetControl(
          id: 'finish_task',
          label: l10n.text('widget_action_finish'),
        ),
      ],
      'paused' => [
        AndroidHomeWidgetControl(
          id: 'resume',
          label: l10n.text('widget_action_continue'),
        ),
        AndroidHomeWidgetControl(
          id: 'finish_task',
          label: l10n.text('widget_action_finish'),
        ),
      ],
      _ => [
        AndroidHomeWidgetControl(
          id: 'pause',
          label: l10n.text('widget_action_pause'),
        ),
        if (task.executionMode == 'pomodoro')
          AndroidHomeWidgetControl(
            id: 'start_break',
            label: l10n.text('widget_action_break'),
          ),
        AndroidHomeWidgetControl(
          id: 'finish_task',
          label: l10n.text('widget_action_finish'),
        ),
      ],
    };
    var timerMode = AndroidHomeWidgetTimerMode.fixed;
    DateTime? timerBoundary;
    late String timerLabel;
    late String statusLabel;
    late String message;
    late String completionLabel;
    double progress;

    if (pomodoro != null) {
      final waiting = pomodoro.isWaiting || pomodoro.remainingMs <= 0;
      final intervalMs = pomodoro.intervalDurationMs.clamp(1, 1 << 53);
      progress = ((intervalMs - pomodoro.remainingMs) / intervalMs).clamp(
        0.0,
        1.0,
      );
      timerLabel = formatPomodoroCountdown(pomodoro.remainingMs);
      completionLabel = l10n.text(
        pomodoro.isBreak ? 'widget_break_complete' : 'widget_focus_complete',
      );
      if (!waiting && runtime.state != 'paused') {
        timerMode = AndroidHomeWidgetTimerMode.countdown;
        timerBoundary = effectiveNow.add(
          Duration(milliseconds: pomodoro.remainingMs),
        );
      }
      statusLabel = l10n.text(
        pomodoro.isBreak
            ? 'pomodoro_break_session'
            : runtime.state == 'paused'
            ? 'status_paused'
            : 'pomodoro_focus_session',
      );
      message = waiting
          ? completionLabel
          : runtime.state == 'paused'
          ? l10n.text('widget_paused_message')
          : pomodoro.isBreak
          ? l10n.text('widget_break_message')
          : l10n.text('widget_focus_message');
    } else {
      final plannedMs = task.estimatedDurationMs.clamp(0, 1 << 53);
      final remainingMs = taskEffortRemainingMs(
        plannedMs: plannedMs,
        recordedMs: recordedMs,
      );
      final overtimeMs = taskEffortOvertimeMs(
        plannedMs: plannedMs,
        recordedMs: recordedMs,
      );
      progress = plannedMs <= 0 ? 0 : (recordedMs / plannedMs).clamp(0.0, 1.0);
      completionLabel = l10n.text('status_overdue');
      if (runtime.state == 'running' && remainingMs > 0) {
        timerMode = AndroidHomeWidgetTimerMode.countdown;
        timerBoundary = effectiveNow.add(Duration(milliseconds: remainingMs));
        timerLabel = formatTaskEffortCountdown(remainingMs);
      } else if (runtime.state == 'running' && overtimeMs > 0) {
        timerMode = AndroidHomeWidgetTimerMode.countup;
        timerBoundary = effectiveNow.subtract(
          Duration(milliseconds: overtimeMs),
        );
        timerLabel = formatTaskEffortOvertime(overtimeMs);
      } else {
        timerLabel = overtimeMs > 0
            ? formatTaskEffortOvertime(overtimeMs)
            : formatTaskEffortCountdown(remainingMs);
      }
      statusLabel = overtimeMs > 0
          ? l10n.text('status_overdue')
          : runtime.state == 'paused'
          ? l10n.text('status_paused')
          : l10n.text('currently_running');
      message = runtime.state == 'paused'
          ? l10n.text('widget_paused_message')
          : l10n.text('widget_focus_message');
    }

    return AndroidHomeWidgetState(
      mode: widgetMode,
      localeCode: localeCode,
      statusLabel: statusLabel,
      title: task.title,
      message: message,
      timerLabel: timerLabel,
      timerMode: timerMode,
      timerBoundary: timerBoundary,
      progress: progress,
      actionLabel: l10n.text('widget_open_task'),
      completionLabel: completionLabel,
      ownerId: ownerId,
      taskId: task.id,
      sessionId: runtime.sessionId,
      runtimeRevision: runtime.revision,
      runtimeUpdatedAt: runtime.updatedAt,
      controls: runtime.sessionId == null ? const [] : controls,
    );
  }

  static List<LocalTask> _selectSuggestions(
    List<LocalTask> tasks,
    DateTime now,
  ) {
    final eligible = tasks.toList();
    DateTime? schedule(LocalTask task) =>
        task.plannedStart?.toLocal() ??
        task.scheduledDate?.toLocal() ??
        task.dueAt?.toLocal();
    int bucket(LocalTask task) {
      final value = schedule(task);
      if (value == null) return 3;
      final day = DateTime(value.year, value.month, value.day);
      final today = DateTime(now.year, now.month, now.day);
      if (day.isBefore(today)) return 0;
      if (day == today) return 1;
      return 2;
    }

    eligible.sort((left, right) {
      final byBucket = bucket(left).compareTo(bucket(right));
      if (byBucket != 0) return byBucket;
      final byPriority = right.priority.compareTo(left.priority);
      if (byPriority != 0) return byPriority;
      final leftSchedule = schedule(left);
      final rightSchedule = schedule(right);
      if (leftSchedule != null && rightSchedule != null) {
        final bySchedule = leftSchedule.compareTo(rightSchedule);
        if (bySchedule != 0) return bySchedule;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return eligible.take(3).toList(growable: false);
  }

  static List<LocalTask> _eligibleTasks(List<LocalTask> tasks) => tasks
      .where(
        (task) => !const {
          'completed',
          'cancelled',
          'archived',
          'skipped',
        }.contains(task.status),
      )
      .toList(growable: false);
}

/// A widget projection is owned by one exact persisted runtime snapshot. The
/// update time distinguishes same-revision local repairs while the revision
/// remains the primary canonical ordering key.
bool sameWidgetRuntimeProjection(LocalRuntime? left, LocalRuntime? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null) return left == null && right == null;
  return left.userId == right.userId &&
      left.revision == right.revision &&
      left.updatedAt.isAtSameMomentAs(right.updatedAt) &&
      left.activeTaskId == right.activeTaskId &&
      left.sessionId == right.sessionId &&
      left.state == right.state;
}
