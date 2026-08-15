import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_service.dart';

/// Account access management lives here rather than inside synchronization.
///
/// Device discovery is intentionally demand-driven: opening or refreshing this
/// screen is the only normal-settings path that fetches the remote registry.
class ConnectedDevicesScreen extends ConsumerStatefulWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  ConsumerState<ConnectedDevicesScreen> createState() =>
      _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState
    extends ConsumerState<ConnectedDevicesScreen> {
  late Future<SyncSnapshot> _snapshot;
  String? _revokingDeviceId;

  @override
  void initState() {
    super.initState();
    _snapshot = _loadDevices();
  }

  Future<SyncSnapshot> _loadDevices() =>
      ref.read(syncServiceProvider).getSnapshot(checkRemoteDevices: true);

  Future<void> _refresh() async {
    setState(() => _snapshot = _loadDevices());
    try {
      await _snapshot;
    } catch (_) {
      // The FutureBuilder owns the localized retry state.
    }
  }

  Future<void> _revokeDevice(Map<String, dynamic> device) async {
    final targetId = device['id'] as String?;
    if (targetId == null || _revokingDeviceId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('sign_out_device_question')),
        content: Text(context.l10n.text('sign_out_device_explanation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.logout),
            label: Text(context.l10n.text('sign_out_device')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revokingDeviceId = targetId);
    try {
      await ref.read(syncServiceProvider).revokeOtherDevice(targetId);
      if (!mounted) return;
      setState(() => _snapshot = _loadDevices());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('device_signed_out'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('connected_devices_load_failed')),
        ),
      );
    } finally {
      if (mounted) setState(() => _revokingDeviceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('connected_devices')),
        actions: [
          IconButton(
            tooltip: context.l10n.text('refresh_connected_devices'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<SyncSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DevicesMessage(
              icon: Icons.cloud_off_outlined,
              title: context.l10n.text('connected_devices_load_failed'),
              detail: context.l10n.text('connected_devices_load_failed_detail'),
              actionLabel: context.l10n.text('retry'),
              onAction: _refresh,
            );
          }
          final data = snapshot.data;
          final devices = data?.otherDevices ?? const [];
          if (devices.isEmpty) {
            return _DevicesMessage(
              icon: Icons.devices_outlined,
              title: context.l10n.text('connected_devices_empty'),
              detail: context.l10n.text('connected_devices_empty_detail'),
              actionLabel: context.l10n.text('refresh_connected_devices'),
              onAction: _refresh,
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              key: const ValueKey('connected-devices-list'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _DevicesIntro(deviceCount: devices.length),
                const SizedBox(height: 14),
                for (var index = 0; index < devices.length; index++) ...[
                  _ConnectedDeviceCard(
                    device: devices[index],
                    isCurrent: devices[index]['id'] == data?.currentDeviceId,
                    busy: _revokingDeviceId == devices[index]['id'],
                    onRevoke: () => _revokeDevice(devices[index]),
                  ),
                  if (index != devices.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DevicesIntro extends StatelessWidget {
  const _DevicesIntro({required this.deviceCount});

  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.devices_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('connected_devices'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(context.l10n.text('connected_devices_description')),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.format('registered_devices', {
                      'count': deviceCount,
                    }),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  const _ConnectedDeviceCard({
    required this.device,
    required this.isCurrent,
    required this.busy,
    required this.onRevoke,
  });

  final Map<String, dynamic> device;
  final bool isCurrent;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final android = device['platform'] == 'android';
    final lastSeen = DateTime.tryParse(
      device['last_seen_at'] as String? ?? '',
    )?.toLocal();
    final platform = l10n.text(
      android ? 'device_platform_android' : 'device_platform_windows',
    );
    final version = l10n.format('version_label', {
      'version': device['app_version'] ?? '—',
    });
    final lastActive = lastSeen == null
        ? null
        : '${l10n.text('last_active')}: ${DateFormat.yMMMd(l10n.locale.toLanguageTag()).add_jm().format(lastSeen)}';
    return Card(
      key: ValueKey('connected-device-${device['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Icon(
                android
                    ? Icons.phone_android_outlined
                    : Icons.computer_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device['device_name'] as String? ??
                        l10n.text('taskmaster_device'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('$platform · $version'),
                      if (isCurrent)
                        Chip(
                          avatar: const Icon(Icons.check_circle, size: 16),
                          label: Text(l10n.text('this_device')),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.green.withValues(alpha: 0.16),
                        ),
                    ],
                  ),
                  if (lastActive != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      lastActive,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isCurrent)
              IconButton(
                tooltip: l10n.text('sign_out_device'),
                onPressed: busy ? null : onRevoke,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout_outlined),
              ),
          ],
        ),
      ),
    );
  }
}

class _DevicesMessage extends StatelessWidget {
  const _DevicesMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 52),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
