#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"TaskMasterPro.SingleInstance";
constexpr ULONG_PTR kDeepLinkCopyDataId = 0x544d504c;  // TMPL

HWND FindExistingTaskMasterWindow() {
  HWND window = nullptr;
  for (int attempt = 0; attempt < 20 && window == nullptr; attempt += 1) {
    window = FindWindow(Win32Window::WindowClassName(), L"TaskMaster Pro");
    if (window == nullptr) {
      Sleep(100);
    }
  }
  return window;
}

void RestoreExistingWindow(HWND window) {
  if (window == nullptr) {
    return;
  }
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else {
    ShowWindow(window, SW_SHOWNORMAL);
  }
  SetForegroundWindow(window);
}

void ForwardArgumentsToExistingWindow(
    HWND window,
    const std::vector<std::string>& command_line_arguments) {
  if (window == nullptr) {
    return;
  }

  for (const auto& argument : command_line_arguments) {
    std::wstring payload = Utf16FromUtf8(argument);
    if (payload.empty()) {
      continue;
    }
    COPYDATASTRUCT copy_data = {};
    copy_data.dwData = kDeepLinkCopyDataId;
    copy_data.cbData =
        static_cast<DWORD>((payload.size() + 1) * sizeof(wchar_t));
    copy_data.lpData = payload.data();
    SendMessage(window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy_data));
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  HANDLE single_instance_mutex =
      CreateMutex(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing_window = FindExistingTaskMasterWindow();
    RestoreExistingWindow(existing_window);
    ForwardArgumentsToExistingWindow(existing_window, command_line_arguments);
    CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"TaskMaster Pro", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
