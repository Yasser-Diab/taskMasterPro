import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import 'activity_repository.dart';

class ActivityCaptureService {
  ActivityCaptureService({required this.database, required this.repository});

  final AppDatabase database;
  final ActivityRepository repository;
  static const _channel = MethodChannel('taskmasterpro/activity');

  Timer? _timer;
  _ActivitySample? _current;
  DateTime? _segmentStartedAt;
  bool _sampling = false;

  Future<void> start() async {
    if (!Platform.isWindows && !Platform.isAndroid) return;
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
      final settings = await (database.select(
        database.localAppSettings,
      )..where((row) => row.id.equals('app'))).getSingleOrNull();
      if (settings?.applicationTrackingEnabled != true) {
        await _flush(DateTime.now().toUtc(), settings);
        _current = null;
        _segmentStartedAt = null;
        return;
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
      final segmentLong =
          _segmentStartedAt != null &&
          now.difference(_segmentStartedAt!).inSeconds >= 30;
      if (changed || segmentLong) {
        await _flush(now, settings);
        _current = sample;
        _segmentStartedAt = now;
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

  Future<void> _flush(DateTime endedAt, LocalAppSetting? settings) async {
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
    await repository.captureRawSegment(
      startedAt: startedAt,
      endedAt: endedAt,
      sourceType: Platform.isWindows ? 'windows_foreground' : 'android_usage',
      processName: sample.processName,
      windowTitle: sample.windowTitle,
      idleState: sample.idleState,
      packageName: Platform.isAndroid ? sample.processName : null,
      confidence: sample.isTaskMasterWindow ? 1 : 0.75,
      createReview: retainReview && !sample.isTaskMasterWindow,
    );
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _flush(DateTime.now().toUtc(), null);
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
