import 'dart:async';
import 'dart:collection';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';

enum AuthCallbackEventKind {
  completed,
  cancelled,
  expired,
  rejected,
  connectionFailed,
}

@immutable
class AuthCallbackEvent {
  AuthCallbackEvent(this.kind) : occurredAt = DateTime.now();

  final AuthCallbackEventKind kind;
  final DateTime occurredAt;
}

@visibleForTesting
AuthCallbackEventKind classifyAuthCallbackFailure({
  required String? code,
  required String message,
}) {
  final normalizedCode = code?.toLowerCase() ?? '';
  final normalizedMessage = message.toLowerCase();
  if (normalizedCode == 'access_denied' ||
      normalizedMessage.contains('access denied') ||
      normalizedMessage.contains('cancelled') ||
      normalizedMessage.contains('canceled')) {
    return AuthCallbackEventKind.cancelled;
  }
  if (normalizedCode == 'flow_state_not_found' ||
      normalizedCode == 'bad_oauth_state' ||
      normalizedCode == 'otp_expired' ||
      normalizedMessage.contains('code verifier') ||
      normalizedMessage.contains('no code detected') ||
      normalizedMessage.contains('pkce') ||
      normalizedMessage.contains('invalid grant') ||
      normalizedMessage.contains('expired')) {
    return AuthCallbackEventKind.expired;
  }
  return AuthCallbackEventKind.rejected;
}

/// Owns the complete OAuth and email-link callback exchange.
///
/// Supabase's default Flutter observer intentionally hides callback errors in
/// its logger. DayVector instead keeps a single explicit owner so callbacks
/// are exchanged once, repeated Windows protocol deliveries are harmless, and
/// the sign-in screen can explain a failed or expired browser attempt.
class AuthCallbackCoordinator {
  AuthCallbackCoordinator({
    required this.expectedCallback,
    required this.exchange,
  });

  final Uri expectedCallback;
  final Future<void> Function(Uri callback) exchange;
  final _events = StreamController<AuthCallbackEvent>.broadcast();
  final _inFlight = <String>{};
  final _handled = <String>{};
  final _handledOrder = ListQueue<String>();

  Stream<AuthCallbackEvent> get events => _events.stream;

  bool accepts(Uri callback) {
    if (callback.scheme.toLowerCase() !=
            expectedCallback.scheme.toLowerCase() ||
        callback.host.toLowerCase() != expectedCallback.host.toLowerCase()) {
      return false;
    }
    String normalizedPath(String value) => value == '/' ? '' : value;
    if (normalizedPath(callback.path) !=
        normalizedPath(expectedCallback.path)) {
      return false;
    }

    var fragmentParameters = const <String, String>{};
    try {
      fragmentParameters = Uri.splitQueryString(callback.fragment);
    } on FormatException {
      return false;
    }
    bool hasParameter(String key) =>
        callback.queryParameters.containsKey(key) ||
        fragmentParameters.containsKey(key);
    return const {
      'access_token',
      'code',
      'error',
      'error_code',
      'error_description',
    }.any(hasParameter);
  }

  Future<void> handle(Uri callback) async {
    if (!accepts(callback)) return;
    // This value can contain a short-lived authorization code, so it remains
    // private in memory and is never logged, persisted, or exposed in events.
    final callbackIdentity = callback.toString();
    if (_handled.contains(callbackIdentity) ||
        !_inFlight.add(callbackIdentity)) {
      return;
    }

    AuthCallbackEvent event;
    try {
      await exchange(callback);
      event = AuthCallbackEvent(AuthCallbackEventKind.completed);
    } on AuthException catch (error) {
      event = AuthCallbackEvent(
        classifyAuthCallbackFailure(code: error.code, message: error.message),
      );
    } catch (_) {
      event = AuthCallbackEvent(AuthCallbackEventKind.connectionFailed);
    } finally {
      _inFlight.remove(callbackIdentity);
      _rememberHandled(callbackIdentity);
    }
    if (!_events.isClosed) _events.add(event);
  }

  void reportLinkFailure() {
    if (!_events.isClosed) {
      _events.add(AuthCallbackEvent(AuthCallbackEventKind.connectionFailed));
    }
  }

  void _rememberHandled(String identity) {
    if (!_handled.add(identity)) return;
    _handledOrder.addLast(identity);
    while (_handledOrder.length > 8) {
      _handled.remove(_handledOrder.removeFirst());
    }
  }

  Future<void> dispose() => _events.close();
}

class AuthCallbackService {
  AuthCallbackService._();

  static final instance = AuthCallbackService._();

  AuthCallbackCoordinator? _coordinator;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<AuthCallbackEvent>? _eventSubscription;
  final _events = StreamController<AuthCallbackEvent>.broadcast();

  AuthCallbackEvent? latestEvent;

  Stream<AuthCallbackEvent> get events => _events.stream;

  void start(GoTrueClient auth) {
    if (_linkSubscription != null) return;
    final coordinator = AuthCallbackCoordinator(
      expectedCallback: Uri.parse(SupabaseConfig.authCallback),
      exchange: (callback) async {
        await auth.getSessionFromUrl(callback);
      },
    );
    _coordinator = coordinator;
    _eventSubscription = coordinator.events.listen((event) {
      latestEvent = event;
      _events.add(event);
    });
    _linkSubscription = AppLinks().uriLinkStream.listen(
      (callback) => unawaited(coordinator.handle(callback)),
      onError: (_, _) => coordinator.reportLinkFailure(),
    );
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    await _linkSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _coordinator?.dispose();
    _linkSubscription = null;
    _eventSubscription = null;
    _coordinator = null;
    latestEvent = null;
  }
}
