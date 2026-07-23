#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <wrl.h>
#include <WebView2.h>

#include <map>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

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
  static LRESULT CALLBACK BrowserWindowProc(HWND hwnd, UINT message,
                                            WPARAM wparam, LPARAM lparam);
  void ConfigureLifecycleChannel();
  void ConfigureDeepLinkChannel();
  void ConfigureInteractionFeedbackChannel();
  void ConfigureProfileFilesChannel();
  void ConfigureTaskBrowserChannel();
  void ConfigureTaskReminderChannel();
  void AddTrayIcon();
  void RemoveTrayIcon();
  void UpdateTrayTooltip();
  void ShowTrayMenu();
  void HandleTrayCommand(UINT command);
  void SendTrayCommand(const std::string& command);
  void SendDeepLink(const std::wstring& link);
  std::optional<std::vector<uint8_t>> PickAvatarImageBytes();
  std::optional<std::string> PickReadingFilePath();
  void InitializeClickSound(const std::vector<uint8_t>& bytes);
  void SetClickVolume(double volume);
  void PlayClickSound();
  void EnsureBrowser(const std::wstring& url, const std::wstring& profile_id);
  void ShowDockedBrowser(double x, double y, double width, double height,
                         const std::wstring& url,
                         const std::wstring& profile_id);
  void PositionBrowser(double x, double y, double width, double height);
  void HideBrowser();
  void NavigateBrowser(const std::wstring& url);
  void BrowserGoBack();
  void BrowserGoForward();
  void BrowserReload();
  void BrowserStop();
  void BrowserDetach(const std::wstring& title);
  void BrowserDock();
  std::wstring CurrentBrowserDocumentTitle();
  void SendBrowserEvent(bool loading, const std::wstring& url,
                        const std::wstring& error = L"",
                        const std::wstring& new_tab_url = L"",
                        const std::wstring& title = L"");
  void ResetBrowserForProfile();
  HWND BrowserParentWindow();
  std::wstring BrowserUserDataFolder(const std::wstring& profile_id);
  std::wstring WindowStateFile();
  RECT ClampMainWindowRect(RECT rect);
  void RestoreMainWindowState();
  void SaveMainWindowState();
  void ResetMainWindowPosition();
  void CreateBrowserHostIfNeeded();
  void CreateDetachedWindowIfNeeded(const std::wstring& title);
  void ExitApplication();
  void ScheduleTaskReminder(const std::wstring& id,
                            const std::wstring& task_id,
                            const std::wstring& title,
                            const std::wstring& body,
                            int64_t trigger_at);
  void CancelTaskReminders(const std::wstring& task_id);
  void HandleTaskReminderTimer(UINT_PTR timer_id);
  void ShowTaskReminderNow(const std::wstring& id,
                           const std::wstring& task_id,
                           const std::wstring& title,
                           const std::wstring& body,
                           const std::wstring& channel);
  void PlayPackagedNotificationSound(const std::wstring& channel);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lifecycle_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      deep_link_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      interaction_feedback_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      profile_files_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      task_browser_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      task_reminder_channel_;

  Microsoft::WRL::ComPtr<ICoreWebView2Environment> browser_environment_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> browser_controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> browser_webview_;

  NOTIFYICONDATA tray_icon_data_ = {};
  HWND browser_host_window_ = nullptr;
  HWND detached_browser_window_ = nullptr;
  bool tray_added_ = false;
  bool exit_requested_ = false;
  bool exit_in_progress_ = false;
  bool has_active_session_ = false;
  bool click_sound_ready_ = false;
  bool browser_creating_ = false;
  bool browser_detached_ = false;
  bool com_initialized_ = false;
  bool browser_password_autosave_enabled_ = false;
  bool browser_general_autofill_enabled_ = true;
  bool start_maximized_ = false;
  int browser_creation_count_ = 0;
  int browser_navigation_count_ = 0;
  double click_volume_ = 0.65;
  std::wstring active_session_summary_;
  std::wstring click_sound_path_;
  std::wstring last_notification_at_;
  std::wstring last_notification_result_;
  std::wstring browser_id_;
  std::wstring browser_profile_id_;
  std::wstring browser_current_url_;
  std::wstring browser_last_error_;
  std::map<UINT, std::wstring> tray_labels_;
  struct ScheduledTaskReminder {
    std::wstring id;
    std::wstring task_id;
    std::wstring title;
    std::wstring body;
    int64_t trigger_at = 0;
  };
  std::map<UINT_PTR, ScheduledTaskReminder> task_reminders_;
  UINT_PTR next_task_reminder_timer_id_ = 70000;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
