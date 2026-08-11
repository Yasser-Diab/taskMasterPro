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
