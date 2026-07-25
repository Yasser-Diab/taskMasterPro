import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity.dart';

class SettingsRepository {
  SettingsRepository(this.database);

  final AppDatabase database;

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

  Future<void> updateAttributionSetting({
    bool? detectBreakActivity,
    bool? detectCrossTaskActivity,
    bool? automaticTrustedRules,
    bool? retainUnclassifiedActivity,
    bool? retainTechnicalIdle,
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
      ),
    );
  }

  Future<void> completeOnboarding({
    required String userId,
    required String displayName,
  }) async {
    final now = DateTime.now().toUtc();
    await (database.update(
      database.localProfiles,
    )..where((row) => row.userId.equals(userId))).write(
      LocalProfilesCompanion(
        displayName: Value(displayName.trim()),
        onboardingCompleted: const Value(true),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _update(LocalAppSettingsCompanion changes) async {
    final now = DateTime.now().toUtc();
    await (database.update(database.localAppSettings)
          ..where((row) => row.id.equals('app')))
        .write(changes.copyWith(updatedAt: Value(now)));
  }
}
