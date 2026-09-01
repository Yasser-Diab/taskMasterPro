import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/auth/presentation/auth_gate.dart';

void main() {
  test('only a real suspended interval requests a Realtime catch-up', () {
    final lifecycle = RealtimeLifecycleRecoveryState();

    expect(lifecycle.observe(AppLifecycleState.inactive), isFalse);
    expect(lifecycle.observe(AppLifecycleState.resumed), isFalse);

    expect(lifecycle.observe(AppLifecycleState.hidden), isFalse);
    expect(lifecycle.observe(AppLifecycleState.paused), isFalse);
    expect(lifecycle.observe(AppLifecycleState.resumed), isTrue);
    expect(
      lifecycle.observe(AppLifecycleState.resumed),
      isFalse,
      reason: 'One background interval performs exactly one bounded catch-up.',
    );
  });
}
