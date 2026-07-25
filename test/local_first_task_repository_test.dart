import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/settings/data/settings_repository.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TaskRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase(NativeDatabase.memory());
    repository = TaskRepository(
      database,
      SupabaseClient('https://example.supabase.co', 'sb_publishable_test_key'),
    );
  });

  tearDown(() => database.close());

  test(
    'create succeeds locally and writes an idempotent outbox command',
    () async {
      await repository.createTask(
        TaskDraft(
          title: 'Build local-first foundation',
          scheduledDate: DateTime(2026, 7, 25),
          estimatedDuration: const Duration(minutes: 45),
        ),
      );

      final tasks = await database.select(database.localTasks).get();
      final commands = await database
          .select(database.localOutboxCommands)
          .get();

      expect(tasks, hasLength(1));
      expect(tasks.single.title, 'Build local-first foundation');
      expect(tasks.single.revision, 1);
      expect(commands, hasLength(1));
      expect(commands.single.entityId, tasks.single.id);
      expect(commands.single.commandType, 'create');
      expect(commands.single.baseRevision, 0);
      expect(commands.single.status, 'pending');
    },
  );

  test(
    'status change is immediate and keeps the original command history',
    () async {
      await repository.createTask(
        TaskDraft(title: 'Run timer', scheduledDate: DateTime(2026, 7, 25)),
      );
      final created = await database.select(database.localTasks).getSingle();

      await repository.changeStatus(created, 'completed');

      final updated = await database.select(database.localTasks).getSingle();
      final commands = await database
          .select(database.localOutboxCommands)
          .get();

      expect(updated.status, 'completed');
      expect(updated.progress, 1);
      expect(updated.revision, 2);
      expect(commands, hasLength(2));
      expect(commands.last.baseRevision, 1);
    },
  );

  test('account refresh preserves completed onboarding', () async {
    final settings = SettingsRepository(database);
    const user = User(
      id: 'user-1',
      appMetadata: {},
      userMetadata: {'display_name': 'Initial name'},
      aud: 'authenticated',
      email: 'person@example.com',
      createdAt: '2026-07-25T00:00:00Z',
    );

    await settings.ensureLocalAccount(user);
    await settings.completeOnboarding(
      userId: user.id,
      displayName: 'Chosen name',
    );
    await settings.ensureLocalAccount(user);

    final profile = await database.select(database.localProfiles).getSingle();
    expect(profile.onboardingCompleted, isTrue);
    expect(profile.displayName, 'Chosen name');
  });
}
