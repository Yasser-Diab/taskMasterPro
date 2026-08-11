import 'dart:async';
import 'dart:io';

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
  static const _types = [
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
  ];

  final Health _health = Health();
  bool _checking = true;
  bool _available = false;
  bool _authorized = false;
  bool _loading = false;
  String? _message;
  Map<String, Object?> _bluetoothState = const {};
  List<PairedHealthWearable> _pairedWearables = const [];
  bool _wearablesLoading = false;
  String? _wearablesMessage;
  final Set<HealthDataType> _unavailableTypes = {};
  Set<String> _providerSources = const {};
  Map<String, DateTime> _providerLastRecordAt = const {};
  bool _hasActualRecords = false;
  bool _readFailed = false;
  double? _profileHeightCm;
  HealthSummary _summary = const HealthSummary();
  Timer? _dayBoundaryTimer;

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
        setState(() => _summary = const HealthSummary());
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
      await _health.configure();
      final available = await _health.isHealthConnectAvailable();
      final permission = available
          ? await _health.hasPermissions(
                  _types,
                  permissions: List.filled(
                    _types.length,
                    HealthDataAccess.READ,
                  ),
                ) ??
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
          .invokeMapMethod<String, Object?>('state');
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
      final values = await _healthSourcesChannel.invokeListMethod<Object?>(
        'pairedHealthDevices',
      );
      final wearables = PairedHealthWearable.fromPlatformValues(
        values ?? const <Object?>[],
      );
      if (!mounted) return;
      setState(() {
        _pairedWearables = wearables;
        _wearablesMessage = wearables.isEmpty
            ? context.l10n.text('health_wearables_none')
            : null;
      });
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
      );
      _pairedWearables = List.unmodifiable(updated);
    });
    try {
      final inspected = await _healthSourcesChannel
          .invokeMapMethod<String, Object?>('inspectPairedHealthDevice', {
            'address': bridgeId,
            'timeoutMillis': 12000,
          });
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
        );
        _pairedWearables = List.unmodifiable(updated);
      });
    }
  }

  Future<void> _openBluetoothSettings() async {
    await _healthSourcesChannel.invokeMethod<void>('openSettings');
    await _loadBluetoothState();
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
      for (final type in _types) {
        try {
          points.addAll(
            await _health.getHealthDataFromTypes(
              startTime: start,
              endTime: end,
              types: [type],
            ),
          );
        } catch (_) {
          _unavailableTypes.add(type);
        }
      }
      final reconciliation = HealthRecordReconciler.reconcile(points);
      final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
      final profile = userId == null
          ? null
          : await ref.read(localProfileProvider(userId).future);
      final heightCm = profile?.heightCm;
      final dailySummaries = <HealthSummary>[];
      final summariesByDay = <String, HealthSummary>{};
      for (var index = 0; index < 7; index++) {
        final dayStart = firstLocalDay.add(Duration(days: index));
        final rawDayEnd = dayStart.add(const Duration(days: 1));
        final dayEnd = rawDayEnd.isAfter(localNow) ? localNow : rawDayEnd;
        if (!dayStart.isBefore(dayEnd)) continue;
        int? canonicalSteps;
        if (!_unavailableTypes.contains(HealthDataType.STEPS)) {
          try {
            canonicalSteps = await _health.getTotalStepsInInterval(
              dayStart,
              dayEnd,
            );
          } catch (_) {
            canonicalSteps = null;
          }
        }
        final dailyWindow = HealthInterval(dayStart.toUtc(), dayEnd.toUtc());
        final dailySummary = HealthSummary.fromReconciliation(
          reconciliation,
          rawPoints: points,
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
      if (dailySummaries.isEmpty) {
        await _removeInvalidEmptySummary(localNow);
      }
      final taskSummaries = await _buildTaskHealthSummaries(
        points: points,
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
      for (final dailySummary in dailySummaries) {
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
      // Headline metrics are always the current local calendar day. The last
      // record from yesterday must not remain visible after midnight while
      // waiting for today's first Health Connect record.
      final summary = healthSummaryForLocalDay(summariesByDay, localNow);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _providerSources = Set.unmodifiable(providerSources);
        _providerLastRecordAt = Map.unmodifiable(providerLastRecordAt);
        _hasActualRecords = hasActualRecords;
        _readFailed = false;
        _profileHeightCm = heightCm;
        _message = !hasActualRecords
            ? context.l10n.text('health_no_records_explanation')
            : _unavailableTypes.isNotEmpty
            ? context.l10n.text('health_partial_import')
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _readFailed = true;
          _message = context.l10n.text('health_read_failed');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
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
        'source_latest_record_at': data['source_latest_record_at'],
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
          _providerSources = const {};
          _providerLastRecordAt = const {};
          _hasActualRecords = false;
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
        _providerSources = const {};
        _providerLastRecordAt = const {};
        _hasActualRecords = false;
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
      latestRecordAt: _summary.latestRecordAt,
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
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('health_connect'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.health_and_safety_outlined,
                        size: 34,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connectionTitle,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(connectionDetail),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(context.l10n.text('health_permission_detail')),
                  const SizedBox(height: 16),
                  if (_checking || _loading)
                    const LinearProgressIndicator()
                  else if (!_authorized)
                    FilledButton.icon(
                      onPressed: _connect,
                      icon: Icon(
                        _available
                            ? Icons.lock_open_outlined
                            : Icons.download_outlined,
                      ),
                      label: Text(
                        _available
                            ? context.l10n.text('health_continue_permissions')
                            : context.l10n.text('health_install_connect'),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            context.l10n.text('health_refresh_seven_days'),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.link_off),
                          label: Text(context.l10n.text('health_disconnect')),
                        ),
                      ],
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_authorized)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.source_outlined),
                      title: Text(context.l10n.text('health_sources')),
                      subtitle: Text(
                        context.l10n.text('health_sources_detail'),
                      ),
                    ),
                    _HealthPlatformSourceTile(
                      title: context.l10n.text('health_connect'),
                      isConnected: false,
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.apps_outlined),
                      title: Text(
                        context.l10n.text('health_source_applications'),
                      ),
                      subtitle: Text(
                        context.l10n.text('health_source_applications_empty'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_authorized) const SizedBox(height: 16),
          if (_authorized) ...[
            Text(
              context.l10n.text('health_recent_context'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.sizeOf(context).width >= 760 ? 3 : 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _HealthMetric(
                  icon: Icons.directions_walk,
                  label: context.l10n.text('health_steps'),
                  value: hasMetric(HealthDataType.STEPS)
                      ? NumberFormat.compact(
                          locale: locale,
                        ).format(_summary.steps)
                      : '—',
                ),
                _HealthMetric(
                  icon: Icons.route_outlined,
                  label: context.l10n.text(
                    _summary.distanceEstimated
                        ? 'health_distance_estimated'
                        : 'health_distance',
                  ),
                  value: distanceValue,
                ),
                _HealthMetric(
                  icon: Icons.favorite_border,
                  label: context.l10n.text('health_average_heart_rate'),
                  value: _summary.averageHeartRate == null
                      ? '—'
                      : '${_summary.averageHeartRate!.round()} bpm',
                ),
                _HealthMetric(
                  icon: Icons.bedtime_outlined,
                  label: context.l10n.text('health_sleep'),
                  value: hasMetric(HealthDataType.SLEEP_ASLEEP)
                      ? context.l10n.duration(
                          Duration(minutes: _summary.sleepMinutes.round()),
                        )
                      : '—',
                ),
                _HealthMetric(
                  icon: Icons.local_fire_department_outlined,
                  label: context.l10n.text('health_active_energy'),
                  value: hasMetric(HealthDataType.ACTIVE_ENERGY_BURNED)
                      ? '${NumberFormat('0', locale).format(_summary.activeCalories)} kcal'
                      : '—',
                ),
                _HealthMetric(
                  icon: Icons.fitness_center_outlined,
                  label: context.l10n.text('health_workouts'),
                  value: hasMetric(HealthDataType.WORKOUT)
                      ? NumberFormat.decimalPattern(
                          locale,
                        ).format(_summary.workoutCount)
                      : '—',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.source_outlined),
                      title: Text(context.l10n.text('health_sources')),
                      subtitle: Text(
                        context.l10n.text('health_sources_detail'),
                      ),
                    ),
                    _HealthPlatformSourceTile(
                      title: context.l10n.text('health_connect'),
                      isConnected: _authorized,
                      latestRecordAt: _summary.latestRecordAt,
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.apps_outlined),
                      title: Text(
                        context.l10n.text('health_source_applications'),
                      ),
                      subtitle: Text(
                        _providerSources.isEmpty
                            ? context.l10n.text(
                                'health_source_applications_empty',
                              )
                            : (_providerSources.toList()..sort()).join(', '),
                      ),
                    ),
                    if (_summary.latestRecordAt != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.update_outlined),
                        title: Text(context.l10n.text('health_latest_record')),
                        subtitle: Text(
                          DateFormat.yMMMd(
                            context.l10n.locale.toLanguageTag(),
                          ).add_jm().format(_summary.latestRecordAt!.toLocal()),
                        ),
                      ),
                    if (_summary.importedAt != null && _hasActualRecords)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_download_outlined),
                        title: Text(
                          context.l10n.text('health_last_successful_import'),
                        ),
                        subtitle: Text(
                          DateFormat.yMMMd(
                            context.l10n.locale.toLanguageTag(),
                          ).add_jm().format(_summary.importedAt!.toLocal()),
                        ),
                      ),
                    for (final source in _providerSources.toList()..sort())
                      _HealthSourceTile(
                        name: source,
                        latestRecordAt: _providerLastRecordAt[source],
                      ),
                    if (_summary.distanceEstimated)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.straighten_outlined),
                        title: Text(
                          context.l10n.text('health_distance_estimated'),
                        ),
                        subtitle: Text(
                          context.l10n
                              .format('health_distance_estimate_provenance', {
                                'height': NumberFormat(
                                  '0.#',
                                  context.l10n.locale.toLanguageTag(),
                                ).format(_summary.heightCm),
                              }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _removeImportedSummaries,
              icon: const Icon(Icons.delete_outline),
              label: Text(context.l10n.text('health_delete_summaries')),
            ),
          ],
          if (Platform.isAndroid) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.watch_outlined),
                      title: Text(context.l10n.text('health_wearables')),
                      subtitle: Text(
                        context.l10n.text('health_wearables_detail'),
                      ),
                    ),
                    if (_wearablesLoading) const LinearProgressIndicator(),
                    if (_wearablesMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(_wearablesMessage!),
                    ],
                    for (final wearable in _pairedWearables)
                      _PairedHealthWearableTile(
                        wearable: wearable,
                        onInspect: _inspectPairedHealthWearable,
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed:
                              _wearablesLoading ||
                                  _bluetoothState['supported'] == false
                              ? null
                              : () => _loadPairedHealthWearables(
                                  requestBluetoothPermission: true,
                                ),
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            context.l10n.text('health_wearables_refresh'),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openBluetoothSettings,
                          icon: const Icon(Icons.bluetooth_outlined),
                          label: Text(
                            context.l10n.text('health_wearables_settings'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.text('health_wearables_history_notice'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (!distanceAvailable &&
                hasMetric(HealthDataType.STEPS) &&
                !isValidHealthHeight(_profileHeightCm))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.height_outlined),
                title: Text(context.l10n.text('health_distance')),
                subtitle: Text(context.l10n.text('height_required')),
              ),
          ],
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
          (value) =>
              context.l10n.format('health_wearables_capability_available', {
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
      wearable.isConnected
          ? context.l10n.text('health_wearables_connected')
          : context.l10n.text('health_wearables_paired'),
    ].join(' • ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        capabilityState == 'direct_supported'
            ? Icons.watch_outlined
            : Icons.bluetooth_outlined,
      ),
      title: Text(
        wearable.displayName.isEmpty
            ? context.l10n.text('health_wearables_unnamed')
            : wearable.displayName,
      ),
      subtitle: Text(detail),
      trailing: capabilityState == 'inspecting'
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: context.l10n.text('health_wearables_check_live'),
              onPressed: () => onInspect(wearable.bridgeId),
              icon: const Icon(Icons.manage_search_outlined),
            ),
    );
  }
}

