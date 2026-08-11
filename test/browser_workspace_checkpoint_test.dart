import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/tasks/domain/browser_workspace_checkpoint.dart';

void main() {
  test(
    'checkpoint parsing is bounded and stable across WebView result shapes',
    () {
      const raw = '''
      {"url":"https://www.freecodecamp.org/learn/javascript-v9/?utm=a",
       "title":"JavaScript lesson",
       "scroll_x":-12,
       "scroll_y":160.678,
       "media_position_seconds":82.349,
       "zoom_scale":8}
    ''';

      final direct = BrowserWorkspaceCheckpoint.fromJavaScript(raw);
      final quoted = BrowserWorkspaceCheckpoint.fromJavaScript(jsonEncode(raw));

      expect(
        direct.url,
        'https://www.freecodecamp.org/learn/javascript-v9/?utm=a',
      );
      expect(direct.scrollX, 0);
      expect(direct.scrollY, 160.68);
      expect(direct.mediaPositionSeconds, 82.35);
      expect(direct.zoomScale, 4);
      expect(quoted.sameContent(direct), isTrue);
      expect(
        direct.sameContent(direct.stamped(DateTime.utc(2026, 8, 10))),
        isTrue,
      );
    },
  );

  test('restore applies only to the same safe document path', () {
    const checkpoint = BrowserWorkspaceCheckpoint(
      url: 'https://www.freecodecamp.org/learn/javascript-v9/lesson-one?x=1',
      scrollY: 420,
      mediaPositionSeconds: 73,
    );

    expect(
      checkpoint.matchesPage(
        'https://www.freecodecamp.org/learn/javascript-v9/lesson-one?utm=abc#top',
      ),
      isTrue,
    );
    expect(
      checkpoint.matchesPage(
        'https://www.freecodecamp.org/learn/javascript-v9/',
      ),
      isFalse,
    );
    expect(
      checkpoint.matchesPage(
        'https://example.com/learn/javascript-v9/lesson-one',
      ),
      isFalse,
    );
  });

  test('restore script seeks without autoplaying or touching forms', () {
    const checkpoint = BrowserWorkspaceCheckpoint(
      url: 'https://example.com/lesson',
      scrollX: 10,
      scrollY: 200,
      mediaPositionSeconds: 45,
    );
    final script = buildBrowserWorkspaceCheckpointRestoreScript(checkpoint);

    expect(script, contains('window.scrollTo'));
    expect(script, contains('loadedmetadata'));
    expect(script, isNot(contains('.play(')));
    expect(script, isNot(contains('input')));
  });

  test('checkpoints are local/debounced and synchronize only at boundaries', () {
    final workspace = File(
      'lib/features/tasks/presentation/task_browser_workspace.dart',
    ).readAsStringSync();
    final webview = File(
      'lib/features/tasks/presentation/cross_platform_webview.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260810143000_v0028_browser_workspace_checkpoints.sql',
    ).readAsStringSync();

    expect(workspace, contains('const Duration(seconds: 20)'));
    expect(workspace, contains('Future<void> _flushLocalCheckpoint'));
    expect(workspace, contains('entities.updateLocalData(latest, data: data)'));
    expect(workspace, contains('Future<bool> _synchronizeCheckpoint'));
    expect(workspace, contains('_checkpointBeforeBackground'));
    expect(workspace, contains('_checkpointBeforeTaskExit'));
    expect(workspace, contains('_metadataDirtyTabs'));
    expect(workspace, isNot(contains("entityType: 'browser_history_events'")));
    final localMetadataSection = workspace.substring(
      workspace.indexOf('Future<void> _flushMetadataUpdate'),
      workspace.indexOf('Future<void> _addBookmark'),
    );
    expect(localMetadataSection, contains('entities.updateLocalData'));
    expect(localMetadataSection, isNot(contains('entities.update(')));
    expect(localMetadataSection, isNot(contains('drainOutbox')));
    expect(webview, contains('browserWorkspaceCheckpointCaptureScript'));
    expect(webview, contains('_restorePendingCheckpoint'));
    expect(
      browserWorkspaceCheckpointCaptureScript,
      isNot(contains("addEventListener('scroll'")),
    );
    expect(migration, contains('add column if not exists checkpoint jsonb'));
  });
}
