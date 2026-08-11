import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../sync/presentation/synchronization_panel.dart';
import '../../tasks/domain/browser_handoff.dart';
import '../data/vault_repository.dart';

Timer? _vaultClipboardClearTimer;

/// Copies a credential only briefly.  It never overwrites clipboard content
/// the user copied after it, and no cleartext is persisted by this helper.
Future<void> copyVaultCredentialToClipboard(String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  _vaultClipboardClearTimer?.cancel();
  _vaultClipboardClearTimer = Timer(const Duration(seconds: 45), () async {
    final current = await Clipboard.getData('text/plain');
    if (current?.text == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}

class PasswordVaultScreen extends ConsumerStatefulWidget {
  const PasswordVaultScreen({
    this.initialWebsite,
    this.openAddWhenUnlocked = false,
    this.autofillForWebsite,
    super.key,
  });

  final String? initialWebsite;
  final bool openAddWhenUnlocked;
  final String? autofillForWebsite;

  @override
  ConsumerState<PasswordVaultScreen> createState() =>
      _PasswordVaultScreenState();
}

class _PasswordVaultScreenState extends ConsumerState<PasswordVaultScreen>
    with WidgetsBindingObserver {
  late final VaultRepository _repository;
  SecretKey? _key;
  LocalEntityRecord? _vault;
  List<VaultItem> _items = const [];
  bool _loading = true;
  bool _hasDeviceKey = false;
  VaultPreferences _preferences = const VaultPreferences();
  String _query = '';
  Timer? _autoLock;
  bool _initialDraftOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository = VaultRepository(ref.read(entityRecordRepositoryProvider));
    unawaited(_load());
  }

  @override
  void dispose() {
    _autoLock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_preferences.lockOnBackground &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached ||
            state == AppLifecycleState.hidden)) {
      _lock();
    }
  }

  Future<void> _load() async {
    final vault = await _repository.currentVault();
    final hasDeviceKey = await _repository.hasRememberedKey();
    if (!mounted) return;
    setState(() {
      _vault = vault;
      _hasDeviceKey = hasDeviceKey;
      _preferences = vault == null
          ? const VaultPreferences()
          : _repository.preferences(vault);
      _loading = false;
    });
  }

  void _startAutoLock() {
    _autoLock?.cancel();
    _autoLock = Timer(Duration(minutes: _preferences.autoLockMinutes), _lock);
  }

  void _lock() {
    _autoLock?.cancel();
    if (!mounted) return;
    setState(() {
      _key = null;
      _items = const [];
    });
  }

  Future<void> _create() async {
    final result = await showDialog<_PasswordResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateVaultDialog(),
    );
    if (result == null) return;
    if (!mounted) return;
    final deviceAuthReason = context.l10n.text('vault_device_auth_reason');
    setState(() => _loading = true);
    try {
      final key = await _repository.createVault(password: result.password);
      var hasDeviceKey = false;
      if (result.remember) {
        hasDeviceKey = await _repository.rememberKey(
          key,
          localizedReason: deviceAuthReason,
        );
      } else {
        await _repository.clearRememberedKey();
      }
      final vault = await _repository.currentVault();
      if (!mounted) return;
      setState(() {
        _vault = vault;
        _key = key;
        _hasDeviceKey = hasDeviceKey;
        _preferences = vault == null
            ? const VaultPreferences()
            : _repository.preferences(vault);
        _items = const [];
      });
      _startAutoLock();
      if (result.remember && !hasDeviceKey) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.text('vault_device_auth_failed')),
          ),
        );
      }
      unawaited(ref.read(syncServiceProvider).drainOutbox());
      _openInitialDraftIfNeeded();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('vault_create_failed'))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unlock() async {
    final password = await _askPassword();
    if (password == null || _vault == null) return;
    setState(() => _loading = true);
    final key = await _repository.unlockWithPassword(_vault!, password);
    if (key == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('vault_wrong_password'))),
        );
        setState(() => _loading = false);
      }
      return;
    }
    await _finishUnlock(key);
  }

  Future<void> _unlockWithDevice() async {
    setState(() => _loading = true);
    try {
      final key = await _repository.unlockWithDevice(
        localizedReason: context.l10n.text('vault_device_auth_reason'),
      );
      if (key == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.text('vault_device_auth_failed')),
            ),
          );
        }
        return;
      }
      await _finishUnlock(key);
    } finally {
      if (mounted && _key == null) setState(() => _loading = false);
    }
  }

  Future<void> _finishUnlock(SecretKey key) async {
    final items = await _repository.decryptItems(key);
    if (!mounted) return;
    setState(() {
      _key = key;
      _items = items;
      _loading = false;
    });
    _startAutoLock();
    _openInitialDraftIfNeeded();
  }

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('vault_unlock_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: InputDecoration(
            labelText: context.l10n.text('vault_password'),
            prefixIcon: const Icon(Icons.password),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.l10n.text('vault_unlock')),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  void _openInitialDraftIfNeeded() {
    if (!widget.openAddWhenUnlocked || _initialDraftOpened || _key == null) {
      return;
    }
    _initialDraftOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_editItem(initialWebsite: widget.initialWebsite));
    });
  }

  Future<void> _editItem({VaultItem? item, String? initialWebsite}) async {
    final key = _key;
    final vault = _vault;
    if (key == null || vault == null) return;
    final draft = await showDialog<_VaultItemDraft>(
      context: context,
      builder: (_) =>
          _VaultItemDialog(item: item, initialWebsite: initialWebsite),
    );
    if (draft == null) return;
    await _repository.saveItem(
      vaultId: vault.id,
      key: key,
      existing: item?.record,
      name: draft.name,
      username: draft.username,
      password: draft.password,
      website: draft.website,
      notes: draft.notes,
    );
    await _refreshItems();
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  Future<void> _deleteItem(VaultItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('vault_delete_saved_title')),
        content: Text(
          context.l10n.format('vault_delete_saved_body', {'name': item.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteItem(item.record);
    await _refreshItems();
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  Future<void> _refreshItems() async {
    final key = _key;
    if (key == null) return;
    final items = await _repository.decryptItems(key);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('vault_title')),
        actions: [
          if (_key != null)
            IconButton(
              tooltip: context.l10n.text('vault_settings'),
              onPressed: _showSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vault == null
          ? _NotConfigured(onCreate: _create)
          : _key == null
          ? _Locked(
              onUnlock: _unlock,
              onDeviceUnlock: _hasDeviceKey ? _unlockWithDevice : null,
              onRecovery: () => _showRecovery(context),
            )
          : _available(),
      floatingActionButton: _key == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editItem(),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.text('vault_add_account')),
            ),
    );
  }

  Widget _available() {
    final query = _query.toLowerCase().trim();
    final filtered = _items
        .where(
          (item) =>
              (widget.autofillForWebsite == null ||
                  websiteMatchesForCredential(
                    savedWebsite: item.website,
                    pageUrl: widget.autofillForWebsite!,
                  )) &&
              (query.isEmpty ||
                  item.name.toLowerCase().contains(query) ||
                  item.username.toLowerCase().contains(query) ||
                  item.website.toLowerCase().contains(query)),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(syncServiceProvider).drainOutbox();
        await ref.read(syncServiceProvider).pullChanges();
        await _refreshItems();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.text('vault_protected_title'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(context.l10n.text('vault_protected_body')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (widget.autofillForWebsite != null) ...[
            Text(context.l10n.text('vault_select_autofill_account')),
            const SizedBox(height: 14),
          ],
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: context.l10n.text('vault_search'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 50),
              child: Center(
                child: Text(
                  context.l10n.text(
                    widget.autofillForWebsite == null
                        ? 'vault_empty'
                        : 'vault_no_matching_account',
                  ),
                ),
              ),
            )
          else
            for (final item in filtered)
              _VaultItemCard(
                item: item,
                onEdit: () => _editItem(item: item),
                onDelete: () => _deleteItem(item),
                onFill: widget.autofillForWebsite == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        VaultAutofillCredential(
                          username: item.username,
                          password: item.password,
                          website: item.website,
                        ),
                      ),
              ),
        ],
      ),
    );
  }

  Future<void> _showSettings() async {
    final sync = await ref.read(syncServiceProvider).getSnapshot();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              context.l10n.text('vault_settings'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: Text(context.l10n.text('vault_status')),
              subtitle: Text(context.l10n.text('vault_unlocked_device')),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text(context.l10n.text('last_successful_sync')),
              subtitle: Text(
                sync.lastSuccessfulSync?.toString() ??
                    context.l10n.text('sync_not_completed_device'),
              ),
              onTap: () {
                Navigator.pop(context);
                SynchronizationPanel.show(this.context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text(context.l10n.text('vault_trusted_devices')),
              subtitle: Text(
                context.l10n.format('registered_devices', {
                  'count': sync.otherDevices.length,
                }),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(context.l10n.text('vault_automatic_lock')),
              subtitle: Text(
                context.l10n.format('vault_automatic_lock_minutes', {
                  'minutes': _preferences.autoLockMinutes,
                }),
              ),
              onTap: () => _chooseAutoLock(context),
            ),
            SwitchListTile(
              value: _preferences.lockOnBackground,
              onChanged: (value) => _updatePreferences(
                VaultPreferences(
                  autoLockMinutes: _preferences.autoLockMinutes,
                  lockOnBackground: value,
                  credentialSavingEnabled: _preferences.credentialSavingEnabled,
                  autofillEnabled: _preferences.autofillEnabled,
                ),
              ),
              secondary: const Icon(Icons.phone_locked_outlined),
              title: Text(context.l10n.text('vault_lock_on_background')),
            ),
            if (Platform.isAndroid)
              SwitchListTile(
                value: _hasDeviceKey,
                onChanged: (value) async {
                  if (!value) {
                    await _repository.clearRememberedKey();
                    if (mounted) setState(() => _hasDeviceKey = false);
                  } else if (_key != null) {
                    final deviceAuthReason = context.l10n.text(
                      'vault_device_auth_reason',
                    );
                    final remembered = await _repository.rememberKey(
                      _key!,
                      localizedReason: deviceAuthReason,
                    );
                    if (!mounted || !context.mounted) return;
                    setState(() => _hasDeviceKey = remembered);
                    if (!remembered) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.text('vault_device_auth_failed'),
                          ),
                        ),
                      );
                    }
                  }
                },
                secondary: const Icon(Icons.fingerprint),
                title: Text(context.l10n.text('vault_use_device_auth')),
              ),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(context.l10n.text('vault_change_password')),
              onTap: () {
                Navigator.pop(context);
                _changePassword();
              },
            ),
            ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text(context.l10n.text('vault_recovery_options')),
              onTap: () => _showRecovery(context),
            ),
            SwitchListTile(
              value: _preferences.credentialSavingEnabled,
              onChanged: (value) => _updatePreferences(
                VaultPreferences(
                  autoLockMinutes: _preferences.autoLockMinutes,
                  lockOnBackground: _preferences.lockOnBackground,
                  credentialSavingEnabled: value,
                  autofillEnabled: _preferences.autofillEnabled,
                ),
              ),
              secondary: const Icon(Icons.save_outlined),
              title: Text(context.l10n.text('vault_credential_saving')),
              subtitle: Text(
                context.l10n.text('vault_credential_saving_detail'),
              ),
            ),
            SwitchListTile(
              value: _preferences.autofillEnabled,
              onChanged: (value) => _updatePreferences(
                VaultPreferences(
                  autoLockMinutes: _preferences.autoLockMinutes,
                  lockOnBackground: _preferences.lockOnBackground,
                  credentialSavingEnabled: _preferences.credentialSavingEnabled,
                  autofillEnabled: value,
                ),
              ),
              secondary: const Icon(Icons.auto_fix_high_outlined),
              title: Text(context.l10n.text('vault_autofill')),
              subtitle: Text(context.l10n.text('vault_autofill_detail')),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(context.l10n.text('vault_lock_now')),
              onTap: () {
                Navigator.pop(context);
                _lock();
              },
            ),
            ListTile(
              leading: const Icon(Icons.phonelink_erase_outlined),
              title: Text(context.l10n.text('vault_clear_local')),
              subtitle: Text(context.l10n.text('vault_clear_local_detail')),
              onTap: () async {
                await _repository.clearRememberedKey();
                if (mounted && context.mounted) {
                  setState(() => _hasDeviceKey = false);
                  Navigator.pop(context);
                  _lock();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseAutoLock(BuildContext sheetContext) async {
    final value = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.text('vault_automatic_lock')),
        children: [
          for (final minutes in const [1, 5, 15, 30])
            ListTile(
              leading: Icon(
                _preferences.autoLockMinutes == minutes
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: () => Navigator.pop(context, minutes),
              title: Text(
                context.l10n.format('vault_automatic_lock_minutes', {
                  'minutes': minutes,
                }),
              ),
            ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await _updatePreferences(
      VaultPreferences(
        autoLockMinutes: value,
        lockOnBackground: _preferences.lockOnBackground,
        credentialSavingEnabled: _preferences.credentialSavingEnabled,
        autofillEnabled: _preferences.autofillEnabled,
      ),
    );
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    _startAutoLock();
  }

  Future<void> _updatePreferences(VaultPreferences preferences) async {
    final vault = _vault;
    if (vault == null) return;
    final updated = await _repository.updatePreferences(vault, preferences);
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      if (updated != null) _vault = updated;
    });
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }

  Future<void> _changePassword() async {
    final vault = _vault;
    if (vault == null) return;
    final result = await showDialog<_PasswordChangeResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangeVaultPasswordDialog(),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      final shouldRememberOnDevice = _hasDeviceKey;
      final key = await _repository.changePassword(
        vault: vault,
        currentPassword: result.currentPassword,
        newPassword: result.newPassword,
      );
      if (!mounted) return;
      if (key == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('vault_wrong_password'))),
        );
        return;
      }
      final updatedVault = await _repository.currentVault();
      if (!mounted) return;
      final hasDeviceKey = shouldRememberOnDevice
          ? await _repository.rememberKey(
              key,
              localizedReason: context.l10n.text('vault_device_auth_reason'),
            )
          : false;
      if (!mounted) return;
      setState(() {
        _key = key;
        _vault = updatedVault;
        _hasDeviceKey = hasDeviceKey;
      });
      _startAutoLock();
      unawaited(ref.read(syncServiceProvider).drainOutbox());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('vault_password_changed'))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.text('vault_password_change_failed')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showRecovery(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('vault_recovery_options')),
        content: Text(context.l10n.text('vault_recovery_body')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('close')),
          ),
        ],
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _CenteredVaultState(
      icon: Icons.shield_outlined,
      title: context.l10n.text('vault_not_configured_title'),
      message: context.l10n.text('vault_not_configured_body'),
      actions: [
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_moderator_outlined),
          label: Text(context.l10n.text('vault_create')),
        ),
        TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.l10n.text('vault_learn_title')),
              content: Text(context.l10n.text('vault_learn_body')),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.text('got_it')),
                ),
              ],
            ),
          ),
          child: Text(context.l10n.text('learn_how')),
        ),
      ],
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({
    required this.onUnlock,
    required this.onDeviceUnlock,
    required this.onRecovery,
  });

  final VoidCallback onUnlock;
  final VoidCallback? onDeviceUnlock;
  final VoidCallback onRecovery;

  @override
  Widget build(BuildContext context) {
    return _CenteredVaultState(
      icon: Icons.lock_outline,
      title: context.l10n.text('vault_locked_title'),
      message: context.l10n.text('vault_locked_body'),
      actions: [
        FilledButton.icon(
          onPressed: onUnlock,
          icon: const Icon(Icons.lock_open),
          label: Text(context.l10n.text('vault_unlock')),
        ),
        if (onDeviceUnlock != null)
          OutlinedButton.icon(
            onPressed: onDeviceUnlock,
            icon: const Icon(Icons.fingerprint),
            label: Text(context.l10n.text('vault_use_device_auth')),
          ),
        TextButton(
          onPressed: onRecovery,
          child: Text(context.l10n.text('vault_open_recovery')),
        ),
      ],
    );
  }
}

