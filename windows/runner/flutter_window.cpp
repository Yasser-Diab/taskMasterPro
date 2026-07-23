#include "flutter_window.h"

#include <algorithm>
#include <chrono>
#include <fstream>
#include <iterator>
#include <mmsystem.h>
#include <objbase.h>
#include <optional>
#include <shobjidl.h>
#include <sstream>
#include <variant>
#include <wrl.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayCommandTasks = 60001;
constexpr UINT kTrayCommandPomodoro = 60002;
constexpr UINT kTrayCommandWorkSession = 60003;
constexpr UINT kTrayCommandLearningSession = 60004;
constexpr UINT kTrayCommandNotifications = 60005;
constexpr UINT kTrayCommandSynchronization = 60006;
constexpr UINT kTrayCommandSettings = 60007;
constexpr UINT kTrayCommandExit = 60008;
constexpr ULONG_PTR kDeepLinkCopyDataId = 0x544d504c;  // TMPL

constexpr const wchar_t kAppName[] = L"TaskMaster Pro";
constexpr const wchar_t kBrowserWindowClassName[] =
    L"TaskMasterProDetachedBrowser";

std::wstring LabelOrDefault(const std::map<UINT, std::wstring>& labels,
                            UINT command,
                            const wchar_t* fallback) {
  auto label = labels.find(command);
  if (label == labels.end() || label->second.empty()) {
    return fallback;
  }
  return label->second;
}

std::string TrayCommandName(UINT command) {
  switch (command) {
    case kTrayCommandTasks:
      return "tasks";
    case kTrayCommandPomodoro:
      return "pomodoro";
    case kTrayCommandWorkSession:
      return "workSession";
    case kTrayCommandLearningSession:
      return "learningSession";
    case kTrayCommandNotifications:
      return "notifications";
    case kTrayCommandSynchronization:
      return "synchronization";
    case kTrayCommandSettings:
      return "settings";
    case kTrayCommandExit:
      return "exit";
    default:
      return "";
  }
}

void CopyToTrayTip(wchar_t* target,
                   size_t target_count,
                   const std::wstring& text) {
  if (target_count == 0) {
    return;
  }
  wcsncpy_s(target, target_count, text.c_str(), _TRUNCATE);
}

void EnsureDirectory(const std::wstring& path) {
  if (path.empty()) {
    return;
  }
  std::wstring current;
  for (wchar_t ch : path) {
    current.push_back(ch);
    if (ch == L'\\' || ch == L'/') {
      if (current.length() > 3) {
        CreateDirectoryW(current.c_str(), nullptr);
      }
    }
  }
  CreateDirectoryW(path.c_str(), nullptr);
}

std::wstring StringArgument(const flutter::EncodableMap& map,
                            const char* key,
                            const wchar_t* fallback = L"") {
  auto value = map.find(flutter::EncodableValue(key));
  if (value != map.end() &&
      std::holds_alternative<std::string>(value->second)) {
    return Utf16FromUtf8(std::get<std::string>(value->second));
  }
  return fallback;
}

double DoubleArgument(const flutter::EncodableMap& map,
                      const char* key,
                      double fallback = 0.0) {
  auto value = map.find(flutter::EncodableValue(key));
  if (value == map.end()) {
    return fallback;
  }
  if (std::holds_alternative<double>(value->second)) {
    return std::get<double>(value->second);
  }
  if (std::holds_alternative<int32_t>(value->second)) {
    return static_cast<double>(std::get<int32_t>(value->second));
  }
  if (std::holds_alternative<int64_t>(value->second)) {
    return static_cast<double>(std::get<int64_t>(value->second));
  }
  return fallback;
}

bool BoolArgument(const flutter::EncodableMap& map,
                  const char* key,
                  bool fallback = false) {
  auto value = map.find(flutter::EncodableValue(key));
  if (value != map.end() && std::holds_alternative<bool>(value->second)) {
    return std::get<bool>(value->second);
  }
  return fallback;
}

int64_t Int64Argument(const flutter::EncodableMap& map,
                      const char* key,
                      int64_t fallback = 0) {
  auto value = map.find(flutter::EncodableValue(key));
  if (value == map.end()) return fallback;
  if (std::holds_alternative<int64_t>(value->second)) {
    return std::get<int64_t>(value->second);
  }
  if (std::holds_alternative<int32_t>(value->second)) {
    return static_cast<int64_t>(std::get<int32_t>(value->second));
  }
  return fallback;
}

std::wstring ExecutableDirectory() {
  wchar_t raw_path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, raw_path, MAX_PATH);
  if (length == 0) return L".";
  std::wstring path(raw_path, length);
  const size_t separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return L".";
  return path.substr(0, separator);
}

std::wstring NotificationSoundAsset(const std::wstring& channel) {
  std::wstring file = L"notifications.mp3";
  if (channel == L"focus_alarm") {
    file = L"app-alarm.mp3";
  } else if (channel == L"break_alarm" || channel == L"session_transitions") {
    file = L"app-alarm.mp3";
  } else if (channel == L"overdue_coaching") {
    file = L"alert-sound.mp3";
  } else if (channel == L"daily_coaching") {
    file = L"UI-notification-tone.mp3";
  }
  return ExecutableDirectory() +
         L"\\data\\flutter_assets\\media\\notifications-sound\\" + file;
}

std::wstring UtcIsoNow() {
  SYSTEMTIME time = {};
  GetSystemTime(&time);
  wchar_t buffer[40] = {};
  swprintf_s(buffer, L"%04u-%02u-%02uT%02u:%02u:%02uZ", time.wYear,
             time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond);
  return buffer;
}

