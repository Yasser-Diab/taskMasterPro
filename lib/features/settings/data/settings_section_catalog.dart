/// Reader-facing settings areas in the product's canonical order.
///
/// Keep this list independent of widgets so tests can prevent the Android and
/// Windows settings navigation from drifting into different groupings.
const settingsSectionOrderKeys = <String>[
  'profile_and_account',
  'schedule_wellbeing',
  'tasks_and_execution',
  'pomodoro',
  'activity_and_privacy',
  'notifications_and_sounds',
  'health',
  'coaching',
  'reports',
  'appearance',
  'synchronization',
  'connected_devices',
  'help_and_diagnostics',
  'about_and_legal',
];

enum SettingsSectionDestination {
  categoryPage,
  scheduleAndWellbeing,
  coachingPreferences,
  notificationsAndSounds,
  health,
}

SettingsSectionDestination settingsSectionDestination(String key) =>
    switch (key) {
      'schedule_wellbeing' => SettingsSectionDestination.scheduleAndWellbeing,
      'coaching' => SettingsSectionDestination.coachingPreferences,
      'notifications_and_sounds' =>
        SettingsSectionDestination.notificationsAndSounds,
      'health' => SettingsSectionDestination.health,
      _ => SettingsSectionDestination.categoryPage,
    };
