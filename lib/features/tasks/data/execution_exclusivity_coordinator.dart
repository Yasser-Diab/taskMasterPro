import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/account/account_context.dart';
import '../../../core/providers.dart';
import 'standalone_pomodoro_store.dart';

enum StandaloneStartGateStatus { started, taskRuntimeActive }

class StandaloneStartGateResult {
  const StandaloneStartGateResult._(this.status, this.activeTaskId);

  const StandaloneStartGateResult.started()
    : this._(StandaloneStartGateStatus.started, null);

  const StandaloneStartGateResult.taskRuntimeActive(String taskId)
    : this._(StandaloneStartGateStatus.taskRuntimeActive, taskId);

  final StandaloneStartGateStatus status;
  final String? activeTaskId;

  bool get started => status == StandaloneStartGateStatus.started;
}

class TaskStartGateResult<T> {
  const TaskStartGateResult.started(this.value) : standaloneWasActive = false;

  const TaskStartGateResult.standaloneActive()
    : value = null,
      standaloneWasActive = true;

  final T? value;
  final bool standaloneWasActive;
}

/// Serializes the two device-local entry points that can claim execution.
///
/// Canonical task execution remains server/repository owned. The standalone
/// Pomodoro remains device-local. This coordinator only protects their local
/// mutual-exclusion boundary and never creates a synchronized command.
class ExecutionExclusivityCoordinator {
  factory ExecutionExclusivityCoordinator({
    required String accountId,
    required StandalonePomodoroStore standalone,
    required Future<String?> Function() readActiveTaskId,
    required Stream<String?> activeTaskIds,
  }) => ExecutionExclusivityCoordinator._(
    accountId: accountId,
    standalone: standalone,
    readActiveTaskId: readActiveTaskId,
    activeTaskIds: activeTaskIds,
  );

  ExecutionExclusivityCoordinator._({
    required String accountId,
    required this._standalone,
    required this._readActiveTaskId,
    required Stream<String?> activeTaskIds,
  }) : _gate = _AccountExecutionGate.acquire(accountId) {
    _runtimeSubscription = activeTaskIds.distinct().listen(
      (taskId) {
        if (taskId != null) unawaited(reconcileTaskRuntime(taskId));
      },
      // A temporary Drift/read failure must not tear down the local gate. The
      // next runtime emission or explicit start preflight reconciles again.
      onError: (Object _, StackTrace _) {},
    );
    unawaited(_reconcileCurrentRuntime());
  }

  final _AccountExecutionGate _gate;
  final StandalonePomodoroStore _standalone;
  final Future<String?> Function() _readActiveTaskId;
  StreamSubscription<String?>? _runtimeSubscription;
  bool _disposed = false;

  Future<StandaloneStartGateResult> startStandalone(
    Future<void> Function() start,
  ) {
    return _gate.run(() async {
      final activeTaskId = await _readActiveTaskId();
      if (activeTaskId != null) {
        await _resetStandaloneIfActive();
        return StandaloneStartGateResult.taskRuntimeActive(activeTaskId);
      }

      await start();

      // A Realtime/database write is not produced through this process gate.
      // Re-read before reporting success and reconcile forward if it arrived
      // while the local preference write was in flight.
      final taskAfterStart = await _readActiveTaskId();
      if (taskAfterStart != null) {
        await _resetStandaloneIfActive();
        return StandaloneStartGateResult.taskRuntimeActive(taskAfterStart);
      }
      return const StandaloneStartGateResult.started();
    });
  }

  Future<TaskStartGateResult<T>> startTask<T>({
    required bool stopStandalone,
    required Future<T> Function() start,
  }) {
    return _gate.run(() async {
      final standaloneState = await _standalone.load();
      if (standaloneState.isActive && !stopStandalone) {
        return TaskStartGateResult<T>.standaloneActive();
      }
      if (standaloneState.isActive) await _standalone.reset();
      return TaskStartGateResult<T>.started(await start());
    });
  }

  /// Reconciles a canonical runtime activation from this or another device.
  Future<void> reconcileTaskRuntime(String taskId) {
    return _gate.run(() async {
      if (taskId.isEmpty) return;
      await _resetStandaloneIfActive();
    });
  }

  Future<void> _reconcileCurrentRuntime() async {
    try {
      final taskId = await _readActiveTaskId();
      if (taskId != null) await reconcileTaskRuntime(taskId);
    } catch (_) {
      // The live runtime subscription remains installed and will retry on its
      // next canonical emission.
    }
  }

  Future<void> _resetStandaloneIfActive() async {
    if ((await _standalone.load()).isActive) await _standalone.reset();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _runtimeSubscription?.cancel();
    _runtimeSubscription = null;
    _gate.release();
  }
}

class _AccountExecutionGate {
  _AccountExecutionGate._(this.accountId);

  static final Map<String, _AccountExecutionGate> _accounts = {};

  static _AccountExecutionGate acquire(String accountId) {
    final gate = _accounts.putIfAbsent(
      accountId,
      () => _AccountExecutionGate._(accountId),
    );
    gate._references += 1;
    return gate;
  }

  final String accountId;
  int _references = 0;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void release() {
    _references -= 1;
    if (_references <= 0 && identical(_accounts[accountId], this)) {
      _accounts.remove(accountId);
    }
  }
}

final executionExclusivityCoordinatorProvider =
    Provider<ExecutionExclusivityCoordinator>((ref) {
      final accountId = ref.watch(activeAccountIdProvider) ?? '__signed_out__';
      final repository = ref.watch(taskRepositoryProvider);
      final coordinator = ExecutionExclusivityCoordinator(
        accountId: accountId,
        standalone: ref.watch(standalonePomodoroStoreProvider),
        readActiveTaskId: () async {
          final runtime = await repository.getRuntime();
          return runtime?.activeTaskId;
        },
        activeTaskIds: repository.watchRuntime().map(
          (runtime) => runtime?.activeTaskId,
        ),
      );
      ref.onDispose(() => unawaited(coordinator.dispose()));
      return coordinator;
    });