std::string CurrentIanaTimeZone() {
  DYNAMIC_TIME_ZONE_INFORMATION information = {};
  if (GetDynamicTimeZoneInformation(&information) == TIME_ZONE_ID_INVALID) {
    return "Etc/UTC";
  }
  const std::wstring key(information.TimeZoneKeyName);
  const std::map<std::wstring, std::string> windows_to_iana = {
      {L"Egypt Standard Time", "Africa/Cairo"},
      {L"W. Europe Standard Time", "Europe/Berlin"},
      {L"Central Europe Standard Time", "Europe/Budapest"},
      {L"GMT Standard Time", "Europe/London"},
      {L"Arabian Standard Time", "Asia/Dubai"},
      {L"Turkey Standard Time", "Europe/Istanbul"},
      {L"Israel Standard Time", "Asia/Jerusalem"},
      {L"Eastern Standard Time", "America/New_York"},
      {L"Central Standard Time", "America/Chicago"},
      {L"Mountain Standard Time", "America/Denver"},
      {L"Pacific Standard Time", "America/Los_Angeles"},
      {L"UTC", "Etc/UTC"},
  };
  const auto match = windows_to_iana.find(key);
  return match == windows_to_iana.end() ? "Etc/UTC" : match->second;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  const HRESULT com_result =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  com_initialized_ = SUCCEEDED(com_result);

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
  ConfigureLifecycleChannel();
  ConfigureDeepLinkChannel();
  ConfigureInteractionFeedbackChannel();
  ConfigureProfileFilesChannel();
  ConfigureTaskBrowserChannel();
  ConfigureTaskReminderChannel();
  AddTrayIcon();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RestoreMainWindowState();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    if (start_maximized_) {
      ShowWindow(GetHandle(), SW_MAXIMIZE);
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  for (const auto& entry : task_reminders_) {
    KillTimer(GetHandle(), entry.first);
  }
  task_reminders_.clear();
  RemoveTrayIcon();
  HideBrowser();
  browser_webview_.Reset();
  browser_controller_.Reset();
  browser_environment_.Reset();
  if (detached_browser_window_ != nullptr) {
    DestroyWindow(detached_browser_window_);
    detached_browser_window_ = nullptr;
  }
  if (browser_host_window_ != nullptr) {
    DestroyWindow(browser_host_window_);
    browser_host_window_ = nullptr;
  }
  mciSendStringW(L"close taskmasterpro_click", nullptr, 0, nullptr);
  click_sound_ready_ = false;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
  if (com_initialized_) {
    CoUninitialize();
    com_initialized_ = false;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      if (!exit_requested_) {
        SaveMainWindowState();
        Hide();
        return 0;
      }
      break;
    case WM_MOVE:
      SaveMainWindowState();
      break;
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED) {
        SaveMainWindowState();
      }
      break;

    case WM_TIMER:
      if (task_reminders_.find(static_cast<UINT_PTR>(wparam)) !=
          task_reminders_.end()) {
        HandleTaskReminderTimer(static_cast<UINT_PTR>(wparam));
        return 0;
      }
      break;

    case kTrayCallbackMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreAndFocus();
          SendTrayCommand("restore");
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          return 0;
      }
      break;

    case WM_COPYDATA: {
      auto copy_data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (copy_data != nullptr &&
          copy_data->dwData == kDeepLinkCopyDataId &&
          copy_data->lpData != nullptr &&
          copy_data->cbData >= sizeof(wchar_t)) {
        auto link = static_cast<const wchar_t*>(copy_data->lpData);
        RestoreAndFocus();
        SendDeepLink(link);
        return TRUE;
      }
      break;
    }
  }

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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ConfigureLifecycleChannel() {
  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/windows_lifecycle",
          &flutter::StandardMethodCodec::GetInstance());

  lifecycle_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "initialize") {
          AddTrayIcon();
          result->Success();
          return;
        }

        if (method == "setMenuLabels") {
          tray_labels_.clear();
          const auto* arguments = call.arguments();
          if (arguments != nullptr &&
              std::holds_alternative<flutter::EncodableMap>(*arguments)) {
            const auto& map = std::get<flutter::EncodableMap>(*arguments);
            const std::map<std::string, UINT> command_ids = {
                {"tasks", kTrayCommandTasks},
                {"pomodoro", kTrayCommandPomodoro},
                {"workSession", kTrayCommandWorkSession},
                {"learningSession", kTrayCommandLearningSession},
                {"notifications", kTrayCommandNotifications},
                {"synchronization", kTrayCommandSynchronization},
                {"settings", kTrayCommandSettings},
                {"exit", kTrayCommandExit},
            };
            for (const auto& entry : command_ids) {
              auto value = map.find(flutter::EncodableValue(entry.first));
              if (value != map.end() &&
                  std::holds_alternative<std::string>(value->second)) {
                tray_labels_[entry.second] =
                    Utf16FromUtf8(std::get<std::string>(value->second));
              }
            }
          }
          result->Success();
          return;
        }

        if (method == "setActiveSession") {
          has_active_session_ = false;
          active_session_summary_.clear();
          const auto* arguments = call.arguments();
          if (arguments != nullptr &&
              std::holds_alternative<flutter::EncodableMap>(*arguments)) {
            const auto& map = std::get<flutter::EncodableMap>(*arguments);
            auto active = map.find(flutter::EncodableValue("active"));
            if (active != map.end() &&
                std::holds_alternative<bool>(active->second)) {
              has_active_session_ = std::get<bool>(active->second);
            }
            auto summary = map.find(flutter::EncodableValue("summary"));
            if (summary != map.end() &&
                std::holds_alternative<std::string>(summary->second)) {
              active_session_summary_ =
                  Utf16FromUtf8(std::get<std::string>(summary->second));
            }
          }
          UpdateTrayTooltip();
          result->Success();
          return;
        }

        if (method == "exitApplication") {
          ExitApplication();
          result->Success();
          return;
        }

        if (method == "isWindowFocused") {
          const HWND foreground = GetForegroundWindow();
          result->Success(flutter::EncodableValue(
              foreground == GetHandle() ||
              foreground == detached_browser_window_));
          return;
        }

        if (method == "sampleForegroundActivity") {
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
              flutter::EncodableValue(foreground == GetHandle() ||
                                      foreground == detached_browser_window_);
          result->Success(flutter::EncodableValue(sample));
          return;
        }

        if (method == "resetWindowPosition") {
          ResetMainWindowPosition();
          result->Success();
          return;
        }

        if (method == "getTimeZoneId") {
          result->Success(flutter::EncodableValue(CurrentIanaTimeZone()));
          return;
        }

        if (method == "applyWindowPreferences") {
          const auto* arguments = call.arguments();
          if (arguments != nullptr &&
              std::holds_alternative<flutter::EncodableMap>(*arguments)) {
            const auto& map = std::get<flutter::EncodableMap>(*arguments);
            const bool restore_geometry =
                BoolArgument(map, "restoreGeometry", true);
            const bool restore_maximized =
                BoolArgument(map, "restoreMaximized", true);
            if (!restore_geometry) {
              ResetMainWindowPosition();
            } else if (!restore_maximized && IsZoomed(GetHandle())) {
              ShowWindow(GetHandle(), SW_RESTORE);
              SaveMainWindowState();
            }
          }
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::ConfigureDeepLinkChannel() {
  deep_link_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/deep_links",
          &flutter::StandardMethodCodec::GetInstance());

  deep_link_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "initialLink") {
          result->Success(flutter::EncodableValue());
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::ConfigureInteractionFeedbackChannel() {
  interaction_feedback_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/interaction_feedback",
          &flutter::StandardMethodCodec::GetInstance());

  interaction_feedback_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "initializeClickSound") {
          const auto* arguments = call.arguments();
          if (arguments != nullptr &&
              std::holds_alternative<flutter::EncodableMap>(*arguments)) {
            const auto& map = std::get<flutter::EncodableMap>(*arguments);
            auto bytes = map.find(flutter::EncodableValue("bytes"));
            if (bytes != map.end() &&
                std::holds_alternative<std::vector<uint8_t>>(bytes->second)) {
              InitializeClickSound(std::get<std::vector<uint8_t>>(
                  bytes->second));
            }
            auto volume = map.find(flutter::EncodableValue("volume"));
            if (volume != map.end()) {
              if (std::holds_alternative<double>(volume->second)) {
                SetClickVolume(std::get<double>(volume->second));
              } else if (std::holds_alternative<int32_t>(volume->second)) {
                SetClickVolume(
                    static_cast<double>(std::get<int32_t>(volume->second)));
              }
            }
          }
          result->Success();
          return;
        }
        if (method == "setVolume") {
          const auto* arguments = call.arguments();
          if (arguments != nullptr &&
              std::holds_alternative<flutter::EncodableMap>(*arguments)) {
            const auto& map = std::get<flutter::EncodableMap>(*arguments);
            auto volume = map.find(flutter::EncodableValue("volume"));
            if (volume != map.end()) {
              if (std::holds_alternative<double>(volume->second)) {
                SetClickVolume(std::get<double>(volume->second));
              } else if (std::holds_alternative<int32_t>(volume->second)) {
                SetClickVolume(
                    static_cast<double>(std::get<int32_t>(volume->second)));
              }
            }
          }
          result->Success();
          return;
        }
        if (method == "playClick") {
          PlayClickSound();
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::ConfigureProfileFilesChannel() {
  profile_files_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/profile_files",
          &flutter::StandardMethodCodec::GetInstance());

  profile_files_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "pickReadingFile") {
          auto path = PickReadingFilePath();
          if (!path.has_value()) {
            result->Success(flutter::EncodableValue());
            return;
          }
          result->Success(flutter::EncodableValue(path.value()));
          return;
        }
        if (call.method_name() == "openReadingFile") {
          const auto* arguments = call.arguments();
          if (arguments != nullptr &&
              std::holds_alternative<flutter::EncodableMap>(*arguments)) {
            const auto& map = std::get<flutter::EncodableMap>(*arguments);
            auto reference = map.find(flutter::EncodableValue("reference"));
            if (reference != map.end() &&
                std::holds_alternative<std::string>(reference->second)) {
              const std::wstring path = Utf16FromUtf8(
                  std::get<std::string>(reference->second));
              const HINSTANCE opened = ShellExecuteW(
                  GetHandle(), L"open", path.c_str(), nullptr, nullptr,
                  SW_SHOWNORMAL);
              if (reinterpret_cast<INT_PTR>(opened) > 32) {
                result->Success();
              } else {
                result->Error("reading_file_open_failed",
                              "The book file could not be opened.");
              }
              return;
            }
          }
          result->Error("invalid_reading_file",
                        "The book file is unavailable.");
          return;
        }
        if (call.method_name() != "pickAvatarImage") {
          result->NotImplemented();
          return;
        }

        auto bytes = PickAvatarImageBytes();
        if (!bytes.has_value()) {
          result->Success(flutter::EncodableValue());
          return;
        }
        result->Success(flutter::EncodableValue(bytes.value()));
      });
}

