import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relativePath) =>
    File('${Directory.current.path}/$relativePath').readAsStringSync();

void main() {
  test('release-facing version metadata is aligned to v0.0.29', () {
    expect(_read('pubspec.yaml'), contains('version: 0.0.29+57'));
    expect(_read('package.json'), contains('"version": "0.0.29"'));
    expect(_read('package-lock.json'), contains('"version": "0.0.29"'));
    expect(
      _read('installer/taskmaster-pro.iss'),
      contains('#define MyAppVersion "0.0.29"'),
    );
    expect(
      _read('lib/core/platform/windows_shell_service.dart'),
      contains("'version': '0.0.29'"),
    );
    expect(
      _read('windows/runner/flutter_window.h'),
      contains('What\'s new in v0.0.29'),
    );
    expect(
      _read('lib/features/settings/presentation/settings_screen.dart'),
      contains("String _version = '0.0.29';"),
    );
  });

  test('package script uses only the staged toolchain and fails closed', () {
    final script = _read('scripts/package-release.ps1');
    final androidGradle = _read('android/app/build.gradle.kts');
    final installer = _read('installer/taskmaster-pro.iss');

    expect(script, contains("\$toolRoot = 'E:\\codingTools'"));
    expect(script, contains('Resolve-StagedTool'));
    expect(script, contains('& \$npm ci'));
    expect(script, contains('& \$flutter build windows --release'));
    expect(script, contains('& \$flutter build apk --release'));
    expect(script, contains('& \$flutter build appbundle --release'));
    expect(script, contains('Android App Bundle signature verification'));
    expect(script, contains(r'$displayVersion = "$version+$buildNumber"'));
    expect(script, contains(r'ProductVersion'));
    expect(script, contains('Windows build version mismatch'));
    expect(script, contains('Windows app snapshot'));
    expect(script, contains('Refusing to package a stale backend'));
    expect(
      script,
      contains('Anonymous application learning is not configured'),
    );
    expect(script, contains(r'$learningProjectRefMatch.Groups[1].Value'));
    expect(script, contains(r'$learningKeyMatch.Groups[1].Value'));
    expect(script, contains(r'/DMyAppDisplayVersion=$displayVersion'));
    expect(script, contains('buildNumber = [int]\$buildNumber'));
    expect(script, contains('displayVersion = \$displayVersion'));
    expect(installer, contains('#define MyAppDisplayVersion MyAppVersion'));
    expect(installer, contains('AppVersion={#MyAppDisplayVersion}'));
    expect(installer, contains('UsePreviousAppDir=no'));
    expect(
      installer,
      contains("ExpandConstant('{localappdata}\\Programs\\TaskMaster Pro')"),
    );
    expect(installer, contains('FileExists(LegacyUninstaller)'));
    expect(installer, contains('DelTree(LegacyDir, True, True, True)'));
    expect(script, isNot(contains('& npm ci')));
    expect(script, isNot(contains('Get-Command iscc.exe')));
    expect(script, contains('Refusing to generate a replacement key'));
    expect(script, contains('Refusing to fall back to a debug'));
    expect(
      androidGradle,
      contains('Release builds require android/key.properties'),
    );
    expect(androidGradle, isNot(contains('signingConfigs.getByName("debug")')));
  });

  test('Windows tray reveal preserves a maximized window placement', () {
    final runner = _read('windows/runner/flutter_window.cpp');
    final start = runner.indexOf('void FlutterWindow::RestoreAndFocus()');
    expect(start, greaterThanOrEqualTo(0));
    final end = runner.indexOf(
      '\n}\n\nvoid FlutterWindow::SaveWindowPlacement',
      start,
    );
    expect(end, greaterThan(start));
    final restore = runner.substring(start, end);

    expect(restore, contains('IsIconic(hwnd)'));
    expect(restore, contains('SW_RESTORE'));
    expect(restore, contains('IsZoomed(hwnd)'));
    expect(restore, contains('SW_SHOWMAXIMIZED'));
    expect(restore, contains('ShowWindow(hwnd, SW_SHOW);'));
  });

  test('Windows persists placement before plugins consume native messages', () {
    final runner = _read('windows/runner/flutter_window.cpp');
    final handlerStart = runner.indexOf('FlutterWindow::MessageHandler(');
    final pluginDispatch = runner.indexOf(
      '// Give Flutter, including plugins, an opportunity',
      handlerStart,
    );
    final nativeCapture = runner.indexOf(
      'if (window_placement_ready_) {',
      handlerStart,
    );

    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(nativeCapture, greaterThan(handlerStart));
    expect(nativeCapture, lessThan(pluginDispatch));
    expect(runner, contains('wparam == SIZE_MAXIMIZED'));
    expect(runner, contains('window_maximized_ = true'));
    expect(runner, contains('window_placement_ready_ = true'));
    expect(runner, contains('placement.showCmd == SW_SHOWMAXIMIZED'));
    expect(runner, contains('kWindowPlacementVersion = 3'));
    expect(runner, contains('L"PlacementVersion"'));
  });
}