class _CenteredVaultState extends StatelessWidget {
  const _CenteredVaultState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 22),
                  for (final action in actions) ...[
                    SizedBox(width: double.infinity, child: action),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultItemCard extends StatefulWidget {
  const _VaultItemCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    this.onFill,
  });

  final VaultItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onFill;

  @override
  State<_VaultItemCard> createState() => _VaultItemCardState();
}

class _VaultItemCardState extends State<_VaultItemCard> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.key_outlined)),
        title: Text(item.name),
        subtitle: Text(
          item.username.isEmpty ? item.website : item.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: item.conflictingCopyOf == null
            ? null
            : Tooltip(
                message: context.l10n.text('vault_conflict'),
                child: const Icon(Icons.warning_amber_rounded),
              ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          if (item.username.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.text('username')),
              subtitle: SelectableText(item.username),
              trailing: IconButton(
                tooltip: context.l10n.text('copy_username'),
                onPressed: () => copyVaultCredentialToClipboard(item.username),
                icon: const Icon(Icons.copy),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.text('password')),
            subtitle: Text(
              _showPassword
                  ? item.password
                  : '•' * item.password.length.clamp(8, 24),
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: context.l10n.text(
                    _showPassword ? 'hide_password' : 'show_password',
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.text('copy_password'),
                  onPressed: () =>
                      copyVaultCredentialToClipboard(item.password),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.onFill != null)
                FilledButton.icon(
                  onPressed: widget.onFill,
                  icon: const Icon(Icons.password),
                  label: Text(context.l10n.text('vault_fill_sign_in')),
                ),
              if (item.website.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(item.website);
                    if (uri != null) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(context.l10n.text('open_website')),
                ),
              OutlinedButton.icon(
                onPressed: widget.onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(context.l10n.text('edit')),
              ),
              TextButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline),
                label: Text(context.l10n.text('delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PasswordResult {
  const _PasswordResult(this.password, this.remember);

  final String password;
  final bool remember;
}

class _PasswordChangeResult {
  const _PasswordChangeResult(this.currentPassword, this.newPassword);

  final String currentPassword;
  final String newPassword;
}

class _ChangeVaultPasswordDialog extends StatefulWidget {
  const _ChangeVaultPasswordDialog();

  @override
  State<_ChangeVaultPasswordDialog> createState() =>
      _ChangeVaultPasswordDialogState();
}

class _ChangeVaultPasswordDialogState
    extends State<_ChangeVaultPasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_current.text.isEmpty || _next.text.length < 10) {
      setState(() => _error = context.l10n.text('vault_password_length'));
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = context.l10n.text('vault_password_mismatch'));
      return;
    }
    Navigator.pop(context, _PasswordChangeResult(_current.text, _next.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.text('vault_change_password')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _current,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.text('vault_current_password'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _next,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.l10n.text('vault_new_password'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: context.l10n.text('confirm_vault_password'),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.text('vault_change_password')),
        ),
      ],
    );
  }
}

