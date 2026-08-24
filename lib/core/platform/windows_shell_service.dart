import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_localizations.dart';

class WindowsTrayState {
  const WindowsTrayState({
    required this.signedIn,
    required this.hasActiveTask,
    required this.taskPaused,
    required this.breakActive,
    required this.activeTask,
    required this.elapsed,
    required this.syncLabel,
    required this.syncAttention,
    required this.localeCode,
    this.pomodoroAvailable = false,
    this.focusComplete = false,
    this.updateAvailable = false,
    this.accountDeletion = false,
  });

  final bool signedIn;
  final bool hasActiveTask;
  final bool taskPaused;
  final bool breakActive;
  final bool pomodoroAvailable;
  final bool focusComplete;
  final String activeTask;
  final String elapsed;
  final String syncLabel;
  final bool syncAttention;
  final String localeCode;
  final bool updateAvailable;
  final bool accountDeletion;

  Map<String, Object?> toMap() {
    final l10n = AppLocalizations(Locale(localeCode));
    return {
      'signedIn': signedIn,
      'hasActiveTask': hasActiveTask,
      'taskPaused': taskPaused,
      'breakActive': breakActive,
      'pomodoroAvailable': pomodoroAvailable,
      'focusComplete': focusComplete,
      'activeTask': activeTask,
      'elapsed': elapsed,
      'syncLabel': syncLabel,
      'syncAttention': syncAttention,
      'updateAvailable': updateAvailable,
      'accountDeletion': accountDeletion,
      'openLabel': l10n.text('tray_open'),
      'signInLabel': l10n.text('sign_in'),
      'noTaskLabel': l10n.text('tray_no_task'),
      'startNextLabel': l10n.text('tray_start_next'),
      'pauseLabel': l10n.text('tray_pause_task'),
      'resumeLabel': l10n.text('tray_resume_task'),
      'finishLabel': l10n.text('finish_task'),
      'startBreakLabel': l10n.text('tray_start_break'),
      'finishBreakLabel': l10n.text('tray_finish_break'),
      'addInterruptionLabel': l10n.text('add_interruption'),
      'addNoteLabel': l10n.text('add_note'),
      'syncNowLabel': l10n.text('sync_now'),
      'whatsNewLabel': l10n.format('tray_whats_new_version', {
        'version': '0.0.28',
      }),
      'settingsLabel': l10n.text('settings'),
      'updateLabel': l10n.text(
        updateAvailable ? 'tray_update_available' : 'tray_check_updates',
      ),
      'exitLabel': l10n.text('tray_exit'),
      'deletionLabel': l10n.text('tray_deletion_scheduled'),
      'tooltipBreak': l10n.text('tray_tooltip_break'),
      'tooltipPaused': l10n.text('tray_tooltip_paused'),
      'tooltipSyncAttention': l10n.text('sync_needs_attention'),
      'stillRunningTitle': l10n.text('tray_still_running_title'),
      'stillRunningBody': l10n.text('tray_still_running_body'),
    };
  }
}

class WindowsShellService {
  WindowsShellService._() {
    if (Platform.isWindows) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'trayCommand' && call.arguments is String) {
          _commands.add(call.arguments as String);
        }
      });
    }
  }

  static final instance = WindowsShellService._();
  static const _channel = MethodChannel('taskmasterpro/windows_shell');
  final _commands = StreamController<String>.broadcast();

  Stream<String> get commands => _commands.stream;

  Future<void> updateTray(WindowsTrayState state) async {
    if (!Platform.isWindows) return;
    await _channel.invokeMethod<void>('updateTray', state.toMap());
  }

  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    await _channel.invokeMethod<void>('showWindow');
  }

  Future<void> exitApplication() async {
    if (!Platform.isWindows) return;
    await _channel.invokeMethod<void>('exitApplication');
  }
}
