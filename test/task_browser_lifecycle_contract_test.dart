import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/tasks/presentation/cross_platform_webview.dart';

void main() {
  test('only regular web URLs can be requested as task-browser tabs', () {
    expect(isTaskBrowserWebUrl('https://www.freecodecamp.org/learn/'), isTrue);
    expect(isTaskBrowserWebUrl('http://localhost:8080/lesson'), isTrue);
    expect(isTaskBrowserWebUrl('mailto:learn@example.com'), isFalse);
    expect(isTaskBrowserWebUrl('intent://open-example'), isFalse);
    expect(isTaskBrowserWebUrl('javascript:alert(1)'), isFalse);
  });

  test('native browser integrations bridge popup requests into task tabs', () {
    final source = File(
      'lib/features/tasks/presentation/cross_platform_webview.dart',
    ).readAsStringSync();

    expect(source, contains('TaskMasterBrowserNewTab'));
    expect(source, contains('taskmaster-open-new-tab'));
    expect(source, contains('addScriptToExecuteOnDocumentCreated'));
    expect(source, contains('WebviewPopupWindowPolicy.sameWindow'));
    expect(
      source,
      contains('onNavigationRequest: _handleMobileNavigationRequest'),
    );
    expect(source, contains('onPageStarted: (_)'));
  });

  test('tab metadata writes are coalesced per tab instead of dropping URLs', () {
    final source = File(
      'lib/features/tasks/presentation/task_browser_workspace.dart',
    ).readAsStringSync();

    expect(source, contains('final _metadataDebounces = <String, Timer>{}'));
    expect(source, contains('final _pendingMetadataUrls = <String, String>{}'));
    expect(
      source,
      contains('Future<void> _flushMetadataUpdate('),
      reason:
          'Navigation metadata is flushed locally, then sent only by the checkpoint boundary.',
    );
    expect(
      source,
      contains('await entities.updateLocalData(latest, data: data)'),
    );
    expect(source, contains('Future<bool> _synchronizeCheckpoint('));
    expect(source, isNot(contains("entityType: 'browser_history_events'")));
    expect(source, contains('onOpenNewTab: (url)'));
  });
}
