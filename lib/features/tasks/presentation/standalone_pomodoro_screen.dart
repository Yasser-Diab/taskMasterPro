import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/execution_exclusivity_coordinator.dart';
import '../data/standalone_pomodoro_store.dart';
import '../data/task_execution_providers.dart';
import '../domain/pomodoro_execution_state.dart';
import 'task_workspace_screen.dart';

class StandalonePomodoroScreen extends ConsumerStatefulWidget {
  const StandalonePomodoroScreen({this.embedded = false, super.key});

  /// The top-level shell supplies its own navigation. Settings and any other
  /// pushed route retain the normal in-app back affordance.
  final bool embedded;

  @override
  ConsumerState<StandalonePomodoroScreen> createState() =>
      _StandalonePomodoroScreenState();
}

class _StandalonePomodoroScreenState
    extends ConsumerState<StandalonePomodoroScreen> {
  Timer? _clock;
  int _focusMinutes = 25;
  int _breakMinutes = 5;
  bool _initializedDurations = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final state = ref.read(standalonePomodoroStateProvider).value;
      if (state?.isRunning == true) {
        setState(() {});
        if (state!.remainingAt(DateTime.now().toUtc()) == 0) {
          unawaited(
            ref
                .read(standalonePomodoroStoreProvider)
                .advanceIfDue(now: DateTime.now().toUtc()),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _startFocus() async {
    final store = ref.read(standalonePomodoroStoreProvider);
    final result = await ref
        .read(executionExclusivityCoordinatorProvider)
        .startStandalone(() async {
          await store.configure(
            focus: Duration(minutes: _focusMinutes),
            rest: Duration(minutes: _breakMinutes),
          );
          await store.startFocus();
        });
    if (!mounted) return;
    if (!result.started && result.activeTaskId != null) {
      await _showTaskOwnsTimer(result.activeTaskId!);
    }
  }

  Future<void> _resume() => ref
      .read(executionExclusivityCoordinatorProvider)
      .startStandalone(() => ref.read(standalonePomodoroStoreProvider).resume())
      .then((result) async {
        if (mounted && !result.started && result.activeTaskId != null) {
          await _showTaskOwnsTimer(result.activeTaskId!);
        }
      });

  Future<void> _startBreak() => ref
      .read(executionExclusivityCoordinatorProvider)
      .startStandalone(
        () => ref.read(standalonePomodoroStoreProvider).startBreak(),
      )
      .then((result) async {
        if (mounted && !result.started && result.activeTaskId != null) {
          await _showTaskOwnsTimer(result.activeTaskId!);
        }
      });

  Future<void> _extendBreak() async {
    await ref.read(standalonePomodoroStoreProvider).extendBreak();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('break_extended_five'))),
    );
  }

  Future<void> _showTaskOwnsTimer(String taskId) async {
    final task = await ref.read(taskRepositoryProvider).getTask(taskId);
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.text('standalone_pomodoro_task_active_title'),
        ),
        content: Text(
          dialogContext.l10n.format('standalone_pomodoro_task_active_detail', {
            'task': task?.title ?? dialogContext.l10n.text('active_task'),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              dialogContext.l10n.text('standalone_pomodoro_open_task'),
            ),
          ),
        ],
      ),
    );
    if (open == true && mounted && task != null) {
      await TaskWorkspaceScreen.open(context, task);
    }
  }

  Future<void> _resetWithConfirmation() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.text('standalone_pomodoro_reset_title')),
        content: Text(
          dialogContext.l10n.text('standalone_pomodoro_reset_detail'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.text('stop_and_reset')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await ref.read(standalonePomodoroStoreProvider).reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(standalonePomodoroStateProvider);
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded ? null : const BackButton(),
        title: Text(context.l10n.text('standalone_pomodoro')),
      ),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(context.l10n.text('standalone_pomodoro_load_failed')),
        ),
        data: (state) {
          if (!_initializedDurations) {
            _initializedDurations = true;
            _focusMinutes =
                state.focusDurationMs ~/ Duration.millisecondsPerMinute;
            _breakMinutes =
                state.breakDurationMs ~/ Duration.millisecondsPerMinute;
          }
          return _TimerBody(
            state: state,
            taskRuntimeActive: runtime?.activeTaskId != null,
            focusMinutes: _focusMinutes,
            breakMinutes: _breakMinutes,
            onFocusMinutes: state.isActive
                ? null
                : (value) => setState(() => _focusMinutes = value),
            onBreakMinutes: state.isActive
                ? null
                : (value) => setState(() => _breakMinutes = value),
            onStartFocus: _startFocus,
            onPause: () => ref.read(standalonePomodoroStoreProvider).pause(),
            onResume: _resume,
            onStartBreak: _startBreak,
            onNextFocus: _startFocus,
            onExtendBreak: _extendBreak,
            onReset: _resetWithConfirmation,
          );
        },
      ),
    );
  }
}

