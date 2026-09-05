import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Canonical routine requested for the owner of the supplied learning plan.
///
/// The routine is data, not UI state. Stable UUID v5 identities let Windows
/// and Android independently install the same records without producing
/// duplicate templates, rules, or occurrences while they are offline.
@immutable
class OwnerRoutineDefinition {
  const OwnerRoutineDefinition({
    required this.key,
    required this.title,
    required this.frequency,
    required this.weekdays,
    required this.localTime,
    required this.duration,
    required this.executionMode,
    required this.reminderOffset,
    this.resourceName,
    this.resourceUrl,
    this.roadmapTitle,
    this.phaseTitlePrefix,
    this.domainKey = 'learning',
    this.pomodoroFocusDuration,
  });

  final String key;
  final String title;
  final String frequency;
  final List<int> weekdays;
  final String localTime;
  final Duration duration;
  final String executionMode;
  final Duration reminderOffset;
  final String? resourceName;
  final String? resourceUrl;
  final String? roadmapTitle;
  final String? phaseTitlePrefix;
  final String domainKey;
  final Duration? pomodoroFocusDuration;

  int get hour => int.parse(localTime.substring(0, 2));
  int get minute => int.parse(localTime.substring(3, 5));

  /// The canonical settings copied to every generated task occurrence.
  ///
  /// A Pomodoro task's [duration] is its scheduled/planned work window.  The
  /// countdown itself is driven by [pomodoro_focus_ms], so an 09:00-17:30
  /// routine opens with a 25:00 focus interval instead of an 08:30:00 timer.
  /// Builds schedule settings in the account's selected IANA zone. The
  /// catalogue describes local routines, not an Egypt-only calendar; the
  /// caller supplies the owner/device zone when rows are materialized.
  Map<String, Object?> executionSettingsFor(String timeZone) => {
    'completion_method': 'duration',
    'time_zone': timeZone,
    if (pomodoroFocusDuration != null) ...{
      'planned_window_ms': duration.inMilliseconds,
      'pomodoro_focus_ms': pomodoroFocusDuration!.inMilliseconds,
      'short_break_ms': const Duration(minutes: 5).inMilliseconds,
      'long_break_ms': const Duration(minutes: 15).inMilliseconds,
      'long_break_after': 4,
      'pomodoro_auto_start_breaks': false,
      'pomodoro_auto_start_focus': false,
    },
    if (resourceUrl != null) 'suggested_resource': resourceUrl,
  };
}

abstract final class OwnerRoutineCatalog {
  static const sourceFingerprint =
      '2fa186e94f7c1163fa6574ded389cf0b165c76af077779879260338087f01557';
  static const scheduleProvenance = 'source_timebox_and_weekly_schedule';
  static const routineStart = '2026-08-08';

  /// ISO weekdays: Monday=1 through Sunday=7.
  static const nonFridayWeekdays = <int>[1, 2, 3, 4, 6, 7];
  static const saturdayThroughWednesday = <int>[1, 2, 3, 6, 7];

