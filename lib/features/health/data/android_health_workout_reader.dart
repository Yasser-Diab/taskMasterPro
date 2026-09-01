import 'dart:io';

import 'package:flutter/services.dart';
import 'package:health/health.dart';

class AndroidHealthWorkoutReader {
  const AndroidHealthWorkoutReader();

  static const _channel = MethodChannel('dayvector/health_workouts');

  Future<List<HealthDataPoint>> readSessions({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!Platform.isAndroid) return const [];
    final rows = await _channel
        .invokeMethod<List<Object?>>('readWorkoutSessions', <String, Object?>{
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
        });
    if (rows == null) return const [];
    return rows
        .map(androidWorkoutSessionToHealthDataPoint)
        .whereType<HealthDataPoint>()
        .toList(growable: false);
  }
}

HealthDataPoint? androidWorkoutSessionToHealthDataPoint(Object? value) {
  if (value is! Map) return null;
  final row = Map<Object?, Object?>.from(value);
  final uuid = row['uuid']?.toString().trim() ?? '';
  final startMillis = (row['startMillis'] as num?)?.toInt();
  final endMillis = (row['endMillis'] as num?)?.toInt();
  final sourcePackage = row['sourcePackage']?.toString().trim() ?? '';
  if (uuid.isEmpty ||
      sourcePackage.isEmpty ||
      startMillis == null ||
      endMillis == null ||
      startMillis >= endMillis) {
    return null;
  }
  final recordingMethod = (row['recordingMethod'] as num?)?.toInt();
  return HealthDataPoint(
    uuid: uuid,
    value: WorkoutHealthValue(
      workoutActivityType: HealthWorkoutActivityType.OTHER,
    ),
    type: HealthDataType.WORKOUT,
    unit: HealthDataUnit.MINUTE,
    dateFrom: DateTime.fromMillisecondsSinceEpoch(startMillis),
    dateTo: DateTime.fromMillisecondsSinceEpoch(endMillis),
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    sourceDeviceId: '',
    sourceId: sourcePackage,
    sourceName: sourcePackage,
    recordingMethod: RecordingMethod.fromInt(recordingMethod),
    metadata: <String, Object?>{'nativeExerciseType': row['exerciseType']},
  );
}
