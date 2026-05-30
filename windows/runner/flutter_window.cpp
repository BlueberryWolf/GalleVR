#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project), system_command_close_(false) {}

FlutterWindow::~FlutterWindow() {}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    bool start_minimized = false;
    const auto& args = project_.dart_entrypoint_arguments();
    for (const auto& arg : args) {
      if (arg == "--start-minimized") {
        start_minimized = true;
        break;
      }
    }

    if (!start_minimized) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  // We still need to force a redraw even if we're starting minimized
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
  std::optional<LRESULT> flutter_result;
  if (flutter_controller_) {
    flutter_result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
  }

  if (message == WM_SIZE || message == WM_SHOWWINDOW || 
      message == WM_ACTIVATE || message == WM_WINDOWPOSCHANGED) {
    HWND child = ::GetWindow(hwnd, GW_CHILD);
    if (child != nullptr) {
      bool parent_visible = ::IsWindowVisible(hwnd);
      if (message == WM_SHOWWINDOW) {
        parent_visible = wparam;
      }
      bool should_show = parent_visible && !::IsIconic(hwnd);
      
      bool child_visible = (::GetWindowLongPtr(child, GWL_STYLE) & WS_VISIBLE) != 0;
      
      if (should_show) {
        if (!child_visible) {
          ::ShowWindow(child, SW_SHOW);
          if (flutter_controller_) {
            flutter_controller_->ForceRedraw();
          }
          ::InvalidateRect(child, nullptr, TRUE);
          ::UpdateWindow(child);
          ::InvalidateRect(hwnd, nullptr, TRUE);
          ::UpdateWindow(hwnd);
        }
      } else {
        if (child_visible) {
          ::ShowWindow(child, SW_HIDE);
        }
      }
    }
  }

  if (message == WM_SIZE) {
    if (wparam == SIZE_MINIMIZED) {
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter::MethodChannel<> channel(
            flutter_controller_->engine()->messenger(),
            "gallevr/window",
            &flutter::StandardMethodCodec::GetInstance());
        channel.InvokeMethod("onWindowMinimized", nullptr);
      }
    } else if (wparam == SIZE_RESTORED || wparam == SIZE_MAXIMIZED) {
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter::MethodChannel<> channel(
            flutter_controller_->engine()->messenger(),
            "gallevr/window",
            &flutter::StandardMethodCodec::GetInstance());
        channel.InvokeMethod("onWindowRestored", nullptr);
      }
    }
  }

  if (flutter_result) {
    return *flutter_result;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SYSCOMMAND:
      if ((wparam & 0xFFF0) == SC_CLOSE) {
        system_command_close_ = true;
      }
      break;
    case WM_CLOSE:
      // Check if Alt key is pressed
      if (GetAsyncKeyState(VK_MENU) & 0x8000) {
        system_command_close_ = true;
      }

      if (system_command_close_) {
        system_command_close_ = false;

        // Send onWindowHidden to Flutter so Dart can unmount the UI and trim memory.
        if (flutter_controller_ && flutter_controller_->engine()) {
          flutter::MethodChannel<> channel(
              flutter_controller_->engine()->messenger(),
              "gallevr/window",
              &flutter::StandardMethodCodec::GetInstance());

          channel.InvokeMethod("onWindowHidden", nullptr);
        }

        ::ShowWindow(hwnd, SW_HIDE);
        return 0;
      }

      // If not system_command_close, quit the app.
      SetQuitOnClose(true);
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
