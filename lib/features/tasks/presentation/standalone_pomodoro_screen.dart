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
    final remainingFraction = state.intervalDurationMs <= 0
        ? 0.0
        : (remainingMs / state.intervalDurationMs).clamp(0.0, 1.0);
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
          constraints: const BoxConstraints(maxWidth: 1180),
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
              ExecutionTimerSurface(
                surfaceKey: const ValueKey('standalone-pomodoro-state-card'),
                mode: 'pomodoro',
                title: phaseLabel,
                stateLabel: stateLabel,
                icon: Icons.center_focus_strong,
                isBreak: state.isBreak,
                active: state.isRunning,
                paused: state.isPaused,
                waiting: state.isFinished || !state.isActive,
                remainingFraction: remainingFraction,
                contentBuilder: (context, palette) => LayoutBuilder(
                  builder: (context, constraints) {
                    final timer = ExecutionTimerDial(
                      displayTime: displayTime,
                      progress: remainingFraction,
                      remainingFraction: remainingFraction,
                      isBreak: state.isBreak,
                      active: state.isRunning,
                      waiting: state.isFinished || !state.isActive,
                      paused: state.isPaused,
                      semanticLabel: phaseLabel,
                      stateLabel: stateLabel,
                      modeIcon: Icons.center_focus_strong,
                    );
                    final details = _StandaloneTimerDetails(
                      state: state,
                      palette: palette,
                      focusMinutes: focusMinutes,
                      breakMinutes: breakMinutes,
                      onFocusMinutes: onFocusMinutes,
                      onBreakMinutes: onBreakMinutes,
                      onStartFocus: onStartFocus,
                      onPause: onPause,
                      onResume: onResume,
                      onStartBreak: onStartBreak,
                      onNextFocus: onNextFocus,
                      onExtendBreak: onExtendBreak,
                      onReset: onReset,
                    );
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          Center(child: timer),
                          const SizedBox(height: 22),
                          details,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 11, child: Center(child: timer)),
                        const SizedBox(width: 34),
                        Expanded(flex: 10, child: details),
                      ],
                    );
                  },
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

class _StandaloneTimerDetails extends StatelessWidget {
  const _StandaloneTimerDetails({
    required this.state,
    required this.palette,
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
  final ExecutionTimerPalette palette;
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
    final primaryForeground =
        ThemeData.estimateBrightnessForColor(palette.accent) == Brightness.dark
        ? Colors.white
        : const Color(0xFF07130D);
    final primary = switch (state.phase) {
      StandalonePomodoroPhase.idle => (
        onStartFocus,
        Icons.play_arrow_rounded,
        'start_focus',
      ),
      StandalonePomodoroPhase.focusRunning => (
        onPause,
        Icons.pause_rounded,
        'pause',
      ),
      StandalonePomodoroPhase.focusPaused ||
      StandalonePomodoroPhase.breakPaused => (
        onResume,
        Icons.play_arrow_rounded,
        'resume',
      ),
      StandalonePomodoroPhase.focusFinished => (
        onStartBreak,
        Icons.coffee_outlined,
        'notification_start_break',
      ),
      StandalonePomodoroPhase.breakRunning ||
      StandalonePomodoroPhase.breakFinished => (
        onNextFocus,
        Icons.center_focus_strong,
        'notification_start_focus',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.format('standalone_pomodoro_sessions_completed', {
            'count': state.completedFocusCount,
          }),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          state.isFinished
              ? state.isBreak
                    ? context.l10n.text('pomodoro_break_complete_waiting')
                    : context.l10n.format('pomodoro_focus_complete_waiting', {
                        'duration': context.l10n.duration(
                          Duration(milliseconds: state.breakDurationMs),
                        ),
                      })
              : context.l10n.text('standalone_pomodoro_description'),
          key: const ValueKey('standalone-pomodoro-state-label'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (!state.isActive) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
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
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: !state.isActive
                  ? const ValueKey('standalone-pomodoro-start')
                  : state.isBreak
                  ? const ValueKey('standalone-pomodoro-skip-break')
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: primaryForeground,
                shadowColor: palette.glow,
                elevation: 2,
              ),
              onPressed: primary.$1,
              icon: Icon(primary.$2),
              label: Text(context.l10n.text(primary.$3)),
            ),
            if (state.phase == StandalonePomodoroPhase.focusRunning)
              OutlinedButton.icon(
                key: const ValueKey('standalone-pomodoro-skip-focus'),
                onPressed: onStartBreak,
                icon: const Icon(Icons.coffee_outlined),
                label: Text(context.l10n.text('notification_start_break')),
              ),
            if (state.phase == StandalonePomodoroPhase.focusFinished)
              OutlinedButton.icon(
                key: const ValueKey('standalone-pomodoro-continue-focus'),
                onPressed: onNextFocus,
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(context.l10n.text('notification_continue_working')),
              ),
            if (state.isBreak)
              OutlinedButton.icon(
                key: const ValueKey('standalone-pomodoro-extend-break'),
                onPressed: onExtendBreak,
                icon: const Icon(Icons.more_time),
                label: Text(context.l10n.text('notification_extend_break')),
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
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final value in values)
          DropdownMenuItem(
            value: value,
            child: Text(
              context.l10n.format('duration_minutes', {'count': value}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged == null ? null : (value) => onChanged!(value!),
    ),
  );
}
