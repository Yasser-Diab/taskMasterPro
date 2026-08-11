import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';

/// One account-scoped runtime subscription shared by every execution surface.
///
/// Task cards used to create one Drift watcher per visible card. On a long
/// schedule that multiplied database invalidations and one-second timers even
/// though only one task can own the canonical runtime.
final taskExecutionRuntimeProvider = StreamProvider<LocalRuntime?>(
  (ref) => ref.watch(taskRepositoryProvider).watchRuntime(),
);

/// Shared task lookup used by the shell and workspaces without repeatedly
/// constructing Futures or Drift streams during unrelated widget rebuilds.
final taskExecutionTaskProvider = StreamProvider.family<LocalTask?, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).watchTask(taskId),
);

/// A single lazily-running wall-clock source for small live timer renderers.
///
/// Consumers subscribe only while they own a running focus/break. Riverpod
/// shares this stream, so Dashboard, Execute, task cards and the compact bar do
/// not each allocate independent periodic timers.
final taskExecutionClockProvider = StreamProvider.autoDispose<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now().toUtc(),
  );
});
