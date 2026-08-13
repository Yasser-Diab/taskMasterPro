import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The authenticated account currently allowed to access local application
/// state.  It is changed only by AuthGate after the prior account workers have
/// stopped.  All account-scoped providers depend on it, which disposes their
/// old repositories and closes the prior account database.
final activeAccountIdProvider =
    NotifierProvider<ActiveAccountIdNotifier, String?>(
      ActiveAccountIdNotifier.new,
    );

class ActiveAccountIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? userId) => state = userId;
}

/// Serializes the destructive boundary between two account-scoped local
/// databases. Callers provide the concrete worker/database operations so the
/// ordering can be regression-tested without opening an authenticated UI.
class AccountDatabaseTransitionCoordinator {
  String? _activeAccountId;
  Future<void> _tail = Future<void>.value();

  String? get activeAccountId => _activeAccountId;

  Future<void> select(
    String? userId, {
    required Future<void> Function() stopSync,
    required Future<void> Function() stopActivity,
    required Future<void> Function() closeDatabase,
    required void Function(String? userId) activate,
  }) {
    if (_activeAccountId == userId) return _tail;
    final transition = _tail.then((_) async {
      if (_activeAccountId == userId) return;
      await stopSync();
      await stopActivity();
      await closeDatabase();
      activate(userId);
      _activeAccountId = userId;
    });
    // Keep the internal queue usable after a surfaced failure. The caller of
    // this transition still receives the original error and may retry.
    _tail = transition.then<void>((_) {}, onError: (_, _) {});
    return transition;
  }
}
