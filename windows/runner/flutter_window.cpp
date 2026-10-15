#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"

namespace {

constexpr wchar_t kSettingsKey[] = L"Software\\GalleVR";
constexpr wchar_t kPlacementValue[] = L"WindowPlacement";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project), minimize_to_tray_(true) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RestorePlacement();

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(), "gallevr/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "updateMinimizeToTray") {
          const auto* val = std::get_if<bool>(call.arguments());
          if (val) {
            this->minimize_to_tray_ = *val;
            printf("GalleVR C++: updateMinimizeToTray set to %d\n", *val);
          } else {
            this->minimize_to_tray_ = true;
            printf("GalleVR C++: updateMinimizeToTray failed to parse argument, defaulted to true\n");
          }
          fflush(stdout);
          result->Success();
        } else if (call.method_name() == "savePlacement") {
          this->SavePlacement();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

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
      this->ShowWithRestoredState();
    }
  });

  // The comments in this file are from flutter itself,
  // so I thought I would be a little more clear:
  // The first frame can finish before the show callback is registered, so
  // force one more frame. This runs even when starting minimized.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RestorePlacement() {
  WINDOWPLACEMENT placement{};
  DWORD size = sizeof(placement);
  if (::RegGetValue(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
                    RRF_RT_REG_BINARY, nullptr, &placement,
                    &size) != ERROR_SUCCESS ||
      size != sizeof(placement) || placement.length != sizeof(placement)) {
    return;
  }

  if (::MonitorFromRect(&placement.rcNormalPosition,
                        MONITOR_DEFAULTTONULL) == nullptr) {
    return;
  }

  restore_maximized_ = placement.showCmd == SW_SHOWMAXIMIZED;
  placement.showCmd = SW_HIDE;
  placement.flags = 0;
  ::SetWindowPlacement(GetHandle(), &placement);
}

void FlutterWindow::SavePlacement() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || ::IsIconic(hwnd)) {
    return;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(hwnd, &placement)) {
    return;
  }

  ::RegSetKeyValue(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
                   REG_BINARY, &placement, sizeof(placement));
}

void FlutterWindow::ShowWithRestoredState() {
  ::ShowWindow(GetHandle(),
               restore_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
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
  if (message == WM_ENTERSIZEMOVE) {
    in_size_move_ = true;
  }

  if (message == WM_EXITSIZEMOVE) {
    in_size_move_ = false;
    SavePlacement();
  }

  if (message == WM_WINDOWPOSCHANGED && !in_size_move_ &&
      ::IsWindowVisible(hwnd)) {
    const auto* pos = reinterpret_cast<const WINDOWPOS*>(lparam);
    if ((pos->flags & (SWP_NOMOVE | SWP_NOSIZE)) !=
        (SWP_NOMOVE | SWP_NOSIZE)) {
      SavePlacement();
    }
  }

  if (message == WM_CLOSE) {
    SavePlacement();
    if (minimize_to_tray_) {
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter::MethodChannel<> channel(
            flutter_controller_->engine()->messenger(),
            "gallevr/window",
            &flutter::StandardMethodCodec::GetInstance());
        channel.InvokeMethod("onWindowHidden", nullptr);
      }
      ::ShowWindow(hwnd, SW_HIDE);
      return 0;
    } else {
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter::MethodChannel<> channel(
            flutter_controller_->engine()->messenger(),
            "gallevr/window",
            &flutter::StandardMethodCodec::GetInstance());
        channel.InvokeMethod("onWindowCloseRequest", nullptr);
      }
      return 0;
    }
  }

  bool parent_visible = ::IsWindowVisible(hwnd);
  if (message == WM_SHOWWINDOW) {
    parent_visible = wparam;
  }
  bool should_show = parent_visible && !::IsIconic(hwnd);

  // Give Flutter, including plugins, an opportunity to handle window messages.
  std::optional<LRESULT> flutter_result;
  if (flutter_controller_) {
    bool skip_engine = !should_show && 
        (message == WM_SIZE || message == WM_SHOWWINDOW || 
         message == WM_ACTIVATE || message == WM_WINDOWPOSCHANGED || 
         message == WM_PAINT);

    if (!skip_engine) {
      flutter_result =
          flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                        lparam);
    }
  }

  if (message == WM_SIZE || message == WM_SHOWWINDOW || 
      message == WM_ACTIVATE || message == WM_WINDOWPOSCHANGED) {
    HWND child = ::GetWindow(hwnd, GW_CHILD);
    if (child != nullptr) {
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
      bool maximized = wparam == SIZE_MAXIMIZED;
      if (maximized != restore_maximized_ && ::IsWindowVisible(hwnd)) {
        restore_maximized_ = maximized;
        SavePlacement();
      }
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
