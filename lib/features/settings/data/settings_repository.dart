import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity.dart';

class SettingsRepository {
  SettingsRepository(this.database, [this.client]);

  final AppDatabase database;
  final SupabaseClient? client;
  static const _uuid = Uuid();

  Stream<LocalAppSetting?> watchSettings() {
    return (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals('app'))).watchSingleOrNull();
  }

  Stream<LocalProfile?> watchProfile(String userId) {
    return (database.select(
      database.localProfiles,
    )..where((row) => row.userId.equals(userId))).watchSingleOrNull();
  }

  Future<void> ensureLocalAccount(User user) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    await database.transaction(() async {
      final existingProfile = await (database.select(
        database.localProfiles,
      )..where((row) => row.userId.equals(user.id))).getSingleOrNull();
      if (existingProfile == null) {
        await database
            .into(database.localProfiles)
            .insert(
              LocalProfilesCompanion.insert(
                id: user.id,
                userId: user.id,
                displayName: Value(
                  user.userMetadata?['display_name'] as String? ??
                      user.userMetadata?['full_name'] as String? ??
                      '',
                ),
                email: Value(user.email),
                imagePath: Value(
                  user.userMetadata?['avatar_url'] as String? ??
                      user.userMetadata?['picture'] as String?,
                ),
                createdAt: now,
                updatedAt: now,
                updatedByDeviceId: Value(deviceId),
              ),
            );
      }
      final settings = await (database.select(
        database.localAppSettings,
      )..where((row) => row.id.equals('app'))).getSingleOrNull();
      if (settings == null) {
        await database
            .into(database.localAppSettings)
            .insert(
              LocalAppSettingsCompanion.insert(
                id: 'app',
                userId: Value(user.id),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
  }

  Future<void> updateTheme(String themeKey) {
    return _update(LocalAppSettingsCompanion(themeKey: Value(themeKey)));
  }

  Future<void> updateLocale(String localeCode) {
    return _update(LocalAppSettingsCompanion(localeCode: Value(localeCode)));
  }

  Future<void> updateNotificationSound(String soundKey) {
    return _update(
      LocalAppSettingsCompanion(notificationSoundKey: Value(soundKey)),
    );
  }

  Future<void> updateHealthConnectEnabled(bool enabled) {
    return _update(
      LocalAppSettingsCompanion(healthConnectEnabled: Value(enabled)),
    );
  }

  Future<void> updateCyclePreferences({bool? enabled, String? storageMode}) {
    return _update(
      LocalAppSettingsCompanion(
        cycleTrackingEnabled: Value.absentIfNull(enabled),
        cycleStorageMode: Value.absentIfNull(storageMode),
      ),
    );
  }

  Future<void> updateCalendarShowCompleted(bool value) {
    return _update(
      LocalAppSettingsCompanion(calendarShowCompleted: Value(value)),
    );
  }

  Future<void> updateAttributionSetting({
    bool? detectBreakActivity,
    bool? detectCrossTaskActivity,
    bool? automaticTrustedRules,
    bool? retainUnclassifiedActivity,
    bool? retainTechnicalIdle,
    bool? activitySyncEnabled,
  }) {
    return _update(
      LocalAppSettingsCompanion(
        detectBreakActivity: Value.absentIfNull(detectBreakActivity),
        detectCrossTaskActivity: Value.absentIfNull(detectCrossTaskActivity),
        automaticTrustedRules: Value.absentIfNull(automaticTrustedRules),
        retainUnclassifiedActivity: Value.absentIfNull(
          retainUnclassifiedActivity,
        ),
        retainTechnicalIdle: Value.absentIfNull(retainTechnicalIdle),
        activitySyncEnabled: Value.absentIfNull(activitySyncEnabled),
      ),
    );
  }

  Future<void> updateTrackingSettings({
    bool? applications,
    bool? windowTitles,
    bool? idleDetection,
    int? idleThresholdSeconds,
  }) {
    return _update(
      LocalAppSettingsCompanion(
        applicationTrackingEnabled: Value.absentIfNull(applications),
        windowTitleTrackingEnabled: Value.absentIfNull(windowTitles),
        idleDetectionEnabled: Value.absentIfNull(idleDetection),
        idleThresholdSeconds: Value.absentIfNull(idleThresholdSeconds),
      ),
    );
  }

  Future<void> completeOnboarding({
    required String userId,
    required String displayName,
  }) async {
    final profile = await (database.select(
      database.localProfiles,
    )..where((row) => row.userId.equals(userId))).getSingle();
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    await database.transaction(() async {
      await (database.update(
        database.localProfiles,
      )..where((row) => row.userId.equals(userId))).write(
        LocalProfilesCompanion(
          displayName: Value(displayName.trim()),
          onboardingCompleted: const Value(true),
          revision: Value(profile.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await database
          .into(database.localOutboxCommands)
          .insert(
            LocalOutboxCommandsCompanion.insert(
              commandId: commandId,
              userId: userId,
              deviceId: deviceId,
              deviceSequence: sequence,
              entityType: 'profiles',
              entityId: profile.id,
              commandType: 'update',
              baseRevision: profile.revision,
              payloadJson: jsonEncode({
                'display_name': displayName.trim(),
                'onboarding_completed_at': now.toIso8601String(),
              }),
              clientTimestamp: now,
              createdAt: now,
            ),
          );
    });
  }

  Future<void> updateProfile({
    required String userId,
    required String displayName,
    String? genderIdentity,
    String? localImagePath,
    String? remoteImagePath,
  }) async {
    final profile = await (database.select(
      database.localProfiles,
    )..where((row) => row.userId.equals(userId))).getSingle();
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final sequence = await DeviceIdentity.nextSequence();
    final commandId = _uuid.v4();
    final normalizedGender = genderIdentity?.trim();
    final payload = <String, Object?>{
      'display_name': displayName.trim(),
      'gender_identity': normalizedGender?.isEmpty == true
          ? null
          : normalizedGender,
    };
    if (remoteImagePath != null) {
      payload['profile_image_path'] = remoteImagePath;
    }
    await database.transaction(() async {
      await (database.update(
        database.localProfiles,
      )..where((row) => row.id.equals(profile.id))).write(
        LocalProfilesCompanion(
          displayName: Value(displayName.trim()),
          genderIdentity: Value(
            normalizedGender?.isEmpty == true ? null : normalizedGender,
          ),
          imagePath: localImagePath == null
              ? const Value.absent()
              : Value(localImagePath),
          revision: Value(profile.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await database
          .into(database.localOutboxCommands)
          .insert(
            LocalOutboxCommandsCompanion.insert(
              commandId: commandId,
              userId: userId,
              deviceId: deviceId,
              deviceSequence: sequence,
              entityType: 'profiles',
              entityId: profile.id,
              commandType: 'update',
              baseRevision: profile.revision,
              payloadJson: jsonEncode(payload),
              clientTimestamp: now,
              createdAt: now,
            ),
          );
    });

    await client?.auth.updateUser(
      UserAttributes(data: {'display_name': displayName.trim()}),
    );
  }

  Future<void> _update(LocalAppSettingsCompanion changes) async {
    final current = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals('app'))).getSingle();
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence();
    await database.transaction(() async {
      await (database.update(
        database.localAppSettings,
      )..where((row) => row.id.equals('app'))).write(
        changes.copyWith(
          revision: Value(current.revision + 1),
          updatedAt: Value(now),
          lastCommandId: Value(commandId),
        ),
      );
      final updated = await (database.select(
        database.localAppSettings,
      )..where((row) => row.id.equals('app'))).getSingle();
      await database
          .into(database.localOutboxCommands)
          .insert(
            LocalOutboxCommandsCompanion.insert(
              commandId: commandId,
              userId: updated.userId,
              deviceId: deviceId,
              deviceSequence: sequence,
              entityType: 'user_settings',
              entityId: updated.userId,
              commandType: 'update',
              baseRevision: current.revision,
              payloadJson: jsonEncode({
                'preferred_language': updated.localeCode,
                'time_zone': updated.timeZone,
                'clock_format': updated.clockFormat,
                'theme': updated.themeKey,
                'accent_color': updated.accentColor,
                'notification_sound': updated.notificationSoundKey,
                'data': {
                  'health_connect_enabled': updated.healthConnectEnabled,
                  'cycle_tracking_enabled': updated.cycleTrackingEnabled,
                  'cycle_storage_mode': updated.cycleStorageMode,
                  'calendar_show_completed': updated.calendarShowCompleted,
                  'application_tracking_enabled':
                      updated.applicationTrackingEnabled,
                  'window_title_tracking_enabled':
                      updated.windowTitleTrackingEnabled,
                  'idle_detection_enabled': updated.idleDetectionEnabled,
                  'idle_threshold_seconds': updated.idleThresholdSeconds,
                  'detect_break_activity': updated.detectBreakActivity,
                  'detect_cross_task_activity': updated.detectCrossTaskActivity,
                  'retain_unclassified_activity':
                      updated.retainUnclassifiedActivity,
                  'retain_technical_idle': updated.retainTechnicalIdle,
                  'automatic_trusted_rules': updated.automaticTrustedRules,
                  'activity_sync_enabled': updated.activitySyncEnabled,
                  'automatic_confidence_threshold':
                      updated.automaticConfidenceThreshold,
                  'minimum_suggestion_duration_ms':
                      updated.minimumSuggestionDurationMs,
                },
              }),
              clientTimestamp: now,
              createdAt: now,
            ),
          );
    });
  }
}
