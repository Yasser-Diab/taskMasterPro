import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';
import '../data/google_oauth_launcher.dart';
import '../data/auth_callback_service.dart';

enum _AuthMode { signIn, createAccount }

@visibleForTesting
String authFailureMessageKey({
  required bool signingIn,
  required String? statusCode,
  required String? code,
}) {
  if (statusCode == '429') return 'auth_link_recently_sent';
  if (signingIn) return 'auth_signin_rejected';
  return switch (code) {
    'email_address_invalid' ||
    'email_address_not_authorized' => 'auth_signup_email_invalid',
    'weak_password' => 'auth_signup_password_weak',
    'user_already_exists' || 'email_exists' => 'auth_signup_account_exists',
    'signup_disabled' => 'auth_signup_unavailable',
    _ => 'auth_signup_failed',
  };
}

@visibleForTesting
String authCallbackMessageKey(AuthCallbackEventKind kind) => switch (kind) {
  AuthCallbackEventKind.completed => 'auth_google_completing',
  AuthCallbackEventKind.cancelled => 'auth_google_cancelled',
  AuthCallbackEventKind.expired => 'auth_google_expired',
  AuthCallbackEventKind.rejected => 'auth_google_rejected',
  AuthCallbackEventKind.connectionFailed => 'auth_google_connection_failed',
};

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.themeKey, super.key});

  final TaskMasterThemeKey themeKey;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _awaitingConfirmation = false;
  bool _acceptPolicies = false;
  bool _obscurePassword = true;
  bool _busy = false;
  bool _googlePending = false;
  String? _message;
  Timer? _googleTimeout;
  StreamSubscription<AuthCallbackEvent>? _callbackSubscription;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void initState() {
    super.initState();
    _callbackSubscription = AuthCallbackService.instance.events.listen(
      _onAuthCallback,
    );
    final latest = AuthCallbackService.instance.latestEvent;
    if (latest != null &&
        DateTime.now().difference(latest.occurredAt) <
            const Duration(seconds: 15)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onAuthCallback(latest);
      });
    }
  }

  @override
  void dispose() {
    _googleTimeout?.cancel();
    unawaited(_callbackSubscription?.cancel());
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _onAuthCallback(AuthCallbackEvent event) {
    if (!mounted) return;
    _googleTimeout?.cancel();
    setState(() {
      _message = context.l10n.text(authCallbackMessageKey(event.kind));
      if (event.kind == AuthCallbackEventKind.completed) {
        _busy = true;
      } else {
        _busy = false;
        _googlePending = false;
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = _friendlyAuthMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = context.l10n.text('auth_connection_failed');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthMessage(AuthException error) {
    return context.l10n.text(
      authFailureMessageKey(
        signingIn: _mode == _AuthMode.signIn,
        statusCode: error.statusCode,
        code: error.code,
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(() async {
      switch (_mode) {
        case _AuthMode.signIn:
          await _auth.signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
        case _AuthMode.createAccount:
          if (!_acceptPolicies) {
            setState(() {
              _message = context.l10n.text('auth_accept_policies_required');
            });
            return;
          }
          final response = await _auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            emailRedirectTo: SupabaseConfig.authCallback,
            data: {'display_name': _displayName.text.trim()},
          );
          if (mounted && response.session == null) {
            setState(() => _awaitingConfirmation = true);
          }
      }
    });
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _googlePending = true;
      _message = null;
    });
    try {
      // Obtain the PKCE URL through GoTrue, then launch it ourselves. The
      // Supabase Flutter convenience helper unconditionally sends Google on
      // Android to a full external browser, which can leave a browser surface
      // visible after the app-link callback has already signed the user in.
      final response = await _auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: SupabaseConfig.authCallback,
        scopes: 'email profile',
      );
      final opened = await launchGoogleOAuthUrl(Uri.parse(response.url));
      if (!opened) {
        throw const AuthException('Could not open the Google sign-in page');
      }
      if (!mounted) return;
      setState(() {
        _message = context.l10n.text('auth_google_browser_opened');
      });
      _googleTimeout?.cancel();
      _googleTimeout = Timer(const Duration(minutes: 2), () {
        if (!mounted || !_googlePending) return;
        setState(() {
          _busy = false;
          _googlePending = false;
          _message = context.l10n.text('auth_google_wait_timeout');
        });
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _googlePending = false;
        _message = _friendlyAuthMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _googlePending = false;
        _message = context.l10n.text('auth_connection_failed');
      });
    }
  }

  Future<void> _resendConfirmation() {
    return _run(() async {
      await _auth.resend(
        type: OtpType.signup,
        email: _email.text.trim(),
        emailRedirectTo: SupabaseConfig.authCallback,
      );
      if (mounted) {
        setState(() {
          _message = context.l10n.text('auth_confirmation_resent');
        });
      }
    });
  }

  Future<void> _forgotPassword() {
    if (_email.text.trim().isEmpty) {
      setState(() => _message = context.l10n.text('auth_enter_email_reset'));
      return Future.value();
    }
    return _run(() async {
      await _auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: SupabaseConfig.authCallback,
      );
      if (mounted) {
        setState(() => _message = context.l10n.text('auth_reset_link_sent'));
      }
    });
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _awaitingConfirmation = false;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.72, -0.55),
            radius: 1.35,
            colors: [
              colors.primary.withValues(alpha: 0.2),
              colors.surface,
              colors.surface,
            ],
            stops: const [0, 0.58, 1],
          ),
        ),
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 840;
                    final intro = _AuthIntro(themeKey: widget.themeKey);
                    final form = _AuthFormCard(
                      formKey: _formKey,
                      mode: _mode,
                      busy: _busy,
                      message: _message,
                      awaitingConfirmation: _awaitingConfirmation,
                      displayName: _displayName,
                      email: _email,
                      password: _password,
                      confirmPassword: _confirmPassword,
                      obscurePassword: _obscurePassword,
                      acceptPolicies: _acceptPolicies,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      onAcceptPolicies: (value) =>
                          setState(() => _acceptPolicies = value ?? false),
                      onMode: _setMode,
                      onSubmit: _submit,
                      onGoogle: _google,
                      onForgot: _forgotPassword,
                      onResend: _resendConfirmation,
                      onBackToSignIn: () => _setMode(_AuthMode.signIn),
                    );
                    if (!wide) {
                      return Column(
                        children: [intro, const SizedBox(height: 28), form],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: intro),
                        const SizedBox(width: 64),
                        SizedBox(width: 468, child: form),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({required this.themeKey});

  final TaskMasterThemeKey themeKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final singleColumnFeatures = constraints.maxWidth < 520;
        final tileWidth = singleColumnFeatures
            ? constraints.maxWidth
            : compact
            ? (constraints.maxWidth - 12) / 2
            : 244.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrandLogo(themeKey: themeKey, height: compact ? 76 : 108),
            SizedBox(height: compact ? 22 : 34),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Text(
                  context.l10n.text('auth_marketing_badge'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.25,
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 16 : 20),
            Text(
              context.l10n.text(
                compact
                    ? 'auth_marketing_headline_compact'
                    : 'auth_marketing_headline',
              ),
              style:
                  (compact
                          ? theme.textTheme.displaySmall
                          : theme.textTheme.displayMedium)
                      ?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 0.98,
                        letterSpacing: compact ? -1.2 : -1.8,
                      ),
            ),
            SizedBox(height: compact ? 16 : 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 570),
              child: Text(
                context.l10n.text('auth_marketing_description'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
            ),
            SizedBox(height: compact ? 22 : 30),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _FeatureTile(
                  width: tileWidth,
                  icon: Icons.route_rounded,
                  title: context.l10n.text('roadmaps'),
                  detail: context.l10n.text('auth_feature_roadmaps'),
                ),
                _FeatureTile(
                  width: tileWidth,
                  icon: Icons.offline_bolt_rounded,
                  title: context.l10n.text('auth_feature_offline_title'),
                  detail: context.l10n.text('auth_feature_offline'),
                ),
                _FeatureTile(
                  width: tileWidth,
                  icon: Icons.insights_rounded,
                  title: context.l10n.text('auth_feature_coaching_title'),
                  detail: context.l10n.text('auth_feature_coaching'),
                ),
                _FeatureTile(
                  width: tileWidth,
                  icon: Icons.devices_rounded,
                  title: context.l10n.text('auth_feature_devices_title'),
                  detail: context.l10n.text('auth_feature_devices'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.width,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: colors.primary, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthFormCard extends StatelessWidget {
  const _AuthFormCard({
    required this.formKey,
    required this.mode,
    required this.busy,
    required this.message,
    required this.awaitingConfirmation,
    required this.displayName,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.obscurePassword,
    required this.acceptPolicies,
    required this.onToggleObscure,
    required this.onAcceptPolicies,
    required this.onMode,
    required this.onSubmit,
    required this.onGoogle,
    required this.onForgot,
    required this.onResend,
    required this.onBackToSignIn,
  });

  final GlobalKey<FormState> formKey;
  final _AuthMode mode;
  final bool busy;
  final bool awaitingConfirmation;
  final String? message;
  final TextEditingController displayName;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirmPassword;
  final bool obscurePassword;
  final bool acceptPolicies;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool?> onAcceptPolicies;
  final ValueChanged<_AuthMode> onMode;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onForgot;
  final VoidCallback onResend;
  final VoidCallback onBackToSignIn;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: awaitingConfirmation
            ? _ConfirmationPanel(
                email: email.text.trim(),
                busy: busy,
                message: message,
                onResend: onResend,
                onBackToSignIn: onBackToSignIn,
              )
            : Form(key: formKey, child: _buildForm(context)),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.text(
            mode == _AuthMode.signIn
                ? 'auth_welcome_back'
                : 'auth_create_workspace',
          ),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.text(
            mode == _AuthMode.signIn
                ? 'auth_continue_progress'
                : 'auth_workspace_description',
          ),
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        SegmentedButton<_AuthMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _AuthMode.signIn,
              label: Text(l10n.text('sign_in')),
            ),
            ButtonSegment(
              value: _AuthMode.createAccount,
              label: Text(l10n.text('create_account')),
            ),
          ],
          selected: {mode},
          onSelectionChanged: busy
              ? null
              : (selection) => onMode(selection.first),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: busy ? null : onGoogle,
          icon: const Text(
            'G',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          label: Text(l10n.text('continue_google')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 17),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(l10n.text('auth_or_email')),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),
        if (mode == _AuthMode.createAccount) ...[
          TextFormField(
            controller: displayName,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.text('display_name'),
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? l10n.text('auth_name_required')
                : null,
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: l10n.text('email'),
            prefixIcon: const Icon(Icons.alternate_email_rounded),
          ),
          validator: (value) {
            final normalized = value?.trim() ?? '';
            if (!normalized.contains('@') || normalized.length < 5) {
              return l10n.text('auth_email_invalid');
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: password,
          obscureText: obscurePassword,
          textInputAction: mode == _AuthMode.createAccount
              ? TextInputAction.next
              : TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: l10n.text('password'),
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              onPressed: onToggleObscure,
              tooltip: l10n.text(
                obscurePassword ? 'auth_show_password' : 'auth_hide_password',
              ),
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (value) => (value ?? '').length < 8
              ? l10n.text('auth_password_length')
              : null,
        ),
        if (mode == _AuthMode.createAccount) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: confirmPassword,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.text('confirm_password'),
              prefixIcon: const Icon(Icons.lock_reset_rounded),
            ),
            validator: (value) => value != password.text
                ? l10n.text('auth_passwords_mismatch')
                : null,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: acceptPolicies,
            onChanged: onAcceptPolicies,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              l10n.text('accept_terms'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        if (mode == _AuthMode.signIn)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: busy ? null : onForgot,
              child: Text(l10n.text('forgot_password')),
            ),
          ),
        if (message != null) ...[
          _MessageBanner(message: message!),
          const SizedBox(height: 16),
        ] else
          const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  mode == _AuthMode.signIn
                      ? l10n.text('sign_in')
                      : l10n.text('create_account'),
                ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.text('auth_privacy_note'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ConfirmationPanel extends StatelessWidget {
  const _ConfirmationPanel({
    required this.email,
    required this.busy,
    required this.message,
    required this.onResend,
    required this.onBackToSignIn,
  });

  final String email;
  final bool busy;
  final String? message;
  final VoidCallback onResend;
  final VoidCallback onBackToSignIn;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [colors.primary, colors.tertiary]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.mark_email_read_rounded, size: 34),
        ),
        const SizedBox(height: 22),
        Text(
          context.l10n.text('auth_confirmation_title'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          context.l10n.text('auth_confirmation_sent_to'),
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 5),
        SelectableText(
          email,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        Text(
          context.l10n.text('auth_confirmation_instructions'),
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
        ),
        if (message != null) ...[
          const SizedBox(height: 18),
          _MessageBanner(message: message!),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: busy ? null : onResend,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.text('auth_resend_confirmation')),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onBackToSignIn,
          child: Text(context.l10n.text('auth_return_signin')),
        ),
      ],
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
