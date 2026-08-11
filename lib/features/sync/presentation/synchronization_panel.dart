import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_service.dart';

class SynchronizationPanel extends ConsumerStatefulWidget {
  const SynchronizationPanel({super.key, this.showDevices = false});

  final bool showDevices;

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SynchronizationPanel(),
    );
  }

  static Future<void> showConnectedDevices(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SynchronizationPanel(showDevices: true),
    );
  }

  @override
  ConsumerState<SynchronizationPanel> createState() =>
      _SynchronizationPanelState();
}

class _SynchronizationPanelState extends ConsumerState<SynchronizationPanel> {
  late Future<SyncSnapshot> _snapshot;
  bool _syncing = false;
  String? _revokingDeviceId;

  @override
  void initState() {
    super.initState();
    _snapshot = ref.read(syncServiceProvider).getSnapshot();
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final service = ref.read(syncServiceProvider);
    try {
      await service.synchronizeNow();
      final snapshot = await service.getSnapshot();
      if (!mounted) return;
      setState(() => _snapshot = Future.value(snapshot));
      final (message, actionRequired) = !snapshot.connectionAvailable
          ? (context.l10n.text('sync_offline_saved'), false)
          : snapshot.failedChanges > 0
          ? (
              snapshot.pendingChanges > 0
                  ? context.l10n.format('sync_most_completed', {
                      'count': snapshot.failedChanges,
                    })
                  : context.l10n.text('sync_failed_saved'),
              true,
            )
          : snapshot.pendingChanges > 0
          ? (
              context.l10n.format('sync_waiting_count', {
                'count': snapshot.pendingChanges,
              }),
              false,
            )
          : (context.l10n.text('sync_everything_up_to_date'), false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: actionRequired
              ? const Duration(seconds: 10)
              : const Duration(seconds: 4),
          action: SnackBarAction(
            label: context.l10n.text('close'),
            onPressed: messenger.hideCurrentSnackBar,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('sync_failed_saved'))),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
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
      final service = ref.read(syncServiceProvider);
      await service.revokeOtherDevice(targetId);
      final snapshot = await service.getSnapshot();
      if (!mounted) return;
      setState(() => _snapshot = Future.value(snapshot));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('device_signed_out'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('sync_failed_saved'))),
      );
    } finally {
      if (mounted) setState(() => _revokingDeviceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.showDevices ? 560 : 440,
          maxHeight: widget.showDevices ? 700 : 500,
        ),
        child: FutureBuilder<SyncSnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.text('synchronization'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.text('sync_close_panel'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: data == null
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            _StatusCard(snapshot: data),
                            const SizedBox(height: 16),
                            _DetailRow(
                              icon: Icons.schedule_outlined,
                              label: context.l10n.text('last_successful_sync'),
                              value: data.lastSuccessfulSync == null
                                  ? context.l10n.text(
                                      'sync_not_completed_device',
                                    )
                                  : DateFormat.yMMMd().add_jm().format(
                                      data.lastSuccessfulSync!,
                                    ),
                            ),
                            _DetailRow(
                              icon: data.connectionAvailable
                                  ? Icons.wifi
                                  : Icons.wifi_off,
                              label: context.l10n.text('sync_connection'),
                              value: data.connectionAvailable
                                  ? context.l10n.text('sync_connected')
                                  : context.l10n.text('sync_you_offline'),
                            ),
                            _DetailRow(
                              icon: Icons.pending_actions_outlined,
                              label: context.l10n.text('sync_changes_waiting'),
                              value: '${data.pendingChanges}',
                            ),
                            _DetailRow(
                              icon: Icons.error_outline,
                              label: context.l10n.text(
                                'sync_changes_attention',
                              ),
                              value: '${data.failedChanges}',
                            ),
                            if (widget.showDevices)
                              _DetailRow(
                                icon: Icons.devices_outlined,
                                label: context.l10n.text('sync_current_device'),
                                value: data.deviceName,
                              ),
                            if (widget.showDevices)
                              _DetailRow(
                                icon: Icons.account_circle_outlined,
                                label: context.l10n.text(
                                  'sync_connected_account',
                                ),
                                value:
                                    data.accountEmail ??
                                    context.l10n.text('signed_out'),
                              ),
                            if (widget.showDevices &&
                                data.otherDevices.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Text(
                                context.l10n.text('connected_devices'),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              for (final device in data.otherDevices)
                                _ConnectedDeviceTile(
                                  device: device,
                                  isCurrent:
                                      device['id'] == data.currentDeviceId,
                                  busy: _revokingDeviceId == device['id'],
                                  onRevoke: () => _revokeDevice(device),
                                ),
                            ],
                          ],
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.l10n.text('close')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _syncing ? null : _syncNow,
                        icon: _syncing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: Text(
                          context.l10n.text(
                            data?.failedChanges == null ||
                                    data!.failedChanges == 0
                                ? 'sync_now'
                                : 'retry',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class SynchronizationDiagnosticsPanel extends ConsumerStatefulWidget {
  const SynchronizationDiagnosticsPanel({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SynchronizationDiagnosticsPanel(),
    );
  }

  @override
  ConsumerState<SynchronizationDiagnosticsPanel> createState() =>
      _SynchronizationDiagnosticsPanelState();
}

class _SynchronizationDiagnosticsPanelState
    extends ConsumerState<SynchronizationDiagnosticsPanel> {
  late Future<SyncSnapshot> _snapshot;
  late Future<List<SyncConflictNotice>> _conflictNotices;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    final service = ref.read(syncServiceProvider);
    _snapshot = service.getSnapshot(checkRemoteDevices: false);
    _conflictNotices = service.getConflictNotices();
  }

  Future<void> _refresh() async {
    final service = ref.read(syncServiceProvider);
    final snapshot = await service.getSnapshot(checkRemoteDevices: false);
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
      _conflictNotices = service.getConflictNotices();
    });
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      final service = ref.read(syncServiceProvider);
      await service.synchronizeNow();
      await _refresh();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _resolveAutomatically() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await ref.read(syncServiceProvider).resolveConflictsAutomatically();
      await _refresh();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _clearResolved() async {
    await ref.read(syncServiceProvider).clearResolvedConflicts();
    await _refresh();
  }

  Future<bool> _confirmDiscard() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.text('sync_discard_local_question')),
            content: Text(context.l10n.text('sync_discard_local_explanation')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.text('sync_discard_local_change')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _reviewDifferences(SyncConflictNotice notice) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('sync_review_differences')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notice.subject,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.text('sync_server_version'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              notice.serverSummary ??
                  context.l10n.text('sync_server_version_available'),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.text('sync_this_device_version'),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(notice.localSummary),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('sync_decide_later')),
          ),
        ],
      ),
    );
  }

  Future<void> _keepServer(SyncConflictNotice notice) async {
    if (!await _confirmDiscard()) return;
    await ref.read(syncServiceProvider).keepServerVersion(notice.commandId);
    await _refresh();
  }

  Future<void> _discardLocal(SyncConflictNotice notice) async {
    if (!await _confirmDiscard()) return;
    await ref.read(syncServiceProvider).discardLocalChange(notice.commandId);
    await _refresh();
  }

  Future<void> _keepDevice(SyncConflictNotice notice) async {
    await ref.read(syncServiceProvider).keepDeviceVersion(notice.commandId);
    await _refresh();
  }

  String _diagnosticText(
    SyncSnapshot snapshot,
    List<SyncTrafficDiagnostic> traffic,
  ) {
    final connection = ref.read(syncServiceProvider).getConnectionDiagnostics();
    final buffer = StringBuffer()
      ..writeln('TaskMaster Pro synchronization diagnostics')
      ..writeln(
        'Last successful synchronization: '
        '${snapshot.lastSuccessfulSync?.toIso8601String() ?? 'none'}',
      )
      ..writeln('Realtime connection: ${snapshot.liveConnectionAvailable}')
      ..writeln(
        'Active Realtime connections: '
        '${connection.activeRealtimeConnections}',
      )
      ..writeln('Active account channels: ${connection.activeAccountChannels}')
      ..writeln(
        'Registered event handlers: ${connection.registeredEventHandlers}',
      )
      ..writeln(
        'Duplicate handlers detected: '
        '${connection.duplicateHandlersDetected}',
      )
      ..writeln('Pending commands: ${snapshot.pendingChanges}')
      ..writeln('Failed commands: ${snapshot.failedChanges}');
    if (snapshot.diagnosticProblems.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Command diagnostics:');
      for (final problem in snapshot.diagnosticProblems) {
        buffer.writeln(problem);
      }
    }
    if (traffic.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Traffic since account connection:');
      for (final row in traffic) {
        buffer.writeln(
          '${row.source}: requests=${row.requestCount}, '
          'downloaded=${row.downloadedBytes}, uploaded=${row.uploadedBytes}, '
          'realtime=${row.realtimeMessageCount}, '
          'repeated=${row.repeatedQueryCount}, '
          'largest=${row.largestPayloadBytes}, '
          'last=${row.lastSynchronization?.toIso8601String() ?? 'none'}',
        );
      }
    }
    return buffer.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: FutureBuilder<SyncSnapshot>(
          future: _snapshot,
          builder: (context, asyncSnapshot) {
            final snapshot = asyncSnapshot.data;
            if (snapshot == null) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final traffic = ref
                .read(syncServiceProvider)
                .getTrafficDiagnostics();
            final connection = ref
                .read(syncServiceProvider)
                .getConnectionDiagnostics();
            final text = _diagnosticText(snapshot, traffic);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.monitor_heart_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.text('sync_diagnostics'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _DetailRow(
                        icon: Icons.schedule_outlined,
                        label: context.l10n.text('last_successful_sync'),
                        value: snapshot.lastSuccessfulSync == null
                            ? context.l10n.text('sync_not_completed_device')
                            : DateFormat.yMMMd().add_jm().format(
                                snapshot.lastSuccessfulSync!,
                              ),
                      ),
                      _DetailRow(
                        icon: Icons.hub_outlined,
                        label: context.l10n.text('sync_realtime_state'),
                        value: snapshot.liveConnectionAvailable
                            ? context.l10n.text('sync_connected')
                            : context.l10n.text('sync_disconnected'),
                      ),
                      _DetailRow(
                        icon: Icons.cable_outlined,
                        label: context.l10n.text(
                          'sync_active_realtime_connections',
                        ),
                        value: '${connection.activeRealtimeConnections}',
                      ),
                      _DetailRow(
                        icon: Icons.account_tree_outlined,
                        label: context.l10n.text(
                          'sync_active_account_channels',
                        ),
                        value: '${connection.activeAccountChannels}',
                      ),
                      _DetailRow(
                        icon: Icons.hearing_outlined,
                        label: context.l10n.text(
                          'sync_registered_event_handlers',
                        ),
                        value: '${connection.registeredEventHandlers}',
                      ),
                      _DetailRow(
                        icon: Icons.filter_alt_off_outlined,
                        label: context.l10n.text(
                          'sync_duplicate_handlers_detected',
                        ),
                        value: '${connection.duplicateHandlersDetected}',
                      ),
                      _DetailRow(
                        icon: Icons.pending_actions_outlined,
                        label: context.l10n.text('sync_changes_waiting'),
                        value: '${snapshot.pendingChanges}',
                      ),
                      _DetailRow(
                        icon: Icons.error_outline,
                        label: context.l10n.text('sync_failed_commands'),
                        value: '${snapshot.failedChanges}',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.text('sync_conflicts_title'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          TextButton(
                            onPressed: _retrying ? null : _resolveAutomatically,
                            child: Text(
                              context.l10n.text('sync_resolve_automatically'),
                            ),
                          ),
                        ],
                      ),
                      FutureBuilder<List<SyncConflictNotice>>(
                        future: _conflictNotices,
                        builder: (context, conflictSnapshot) {
                          final notices = conflictSnapshot.data;
                          if (notices == null) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          if (notices.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                context.l10n.text('sync_no_conflicts'),
                              ),
                            );
                          }
                          return Column(
                            children: [
                              for (final notice in notices)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          notice.subject,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _conflictCategoryLabel(
                                            context,
                                            notice.category,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton(
                                              onPressed: () =>
                                                  _reviewDifferences(notice),
                                              child: Text(
                                                context.l10n.text(
                                                  'sync_review_differences',
                                                ),
                                              ),
                                            ),
                                            OutlinedButton(
                                              onPressed: () =>
                                                  _keepServer(notice),
                                              child: Text(
                                                context.l10n.text(
                                                  'sync_keep_server_version',
                                                ),
                                              ),
                                            ),
                                            if (notice.canKeepDeviceVersion)
                                              FilledButton.tonal(
                                                onPressed: () =>
                                                    _keepDevice(notice),
                                                child: Text(
                                                  context.l10n.text(
                                                    'sync_keep_device_version',
                                                  ),
                                                ),
                                              ),
                                            TextButton(
                                              onPressed: () =>
                                                  _discardLocal(notice),
                                              child: Text(
                                                context.l10n.text(
                                                  'sync_discard_local_change',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _clearResolved,
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: Text(
                            context.l10n.text('sync_clear_resolved_conflicts'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.text('sync_traffic_diagnostics'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (traffic.isEmpty)
                        Text(context.l10n.text('sync_no_traffic_yet'))
                      else
                        for (final row in traffic)
                          Card(
                            child: ListTile(
                              title: Text(row.source),
                              subtitle: Text(
                                context.l10n.format('sync_traffic_values', {
                                  'requests': row.requestCount,
                                  'downloaded': row.downloadedBytes,
                                  'uploaded': row.uploadedBytes,
                                  'realtime': row.realtimeMessageCount,
                                  'repeated': row.repeatedQueryCount,
                                  'largest': row.largestPayloadBytes,
                                }),
                              ),
                            ),
                          ),
                      if (snapshot.diagnosticProblems.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          snapshot.diagnosticProblems.join('\n'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.l10n.text('sync_diagnostics_copied'),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(context.l10n.text('sync_copy_diagnostics')),
                      ),
                      FilledButton.icon(
                        onPressed: _retrying ? null : _retry,
                        icon: _retrying
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          context.l10n.text('sync_retry_failed_changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _conflictCategoryLabel(
  BuildContext context,
  SyncConflictCategory category,
) {
  final key = switch (category) {
    SyncConflictCategory.alreadyApplied => 'sync_conflict_already_resolved',
    SyncConflictCategory.duplicate => 'sync_conflict_duplicate',
    SyncConflictCategory.superseded => 'sync_conflict_superseded',
    SyncConflictCategory.permanentFailure => 'sync_conflict_permanent_failure',
    SyncConflictCategory.revisionConflict => 'sync_conflict_revision',
    SyncConflictCategory.discardedByUser => 'sync_conflict_discarded',
    SyncConflictCategory.needsReview => 'sync_conflict_needs_review',
  };
  return context.l10n.text(key);
}

class _ConnectedDeviceTile extends StatelessWidget {
  const _ConnectedDeviceTile({
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
    final lastSeen = DateTime.tryParse(
      device['last_seen_at'] as String? ?? '',
    )?.toLocal();
    final platform = device['platform'] == 'android'
        ? l10n.text('device_platform_android')
        : l10n.text('device_platform_windows');
    final version = l10n.format('version_label', {
      'version': device['app_version'] ?? '—',
    });
    final lastActive = lastSeen == null
        ? null
        : '${l10n.text('last_active')}: ${DateFormat.yMMMd().add_jm().format(lastSeen)}';
    return Semantics(
      container: true,
      label: isCurrent
          ? '${device['device_name']}, ${l10n.text('this_device')}'
          : '${device['device_name']}, $platform',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 10,
        leading: Icon(
          device['platform'] == 'android'
              ? Icons.phone_android_outlined
              : Icons.computer_outlined,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                device['device_name'] as String? ??
                    l10n.text('taskmaster_device'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 8),
              Chip(
                avatar: const Icon(Icons.check_circle, size: 16),
                label: Text(l10n.text('this_device')),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.green.withValues(alpha: 0.16),
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text([platform, version, ?lastActive].join(' · ')),
        trailing: isCurrent
            ? null
            : IconButton(
                tooltip: l10n.text('sign_out_device'),
                onPressed: busy ? null : onRevoke,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
              ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.snapshot});

  final SyncSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message, color) = snapshot.isTruthfullySynced
        ? (
            Icons.cloud_done_outlined,
            context.l10n.text('sync_all_changes'),
            context.l10n.text('sync_last_just_now'),
            Colors.green,
          )
        : !snapshot.connectionAvailable
        ? (
            Icons.cloud_off_outlined,
            context.l10n.text('sync_you_offline'),
            context.l10n.text('sync_offline_reconnect'),
            Colors.blueGrey,
          )
        : snapshot.failedChanges > 0
        ? (
            Icons.sync_problem,
            context.l10n.text('sync_some_attention'),
            context.l10n.text('sync_auto_retry_message'),
            Theme.of(context).colorScheme.error,
          )
        : (
            Icons.sync,
            context.l10n.text('syncing_latest'),
            context.l10n.format('sync_waiting_count', {
              'count': snapshot.pendingChanges,
            }),
            Theme.of(context).colorScheme.primary,
          );
    return Card(
      color: color.withValues(alpha: 0.11),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
