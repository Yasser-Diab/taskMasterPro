/// The top-level shell is not a transient route: the user can move between
/// destinations without pushing a Navigator route.  This policy gives Android
/// back/edge gestures predictable semantics for that shell.
///
/// A back gesture from a destination returns to the preceding shell
/// destination. At the shell root, the first gesture only arms an exit prompt
/// and a second gesture inside the short confirmation window exits. Any
/// deliberate in-app navigation clears the armed exit state.
enum HomeShellBackAction { navigateInApp, showExitHint, exitApplication }

class HomeShellBackDecision {
  const HomeShellBackDecision._(this.action, {this.destinationIndex});

  const HomeShellBackDecision.navigateInApp(int destinationIndex)
    : this._(
        HomeShellBackAction.navigateInApp,
        destinationIndex: destinationIndex,
      );

  const HomeShellBackDecision.showExitHint()
    : this._(HomeShellBackAction.showExitHint);

  const HomeShellBackDecision.exitApplication()
    : this._(HomeShellBackAction.exitApplication);

  final HomeShellBackAction action;
  final int? destinationIndex;
}

class HomeShellBackNavigation {
  HomeShellBackNavigation({
    this.exitConfirmationWindow = const Duration(seconds: 2),
  });

  final Duration exitConfirmationWindow;
  final List<int> _destinationHistory = <int>[];
  DateTime? _armedAt;

  /// Records a deliberate top-level destination selection. The caller must
  /// not call this while applying a back decision, otherwise a back gesture
  /// would re-add the page it has just left.
  void recordDestination({required int from, required int to}) {
    cancelExit();
    if (from == to) return;
    _destinationHistory.add(from);
    // A very long tab-hopping session should not retain an unbounded history,
    // but the last destinations still behave like normal in-app back steps.
    if (_destinationHistory.length > 24) {
      _destinationHistory.removeAt(0);
    }
  }

  HomeShellBackDecision resolve({
    required int currentIndex,
    required int rootIndex,
    required DateTime now,
  }) {
    while (_destinationHistory.isNotEmpty) {
      final previousIndex = _destinationHistory.removeLast();
      if (previousIndex == currentIndex) continue;
      cancelExit();
      return HomeShellBackDecision.navigateInApp(previousIndex);
    }

    // History can be absent after process recreation or a deep link. Going to
    // the shell root is still safer than treating the first gesture as exit.
    if (currentIndex != rootIndex) {
      cancelExit();
      return HomeShellBackDecision.navigateInApp(rootIndex);
    }

    final armedAt = _armedAt;
    final elapsed = armedAt == null ? null : now.difference(armedAt);
    if (elapsed != null &&
        !elapsed.isNegative &&
        elapsed <= exitConfirmationWindow) {
      cancelExit();
      return const HomeShellBackDecision.exitApplication();
    }

    _armedAt = now;
    return const HomeShellBackDecision.showExitHint();
  }

  void cancelExit() => _armedAt = null;
}
