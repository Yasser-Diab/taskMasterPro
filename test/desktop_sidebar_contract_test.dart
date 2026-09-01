import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/shell/presentation/home_shell.dart';

void main() {
  test('health is a top-level destination on Android and Windows', () {
    expect(showsHealthShellDestination(TargetPlatform.android), isTrue);
    expect(showsHealthShellDestination(TargetPlatform.windows), isTrue);
    expect(showsHealthShellDestination(TargetPlatform.iOS), isFalse);
  });

  test('Ctrl plus physical B ignores the active character layout', () {
    final event = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyB,
      logicalKey: LogicalKeyboardKey.keyQ,
      character: 'ض',
      timeStamp: Duration.zero,
    );

    expect(
      acceptsDesktopSidebarShortcut(
        event: event,
        pressedKeys: {
          PhysicalKeyboardKey.controlLeft,
          PhysicalKeyboardKey.keyB,
        },
      ),
      isTrue,
    );
    expect(
      acceptsDesktopSidebarShortcut(
        event: event,
        pressedKeys: {PhysicalKeyboardKey.keyB},
      ),
      isFalse,
    );
  });

  test('sidebar keeps explicit collapse and expand affordances', () async {
    final source = await File(
      'lib/features/shell/presentation/home_shell.dart',
    ).readAsString();
    expect(source, contains("'desktop-sidebar-toggle'"));
    expect(source, contains('Icons.chevron_left_rounded'));
    expect(source, contains('Icons.chevron_right_rounded'));
    expect(source, contains('dimension: 38'));
    expect(source, contains('symbolOnly: !expanded'));
    expect(source, contains('addHandler(_handleDesktopSidebarKeyEvent)'));
    expect(source, contains('removeHandler(_handleDesktopSidebarKeyEvent)'));
    expect(source, contains('HardwareKeyboard.instance.physicalKeysPressed'));

    final windowsRunner = await File(
      'windows/runner/flutter_window.cpp',
    ).readAsString();
    expect(windowsRunner, contains('kPhysicalBScanCode = 0x30'));
    expect(windowsRunner, contains('GetKeyState(VK_CONTROL)'));
    expect(windowsRunner, contains('HandleAccelerator(const MSG& message)'));
    expect(windowsRunner, contains('SendTrayCommand("toggleSidebar")'));

    final windowsMain = await File('windows/runner/main.cpp').readAsString();
    expect(windowsMain, contains('YADiab.DayVector.SingleInstance.v1'));
    expect(windowsMain, contains('ActivateRunningInstance()'));
    expect(windowsMain, contains('window.HandleAccelerator(msg)'));
  });
}
