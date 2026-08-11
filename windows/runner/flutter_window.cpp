#include "flutter_window.h"

#include <algorithm>
#include <iterator>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {
constexpr UINT kTrayCallbackMessage = WM_APP + 25;
constexpr UINT kTrayCommandOpen = 62001;
constexpr UINT kTrayCommandActiveTask = 62002;
constexpr UINT kTrayCommandPauseResume = 62003;
constexpr UINT kTrayCommandFinishTask = 62004;
constexpr UINT kTrayCommandBreak = 62005;
constexpr UINT kTrayCommandInterruption = 62006;
constexpr UINT kTrayCommandNote = 62007;
constexpr UINT kTrayCommandSyncPanel = 62008;
constexpr UINT kTrayCommandSyncNow = 62009;
constexpr UINT kTrayCommandWhatsNew = 62010;
constexpr UINT kTrayCommandSettings = 62011;
constexpr UINT kTrayCommandUpdate = 62012;
constexpr UINT kTrayCommandExit = 62013;
constexpr UINT kTrayCommandSignIn = 62014;
constexpr UINT kTrayCommandStartNext = 62015;
constexpr UINT kTrayCommandDeletion = 62016;
constexpr wchar_t kTrayTooltip[] = L"TaskMaster Pro";
constexpr wchar_t kWindowRegistryPath[] =
    L"Software\\Y. A. Diab\\TaskMaster Pro\\Window";

std::optional<flutter::EncodableMap> ArgumentMap(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) {
    return std::nullopt;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  return map == nullptr ? std::nullopt
                        : std::optional<flutter::EncodableMap>(*map);
}

std::wstring StringValue(const flutter::EncodableMap& map,
                         const std::string& key,
                         const std::wstring& fallback = L"") {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  const auto* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? fallback : Utf16FromUtf8(*value);
}

bool BoolValue(const flutter::EncodableMap& map,
               const std::string& key,
               bool fallback = false) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  const auto* value = std::get_if<bool>(&iterator->second);
  return value == nullptr ? fallback : *value;
}

bool RegistryFlagEnabled(const wchar_t* name) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kWindowRegistryPath, 0, KEY_QUERY_VALUE,
                    &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD value = 0;
  DWORD type = 0;
  DWORD size = sizeof(value);
  const bool enabled =
      RegQueryValueExW(key, name, nullptr, &type,
                       reinterpret_cast<BYTE*>(&value),
                       &size) == ERROR_SUCCESS &&
      type == REG_DWORD && value != 0;
  RegCloseKey(key);
  return enabled;
}

void SetRegistryFlag(const wchar_t* name) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kWindowRegistryPath, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  const DWORD value = 1;
  RegSetValueExW(key, name, 0, REG_DWORD,
                 reinterpret_cast<const BYTE*>(&value), sizeof(value));
  RegCloseKey(key);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { RemoveTrayIcon(); }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RestoreWindowPlacement();
  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  ConfigureActivityChannel();
  ConfigureWindowsShellChannel();
  AddTrayIcon();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    if (restore_maximized_) {
      ShowWindow(GetHandle(), SW_MAXIMIZE);
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::ConfigureActivityChannel() {
  activity_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/activity",
          &flutter::StandardMethodCodec::GetInstance());

  activity_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "sampleForegroundActivity") {
          result->NotImplemented();
          return;
        }

        const HWND foreground = GetForegroundWindow();
        if (foreground == nullptr) {
          result->Success();
          return;
        }

        wchar_t title_buffer[1024] = {};
        GetWindowTextW(foreground, title_buffer,
                       static_cast<int>(std::size(title_buffer)));

        DWORD process_id = 0;
        GetWindowThreadProcessId(foreground, &process_id);
        std::wstring application_name;
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,
                                     FALSE, process_id);
        if (process != nullptr) {
          wchar_t path_buffer[32768] = {};
          DWORD path_size = static_cast<DWORD>(std::size(path_buffer));
          if (QueryFullProcessImageNameW(process, 0, path_buffer,
                                         &path_size)) {
            std::wstring path(path_buffer, path_size);
            const size_t separator = path.find_last_of(L"\\/");
            application_name = separator == std::wstring::npos
                                   ? path
                                   : path.substr(separator + 1);
          }
          CloseHandle(process);
        }

        LASTINPUTINFO last_input = {};
        last_input.cbSize = sizeof(LASTINPUTINFO);
        DWORD idle_seconds = 0;
        if (GetLastInputInfo(&last_input)) {
          idle_seconds = static_cast<DWORD>(
              (GetTickCount64() - last_input.dwTime) / 1000);
        }

        flutter::EncodableMap sample;
        sample[flutter::EncodableValue("applicationName")] =
            flutter::EncodableValue(
                Utf8FromUtf16(application_name.c_str()));
        sample[flutter::EncodableValue("windowTitle")] =
            flutter::EncodableValue(Utf8FromUtf16(title_buffer));
        sample[flutter::EncodableValue("idleSeconds")] =
            flutter::EncodableValue(static_cast<int>(idle_seconds));
        sample[flutter::EncodableValue("isTaskMasterWindow")] =
            flutter::EncodableValue(foreground == GetHandle());
        result->Success(flutter::EncodableValue(sample));
      });
}

