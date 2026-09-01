import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/health/data/synced_health_overview.dart';

void main() {
  test('uses one freshest metric per newest health day', () {
    final overview = SyncedHealthOverview.fromEntries([
      _entry('2026-08-23', 'steps', 500),
      _entry('2026-08-24', 'steps', 700, minute: 1),
      _entry('2026-08-24', 'steps', 738, minute: 2),
      _entry('2026-08-23', 'active_calories', 103.51435058326157),
      _entry('2026-08-24', 'active_calories', 31.0),
      _entry('2026-08-23', 'exercise_sessions', 2),
      _entry('2026-08-24', 'exercise_sessions', 3),
    ]);

    expect(overview, isNotNull);
    expect(overview!.value('steps'), 738);
    expect(overview.value('active_calories'), 31.0);
    expect(overview.weeklySteps.map((entry) => entry.value), [500, 738]);
    expect(overview.weeklyWorkoutCount, 5);
  });

  test('weekly workout count uses only the freshest value for each day', () {
    final overview = SyncedHealthOverview.fromEntries([
      _entry('2026-08-23', 'steps', 500),
      _entry('2026-08-23', 'exercise_sessions', 2, minute: 1),
      _entry('2026-08-23', 'exercise_sessions', 3, minute: 2),
      _entry('2026-08-24', 'exercise_sessions', 1),
    ]);

    expect(overview?.weeklyWorkoutCount, 4);
  });

  test('formats synchronized metric precision for people', () {
    expect(
      formatSyncedHealthNumber(
        'average_heart_rate',
        78.38167938931298,
        locale: 'en',
      ),
      '78 bpm',
    );
    expect(
      formatSyncedHealthNumber('distance', 1276.2079999999999, locale: 'en'),
      '1,276 m',
    );
    expect(
      formatSyncedHealthNumber(
        'active_calories',
        103.51435058326157,
        locale: 'en',
      ),
      '104 kcal',
    );
  });

  test('removes package identifiers from an existing synchronized source', () {
    final overview = SyncedHealthOverview.fromEntries([
      SyncedHealthEntry(
        summaryDate: DateTime.parse('2026-08-27'),
        updatedAt: DateTime.parse('2026-08-27T06:10:00Z'),
        type: 'steps',
        value: 2952,
        source:
            'Nothing X, com.android.healthconnect.phone.j1cbd7fde659a3cc79f852f59ea55f398',
      ),
    ]);

    expect(overview?.source, 'Nothing X');
  });
}

SyncedHealthEntry _entry(
  String date,
  String type,
  num value, {
  int minute = 0,
}) => SyncedHealthEntry(
  summaryDate: DateTime.parse(date),
  updatedAt: DateTime.parse(
    '${date}T12:${minute.toString().padLeft(2, '0')}:00Z',
  ),
  type: type,
  value: value,
  source: 'Nothing X',
);
