import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskmaster_pro/core/data/entity_record_repository.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'coalesced generic edits keep one canonical optimistic revision',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = EntityRecordRepository(
        database,
        SupabaseClient(
          'https://example.supabase.co',
          'sb_publishable_test_key',
        ),
      );
      const entityId = '00000000-0000-4000-8000-000000000028';

      await repository.create(
        const EntityRecordDraft(
          id: entityId,
          entityType: 'health_summaries',
          title: 'steps',
          data: <String, Object?>{'value': 100},
          syncPayload: <String, Object?>{
            'summary_date': '2026-08-24',
            'summary_type': 'steps',
            'value': 100,
          },
        ),
      );
      for (final value in const [200, 300, 400]) {
        final record = await repository.get(entityId);
        await repository.update(
          record!,
          data: <String, Object?>{'value': value},
          syncPayload: <String, Object?>{
            'summary_date': '2026-08-24',
            'summary_type': 'steps',
            'value': value,
          },
        );
      }

      final record = await repository.get(entityId);
      final commands = await database
          .select(database.localOutboxCommands)
          .get();
      expect(commands, hasLength(1));
      expect(commands.single.commandType, 'create');
      expect(commands.single.baseRevision, 0);
      expect((jsonDecode(commands.single.payloadJson) as Map)['value'], 400);
      expect(record!.revision, 1);
      expect(record.lastCommandId, commands.single.commandId);
    },
  );
}
