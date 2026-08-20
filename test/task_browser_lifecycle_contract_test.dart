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

  test('a failed page never poisons the next main-frame navigation', () {
    final navigation = TaskBrowserNavigationState(
      'https://example.com/first-lesson',
    );

    expect(
      navigation.fail(
        url: 'https://example.com/first-lesson',
        isForMainFrame: true,
      ),
      isTrue,
    );
    expect(navigation.failedUrl, 'https://example.com/first-lesson');

    navigation.begin('https://www.google.com/search?q=lesson');
    expect(navigation.hasFailure, isFalse);
    expect(navigation.currentUrl, 'https://www.google.com/search?q=lesson');

    // Android may report cancellation of the abandoned request after the new
    // page starts. That callback cannot cover the current page.
    expect(
      navigation.fail(
        url: 'https://example.com/first-lesson',
        isForMainFrame: true,
      ),
      isFalse,
    );
    expect(navigation.hasFailure, isFalse);
  });

  test('retry and external fallback keep the actual failed document URL', () {
    final navigation = TaskBrowserNavigationState('https://example.com/');
    navigation.begin('https://www.freecodecamp.org/learn/javascript-v9/');
    navigation.fail(
      url: 'https://www.freecodecamp.org/learn/javascript-v9/',
      isForMainFrame: true,
    );

    expect(
      navigation.fallbackUrl('https://example.com/'),
      'https://www.freecodecamp.org/learn/javascript-v9/',
    );
    navigation.begin(navigation.fallbackUrl('https://example.com/'));
    expect(navigation.hasFailure, isFalse);
  });

  test('subresource failures do not replace a healthy main document', () {
    final navigation = TaskBrowserNavigationState('https://example.com/');

    expect(
      navigation.fail(
        url: 'https://cdn.example.com/missing.png',
        isForMainFrame: false,
      ),
      isFalse,
    );
    expect(navigation.hasFailure, isFalse);
  });

  test('fresh successful navigation clears the prior document failure', () {
    final navigation = TaskBrowserNavigationState('https://example.com/');
    navigation.fail(url: 'https://example.com/', isForMainFrame: true);
    // Android can finish its generated error page for the same URL; keep the
    // visible failure until the user initiates a fresh request.
    navigation.finish('https://example.com/');
    expect(navigation.hasFailure, isTrue);

    navigation.begin('https://www.freecodecamp.org/learn/');
    navigation.finish('https://www.freecodecamp.org/learn/');

    expect(navigation.hasFailure, isFalse);
    expect(navigation.currentUrl, 'https://www.freecodecamp.org/learn/');
  });

  test('new-tab messages accept resolved HTTP links only', () {
    expect(
      taskBrowserNewTabUrl(
        '{"type":"taskmaster-open-new-tab",'
        '"url":"https://www.freecodecamp.org/learn/"}',
      ),
      'https://www.freecodecamp.org/learn/',
    );
    expect(
      taskBrowserNewTabUrl('https://www.youtube.com/watch?v=lesson'),
      'https://www.youtube.com/watch?v=lesson',
    );
    expect(
      taskBrowserNewTabUrl({
        'type': 'untrusted-message',
        'url': 'https://example.com/',
      }),
      isNull,
    );
    expect(taskBrowserNewTabUrl('intent://launch-app'), isNull);
    expect(taskBrowserNewTabUrl('javascript:alert(1)'), isNull);
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
    expect(source, contains('onPageStarted: (url)'));
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

  test('browser timer pill exposes every canonical interval command', () {
    final source = File(
      'lib/features/tasks/presentation/task_browser_workspace.dart',
    ).readAsStringSync();

    expect(source, contains("ValueKey('browser-task-primary-control')"));
    expect(source, contains("ValueKey('browser-task-more-controls')"));
    expect(source, contains('_BrowserTimerAction.startBreakEarly'));
    expect(source, contains('_BrowserTimerAction.skipOfferedBreak'));
    expect(source, contains('_BrowserTimerAction.extendBreak'));
    expect(source, contains('_BrowserTimerAction.finishTask'));
    expect(source, contains('TaskExecutionCommands.skipOfferedBreak('));
    expect(source, contains('TaskExecutionCommands.extendBreak('));
  });
}