std::optional<std::string> FlutterWindow::PickReadingFilePath() {
  Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  if (FAILED(hr) || !dialog) return std::nullopt;
  COMDLG_FILTERSPEC filters[] = {
      {L"Books", L"*.pdf;*.epub"},
      {L"PDF", L"*.pdf"},
      {L"EPUB", L"*.epub"},
  };
  dialog->SetFileTypes(3, filters);
  dialog->SetTitle(L"Choose a book");
  if (FAILED(dialog->Show(GetHandle()))) return std::nullopt;
  Microsoft::WRL::ComPtr<IShellItem> item;
  if (FAILED(dialog->GetResult(&item)) || !item) return std::nullopt;
  PWSTR raw_path = nullptr;
  if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &raw_path)) ||
      raw_path == nullptr) return std::nullopt;
  std::wstring path(raw_path);
  CoTaskMemFree(raw_path);
  return Utf8FromUtf16(path.c_str());
}

std::optional<std::vector<uint8_t>> FlutterWindow::PickAvatarImageBytes() {
  Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
  if (FAILED(hr) || !dialog) {
    return std::nullopt;
  }

  COMDLG_FILTERSPEC filters[] = {
      {L"Image files", L"*.jpg;*.jpeg;*.png;*.webp"},
      {L"All files", L"*.*"},
  };
  dialog->SetFileTypes(2, filters);
  dialog->SetFileTypeIndex(1);
  dialog->SetTitle(L"Choose profile picture");

  hr = dialog->Show(GetHandle());
  if (FAILED(hr)) {
    return std::nullopt;
  }

  Microsoft::WRL::ComPtr<IShellItem> item;
  hr = dialog->GetResult(&item);
  if (FAILED(hr) || !item) {
    return std::nullopt;
  }

  PWSTR raw_path = nullptr;
  hr = item->GetDisplayName(SIGDN_FILESYSPATH, &raw_path);
  if (FAILED(hr) || raw_path == nullptr) {
    return std::nullopt;
  }

  std::wstring path(raw_path);
  CoTaskMemFree(raw_path);

  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!input) {
    return std::nullopt;
  }

  const std::streamsize size = input.tellg();
  if (size <= 0) {
    return std::nullopt;
  }

  input.seekg(0, std::ios::beg);
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  if (!input.read(reinterpret_cast<char*>(bytes.data()), size)) {
    return std::nullopt;
  }
  return bytes;
}

