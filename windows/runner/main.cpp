#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

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

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // 窗口在屏幕工作区居中，默认 1200x820（逻辑像素，Create 里会按 DPI 放大）。
  // 屏幕放不下就缩小，四周各留 20
  RECT work{};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work, 0);
  const HMONITOR monitor = ::MonitorFromRect(&work, MONITOR_DEFAULTTOPRIMARY);
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const int avail_width = static_cast<int>((work.right - work.left) / scale);
  const int avail_height = static_cast<int>((work.bottom - work.top) / scale);
  const int width = std::min(1200, avail_width - 40);
  const int height = std::min(820, avail_height - 40);
  Win32Window::Point origin(
      static_cast<int>(work.left / scale) + (avail_width - width) / 2,
      static_cast<int>(work.top / scale) + (avail_height - height) / 2);
  Win32Window::Size size(width, height);
  if (!window.Create(L"实用英语", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