  static const routines = <OwnerRoutineDefinition>[
    OwnerRoutineDefinition(
      key: 'work_non_friday',
      title: 'Daily work routine',
      frequency: 'weekly',
      weekdays: nonFridayWeekdays,
      localTime: '09:00',
      duration: Duration(hours: 8, minutes: 30),
      executionMode: 'pomodoro',
      pomodoroFocusDuration: Duration(minutes: 25),
      reminderOffset: Duration(minutes: 10),
      domainKey: 'work',
    ),
    OwnerRoutineDefinition(
      key: 'german_sat_wed',
      title: 'German structured study',
      frequency: 'weekly',
      weekdays: saturdayThroughWednesday,
      localTime: '06:30',
      duration: Duration(minutes: 40),
      executionMode: 'continuous',
      reminderOffset: Duration(minutes: 10),
      resourceName: 'VHS German A1',
      resourceUrl: 'https://a1.vhs-lernportal.de/',
      roadmapTitle: 'German Professional Fluency',
      phaseTitlePrefix: 'G0',
    ),
    OwnerRoutineDefinition(
      key: 'programming_sat_wed',
      title: 'Programming study',
      frequency: 'weekly',
      weekdays: saturdayThroughWednesday,
      localTime: '19:30',
      duration: Duration(minutes: 90),
      executionMode: 'pomodoro',
      reminderOffset: Duration(minutes: 10),
      resourceName: 'Full-Stack learning workspace',
      resourceUrl: 'https://www.freecodecamp.org/learn/javascript-v9/',
      roadmapTitle: 'Full-Stack Development',
      phaseTitlePrefix: 'P0',
    ),
    OwnerRoutineDefinition(
      key: 'german_thursday',
      title: 'German review',
      frequency: 'weekly',
      weekdays: <int>[4],
      localTime: '06:30',
      duration: Duration(minutes: 40),
      executionMode: 'continuous',
      reminderOffset: Duration(minutes: 10),
      resourceName: 'Goethe German exercises',
      resourceUrl: 'https://www.goethe.de/en/spr/ueb.html',
      roadmapTitle: 'German Professional Fluency',
      phaseTitlePrefix: 'G0',
    ),
    OwnerRoutineDefinition(
      key: 'english_thursday',
      title: 'English correction, listening or pronunciation',
      frequency: 'weekly',
      weekdays: <int>[4],
      localTime: '19:30',
      duration: Duration(minutes: 45),
      executionMode: 'continuous',
      reminderOffset: Duration(minutes: 10),
      resourceName: 'British Council LearnEnglish',
      resourceUrl: 'https://learnenglish.britishcouncil.org/free-resources',
      roadmapTitle: 'English Professional Fluency',
      phaseTitlePrefix: 'E0',
    ),
    OwnerRoutineDefinition(
      key: 'programming_friday',
      title: 'Programming project and documentation',
      frequency: 'weekly',
      weekdays: <int>[5],
      localTime: '08:00',
      duration: Duration(hours: 4),
      executionMode: 'pomodoro',
      reminderOffset: Duration(minutes: 15),
      resourceName: 'Programming project workspace',
      resourceUrl: 'https://github.com/new',
      roadmapTitle: 'Full-Stack Development',
      phaseTitlePrefix: 'P0',
    ),
    OwnerRoutineDefinition(
      key: 'german_friday',
      title: 'German study',
      frequency: 'weekly',
      weekdays: <int>[5],
      localTime: '16:00',
      duration: Duration(minutes: 75),
      executionMode: 'continuous',
      reminderOffset: Duration(minutes: 10),
      resourceName: 'VHS German A1',
      resourceUrl: 'https://a1.vhs-lernportal.de/',
      roadmapTitle: 'German Professional Fluency',
      phaseTitlePrefix: 'G0',
    ),
    OwnerRoutineDefinition(
      key: 'english_friday',
      title: 'English writing or speaking',
      frequency: 'weekly',
      weekdays: <int>[5],
      localTime: '17:30',
      duration: Duration(minutes: 45),
      executionMode: 'continuous',
      reminderOffset: Duration(minutes: 10),
      resourceName: 'Cambridge Write & Improve',
      resourceUrl: 'https://writeandimprove.com/free',
      roadmapTitle: 'English Professional Fluency',
      phaseTitlePrefix: 'E0',
    ),
    OwnerRoutineDefinition(
      key: 'duolingo_german_daily',
      title: 'Duolingo German — 10 minutes',
      frequency: 'daily',
      weekdays: <int>[],
      localTime: '13:00',
      duration: Duration(minutes: 10),
      executionMode: 'habit',
      reminderOffset: Duration(minutes: 5),
      resourceName: 'Duolingo German',
      resourceUrl: 'https://ar.duolingo.com/learn',
      roadmapTitle: 'German Professional Fluency',
      phaseTitlePrefix: 'G0',
    ),
  ];

  static String stableId({
    required String userId,
    required String routineKey,
    required String recordKind,
    String? occurrenceKey,
  }) => const Uuid().v5(
    Namespace.url.value,
    'https://taskmasterpro.app/account/$userId/owner-routine/'
    '$routineKey/$recordKind${occurrenceKey == null ? '' : '/$occurrenceKey'}',
  );
}
