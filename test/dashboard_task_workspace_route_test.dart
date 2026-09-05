import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard navigation passes the selected immutable task id', () {
    final source = File(
      'lib/features/dashboard/presentation/dashboard_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(source, contains('TaskWorkspaceScreen.openForTaskId('));
    expect(source, contains('widget.task.id,'));
    expect(source, contains('task.id,\n          initialSection: 1'));
  });

  test('workspace routes are keyed by the task they resolve', () {
    final source = File(
      'lib/features/tasks/presentation/task_workspace_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(source, contains('static Future<void> openForTaskId('));
    expect(source, contains("ValueKey('task-workspace:\$targetTaskId')"));
    expect(source, contains("name: 'task-workspace/\$targetTaskId'"));
  });
}