class _CreateVaultDialog extends StatefulWidget {
  const _CreateVaultDialog();

  @override
  State<_CreateVaultDialog> createState() => _CreateVaultDialogState();
}

class _CreateVaultDialogState extends State<_CreateVaultDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _remember = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    if (_first.text.length < 10) {
      setState(() => _error = context.l10n.text('vault_password_length'));
      return;
    }
    if (_first.text != _second.text) {
      setState(() => _error = context.l10n.text('vault_password_mismatch'));
      return;
    }
    Navigator.pop(context, _PasswordResult(_first.text, _remember));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.text('vault_create_title')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.text('vault_create_body')),
            const SizedBox(height: 14),
            TextField(
              controller: _first,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.l10n.text('vault_password'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _second,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: context.l10n.text('confirm_vault_password'),
                errorText: _error,
              ),
            ),
            if (Platform.isAndroid)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _remember,
                onChanged: (value) =>
                    setState(() => _remember = value ?? false),
                title: Text(context.l10n.text('vault_allow_device_auth')),
                subtitle: Text(context.l10n.text('vault_device_key_detail')),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.text('vault_create_action')),
        ),
      ],
    );
  }
}

class _VaultItemDraft {
  const _VaultItemDraft({
    required this.name,
    required this.username,
    required this.password,
    required this.website,
    required this.notes,
  });

