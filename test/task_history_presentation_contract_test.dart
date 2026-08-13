import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history resolves task and session records without raw identities', () {
    final source = File(
      'lib/features/tasks/presentation/task_workspace_screen.dart',
    ).readAsStringSync();

    for (final entityType in const [
      'execution_sessions',
      'session_events',
      'pomodoro_cycles',
      'interruptions',
      'task_application_links',
      'website_rules',
      'task_resources',
      'resource_activity',
    ]) {
      expect(source, contains("'$entityType'"));
    }
    expect(source, contains('_historyRecordReferencesTask'));
    expect(source, contains('_historyDetails'));
    expect(source, contains('_historySafeLabel'));
    expect(source, contains('history_duration'));
    expect(source, contains('history_device'));
    expect(source, contains('history_resource'));
  });
}
