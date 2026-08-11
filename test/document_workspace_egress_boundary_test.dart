import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'document page turns remain local and synchronize only at a boundary',
    () {
      final workspace = File(
        'lib/features/tasks/presentation/task_document_workspace.dart',
      ).readAsStringSync();

      expect(workspace, contains('SharedPreferences.getInstance'));
      expect(workspace, contains('const Duration(milliseconds: 850)'));
      expect(workspace, contains('Future<void> _persistLastPositionLocally'));
      expect(
        workspace,
        contains('Future<void> _synchronizeLastPositionAtBoundary'),
      );
      expect(workspace, contains('didChangeAppLifecycleState'));
      expect(
        workspace,
        contains('unawaited(_synchronizeLastPositionAtBoundary())'),
      );

      final pageTurnSection = workspace.substring(
        workspace.indexOf('void _saveLastPosition'),
        workspace.indexOf('Future<void> _persistLastPositionLocally'),
      );
      expect(pageTurnSection, contains('_positionDirty = true'));
      expect(pageTurnSection, contains('_persistLastPositionLocally'));
      expect(pageTurnSection, isNot(contains('entities.update(')));
      expect(pageTurnSection, isNot(contains('entities.create(')));
      expect(pageTurnSection, isNot(contains('drainOutbox')));

      final boundarySection = workspace.substring(
        workspace.indexOf('Future<void> _synchronizeLastPositionAtBoundary'),
        workspace.indexOf('LocalEntityRecord? _lastSyncedPosition'),
      );
      expect(boundarySection, contains('entities.create('));
      expect(boundarySection, contains('entities.update('));
      expect(boundarySection, contains('synchronizer.drainOutbox'));
      expect(boundarySection, contains('latestPage != pending.page'));
    },
  );
}