void FlutterWindow::ConfigureTaskReminderChannel() {
  task_reminder_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/task_reminders",
          &flutter::StandardMethodCodec::GetInstance());

  task_reminder_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getStatus") {
          flutter::EncodableMap status;
          status[flutter::EncodableValue("notificationsAllowed")] =
              flutter::EncodableValue(true);
          status[flutter::EncodableValue("exactSchedulingAvailable")] =
              flutter::EncodableValue(true);
          status[flutter::EncodableValue("activeTimerRunning")] =
              flutter::EncodableValue(has_active_session_);
          status[flutter::EncodableValue("channelId")] =
              flutter::EncodableValue("windows_tray_notification");
          status[flutter::EncodableValue("selectedSound")] =
              flutter::EncodableValue("packaged_taskmaster_sound");
          status[flutter::EncodableValue("soundAssetExists")] =
              flutter::EncodableValue(true);
          status[flutter::EncodableValue("channelSoundEnabled")] =
              flutter::EncodableValue(true);
          status[flutter::EncodableValue("vibrationEnabled")] =
              flutter::EncodableValue(false);
          status[flutter::EncodableValue("lastNotificationResult")] =
              flutter::EncodableValue(
                  Utf8FromUtf16(last_notification_result_.c_str()));
          status[flutter::EncodableValue("lastNotificationAt")] =
              flutter::EncodableValue(
                  Utf8FromUtf16(last_notification_at_.c_str()));
          result->Success(flutter::EncodableValue(status));
          return;
        }
        const auto* arguments = call.arguments();
        if (arguments == nullptr ||
            !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          result->Error("invalid_reminder", "Reminder details are missing.");
          return;
        }
        const auto& map = std::get<flutter::EncodableMap>(*arguments);
        if (call.method_name() == "schedule") {
          ScheduleTaskReminder(
              StringArgument(map, "id"), StringArgument(map, "taskId"),
              StringArgument(map, "title", kAppName),
              StringArgument(map, "body", L"Your task is ready."),
              Int64Argument(map, "triggerAt"));
          result->Success();
          return;
        }
        if (call.method_name() == "cancelTask") {
          CancelTaskReminders(StringArgument(map, "taskId"));
          result->Success();
          return;
        }
        if (call.method_name() == "showNow") {
          ShowTaskReminderNow(
              StringArgument(map, "id"), StringArgument(map, "taskId"),
              StringArgument(map, "title", kAppName),
              StringArgument(map, "body", L"Your task is ready."),
              StringArgument(map, "channel", L"task_reminders"));
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::ScheduleTaskReminder(const std::wstring& id,
                                         const std::wstring& task_id,
                                         const std::wstring& title,
                                         const std::wstring& body,
                                         int64_t trigger_at) {
  if (id.empty() || task_id.empty() || trigger_at <= 0) return;
  for (auto iterator = task_reminders_.begin();
       iterator != task_reminders_.end();) {
    if (iterator->second.id == id) {
      KillTimer(GetHandle(), iterator->first);
      iterator = task_reminders_.erase(iterator);
    } else {
      ++iterator;
    }
  }
  const int64_t now = std::chrono::duration_cast<std::chrono::milliseconds>(
                          std::chrono::system_clock::now().time_since_epoch())
                          .count();
  const int64_t remaining = std::max<int64_t>(1, trigger_at - now);
  const UINT delay = static_cast<UINT>(
      std::min<int64_t>(remaining, 24LL * 60LL * 60LL * 1000LL));
  const UINT_PTR timer_id = next_task_reminder_timer_id_++;
  task_reminders_[timer_id] =
      ScheduledTaskReminder{id, task_id, title, body, trigger_at};
  SetTimer(GetHandle(), timer_id, delay, nullptr);
}

void FlutterWindow::CancelTaskReminders(const std::wstring& task_id) {
  for (auto iterator = task_reminders_.begin();
       iterator != task_reminders_.end();) {
    if (iterator->second.task_id == task_id) {
      KillTimer(GetHandle(), iterator->first);
      iterator = task_reminders_.erase(iterator);
    } else {
      ++iterator;
    }
  }
}

void FlutterWindow::HandleTaskReminderTimer(UINT_PTR timer_id) {
  auto found = task_reminders_.find(timer_id);
  if (found == task_reminders_.end()) return;
  KillTimer(GetHandle(), timer_id);
  const ScheduledTaskReminder reminder = found->second;
  task_reminders_.erase(found);
  const int64_t now = std::chrono::duration_cast<std::chrono::milliseconds>(
                          std::chrono::system_clock::now().time_since_epoch())
                          .count();
  if (reminder.trigger_at > now + 1000) {
    ScheduleTaskReminder(reminder.id, reminder.task_id, reminder.title,
                         reminder.body, reminder.trigger_at);
    return;
  }
  ShowTaskReminderNow(reminder.id, reminder.task_id, reminder.title,
                      reminder.body, L"task_reminders");
}

void FlutterWindow::ShowTaskReminderNow(const std::wstring& id,
                                        const std::wstring& task_id,
                                        const std::wstring& title,
                                        const std::wstring& body,
                                        const std::wstring& channel) {
  AddTrayIcon();
  if (!tray_added_) return;
  tray_icon_data_.uFlags = NIF_INFO;
  CopyToTrayTip(tray_icon_data_.szInfoTitle,
                ARRAYSIZE(tray_icon_data_.szInfoTitle), title);
  CopyToTrayTip(tray_icon_data_.szInfo, ARRAYSIZE(tray_icon_data_.szInfo),
                body);
  tray_icon_data_.dwInfoFlags =
      channel == L"focus_alarm" || channel == L"break_alarm" ? NIIF_WARNING
                                                             : NIIF_INFO;
  Shell_NotifyIcon(NIM_MODIFY, &tray_icon_data_);
  last_notification_at_ = UtcIsoNow();
  last_notification_result_ = L"posted";
  PlayPackagedNotificationSound(channel);
  UpdateTrayTooltip();
}

void FlutterWindow::PlayPackagedNotificationSound(
    const std::wstring& channel) {
  const std::wstring sound_path = NotificationSoundAsset(channel);
  std::ifstream input(sound_path, std::ios::binary);
  if (!input) {
    last_notification_result_ = L"posted_sound_missing";
    return;
  }
  mciSendStringW(L"close taskmaster_notification_sound", nullptr, 0, nullptr);
  const std::wstring open_command =
      L"open \"" + sound_path +
      L"\" type mpegvideo alias taskmaster_notification_sound";
  if (mciSendStringW(open_command.c_str(), nullptr, 0, nullptr) != 0) {
    last_notification_result_ = L"posted_sound_open_failed";
    return;
  }
  mciSendStringW(L"play taskmaster_notification_sound from 0", nullptr, 0,
                 nullptr);
}

void FlutterWindow::ConfigureTaskBrowserChannel() {
  task_browser_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "taskmasterpro/task_browser",
          &flutter::StandardMethodCodec::GetInstance());

  task_browser_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* arguments = call.arguments();
        flutter::EncodableMap map;
        if (arguments != nullptr &&
            std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          map = std::get<flutter::EncodableMap>(*arguments);
        }

        const std::wstring browser_id = StringArgument(map, "browserId");
        if (!browser_id.empty()) {
          browser_id_ = browser_id;
        }
        const std::wstring profile_id =
            StringArgument(map, "profileId", L"signed-out");

        const std::string& method = call.method_name();
        if (method == "showDocked") {
          browser_password_autosave_enabled_ =
              BoolArgument(map, "passwordAutosave", false);
          browser_general_autofill_enabled_ =
              BoolArgument(map, "generalAutofill", true);
          ShowDockedBrowser(DoubleArgument(map, "x"),
                            DoubleArgument(map, "y"),
                            DoubleArgument(map, "width", 100.0),
                            DoubleArgument(map, "height", 100.0),
                            StringArgument(map, "url"), profile_id);
          result->Success();
          return;
        }
        if (method == "hide") {
          HideBrowser();
          result->Success();
          return;
        }
        if (method == "destroy") {
          DestroyBrowser();
          result->Success();
          return;
        }
        if (method == "navigate") {
          NavigateBrowser(StringArgument(map, "url"));
          result->Success();
          return;
        }
        if (method == "goBack") {
          BrowserGoBack();
          result->Success();
          return;
        }
        if (method == "goForward") {
          BrowserGoForward();
          result->Success();
          return;
        }
        if (method == "reload") {
          BrowserReload();
          result->Success();
          return;
        }
        if (method == "stop") {
          BrowserStop();
          result->Success();
          return;
        }
        if (method == "openExternal") {
          const std::wstring url = StringArgument(map, "url");
          if (!url.empty()) {
            ShellExecuteW(GetHandle(), L"open", url.c_str(), nullptr, nullptr,
                          SW_SHOWNORMAL);
          }
          result->Success();
          return;
        }
        if (method == "detach") {
          BrowserDetach(StringArgument(map, "title", kAppName));
          result->Success();
          return;
        }
        if (method == "dock") {
          BrowserDock();
          result->Success();
          return;
        }
        if (method == "diagnostics") {
          flutter::EncodableMap diagnostics;
          diagnostics[flutter::EncodableValue("profileId")] =
              flutter::EncodableValue(Utf8FromUtf16(browser_profile_id_.c_str()));
          diagnostics[flutter::EncodableValue("currentUrl")] =
              flutter::EncodableValue(Utf8FromUtf16(browser_current_url_.c_str()));
          diagnostics[flutter::EncodableValue("creationCount")] =
              flutter::EncodableValue(browser_creation_count_);
          diagnostics[flutter::EncodableValue("navigationCount")] =
              flutter::EncodableValue(browser_navigation_count_);
          diagnostics[flutter::EncodableValue("lastError")] =
              flutter::EncodableValue(Utf8FromUtf16(browser_last_error_.c_str()));
          result->Success(flutter::EncodableValue(diagnostics));
          return;
        }

        result->NotImplemented();
      });
}

