import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/config/supabase_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_brand.dart';
import '../../../core/theme/app_theme.dart';

class CreateNewPasswordScreen extends StatefulWidget {
  const CreateNewPasswordScreen({required this.supabaseService, super.key});

  final SupabaseService supabaseService;

  @override
  State<CreateNewPasswordScreen> createState() =>
      _CreateNewPasswordScreenState();
}

class _CreateNewPasswordScreenState extends State<CreateNewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        AppBrand.logoAssetForTheme(services.config.themeChoice),
                        height: 96,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        context.text('createNewPassword'),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.text('createNewPasswordHelp'),
                        style: TextStyle(color: context.appColors.mutedText),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: context.text('newPassword'),
                          prefixIcon: const Icon(Icons.lock_reset_outlined),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? context.text('showPassword')
                                : context.text('hidePassword'),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        onSubmitted: (_) => _updatePassword(),
                        decoration: InputDecoration(
                          labelText: context.text('confirmPassword'),
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _status!,
                          style: TextStyle(
                            color: _status == context.text('passwordUpdated')
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _updatePassword,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_outlined),
                        label: Text(context.text('updatePassword')),
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

  Future<void> _updatePassword() async {
    final password = _passwordController.text;
    final confirmation = _confirmController.text;
    if (password.length < 8) {
      setState(() => _status = context.text('passwordTooShort'));
      return;
    }
    if (password != confirmation) {
      setState(() => _status = context.text('passwordsDoNotMatch'));
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });
    final error = await widget.supabaseService.updatePassword(password);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _status = error ?? context.text('passwordUpdated');
    });
  }
}
