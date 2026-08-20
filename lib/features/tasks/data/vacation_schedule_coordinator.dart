import 'dart:async';

/// Keeps recurrence materialization and vacation adjustments converged while
/// an account remains open. Both local edits and canonical rows projected by
/// synchronization flow through the same vacation stream.
class VacationScheduleCoordinator {
  VacationScheduleCoordinator({
    required this.changes,
    required this.reconcile,
    required this.generate,
    required this.drain,
    this.debounce = const Duration(milliseconds: 250),
  });

  final Stream<Object?> changes;
  final Future<int> Function() reconcile;
  final Future<int> Function() generate;
  final Future<void> Function() drain;
  final Duration debounce;

  StreamSubscription<Object?>? _subscription;
  Timer? _timer;
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  void start() {
    if (_disposed || _subscription != null) return;
    _subscription = changes.listen(
      (_) => schedule(),
      onError: (Object _, StackTrace _) {
        // A database stream is re-established with the next account-scoped
        // provider. One projection failure must not crash the application.
      },
    );
  }

  void schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(runNow().catchError((Object _, StackTrace _) => false));
    });
  }

  /// Runs the complete deterministic pipeline. Calls are serialized so a
  /// burst of Realtime and snapshot projections cannot race one another.
  Future<bool> runNow() {
    if (_disposed) return Future<bool>.value(false);
    _timer?.cancel();
    _timer = null;
    final operation = _tail.then((_) => _runPipeline());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<bool> _runPipeline() async {
    final beforeGeneration = await reconcile();
    final generated = await generate();
    final afterGeneration = await reconcile();
    final changed = beforeGeneration + generated + afterGeneration > 0;
    if (changed) await drain();
    return changed;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _tail;
  }
}