void FlutterWindow::ConfigureWindowsShellChannel() {
  windows_shell_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/windows_shell",
          &flutter::StandardMethodCodec::GetInstance());
  windows_shell_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "updateTray") {
          const auto arguments = ArgumentMap(call.arguments());
          if (!arguments.has_value()) {
            result->Error("invalid_arguments", "Tray state is required");
            return;
          }
          const auto& map = arguments.value();
          tray_signed_in_ = BoolValue(map, "signedIn");
          tray_has_active_task_ = BoolValue(map, "hasActiveTask");
          tray_task_paused_ = BoolValue(map, "taskPaused");
          tray_break_active_ = BoolValue(map, "breakActive");
          tray_pomodoro_available_ = BoolValue(map, "pomodoroAvailable");
          tray_focus_complete_ = BoolValue(map, "focusComplete");
          tray_sync_attention_ = BoolValue(map, "syncAttention");
          tray_update_available_ = BoolValue(map, "updateAvailable");
          tray_account_deletion_ = BoolValue(map, "accountDeletion");
          tray_active_task_ = StringValue(map, "activeTask");
          tray_elapsed_ = StringValue(map, "elapsed");
          tray_sync_label_ =
              StringValue(map, "syncLabel", tray_sync_label_);
          tray_open_label_ =
              StringValue(map, "openLabel", tray_open_label_);
          tray_sign_in_label_ =
              StringValue(map, "signInLabel", tray_sign_in_label_);
          tray_no_task_label_ =
              StringValue(map, "noTaskLabel", tray_no_task_label_);
          tray_start_next_label_ =
              StringValue(map, "startNextLabel", tray_start_next_label_);
          tray_pause_label_ =
              StringValue(map, "pauseLabel", tray_pause_label_);
          tray_resume_label_ =
              StringValue(map, "resumeLabel", tray_resume_label_);
          tray_finish_label_ =
              StringValue(map, "finishLabel", tray_finish_label_);
          tray_start_break_label_ =
              StringValue(map, "startBreakLabel", tray_start_break_label_);
          tray_finish_break_label_ =
              StringValue(map, "finishBreakLabel", tray_finish_break_label_);
          tray_add_interruption_label_ = StringValue(
              map, "addInterruptionLabel", tray_add_interruption_label_);
          tray_add_note_label_ =
              StringValue(map, "addNoteLabel", tray_add_note_label_);
          tray_sync_now_label_ =
              StringValue(map, "syncNowLabel", tray_sync_now_label_);
          tray_whats_new_label_ =
              StringValue(map, "whatsNewLabel", tray_whats_new_label_);
          tray_settings_label_ =
              StringValue(map, "settingsLabel", tray_settings_label_);
          tray_update_label_ =
              StringValue(map, "updateLabel", tray_update_label_);
          tray_exit_label_ =
              StringValue(map, "exitLabel", tray_exit_label_);
          tray_deletion_label_ =
              StringValue(map, "deletionLabel", tray_deletion_label_);
          tray_tooltip_break_ =
              StringValue(map, "tooltipBreak", tray_tooltip_break_);
          tray_tooltip_paused_ =
              StringValue(map, "tooltipPaused", tray_tooltip_paused_);
          tray_tooltip_sync_attention_ = StringValue(
              map, "tooltipSyncAttention", tray_tooltip_sync_attention_);
          tray_still_running_title_ =
              StringValue(map, "stillRunningTitle", tray_still_running_title_);
          tray_still_running_body_ =
              StringValue(map, "stillRunningBody", tray_still_running_body_);
          UpdateTrayIcon();
          result->Success();
          return;
        }
        if (call.method_name() == "showWindow") {
          RestoreAndFocus();
          result->Success();
          return;
        }
        if (call.method_name() == "exitApplication") {
          ExitApplication();
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (!exit_requested_) {
        SaveWindowPlacement();
        ShowWindow(hwnd, SW_HIDE);
        if (tray_added_ && !RegistryFlagEnabled(L"TrayExplanationShown")) {
          tray_icon_data_.uFlags = NIF_INFO;
          wcsncpy_s(tray_icon_data_.szInfoTitle,
                    tray_still_running_title_.c_str(), _TRUNCATE);
          wcsncpy_s(tray_icon_data_.szInfo, tray_still_running_body_.c_str(),
                    _TRUNCATE);
          tray_icon_data_.dwInfoFlags = NIIF_INFO;
          Shell_NotifyIcon(NIM_MODIFY, &tray_icon_data_);
          SetRegistryFlag(L"TrayExplanationShown");
        }
        return 0;
      }
      break;
    case WM_MOVE:
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED) {
        SaveWindowPlacement();
      }
      break;
    case kTrayCallbackMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreAndFocus();
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AddTrayIcon() {
  if (tray_added_ || GetHandle() == nullptr) {
    return;
  }
  ZeroMemory(&tray_icon_data_, sizeof(tray_icon_data_));
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = 1;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon = static_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_TRAY_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR | LR_SHARED));
  wcsncpy_s(tray_icon_data_.szTip, kTrayTooltip, _TRUNCATE);
  if (Shell_NotifyIcon(NIM_ADD, &tray_icon_data_)) {
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIcon(NIM_SETVERSION, &tray_icon_data_);
    tray_added_ = true;
  }
}

