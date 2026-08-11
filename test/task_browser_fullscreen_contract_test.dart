import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full-screen task browsing reuses the resident workspace', () {
    final browserSource = File(
      'lib/features/tasks/presentation/task_browser_workspace.dart',
    ).readAsStringSync();
    final workspaceSource = File(
      'lib/features/tasks/presentation/task_workspace_screen.dart',
    ).readAsStringSync();

    expect(browserSource, contains('final _browserControllers'));
    expect(browserSource, contains('IndexedStack('));
    expect(browserSource, contains("ValueKey('task-browser-tab-\${tab.id}')"));
    expect(browserSource, isNot(contains('_TaskBrowserFullscreenPage')));
    expect(browserSource, contains('onFullScreenChanged(!widget.fullScreen)'));
    expect(browserSource, contains('void didUpdateWidget('));
    expect(browserSource, contains('_openRequestedUrl(widget.initialUrl)'));
    expect(workspaceSource, contains('_browserWorkspaceKey'));
    expect(workspaceSource, contains('_browserWorkspaceStarted'));
    expect(workspaceSource, contains('Offstage('));
    expect(workspaceSource, contains('SystemUiMode.immersiveSticky'));
    expect(workspaceSource, contains('PopScope('));
  });
}
