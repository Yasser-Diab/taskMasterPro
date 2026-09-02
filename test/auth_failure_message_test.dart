import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/auth/data/auth_callback_service.dart';
import 'package:taskmaster_pro/features/auth/presentation/auth_screen.dart';

void main() {
  test('manual account creation explains actionable server rejections', () {
    expect(
      authFailureMessageKey(
        signingIn: false,
        statusCode: '400',
        code: 'email_address_invalid',
      ),
      'auth_signup_email_invalid',
    );
    expect(
      authFailureMessageKey(
        signingIn: false,
        statusCode: '422',
        code: 'weak_password',
      ),
      'auth_signup_password_weak',
    );
    expect(
      authFailureMessageKey(
        signingIn: false,
        statusCode: '422',
        code: 'user_already_exists',
      ),
      'auth_signup_account_exists',
    );
    expect(
      authFailureMessageKey(
        signingIn: false,
        statusCode: '400',
        code: 'signup_disabled',
      ),
      'auth_signup_unavailable',
    );
  });

  test('sign-in and rate-limit messages keep their existing behavior', () {
    expect(
      authFailureMessageKey(
        signingIn: true,
        statusCode: '400',
        code: 'invalid_credentials',
      ),
      'auth_signin_rejected',
    );
    expect(
      authFailureMessageKey(
        signingIn: false,
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      ),
      'auth_link_recently_sent',
    );
  });

  test('OAuth callback outcomes always map to friendly visible messages', () {
    expect(
      authCallbackMessageKey(AuthCallbackEventKind.cancelled),
      'auth_google_cancelled',
    );
    expect(
      authCallbackMessageKey(AuthCallbackEventKind.expired),
      'auth_google_expired',
    );
    expect(
      authCallbackMessageKey(AuthCallbackEventKind.connectionFailed),
      'auth_google_connection_failed',
    );
  });
}
