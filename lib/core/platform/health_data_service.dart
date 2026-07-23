import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/supabase_service.dart';

enum HealthProviderStatus {
  unsupported,
  unavailable,
  updateRequired,
  available,
  notConnected,
  permissionRequestInProgress,
  partiallyConnected,
  connected,
  connectedNoRecords,
  connectedDataAvailable,
  permissionDeclined,
  permissionRevoked,
  readFailed,
}

extension HealthProviderStatusX on HealthProviderStatus {
  bool get hasConnection =>
      this == HealthProviderStatus.connected ||
      this == HealthProviderStatus.connectedNoRecords ||
      this == HealthProviderStatus.connectedDataAvailable ||
      this == HealthProviderStatus.partiallyConnected;
}

class HealthDataSummary {
  const HealthDataSummary({
    this.steps = 0,
    this.activeMinutes = 0,
    this.exerciseMinutes = 0,
    this.distanceKilometers = 0,
    this.calories = 0,
    this.lastSleepMinutes,
    this.latestHeartRate,
    this.latestHeartRateAt,
    this.lastReadAt,
    this.lastReadAttempt,
    this.recordCount = 0,
    this.dataSources = const {},
    this.backgroundAccessEnabled = false,
  });

  final int steps;
  final int activeMinutes;
  final int exerciseMinutes;
  final double distanceKilometers;
  final double calories;
  final int? lastSleepMinutes;
  final int? latestHeartRate;
  final DateTime? latestHeartRateAt;
  final DateTime? lastReadAt;
  final DateTime? lastReadAttempt;
  final int recordCount;
  final Set<String> dataSources;
  final bool backgroundAccessEnabled;

  factory HealthDataSummary.fromMap(Map<Object?, Object?> map) {
    int integer(String key) => (map[key] as num?)?.round() ?? 0;
    double decimal(String key) => (map[key] as num?)?.toDouble() ?? 0;
    DateTime? date(String key) => DateTime.tryParse(map[key]?.toString() ?? '');
    return HealthDataSummary(
      steps: integer('steps'),
      activeMinutes: integer('activeMinutes'),
      exerciseMinutes: integer('exerciseMinutes'),
      distanceKilometers: decimal('distanceKilometers'),
      calories: decimal('calories'),
      lastSleepMinutes: map['lastSleepMinutes'] == null
          ? null
          : integer('lastSleepMinutes'),
      latestHeartRate: map['latestHeartRate'] == null
          ? null
          : integer('latestHeartRate'),
      latestHeartRateAt: date('latestHeartRateAt'),
      lastReadAt: date('lastReadAt'),
      lastReadAttempt: date('lastReadAttempt'),
      recordCount: integer('recordCount'),
      dataSources: (map['dataSources'] as List<Object?>? ?? const [])
          .map((value) => '$value')
          .where((value) => value.isNotEmpty)
          .toSet(),
      backgroundAccessEnabled: map['backgroundAccessEnabled'] == true,
    );
  }
}

class HealthDataService extends ChangeNotifier {
  HealthDataService(this._supabase);

  static const _channel = MethodChannel('taskmasterpro/health');
  static const Set<String> _defaultRequestedTypes = {
    'steps',
    'exercise',
    'distance',
    'heart_rate',
    'sleep',
    'calories',
  };

  final SupabaseService _supabase;

  HealthProviderStatus _healthConnectStatus = HealthProviderStatus.unsupported;
  HealthProviderStatus _huaweiStatus = HealthProviderStatus.unsupported;
  Set<String> _grantedTypes = const {};
  Set<String> _requestedTypes = const {};
  Set<String> _grantedPermissions = const {};
  Set<String> _manifestDeclaredPermissions = const {};
  String? _lastPermissionResult;
  String? _lastReadAttempt;
  int _lastRecordCount = 0;
  HealthDataSummary? _summary;
  bool _loading = false;
  String? _error;
  bool _keepDataLocal = false;

  HealthProviderStatus get healthConnectStatus => _healthConnectStatus;
  HealthProviderStatus get huaweiStatus => _huaweiStatus;
  Set<String> get grantedTypes => _grantedTypes;
  Set<String> get requestedTypes => _requestedTypes;
  Set<String> get grantedPermissions => _grantedPermissions;
  Set<String> get manifestDeclaredPermissions => _manifestDeclaredPermissions;
  String? get lastPermissionResult => _lastPermissionResult;
  String? get lastReadAttempt => _lastReadAttempt;
  int get lastRecordCount => _lastRecordCount;
  HealthDataSummary? get summary => _summary;
  bool get loading => _loading;
  String? get error => _error;

