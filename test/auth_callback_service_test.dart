import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/auth/data/auth_callback_service.dart';

void main() {
  final expected = Uri.parse('pro.taskmaster.app://auth-callback');

  test('ignores links that are not DayVector auth callbacks', () async {
    var exchanges = 0;
    final coordinator = AuthCallbackCoordinator(
      expectedCallback: expected,
      exchange: (_) async => exchanges += 1,
    );

    await coordinator.handle(Uri.parse('https://example.com/?code=secret'));
    await coordinator.handle(
      Uri.parse('pro.taskmaster.app://different?code=secret'),
    );
    await coordinator.handle(expected);

    expect(exchanges, 0);
    await coordinator.dispose();
  });

  test(
    'exchanges one callback exactly once across repeated delivery',
    () async {
      var exchanges = 0;
      final exchangeGate = Completer<void>();
      final coordinator = AuthCallbackCoordinator(
        expectedCallback: expected,
        exchange: (_) {
          exchanges += 1;
          return exchangeGate.future;
        },
      );
      final callback = Uri.parse(
        'pro.taskmaster.app://auth-callback?code=short-lived-code',
      );
      final completed = expectLater(
        coordinator.events,
        emits(
          isA<AuthCallbackEvent>().having(
            (event) => event.kind,
            'kind',
            AuthCallbackEventKind.completed,
          ),
        ),
      );

      final first = coordinator.handle(callback);
      final duplicate = coordinator.handle(callback);
      expect(exchanges, 1);
      exchangeGate.complete();
      await Future.wait([first, duplicate]);
      await coordinator.handle(callback);

      expect(exchanges, 1);
      await completed;
      await coordinator.dispose();
    },
  );

  test('classifies cancelled and stale PKCE callbacks for friendly UI', () {
    expect(
      classifyAuthCallbackFailure(
        code: 'access_denied',
        message: 'The user cancelled',
      ),
      AuthCallbackEventKind.cancelled,
    );
    expect(
      classifyAuthCallbackFailure(
        code: 'flow_state_not_found',
        message: 'Code verifier could not be found in local storage.',
      ),
      AuthCallbackEventKind.expired,
    );
    expect(
      classifyAuthCallbackFailure(
        code: 'server_error',
        message: 'Provider rejected the request',
      ),
      AuthCallbackEventKind.rejected,
    );
  });
}
