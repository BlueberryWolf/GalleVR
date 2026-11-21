#include <flutter/dart_project.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kInstallerMutexName[] =
    L"2fc54373-926e-545c-883a-dabcd36b229f";
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\GalleVR-app.single-instance";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"GalleVR";

bool TryLaunchDaemonForStartMinimized(
    const std::vector<std::string>& args) {
  bool start_minimized = false;
  for (const auto& arg : args) {
    if (arg == "--start-minimized") {
      start_minimized = true;
      break;
    }
  }
  if (!start_minimized) {
    return false;
  }

  wchar_t exe_path[MAX_PATH] = {};
  DWORD len = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return false;
  }

  std::wstring dir(exe_path, len);
  size_t sep = dir.find_last_of(L"\\/");
  if (sep == std::wstring::npos) {
    return false;
  }
  std::wstring daemon_path = dir.substr(0, sep + 1) + L"gallevr_daemon.exe";
  if (::GetFileAttributesW(daemon_path.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }

  std::wstring cmdline = L"\"" + daemon_path + L"\" --start-minimized";
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  BOOL ok = ::CreateProcessW(
      daemon_path.c_str(), cmdline.data(), nullptr, nullptr, FALSE,
      DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP, nullptr, nullptr, &si, &pi);
  if (ok) {
    ::CloseHandle(pi.hThread);
    ::CloseHandle(pi.hProcess);
    return true;
  }
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  if (TryLaunchDaemonForStartMinimized(command_line_arguments)) {
    return EXIT_SUCCESS;
  }

  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(kWindowClassName, kWindowTitle);
    if (existing != nullptr) {
      DWORD existing_pid = 0;
      ::GetWindowThreadProcessId(existing, &existing_pid);
      if (existing_pid != 0) {
        ::AllowSetForegroundWindow(existing_pid);
      }
      ::PostMessageW(existing, FlutterWindow::WakeUpMessage(), 0, 0);
    }
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  HANDLE installer_mutex =
      ::CreateMutexW(nullptr, FALSE, kInstallerMutexName);

  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  FlutterWindow window(L"data", std::move(command_line_arguments));

  RECT workArea{};
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &workArea, 0);
  int screenWidth = workArea.right - workArea.left;
  int screenHeight = workArea.bottom - workArea.top;

  Win32Window::Size size(1280, 720);

  int centerX = (screenWidth - static_cast<int>(size.width)) / 2;
  int centerY = (screenHeight - static_cast<int>(size.height)) / 2;
  centerX = centerX < 0 ? 0 : centerX;
  centerY = centerY < 0 ? 0 : centerY;

  Win32Window::Point origin(static_cast<unsigned int>(centerX),
                            static_cast<unsigned int>(centerY));

  if (!window.Create(kWindowTitle, origin, size)) {
    ::CoUninitialize();
    if (installer_mutex != nullptr) ::CloseHandle(installer_mutex);
    if (single_instance_mutex != nullptr) ::CloseHandle(single_instance_mutex);
    return EXIT_FAILURE;
  }

  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (installer_mutex != nullptr) {
    ::CloseHandle(installer_mutex);
  }
  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