LRESULT CALLBACK FlutterWindow::BrowserWindowProc(HWND hwnd,
                                                  UINT message,
                                                  WPARAM wparam,
                                                  LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
  }

  auto self =
      reinterpret_cast<FlutterWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    switch (message) {
      case WM_CLOSE:
        self->BrowserDock();
        return 0;
      case WM_SIZE:
        if (self->browser_host_window_ != nullptr &&
            GetParent(self->browser_host_window_) == hwnd) {
          RECT bounds;
          GetClientRect(hwnd, &bounds);
          MoveWindow(self->browser_host_window_, 0, 0,
                     bounds.right - bounds.left, bounds.bottom - bounds.top,
                     TRUE);
          if (self->browser_controller_) {
            self->browser_controller_->put_Bounds(bounds);
          }
        }
        return 0;
    }
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::CreateBrowserHostIfNeeded() {
  if (browser_host_window_ != nullptr) {
    return;
  }
  HWND parent = BrowserParentWindow();
  if (parent == nullptr) {
    return;
  }
  browser_host_window_ = CreateWindowExW(
      0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS |
                           WS_CLIPCHILDREN,
      0, 0, 100, 100, parent, nullptr, GetModuleHandle(nullptr), nullptr);
}

void FlutterWindow::EnsureBrowser(const std::wstring& url,
                                  const std::wstring& profile_id) {
  const std::wstring next_profile =
      profile_id.empty() ? L"signed-out" : profile_id;
  if (!browser_profile_id_.empty() && browser_profile_id_ != next_profile) {
    ResetBrowserForProfile();
  }
  browser_profile_id_ = next_profile;
  CreateBrowserHostIfNeeded();
  if (browser_webview_) {
    return;
  }
  if (browser_creating_ || browser_host_window_ == nullptr) {
    return;
  }

  browser_creating_ = true;
  std::wstring user_data_folder = BrowserUserDataFolder(browser_profile_id_);
  EnsureDirectory(user_data_folder);

  CreateCoreWebView2EnvironmentWithOptions(
      nullptr, user_data_folder.empty() ? nullptr : user_data_folder.c_str(),
      nullptr,
      Microsoft::WRL::Callback<
          ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this, url](HRESULT result,
                      ICoreWebView2Environment* environment) -> HRESULT {
            if (!browser_creating_ || browser_host_window_ == nullptr) {
              browser_creating_ = false;
              return S_OK;
            }
            if (FAILED(result) || environment == nullptr) {
              browser_creating_ = false;
              SendBrowserEvent(false, L"",
                               L"WebView2 runtime is unavailable.");
              return S_OK;
            }
            browser_environment_ = environment;
            browser_environment_->CreateCoreWebView2Controller(
                browser_host_window_,
                Microsoft::WRL::Callback<
                    ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [this, url](HRESULT controller_result,
                                ICoreWebView2Controller* controller)
                        -> HRESULT {
                      browser_creating_ = false;
                      if (browser_host_window_ == nullptr) {
                        if (controller != nullptr) {
                          controller->Close();
                        }
                        return S_OK;
                      }
                      if (FAILED(controller_result) || controller == nullptr) {
                        SendBrowserEvent(false, L"",
                                         L"WebView2 could not be created.");
                        return S_OK;
                      }

                      browser_controller_ = controller;
                      browser_creation_count_ += 1;
                      browser_controller_->get_CoreWebView2(&browser_webview_);
                      Microsoft::WRL::ComPtr<ICoreWebView2Settings> settings;
                      if (browser_webview_ &&
                          SUCCEEDED(browser_webview_->get_Settings(&settings))) {
                        settings->put_IsScriptEnabled(TRUE);
                        settings->put_AreDefaultScriptDialogsEnabled(TRUE);
                        settings->put_AreDevToolsEnabled(FALSE);
                        Microsoft::WRL::ComPtr<ICoreWebView2Settings4>
                            settings4;
                        if (SUCCEEDED(settings.As(&settings4)) && settings4) {
                          settings4->put_IsGeneralAutofillEnabled(
                              browser_general_autofill_enabled_ ? TRUE
                                                                : FALSE);
                          settings4->put_IsPasswordAutosaveEnabled(
                              browser_password_autosave_enabled_ ? TRUE
                                                                 : FALSE);
                        }
                      }

                      if (browser_webview_) {
                        browser_webview_->add_NavigationStarting(
                            Microsoft::WRL::Callback<
                                ICoreWebView2NavigationStartingEventHandler>(
                                [this](ICoreWebView2*,
                                       ICoreWebView2NavigationStartingEventArgs*
                                           args) -> HRESULT {
                                  LPWSTR uri = nullptr;
                                  if (args != nullptr &&
                                      SUCCEEDED(args->get_Uri(&uri)) &&
                                      uri != nullptr) {
                                    SendBrowserEvent(true, uri);
                                    CoTaskMemFree(uri);
                                  } else {
                                    SendBrowserEvent(true,
                                                     browser_current_url_);
                                  }
                                  return S_OK;
                                })
                                .Get(),
                            nullptr);
                        browser_webview_->add_NewWindowRequested(
                            Microsoft::WRL::Callback<
                                ICoreWebView2NewWindowRequestedEventHandler>(
                                [this](ICoreWebView2*,
                                       ICoreWebView2NewWindowRequestedEventArgs*
                                           args) -> HRESULT {
                                  LPWSTR uri = nullptr;
                                  if (args != nullptr &&
                                      SUCCEEDED(args->get_Uri(&uri)) &&
                                      uri != nullptr) {
                                    args->put_Handled(TRUE);
                                    SendBrowserEvent(false, browser_current_url_,
                                                     L"", uri);
                                    CoTaskMemFree(uri);
                                  }
                                  return S_OK;
                                })
                                .Get(),
                            nullptr);
                        browser_webview_->add_NavigationCompleted(
                            Microsoft::WRL::Callback<
                                ICoreWebView2NavigationCompletedEventHandler>(
                                [this](ICoreWebView2*,
                                       ICoreWebView2NavigationCompletedEventArgs*
                                           args) -> HRESULT {
                                  BOOL success = TRUE;
                                  if (args != nullptr) {
                                    args->get_IsSuccess(&success);
                                  }
                                  LPWSTR source = nullptr;
                                  if (SUCCEEDED(browser_webview_->get_Source(
                                          &source)) &&
                                      source != nullptr) {
                                    browser_current_url_ = source;
                                    browser_last_error_ =
                                        success ? L"" : L"Page failed to load.";
                                    SendBrowserEvent(
                                        false, source,
                                        success ? L""
                                                : L"Page failed to load.",
                                        L"", CurrentBrowserDocumentTitle());
                                    CoTaskMemFree(source);
                                  } else {
                                    browser_last_error_ =
                                        success ? L"" : L"Page failed to load.";
                                    SendBrowserEvent(
                                        false, browser_current_url_,
                                        success ? L""
                                                : L"Page failed to load.",
                                        L"", CurrentBrowserDocumentTitle());
                                  }
                                  return S_OK;
                                })
                                .Get(),
                            nullptr);
                        browser_webview_->add_DocumentTitleChanged(
                            Microsoft::WRL::Callback<
                                ICoreWebView2DocumentTitleChangedEventHandler>(
                                [this](ICoreWebView2*,
                                       IUnknown*) -> HRESULT {
                                  SendBrowserEvent(
                                      false, browser_current_url_, L"", L"",
                                      CurrentBrowserDocumentTitle());
                                  return S_OK;
                                })
                                .Get(),
                            nullptr);
                      }

                      RECT bounds;
                      GetClientRect(browser_host_window_, &bounds);
                      browser_controller_->put_Bounds(bounds);
                      if (!url.empty()) {
                        NavigateBrowser(url);
                      }
                      return S_OK;
                    })
                    .Get());
            return S_OK;
          })
          .Get());
}

