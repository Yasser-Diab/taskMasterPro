#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void ConfigureActivityChannel();
  void ConfigureWindowsShellChannel();
  void AddTrayIcon();
  void UpdateTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void RestoreAndFocus();
  void ExitApplication();
  void SaveWindowPlacement();
  void RestoreWindowPlacement();
  void SendTrayCommand(const std::string& command);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      activity_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      windows_shell_channel_;
  NOTIFYICONDATA tray_icon_data_ = {};
  bool tray_added_ = false;
  bool exit_requested_ = false;
  bool restore_maximized_ = false;
  bool window_maximized_ = false;
  bool window_placement_ready_ = false;
  bool tray_signed_in_ = false;
  bool tray_has_active_task_ = false;
  bool tray_task_paused_ = false;
  bool tray_break_active_ = false;
  bool tray_pomodoro_available_ = false;
  bool tray_focus_complete_ = false;
  bool tray_sync_attention_ = false;
  bool tray_update_available_ = false;
  bool tray_account_deletion_ = false;
  std::wstring tray_active_task_;
  std::wstring tray_elapsed_;
  std::wstring tray_sync_label_ = L"All changes synced";
  std::wstring tray_open_label_ = L"Open TaskMaster Pro";
  std::wstring tray_sign_in_label_ = L"Sign in";
  std::wstring tray_no_task_label_ = L"No task is currently running";
  std::wstring tray_start_next_label_ = L"Start next task";
  std::wstring tray_pause_label_ = L"Pause task";
  std::wstring tray_resume_label_ = L"Resume task";
  std::wstring tray_finish_label_ = L"Finish task";
  std::wstring tray_start_break_label_ = L"Start break";
  std::wstring tray_finish_break_label_ = L"Finish break";
  std::wstring tray_add_interruption_label_ = L"Add interruption";
  std::wstring tray_add_note_label_ = L"Add note";
  std::wstring tray_sync_now_label_ = L"Sync now";
  std::wstring tray_whats_new_label_ = L"What's new in v0.0.30";
  std::wstring tray_settings_label_ = L"Settings";
  std::wstring tray_update_label_ = L"Check for updates";
  std::wstring tray_exit_label_ = L"Exit TaskMaster Pro";
  std::wstring tray_deletion_label_ = L"Account deletion scheduled";
  std::wstring tray_tooltip_break_ = L"Break in progress";
  std::wstring tray_tooltip_paused_ = L"Task paused";
  std::wstring tray_tooltip_sync_attention_ = L"Sync needs attention";
  std::wstring tray_still_running_title_ = L"TaskMaster Pro is still running";
  std::wstring tray_still_running_body_ =
      L"Timers and reminders will continue in the background. Use the tray "
      L"icon to reopen or exit the app.";
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
