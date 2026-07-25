import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/activity/data/activity_repository.dart';
import '../features/roadmaps/data/roadmap_repository.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/tasks/data/task_repository.dart';
import 'database/app_database.dart';
import 'sync/sync_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);

final appSettingsProvider = StreamProvider<LocalAppSetting?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchSettings(),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(
    ref.watch(databaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final roadmapRepositoryProvider = Provider<RoadmapRepository>(
  (ref) => RoadmapRepository(ref.watch(databaseProvider)),
);

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(databaseProvider)),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    database: ref.watch(databaseProvider),
    client: ref.watch(supabaseClientProvider),
  ),
);
