import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  late List<Object?> plans;
  late List<Object?> schedules;

  setUpAll(() {
    sql = File('tool/seed_v0027_owner_learning_plan.sql').readAsStringSync();
    plans = _decodeDollarQuotedJson(sql, 'plans');
    schedules = _decodeDollarQuotedJson(sql, 'schedules');
  });

  test('binds the verified owner and v0.0.27 plan start', () {
    expect(sql, contains('4bd3e32d-1dcd-48ed-9f64-9099675047f1'));
    expect(sql, contains("plan_start constant date := date '2026-08-01'"));
    expect(sql, contains("installed_release constant text := '0.0.27'"));
    expect(sql, isNot(contains('0.0.26')));
    expect(sql, contains('from auth.users account'));
  });

  test('contains the complete programming and German roadmap hierarchy', () {
    expect(plans, hasLength(2));
    final plansByKey = <String, Map<String, Object?>>{
      for (final rawPlan in plans)
        (rawPlan! as Map<String, Object?>)['key']! as String:
            rawPlan as Map<String, Object?>,
    };

    final programming = plansByKey['full_stack_programming']!;
    final german = plansByKey['german_professional_fluency']!;
    expect(programming['title'], 'Full-Stack Programming');
    expect(german['title'], 'German Professional Fluency');
    expect(programming['weekly_target_hours'], '11–12');
    expect(german['weekly_target_hours'], '6–7');
    expect(programming['full_stack_open_cost'], 'Free');

    final programmingPhases = programming['phases']! as List<Object?>;
    final germanPhases = german['phases']! as List<Object?>;
    expect(programmingPhases, hasLength(9));
    expect(germanPhases, hasLength(6));
    expect(_taskCount(programming), 123);
    expect(_taskCount(german), 40);
    expect(
      programmingPhases
          .map((phase) => (phase! as Map<String, Object?>)['key'])
          .toList(),
      <String>['p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'],
    );
    expect(
      germanPhases
          .map((phase) => (phase! as Map<String, Object?>)['key'])
          .toList(),
      <String>['g0', 'g1', 'g2', 'g3', 'g4', 'g5'],
    );
  });

  test('every roadmap task has a usable resource and execution method', () {
    const supportedModes = <String>{
      'checklist',
      'continuous',
      'habit',
      'pomodoro',
    };
    var taskCount = 0;
    var checkpointCount = 0;

    for (final rawPlan in plans) {
      final plan = rawPlan! as Map<String, Object?>;
      for (final rawPhase in plan['phases']! as List<Object?>) {
        final phase = rawPhase! as Map<String, Object?>;
        checkpointCount += (phase['checkpoints']! as List<Object?>).length;
        for (final rawTask in phase['tasks']! as List<Object?>) {
          final task = rawTask! as Map<String, Object?>;
          taskCount += 1;
          expect((task['title']! as String).trim(), isNotEmpty);
          expect((task['resource_name']! as String).trim(), isNotEmpty);
          expect(
            Uri.parse(task['url']! as String).isScheme('https'),
            isTrue,
            reason: '${task['title']} must use an HTTPS resource',
          );
          expect(task['minutes']! as num, greaterThan(0));
          expect(supportedModes, contains(task['mode']));
        }
      }
    }

    expect(taskCount, 163);
    expect(checkpointCount, 79);
  });

  test('recurring timetable is sustainable and phase-resolvable', () {
    expect(schedules, hasLength(11));
    final plansByKey = <String, Map<String, Object?>>{
      for (final rawPlan in plans)
        (rawPlan! as Map<String, Object?>)['key']! as String:
            rawPlan as Map<String, Object?>,
    };
    final scheduleByKey = <String, Map<String, Object?>>{
      for (final rawSchedule in schedules)
        (rawSchedule! as Map<String, Object?>)['key']! as String:
            rawSchedule as Map<String, Object?>,
    };
    var recurringResourceCount = 0;

    for (final rawSchedule in schedules) {
      final schedule = rawSchedule! as Map<String, Object?>;
      recurringResourceCount += 1;
      final roadmap = plansByKey[schedule['roadmap']]!;
      final phases = roadmap['phases']! as List<Object?>;
      expect(
        phases.any(
          (phase) =>
              (phase! as Map<String, Object?>)['key'] == schedule['phase'],
        ),
        isTrue,
        reason: '${schedule['key']} must target an existing phase',
      );
      expect(Uri.parse(schedule['url']! as String).isScheme('https'), isTrue);
      expect(schedule['minutes']! as num, greaterThan(0));
      expect(schedule['reminder']! as num, greaterThanOrEqualTo(0));
      for (final rawResource
          in (schedule['additional_resources'] as List<Object?>?) ??
              const <Object?>[]) {
        final resource = rawResource! as Map<String, Object?>;
        recurringResourceCount += 1;
        expect((resource['name']! as String).trim(), isNotEmpty);
        expect(Uri.parse(resource['url']! as String).isScheme('https'), isTrue);
      }
    }
    expect(recurringResourceCount, 14);

    expect(scheduleByKey['german_structured_workdays']!['weekdays'], <Object?>[
      1,
      2,
      3,
      6,
      7,
    ]);
    expect(scheduleByKey['german_structured_workdays']!['time'], '06:30');
    expect(scheduleByKey['german_structured_workdays']!['minutes'], 30);
    expect(scheduleByKey['programming_hsoub_sat_mon']!['weekdays'], <Object?>[
      1,
      6,
    ]);
    expect(scheduleByKey['programming_hsoub_sat_mon']!['time'], '19:30');
    expect(scheduleByKey['programming_fcc_sun_tue']!['weekdays'], <Object?>[
      2,
      7,
    ]);
    expect(scheduleByKey['programming_fcc_sun_tue']!['time'], '19:30');
    expect(scheduleByKey['programming_wednesday_project']!['time'], '19:30');
    expect(
      scheduleByKey['german_thursday_listening_speaking']!['time'],
      '19:30',
    );
    expect(scheduleByKey['german_daily_duolingo']!['frequency'], 'daily');
    expect(scheduleByKey['german_daily_duolingo']!['minutes'], 10);
    expect(scheduleByKey['programming_friday_main_project']!['time'], '08:00');
    expect(scheduleByKey['programming_friday_course_docs']!['time'], '10:30');
    expect(scheduleByKey['german_friday_structured_study']!['time'], '16:00');
    expect(scheduleByKey['german_friday_speaking']!['time'], '18:00');
  });

  test('seed writes every production hierarchy and resource table', () {
    for (final table in <String>[
      'public.roadmaps',
      'public.roadmap_progress_rules',
      'public.roadmap_phases',
      'public.roadmap_milestones',
      'public.roadmap_checkpoints',
      'public.task_occurrences',
      'public.roadmap_task_links',
      'public.task_resources',
      'public.task_templates',
      'public.recurrence_rules',
      'public.task_reminders',
    ]) {
      expect(sql, contains(table));
    }
    expect(sql, contains("'open_mode', 'task_browser'"));
  });
}

List<Object?> _decodeDollarQuotedJson(String sql, String variableName) {
  final match = RegExp(
    '$variableName constant jsonb := '
    r'\$'
    '$variableName'
    r'\$([\s\S]*?)\$'
    '$variableName'
    r'\$::jsonb',
  ).firstMatch(sql);
  expect(match, isNotNull, reason: 'Missing $variableName JSON block');
  return jsonDecode(match!.group(1)!)! as List<Object?>;
}

int _taskCount(Map<String, Object?> plan) {
  return (plan['phases']! as List<Object?>).fold<int>(
    0,
    (count, rawPhase) =>
        count +
        ((rawPhase! as Map<String, Object?>)['tasks']! as List<Object?>).length,
  );
}
