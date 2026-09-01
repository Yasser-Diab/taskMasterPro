#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\YADiab.DayVector.SingleInstance.v1";
constexpr wchar_t kActivateExistingInstanceMessageName[] =
    L"YADiab.DayVector.ActivateExistingInstance.v1";

void ActivateRunningInstance() {
  const UINT activation_message =
      ::RegisterWindowMessageW(kActivateExistingInstanceMessageName);
  // Broadcast reaches a hidden-to-tray window as well as a visible one. A
  // short retry window also covers two nearly simultaneous launches where the
  // first process owns the mutex but has not created its HWND yet.
  for (int attempt = 0; attempt < 20; ++attempt) {
    ::PostMessageW(HWND_BROADCAST, activation_message, 0, 0);
    if (::FindWindowW(nullptr, L"DayVector") != nullptr) {
      return;
    }
    ::Sleep(50);
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

  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (single_instance_mutex == nullptr) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"DayVector", origin, size)) {
    ::CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  // Closing the main window keeps timers and synchronization alive. The tray
  // menu exposes an explicit Exit command that terminates the process.
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    if (window.HandleAccelerator(msg)) {
      continue;
    }
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CloseHandle(single_instance_mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