class _TimerBody extends StatelessWidget {
  const _TimerBody({
    required this.state,
    required this.taskRuntimeActive,
    required this.focusMinutes,
    required this.breakMinutes,
    required this.onFocusMinutes,
    required this.onBreakMinutes,
    required this.onStartFocus,
    required this.onPause,
    required this.onResume,
    required this.onStartBreak,
    required this.onNextFocus,
    required this.onExtendBreak,
    required this.onReset,
  });

  final StandalonePomodoroState state;
  final bool taskRuntimeActive;
  final int focusMinutes;
  final int breakMinutes;
  final ValueChanged<int>? onFocusMinutes;
  final ValueChanged<int>? onBreakMinutes;
  final VoidCallback onStartFocus;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStartBreak;
  final VoidCallback onNextFocus;
  final VoidCallback onExtendBreak;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final remainingMs = state.remainingAt(now);
    final displayTime = formatPomodoroCountdown(remainingMs);
    final timerState = pomodoroTimerVisualState(
      active: state.isRunning,
      paused: state.isPaused,
      waiting: state.isFinished || !state.isActive,
    );
    final progress = state.intervalDurationMs <= 0
        ? 0.0
        : 1 - (remainingMs / state.intervalDurationMs).clamp(0.0, 1.0);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final colors = Theme.of(context).colorScheme;
    final phaseLabel = state.phase == StandalonePomodoroPhase.idle
        ? context.l10n.text('standalone_pomodoro_ready')
        : state.isBreak
        ? context.l10n.text('pomodoro_break_session')
        : context.l10n.text('pomodoro_focus_session');
    final stateLabel = switch (timerState) {
      PomodoroTimerVisualState.running => context.l10n.taskStatus('running'),
      PomodoroTimerVisualState.paused => context.l10n.taskStatus('paused'),
      PomodoroTimerVisualState.waiting when state.isFinished =>
        context.l10n.text('pomodoro_waiting'),
      PomodoroTimerVisualState.waiting => context.l10n.text(
        'standalone_pomodoro_ready',
      ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 32,
          compact ? 16 : 32,
          compact ? 16 : 32,
          32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.text('standalone_pomodoro_description'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              if (taskRuntimeActive && !state.isActive)
                Card(
                  color: colors.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.task_alt, color: colors.onTertiaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.text(
                              'standalone_pomodoro_task_active_banner',
                            ),
                            style: TextStyle(color: colors.onTertiaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Card(
                key: const ValueKey('standalone-pomodoro-state-card'),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 20 : 32),
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: compact ? 138 : 178,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: compact ? 8 : 10,
                                backgroundColor: colors.surfaceContainerHighest,
                              ),
                            ),
                            Icon(
                              state.isBreak
                                  ? Icons.coffee_outlined
                                  : Icons.timer_outlined,
                              size: compact ? 46 : 58,
                              color: colors.primary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        phaseLabel,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stateLabel,
                        key: const ValueKey('standalone-pomodoro-state-label'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        label: context.l10n.format(
                          'standalone_pomodoro_time_remaining',
                          {'time': displayTime},
                        ),
                        child: Text(
                          displayTime,
                          key: const ValueKey('standalone-pomodoro-clock'),
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                      if (state.isFinished) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.isBreak
                              ? context.l10n.text(
                                  'pomodoro_break_complete_waiting',
                                )
                              : context.l10n
                                    .format('pomodoro_focus_complete_waiting', {
                                      'duration': context.l10n.duration(
                                        Duration(
                                          milliseconds: state.breakDurationMs,
                                        ),
                                      ),
                                    }),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (!state.isActive)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _DurationDropdown(
                              label: context.l10n.text('focus_duration'),
                              value: focusMinutes,
                              values: const [15, 20, 25, 30, 45, 60],
                              onChanged: onFocusMinutes,
                            ),
                            _DurationDropdown(
                              label: context.l10n.text('break_duration'),
                              value: breakMinutes,
                              values: const [5, 10, 15, 20],
                              onChanged: onBreakMinutes,
                            ),
                          ],
                        ),
                      if (!state.isActive) const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          if (!state.isActive)
                            FilledButton.icon(
                              key: const ValueKey('standalone-pomodoro-start'),
                              onPressed: onStartFocus,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(context.l10n.text('start_focus')),
                            ),
                          if (state.isRunning)
                            FilledButton.icon(
                              onPressed: onPause,
                              icon: const Icon(Icons.pause),
                              label: Text(context.l10n.text('pause')),
                            ),
                          if (state.isPaused)
                            FilledButton.icon(
                              onPressed: onResume,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(context.l10n.text('resume')),
                            ),
                          if (state.phase ==
                              StandalonePomodoroPhase.focusFinished)
                            FilledButton.icon(
                              onPressed: onStartBreak,
                              icon: const Icon(Icons.coffee_outlined),
                              label: Text(
                                context.l10n.text(
                                  'standalone_pomodoro_skip_focus',
                                ),
                              ),
                            ),
                          if (state.phase ==
                              StandalonePomodoroPhase.focusFinished)
                            OutlinedButton.icon(
                              key: const ValueKey(
                                'standalone-pomodoro-continue-focus',
                              ),
                              onPressed: onNextFocus,
                              icon: const Icon(Icons.center_focus_strong),
                              label: Text(
                                context.l10n.text(
                                  'notification_continue_working',
                                ),
                              ),
                            ),
                          if (!state.isBreak &&
                              state.phase != StandalonePomodoroPhase.idle &&
                              state.phase !=
                                  StandalonePomodoroPhase.focusFinished)
                            OutlinedButton.icon(
                              key: const ValueKey(
                                'standalone-pomodoro-skip-focus',
                              ),
                              onPressed: onStartBreak,
                              icon: const Icon(Icons.coffee_outlined),
                              label: Text(
                                context.l10n.text('notification_start_break'),
                              ),
                            ),
                          if (state.phase ==
                              StandalonePomodoroPhase.breakFinished)
                            FilledButton.icon(
                              onPressed: onNextFocus,
                              icon: const Icon(Icons.center_focus_strong),
                              label: Text(
                                context.l10n.text('notification_start_focus'),
                              ),
                            ),
                          if (state.isBreak &&
                              state.phase !=
                                  StandalonePomodoroPhase.breakFinished)
                            OutlinedButton.icon(
                              key: const ValueKey(
                                'standalone-pomodoro-skip-break',
                              ),
                              onPressed: onNextFocus,
                              icon: const Icon(Icons.skip_next_rounded),
                              label: Text(
                                context.l10n.text('pomodoro_skip_break'),
                              ),
                            ),
                          if (state.isBreak)
                            OutlinedButton.icon(
                              key: const ValueKey(
                                'standalone-pomodoro-extend-break',
                              ),
                              onPressed: onExtendBreak,
                              icon: const Icon(Icons.more_time),
                              label: Text(
                                context.l10n.text('notification_extend_break'),
                              ),
                            ),
                          if (state.isActive)
                            OutlinedButton.icon(
                              onPressed: onReset,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: Text(context.l10n.text('stop_and_reset')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.format('standalone_pomodoro_sessions_completed', {
                  'count': state.completedFocusCount,
                }),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DurationDropdown extends StatelessWidget {
  const _DurationDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> values;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final value in values)
          DropdownMenuItem(
            value: value,
            child: Text(
              context.l10n.format('duration_minutes', {'count': value}),
            ),
          ),
      ],
      onChanged: onChanged == null ? null : (value) => onChanged!(value!),
    ),
  );
}
