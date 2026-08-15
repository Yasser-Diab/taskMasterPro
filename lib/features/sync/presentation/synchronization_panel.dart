import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_service.dart';

class SynchronizationPanel extends ConsumerStatefulWidget {
  const SynchronizationPanel({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SynchronizationPanel(),
    );
  }

  @override
  ConsumerState<SynchronizationPanel> createState() =>
      _SynchronizationPanelState();
}

class _SynchronizationPanelState extends ConsumerState<SynchronizationPanel> {
  late Future<SyncSnapshot> _snapshot;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _snapshot = ref
        .read(syncServiceProvider)
        .getSnapshot(checkRemoteDevices: false);
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final service = ref.read(syncServiceProvider);
    try {
      await service.synchronizeNow();
      final snapshot = await service.getSnapshot(checkRemoteDevices: false);
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

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 430;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: compact ? 20 : 24,
      ),
      child: SizedBox(
        width: 440,
        height: (viewport.height - (compact ? 40 : 48)).clamp(320.0, 560.0),
        child: FutureBuilder<SyncSnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    compact ? 16 : 24,
                    compact ? 12 : 20,
                    compact ? 6 : 12,
                    compact ? 8 : 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_rounded, size: 22),
                      SizedBox(width: compact ? 8 : 12),
                      Expanded(
                        child: Text(
                          context.l10n.text('synchronization'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.all(compact ? 16 : 24),
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
                                  : DateFormat.yMMMd(
                                      context.l10n.locale.toLanguageTag(),
                                    ).add_jm().format(
                                      data.lastSuccessfulSync!.toLocal(),
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
                          ],
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.all(compact ? 12 : 16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.l10n.text('close')),
                      ),
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
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 600;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: compact ? 16 : 24,
      ),
      child: SizedBox(
        width: 720,
        height: (viewport.height - (compact ? 32 : 48)).clamp(320.0, 760.0),
        child: FutureBuilder<SyncSnapshot>(
          future: _snapshot,
          builder: (context, asyncSnapshot) {
            final snapshot = asyncSnapshot.data;
            if (snapshot == null) {
              return Padding(
                padding: EdgeInsets.all(compact ? 24 : 48),
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
                  padding: EdgeInsetsDirectional.fromSTEB(
                    compact ? 16 : 24,
                    compact ? 12 : 20,
                    compact ? 6 : 12,
                    compact ? 8 : 12,
                  ),
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
                    padding: EdgeInsets.all(compact ? 16 : 24),
                    children: [
                      _DetailRow(
                        icon: Icons.schedule_outlined,
                        label: context.l10n.text('last_successful_sync'),
                        value: snapshot.lastSuccessfulSync == null
                            ? context.l10n.text('sync_not_completed_device')
                            : DateFormat.yMMMd(
                                context.l10n.locale.toLanguageTag(),
                              ).add_jm().format(
                                snapshot.lastSuccessfulSync!.toLocal(),
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
                  padding: EdgeInsets.all(compact ? 12 : 16),
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
      key: const ValueKey('synchronization-status-card'),
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
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 7 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: compact ? 22 : 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
