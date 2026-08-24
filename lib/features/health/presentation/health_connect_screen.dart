import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/health_record_processing.dart';
import '../data/health_source_discovery.dart';

export '../data/health_record_processing.dart';

class HealthConnectScreen extends ConsumerStatefulWidget {
  const HealthConnectScreen({super.key});

  @override
  ConsumerState<HealthConnectScreen> createState() =>
      _HealthConnectScreenState();
}

class _HealthConnectScreenState extends ConsumerState<HealthConnectScreen> {
  static const _healthSourcesChannel = MethodChannel('taskmasterpro/ble');
  static const _platformCallTimeout = Duration(seconds: 10);
  static const _healthReadTimeout = Duration(seconds: 10);
  static const _healthRefreshDeadline = Duration(seconds: 30);
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.HEART_RATE,
    ...healthConnectSleepReadTypes,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
  ];

  final Health _health = Health();
  bool _checking = true;
  bool _available = false;
  bool _authorized = false;
  bool _loading = false;
  bool _pullRefreshing = false;
  String? _message;
  Map<String, Object?> _bluetoothState = const {};
  List<PairedHealthWearable> _pairedWearables = const [];
  bool _wearablesLoading = false;
  String? _wearablesMessage;
  final Set<HealthDataType> _unavailableTypes = {};
  Set<String> _providerSources = const {};
  Map<String, DateTime> _providerLastRecordAt = const {};
  bool _hasActualRecords = false;
  DateTime? _latestRecordAt;
  bool _readFailed = false;
  double? _profileHeightCm;
  HealthSummary _summary = const HealthSummary();
  List<_HealthDaySnapshot> _weeklySummaries = const [];
  Timer? _dayBoundaryTimer;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scheduleDayBoundaryReset();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _dayBoundaryTimer?.cancel();
    super.dispose();
  }

  void _scheduleDayBoundaryReset() {
    _dayBoundaryTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _dayBoundaryTimer = Timer(
      nextDay.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() {
          _summary = const HealthSummary();
          _weeklySummaries = const [];
        });
        if (_authorized) unawaited(_refresh());
        _scheduleDayBoundaryReset();
      },
    );
  }

  Future<void> _initialize() async {
    if (!Platform.isAndroid) {
      setState(() {
        _checking = false;
        _message = context.l10n.text('health_android_only');
      });
      return;
    }
    try {
      await _loadBluetoothState();
      unawaited(_loadPairedHealthWearables());
      await _health.configure().timeout(_platformCallTimeout);
      final available = await _health.isHealthConnectAvailable().timeout(
        _platformCallTimeout,
      );
      final permission = available
          ? await _health
                    .hasPermissions(
                      _types,
                      permissions: List.filled(
                        _types.length,
                        HealthDataAccess.READ,
                      ),
                    )
                    .timeout(_platformCallTimeout) ??
                false
          : false;
      if (!mounted) return;
      setState(() {
        _checking = false;
        _available = available;
        _authorized = permission;
      });
      if (permission) await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _readFailed = true;
        _message = context.l10n.text('health_check_failed');
      });
    }
  }

  Future<void> _loadBluetoothState() async {
    if (!Platform.isAndroid) return;
    try {
      final state = await _healthSourcesChannel
          .invokeMapMethod<String, Object?>('state')
          .timeout(_platformCallTimeout);
      if (!mounted || state == null) return;
      setState(() => _bluetoothState = Map<String, Object?>.from(state));
    } catch (_) {
      if (!mounted) return;
      setState(() => _bluetoothState = const {'supported': false});
    }
  }

  /// Reads Android's paired/connected device state only.  This deliberately
  /// does not run a BLE scan: nearby earbuds, vehicles, keyboards and random
  /// peripherals are not health sources.
  Future<void> _loadPairedHealthWearables({
    bool requestBluetoothPermission = false,
  }) async {
    setState(() {
      _wearablesLoading = true;
      _wearablesMessage = null;
    });
    try {
      if (requestBluetoothPermission) {
        final permission = await Permission.bluetoothConnect.request();
        if (!permission.isGranted) {
          throw StateError('bluetooth_permission');
        }
      }
      await _loadBluetoothState();
      if (_bluetoothState['permissionRequired'] == true) {
        throw StateError('bluetooth_permission');
      }
      if (_bluetoothState['enabled'] != true) {
        setState(
          () => _wearablesMessage = context.l10n.text(
            'health_wearables_bluetooth_disabled',
          ),
        );
        return;
      }
      final values = await _healthSourcesChannel
          .invokeListMethod<Object?>('pairedHealthDevices')
          .timeout(_platformCallTimeout);
      final discovered = PairedHealthWearable.fromPlatformValues(
        values ?? const <Object?>[],
      );
      final previousById = {
        for (final wearable in _pairedWearables) wearable.bridgeId: wearable,
      };
      final wearables = discovered
          .map((wearable) {
            final previous = previousById[wearable.bridgeId];
            if (!wearable.isConnected ||
                previous == null ||
                previous.capabilityState == 'inspecting') {
              return wearable;
            }
            return PairedHealthWearable(
              bridgeId: wearable.bridgeId,
              displayName: wearable.displayName,
              isConnected: true,
              capabilityState: previous.capabilityState,
              capabilities: previous.capabilities,
              inspectionError: previous.inspectionError,
              directReadings: previous.directReadings,
            );
          })
          .toList(growable: false);
      final connected = wearables
          .where((wearable) => wearable.isConnected)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _pairedWearables = wearables;
        _wearablesMessage = connected.isEmpty
            ? context.l10n.text('health_wearables_none_connected')
            : null;
      });
      unawaited(_inspectConnectedHealthWearables(connected));
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _wearablesMessage = context.l10n.text(
          error.code == 'bluetooth_disabled'
              ? 'health_wearables_bluetooth_disabled'
              : error.code == 'bluetooth_permission'
              ? 'health_wearables_permission_required'
              : 'health_wearables_refresh_failed',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _wearablesMessage = context.l10n.text(
          'health_wearables_permission_required',
        ),
      );
    } finally {
      if (mounted) setState(() => _wearablesLoading = false);
    }
  }

  Future<void> _inspectConnectedHealthWearables(
    List<PairedHealthWearable> wearables,
  ) async {
    for (final wearable in wearables) {
      if (!mounted) return;
      if (wearable.capabilityState == 'direct_supported' ||
          wearable.capabilityState == 'no_direct_health_service') {
        continue;
      }
      await _inspectPairedHealthWearable(wearable.bridgeId);
    }
  }

  Future<void> _refreshDashboard() async {
    if (mounted) setState(() => _pullRefreshing = true);
    try {
      final healthRefresh = _authorized ? _refresh() : Future<void>.value();
      final wearableRefresh = Platform.isAndroid
          ? _loadPairedHealthWearables()
          : Future<void>.value();
      await Future.wait([healthRefresh, wearableRefresh]);
    } finally {
      if (mounted) setState(() => _pullRefreshing = false);
    }
  }

  void _showDataReceivedNotice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.text('health_data_received_popup'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
    });
  }

  Future<void> _inspectPairedHealthWearable(String bridgeId) async {
    final index = _pairedWearables.indexWhere(
      (wearable) => wearable.bridgeId == bridgeId,
    );
    if (index < 0) return;
    setState(() {
      final updated = [..._pairedWearables];
      final wearable = updated[index];
      updated[index] = PairedHealthWearable(
        bridgeId: wearable.bridgeId,
        displayName: wearable.displayName,
        isConnected: wearable.isConnected,
        capabilityState: 'inspecting',
        capabilities: wearable.capabilities,
        directReadings: wearable.directReadings,
      );
      _pairedWearables = List.unmodifiable(updated);
    });
    try {
      final inspected = await _healthSourcesChannel
          .invokeMapMethod<String, Object?>('inspectPairedHealthDevice', {
            'address': bridgeId,
            'timeoutMillis': 12000,
          })
          .timeout(const Duration(seconds: 16));
      if (!mounted || inspected == null) return;
      final currentIndex = _pairedWearables.indexWhere(
        (wearable) => wearable.bridgeId == bridgeId,
      );
      if (currentIndex < 0) return;
      setState(() {
        final updated = [..._pairedWearables];
        updated[currentIndex] = updated[currentIndex]
            .copyWithPlatformInspection(Map<String, Object?>.from(inspected));
        _pairedWearables = List.unmodifiable(updated);
      });
    } on PlatformException {
      if (!mounted) return;
      final currentIndex = _pairedWearables.indexWhere(
        (wearable) => wearable.bridgeId == bridgeId,
      );
      if (currentIndex < 0) return;
      setState(() {
        final updated = [..._pairedWearables];
        final wearable = updated[currentIndex];
        updated[currentIndex] = PairedHealthWearable(
          bridgeId: wearable.bridgeId,
          displayName: wearable.displayName,
          isConnected: wearable.isConnected,
          capabilityState: 'unknown',
          capabilities: wearable.capabilities,
          inspectionError: 'inspection_failed',
          directReadings: wearable.directReadings,
        );
        _pairedWearables = List.unmodifiable(updated);
      });
    }
  }

  Future<void> _openBluetoothSettings() async {
    await _healthSourcesChannel
        .invokeMethod<void>('openSettings')
        .timeout(_platformCallTimeout);
    await _loadBluetoothState();
  }

  Future<void> _openHealthConnectSettings() async {
    try {
      await _healthSourcesChannel
          .invokeMethod<void>('openHealthConnectSettings')
          .timeout(_platformCallTimeout);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _readFailed = true;
        _message = context.l10n.text('health_check_failed');
      });
    }
  }

  Future<void> _connect() async {
    if (!_available) {
      await _health.installHealthConnect();
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
      _readFailed = false;
    });
    try {
      final activityPermission = await Permission.activityRecognition.request();
      if (!activityPermission.isGranted) {
        throw StateError('activity_permission_denied');
      }
      final granted = await _health.requestAuthorization(
        _types,
        permissions: List.filled(_types.length, HealthDataAccess.READ),
      );
      if (!mounted) return;
      setState(() => _authorized = granted);
      await ref
          .read(settingsRepositoryProvider)
          .updateHealthConnectEnabled(granted);
      if (granted) await _refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = context.l10n.text('health_permission_failed'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final refreshGeneration = ++_refreshGeneration;
    final deadline = Timer(_healthRefreshDeadline, () {
      if (!mounted || refreshGeneration != _refreshGeneration) return;
      _refreshGeneration++;
      setState(() {
        _loading = false;
        _readFailed = true;
        _message = context.l10n.text('health_operation_timed_out');
      });
    });
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final importedAt = DateTime.now().toUtc();
      final localNow = importedAt.toLocal();
      final firstLocalDay = DateTime(
        localNow.year,
        localNow.month,
        localNow.day,
      ).subtract(const Duration(days: 6));
      final start = firstLocalDay.toUtc();
      final end = importedAt;
      final refreshWindow = HealthInterval(start, end);
      final points = <HealthDataPoint>[];
      _unavailableTypes.clear();
      final typeReads = await Future.wait(
        _types.map((type) async {
          try {
            final values = await _health
                .getHealthDataFromTypes(
                  startTime: start,
                  endTime: end,
                  types: [type],
                )
                .timeout(_healthReadTimeout);
            return (type: type, points: values, failed: false);
          } catch (_) {
            return (
              type: type,
              points: const <HealthDataPoint>[],
              failed: true,
            );
          }
        }),
      );
      for (final read in typeReads) {
        points.addAll(read.points);
        if (read.failed) _unavailableTypes.add(read.type);
      }
      final normalizedPoints = normalizeHealthConnectSleepRecords(points);
      final reconciliation = HealthRecordReconciler.reconcile(normalizedPoints);
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      final profile = userId == null
          ? null
          : await ref.read(localProfileProvider(userId).future);
      final heightCm = profile?.heightCm;
      final dailySummaries = <HealthSummary>[];
      final summariesByDay = <String, HealthSummary>{};
      final canonicalStepsByDay = <String, int?>{};
      if (!_unavailableTypes.contains(HealthDataType.STEPS)) {
        final totals = await Future.wait(
          List.generate(7, (index) async {
            final dayStart = firstLocalDay.add(Duration(days: index));
            final rawDayEnd = dayStart.add(const Duration(days: 1));
            final dayEnd = rawDayEnd.isAfter(localNow) ? localNow : rawDayEnd;
            if (!dayStart.isBefore(dayEnd)) {
              return (day: healthLocalDayKey(dayStart), steps: null);
            }
            try {
              final steps = await _health
                  .getTotalStepsInInterval(dayStart, dayEnd)
                  .timeout(_healthReadTimeout);
              return (day: healthLocalDayKey(dayStart), steps: steps);
            } catch (_) {
              return (day: healthLocalDayKey(dayStart), steps: null);
            }
          }),
        );
        canonicalStepsByDay.addEntries(
          totals.map((total) => MapEntry(total.day, total.steps)),
        );
      }
      for (var index = 0; index < 7; index++) {
        final dayStart = firstLocalDay.add(Duration(days: index));
        final rawDayEnd = dayStart.add(const Duration(days: 1));
        final dayEnd = rawDayEnd.isAfter(localNow) ? localNow : rawDayEnd;
        if (!dayStart.isBefore(dayEnd)) continue;
        final canonicalSteps = canonicalStepsByDay[healthLocalDayKey(dayStart)];
        final dailyWindow = HealthInterval(dayStart.toUtc(), dayEnd.toUtc());
        final dailySummary = HealthSummary.fromReconciliation(
          reconciliation,
          rawPoints: normalizedPoints,
          window: dailyWindow,
          canonicalSteps: canonicalSteps,
          heightCm: heightCm,
          importedAt: importedAt,
        );
        if (dailySummary.recordCount == 0) continue;
        dailySummaries.add(dailySummary);
        summariesByDay[healthLocalDayKey(dayStart)] = dailySummary;
        await _storeSummary(
          dailySummary,
          dayStart,
          windowStart: dailyWindow.start,
          windowEnd: dailyWindow.end,
        );
      }
      final weeklySummaries = List<_HealthDaySnapshot>.generate(7, (index) {
        final day = firstLocalDay.add(Duration(days: index));
        return _HealthDaySnapshot(
          day: day,
          summary:
              summariesByDay[healthLocalDayKey(day)] ?? const HealthSummary(),
        );
      }, growable: false);
      if (dailySummaries.isEmpty) {
        await _removeInvalidEmptySummary(localNow);
      }
      final taskSummaries = await _buildTaskHealthSummaries(
        points: normalizedPoints,
        refreshWindow: refreshWindow,
        importedAt: importedAt,
        heightCm: heightCm,
      );
      await _storeTaskHealthSummaries(
        taskSummaries,
        refreshWindow: refreshWindow,
      );
      final providerSources = <String>{};
      final providerLastRecordAt = <String, DateTime>{};
      DateTime? latestRecordAt;
      for (final dailySummary in dailySummaries) {
        final latestSummaryRecordAt = dailySummary.latestRecordAt;
        if (latestSummaryRecordAt != null &&
            (latestRecordAt == null ||
                latestSummaryRecordAt.isAfter(latestRecordAt))) {
          latestRecordAt = latestSummaryRecordAt;
        }
        providerSources.addAll(
          observedHealthApplicationSources(dailySummary.sources),
        );
        for (final entry in dailySummary.sourceLatestRecordAt.entries) {
          final source = healthApplicationDisplayName(entry.key);
          if (source == null || source == 'Health Connect') continue;
          final current = providerLastRecordAt[source];
          if (current == null || entry.value.isAfter(current)) {
            providerLastRecordAt[source] = entry.value;
          }
        }
      }
      final hasActualRecords = dailySummaries.any(
        (summary) => summary.recordCount > 0,
      );
      final hasRecentRecords =
          latestRecordAt != null &&
          importedAt.difference(latestRecordAt.toUtc()) <=
              const Duration(days: 2);
      // Headline metrics are always the current local calendar day. The last
      // record from yesterday must not remain visible after midnight while
      // waiting for today's first Health Connect record.
      final summary = healthSummaryForLocalDay(summariesByDay, localNow);
      if (!mounted || refreshGeneration != _refreshGeneration) return;
      setState(() {
        _summary = summary;
        _weeklySummaries = List.unmodifiable(weeklySummaries);
        _providerSources = Set.unmodifiable(providerSources);
        _providerLastRecordAt = Map.unmodifiable(providerLastRecordAt);
        _hasActualRecords = hasActualRecords;
        _latestRecordAt = latestRecordAt;
        _readFailed = false;
        _profileHeightCm = heightCm;
        _message = !hasActualRecords
            ? context.l10n.text(
                _bluetoothState['healthConnectStepTrackingAvailable'] == true
                    ? 'health_on_device_steps_waiting'
                    : 'health_no_records_explanation',
              )
            : !hasRecentRecords
            ? context.l10n.text('health_no_recent_records_explanation')
            : summary.recordCount == 0
            ? context.l10n.text('health_no_records_today_explanation')
            : _unavailableTypes.isNotEmpty
            ? context.l10n.text('health_partial_import')
            : null;
      });
      if (hasActualRecords) _showDataReceivedNotice();
    } catch (_) {
      if (mounted && refreshGeneration == _refreshGeneration) {
        setState(() {
          _readFailed = true;
          _message = context.l10n.text('health_read_failed');
        });
      }
    } finally {
      deadline.cancel();
      if (mounted && refreshGeneration == _refreshGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<TaskHealthSummary>> _buildTaskHealthSummaries({
    required List<HealthDataPoint> points,
    required HealthInterval refreshWindow,
    required DateTime importedAt,
    required double? heightCm,
  }) async {
    if (points.isEmpty) return const [];
    final repository = ref.read(entityRecordRepositoryProvider);
    final sessionRecords = await repository.list(
      entityType: 'execution_sessions',
    );
    final eventRecords = await repository.list(entityType: 'session_events');
    final sessions = <HealthExecutionSession>[];
    for (final record in sessionRecords) {
      final data = repository.decode(record);
      final taskOccurrenceId =
          (data['task_occurrence_id'] as String?) ?? record.parentId;
      if (taskOccurrenceId == null || taskOccurrenceId.isEmpty) continue;
      sessions.add(
        HealthExecutionSession(
          id: record.id,
          taskOccurrenceId: taskOccurrenceId,
          state: (data['state'] as String?) ?? record.status,
          startedAt: _healthInstant(data['started_at']),
          finishedAt: _healthInstant(data['finished_at']),
          activeSegmentStartedAt: _healthInstant(
            data['active_segment_started_at'],
          ),
          accumulatedActiveMs:
              (data['accumulated_active_ms'] as num?)?.toInt() ?? 0,
          updatedAt:
              _healthInstant(data['updated_at']) ?? record.updatedAt.toUtc(),
        ),
      );
    }
    final events = <HealthSessionEvent>[];
    for (final record in eventRecords) {
      final data = repository.decode(record);
      final sessionId =
          (data['session_id'] as String?) ??
          record.parentId ??
          record.secondaryParentId;
      final eventType = (data['event_type'] as String?) ?? record.title.trim();
      final occurredAt =
          _healthInstant(data['occurred_at']) ?? record.createdAt.toUtc();
      if (sessionId == null || sessionId.isEmpty || eventType.isEmpty) {
        continue;
      }
      events.add(
        HealthSessionEvent(
          sessionId: sessionId,
          eventType: eventType,
          occurredAt: occurredAt,
        ),
      );
    }
    final intervals = HealthExecutionIntervalBuilder.build(
      sessions: sessions,
      events: events,
      refreshWindow: refreshWindow,
      now: importedAt,
    );
    return TaskHealthSummaryAggregator.aggregate(
      rawPoints: points,
      executionIntervals: intervals,
      refreshWindow: refreshWindow,
      importedAt: importedAt,
      heightCm: heightCm,
    );
  }

  Future<void> _storeTaskHealthSummaries(
    List<TaskHealthSummary> summaries, {
    required HealthInterval refreshWindow,
  }) async {
    if (summaries.isEmpty) return;
    final repository = ref.read(entityRecordRepositoryProvider);
    final existing = await repository.list(entityType: 'task_health_summaries');
    final synchronize =
        ref.read(appSettingsProvider).value?.healthSummarySyncEnabled ?? false;
    for (final summary in summaries) {
      if (summary.recordCount <= 0 ||
          summary.sourceApplications.isEmpty ||
          summary.taskOccurrenceId.isEmpty ||
          summary.executionSessionId.isEmpty) {
        continue;
      }
      final summaryDate = DateFormat(
        'yyyy-MM-dd',
      ).format(summary.intervalStartAt.toLocal());
      final data = <String, Object?>{
        'summary_date': summaryDate,
        'source': summary.sourceApplications.join(', '),
        'summary_type': summary.metricType,
        'metric_type': summary.metricType,
        'value': summary.value,
        'unit': summary.unit,
        'record_count': summary.recordCount,
        'raw_record_count': summary.rawRecordCount,
        'source_applications': summary.sourceApplications,
        'source_record_counts': summary.sourceRecordCounts,
        'last_updated_at': summary.latestRecordAt.toUtc().toIso8601String(),
        'latest_record_at': summary.latestRecordAt.toUtc().toIso8601String(),
        'imported_at': summary.importedAt.toUtc().toIso8601String(),
        'window_start_at': refreshWindow.start.toUtc().toIso8601String(),
        'window_end_at': refreshWindow.end.toUtc().toIso8601String(),
        'task_occurrence_id': summary.taskOccurrenceId,
        'execution_session_id': summary.executionSessionId,
        'interval_start_at': summary.intervalStartAt.toUtc().toIso8601String(),
        'interval_end_at': summary.intervalEndAt.toUtc().toIso8601String(),
        'allocation_method': summary.allocationMethod,
        'estimated': summary.estimated,
        'provenance': summary.provenance,
        'overlap_fraction': summary.overlapFraction,
        'height_cm': summary.heightCm,
        'stride_factor': summary.strideFactor,
      };
      final syncPayload = <String, Object?>{
        'summary_date': data['summary_date'],
        'source': data['source'],
        'summary_type': data['summary_type'],
        'value': data['value'],
        'unit': data['unit'],
        'record_count': data['record_count'],
        'raw_record_count': data['raw_record_count'],
        'source_applications': data['source_applications'],
        'source_record_counts': data['source_record_counts'],
        'last_updated_at': data['last_updated_at'],
        'window_start_at': data['window_start_at'],
        'window_end_at': data['window_end_at'],
        'task_occurrence_id': data['task_occurrence_id'],
        'execution_session_id': data['execution_session_id'],
        'interval_start_at': data['interval_start_at'],
        'interval_end_at': data['interval_end_at'],
        'allocation_method': data['allocation_method'],
        'estimated': data['estimated'],
        'provenance': data['provenance'],
        'overlap_fraction': data['overlap_fraction'],
        'height_cm': data['height_cm'],
        'stride_factor': data['stride_factor'],
      };
      final matching = existing
          .where((record) {
            if (record.parentId != summary.taskOccurrenceId ||
                record.secondaryParentId != summary.executionSessionId) {
              return false;
            }
            final current = repository.decode(record);
            final metric =
                current['metric_type'] ??
                current['summary_type'] ??
                record.title;
            return metric == summary.metricType;
          })
          .toList(growable: false);
      if (matching.isEmpty) {
        await repository.create(
          EntityRecordDraft(
            entityType: 'task_health_summaries',
            parentId: summary.taskOccurrenceId,
            secondaryParentId: summary.executionSessionId,
            title: summary.metricType,
            status: 'recorded',
            data: data,
            syncPayload: syncPayload,
            synchronize: synchronize,
          ),
        );
      } else {
        await repository.update(
          matching.first,
          title: summary.metricType,
          status: 'recorded',
          data: data,
          syncPayload: syncPayload,
          synchronize: synchronize,
        );
        for (final duplicate in matching.skip(1)) {
          await repository.softDelete(duplicate, synchronize: synchronize);
        }
      }
    }
    if (synchronize) {
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    }
  }

  Future<void> _removeInvalidEmptySummary(DateTime day) async {
    final repository = ref.read(entityRecordRepositoryProvider);
    final date = DateFormat('yyyy-MM-dd').format(day);
    final synchronize =
        ref.read(appSettingsProvider).value?.healthSummarySyncEnabled ?? false;
    final records = await repository.list(entityType: 'health_summaries');
    for (final record in records) {
      final data = repository.decode(record);
      final value = data['value'];
      final legacyEmpty =
          data['summary_date'] == date &&
          data['source'] == 'Android Health Connect' &&
          (data['record_count'] == null || data['record_count'] == 0) &&
          (value == null || value == 0 || value == 0.0);
      if (legacyEmpty) {
        await repository.softDelete(record, synchronize: synchronize);
      }
    }
  }

  Future<void> _storeSummary(
    HealthSummary summary,
    DateTime day, {
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final repository = ref.read(entityRecordRepositoryProvider);
    final date = DateFormat('yyyy-MM-dd').format(day);
    final records = await repository.list(entityType: 'health_summaries');
    final synchronize =
        ref.read(appSettingsProvider).value?.healthSummarySyncEnabled ?? false;
    final values = <(String, HealthDataType, num, String)>[
      ('steps', HealthDataType.STEPS, summary.steps, 'count'),
      ('distance', HealthDataType.DISTANCE_DELTA, summary.distanceMeters, 'm'),
      if (summary.averageHeartRate != null)
        (
          'average_heart_rate',
          HealthDataType.HEART_RATE,
          summary.averageHeartRate!,
          'bpm',
        ),
      (
        'sleep_duration',
        HealthDataType.SLEEP_ASLEEP,
        summary.sleepMinutes,
        'min',
      ),
      (
        'active_calories',
        HealthDataType.ACTIVE_ENERGY_BURNED,
        summary.activeCalories,
        'kcal',
      ),
      (
        'exercise_sessions',
        HealthDataType.WORKOUT,
        summary.workoutCount,
        'count',
      ),
    ];
    for (final metric in values) {
      final metricRecordCount = summary.metricRecordCounts[metric.$2] ?? 0;
      if (metricRecordCount == 0) continue;
      final metricSources =
          summary.metricSources[metric.$2] ?? const <String>{};
      final latestRecordAt =
          summary.metricLatestRecordAt[metric.$2] ??
          summary.latestRecordAt ??
          summary.importedAt ??
          windowEnd;
      final estimated =
          metric.$2 == HealthDataType.DISTANCE_DELTA &&
          summary.distanceEstimated;
      final provenance = estimated
          ? summary.distanceProvenance
          : metric.$2 == HealthDataType.STEPS
          ? 'health_connect_daily_aggregate'
          : 'health_connect_record';
      final data = <String, Object?>{
        'summary_date': date,
        'source': metricSources.join(', '),
        'summary_type': metric.$1,
        'value': metric.$3,
        'unit': metric.$4,
        'record_count': metricRecordCount,
        'source_applications': metricSources.toList(growable: false),
        'source_record_counts':
            summary.metricSourceRecordCounts[metric.$2] ??
            const <String, int>{},
        'source_latest_record_at': {
          for (final source in metricSources)
            if (summary.sourceLatestRecordAt[source] != null)
              source: summary.sourceLatestRecordAt[source]!
                  .toUtc()
                  .toIso8601String(),
        },
        'last_updated_at': latestRecordAt.toUtc().toIso8601String(),
        'latest_record_at': latestRecordAt.toUtc().toIso8601String(),
        'imported_at': summary.importedAt?.toUtc().toIso8601String(),
        'window_start_at': windowStart.toUtc().toIso8601String(),
        'window_end_at': windowEnd.toUtc().toIso8601String(),
        'raw_record_count': summary.rawRecordCount,
        'discarded_overlap_count': summary.discardedOverlapCount,
        'estimated': estimated,
        'provenance': provenance,
        'height_cm': estimated ? summary.heightCm : null,
        'stride_factor': estimated ? summary.strideFactor : null,
        'encrypted_details': null,
      };
      final syncPayload = <String, Object?>{
        'summary_date': data['summary_date'],
        'source': data['source'],
        'summary_type': data['summary_type'],
        'value': data['value'],
        'unit': data['unit'],
        'record_count': data['record_count'],
        'source_applications': data['source_applications'],
        'source_record_counts': data['source_record_counts'],
        'last_updated_at': data['last_updated_at'],
        'window_start_at': data['window_start_at'],
        'window_end_at': data['window_end_at'],
        'raw_record_count': data['raw_record_count'],
        'discarded_overlap_count': data['discarded_overlap_count'],
        'estimated': data['estimated'],
        'provenance': data['provenance'],
        'height_cm': data['height_cm'],
        'stride_factor': data['stride_factor'],
        'encrypted_details': null,
      };
      final existing = records
          .where((record) {
            final current = repository.decode(record);
            return current['summary_date'] == date &&
                current['summary_type'] == metric.$1;
          })
          .toList(growable: false);
      if (existing.isEmpty) {
        await repository.create(
          EntityRecordDraft(
            entityType: 'health_summaries',
            title: metric.$1,
            status: 'recorded',
            data: data,
            syncPayload: syncPayload,
            synchronize: synchronize,
          ),
        );
      } else {
        await repository.update(
          existing.first,
          data: data,
          syncPayload: syncPayload,
          synchronize: synchronize,
        );
        for (final duplicate in existing.skip(1)) {
          await repository.softDelete(duplicate, synchronize: synchronize);
        }
      }
    }
    if (synchronize) {
      unawaited(ref.read(syncServiceProvider).drainOutbox());
    }
  }

  Future<void> _disconnect() async {
    try {
      await _health.revokePermissions();
    } finally {
      await ref
          .read(settingsRepositoryProvider)
          .updateHealthConnectEnabled(false);
      if (mounted) {
        setState(() {
          _authorized = false;
          _summary = const HealthSummary();
          _weeklySummaries = const [];
          _providerSources = const {};
          _providerLastRecordAt = const {};
          _hasActualRecords = false;
          _latestRecordAt = null;
          _readFailed = false;
        });
      }
    }
  }

  Future<void> _removeImportedSummaries() async {
    final repository = ref.read(entityRecordRepositoryProvider);
    final records = await repository.list(entityType: 'health_summaries');
    final synchronize =
        ref.read(appSettingsProvider).value?.healthSummarySyncEnabled ?? false;
    for (final record in records) {
      await repository.softDelete(record, synchronize: synchronize);
    }
    if (mounted) {
      setState(() {
        _summary = const HealthSummary();
        _weeklySummaries = const [];
        _providerSources = const {};
        _providerLastRecordAt = const {};
        _hasActualRecords = false;
        _latestRecordAt = null;
        _readFailed = false;
        _message = context.l10n.text('health_summaries_removed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasMetric(HealthDataType type) =>
        (_summary.metricRecordCounts[type] ?? 0) > 0;
    final locale = context.l10n.locale.toLanguageTag();
    final distanceAvailable = hasMetric(HealthDataType.DISTANCE_DELTA);
    final distanceValue = !distanceAvailable
        ? '—'
        : _summary.distanceMeters < 1000
        ? '${NumberFormat('0', locale).format(_summary.distanceMeters)} m'
        : '${NumberFormat('0.0', locale).format(_summary.distanceMeters / 1000)} km';
    final connectionState = resolveHealthConnectionState(
      authorized: _authorized,
      hasActualRecords: _hasActualRecords,
      latestRecordAt: _latestRecordAt,
      now: DateTime.now(),
      readFailed: _readFailed,
    );
    final connectionTitle = context.l10n.text(switch (connectionState) {
      HealthConnectionState.permissionRequired =>
        'health_permission_required_state',
      HealthConnectionState.permissionGrantedWaitingForData =>
        'health_permissions_ready',
      HealthConnectionState.connectedDataReceived => 'health_connected',
      HealthConnectionState.connectedNoRecentRecords =>
        'health_connected_no_recent',
      HealthConnectionState.needsAttention =>
        'health_connection_needs_attention',
    });
    final connectionDetail = context.l10n.text(switch (connectionState) {
      HealthConnectionState.permissionRequired =>
        'health_permission_explanation',
      HealthConnectionState.permissionGrantedWaitingForData =>
        'health_permissions_no_source',
      HealthConnectionState.connectedDataReceived => 'health_read_only_active',
      HealthConnectionState.connectedNoRecentRecords =>
        'health_connected_no_recent_detail',
      HealthConnectionState.needsAttention =>
        'health_connection_needs_attention_detail',
    });
    final connectedWearables = _pairedWearables
        .where((wearable) => wearable.isConnected)
        .toList(growable: false);
    final providerNames = _providerSources.toList()..sort();
    final stepsAvailable = hasMetric(HealthDataType.STEPS);
    final weeklyPeakSteps = _weeklySummaries.fold<int>(
      0,
      (highest, day) => math.max(highest, day.summary.steps),
    );
    final todayComparedWithWeek = weeklyPeakSteps == 0
        ? 0.0
        : (_summary.steps / weeklyPeakSteps).clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('health_connect')),
        actions: [
          PopupMenuButton<String>(
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            onSelected: (value) {
              switch (value) {
                case 'access':
                  unawaited(_openHealthConnectSettings());
                case 'bluetooth':
                  unawaited(_openBluetoothSettings());
                case 'delete':
                  unawaited(_removeImportedSummaries());
                case 'disconnect':
                  unawaited(_disconnect());
              }
            },
            itemBuilder: (context) => [
              if (_available)
                PopupMenuItem(
                  value: 'access',
                  child: _HealthMenuRow(
                    icon: Icons.manage_accounts_outlined,
                    label: context.l10n.text('health_manage_access'),
                  ),
                ),
              if (Platform.isAndroid)
                PopupMenuItem(
                  value: 'bluetooth',
                  child: _HealthMenuRow(
                    icon: Icons.bluetooth_outlined,
                    label: context.l10n.text('health_wearables_settings'),
                  ),
                ),
              if (_authorized && _hasActualRecords)
                PopupMenuItem(
                  value: 'delete',
                  child: _HealthMenuRow(
                    icon: Icons.delete_outline,
                    label: context.l10n.text('health_delete_summaries'),
                  ),
                ),
              if (_authorized)
                PopupMenuItem(
                  value: 'disconnect',
                  child: _HealthMenuRow(
                    icon: Icons.link_off_outlined,
                    label: context.l10n.text('health_disconnect'),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: ListView(
          key: const PageStorageKey<String>('health-connect-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            10,
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (_pullRefreshing) const SizedBox(height: 52),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HealthStatusCard(
                      state: connectionState,
                      title: connectionTitle,
                      detail: connectionDetail,
                      message: _message,
                      busy: _checking || (_loading && !_pullRefreshing),
                      authorized: _authorized,
                      available: _available,
                      onConnect: _connect,
                    ),
                    if (_authorized) ...[
                      const SizedBox(height: 14),
                      _TodayHealthCard(
                        title: context.l10n.text('health_recent_context'),
                        stepsLabel: context.l10n.text('health_steps'),
                        steps: stepsAvailable
                            ? NumberFormat.decimalPattern(
                                locale,
                              ).format(_summary.steps)
                            : '—',
                        relativeProgress: todayComparedWithWeek,
                        distanceLabel: context.l10n.text(
                          _summary.distanceEstimated
                              ? 'health_distance_estimated'
                              : 'health_distance',
                        ),
                        distance: distanceValue,
                        energyLabel: context.l10n.text('health_active_energy'),
                        energy: hasMetric(HealthDataType.ACTIVE_ENERGY_BURNED)
                            ? '${NumberFormat('0', locale).format(_summary.activeCalories)} kcal'
                            : '—',
                        workoutsLabel: context.l10n.text('health_workouts'),
                        workouts: hasMetric(HealthDataType.WORKOUT)
                            ? NumberFormat.decimalPattern(
                                locale,
                              ).format(_summary.workoutCount)
                            : '—',
                      ),
                      const SizedBox(height: 14),
                      _WeeklyStepsCard(
                        snapshots: _weeklySummaries,
                        locale: locale,
                        title: context.l10n.text('health_weekly_steps'),
                        detail: context.l10n.text('health_weekly_steps_detail'),
                        stepsLabel: context.l10n.text('health_steps'),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const gap = 10.0;
                          final columns = constraints.maxWidth >= 760 ? 3 : 2;
                          final width =
                              (constraints.maxWidth - gap * (columns - 1)) /
                              columns;
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              SizedBox(
                                width: width,
                                child: _HealthMetric(
                                  icon: Icons.favorite_rounded,
                                  accent: Colors.redAccent,
                                  label: context.l10n.text(
                                    'health_average_heart_rate',
                                  ),
                                  value: _summary.averageHeartRate == null
                                      ? '—'
                                      : '${_summary.averageHeartRate!.round()} bpm',
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _HealthMetric(
                                  icon: Icons.bedtime_rounded,
                                  accent: Colors.deepPurpleAccent,
                                  label: context.l10n.text('health_sleep'),
                                  value: hasMetric(HealthDataType.SLEEP_ASLEEP)
                                      ? context.l10n.duration(
                                          Duration(
                                            minutes: _summary.sleepMinutes
                                                .round(),
                                          ),
                                        )
                                      : '—',
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _HealthMetric(
                                  icon: Icons.update_rounded,
                                  accent: colorScheme.primary,
                                  label: context.l10n.text(
                                    'health_latest_record',
                                  ),
                                  value: _latestRecordAt == null
                                      ? '—'
                                      : DateFormat.Hm(
                                          locale,
                                        ).format(_latestRecordAt!.toLocal()),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                    if (!_authorized) ...[
                      const SizedBox(height: 14),
                      _HealthPermissionCard(
                        title: context.l10n.text('health_connect_context'),
                        detail: context.l10n.text('health_permission_detail'),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _HealthSourcesCard(
                      title: context.l10n.text('health_sources'),
                      healthConnectLabel: context.l10n.text('health_connect'),
                      healthConnectStatus: context.l10n.text(
                        _authorized
                            ? 'health_connected'
                            : 'health_permission_required_state',
                      ),
                      healthConnectConnected: _authorized,
                      applicationLabel: context.l10n.text(
                        'health_source_applications',
                      ),
                      emptyApplicationsLabel: context.l10n.text(
                        'health_source_applications_empty',
                      ),
                      latestRecordLabel: context.l10n.text(
                        'health_latest_record',
                      ),
                      latestRecordAt: _latestRecordAt,
                      providerNames: providerNames,
                      providerLastRecordAt: _providerLastRecordAt,
                      locale: locale,
                      estimatedDistanceDetail:
                          _authorized && _summary.distanceEstimated
                          ? context.l10n
                                .format('health_distance_estimate_provenance', {
                                  'height': NumberFormat(
                                    '0.#',
                                    locale,
                                  ).format(_summary.heightCm),
                                })
                          : null,
                      showWearables: Platform.isAndroid,
                      wearablesTitle: context.l10n.text(
                        'health_connected_watches',
                      ),
                      wearablesDetail: context.l10n.text(
                        'health_connected_watches_detail',
                      ),
                      wearablesHistoryNotice: context.l10n.text(
                        'health_wearables_history_notice',
                      ),
                      wearablesMessage: _wearablesMessage,
                      wearablesLoading: _wearablesLoading,
                      wearables: connectedWearables,
                      onInspectWearable: _inspectPairedHealthWearable,
                      onBluetoothSettings: _openBluetoothSettings,
                    ),
                    if (Platform.isAndroid) ...[
                      if (!distanceAvailable &&
                          stepsAvailable &&
                          !isValidHealthHeight(_profileHeightCm)) ...[
                        const SizedBox(height: 10),
                        _HealthInlineNotice(
                          icon: Icons.height_outlined,
                          text: context.l10n.text('height_required'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.text('health_pull_to_refresh'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthDaySnapshot {
  const _HealthDaySnapshot({required this.day, required this.summary});

  final DateTime day;
  final HealthSummary summary;
}

class _HealthMenuRow extends StatelessWidget {
  const _HealthMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _HealthStatusCard extends StatelessWidget {
  const _HealthStatusCard({
    required this.state,
    required this.title,
    required this.detail,
    required this.busy,
    required this.authorized,
    required this.available,
    required this.onConnect,
    this.message,
  });

  final HealthConnectionState state;
  final String title;
  final String detail;
  final String? message;
  final bool busy;
  final bool authorized;
  final bool available;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = switch (state) {
      HealthConnectionState.connectedDataReceived => const Color(0xFF22A06B),
      HealthConnectionState.permissionGrantedWaitingForData => colors.tertiary,
      HealthConnectionState.connectedNoRecentRecords => const Color(0xFFE59A24),
      HealthConnectionState.needsAttention => colors.error,
      HealthConnectionState.permissionRequired => colors.primary,
    };
    final icon = switch (state) {
      HealthConnectionState.connectedDataReceived => Icons.favorite_rounded,
      HealthConnectionState.permissionGrantedWaitingForData =>
        Icons.hourglass_top_rounded,
      HealthConnectionState.connectedNoRecentRecords => Icons.history_rounded,
      HealthConnectionState.needsAttention => Icons.error_outline_rounded,
      HealthConnectionState.permissionRequired =>
        Icons.health_and_safety_outlined,
    };
    return Material(
      color: Color.alphaBlend(accent.withValues(alpha: 0.09), colors.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!authorized && !busy) ...[
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: available
                        ? context.l10n.text('health_continue_permissions')
                        : context.l10n.text('health_install_connect'),
                    onPressed: onConnect,
                    icon: Icon(
                      available
                          ? Icons.arrow_forward_rounded
                          : Icons.download_rounded,
                    ),
                  ),
                ],
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(99),
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.12),
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HealthPermissionCard extends StatelessWidget {
  const _HealthPermissionCard({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
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

class _TodayHealthCard extends StatelessWidget {
  const _TodayHealthCard({
    required this.title,
    required this.stepsLabel,
    required this.steps,
    required this.relativeProgress,
    required this.distanceLabel,
    required this.distance,
    required this.energyLabel,
    required this.energy,
    required this.workoutsLabel,
    required this.workouts,
  });

  final String title;
  final String stepsLabel;
  final String steps;
  final double relativeProgress;
  final String distanceLabel;
  final String distance;
  final String energyLabel;
  final String energy;
  final String workoutsLabel;
  final String workouts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.58),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 540;
            final dial = SizedBox.square(
              dimension: compact ? 126 : 142,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: relativeProgress,
                    strokeWidth: 10,
                    strokeCap: StrokeCap.round,
                    color: colors.primary,
                    backgroundColor: colors.primary.withValues(alpha: 0.13),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_walk_rounded,
                          size: 24,
                          color: colors.primary,
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            steps,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          stepsLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                _HealthMiniValue(
                  icon: Icons.route_rounded,
                  label: distanceLabel,
                  value: distance,
                ),
                const SizedBox(height: 10),
                _HealthMiniValue(
                  icon: Icons.local_fire_department_rounded,
                  label: energyLabel,
                  value: energy,
                ),
                const SizedBox(height: 10),
                _HealthMiniValue(
                  icon: Icons.fitness_center_rounded,
                  label: workoutsLabel,
                  value: workouts,
                ),
              ],
            );
            if (compact) {
              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  dial,
                  const SizedBox(height: 18),
                  _HealthMiniValue(
                    icon: Icons.route_rounded,
                    label: distanceLabel,
                    value: distance,
                  ),
                  const SizedBox(height: 10),
                  _HealthMiniValue(
                    icon: Icons.local_fire_department_rounded,
                    label: energyLabel,
                    value: energy,
                  ),
                  const SizedBox(height: 10),
                  _HealthMiniValue(
                    icon: Icons.fitness_center_rounded,
                    label: workoutsLabel,
                    value: workouts,
                  ),
                ],
              );
            }
            return Row(
              children: [
                dial,
                const SizedBox(width: 24),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HealthMiniValue extends StatelessWidget {
  const _HealthMiniValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _WeeklyStepsCard extends StatelessWidget {
  const _WeeklyStepsCard({
    required this.snapshots,
    required this.locale,
    required this.title,
    required this.detail,
    required this.stepsLabel,
  });

  final List<_HealthDaySnapshot> snapshots;
  final String locale;
  final String title;
  final String detail;
  final String stepsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = snapshots.fold<int>(
      0,
      (sum, snapshot) => sum + snapshot.summary.steps,
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NumberFormat.compact(locale: locale).format(total),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: colors.primary,
                      ),
                    ),
                    Text(
                      stepsLabel,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 116,
              child: CustomPaint(
                painter: _WeeklyStepsPainter(
                  snapshots: snapshots,
                  barColor: colors.primary,
                  todayColor: colors.tertiary,
                  gridColor: colors.outlineVariant.withValues(alpha: 0.42),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final snapshot in snapshots)
                  Expanded(
                    child: Text(
                      DateFormat.E(locale).format(snapshot.day),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: DateUtils.isSameDay(snapshot.day, DateTime.now())
                            ? colors.tertiary
                            : colors.onSurfaceVariant,
                        fontWeight:
                            DateUtils.isSameDay(snapshot.day, DateTime.now())
                            ? FontWeight.w900
                            : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyStepsPainter extends CustomPainter {
  const _WeeklyStepsPainter({
    required this.snapshots,
    required this.barColor,
    required this.todayColor,
    required this.gridColor,
  });

  final List<_HealthDaySnapshot> snapshots;
  final Color barColor;
  final Color todayColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index < 3; index++) {
      final y = size.height * index / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (snapshots.isEmpty) return;
    final maximum = snapshots.fold<int>(
      0,
      (highest, snapshot) => math.max(highest, snapshot.summary.steps),
    );
    final slotWidth = size.width / snapshots.length;
    final barWidth = math.min(24.0, slotWidth * 0.46);
    for (var index = 0; index < snapshots.length; index++) {
      final snapshot = snapshots[index];
      final ratio = maximum == 0 ? 0.0 : snapshot.summary.steps / maximum;
      final barHeight = ratio == 0 ? 4.0 : math.max(8.0, size.height * ratio);
      final centerX = slotWidth * index + slotWidth / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          centerX - barWidth / 2,
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        const Radius.circular(12),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = DateUtils.isSameDay(snapshot.day, DateTime.now())
              ? todayColor
              : barColor.withValues(alpha: ratio == 0 ? 0.18 : 0.82),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklyStepsPainter oldDelegate) =>
      oldDelegate.snapshots != snapshots ||
      oldDelegate.barColor != barColor ||
      oldDelegate.todayColor != todayColor ||
      oldDelegate.gridColor != gridColor;
}

class _HealthSourcesCard extends StatelessWidget {
  const _HealthSourcesCard({
    required this.title,
    required this.healthConnectLabel,
    required this.healthConnectStatus,
    required this.healthConnectConnected,
    required this.applicationLabel,
    required this.emptyApplicationsLabel,
    required this.latestRecordLabel,
    required this.providerNames,
    required this.providerLastRecordAt,
    required this.locale,
    required this.showWearables,
    required this.wearablesTitle,
    required this.wearablesDetail,
    required this.wearablesHistoryNotice,
    required this.wearablesLoading,
    required this.wearables,
    required this.onInspectWearable,
    required this.onBluetoothSettings,
    this.wearablesMessage,
    this.latestRecordAt,
    this.estimatedDistanceDetail,
  });

  final String title;
  final String healthConnectLabel;
  final String healthConnectStatus;
  final bool healthConnectConnected;
  final String applicationLabel;
  final String emptyApplicationsLabel;
  final String latestRecordLabel;
  final DateTime? latestRecordAt;
  final List<String> providerNames;
  final Map<String, DateTime> providerLastRecordAt;
  final String locale;
  final String? estimatedDistanceDetail;
  final bool showWearables;
  final String wearablesTitle;
  final String wearablesDetail;
  final String wearablesHistoryNotice;
  final String? wearablesMessage;
  final bool wearablesLoading;
  final List<PairedHealthWearable> wearables;
  final ValueChanged<String> onInspectWearable;
  final VoidCallback onBluetoothSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const PageStorageKey<String>('health-sources-expansion'),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.hub_rounded, color: colors.primary, size: 21),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: latestRecordAt == null
            ? Text(healthConnectLabel)
            : Text(
                '$latestRecordLabel · ${DateFormat.MMMd(locale).add_Hm().format(latestRecordAt!.toLocal())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minLeadingWidth: 36,
            leading: Icon(
              Icons.health_and_safety_rounded,
              color: healthConnectConnected
                  ? const Color(0xFF22A06B)
                  : colors.onSurfaceVariant,
            ),
            title: Text(
              healthConnectLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    (healthConnectConnected
                            ? const Color(0xFF22A06B)
                            : colors.surfaceContainerHighest)
                        .withValues(alpha: healthConnectConnected ? 0.12 : 0.7),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                healthConnectStatus,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: healthConnectConnected
                      ? const Color(0xFF16764F)
                      : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              applicationLabel,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          if (providerNames.isEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                emptyApplicationsLabel,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final provider in providerNames)
                    Tooltip(
                      message: providerLastRecordAt[provider] == null
                          ? provider
                          : DateFormat.yMMMd(locale).add_Hm().format(
                              providerLastRecordAt[provider]!.toLocal(),
                            ),
                      child: Chip(
                        avatar: const Icon(Icons.check_rounded, size: 17),
                        label: Text(provider),
                      ),
                    ),
                ],
              ),
            ),
          if (estimatedDistanceDetail != null) ...[
            const SizedBox(height: 12),
            _HealthInlineNotice(
              icon: Icons.straighten_rounded,
              text: estimatedDistanceDetail!,
            ),
          ],
          if (showWearables) ...[
            const SizedBox(height: 14),
            const Divider(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.tertiary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.watch_rounded,
                    color: colors.tertiary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wearablesTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        wearablesDetail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.text('health_wearables_settings'),
                  onPressed: onBluetoothSettings,
                  icon: const Icon(Icons.settings_bluetooth_rounded),
                ),
              ],
            ),
            if (wearablesLoading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(99),
              ),
            ],
            if (wearablesMessage != null) ...[
              const SizedBox(height: 12),
              _HealthInlineNotice(
                icon: Icons.watch_off_outlined,
                text: wearablesMessage!,
              ),
            ],
            if (wearables.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final wearable in wearables)
                _PairedHealthWearableTile(
                  wearable: wearable,
                  onInspect: onInspectWearable,
                ),
            ],
            const SizedBox(height: 12),
            Text(
              wearablesHistoryNotice,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthInlineNotice extends StatelessWidget {
  const _HealthInlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colors.onSurfaceVariant),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairedHealthWearableTile extends StatelessWidget {
  const _PairedHealthWearableTile({
    required this.wearable,
    required this.onInspect,
  });

  final PairedHealthWearable wearable;
  final ValueChanged<String> onInspect;

  @override
  Widget build(BuildContext context) {
    final capabilityState = wearable.capabilityState;
    final capabilityLabels = wearable.capabilities
        .map(
          (value) => value == 'battery' && wearable.batteryPercent != null
              ? context.l10n.format('health_wearables_battery_value', {
                  'value': wearable.batteryPercent,
                })
              : context.l10n.format('health_wearables_capability_available', {
                  'capability': context.l10n.text(
                    'health_wearables_capability_$value',
                  ),
                }),
        )
        .join(' • ');
    final inspectionFailed = wearable.inspectionError != null;
    final capabilityText = switch (capabilityState) {
      'direct_supported' when wearable.capabilities.isNotEmpty =>
        context.l10n.format('health_wearables_direct_available', {
          'capabilities': capabilityLabels,
        }),
      'no_direct_health_service' => context.l10n.text(
        'health_wearables_no_direct_service',
      ),
      'inspecting' => context.l10n.text('health_wearables_inspecting'),
      _ when inspectionFailed => context.l10n.text(
        'health_wearables_inspection_failed',
      ),
      _ => context.l10n.text('health_wearables_not_checked'),
    };
    final detail = <String>[
      capabilityText,
      context.l10n.text('health_wearables_connected'),
    ].join(' • ');
    final colors = Theme.of(context).colorScheme;
    final direct = capabilityState == 'direct_supported';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: direct
              ? colors.tertiary.withValues(alpha: 0.35)
              : colors.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (direct ? colors.tertiary : colors.primary).withValues(
                alpha: 0.1,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              direct
                  ? Icons.sensors_rounded
                  : Icons.bluetooth_connected_rounded,
              color: direct ? colors.tertiary : colors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wearable.displayName.isEmpty
                      ? context.l10n.text('health_wearables_unnamed')
                      : wearable.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (capabilityState == 'inspecting')
            const Padding(
              padding: EdgeInsets.all(11),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: context.l10n.text('health_wearables_check_live'),
              onPressed: () => onInspect(wearable.bridgeId),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolvedAccent = accent ?? colors.primary;
    return Container(
      constraints: const BoxConstraints(minHeight: 108),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: resolvedAccent.withValues(alpha: 0.11),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: resolvedAccent, size: 18),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

DateTime? _healthInstant(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim())?.toUtc();
  }
  return null;
}