void FlutterWindow::ShowDockedBrowser(double x,
                                      double y,
                                      double width,
                                      double height,
                                      const std::wstring& url,
                                      const std::wstring& profile_id) {
  EnsureBrowser(url, profile_id);
  if (browser_detached_) {
    return;
  }
  if (browser_host_window_ != nullptr) {
    HWND parent = BrowserParentWindow();
    if (parent != nullptr && GetParent(browser_host_window_) != parent) {
      SetParent(browser_host_window_, parent);
      SetWindowLongPtr(browser_host_window_, GWL_STYLE,
                       WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS |
                           WS_CLIPCHILDREN);
    }
    if (browser_controller_) {
      browser_controller_->put_IsVisible(TRUE);
    }
    ShowWindow(browser_host_window_, SW_SHOW);
    PositionBrowser(x, y, width, height);
  }
}

void FlutterWindow::PositionBrowser(double x,
                                    double y,
                                    double width,
                                    double height) {
  if (browser_host_window_ == nullptr || browser_detached_) {
    return;
  }
  HWND parent = BrowserParentWindow();
  if (parent == nullptr) {
    parent = GetHandle();
  }
  const double scale =
      parent != nullptr ? static_cast<double>(GetDpiForWindow(parent)) / 96.0
                        : 1.0;
  const int left = static_cast<int>(x * scale);
  const int top = static_cast<int>(y * scale);
  const int browser_width = std::max(1, static_cast<int>(width * scale));
  const int browser_height = std::max(1, static_cast<int>(height * scale));
  SetWindowPos(browser_host_window_, HWND_TOP, left, top, browser_width,
               browser_height, SWP_SHOWWINDOW | SWP_NOACTIVATE);
  BringWindowToTop(browser_host_window_);
  UpdateWindow(browser_host_window_);
  if (browser_controller_) {
    RECT bounds = {0, 0, browser_width, browser_height};
    browser_controller_->put_Bounds(bounds);
  }
}

void FlutterWindow::HideBrowser() {
  if (browser_controller_) {
    browser_controller_->put_IsVisible(FALSE);
  }
  if (browser_host_window_ != nullptr) {
    SetWindowPos(
        browser_host_window_, HWND_BOTTOM, -32000, -32000, 1, 1,
        SWP_HIDEWINDOW | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
  }
}

void FlutterWindow::DestroyBrowser() {
  browser_creating_ = false;
  browser_detached_ = false;
  if (browser_controller_) {
    browser_controller_->put_IsVisible(FALSE);
    browser_controller_->Close();
  }
  browser_webview_.Reset();
  browser_controller_.Reset();
  browser_environment_.Reset();
  if (browser_host_window_ != nullptr) {
    DestroyWindow(browser_host_window_);
    browser_host_window_ = nullptr;
  }
  if (detached_browser_window_ != nullptr) {
    DestroyWindow(detached_browser_window_);
    detached_browser_window_ = nullptr;
  }
  browser_current_url_.clear();
  browser_last_error_.clear();
}

void FlutterWindow::NavigateBrowser(const std::wstring& url) {
  if (url.empty()) {
    return;
  }
  browser_current_url_ = url;
  browser_navigation_count_ += 1;
  if (browser_webview_) {
    browser_webview_->Navigate(url.c_str());
  } else {
    EnsureBrowser(url, browser_profile_id_);
  }
}

void FlutterWindow::BrowserGoBack() {
  if (!browser_webview_) {
    return;
  }
  BOOL can_go_back = FALSE;
  browser_webview_->get_CanGoBack(&can_go_back);
  if (can_go_back) {
    browser_webview_->GoBack();
  }
}

void FlutterWindow::BrowserGoForward() {
  if (!browser_webview_) {
    return;
  }
  BOOL can_go_forward = FALSE;
  browser_webview_->get_CanGoForward(&can_go_forward);
  if (can_go_forward) {
    browser_webview_->GoForward();
  }
}

void FlutterWindow::BrowserReload() {
  if (browser_webview_) {
    browser_webview_->Reload();
  }
}

void FlutterWindow::BrowserStop() {
  if (browser_webview_) {
    browser_webview_->Stop();
  }
}

void FlutterWindow::CreateDetachedWindowIfNeeded(const std::wstring& title) {
  if (detached_browser_window_ != nullptr) {
    SetWindowTextW(detached_browser_window_, title.c_str());
    return;
  }

  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = FlutterWindow::BrowserWindowProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kBrowserWindowClassName;
  window_class.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);

  detached_browser_window_ = CreateWindowExW(
      0, kBrowserWindowClassName, title.c_str(), WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT, CW_USEDEFAULT, 1200, 800, nullptr, nullptr,
      GetModuleHandle(nullptr), this);
}

