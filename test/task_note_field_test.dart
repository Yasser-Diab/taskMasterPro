import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/features/tasks/data/task_repository.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_list_projection.dart';
import 'package:taskmaster_pro/features/tasks/presentation/task_card.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 9);

  LocalTask task({
    String id = '00000000-0000-4000-8000-000000000101',
    String title = 'Prepare release notes',
    String note = 'Summarize the notification reliability work',
  }) => LocalTask(
    id: id,
    userId: '00000000-0000-4000-8000-000000000001',
    templateId: null,
    title: title,
    // The existing synchronized description column is the canonical storage
    // for the concise task Note/subheading. Workspace notes remain separate.
    description: note,
    domainId: null,
    status: 'ready',
    priority: 2,
    executionMode: 'pomodoro',
    scheduledDate: now,
    plannedStart: now,
    plannedEnd: now.add(const Duration(minutes: 25)),
    dueAt: null,
    estimatedDurationMs: const Duration(minutes: 25).inMilliseconds,
    actualStart: null,
    actualFinish: null,
    activeDurationMs: 0,
    pausedDurationMs: 0,
    idleDurationMs: 0,
    progress: 0,
    roadmapId: null,
    roadmapPhaseId: null,
    occurrenceKey: null,
    dataJson: '{}',
    revision: 1,
    createdAt: now,
    updatedAt: now,
    createdByDeviceId: null,
    updatedByDeviceId: null,
    lastCommandId: null,
    deletedAt: null,
  );

  test('task search includes the Note/subheading text', () {
    final result = const TaskListQuery(
      search: 'notification reliability',
    ).apply([task()], now: now, timeZone: 'Africa/Cairo');

    expect(result, hasLength(1));
    expect(result.single.task.title, 'Prepare release notes');
  });

  test('create, edit and duplicate preserve the canonical task Note', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TaskRepository(
      database,
      SupabaseClient('https://example.supabase.co', 'sb_publishable_test_key'),
    );

    final taskId = await repository.createTask(
      TaskDraft(
        title: 'Concise heading',
        description: '  Supporting detail for the heading  ',
        scheduledDate: now,
      ),
    );
    var saved = (await repository.getTask(taskId))!;
    expect(saved.description, 'Supporting detail for the heading');

    await repository.updateTask(
      saved,
      TaskDraft(
        title: saved.title,
        description: 'Updated supporting detail',
        scheduledDate: saved.scheduledDate,
        estimatedDuration: Duration(milliseconds: saved.estimatedDurationMs),
        configuration: const {},
      ),
    );
    saved = (await repository.getTask(taskId))!;
    final duplicateId = await repository.duplicate(saved);
    final duplicate = (await repository.getTask(duplicateId))!;

    expect(saved.description, 'Updated supporting detail');
    expect(duplicate.description, saved.description);
    final commandPayloads = await database
        .select(database.localOutboxCommands)
        .get();
    expect(
      commandPayloads.any(
        (command) => command.payloadJson.contains(
          '"description":"Updated supporting detail"',
        ),
      ),
      isTrue,
    );
    final workspaceNotes = await database
        .select(database.localEntityRecords)
        .get();
    expect(
      workspaceNotes.where((record) => record.entityType == 'task_notes'),
      isEmpty,
      reason: 'The task subheading must not create workspace Notes entries.',
    );
  });

  test('Note field copy is complete and distinct from workspace Notes', () {
    const expected = {
      'en': (
        'Note',
        'Brief detail shown below the task title',
        'Device default',
      ),
      'ar': (
        'ملاحظة',
        'تفصيل مختصر يظهر أسفل عنوان المهمة',
        'إعداد الجهاز الافتراضي',
      ),
      'de': (
        'Notiz',
        'Kurzes Detail unter dem Aufgabentitel',
        'Gerätestandard',
      ),
    };

    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      final copy = expected[locale.languageCode]!;
      expect(l10n.text('task_subheading_note'), copy.$1);
      expect(l10n.text('task_subheading_note_hint'), copy.$2);
      expect(l10n.text('sound_system_default'), copy.$3);
      expect(
        l10n.text('task_subheading_note_detail'),
        isNot(l10n.text('task_notes_detail')),
      );
    }
    expect(AppLocalizations.translationsComplete, isTrue);
  });

  testWidgets('compact task card renders a long Note as secondary text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final item = task(
      note:
          'Keep this supporting detail under the concise heading without widening the mobile card.',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: TaskCard(
              task: item,
              compact: true,
              hideExecutionControl: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final note = find.byKey(ValueKey('task-subheading-${item.id}'));
    expect(note, findsOneWidget);
    expect(tester.widget<Text>(note).maxLines, 1);
    expect(tester.takeException(), isNull);
  });
}
