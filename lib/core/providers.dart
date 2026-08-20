import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account/account_context.dart';
import '../features/activity/data/activity_repository.dart';
import '../features/activity/data/activity_capture_service.dart';
import '../features/coaching/data/adaptive_coaching_service.dart';
import '../features/roadmaps/data/roadmap_repository.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/tasks/data/task_repository.dart';
import '../features/tasks/data/recurrence_service.dart';
import '../features/tasks/data/owner_routine_installer.dart';
import '../features/tasks/data/task_resource_service.dart';
import '../features/tasks/data/vacation_repository.dart';
import '../features/tasks/data/vacation_schedule_coordinator.dart';
import '../features/tasks/data/vacation_scheduling_service.dart';
import '../features/tasks/data/website_rule_service.dart';
import 'data/entity_record_repository.dart';
import 'database/app_database.dart';
import 'learning/application_system_learning.dart';
import 'sync/sync_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final accountId = ref.watch(activeAccountIdProvider);
  final database = AppDatabase.forAccount(accountId);
  // AuthGate owns the ordered account transition. Closing here would race the
  // Activity collector's asynchronous provider disposal and can tear down
  // Drift while a final sample is still being written.
  return database;
});

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final applicationSystemLearningServiceProvider =
    FutureProvider<ApplicationSystemLearningService?>((ref) async {
      if (!ApplicationSystemLearningConfig.isConfigured) return null;
      final preferences = await SharedPreferences.getInstance();
      final learningClient = SupabaseClient(
        ApplicationSystemLearningConfig.url,
        ApplicationSystemLearningConfig.publishableKey,
      );
      return ApplicationSystemLearningService(
        preferences: SharedPreferencesApplicationSystemLearningPreferences(
          preferences,
        ),
        secretStore: SecureApplicationLearningSecretStore(),
        gateway: SupabaseApplicationSystemLearningGateway(learningClient),
        cache: ApplicationSystemLearningCache(preferences),
      );
    });

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(
    ref.watch(databaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final appSettingsProvider = StreamProvider<LocalAppSetting?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchSettings(),
);

final localProfileProvider = StreamProvider.family<LocalProfile?, String>(
  (ref, userId) => ref.watch(settingsRepositoryProvider).watchProfile(userId),
);

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final database = ref.watch(databaseProvider);
  final client = ref.watch(supabaseClientProvider);
  final roadmaps = RoadmapRepository(database, client);
  return TaskRepository(
    database,
    client,
    recalculateRoadmap: roadmaps.recalculateProgress,
  );
});

final recurrenceServiceProvider = Provider<RecurrenceService>(
  (ref) => RecurrenceService(
    database: ref.watch(databaseProvider),
    entities: ref.watch(entityRecordRepositoryProvider),
    tasks: ref.watch(taskRepositoryProvider),
    vacations: ref.watch(vacationRepositoryProvider),
  ),
);

final vacationRepositoryProvider = Provider<VacationRepository>(
  (ref) => VacationRepository(ref.watch(entityRecordRepositoryProvider)),
);

final vacationSchedulingServiceProvider = Provider<VacationSchedulingService>(
  (ref) => VacationSchedulingService(
    database: ref.watch(databaseProvider),
    tasks: ref.watch(taskRepositoryProvider),
    vacations: ref.watch(vacationRepositoryProvider),
  ),
);

final vacationScheduleCoordinatorProvider =
    Provider<VacationScheduleCoordinator>((ref) {
      final coordinator = VacationScheduleCoordinator(
        changes: ref.watch(vacationRepositoryProvider).watch(),
        reconcile: ref
            .watch(vacationSchedulingServiceProvider)
            .reconcileUpcoming,
        generate: ref.watch(recurrenceServiceProvider).generateUpcoming,
        drain: ref.watch(syncServiceProvider).drainOutbox,
      );
      coordinator.start();
      ref.onDispose(() => unawaited(coordinator.dispose()));
      return coordinator;
    });

final ownerRoutineInstallerProvider = Provider<OwnerRoutineInstaller>(
  (ref) => OwnerRoutineInstaller(
    database: ref.watch(databaseProvider),
    entities: ref.watch(entityRecordRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

final roadmapRepositoryProvider = Provider<RoadmapRepository>(
  (ref) => RoadmapRepository(
    ref.watch(databaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(
    ref.watch(databaseProvider),
    ref.watch(supabaseClientProvider),
    communityLearning: ref.watch(
      applicationSystemLearningServiceProvider.future,
    ),
  ),
);

final activityCaptureServiceProvider = Provider<ActivityCaptureService>((ref) {
  final service = ActivityCaptureService(
    database: ref.watch(databaseProvider),
    repository: ref.watch(activityRepositoryProvider),
  );
  return service;
});

final entityRecordRepositoryProvider = Provider<EntityRecordRepository>(
  (ref) => EntityRecordRepository(
    ref.watch(databaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final adaptiveCoachingServiceProvider = Provider<AdaptiveCoachingService>((
  ref,
) {
  final userId = ref.watch(activeAccountIdProvider) ?? '__signed_out__';
  return AdaptiveCoachingService(
    database: ref.watch(databaseProvider),
    entities: ref.watch(entityRecordRepositoryProvider),
    userId: userId,
  );
});

final taskResourceServiceProvider = Provider<TaskResourceService>(
  (ref) => TaskResourceService(
    entities: ref.watch(entityRecordRepositoryProvider),
    client: ref.watch(supabaseClientProvider),
  ),
);

final websiteRuleServiceProvider = Provider<WebsiteRuleService>(
  (ref) =>
      WebsiteRuleService(entities: ref.watch(entityRecordRepositoryProvider)),
);

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    database: ref.watch(databaseProvider),
    client: ref.watch(supabaseClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
