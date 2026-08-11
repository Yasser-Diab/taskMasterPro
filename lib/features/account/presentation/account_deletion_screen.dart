import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../data/account_deletion_service.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  late final AccountDeletionService _service;
  AccountDeletionRequest? _request;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = AccountDeletionService(Supabase.instance.client);
    _refresh();
  }

  Future<void> _refresh() async {
    final request = await _service.current();
    if (mounted) {
      setState(() {
        _request = request;
        _loading = false;
      });
    }
  }

  Future<bool> _reauthenticate() async {
    try {
      await _service.requestRecentAuthentication();
      if (!mounted) return false;
      final code = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.text('account_confirm_identity')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.text('account_confirmation_code_sent')),
              const SizedBox(height: 14),
              TextField(
                controller: code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: context.l10n.text('account_confirmation_code'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, code.text),
              child: Text(context.l10n.text('account_confirm')),
            ),
          ],
        ),
      );
      code.dispose();
      if (result == null || result.trim().isEmpty) return false;
      await _service.confirmRecentAuthentication(result);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.text('account_identity_confirmation_failed'),
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _schedule() async {
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.text('account_schedule_deletion_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.text('account_schedule_deletion_warning')),
              const SizedBox(height: 14),
              Text(context.l10n.text('account_deletion_includes')),
              const SizedBox(height: 16),
              TextField(
                controller: typed,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('account_type_delete'),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('account_keep')),
            ),
            FilledButton(
              onPressed: typed.text.trim().toUpperCase() == 'DELETE'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text(context.l10n.text('account_continue')),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (confirmed != true || !await _reauthenticate()) return;
    setState(() => _loading = true);
    try {
      final request = await _service.schedule();
      if (mounted) setState(() => _request = request);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.text('account_schedule_deletion_failed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    if (!await _reauthenticate()) return;
    setState(() => _loading = true);
    try {
      await _service.cancel();
      if (!mounted) return;
      setState(() => _request = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('account_deletion_cancelled')),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('delete_account'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_request != null)
                  Card(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withValues(alpha: 0.62),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.format('account_deletion_countdown', {
                              'days': _request!.remainingDays,
                            }),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.text(
                              'account_deletion_signin_warning',
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton(
                                onPressed: _cancel,
                                child: Text(
                                  context.l10n.text('account_cancel_deletion'),
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  context.l10n.text('account_continue'),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Supabase.instance.client.auth.signOut(),
                                child: Text(context.l10n.text('sign_out')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.delete_forever_outlined,
                            size: 42,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            context.l10n.text('account_delete_heading'),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.text('account_delete_recovery_detail'),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                            onPressed: _schedule,
                            icon: const Icon(Icons.schedule),
                            label: Text(
                              context.l10n.text('account_schedule_deletion'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
