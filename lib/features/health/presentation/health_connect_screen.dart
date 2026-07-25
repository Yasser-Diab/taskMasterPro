import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/providers.dart';
import '../../../core/data/entity_record_repository.dart';

class HealthConnectScreen extends ConsumerStatefulWidget {
  const HealthConnectScreen({super.key});

  @override
  ConsumerState<HealthConnectScreen> createState() =>
      _HealthConnectScreenState();
}

class _HealthConnectScreenState extends ConsumerState<HealthConnectScreen> {
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
  HealthSummary _summary = const HealthSummary();

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (!Platform.isAndroid) {
      setState(() {
        _checking = false;
        _message =
            'Health Connect is available in the Android version of TaskMaster Pro';
      });
      return;
    }
    try {
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _message = 'Health Connect could not be checked: $error';
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
    });
    try {
      final activityPermission = await Permission.activityRecognition.request();
      if (!activityPermission.isGranted) {
        throw StateError(
          'Activity recognition permission is required for steps and exercise',
        );
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
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Permission was not granted: $error');
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
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 7));
      final points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: _types,
      );
      final deduplicated = _health.removeDuplicates(points);
      final summary = HealthSummary.fromPoints(deduplicated);
      await _storeSummary(summary, now);
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Health data could not be read: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _storeSummary(HealthSummary summary, DateTime day) async {
    final repository = ref.read(entityRecordRepositoryProvider);
    final date = DateFormat('yyyy-MM-dd').format(day);
    final records = await repository.list(entityType: 'health_summaries');
    final data = <String, Object?>{
      'summary_date': date,
      'steps': summary.steps,
      'distance_meters': summary.distanceMeters,
      'average_heart_rate': summary.averageHeartRate,
      'sleep_minutes': summary.sleepMinutes,
      'active_calories': summary.activeCalories,
      'workout_count': summary.workoutCount,
      'sources': summary.sources.toList(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final existing = records.where((record) {
      return repository.decode(record)['summary_date'] == date;
    }).firstOrNull;
    if (existing == null) {
      await repository.create(
        EntityRecordDraft(
          entityType: 'health_summaries',
          title: 'Health summary',
          status: 'recorded',
          data: data,
          synchronize: false,
        ),
      );
    } else {
      await repository.update(existing, data: data, synchronize: false);
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
        });
      }
    }
  }

  Future<void> _removeImportedSummaries() async {
    final repository = ref.read(entityRecordRepositoryProvider);
    final records = await repository.list(entityType: 'health_summaries');
    for (final record in records) {
      await repository.softDelete(record, synchronize: false);
    }
    if (mounted) {
      setState(() {
        _summary = const HealthSummary();
        _message = 'Imported health summaries were removed from this device';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Connect')),
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
                              _authorized
                                  ? 'Health Connect is connected'
                                  : 'Connect health context',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              _authorized
                                  ? 'Read-only access is active'
                                  : 'TaskMaster Pro explains the permission before Android opens the system panel',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'With your permission, the app can read steps, exercise, distance, heart rate, sleep, and active calories. Health data is used only for productivity context and is never a medical diagnosis.',
                  ),
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
                            ? 'Continue to Android permissions'
                            : 'Install or update Health Connect',
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
                          label: const Text('Refresh last 7 days'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect'),
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
          if (_authorized) ...[
            Text(
              'Recent health context',
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
                  label: 'Steps',
                  value: NumberFormat.compact().format(_summary.steps),
                ),
                _HealthMetric(
                  icon: Icons.route_outlined,
                  label: 'Distance',
                  value:
                      '${(_summary.distanceMeters / 1000).toStringAsFixed(1)} km',
                ),
                _HealthMetric(
                  icon: Icons.favorite_border,
                  label: 'Average heart rate',
                  value: _summary.averageHeartRate == null
                      ? '—'
                      : '${_summary.averageHeartRate!.round()} bpm',
                ),
                _HealthMetric(
                  icon: Icons.bedtime_outlined,
                  label: 'Sleep',
                  value: '${(_summary.sleepMinutes / 60).toStringAsFixed(1)} h',
                ),
                _HealthMetric(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Active energy',
                  value: '${_summary.activeCalories.round()} kcal',
                ),
                _HealthMetric(
                  icon: Icons.fitness_center_outlined,
                  label: 'Workouts',
                  value: '${_summary.workoutCount}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.source_outlined),
                title: const Text('Available data sources'),
                subtitle: Text(
                  _summary.sources.isEmpty
                      ? 'No records were returned'
                      : _summary.sources.join(', '),
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _removeImportedSummaries,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete imported health summaries'),
            ),
          ],
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

class HealthSummary {
  const HealthSummary({
    this.steps = 0,
    this.distanceMeters = 0,
    this.averageHeartRate,
    this.sleepMinutes = 0,
    this.activeCalories = 0,
    this.workoutCount = 0,
    this.sources = const {},
  });

  factory HealthSummary.fromPoints(List<HealthDataPoint> points) {
    var steps = 0.0;
    var distance = 0.0;
    var sleep = 0.0;
    var calories = 0.0;
    var heartRate = 0.0;
    var heartRateCount = 0;
    var workouts = 0;
    final sources = <String>{};

    for (final point in points) {
      sources.add(point.sourceName);
      final numeric = point.value is NumericHealthValue
          ? (point.value as NumericHealthValue).numericValue.toDouble()
          : null;
      switch (point.type) {
        case HealthDataType.STEPS:
          steps += numeric ?? 0;
        case HealthDataType.DISTANCE_DELTA:
          distance += numeric ?? 0;
        case HealthDataType.HEART_RATE:
          if (numeric != null) {
            heartRate += numeric;
            heartRateCount++;
          }
        case HealthDataType.SLEEP_ASLEEP:
          sleep += numeric ?? 0;
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          calories += numeric ?? 0;
        case HealthDataType.WORKOUT:
          workouts++;
        default:
          break;
      }
    }
    return HealthSummary(
      steps: steps.round(),
      distanceMeters: distance,
      averageHeartRate: heartRateCount == 0 ? null : heartRate / heartRateCount,
      sleepMinutes: sleep,
      activeCalories: calories,
      workoutCount: workouts,
      sources: sources,
    );
  }

  final int steps;
  final double distanceMeters;
  final double? averageHeartRate;
  final double sleepMinutes;
  final double activeCalories;
  final int workoutCount;
  final Set<String> sources;
}
