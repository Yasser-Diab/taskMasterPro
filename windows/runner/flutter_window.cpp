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
constexpr UINT kTrayCommandExit = 62002;
constexpr wchar_t kTrayTooltip[] = L"TaskMaster Pro";
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() { RemoveTrayIcon(); }

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

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
  AddTrayIcon();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
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
        ShowWindow(hwnd, SW_HIDE);
        return 0;
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
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(tray_icon_data_.szTip, kTrayTooltip, _TRUNCATE);
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

void FlutterWindow::ShowTrayMenu() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  POINT cursor = {};
  GetCursorPos(&cursor);
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kTrayCommandOpen, L"Open TaskMaster Pro");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandExit, L"Exit TaskMaster Pro");
  SetForegroundWindow(hwnd);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, hwnd, nullptr);
  DestroyMenu(menu);
  PostMessage(hwnd, WM_NULL, 0, 0);
  if (command == kTrayCommandOpen) {
    RestoreAndFocus();
  } else if (command == kTrayCommandExit) {
    ExitApplication();
  }
}

void FlutterWindow::RestoreAndFocus() {
  const HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  ShowWindow(hwnd, SW_RESTORE);
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ExitApplication() {
  exit_requested_ = true;
  RemoveTrayIcon();
  DestroyWindow(GetHandle());
}
