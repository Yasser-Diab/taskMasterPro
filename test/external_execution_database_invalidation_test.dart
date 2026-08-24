import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';

void main() {
  test(
    'foreground execution streams refresh after a headless database write',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'taskmaster-external-execution-',
      );
      final file = File('${directory.path}${Platform.pathSeparator}account.db');
      final foreground = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await foreground.close();
        await directory.delete(recursive: true);
      });

      final now = DateTime.utc(2026, 8, 23, 19);
      await foreground
          .into(foreground.localRuntimeStates)
          .insert(
            LocalRuntimeStatesCompanion.insert(
              id: localRuntimeStateId('account'),
              userId: 'account',
              activeTaskId: const drift.Value('task'),
              sessionId: const drift.Value('session'),
              state: const drift.Value('running'),
              revision: const drift.Value(7),
              updatedAt: now,
            ),
          );

      final iterator = StreamIterator(
        foreground.select(foreground.localRuntimeStates).watchSingle(),
      );
      addTearDown(iterator.cancel);
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.state, 'running');

      final headless = AppDatabase(NativeDatabase(file));
      await (headless.update(
        headless.localRuntimeStates,
      )..where((row) => row.id.equals(localRuntimeStateId('account')))).write(
        LocalRuntimeStatesCompanion(
          state: const drift.Value('paused'),
          revision: const drift.Value(8),
          updatedAt: drift.Value(now.add(const Duration(minutes: 1))),
        ),
      );
      await headless.close();

      foreground.notifyExternalExecutionMutation();

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.state, 'paused');
      expect(iterator.current.revision, 8);
    },
  );
}