void FlutterWindow::BrowserDetach(const std::wstring& title) {
  EnsureBrowser(browser_current_url_, browser_profile_id_);
  if (browser_host_window_ == nullptr) {
    return;
  }
  CreateDetachedWindowIfNeeded(title.empty() ? kAppName : title);
  if (detached_browser_window_ == nullptr) {
    return;
  }

  SetParent(browser_host_window_, detached_browser_window_);
  SetWindowLongPtr(browser_host_window_, GWL_STYLE,
                   WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN);
  RECT bounds;
  GetClientRect(detached_browser_window_, &bounds);
  MoveWindow(browser_host_window_, 0, 0, bounds.right - bounds.left,
             bounds.bottom - bounds.top, TRUE);
  if (browser_controller_) {
    browser_controller_->put_Bounds(bounds);
  }
  ShowWindow(detached_browser_window_, SW_SHOWNORMAL);
  SetForegroundWindow(detached_browser_window_);
  browser_detached_ = true;
  SendBrowserEvent(false, browser_current_url_);
}

void FlutterWindow::BrowserDock() {
  if (browser_host_window_ == nullptr) {
    return;
  }
  HWND parent = BrowserParentWindow();
  SetParent(browser_host_window_, parent == nullptr ? GetHandle() : parent);
  SetWindowLongPtr(browser_host_window_, GWL_STYLE,
                   WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN);
  if (detached_browser_window_ != nullptr) {
    ShowWindow(detached_browser_window_, SW_HIDE);
  }
  browser_detached_ = false;
  SendBrowserEvent(false, browser_current_url_);
}

std::wstring FlutterWindow::CurrentBrowserDocumentTitle() {
  if (!browser_webview_) {
    return L"";
  }
  LPWSTR title = nullptr;
  std::wstring result;
  if (SUCCEEDED(browser_webview_->get_DocumentTitle(&title)) &&
      title != nullptr) {
    result = title;
    CoTaskMemFree(title);
  }
  return result;
}

void FlutterWindow::SendBrowserEvent(bool loading,
                                     const std::wstring& url,
                                     const std::wstring& error,
                                     const std::wstring& new_tab_url,
                                     const std::wstring& title) {
  if (!task_browser_channel_) {
    return;
  }
  flutter::EncodableMap event;
  event[flutter::EncodableValue("browserId")] =
      flutter::EncodableValue(Utf8FromUtf16(browser_id_.c_str()));
  event[flutter::EncodableValue("loading")] = flutter::EncodableValue(loading);
  event[flutter::EncodableValue("detached")] =
      flutter::EncodableValue(browser_detached_);
  event[flutter::EncodableValue("url")] =
      flutter::EncodableValue(Utf8FromUtf16(url.c_str()));
  event[flutter::EncodableValue("error")] =
      flutter::EncodableValue(Utf8FromUtf16(error.c_str()));
  event[flutter::EncodableValue("newTabUrl")] =
      flutter::EncodableValue(Utf8FromUtf16(new_tab_url.c_str()));
  event[flutter::EncodableValue("title")] =
      flutter::EncodableValue(Utf8FromUtf16(title.c_str()));
  event[flutter::EncodableValue("creationCount")] =
      flutter::EncodableValue(browser_creation_count_);
  event[flutter::EncodableValue("navigationCount")] =
      flutter::EncodableValue(browser_navigation_count_);
  task_browser_channel_->InvokeMethod(
      "browserEvent", std::make_unique<flutter::EncodableValue>(event));
}

void FlutterWindow::ResetBrowserForProfile() {
  DestroyBrowser();
}

HWND FlutterWindow::BrowserParentWindow() {
  if (flutter_controller_ && flutter_controller_->view()) {
    HWND view_window = flutter_controller_->view()->GetNativeWindow();
    if (view_window != nullptr) {
      return view_window;
    }
  }
  return GetHandle();
}

std::wstring FlutterWindow::BrowserUserDataFolder(
    const std::wstring& profile_id) {
  wchar_t local_app_data[MAX_PATH];
  DWORD length =
      GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, MAX_PATH);
  std::wstring base =
      length > 0 && length < MAX_PATH ? std::wstring(local_app_data)
                                      : std::wstring(L".");
  return base + L"\\TaskMasterPro\\BrowserData\\" +
         (profile_id.empty() ? L"signed-out" : profile_id) +
         L"\\WebView2Profile";
}

std::wstring FlutterWindow::WindowStateFile() {
  wchar_t app_data[MAX_PATH];
  DWORD length = GetEnvironmentVariableW(L"APPDATA", app_data, MAX_PATH);
  std::wstring base =
      length > 0 && length < MAX_PATH ? std::wstring(app_data)
                                      : std::wstring(L".");
  std::wstring folder = base + L"\\TaskMasterPro";
  EnsureDirectory(folder);
  return folder + L"\\window_state.txt";
}

RECT FlutterWindow::ClampMainWindowRect(RECT rect) {
  constexpr LONG minimum_width = 1050;
  constexpr LONG minimum_height = 700;
  LONG width = std::max(minimum_width, rect.right - rect.left);
  LONG height = std::max(minimum_height, rect.bottom - rect.top);

  HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfoW(monitor, &info)) {
    return RECT{40, 40, 40 + width, 40 + height};
  }

  RECT work = info.rcWork;
  width = std::min(width, work.right - work.left);
  height = std::min(height, work.bottom - work.top);
  LONG left = std::clamp(rect.left, work.left, work.right - width);
  LONG top = std::clamp(rect.top, work.top, work.bottom - height);
  return RECT{left, top, left + width, top + height};
}

void FlutterWindow::RestoreMainWindowState() {
  std::wifstream file(WindowStateFile());
  if (!file.is_open()) {
    return;
  }
  LONG left = 0;
  LONG top = 0;
  LONG right = 0;
  LONG bottom = 0;
  int maximized = 0;
  if (!(file >> left >> top >> right >> bottom >> maximized) ||
      right <= left || bottom <= top) {
    return;
  }
  RECT rect = ClampMainWindowRect(RECT{left, top, right, bottom});
  SetWindowPos(GetHandle(), nullptr, rect.left, rect.top,
               rect.right - rect.left, rect.bottom - rect.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
  start_maximized_ = maximized != 0;
}

void FlutterWindow::SaveMainWindowState() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || IsIconic(hwnd)) {
    return;
  }

  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(hwnd, &placement)) {
    return;
  }

  RECT rect = placement.rcNormalPosition;
  std::wofstream file(WindowStateFile(), std::ios::trunc);
  if (!file.is_open()) {
    return;
  }
  file << rect.left << L' ' << rect.top << L' ' << rect.right << L' '
       << rect.bottom << L' ' << (IsZoomed(hwnd) ? 1 : 0);
}

