import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';

enum _AuthMode { signIn, createAccount, emailCode }

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
  final _code = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _acceptPolicies = false;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _message;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthException {
      setState(() {
        _message =
            'Unable to complete that request. Check the details and try again.';
      });
    } catch (_) {
      setState(() {
        _message =
            'Unable to connect right now. Your account session has not been removed.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            setState(
              () => _message = 'Please accept the policies to continue.',
            );
            return;
          }
          await _auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            emailRedirectTo: SupabaseConfig.authCallback,
            data: {'display_name': _displayName.text.trim()},
          );
          if (mounted) {
            setState(() {
              _message = context.l10n.text('generic_email_response');
              _mode = _AuthMode.emailCode;
            });
          }
        case _AuthMode.emailCode:
          if (_code.text.trim().isEmpty) {
            await _auth.signInWithOtp(
              email: _email.text.trim(),
              emailRedirectTo: SupabaseConfig.authCallback,
              shouldCreateUser: false,
            );
            if (mounted) {
              setState(
                () => _message = context.l10n.text('generic_email_response'),
              );
            }
          } else {
            await _auth.verifyOTP(
              email: _email.text.trim(),
              token: _code.text.trim(),
              type: OtpType.email,
            );
          }
      }
    });
  }

  Future<void> _google() {
    return _run(() async {
      await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.authCallback,
      );
    });
  }

  Future<void> _forgotPassword() {
    if (_email.text.trim().isEmpty) {
      setState(() => _message = 'Enter your email first.');
      return Future.value();
    }
    return _run(() async {
      await _auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: SupabaseConfig.authCallback,
      );
      if (mounted) {
        setState(() => _message = context.l10n.text('generic_email_response'));
      }
    });
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surface,
              colorScheme.primaryContainer.withValues(alpha: 0.36),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 820;
                    final intro = _AuthIntro(themeKey: widget.themeKey);
                    final form = _AuthFormCard(
                      formKey: _formKey,
                      mode: _mode,
                      busy: _busy,
                      message: _message,
                      displayName: _displayName,
                      email: _email,
                      password: _password,
                      confirmPassword: _confirmPassword,
                      code: _code,
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
                    );
                    if (!wide) {
                      return Column(
                        children: [intro, const SizedBox(height: 24), form],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: intro),
                        const SizedBox(width: 56),
                        SizedBox(width: 460, child: form),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrandLogo(themeKey: themeKey, height: 104),
        const SizedBox(height: 28),
        Text(
          'Plan less blindly.\nExecute with evidence.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Goals become roadmaps. Roadmaps become executable work. '
          'Actual effort improves tomorrow’s plan—online or offline.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FeaturePill(icon: Icons.offline_bolt, label: 'Local-first'),
            _FeaturePill(icon: Icons.devices, label: 'Multi-device'),
            _FeaturePill(icon: Icons.route, label: 'Roadmaps'),
            _FeaturePill(icon: Icons.insights, label: 'Explainable coaching'),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
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
    required this.displayName,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.code,
    required this.obscurePassword,
    required this.acceptPolicies,
    required this.onToggleObscure,
    required this.onAcceptPolicies,
    required this.onMode,
    required this.onSubmit,
    required this.onGoogle,
    required this.onForgot,
  });

  final GlobalKey<FormState> formKey;
  final _AuthMode mode;
  final bool busy;
  final String? message;
  final TextEditingController displayName;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirmPassword;
  final TextEditingController code;
  final bool obscurePassword;
  final bool acceptPolicies;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool?> onAcceptPolicies;
  final ValueChanged<_AuthMode> onMode;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onForgot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_AuthMode>(
                segments: [
                  ButtonSegment(
                    value: _AuthMode.signIn,
                    label: Text(l10n.text('sign_in')),
                  ),
                  ButtonSegment(
                    value: _AuthMode.createAccount,
                    label: Text(l10n.text('create_account')),
                  ),
                  const ButtonSegment(
                    value: _AuthMode.emailCode,
                    icon: Icon(Icons.password_rounded),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: busy
                    ? null
                    : (selection) => onMode(selection.first),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: busy ? null : onGoogle,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                label: Text(l10n.text('continue_google')),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              if (mode == _AuthMode.createAccount) ...[
                TextFormField(
                  controller: displayName,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.text('display_name'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Display name is required.'
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
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  if (!normalized.contains('@') || normalized.length < 5) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              if (mode != _AuthMode.emailCode) ...[
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
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: onToggleObscure,
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').length < 8) {
                      return 'Use at least eight characters.';
                    }
                    return null;
                  },
                ),
              ],
              if (mode == _AuthMode.createAccount) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPassword,
                  obscureText: obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: l10n.text('confirm_password'),
                    prefixIcon: const Icon(Icons.lock_reset),
                  ),
                  validator: (value) =>
                      value != password.text ? 'Passwords do not match.' : null,
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
              if (mode == _AuthMode.emailCode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: l10n.text('email_code'),
                    hintText: 'Leave empty to request a code',
                    prefixIcon: const Icon(Icons.pin_outlined),
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
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(message!, textAlign: TextAlign.center),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: busy ? null : onSubmit,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(switch (mode) {
                        _AuthMode.signIn => l10n.text('sign_in'),
                        _AuthMode.createAccount => l10n.text('create_account'),
                        _AuthMode.emailCode =>
                          code.text.trim().isEmpty
                              ? 'Send code'
                              : 'Verify code',
                      }),
              ),
              const SizedBox(height: 12),
              Text(
                'We use generic email responses to protect account privacy.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