class _HealthPlatformSourceTile extends StatelessWidget {
  const _HealthPlatformSourceTile({
    required this.title,
    required this.isConnected,
    this.latestRecordAt,
  });

  final String title;
  final bool isConnected;
  final DateTime? latestRecordAt;

  @override
  Widget build(BuildContext context) {
    final subtitle = !isConnected
        ? context.l10n.text('health_permission_required_state')
        : latestRecordAt == null
        ? context.l10n.text('health_permissions_ready')
        : context.l10n.format('health_source_latest_record', {
            'source': title,
            'time': DateFormat.yMMMd(
              context.l10n.locale.toLanguageTag(),
            ).add_jm().format(latestRecordAt!.toLocal()),
          });
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.health_and_safety_outlined,
        color: isConnected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _HealthSourceTile extends StatelessWidget {
  const _HealthSourceTile({required this.name, this.latestRecordAt});

  final String name;
  final DateTime? latestRecordAt;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.check_circle_outline,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(name),
      subtitle: Text(
        latestRecordAt == null
            ? context.l10n.text('health_connected_data_received')
            : context.l10n.format('health_source_latest_record', {
                'source': name,
                'time': DateFormat.yMMMd(
                  context.l10n.locale.toLanguageTag(),
                ).add_jm().format(latestRecordAt!.toLocal()),
              }),
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
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