  set keepDataLocal(bool value) => _keepDataLocal = value;

  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      _healthConnectStatus = HealthProviderStatus.unsupported;
      _huaweiStatus = HealthProviderStatus.unsupported;
      return;
    }
    await _loadCachedSummary();
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getStatus',
      );
      _applyStatusResult(result);
      _error = null;
    } on Object catch (error) {
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<bool> connectHealthConnect(Set<String> dataTypes) async {
    if (!Platform.isAndroid) return false;
    _loading = true;
    _error = null;
    _healthConnectStatus = HealthProviderStatus.permissionRequestInProgress;
    notifyListeners();
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'requestPermissions',
        {'dataTypes': dataTypes.toList()},
      );
      _applyStatusResult(result);
      if (_healthConnectStatus.hasConnection) {
        await readLatestSummary();
      }
      return _healthConnectStatus.hasConnection;
    } on Object catch (error) {
      _error = error.toString();
      _healthConnectStatus = HealthProviderStatus.readFailed;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<HealthDataSummary?> readLatestSummary() async {
    if (!Platform.isAndroid || !_healthConnectStatus.hasConnection) {
      return null;
    }
    _loading = true;
    _requestedTypes = _requestedTypes.isNotEmpty
        ? _requestedTypes
        : _grantedTypes.isNotEmpty
        ? _grantedTypes
        : _defaultRequestedTypes;
    notifyListeners();
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'readSummary',
        {'dataTypes': _requestedTypes.toList()},
      );
      if (result != null) {
        Set<String> stringSet(String key) =>
            (result[key] as List<Object?>? ?? const [])
                .map((value) => '$value')
                .where((value) => value.isNotEmpty)
                .toSet();
        final returnedRequested = stringSet('requestedTypes');
        final returnedGranted = stringSet('grantedTypes');
        final returnedGrantedPermissions = stringSet('grantedPermissions');
        if (returnedRequested.isNotEmpty) {
          _requestedTypes = returnedRequested;
        }
        if (returnedGranted.isNotEmpty) {
          _grantedTypes = returnedGranted;
        }
        if (returnedGrantedPermissions.isNotEmpty) {
          _grantedPermissions = returnedGrantedPermissions;
        }
        _summary = HealthDataSummary.fromMap(result);
        _lastReadAttempt =
            _summary!.lastReadAttempt?.toIso8601String() ??
            _summary!.lastReadAt?.toIso8601String();
        _lastRecordCount = _summary!.recordCount;
        await _persistSummary(_summary!);
        _healthConnectStatus = _summaryHasRecords(_summary!)
            ? HealthProviderStatus.connectedDataAvailable
            : HealthProviderStatus.connectedNoRecords;
      }
      _error = null;
      return _summary;
    } on Object catch (error) {
      _error = error.toString();
      _healthConnectStatus = HealthProviderStatus.readFailed;
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> openAccessManagement() async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('manageAccess');
    }
  }

  Future<void> disconnectHealthConnect() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('disconnect');
    _summary = null;
    final userId = _supabase.currentUser?.id;
    if (userId != null) {
      await _channel.invokeMethod<void>('deleteCachedSummary', {
        'userId': userId,
      });
    }
    await refreshStatus();
  }

  @visibleForTesting
  static HealthProviderStatus statusFromNative(String? value) =>
      switch (value) {
        'connected_data_available' =>
          HealthProviderStatus.connectedDataAvailable,
        'connected_no_records' => HealthProviderStatus.connectedNoRecords,
        'partially_connected' => HealthProviderStatus.partiallyConnected,
        'connected' => HealthProviderStatus.connected,
        'permission_declined' => HealthProviderStatus.permissionDeclined,
        'permission_denied' => HealthProviderStatus.permissionDeclined,
        'permission_revoked' => HealthProviderStatus.permissionRevoked,
        'read_failed' => HealthProviderStatus.readFailed,
        'available' => HealthProviderStatus.available,
        'not_connected' => HealthProviderStatus.notConnected,
        'update_required' => HealthProviderStatus.updateRequired,
        'unavailable' => HealthProviderStatus.unavailable,
        _ => HealthProviderStatus.unsupported,
      };

  void _applyStatusResult(Map<String, Object?>? result) {
    _healthConnectStatus = statusFromNative(
      result?['healthConnect']?.toString(),
    );
    _huaweiStatus = statusFromNative(result?['huawei']?.toString());
    Set<String> stringSet(String key) =>
        (result?[key] as List<Object?>? ?? const [])
            .map((value) => '$value')
            .where((value) => value.isNotEmpty)
            .toSet();
    final requested = stringSet('requestedTypes');
    _grantedTypes = stringSet('grantedTypes');
    _requestedTypes = requested.isNotEmpty
        ? requested
        : _grantedTypes.isNotEmpty
        ? _grantedTypes
        : _requestedTypes;
    _grantedPermissions = stringSet('grantedPermissions');
    _manifestDeclaredPermissions = stringSet('manifestDeclaredPermissions');
    _lastPermissionResult = result?['lastPermissionResult']?.toString();
  }

  static bool _summaryHasRecords(HealthDataSummary summary) {
    return summary.steps > 0 ||
        summary.exerciseMinutes > 0 ||
        summary.distanceKilometers > 0 ||
        summary.calories > 0 ||
        summary.lastSleepMinutes != null ||
        summary.latestHeartRate != null;
  }

  Future<void> _loadCachedSummary() async {
    final userId = _supabase.currentUser?.id;
    if (!Platform.isAndroid || userId == null) return;
    try {
      final encoded = await _channel.invokeMethod<String>('readCachedSummary', {
        'userId': userId,
      });
      if (encoded == null || encoded.isEmpty) return;
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        _summary = HealthDataSummary.fromMap(decoded);
      }
    } on Object {
      // A corrupt cache is ignored; the next provider read replaces it.
    }
  }

  Future<void> _persistSummary(HealthDataSummary summary) async {
    final user = _supabase.currentUser;
    if (!Platform.isAndroid || user == null) return;
    final values = <String, Object?>{
      'steps': summary.steps,
      'activeMinutes': summary.activeMinutes,
      'exerciseMinutes': summary.exerciseMinutes,
      'distanceKilometers': summary.distanceKilometers,
      'calories': summary.calories,
      'lastSleepMinutes': summary.lastSleepMinutes,
      'latestHeartRate': summary.latestHeartRate,
      'latestHeartRateAt': summary.latestHeartRateAt?.toUtc().toIso8601String(),
      'lastReadAt': summary.lastReadAt?.toUtc().toIso8601String(),
      'lastReadAttempt': summary.lastReadAttempt?.toUtc().toIso8601String(),
      'recordCount': summary.recordCount,
      'dataSources': summary.dataSources.toList(),
      'backgroundAccessEnabled': summary.backgroundAccessEnabled,
    };
    await _channel.invokeMethod<void>('writeCachedSummary', {
      'userId': user.id,
      'summaryJson': jsonEncode(values),
    });
    if (_keepDataLocal) return;
    unawaited(_syncSummary(user.id, summary));
  }

  Future<void> _syncSummary(String userId, HealthDataSummary summary) async {
    final client = _supabase.clientOrNull;
    if (client == null) return;
    final date = (summary.lastReadAt ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .split('T')
        .first;
    final records = <Map<String, Object?>>[
      _summaryRecord(userId, date, 'steps', summary.steps.toDouble(), 'count'),
      _summaryRecord(
        userId,
        date,
        'exercise_minutes',
        summary.exerciseMinutes.toDouble(),
        'minutes',
      ),
      _summaryRecord(
        userId,
        date,
        'distance',
        summary.distanceKilometers,
        'km',
      ),
      if (summary.latestHeartRate != null)
        _summaryRecord(
          userId,
          date,
          'heart_rate',
          summary.latestHeartRate!.toDouble(),
          'bpm',
        ),
      if (summary.lastSleepMinutes != null)
        _summaryRecord(
          userId,
          date,
          'sleep',
          summary.lastSleepMinutes!.toDouble(),
          'minutes',
        ),
    ];
    try {
      await client.from('health_connections').upsert({
        'user_id': userId,
        'device_id': 'android_local',
        'provider': 'health_connect',
        'connection_status': 'connected',
        'granted_data_types': _grantedTypes.toList(),
        'background_access_enabled': summary.backgroundAccessEnabled,
        'last_read_at': summary.lastReadAt?.toUtc().toIso8601String(),
        'last_successful_sync_at': DateTime.now().toUtc().toIso8601String(),
        'last_error': null,
      }, onConflict: 'user_id,device_id,provider');
      await client
          .from('health_records')
          .upsert(
            records,
            onConflict: 'user_id,provider,device_id,source_record_id',
          );
    } on Object catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Map<String, Object?> _summaryRecord(
    String userId,
    String date,
    String type,
    double value,
    String unit,
  ) => {
    'user_id': userId,
    'device_id': 'android_local',
    'provider': 'health_connect',
    'source_record_id': 'daily:$date:$type',
    'data_type': type,
    'started_at': '${date}T00:00:00Z',
    'ended_at': '${date}T23:59:59Z',
    'numeric_value': value,
    'unit': unit,
    'metadata': {'summary': true},
  };
}
