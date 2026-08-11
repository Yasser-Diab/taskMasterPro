import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the authenticated password-recovery session separate from a normal
/// sign-in. Supabase emits [AuthChangeEvent.passwordRecovery] after it has
/// securely exchanged the recovery callback for a short-lived session.
///
/// The controller is started directly after Supabase initialization so that a
/// callback received while the app is opening is not mistaken for an ordinary
/// authenticated session.
class PasswordRecoveryController extends ValueNotifier<bool> {
  PasswordRecoveryController() : super(false);

  StreamSubscription<AuthState>? _subscription;

  void start(GoTrueClient auth) {
    _subscription ??= auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        value = true;
      } else if (state.event == AuthChangeEvent.signedOut) {
        value = false;
      }
    });
  }

  void complete() {
    value = false;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

final passwordRecoveryController = PasswordRecoveryController();
