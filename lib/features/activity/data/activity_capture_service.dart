import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import 'activity_repository.dart';

/// Broad device-use tracking is optional, but a task that is actively running
/// must still collect its own local Activity.  Otherwise the user can start a
/// task, work in another application, and be shown an empty task-Activity
/// screen simply because they chose not to retain unrelated device usage.
bool shouldCaptureActivity({
  required bool broadTrackingEnabled,
  String? activeTaskId,
  String? runtimeState,
}) {
  if (broadTrackingEnabled) return true;
  if (activeTaskId == null) return false;
  return const {
    'running',
    'focus_running',
    'break_running',
  }.contains(runtimeState);
}

class ActivityCaptureService {
  ActivityCaptureService({required this.database, required this.repository});

  final AppDatabase database;
  final ActivityRepository repository;
  static const _channel = MethodChannel('taskmasterpro/activity');

  Timer? _timer;
  _ActivitySample? _current;
  DateTime? _segmentStartedAt;
  DateTime? _lastSegmentUpdateAt;
  String? _currentSegmentId;
  String? _androidHistorySessionId;
  DateTime? _lastAndroidHistoryLookupAt;
  bool _sampling = false;

  Future<void> start() async {
    if (!Platform.isWindows && !Platform.isAndroid) return;
    await repository.purgeExpiredLocalActivity();
    _timer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_sample()),
    );
    await _sample();
  }

  Future<bool> hasAndroidUsageAccess() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
  }

  Future<void> openAndroidUsageAccess() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openUsageAccess');
  }

  Future<void> _sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final settings =
          await (database.select(database.localAppSettings)
                ..where((row) => row.id.equals(repository.settingsId)))
              .getSingleOrNull();
      final runtime =
          await (database.select(database.localRuntimeStates)
                ..where((row) => row.userId.equals(repository.currentUserId)))
              .getSingleOrNull();
      if (!shouldCaptureActivity(
        broadTrackingEnabled: settings?.applicationTrackingEnabled == true,
        activeTaskId: runtime?.activeTaskId,
        runtimeState: runtime?.state,
      )) {
        await _flush(DateTime.now().toUtc(), settings, isFinalized: true);
        _current = null;
        _segmentStartedAt = null;
        _lastSegmentUpdateAt = null;
        _currentSegmentId = null;
        return;
      }
      if (Platform.isAndroid) {
        await _captureRecentAndroidForegroundPeriods(
          settings: settings,
          runtime: runtime,
        );
      }
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'sampleForegroundActivity',
      );
      if (raw == null) return;
      final process =
          raw['packageName'] as String? ??
          raw['applicationName'] as String? ??
          '';
      if (process.isEmpty) return;
      final windowTitle = settings?.windowTitleTrackingEnabled == true
          ? raw['windowTitle'] as String?
          : null;
      final idleSeconds = (raw['idleSeconds'] as num?)?.toInt() ?? 0;
      final technicalIdle =
          settings?.idleDetectionEnabled == true &&
          idleSeconds >= (settings?.idleThresholdSeconds ?? 30);
      final sample = _ActivitySample(
        applicationName: raw['applicationName'] as String? ?? process,
        processName: process,
        windowTitle: windowTitle,
        idleState: technicalIdle ? 'technical_idle' : 'active',
        isTaskMasterWindow: raw['isTaskMasterWindow'] == true,
      );
      final now = DateTime.now().toUtc();
      final changed = _current?.signature != sample.signature;
      // The samples themselves remain local. A stable normalized Activity
      // segment is extended at a restrained interval instead of creating a
      // new segment for every foreground poll or 30-second bucket.
      final segmentUpdateDue =
          _lastSegmentUpdateAt != null &&
          now.difference(_lastSegmentUpdateAt!).inSeconds >= 15;
      if (changed) {
        await _flush(now, settings, isFinalized: true);
        _current = sample;
        _segmentStartedAt = now;
        _lastSegmentUpdateAt = null;
        _currentSegmentId = null;
      } else if (_currentSegmentId == null || segmentUpdateDue) {
        await _flush(now, settings, isFinalized: false);
        _lastSegmentUpdateAt = now;
      }
    } on MissingPluginException {
      _timer?.cancel();
      _timer = null;
    } on PlatformException {
      // Capture is permission-dependent. The next compact sample retries.
    } finally {
      _sampling = false;
    }
  }

  /// Backfills normalized foreground periods after Android resumes this app.
  /// Flutter timers can be paused while another Android app is foregrounded;
  /// UsageEvents supplies the completed, privacy-safe interval when the user
  /// returns.  A stable segment ID makes overlapping lookups idempotent.
  Future<void> _captureRecentAndroidForegroundPeriods({
    required LocalAppSetting? settings,
    required LocalRuntime? runtime,
  }) async {
    final sessionKey = runtime?.sessionId ?? runtime?.activeTaskId;
    if (sessionKey == null) return;
    if (_androidHistorySessionId != sessionKey) {
      _androidHistorySessionId = sessionKey;
      _lastAndroidHistoryLookupAt = runtime?.segmentStartedAt?.toUtc();
    }
    final now = DateTime.now().toUtc();
    final sixHoursAgo = now.subtract(const Duration(hours: 6));
    final requestedSince =
        _lastAndroidHistoryLookupAt ??
        runtime?.segmentStartedAt?.toUtc() ??
        now;
    final since = requestedSince.isBefore(sixHoursAgo)
        ? sixHoursAgo
        : requestedSince;
    final periods =
        await _channel.invokeListMethod<Object?>(
          'recentForegroundActivityPeriods',
          <String, Object?>{'sinceMillis': since.millisecondsSinceEpoch},
        ) ??
        const <Object?>[];
    _lastAndroidHistoryLookupAt = now;
    for (final value in periods) {
      if (value is! Map) continue;
      final period = <String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
      final process =
          period['packageName'] as String? ??
          period['applicationName'] as String? ??
          '';
      final startedMillis = (period['startedAt'] as num?)?.toInt();
      final endedMillis = (period['endedAt'] as num?)?.toInt();
      if (process.isEmpty || startedMillis == null || endedMillis == null) {
        continue;
      }
      final startedAt = DateTime.fromMillisecondsSinceEpoch(
        startedMillis,
        isUtc: true,
      );
      final endedAt = DateTime.fromMillisecondsSinceEpoch(
        endedMillis,
        isUtc: true,
      );
      if (!endedAt.isAfter(startedAt) ||
          endedAt.difference(startedAt).inMilliseconds < 900) {
        continue;
      }
      final retainReview = settings?.retainUnclassifiedActivity != false;
      await repository.captureRawSegment(
        // The period's immutable Android boundaries make a repeated lookup an
        // update, never an additional Activity card.
        segmentId: 'android-history-$process-$startedMillis-$endedMillis',
        startedAt: startedAt,
        endedAt: endedAt,
        sourceType: 'android_usage_history',
        processName: process,
        packageName: process,
        idleState: 'active',
        confidence: 0.85,
        createReview: retainReview,
        isFinalized: true,
      );
    }
  }

  Future<void> _flush(
    DateTime endedAt,
    LocalAppSetting? settings, {
    required bool isFinalized,
  }) async {
    final sample = _current;
    final startedAt = _segmentStartedAt;
    if (sample == null ||
        startedAt == null ||
        endedAt.difference(startedAt).inMilliseconds < 900) {
      return;
    }
    final isIdle = sample.idleState == 'technical_idle';
    final retainReview = isIdle
        ? settings?.retainTechnicalIdle != false
        : settings?.retainUnclassifiedActivity != false;
    _currentSegmentId = await repository.captureRawSegment(
      segmentId: _currentSegmentId,
      startedAt: startedAt,
      endedAt: endedAt,
      sourceType: Platform.isWindows ? 'windows_foreground' : 'android_usage',
      processName: sample.processName,
      windowTitle: sample.windowTitle,
      idleState: sample.idleState,
      packageName: Platform.isAndroid ? sample.processName : null,
      confidence: sample.isTaskMasterWindow ? 1 : 0.75,
      createReview: retainReview && !sample.isTaskMasterWindow,
      isFinalized: isFinalized,
    );
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _flush(DateTime.now().toUtc(), null, isFinalized: true);
  }
}

class _ActivitySample {
  const _ActivitySample({
    required this.applicationName,
    required this.processName,
    required this.windowTitle,
    required this.idleState,
    required this.isTaskMasterWindow,
  });

  final String applicationName;
  final String processName;
  final String? windowTitle;
  final String idleState;
  final bool isTaskMasterWindow;

  String get signature =>
      '$processName|${windowTitle ?? ''}|$idleState|$isTaskMasterWindow';
}