  final String name;
  final String username;
  final String password;
  final String website;
  final String notes;
}

class _VaultItemDialog extends StatefulWidget {
  const _VaultItemDialog({this.item, this.initialWebsite});

  final VaultItem? item;
  final String? initialWebsite;

  @override
  State<_VaultItemDialog> createState() => _VaultItemDialogState();
}

class _VaultItemDialogState extends State<_VaultItemDialog> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _website;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item?.name);
    _username = TextEditingController(text: widget.item?.username);
    _password = TextEditingController(text: widget.item?.password);
    _website = TextEditingController(
      text: widget.item?.website ?? widget.initialWebsite,
    );
    _notes = TextEditingController(text: widget.item?.notes);
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _website.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty || _password.text.isEmpty) return;
    var website = _website.text.trim();
    if (website.isNotEmpty && !website.contains('://')) {
      website = 'https://$website';
    }
    Navigator.pop(
      context,
      _VaultItemDraft(
        name: _name.text,
        username: _username.text,
        password: _password.text,
        website: website,
        notes: _notes.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        context.l10n.text(
          widget.item == null ? 'vault_add_saved' : 'vault_edit_account',
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('vault_account_name'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: context.l10n.text('username'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('password'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _website,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: context.l10n.text('website'),
                  hintText:
                      'https://example.org', // localization-audit: allow — URL example
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.text('private_notes'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(context.l10n.text('vault_save_account')),
        ),
      ],
    );
  }
}