void FlutterWindow::ResetMainWindowPosition() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  RECT primary = {};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &primary, 0);
  LONG width = std::min<LONG>(1280, primary.right - primary.left);
  LONG height = std::min<LONG>(820, primary.bottom - primary.top);
  LONG left = primary.left + ((primary.right - primary.left - width) / 2);
  LONG top = primary.top + ((primary.bottom - primary.top - height) / 2);
  ShowWindow(hwnd, SW_RESTORE);
  SetWindowPos(hwnd, nullptr, left, top, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
  SaveMainWindowState();
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
  tray_icon_data_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                                   MAKEINTRESOURCE(IDI_APP_ICON));
  CopyToTrayTip(tray_icon_data_.szTip, ARRAYSIZE(tray_icon_data_.szTip),
                kAppName);

  if (Shell_NotifyIcon(NIM_ADD, &tray_icon_data_)) {
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIcon(NIM_SETVERSION, &tray_icon_data_);
    tray_added_ = true;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
  tray_added_ = false;
}

void FlutterWindow::UpdateTrayTooltip() {
  if (!tray_added_) {
    return;
  }

  std::wstring tooltip = kAppName;
  if (has_active_session_ && !active_session_summary_.empty()) {
    tooltip += L" - ";
    tooltip += active_session_summary_;
  }

  tray_icon_data_.uFlags = NIF_TIP;
  CopyToTrayTip(tray_icon_data_.szTip, ARRAYSIZE(tray_icon_data_.szTip),
                tooltip);
  Shell_NotifyIcon(NIM_MODIFY, &tray_icon_data_);
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  POINT cursor_position;
  GetCursorPos(&cursor_position);

  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kTrayCommandTasks,
              LabelOrDefault(tray_labels_, kTrayCommandTasks, L"Tasks").c_str());
  AppendMenuW(menu, MF_STRING, kTrayCommandPomodoro,
              LabelOrDefault(tray_labels_, kTrayCommandPomodoro, L"Pomodoro")
                  .c_str());
  AppendMenuW(menu, MF_STRING, kTrayCommandWorkSession,
              LabelOrDefault(tray_labels_, kTrayCommandWorkSession,
                             L"Work session")
                  .c_str());
  AppendMenuW(menu, MF_STRING, kTrayCommandLearningSession,
              LabelOrDefault(tray_labels_, kTrayCommandLearningSession,
                             L"Learning session")
                  .c_str());
  AppendMenuW(menu, MF_STRING, kTrayCommandNotifications,
              LabelOrDefault(tray_labels_, kTrayCommandNotifications,
                             L"Notifications")
                  .c_str());
  AppendMenuW(menu, MF_STRING, kTrayCommandSynchronization,
              LabelOrDefault(tray_labels_, kTrayCommandSynchronization,
                             L"Synchronization")
                  .c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandSettings,
              LabelOrDefault(tray_labels_, kTrayCommandSettings, L"Settings")
                  .c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandExit,
              LabelOrDefault(tray_labels_, kTrayCommandExit,
                             L"Exit TaskMaster Pro")
                  .c_str());

  SetForegroundWindow(hwnd);
  UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
      cursor_position.x, cursor_position.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
  PostMessage(hwnd, WM_NULL, 0, 0);

  if (command != 0) {
    HandleTrayCommand(command);
  }
}

void FlutterWindow::HandleTrayCommand(UINT command) {
  const std::string command_name = TrayCommandName(command);
  if (command_name.empty()) {
    return;
  }

  if (command == kTrayCommandExit && !has_active_session_) {
    ExitApplication();
    return;
  }

  if (command != kTrayCommandExit) {
    RestoreAndFocus();
  }
  SendTrayCommand(command_name);
}

void FlutterWindow::SendTrayCommand(const std::string& command) {
  if (!lifecycle_channel_) {
    return;
  }
  lifecycle_channel_->InvokeMethod(
      "trayCommand", std::make_unique<flutter::EncodableValue>(command));
}

void FlutterWindow::SendDeepLink(const std::wstring& link) {
  if (!deep_link_channel_ || link.empty()) {
    return;
  }
  deep_link_channel_->InvokeMethod(
      "link",
      std::make_unique<flutter::EncodableValue>(Utf8FromUtf16(link.c_str())));
}

void FlutterWindow::InitializeClickSound(const std::vector<uint8_t>& bytes) {
  if (bytes.empty()) {
    return;
  }

  wchar_t temp_path[MAX_PATH];
  DWORD length = GetTempPathW(ARRAYSIZE(temp_path), temp_path);
  if (length == 0 || length > ARRAYSIZE(temp_path)) {
    return;
  }

  click_sound_path_ =
      std::wstring(temp_path) + L"taskmasterpro_ui_click_sound.mp3";
  std::ofstream file(click_sound_path_, std::ios::binary | std::ios::trunc);
  if (!file.is_open()) {
    return;
  }
  file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  file.close();

  mciSendStringW(L"close taskmasterpro_click", nullptr, 0, nullptr);
  std::wstring open_command =
      L"open \"" + click_sound_path_ +
      L"\" type mpegvideo alias taskmasterpro_click";
  if (mciSendStringW(open_command.c_str(), nullptr, 0, nullptr) == 0) {
    click_sound_ready_ = true;
    SetClickVolume(click_volume_);
  }
}

void FlutterWindow::SetClickVolume(double volume) {
  click_volume_ = std::clamp(volume, 0.0, 1.0);
  if (!click_sound_ready_) {
    return;
  }
  const int mci_volume = static_cast<int>(click_volume_ * 1000.0);
  std::wstring command = L"setaudio taskmasterpro_click volume to " +
                         std::to_wstring(mci_volume);
  mciSendStringW(command.c_str(), nullptr, 0, nullptr);
}

void FlutterWindow::PlayClickSound() {
  if (!click_sound_ready_) {
    return;
  }
  mciSendStringW(L"stop taskmasterpro_click", nullptr, 0, nullptr);
  mciSendStringW(L"seek taskmasterpro_click to start", nullptr, 0, nullptr);
  mciSendStringW(L"play taskmasterpro_click", nullptr, 0, nullptr);
}

void FlutterWindow::ExitApplication() {
  if (exit_in_progress_) {
    return;
  }
  exit_in_progress_ = true;
  exit_requested_ = true;
  has_active_session_ = false;
  active_session_summary_.clear();
  SaveMainWindowState();

  HideBrowser();
  browser_webview_.Reset();
  browser_controller_.Reset();
  browser_environment_.Reset();
  if (detached_browser_window_ != nullptr) {
    DestroyWindow(detached_browser_window_);
    detached_browser_window_ = nullptr;
  }
  if (browser_host_window_ != nullptr) {
    DestroyWindow(browser_host_window_);
    browser_host_window_ = nullptr;
  }

  RemoveTrayIcon();
  SetQuitOnClose(true);
  Destroy();
  PostQuitMessage(0);
}