void FlutterWindow::UpdateTrayIcon() {
  if (!tray_added_) {
    return;
  }
  wcsncpy_s(tray_icon_data_.szTip, kTrayTooltip, _TRUNCATE);
  tray_icon_data_.uFlags = NIF_TIP | NIF_ICON | NIF_MESSAGE;
  Shell_NotifyIcon(NIM_MODIFY, &tray_icon_data_);
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
  tray_added_ = false;
}

void FlutterWindow::ShowTrayMenu() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  POINT cursor = {};
  GetCursorPos(&cursor);
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, L"TaskMaster Pro");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandOpen, tray_open_label_.c_str());
  if (!tray_signed_in_) {
    AppendMenuW(menu, MF_STRING, kTrayCommandSignIn,
                tray_sign_in_label_.c_str());
  } else if (tray_has_active_task_) {
    std::wstring active = tray_active_task_;
    if (active.length() > 54) {
      active = active.substr(0, 51) + L"...";
    }
    if (!tray_elapsed_.empty()) {
      active += L" — " + tray_elapsed_;
    }
    AppendMenuW(menu, MF_STRING, kTrayCommandActiveTask, active.c_str());
    if (!tray_break_active_ && !tray_focus_complete_) {
      AppendMenuW(menu, MF_STRING, kTrayCommandPauseResume,
                  tray_task_paused_ ? tray_resume_label_.c_str()
                                    : tray_pause_label_.c_str());
    }
    AppendMenuW(menu, MF_STRING, kTrayCommandFinishTask,
                tray_finish_label_.c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    if (tray_break_active_ ||
        (tray_pomodoro_available_ && !tray_task_paused_)) {
      AppendMenuW(menu, MF_STRING, kTrayCommandBreak,
                  tray_break_active_ ? tray_finish_break_label_.c_str()
                                     : tray_start_break_label_.c_str());
    }
    AppendMenuW(menu, MF_STRING, kTrayCommandInterruption,
                tray_add_interruption_label_.c_str());
    AppendMenuW(menu, MF_STRING, kTrayCommandNote,
                tray_add_note_label_.c_str());
  } else {
    AppendMenuW(menu, MF_STRING | MF_DISABLED, 0,
                tray_no_task_label_.c_str());
    AppendMenuW(menu, MF_STRING, kTrayCommandStartNext,
                tray_start_next_label_.c_str());
  }
  if (tray_signed_in_) {
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kTrayCommandSyncPanel,
                tray_sync_label_.c_str());
    AppendMenuW(menu, MF_STRING, kTrayCommandSyncNow,
                tray_sync_now_label_.c_str());
  }
  if (tray_account_deletion_) {
    AppendMenuW(menu, MF_STRING, kTrayCommandDeletion,
                tray_deletion_label_.c_str());
  }
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandWhatsNew,
              tray_whats_new_label_.c_str());
  AppendMenuW(menu, MF_STRING, kTrayCommandSettings,
              tray_settings_label_.c_str());
  AppendMenuW(menu, MF_STRING, kTrayCommandUpdate,
              tray_update_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandExit, tray_exit_label_.c_str());
  SetForegroundWindow(hwnd);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, hwnd, nullptr);
  DestroyMenu(menu);
  PostMessage(hwnd, WM_NULL, 0, 0);
  if (command == kTrayCommandOpen) {
    RestoreAndFocus();
    return;
  }
  if (command == kTrayCommandExit) {
    RestoreAndFocus();
    SendTrayCommand("exit");
    return;
  }
  const std::pair<UINT, const char*> commands[] = {
      {kTrayCommandActiveTask, "openActiveTask"},
      {kTrayCommandPauseResume, tray_task_paused_ ? "resumeTask" : "pauseTask"},
      {kTrayCommandFinishTask, "finishTask"},
      {kTrayCommandBreak,
       tray_break_active_
           ? "finishBreak"
           : (tray_focus_complete_ ? "startOfferedBreak" : "startBreak")},
      {kTrayCommandInterruption, "addInterruption"},
      {kTrayCommandNote, "addNote"},
      {kTrayCommandSyncPanel, "openSync"},
      {kTrayCommandSyncNow, "syncNow"},
      {kTrayCommandWhatsNew, "whatsNew"},
      {kTrayCommandSettings, "settings"},
      {kTrayCommandUpdate, "checkUpdate"},
      {kTrayCommandSignIn, "signIn"},
      {kTrayCommandStartNext, "startNextTask"},
      {kTrayCommandDeletion, "accountDeletion"},
  };
  for (const auto& entry : commands) {
    if (command == entry.first) {
      RestoreAndFocus();
      SendTrayCommand(entry.second);
      return;
    }
  }
}

