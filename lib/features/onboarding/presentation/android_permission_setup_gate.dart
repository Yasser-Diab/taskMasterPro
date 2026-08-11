import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../../health/presentation/health_connect_screen.dart';
import '../data/android_permission_setup_store.dart';

/// A per-device Android capability review shown after account onboarding and
/// before the home shell. It deliberately does not request permissions during
/// initialization: every platform prompt is tied to the matching user tap.
class AndroidPermissionSetupGate extends StatefulWidget {
  const AndroidPermissionSetupGate({
    required this.userId,
    required this.child,
    super.key,
  });

  final String userId;
  final Widget child;

  @override
  State<AndroidPermissionSetupGate> createState() =>
      _AndroidPermissionSetupGateState();
}

class _AndroidPermissionSetupGateState
    extends State<AndroidPermissionSetupGate> {
  AndroidPermissionSetupStore? _store;
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AndroidPermissionSetupGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId == widget.userId) return;
    setState(() {
      _store = null;
      _loadError = null;
      _loading = true;
      _alreadyReviewed = false;
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final userId = widget.userId;
    try {
      final store = await SharedPreferencesAndroidPermissionSetupStore.open();
      final record = await store.read(userId: userId);
      if (!mounted || userId != widget.userId) return;
      setState(() {
        _store = store;
        _loading = false;
        _loadError = null;
        if (record != null) _alreadyReviewed = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error;
        });
      }
    }
  }

  bool _alreadyReviewed = false;

  Future<void> _finish(
    AndroidPermissionSetupOutcome outcome,
    Map<String, String> capabilityStates,
  ) async {
    final store = _store;
    if (store == null) return;
    await store.write(
      userId: widget.userId,
      record: AndroidPermissionSetupRecord(
        outcome: outcome,
        reviewedAt: DateTime.now().toUtc(),
        capabilityStates: capabilityStates,
      ),
    );
    if (mounted) setState(() => _alreadyReviewed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return widget.child;
    }
    if (_loading) return const _PermissionSetupLoading();
    if (_loadError != null) {
      return _PermissionSetupStorageError(onRetry: _load);
    }
    if (_alreadyReviewed) return widget.child;
    return AndroidPermissionSetupScreen(onFinish: _finish);
  }
}

enum _AndroidPermissionCapability {
  notifications,
  activityRecognition,
  bluetoothConnect,
  usageAccess,
  exactAlarms,
  healthConnect,
}

enum _AndroidPermissionState {
  allowed,
  needsPermission,
  needsSettings,
  unavailable,
}

class AndroidPermissionSetupScreen extends ConsumerStatefulWidget {
  const AndroidPermissionSetupScreen({required this.onFinish, super.key});

  final Future<void> Function(
    AndroidPermissionSetupOutcome outcome,
    Map<String, String> capabilityStates,
  )
  onFinish;

  @override
  ConsumerState<AndroidPermissionSetupScreen> createState() =>
      _AndroidPermissionSetupScreenState();
}

