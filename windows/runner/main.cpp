#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// v1.6.0 电脑端安全加固 —— 「安全单实例」。
// 用命名互斥体判定是否已有实例在跑：第二个实例**不杀进程**，而是把已有主窗口
// 还原（可能已最小化到托盘）并前置，然后自己退出。
constexpr const wchar_t kSingleInstanceMutex[] =
    L"Local\\com.dzy.cloud.dzy-app.single-instance";

// 主窗口类名（与 win32_window.cpp 的 kWindowClassName 保持一致）
constexpr const wchar_t kMainWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// 把已有实例的窗口还原并前置到最前。
void BringExistingInstanceToFront() {
  HWND existing = ::FindWindowW(kMainWindowClassName, nullptr);
  if (existing == nullptr) {
    return;
  }
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  } else {
    ::ShowWindow(existing, SW_SHOW);
  }
  ::SetForegroundWindow(existing);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
#ifdef _DEBUG
  else {
    // Force console in debug mode even without attached debugger (e.g. double click exe)
    CreateAndAttachConsole();
  }
#endif

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // v1.6.0：安全单实例 —— 已有实例在跑则把其窗口前置并退出本实例，绝不杀进程。
  HANDLE instance_mutex = ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    BringExistingInstanceToFront();
    ::CloseHandle(instance_mutex);
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
  if (!window.Create(L"队长云加速", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
