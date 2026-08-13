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
  'privacy_and_vault',
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

enum CanonicalSettingType { boolean, integer, decimal, text, choice, duration }

enum CanonicalSettingScope { account, device, task }

class CanonicalSettingDefinition {
  const CanonicalSettingDefinition({
    required this.key,
    required this.sectionKey,
    required this.type,
    required this.scope,
    required this.defaultValue,
    this.taskOverrideAllowed = false,
    this.deviceOverrideAllowed = false,
  });

  final String key;
  final String sectionKey;
  final CanonicalSettingType type;
  final CanonicalSettingScope scope;
  final Object defaultValue;
  final bool taskOverrideAllowed;
  final bool deviceOverrideAllowed;
}

/// Single metadata authority for settings linked from feature screens.
const canonicalSettingsRegistry = <CanonicalSettingDefinition>[
  CanonicalSettingDefinition(
    key: 'appearance.theme',
    sectionKey: 'appearance',
    type: CanonicalSettingType.choice,
    scope: CanonicalSettingScope.account,
    defaultValue: 'system',
    deviceOverrideAllowed: true,
  ),
  CanonicalSettingDefinition(
    key: 'regional.time_zone',
    sectionKey: 'schedule_wellbeing',
    type: CanonicalSettingType.text,
    scope: CanonicalSettingScope.account,
    defaultValue: 'UTC',
    deviceOverrideAllowed: true,
  ),
  CanonicalSettingDefinition(
    key: 'notifications.sound',
    sectionKey: 'notifications_and_sounds',
    type: CanonicalSettingType.choice,
    scope: CanonicalSettingScope.account,
    defaultValue: 'system',
    deviceOverrideAllowed: true,
  ),
  CanonicalSettingDefinition(
    key: 'activity.application_tracking',
    sectionKey: 'activity_and_privacy',
    type: CanonicalSettingType.boolean,
    scope: CanonicalSettingScope.device,
    defaultValue: true,
  ),
  CanonicalSettingDefinition(
    key: 'activity.detailed_sync',
    sectionKey: 'activity_and_privacy',
    type: CanonicalSettingType.boolean,
    scope: CanonicalSettingScope.account,
    defaultValue: false,
  ),
  CanonicalSettingDefinition(
    key: 'activity.rule_sync',
    sectionKey: 'activity_and_privacy',
    type: CanonicalSettingType.boolean,
    scope: CanonicalSettingScope.account,
    defaultValue: true,
  ),
  CanonicalSettingDefinition(
    key: 'pomodoro.focus_duration',
    sectionKey: 'pomodoro',
    type: CanonicalSettingType.duration,
    scope: CanonicalSettingScope.account,
    defaultValue: 1500000,
    taskOverrideAllowed: true,
  ),
  CanonicalSettingDefinition(
    key: 'vault.credential_saving',
    sectionKey: 'privacy_and_vault',
    type: CanonicalSettingType.boolean,
    scope: CanonicalSettingScope.account,
    defaultValue: true,
  ),
  CanonicalSettingDefinition(
    key: 'vault.autofill',
    sectionKey: 'privacy_and_vault',
    type: CanonicalSettingType.boolean,
    scope: CanonicalSettingScope.account,
    defaultValue: true,
  ),
  CanonicalSettingDefinition(
    key: 'vault.auto_lock',
    sectionKey: 'privacy_and_vault',
    type: CanonicalSettingType.duration,
    scope: CanonicalSettingScope.account,
    defaultValue: 300000,
    deviceOverrideAllowed: true,
  ),
];

CanonicalSettingDefinition canonicalSetting(String key) =>
    canonicalSettingsRegistry.singleWhere((setting) => setting.key == key);

bool hasDuplicateCanonicalSettings() {
  final keys = canonicalSettingsRegistry.map((setting) => setting.key).toList();
  return keys.toSet().length != keys.length;
}

enum SettingsSectionDestination {
  categoryPage,
  scheduleAndWellbeing,
  coachingPreferences,
  notificationsAndSounds,
  health,
  vault,
  connectedDevices,
}

SettingsSectionDestination settingsSectionDestination(String key) =>
    switch (key) {
      'schedule_wellbeing' => SettingsSectionDestination.scheduleAndWellbeing,
      'coaching' => SettingsSectionDestination.coachingPreferences,
      'notifications_and_sounds' =>
        SettingsSectionDestination.notificationsAndSounds,
      'health' => SettingsSectionDestination.health,
      'privacy_and_vault' => SettingsSectionDestination.vault,
      'connected_devices' => SettingsSectionDestination.connectedDevices,
      _ => SettingsSectionDestination.categoryPage,
    };
