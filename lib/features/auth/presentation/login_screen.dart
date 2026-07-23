import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/config/supabase_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/platform/external_url_launcher.dart';
import '../../../core/theme/app_brand.dart';
import '../../../core/theme/app_theme.dart';

enum _AuthMode { signIn, createAccount }

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.supabaseService, super.key});

  final SupabaseService supabaseService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _privacyUrl =
      'https://yasser-diab.github.io/taskMasterPro/privacy-policy/';
  static const _termsUrl = 'https://yasser-diab.github.io/taskMasterPro/terms/';

  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _termsAccepted = false;
  bool _busy = false;
  bool _oauthWaiting = false;
  String? _status;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final config = services.config;
    final connected = widget.supabaseService.isInitialized;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButton<Locale>(
                              value: config.locale,
                              underline: const SizedBox.shrink(),
                              items: [
                                DropdownMenuItem(
                                  value: const Locale('en'),
                                  child: Text(context.text('english')),
                                ),
                                DropdownMenuItem(
                                  value: const Locale('ar'),
                                  child: Text(context.text('arabic')),
                                ),
                                DropdownMenuItem(
                                  value: const Locale('de'),
                                  child: Text(context.text('german')),
                                ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (locale) {
                                      if (locale == null) {
                                        return;
                                      }
                                      services.updateConfig(
                                        config.copyWith(locale: locale),
                                      );
                                    },
                            ),
                          ),
                          _ConnectionStatus(
                            connected: connected,
                            onRetry: _busy
                                ? null
                                : () => services.supabaseService.initialize(
                                    services.config,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Image.asset(
                        AppBrand.logoAssetForTheme(services.config.themeChoice),
                        height: 96,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 18),
                      SegmentedButton<_AuthMode>(
                        selected: {_mode},
                        onSelectionChanged: _busy
                            ? null
                            : (selection) {
                                setState(() {
                                  _mode = selection.first;
                                  _status = null;
                                  _oauthWaiting = false;
                                });
                              },
                        segments: [
                          ButtonSegment(
                            value: _AuthMode.signIn,
                            label: Text(context.text('signIn')),
                          ),
                          ButtonSegment(
                            value: _AuthMode.createAccount,
                            label: Text(context.text('createAccount')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _mode == _AuthMode.signIn
                            ? context.text('loginReady')
                            : context.text('createAccountHelp'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.appColors.mutedText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (_oauthWaiting) ...[
                        _OAuthWaitingPanel(
                          onOpenAgain: _busy ? null : _signInWithGoogle,
                          onCancel: _busy
                              ? null
                              : () {
                                  setState(() {
                                    _oauthWaiting = false;
                                    _status = null;
                                  });
                                },
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (_mode == _AuthMode.createAccount) ...[
                        TextField(
                          controller: _fullNameController,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: InputDecoration(
                            labelText: context.text('fullName'),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: context.text('email'),
                          prefixIcon: const Icon(Icons.mail_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: _mode == _AuthMode.signIn
                            ? TextInputAction.done
                            : TextInputAction.next,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) {
                          if (_mode == _AuthMode.signIn) {
                            _signIn();
                          }
                        },
                        onChanged: (_) {
                          if (_mode == _AuthMode.createAccount) {
                            setState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: context.text('password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? context.text('showPassword')
                                : context.text('hidePassword'),
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    );
                                  },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_mode == _AuthMode.createAccount) ...[
                        const SizedBox(height: 8),
                        _PasswordStrengthBar(
                          score: _passwordStrength(_passwordController.text),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onSubmitted: (_) => _createAccount(),
                          decoration: InputDecoration(
                            labelText: context.text('confirmPassword'),
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirmPassword
                                  ? context.text('showPassword')
                                  : context.text('hidePassword'),
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(
                                        () => _obscureConfirmPassword =
                                            !_obscureConfirmPassword,
                                      );
                                    },
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_mode == _AuthMode.signIn)
                        Row(
                          children: [
                            Checkbox(
                              value: config.rememberSession,
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      services.updateConfig(
                                        config.copyWith(
                                          rememberSession: value ?? true,
                                        ),
                                      );
                                    },
                            ),
                            Expanded(
                              child: Text(context.text('rememberSession')),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _forgotPassword,
                              child: Text(context.text('forgotPassword')),
                            ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _termsAccepted,
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      setState(
                                        () => _termsAccepted = value ?? false,
                                      );
                                    },
                              title: Text(context.text('acceptTerms')),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => ExternalUrlLauncher.open(
                                          _privacyUrl,
                                        ),
                                  child: Text(context.text('privacyPolicy')),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () =>
                                            ExternalUrlLauncher.open(_termsUrl),
                                  child: Text(context.text('termsOfService')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      if (_mode == _AuthMode.signIn)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _resendVerification(),
                            child: Text(context.text('resendVerification')),
                          ),
                        ),
                      if (_status != null ||
                          widget.supabaseService.statusMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _status ??
                                widget.supabaseService.statusMessage ??
                                context.text('connectionUnavailable'),
                            style: TextStyle(
                              color: widget.supabaseService.isInitialized
                                  ? context.appColors.mutedText
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy || !connected
                            ? null
                            : _mode == _AuthMode.signIn
                            ? _signIn
                            : _createAccount,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _mode == _AuthMode.signIn
                                    ? Icons.login_outlined
                                    : Icons.person_add_alt_outlined,
                              ),
                        label: Text(
                          _mode == _AuthMode.signIn
                              ? context.text('signIn')
                              : context.text('createAccount'),
                        ),
                      ),
                      if (_mode == _AuthMode.signIn) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy || !connected
                              ? null
                              : _signInWithGoogle,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: Text(context.text('continueWithGoogle')),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _mode = _mode == _AuthMode.signIn
                                      ? _AuthMode.createAccount
                                      : _AuthMode.signIn;
                                  _status = null;
                                  _oauthWaiting = false;
                                });
                              },
                        child: Text(
                          _mode == _AuthMode.signIn
                              ? context.text('createAccountLink')
                              : context.text('returnToSignIn'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final error = await widget.supabaseService.signInWithPassword(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = error;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final result = await widget.supabaseService.googleOAuthSignInUrl();
    if (!mounted) {
      return;
    }
    if (result.error != null || result.url == null) {
      setState(() {
        _busy = false;
        _oauthWaiting = false;
        _status = result.error;
      });
      return;
    }
    try {
      await ExternalUrlLauncher.open(result.url!);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _oauthWaiting = true;
        _status = context.text('authWaitingStatus');
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _oauthWaiting = false;
        _status = context.text('googleSignInOpenFailed');
      });
    }
  }

  Future<void> _createAccount() async {
    final validation = _validateSignup();
    if (validation != null) {
      setState(() => _status = validation);
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    final error = await widget.supabaseService.signUpWithPassword(
      fullName: _fullNameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      preferredLanguage: AppServices.of(context).config.locale.languageCode,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = error ?? context.text('verificationEmailSent');
      if (error == null) {
        _mode = _AuthMode.signIn;
      }
    });
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _status = context.text('enterEmailFirst'));
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    final error = await widget.supabaseService.resetPasswordForEmail(email);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = error ?? context.text('resetPasswordSent');
    });
  }

  Future<void> _resendVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _status = context.text('enterEmailFirst'));
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    final error = await widget.supabaseService.resendVerificationEmail(email);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = error ?? context.text('verificationEmailSent');
    });
  }

  String? _validateSignup() {
    if (_fullNameController.text.trim().isEmpty) {
      return context.text('fullNameRequired');
    }
    if (!_emailController.text.contains('@')) {
      return context.text('validEmailRequired');
    }
    if (_passwordController.text.length < 8) {
      return context.text('passwordTooShort');
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      return context.text('passwordsDoNotMatch');
    }
    if (!_termsAccepted) {
      return context.text('termsRequired');
    }
    return null;
  }

  int _passwordStrength(String password) {
    var score = 0;
    if (password.length >= 8) {
      score += 1;
    }
    if (RegExp('[A-Z]').hasMatch(password)) {
      score += 1;
    }
    if (RegExp('[0-9]').hasMatch(password)) {
      score += 1;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      score += 1;
    }
    return score;
  }
}

class _OAuthWaitingPanel extends StatelessWidget {
  const _OAuthWaitingPanel({required this.onOpenAgain, required this.onCancel});

  final VoidCallback? onOpenAgain;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.open_in_browser_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.text('authWaitingTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: context.text('close'),
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.text('authWaitingMessage')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenAgain,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: Text(context.text('openGoogleAgain')),
                ),
                TextButton(
                  onPressed: onCancel,
                  child: Text(context.text('cancel')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.connected, required this.onRetry});

  final bool connected;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return TextButton.icon(
      onPressed: connected ? null : onRetry,
      icon: Icon(
        connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        color: color,
      ),
      label: Text(
        connected
            ? context.text('serverConnected')
            : context.text('connectionUnavailableRetry'),
      ),
    );
  }
}

class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final value = (score / 4).clamp(0.0, 1.0);
    final color = switch (score) {
      0 || 1 => Theme.of(context).colorScheme.error,
      2 || 3 => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: value, color: color),
        const SizedBox(height: 4),
        Text(
          context.text('passwordStrength'),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
