import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _runnerSource() => File(
  '${Directory.current.path}/windows/runner/flutter_window.cpp',
).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('tray reveal uses remembered maximized state before restoring', () {
    final source = _runnerSource();
    final start = source.indexOf('void FlutterWindow::RestoreAndFocus()');
    final end = source.indexOf(
      '\n}\n\nvoid FlutterWindow::SaveWindowPlacement',
      start,
    );
    final restore = source.substring(start, end);

    expect(restore, contains('window_maximized_ || IsZoomed(hwnd)'));
    expect(restore, contains('ShowWindow(hwnd, SW_SHOWMAXIMIZED)'));
    expect(
      restore.indexOf('ShowWindow(hwnd, SW_SHOWMAXIMIZED)'),
      lessThan(restore.indexOf('ShowWindow(hwnd, SW_RESTORE)')),
    );
  });

  test('native messages do not confuse tray hiding with user restore', () {
    final source = _runnerSource();

    expect(source, contains('message == WM_SYSCOMMAND'));
    expect(source, contains('case SC_MAXIMIZE:'));
    expect(source, contains('case SC_RESTORE:'));
    expect(
      source,
      contains(
        'message == WM_SIZE && wparam == SIZE_RESTORED &&\n'
        '               IsWindowVisible(hwnd)',
      ),
    );
    expect(source, contains('message == WM_EXITSIZEMOVE'));
  });

  test('broken placements are invalidated and restored bounds stay usable', () {
    final source = _runnerSource();

    expect(source, contains('kWindowPlacementVersion = 3'));
    expect(source, contains('kMinimumRestoredWidth = 960'));
    expect(source, contains('kMinimumRestoredHeight = 640'));
    expect(source, contains('const DWORD invalid_version = 0'));
    expect(source, contains('std::clamp(width, minimum_width, work_width)'));
    expect(source, contains('std::clamp(height, minimum_height, work_height)'));
    expect(
      source,
      contains('MonitorFromRect(&desired, MONITOR_DEFAULTTONEAREST)'),
    );
  });
}
