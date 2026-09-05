import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity.dart';
import '../../../core/time/time_zone_service.dart';
import '../../activity/data/activity_privacy_policy.dart';

class SettingsRepository {
  SettingsRepository(this.database, [this.client]);

  final AppDatabase database;
  final SupabaseClient? client;
  static const _uuid = Uuid();

  String get _settingsId =>
      localAppSettingsId(client?.auth.currentUser?.id ?? 'local');

  Stream<LocalAppSetting?> watchSettings() {
    return (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(_settingsId))).watchSingleOrNull();
  }

  Stream<LocalProfile?> watchProfile(String userId) {
    return (database.select(
      database.localProfiles,
    )..where((row) => row.userId.equals(userId))).watchSingleOrNull();
  }

  Future<void> ensureLocalAccount(User user) async {
    // A returning user must always reach their existing local workspace. In
    // particular, a transient platform-preferences or remote-hydration error
    // must never restart onboarding or block an already-prepared account.
    final existingProfile = await (database.select(
      database.localProfiles,
    )..where((row) => row.userId.equals(user.id))).getSingleOrNull();
    final existingSettings =
        await (database.select(database.localAppSettings)..where(
              (row) =>
                  row.id.equals(localAppSettingsId(user.id)) &
                  row.userId.equals(user.id),
            ))
            .getSingleOrNull();
    if (existingProfile != null && existingSettings != null) return;

    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(user.id);
    Map<String, dynamic>? remoteProfile;
    Map<String, dynamic>? remoteSettings;
    Map<String, dynamic>? remotePrivacy;
    if (client != null) {
      try {
        final profile = await client!
            .from('profiles')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
        if (profile != null) {
          remoteProfile = Map<String, dynamic>.from(profile);
        }
        final settings = await client!
            .from('user_settings')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
        if (settings != null) {
          remoteSettings = Map<String, dynamic>.from(settings);
        }
        final privacy = await client!
            .from('privacy_settings')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();
        if (privacy != null) {
          remotePrivacy = Map<String, dynamic>.from(privacy);
        }
      } catch (_) {
        // An existing local account remains usable while offline. A genuinely
        // new device retries this hydration through the synchronization
        // service instead of replacing remote account state.
      }
    }
    final remoteSettingsData = remoteSettings?['data'] is Map
        ? Map<String, dynamic>.from(remoteSettings!['data'] as Map)
        : const <String, dynamic>{};
    final useDeviceTimeZone =
        remoteSettingsData['use_device_time_zone'] as bool? ?? true;
    final detectedTimeZone = useDeviceTimeZone
        ? await TimeZoneService.detectDeviceIanaZone()
        : null;
    final initialTimeZone = TimeZoneService.resolveStoredIanaZone(
      deviceZone: detectedTimeZone,
      storedZone: remoteSettings?['time_zone'] as String?,
      useDeviceTimeZone: useDeviceTimeZone,
    );
    await database.transaction(() async {
      final localProfile = await (database.select(
        database.localProfiles,
      )..where((row) => row.userId.equals(user.id))).getSingleOrNull();
      if (localProfile == null) {
        final profile = remoteProfile;
        await database
            .into(database.localProfiles)
            .insert(
              LocalProfilesCompanion.insert(
                id: profile?['id'] as String? ?? user.id,
                userId: user.id,
                displayName: Value(
                  profile?['display_name'] as String? ??
                      user.userMetadata?['display_name'] as String? ??
                      user.userMetadata?['full_name'] as String? ??
                      '',
                ),
                email: Value(profile?['email'] as String? ?? user.email),
                imagePath: Value(
                  profile?['profile_image_path'] as String? ??
                      user.userMetadata?['avatar_url'] as String? ??
                      user.userMetadata?['picture'] as String?,
                ),
                genderIdentity: Value(profile?['gender_identity'] as String?),
                dateOfBirth: Value(
                  DateTime.tryParse(
                    profile?['date_of_birth'] as String? ?? '',
                  )?.toUtc(),
                ),
                heightCm: Value((profile?['height_cm'] as num?)?.toDouble()),
                onboardingCompleted: Value(
                  profile?['onboarding_completed_at'] != null,
                ),
                revision: Value((profile?['revision'] as num?)?.toInt() ?? 1),
                createdAt:
                    DateTime.tryParse(
                      profile?['created_at'] as String? ?? '',
                    )?.toUtc() ??
                    now,
                updatedAt:
                    DateTime.tryParse(
                      profile?['updated_at'] as String? ?? '',
                    )?.toUtc() ??
                    now,
                updatedByDeviceId: Value(deviceId),
                lastCommandId: Value(profile?['last_command_id'] as String?),
                deletedAt: Value(
                  DateTime.tryParse(
                    profile?['deleted_at'] as String? ?? '',
                  )?.toUtc(),
                ),
              ),
            );
      }
      final localSettings =
          await (database.select(database.localAppSettings)
                ..where((row) => row.id.equals(localAppSettingsId(user.id))))
              .getSingleOrNull();
      if (localSettings == null) {
        final remote = remoteSettings;
        final data = remoteSettingsData;
        final privacyPolicy = ActivityPrivacyPolicy.fromRemoteRow(
          remotePrivacy == null
              ? null
              : Map<String, Object?>.from(remotePrivacy),
        );
        await database
            .into(database.localAppSettings)
            .insert(
              LocalAppSettingsCompanion.insert(
                id: localAppSettingsId(user.id),
                userId: Value(user.id),
                localeCode: Value(
                  remote?['preferred_language'] as String? ?? 'en',
                ),
                themeKey: Value(remote?['theme'] as String? ?? 'system'),
                accentColor: Value(
                  (remote?['accent_color'] as num?)?.toInt() ?? 0xFF0B78D1,
                ),
                timeZone: Value(initialTimeZone),
                useDeviceTimeZone: Value(useDeviceTimeZone),
                clockFormat: Value(remote?['clock_format'] as String? ?? '24h'),
                notificationSoundKey: Value(
                  remote?['notification_sound'] as String? ?? 'system',
                ),
                wakeTimeMinutes: Value(
                  (data['wake_time_minutes'] as num?)?.toInt() ?? 420,
                ),
                sleepTimeMinutes: Value(
                  (data['sleep_time_minutes'] as num?)?.toInt() ?? 1380,
                ),
                workingDaysJson: Value(
                  jsonEncode(
                    data['working_days'] is List
                        ? data['working_days']
                        : const [1, 2, 3, 4, 5],
                  ),
                ),
                workStartMinutes: Value(
                  (data['work_start_minutes'] as num?)?.toInt() ?? 540,
                ),
                workEndMinutes: Value(
                  (data['work_end_minutes'] as num?)?.toInt() ?? 1020,
                ),
                workScheduleEnabled: Value(
                  data['work_schedule_enabled'] as bool? ?? false,
                ),
                workScheduleRotationJson: Value(
                  jsonEncode(data['work_schedule_rotation'] ?? const []),
                ),
                workScheduleAnchorDate: Value(
                  data['work_schedule_anchor_date'] as String? ?? '2026-01-05',
                ),
                workReminderEnabled: Value(
                  data['work_reminder_enabled'] as bool? ?? false,
                ),
                workReminderOffsetMinutes: Value(
                  (data['work_reminder_offset_minutes'] as num?)?.toInt() ?? 15,
                ),
                workPomodoroEnabled: Value(
                  data['work_pomodoro_enabled'] as bool? ?? false,
                ),
                workActivityCreditEnabled: Value(
                  data['work_activity_credit_enabled'] as bool? ?? true,
                ),
                quietStartMinutes: Value(
                  (data['quiet_start_minutes'] as num?)?.toInt() ?? 1320,
                ),
                quietEndMinutes: Value(
                  (data['quiet_end_minutes'] as num?)?.toInt() ?? 420,
                ),
                sleepReminderEnabled: Value(
                  data['sleep_reminder_enabled'] as bool? ?? false,
                ),
                sleepReminderOffsetMinutes: Value(
                  (data['sleep_reminder_offset_minutes'] as num?)?.toInt() ??
                      30,
                ),
                healthConnectEnabled: Value(
                  data['health_connect_enabled'] as bool? ?? false,
                ),
                healthSummarySyncEnabled: Value(
                  data['health_summary_sync_enabled'] as bool? ?? false,
                ),
                coachingSensitivity: Value(
                  data['coaching_sensitivity'] as String? ?? 'standard',
                ),
                coachingTone: Value(
                  data['coaching_tone'] as String? ?? 'balanced',
                ),
                healthReportPrivacy: Value(
                  data['health_report_privacy'] as String? ?? 'ask',
                ),
                notificationPreferencesJson: Value(
                  jsonEncode(
                    data['notification_preferences'] ??
                        const {
                          'task_reminders': true,
                          'scheduled_starts': true,
                          'overdue_tasks': true,
                          'focus_completed': true,
                          'short_break_completed': true,
                          'long_break_completed': true,
                          'roadmaps': true,
                          'activity_review': true,
                          'coaching': true,
                          'sleep_health': true,
                          'synchronization': true,
                          'security': true,
                          'vibration': true,
                        },
                  ),
                ),
                countryCode: Value(data['country_code'] as String? ?? ''),
                dateFormat: Value(data['date_format'] as String? ?? 'locale'),
                firstDayOfWeek: Value(
                  (data['first_day_of_week'] as num?)?.toInt() ?? 1,
                ),
                cycleTrackingEnabled: Value(
                  data['cycle_tracking_enabled'] as bool? ?? false,
                ),
                cycleStorageMode: Value(
                  data['cycle_storage_mode'] as String? ?? 'local_only',
                ),
                activitySyncEnabled: Value(
                  data['activity_sync_enabled'] as bool? ?? true,
                ),
                applicationTrackingEnabled: Value(
                  data['application_tracking_enabled'] as bool? ?? true,
                ),
                activityRuleSyncEnabled: Value(
                  data['activity_rule_sync_enabled'] as bool? ?? true,
                ),
                detailedActivitySyncEnabled: Value(
                  privacyPolicy.hasCanonicalDetailedActivityConsent,
                ),
                localActivityRetentionDays: Value(
                  (data['local_activity_retention_days'] as num?)?.toInt() ??
                      30,
                ),
                hideConfirmedSystemActivity: Value(
                  data['hide_confirmed_system_activity'] as bool? ?? true,
                ),
                showPossibleSystemActivity: Value(
                  data['show_possible_system_activity'] as bool? ?? true,
                ),
                revision: Value((remote?['revision'] as num?)?.toInt() ?? 1),
                createdAt: now,
                updatedAt:
                    DateTime.tryParse(
                      remote?['updated_at'] as String? ?? '',
                    )?.toUtc() ??
                    now,
              ),
            );
      }
      if (remotePrivacy != null) {
        await _upsertPrivacyProjection(remotePrivacy, now: now);
        final authoritative = ActivityPrivacyPolicy.fromRemoteRow(
          Map<String, Object?>.from(remotePrivacy),
        );
        final hydrated =
            await (database.select(database.localAppSettings)
                  ..where((row) => row.id.equals(localAppSettingsId(user.id))))
                .getSingleOrNull();
        if (hydrated != null &&
            !authoritative.allowsDetailedActivityUpload(hydrated)) {
          await (database.update(
            database.localAppSettings,
          )..where((row) => row.id.equals(hydrated.id))).write(
            const LocalAppSettingsCompanion(
              detailedActivitySyncEnabled: Value(false),
            ),
          );
        }
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

  Future<void> updateRegionalSettings({
    String? timeZone,
    bool? useDeviceTimeZone,
    String? countryCode,
    String? dateFormat,
    String? clockFormat,
    int? firstDayOfWeek,
  }) {
    return _update(
      LocalAppSettingsCompanion(
        timeZone: Value.absentIfNull(timeZone),
        useDeviceTimeZone: Value.absentIfNull(useDeviceTimeZone),
        countryCode: Value.absentIfNull(countryCode),
        dateFormat: Value.absentIfNull(dateFormat),
        clockFormat: Value.absentIfNull(clockFormat),
        firstDayOfWeek: Value.absentIfNull(firstDayOfWeek),
      ),
    );
  }

  /// Refreshes an automatic setting from the operating system without asking
  /// for location permission.  A manual IANA choice is never overwritten.
  Future<void> refreshDeviceTimeZoneIfAutomatic() async {
    final current = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(_settingsId))).getSingleOrNull();
    if (current == null || !current.useDeviceTimeZone) return;
    final detected = await TimeZoneService.detectDeviceIanaZone();
    if (detected != current.timeZone) {
      await updateRegionalSettings(timeZone: detected, useDeviceTimeZone: true);
    }
  }

  Future<void> updateCoachingTone(String tone) {
    return _update(LocalAppSettingsCompanion(coachingTone: Value(tone)));
  }

  Future<void> updateHealthReportPrivacy(String value) {
    return _update(
      LocalAppSettingsCompanion(healthReportPrivacy: Value(value)),
    );
  }

  Future<void> updateNotificationPreferences(Map<String, Object?> preferences) {
    return _update(
      LocalAppSettingsCompanion(
        notificationPreferencesJson: Value(jsonEncode(preferences)),
      ),
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

  Future<void> updateScheduleAndWellbeing({
    int? wakeTimeMinutes,
    int? sleepTimeMinutes,
    List<int>? workingDays,
    int? workStartMinutes,
    int? workEndMinutes,
    bool? workScheduleEnabled,
    List<Map<String, Object?>>? workScheduleRotation,
    String? workScheduleAnchorDate,
    bool? workReminderEnabled,
    int? workReminderOffsetMinutes,
    bool? workPomodoroEnabled,
    bool? workActivityCreditEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? sleepReminderEnabled,
    int? sleepReminderOffsetMinutes,
    bool? phoneUsageAnalysisEnabled,
    String? coachingSensitivity,
    bool? healthSummarySyncEnabled,
  }) {
    return _update(
      LocalAppSettingsCompanion(
        wakeTimeMinutes: Value.absentIfNull(wakeTimeMinutes),
        sleepTimeMinutes: Value.absentIfNull(sleepTimeMinutes),
        workingDaysJson: Value.absentIfNull(
          workingDays == null ? null : jsonEncode(workingDays),
        ),
        workStartMinutes: Value.absentIfNull(workStartMinutes),
        workEndMinutes: Value.absentIfNull(workEndMinutes),
        workScheduleEnabled: Value.absentIfNull(workScheduleEnabled),
        workScheduleRotationJson: Value.absentIfNull(
          workScheduleRotation == null
              ? null
              : jsonEncode(workScheduleRotation),
        ),
        workScheduleAnchorDate: Value.absentIfNull(workScheduleAnchorDate),
        workReminderEnabled: Value.absentIfNull(workReminderEnabled),
        workReminderOffsetMinutes: Value.absentIfNull(
          workReminderOffsetMinutes,
        ),
        workPomodoroEnabled: Value.absentIfNull(workPomodoroEnabled),
        workActivityCreditEnabled: Value.absentIfNull(
          workActivityCreditEnabled,
        ),
        quietStartMinutes: Value.absentIfNull(quietStartMinutes),
        quietEndMinutes: Value.absentIfNull(quietEndMinutes),
        sleepReminderEnabled: Value.absentIfNull(sleepReminderEnabled),
        sleepReminderOffsetMinutes: Value.absentIfNull(
          sleepReminderOffsetMinutes,
        ),
        phoneUsageAnalysisEnabled: Value.absentIfNull(
          phoneUsageAnalysisEnabled,
        ),
        coachingSensitivity: Value.absentIfNull(coachingSensitivity),
        healthSummarySyncEnabled: Value.absentIfNull(healthSummarySyncEnabled),
      ),
    );
  }

  Future<void> updateAttributionSetting({
    bool? detectBreakActivity,
    bool? detectCrossTaskActivity,
    bool? automaticTrustedRules,
    bool? retainUnclassifiedActivity,
    bool? retainTechnicalIdle,
    bool? activitySyncEnabled,
    bool? activityRuleSyncEnabled,
    bool? detailedActivitySyncEnabled,
    int? localActivityRetentionDays,
    bool? hideConfirmedSystemActivity,
    bool? showPossibleSystemActivity,
  }) async {
    if (detailedActivitySyncEnabled != null) {
      await _setDetailedActivitySync(detailedActivitySyncEnabled);
    }
    final hasOtherChanges =
        detectBreakActivity != null ||
        detectCrossTaskActivity != null ||
        automaticTrustedRules != null ||
        retainUnclassifiedActivity != null ||
        retainTechnicalIdle != null ||
        activitySyncEnabled != null ||
        activityRuleSyncEnabled != null ||
        localActivityRetentionDays != null ||
        hideConfirmedSystemActivity != null ||
        showPossibleSystemActivity != null;
    if (!hasOtherChanges) return;
    await _update(
      LocalAppSettingsCompanion(
        detectBreakActivity: Value.absentIfNull(detectBreakActivity),
        detectCrossTaskActivity: Value.absentIfNull(detectCrossTaskActivity),
        automaticTrustedRules: Value.absentIfNull(automaticTrustedRules),
        retainUnclassifiedActivity: Value.absentIfNull(
          retainUnclassifiedActivity,
        ),
        retainTechnicalIdle: Value.absentIfNull(retainTechnicalIdle),
        activitySyncEnabled: Value.absentIfNull(activitySyncEnabled),
        activityRuleSyncEnabled: Value.absentIfNull(activityRuleSyncEnabled),
        localActivityRetentionDays: Value.absentIfNull(
          localActivityRetentionDays,
        ),
        hideConfirmedSystemActivity: Value.absentIfNull(
          hideConfirmedSystemActivity,
        ),
        showPossibleSystemActivity: Value.absentIfNull(
          showPossibleSystemActivity,
        ),
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
    final deviceId = await DeviceIdentity.accountId(userId);
    final sequence = await DeviceIdentity.nextSequence(userId);
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
    DateTime? dateOfBirth,
    double? heightCm,
    String? localImagePath,
    String? remoteImagePath,
  }) async {
    if (heightCm != null &&
        (!heightCm.isFinite || heightCm < 50 || heightCm > 250)) {
      throw ArgumentError.value(
        heightCm,
        'heightCm',
        'Height must be between 50 and 250 centimetres.',
      );
    }
    final profile = await (database.select(
      database.localProfiles,
    )..where((row) => row.userId.equals(userId))).getSingle();
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(userId);
    final sequence = await DeviceIdentity.nextSequence(userId);
    final commandId = _uuid.v4();
    final normalizedGender = genderIdentity?.trim();
    final payload = <String, Object?>{
      'display_name': displayName.trim(),
      'gender_identity': normalizedGender?.isEmpty == true
          ? null
          : normalizedGender,
      'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
      'height_cm': heightCm,
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
          dateOfBirth: Value(dateOfBirth?.toUtc()),
          heightCm: Value(heightCm),
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

    // `profiles` plus its durable outbox command is the cross-device
    // authority. Auth metadata is only a signed-out/bootstrap fallback. A
    // temporary Auth request failure must not make the already-saved profile
    // look rejected or tempt the user to create a duplicate edit.
    try {
      await client?.auth.updateUser(
        UserAttributes(data: {'display_name': displayName.trim()}),
      );
    } catch (_) {
      // The outbox watcher delivers the authoritative profile command as soon
      // as connectivity is available; metadata can be refreshed later.
    }
  }

  /// Detailed Activity history is a privacy consent, not an ordinary display
  /// preference.  The canonical privacy row changes first on enable, and the
  /// local switch turns off first on disable so an old outbox cannot race a
  /// user's withdrawal of consent.
  Future<void> _setDetailedActivitySync(bool enabled) async {
    if (!enabled) {
      await _update(
        const LocalAppSettingsCompanion(
          detailedActivitySyncEnabled: Value(false),
        ),
      );
      await _supersedePendingRawActivityCommands();
      await _queueDetailedActivityPrivacyMutation(false);
      return;
    }

    final privacy = await _ensurePrivacyProjection();
    if (privacy == null) {
      throw StateError(
        'Detailed Activity sync requires the canonical privacy settings.',
      );
    }
    await _queueDetailedActivityPrivacyMutation(true, record: privacy);
    await _update(
      const LocalAppSettingsCompanion(detailedActivitySyncEnabled: Value(true)),
    );
  }

  Future<LocalEntityRecord?> _ensurePrivacyProjection() async {
    final current = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(_settingsId))).getSingleOrNull();
    if (current == null) return null;
    final local =
        await (database.select(database.localEntityRecords)
              ..where(
                (row) =>
                    row.userId.equals(current.userId) &
                    row.entityType.equals('privacy_settings') &
                    row.deletedAt.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    if (local != null) return local;

    final user = client?.auth.currentUser;
    if (user == null || user.id != current.userId) return null;
    try {
      final remote = await client!
          .from('privacy_settings')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (remote == null) return null;
      await _upsertPrivacyProjection(
        Map<String, dynamic>.from(remote),
        now: DateTime.now().toUtc(),
      );
    } catch (_) {
      // Failing closed preserves the local-only default when offline.
      return null;
    }
    return (database.select(database.localEntityRecords)
          ..where(
            (row) =>
                row.userId.equals(current.userId) &
                row.entityType.equals('privacy_settings') &
                row.deletedAt.isNull(),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> _upsertPrivacyProjection(
    Map<String, dynamic> row, {
    required DateTime now,
  }) async {
    final id = row['id'] as String?;
    final userId = row['user_id'] as String?;
    if (id == null || id.isEmpty || userId == null || userId.isEmpty) return;
    await database
        .into(database.localEntityRecords)
        .insertOnConflictUpdate(
          LocalEntityRecordsCompanion.insert(
            id: id,
            userId: userId,
            entityType: 'privacy_settings',
            title: const Value('Activity privacy'),
            status: Value(row['activity_storage'] as String? ?? 'local_only'),
            dataJson: Value(jsonEncode(row)),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt:
                DateTime.tryParse(
                  row['created_at'] as String? ?? '',
                )?.toUtc() ??
                now,
            updatedAt:
                DateTime.tryParse(
                  row['updated_at'] as String? ?? '',
                )?.toUtc() ??
                now,
            createdByDeviceId: Value(row['created_by_device_id'] as String?),
            updatedByDeviceId: Value(row['updated_by_device_id'] as String?),
            lastCommandId: Value(row['last_command_id'] as String?),
            deletedAt: Value(
              DateTime.tryParse(row['deleted_at'] as String? ?? '')?.toUtc(),
            ),
          ),
        );
  }

  Future<void> _queueDetailedActivityPrivacyMutation(
    bool enabled, {
    LocalEntityRecord? record,
  }) async {
    final current = record ?? await _ensurePrivacyProjection();
    if (current == null) return;
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(_settingsId))).getSingle();
    final now = DateTime.now().toUtc();
    final commandId = _uuid.v4();
    final deviceId = await DeviceIdentity.accountId(settings.userId);
    final raw = _jsonObject(current.dataJson);
    final data = _jsonObject(raw['data']);
    data['detailed_activity_sync_opt_in'] = enabled;
    data['activity_upload_policy'] = enabled
        ? 'explicit_detailed_history'
        : 'approved_contributions_only';
    if (enabled) {
      data['detailed_activity_sync_opt_in_at'] = now.toIso8601String();
    } else {
      data.remove('detailed_activity_sync_opt_in_at');
    }
    final storage = enabled ? 'synchronized' : 'local_only';
    final updatedRow = <String, Object?>{
      ...raw,
      'activity_storage': storage,
      'application_tracking': storage,
      'website_tracking': storage,
      'data': data,
      'revision': current.revision + 1,
      'updated_at': now.toIso8601String(),
      'updated_by_device_id': deviceId,
      'last_command_id': commandId,
    };
    await database.transaction(() async {
      await (database.update(
        database.localEntityRecords,
      )..where((row) => row.id.equals(current.id))).write(
        LocalEntityRecordsCompanion(
          status: Value(storage),
          dataJson: Value(jsonEncode(updatedRow)),
          revision: Value(current.revision + 1),
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
              userId: settings.userId,
              deviceId: deviceId,
              deviceSequence: await DeviceIdentity.nextSequence(
                settings.userId,
              ),
              entityType: 'privacy_settings',
              entityId: current.id,
              commandType: 'update',
              baseRevision: current.revision,
              payloadJson: jsonEncode({
                'activity_storage': storage,
                'application_tracking': storage,
                'website_tracking': storage,
                'data': data,
              }),
              clientTimestamp: now,
              createdAt: now,
            ),
          );
    });
  }

  Future<void> _supersedePendingRawActivityCommands() async {
    final settings = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(_settingsId))).getSingleOrNull();
    if (settings == null) return;
    final commands =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(settings.userId) &
                  row.status.isIn(const ['pending', 'conflict']) &
                  row.entityType.isIn(const [
                    'activity_segments',
                    'activity_review_queue',
                  ]),
            ))
            .get();
    for (final command in commands) {
      if (command.entityType == 'activity_segments' &&
          _isApprovedContributionPayload(command.payloadJson)) {
        continue;
      }
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        const LocalOutboxCommandsCompanion(
          status: Value('superseded'),
          lastError: Value(null),
        ),
      );
    }
  }

  static bool _isApprovedContributionPayload(String value) {
    final payload = _jsonObject(value);
    final data = _jsonObject(payload['data']);
    return data['approved_contribution'] == true;
  }

  static Map<String, Object?> _jsonObject(Object? value) {
    if (value is String) {
      try {
        return _jsonObject(jsonDecode(value));
      } on FormatException {
        return <String, Object?>{};
      }
    }
    if (value is! Map) return <String, Object?>{};
    return Map<String, Object?>.from(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }

  Future<void> _update(LocalAppSettingsCompanion changes) async {
    final current = await (database.select(
      database.localAppSettings,
    )..where((row) => row.id.equals(_settingsId))).getSingle();
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(current.userId);
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence(current.userId);
    await database.transaction(() async {
      await (database.update(
        database.localAppSettings,
      )..where((row) => row.id.equals(_settingsId))).write(
        changes.copyWith(
          revision: Value(current.revision + 1),
          updatedAt: Value(now),
          lastCommandId: Value(commandId),
        ),
      );
      final updated = await (database.select(
        database.localAppSettings,
      )..where((row) => row.id.equals(_settingsId))).getSingle();
      final data = <String, Object?>{
        if (changes.healthConnectEnabled.present)
          'health_connect_enabled': updated.healthConnectEnabled,
        if (changes.cycleTrackingEnabled.present)
          'cycle_tracking_enabled': updated.cycleTrackingEnabled,
        if (changes.cycleStorageMode.present)
          'cycle_storage_mode': updated.cycleStorageMode,
        if (changes.calendarShowCompleted.present)
          'calendar_show_completed': updated.calendarShowCompleted,
        if (changes.applicationTrackingEnabled.present)
          'application_tracking_enabled': updated.applicationTrackingEnabled,
        if (changes.windowTitleTrackingEnabled.present)
          'window_title_tracking_enabled': updated.windowTitleTrackingEnabled,
        if (changes.idleDetectionEnabled.present)
          'idle_detection_enabled': updated.idleDetectionEnabled,
        if (changes.idleThresholdSeconds.present)
          'idle_threshold_seconds': updated.idleThresholdSeconds,
        if (changes.detectBreakActivity.present)
          'detect_break_activity': updated.detectBreakActivity,
        if (changes.detectCrossTaskActivity.present)
          'detect_cross_task_activity': updated.detectCrossTaskActivity,
        if (changes.retainUnclassifiedActivity.present)
          'retain_unclassified_activity': updated.retainUnclassifiedActivity,
        if (changes.retainTechnicalIdle.present)
          'retain_technical_idle': updated.retainTechnicalIdle,
        if (changes.automaticTrustedRules.present)
          'automatic_trusted_rules': updated.automaticTrustedRules,
        if (changes.activitySyncEnabled.present)
          'activity_sync_enabled': updated.activitySyncEnabled,
        if (changes.activityRuleSyncEnabled.present)
          'activity_rule_sync_enabled': updated.activityRuleSyncEnabled,
        if (changes.detailedActivitySyncEnabled.present)
          'detailed_activity_sync_enabled': updated.detailedActivitySyncEnabled,
        if (changes.localActivityRetentionDays.present)
          'local_activity_retention_days': updated.localActivityRetentionDays,
        if (changes.hideConfirmedSystemActivity.present)
          'hide_confirmed_system_activity': updated.hideConfirmedSystemActivity,
        if (changes.showPossibleSystemActivity.present)
          'show_possible_system_activity': updated.showPossibleSystemActivity,
        if (changes.automaticConfidenceThreshold.present)
          'automatic_confidence_threshold':
              updated.automaticConfidenceThreshold,
        if (changes.minimumSuggestionDurationMs.present)
          'minimum_suggestion_duration_ms': updated.minimumSuggestionDurationMs,
        if (changes.wakeTimeMinutes.present)
          'wake_time_minutes': updated.wakeTimeMinutes,
        if (changes.sleepTimeMinutes.present)
          'sleep_time_minutes': updated.sleepTimeMinutes,
        if (changes.workingDaysJson.present)
          'working_days': jsonDecode(updated.workingDaysJson),
        if (changes.workStartMinutes.present)
          'work_start_minutes': updated.workStartMinutes,
        if (changes.workEndMinutes.present)
          'work_end_minutes': updated.workEndMinutes,
        if (changes.workScheduleEnabled.present)
          'work_schedule_enabled': updated.workScheduleEnabled,
        if (changes.workScheduleRotationJson.present)
          'work_schedule_rotation': jsonDecode(
            updated.workScheduleRotationJson,
          ),
        if (changes.workScheduleAnchorDate.present)
          'work_schedule_anchor_date': updated.workScheduleAnchorDate,
        if (changes.workReminderEnabled.present)
          'work_reminder_enabled': updated.workReminderEnabled,
        if (changes.workReminderOffsetMinutes.present)
          'work_reminder_offset_minutes': updated.workReminderOffsetMinutes,
        if (changes.workPomodoroEnabled.present)
          'work_pomodoro_enabled': updated.workPomodoroEnabled,
        if (changes.workActivityCreditEnabled.present)
          'work_activity_credit_enabled': updated.workActivityCreditEnabled,
        if (changes.quietStartMinutes.present)
          'quiet_start_minutes': updated.quietStartMinutes,
        if (changes.quietEndMinutes.present)
          'quiet_end_minutes': updated.quietEndMinutes,
        if (changes.sleepReminderEnabled.present)
          'sleep_reminder_enabled': updated.sleepReminderEnabled,
        if (changes.sleepReminderOffsetMinutes.present)
          'sleep_reminder_offset_minutes': updated.sleepReminderOffsetMinutes,
        if (changes.phoneUsageAnalysisEnabled.present)
          'phone_usage_analysis_enabled': updated.phoneUsageAnalysisEnabled,
        if (changes.coachingSensitivity.present)
          'coaching_sensitivity': updated.coachingSensitivity,
        if (changes.coachingTone.present) 'coaching_tone': updated.coachingTone,
        if (changes.healthSummarySyncEnabled.present)
          'health_summary_sync_enabled': updated.healthSummarySyncEnabled,
        if (changes.healthReportPrivacy.present)
          'health_report_privacy': updated.healthReportPrivacy,
        if (changes.notificationPreferencesJson.present)
          'notification_preferences': jsonDecode(
            updated.notificationPreferencesJson,
          ),
        if (changes.countryCode.present) 'country_code': updated.countryCode,
        if (changes.dateFormat.present) 'date_format': updated.dateFormat,
        if (changes.firstDayOfWeek.present)
          'first_day_of_week': updated.firstDayOfWeek,
        if (changes.useDeviceTimeZone.present)
          'use_device_time_zone': updated.useDeviceTimeZone,
      };
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
                if (changes.localeCode.present)
                  'preferred_language': updated.localeCode,
                if (changes.timeZone.present) 'time_zone': updated.timeZone,
                if (changes.clockFormat.present)
                  'clock_format': updated.clockFormat,
                if (changes.themeKey.present) 'theme': updated.themeKey,
                if (changes.accentColor.present)
                  'accent_color': updated.accentColor,
                if (changes.notificationSoundKey.present)
                  'notification_sound': updated.notificationSoundKey,
                if (data.isNotEmpty) 'data': data,
              }),
              clientTimestamp: now,
              createdAt: now,
            ),
          );
    });
  }
}
