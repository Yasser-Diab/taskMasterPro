import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';

enum _AuthMode { signIn, createAccount }

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
  String? _message;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = _friendlyAuthMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'We could not connect just now. Your saved session and offline work are safe';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyAuthMessage(AuthException error) {
    if (error.statusCode == '429') {
      return 'A link was sent recently. Give it a moment, then try again';
    }
    if (_mode == _AuthMode.signIn) {
      return 'Those sign-in details were not accepted. Check them or choose Google';
    }
    return 'We could not finish creating the account. Review the details and try again';
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
              _message =
                  'Accept the Terms of Service and Privacy Policy to continue';
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

  Future<void> _google() {
    return _run(() async {
      final opened = await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.authCallback,
        scopes: 'email profile',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const AuthException('Could not open the Google sign-in page');
      }
    });
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
          _message = 'A fresh confirmation link is on its way';
        });
      }
    });
  }

  Future<void> _forgotPassword() {
    if (_email.text.trim().isEmpty) {
      setState(() => _message = 'Enter your email to receive a reset link');
      return Future.value();
    }
    return _run(() async {
      await _auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: SupabaseConfig.authCallback,
      );
      if (mounted) {
        setState(() => _message = 'Check your email for a secure reset link');
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
        final tileWidth = compact ? (constraints.maxWidth - 12) / 2 : 244.0;
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
                  'PLAN  ·  EXECUTE  ·  LEARN',
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
              compact
                  ? 'Bring every goal into focus'
                  : 'Bring every goal\ninto focus',
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
                'Shape ambitious goals into clear roadmaps, move through each '
                'day with purpose, and let real effort guide what comes next — '
                'online or offline',
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
                  title: 'Roadmaps',
                  detail: 'A clear path from goal to action',
                ),
                _FeatureTile(
                  width: tileWidth,
                  icon: Icons.offline_bolt_rounded,
                  title: 'Local-first',
                  detail: 'Keep moving without a connection',
                ),
                _FeatureTile(
                  width: tileWidth,
                  icon: Icons.insights_rounded,
                  title: 'Clear coaching',
                  detail: 'Recommendations backed by evidence',
                ),
                _FeatureTile(
                  width: tileWidth,
                  icon: Icons.devices_rounded,
                  title: 'Your devices',
                  detail: 'Continue wherever the day takes you',
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
          mode == _AuthMode.signIn ? 'Welcome back' : 'Create your workspace',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          mode == _AuthMode.signIn
              ? 'Continue where your progress left off'
              : 'A calmer system for ambitious work starts here',
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
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 17),
          child: Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or use email'),
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
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? 'Add the name you would like to see'
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
              return 'Enter a valid email address';
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
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (value) =>
              (value ?? '').length < 8 ? 'Use at least eight characters' : null,
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
            validator: (value) =>
                value != password.text ? 'Passwords do not match' : null,
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
          'Private by design · ordinary network problems never sign you out',
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
          'One click and you are in',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a confirmation link to',
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
          'Open the message on this device and choose Confirm email address. '
          'TaskMaster Pro will reopen and finish sign-in automatically',
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
          label: const Text('Resend confirmation link'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onBackToSignIn,
          child: const Text('Return to sign in'),
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
