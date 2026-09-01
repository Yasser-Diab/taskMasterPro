import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:taskmaster_pro/features/health/data/android_health_workout_reader.dart';

void main() {
  test('native Health Connect exercise session becomes a workout point', () {
    final point = androidWorkoutSessionToHealthDataPoint(<String, Object?>{
      'uuid': 'exercise-1',
      'startMillis': 1_000,
      'endMillis': 421_000,
      'sourcePackage': 'com.nothing.smartcenter',
      'recordingMethod': 1,
      'exerciseType': 56,
    });

    expect(point, isNotNull);
    expect(point!.uuid, 'exercise-1');
    expect(point.type, HealthDataType.WORKOUT);
    expect(point.sourceName, 'com.nothing.smartcenter');
    expect(point.dateTo.difference(point.dateFrom), const Duration(minutes: 7));
  });

  test('invalid native workout rows are discarded', () {
    expect(
      androidWorkoutSessionToHealthDataPoint(<String, Object?>{
        'uuid': 'exercise-1',
        'startMillis': 1_000,
        'endMillis': 1_000,
        'sourcePackage': 'com.nothing.smartcenter',
      }),
      isNull,
    );
  });
}