void FlutterWindow::SendTrayCommand(const std::string& command) {
  if (!windows_shell_channel_) {
    return;
  }
  windows_shell_channel_->InvokeMethod(
      "trayCommand", std::make_unique<flutter::EncodableValue>(command));
}

void FlutterWindow::RestoreAndFocus() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }

  // SW_RESTORE also unmaximizes a hidden maximized window. Closing to the
  // tray therefore used to reopen the application at its normal bounds (for
  // example 720x520) instead of the user's maximized layout. Only use it for
  // an actually minimized window; otherwise reveal the existing state.
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else if (IsZoomed(hwnd)) {
    ShowWindow(hwnd, SW_SHOWMAXIMIZED);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }
  SetForegroundWindow(hwnd);
}

void FlutterWindow::SaveWindowPlacement() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr || IsIconic(hwnd)) {
    return;
  }
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(hwnd, &placement)) {
    return;
  }
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kWindowRegistryPath, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  const DWORD values[] = {
      static_cast<DWORD>(placement.rcNormalPosition.left),
      static_cast<DWORD>(placement.rcNormalPosition.top),
      static_cast<DWORD>(placement.rcNormalPosition.right -
                         placement.rcNormalPosition.left),
      static_cast<DWORD>(placement.rcNormalPosition.bottom -
                         placement.rcNormalPosition.top),
      IsZoomed(hwnd) ? 1u : 0u,
  };
  const wchar_t* names[] = {L"X", L"Y", L"Width", L"Height", L"Maximized"};
  for (size_t index = 0; index < std::size(values); ++index) {
    RegSetValueExW(key, names[index], 0, REG_DWORD,
                   reinterpret_cast<const BYTE*>(&values[index]),
                   sizeof(DWORD));
  }
  RegCloseKey(key);
}

void FlutterWindow::RestoreWindowPlacement() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kWindowRegistryPath, 0, KEY_QUERY_VALUE,
                    &key) != ERROR_SUCCESS) {
    return;
  }
  DWORD values[5] = {};
  const wchar_t* names[] = {L"X", L"Y", L"Width", L"Height", L"Maximized"};
  bool valid = true;
  for (size_t index = 0; index < std::size(values); ++index) {
    DWORD type = 0;
    DWORD size = sizeof(DWORD);
    if (RegQueryValueExW(key, names[index], nullptr, &type,
                         reinterpret_cast<BYTE*>(&values[index]),
                         &size) != ERROR_SUCCESS ||
        type != REG_DWORD) {
      valid = false;
      break;
    }
  }
  RegCloseKey(key);
  if (!valid) {
    return;
  }

  int x = static_cast<int>(values[0]);
  int y = static_cast<int>(values[1]);
  int width = std::max(720, static_cast<int>(values[2]));
  int height = std::max(520, static_cast<int>(values[3]));
  RECT desired = {x, y, x + width, y + height};
  const HMONITOR monitor =
      MonitorFromRect(&desired, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfoW(monitor, &info)) {
    const RECT work = info.rcWork;
    width = std::min(width, static_cast<int>(work.right - work.left));
    height = std::min(height, static_cast<int>(work.bottom - work.top));
    x = std::clamp(x, static_cast<int>(work.left),
                   static_cast<int>(work.right) - width);
    y = std::clamp(y, static_cast<int>(work.top),
                   static_cast<int>(work.bottom) - height);
  }
  SetWindowPos(GetHandle(), nullptr, x, y, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
  restore_maximized_ = values[4] != 0;
}

void FlutterWindow::ExitApplication() {
  SaveWindowPlacement();
  exit_requested_ = true;
  RemoveTrayIcon();
  DestroyWindow(GetHandle());
}