class _AndroidPermissionSetupScreenState
    extends ConsumerState<AndroidPermissionSetupScreen>
    with WidgetsBindingObserver {
  Map<_AndroidPermissionCapability, _AndroidPermissionState> _states = const {};
  bool _checking = true;
  _AndroidPermissionCapability? _requesting;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) {
      unawaited(_refresh());
    }
  }

  Future<_AndroidPermissionState> _statusFor(Permission permission) async {
    try {
      final status = await permission.status;
      if (status.isGranted || status.isLimited) {
        return _AndroidPermissionState.allowed;
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        return _AndroidPermissionState.needsSettings;
      }
      return _AndroidPermissionState.needsPermission;
    } catch (_) {
      return _AndroidPermissionState.unavailable;
    }
  }

  Future<void> _refresh() async {
    if (_checking == false && _requesting != null) return;
    if (mounted) setState(() => _checking = true);
    final states = <_AndroidPermissionCapability, _AndroidPermissionState>{};
    try {
      final notifications = await localNotificationService
          .areAndroidNotificationsEnabled();
      if (notifications) {
        states[_AndroidPermissionCapability.notifications] =
            _AndroidPermissionState.allowed;
      } else {
        // Android can disable an app's notifications after the runtime grant.
        // In that case another runtime request cannot recover the capability;
        // show the app-settings route instead of a useless repeat prompt.
        final status = await Permission.notification.status;
        states[_AndroidPermissionCapability.notifications] =
            status.isGranted ||
                status.isPermanentlyDenied ||
                status.isRestricted
            ? _AndroidPermissionState.needsSettings
            : _AndroidPermissionState.needsPermission;
      }
      states[_AndroidPermissionCapability.activityRecognition] =
          await _statusFor(Permission.activityRecognition);
      states[_AndroidPermissionCapability.bluetoothConnect] = await _statusFor(
        Permission.bluetoothConnect,
      );
      final usageAccess = await ref
          .read(activityCaptureServiceProvider)
          .hasAndroidUsageAccess();
      states[_AndroidPermissionCapability.usageAccess] = usageAccess
          ? _AndroidPermissionState.allowed
          : _AndroidPermissionState.needsSettings;
      final exactAlarms = await localNotificationService
          .canScheduleExactAlarms();
      states[_AndroidPermissionCapability.exactAlarms] = exactAlarms
          ? _AndroidPermissionState.allowed
          : _AndroidPermissionState.needsSettings;
      // Health Connect itself is always opt-in from the Health screen. The
      // setup gate never invokes its permissions API simply by being opened.
      states[_AndroidPermissionCapability.healthConnect] =
          _AndroidPermissionState.needsPermission;
    } catch (_) {
      for (final capability in _AndroidPermissionCapability.values) {
        states.putIfAbsent(
          capability,
          () => _AndroidPermissionState.unavailable,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _states = Map.unmodifiable(states);
      _checking = false;
    });
  }

  Future<void> _request(_AndroidPermissionCapability capability) async {
    if (_requesting != null || _saving) return;
    setState(() => _requesting = capability);
    try {
      switch (capability) {
        case _AndroidPermissionCapability.notifications:
          final current = _states[capability];
          if (current == _AndroidPermissionState.needsSettings) {
            await localNotificationService.openAndroidAppNotificationSettings();
          } else {
            await localNotificationService.requestPermission();
          }
          break;
        case _AndroidPermissionCapability.activityRecognition:
          if (_states[capability] == _AndroidPermissionState.needsSettings) {
            await openAppSettings();
          } else {
            await Permission.activityRecognition.request();
          }
          break;
        case _AndroidPermissionCapability.bluetoothConnect:
          if (_states[capability] == _AndroidPermissionState.needsSettings) {
            await openAppSettings();
          } else {
            await Permission.bluetoothConnect.request();
          }
          break;
        case _AndroidPermissionCapability.usageAccess:
          await ref
              .read(activityCaptureServiceProvider)
              .openAndroidUsageAccess();
          break;
        case _AndroidPermissionCapability.exactAlarms:
          await localNotificationService.requestExactAlarmsPermission();
          break;
        case _AndroidPermissionCapability.healthConnect:
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const HealthConnectScreen(),
            ),
          );
          break;
      }
    } catch (_) {
      // The current state remains truthful after the refresh below. Android
      // settings may be unavailable on a vendor build without breaking setup.
    } finally {
      if (mounted) setState(() => _requesting = null);
    }
    await _refresh();
  }

  Future<void> _finish(AndroidPermissionSetupOutcome outcome) async {
    if (_checking || _requesting != null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onFinish(
        outcome,
        Map.unmodifiable({
          for (final entry in _states.entries) entry.key.name: entry.value.name,
        }),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _stateLabel(_AndroidPermissionState state) => switch (state) {
    _AndroidPermissionState.allowed => context.l10n.text(
      'permission_setup_allowed',
    ),
    _AndroidPermissionState.needsPermission => context.l10n.text(
      'permission_setup_needs_permission',
    ),
    _AndroidPermissionState.needsSettings => context.l10n.text(
      'permission_setup_needs_settings',
    ),
    _AndroidPermissionState.unavailable => context.l10n.text(
      'permission_setup_unavailable',
    ),
  };

  String _actionLabel(_AndroidPermissionCapability capability) {
    final state = _states[capability] ?? _AndroidPermissionState.unavailable;
    if (state == _AndroidPermissionState.unavailable) {
      return context.l10n.text('permission_setup_unavailable');
    }
    return switch (capability) {
      _AndroidPermissionCapability.notifications ||
      _AndroidPermissionCapability.activityRecognition ||
      _AndroidPermissionCapability.bluetoothConnect =>
        state == _AndroidPermissionState.needsSettings
            ? context.l10n.text('permission_setup_open_app_settings')
            : context.l10n.text('permission_setup_allow'),
      _AndroidPermissionCapability.usageAccess => context.l10n.text(
        'permission_setup_open_usage_settings',
      ),
      _AndroidPermissionCapability.exactAlarms => context.l10n.text(
        'permission_setup_open_exact_alarm_settings',
      ),
      _AndroidPermissionCapability.healthConnect => context.l10n.text(
        'permission_setup_set_up_health',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth < 420 ? 16 : 24,
                  vertical: 24,
                ),
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.text('permission_setup_title'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.text('permission_setup_subtitle')),
                  const SizedBox(height: 10),
                  Text(
                    l10n.text('permission_setup_privacy'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  for (final capability in _AndroidPermissionCapability.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PermissionCapabilityCard(
                        title: l10n.text(_titleKey(capability)),
                        detail: l10n.text(_detailKey(capability)),
                        icon: _iconFor(capability),
                        state: _checking
                            ? null
                            : _states[capability] ??
                                  _AndroidPermissionState.unavailable,
                        stateLabel: _checking
                            ? l10n.text('permission_setup_checking')
                            : _stateLabel(
                                _states[capability] ??
                                    _AndroidPermissionState.unavailable,
                              ),
                        actionLabel: _actionLabel(capability),
                        actionBusy: _requesting == capability,
                        actionEnabled:
                            !_checking &&
                            _requesting == null &&
                            !_saving &&
                            (_states[capability] ??
                                    _AndroidPermissionState.unavailable) !=
                                _AndroidPermissionState.allowed &&
                            (_states[capability] ??
                                    _AndroidPermissionState.unavailable) !=
                                _AndroidPermissionState.unavailable,
                        onAction: () => _request(capability),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.text('permission_setup_revisit'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _checking || _saving || _requesting != null
                        ? null
                        : () =>
                              _finish(AndroidPermissionSetupOutcome.completed),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.text('permission_setup_continue')),
                  ),
                  TextButton(
                    onPressed: _checking || _saving || _requesting != null
                        ? null
                        : () => _finish(AndroidPermissionSetupOutcome.skipped),
                    child: Text(l10n.text('permission_setup_skip')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _titleKey(
  _AndroidPermissionCapability capability,
) => switch (capability) {
  _AndroidPermissionCapability.notifications =>
    'permission_setup_notifications_title',
  _AndroidPermissionCapability.activityRecognition =>
    'permission_setup_activity_title',
  _AndroidPermissionCapability.bluetoothConnect =>
    'permission_setup_bluetooth_title',
  _AndroidPermissionCapability.usageAccess => 'permission_setup_usage_title',
  _AndroidPermissionCapability.exactAlarms =>
    'permission_setup_exact_alarm_title',
  _AndroidPermissionCapability.healthConnect => 'permission_setup_health_title',
};

String _detailKey(_AndroidPermissionCapability capability) =>
    switch (capability) {
      _AndroidPermissionCapability.notifications =>
        'permission_setup_notifications_detail',
      _AndroidPermissionCapability.activityRecognition =>
        'permission_setup_activity_detail',
      _AndroidPermissionCapability.bluetoothConnect =>
        'permission_setup_bluetooth_detail',
      _AndroidPermissionCapability.usageAccess =>
        'permission_setup_usage_detail',
      _AndroidPermissionCapability.exactAlarms =>
        'permission_setup_exact_alarm_detail',
      _AndroidPermissionCapability.healthConnect =>
        'permission_setup_health_detail',
    };

IconData _iconFor(_AndroidPermissionCapability capability) =>
    switch (capability) {
      _AndroidPermissionCapability.notifications =>
        Icons.notifications_outlined,
      _AndroidPermissionCapability.activityRecognition => Icons.directions_walk,
      _AndroidPermissionCapability.bluetoothConnect => Icons.watch_outlined,
      _AndroidPermissionCapability.usageAccess => Icons.timeline_outlined,
      _AndroidPermissionCapability.exactAlarms => Icons.alarm_outlined,
      _AndroidPermissionCapability.healthConnect =>
        Icons.health_and_safety_outlined,
    };

class _PermissionCapabilityCard extends StatelessWidget {
  const _PermissionCapabilityCard({
    required this.title,
    required this.detail,
    required this.icon,
    required this.state,
    required this.stateLabel,
    required this.actionLabel,
    required this.actionBusy,
    required this.actionEnabled,
    required this.onAction,
  });

  final String title;
  final String detail;
  final IconData icon;
  final _AndroidPermissionState? state;
  final String stateLabel;
  final String actionLabel;
  final bool actionBusy;
  final bool actionEnabled;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _AndroidPermissionState.allowed => Colors.green,
      _AndroidPermissionState.needsPermission => Theme.of(
        context,
      ).colorScheme.primary,
      _AndroidPermissionState.needsSettings => Colors.orange,
      _AndroidPermissionState.unavailable => Theme.of(
        context,
      ).colorScheme.outline,
      null => Theme.of(context).colorScheme.outline,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stateLabel,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(detail),
            if (state != _AndroidPermissionState.allowed) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton(
                  onPressed: actionEnabled ? onAction : null,
                  child: actionBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(actionLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionSetupLoading extends StatelessWidget {
  const _PermissionSetupLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    ),
  );
}

class _PermissionSetupStorageError extends StatelessWidget {
  const _PermissionSetupStorageError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage_outlined, size: 42),
              const SizedBox(height: 16),
              Text(
                context.l10n.text('permission_setup_storage_error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => unawaited(onRetry()),
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.text('retry')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
