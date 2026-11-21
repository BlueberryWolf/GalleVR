#include "flutter_window.h"

#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr wchar_t kSettingsKey[] = L"Software\\GalleVR";
constexpr wchar_t kPlacementValue[] = L"WindowPlacement";

constexpr UINT_PTR kMemoryTrimTimerId = 1001;
constexpr UINT_PTR kShowFallbackTimerId = 1002;

struct FlutterDesktopViewControllerProperties {
  int width;
  int height;
};

extern "C" FLUTTER_EXPORT FlutterDesktopViewControllerRef
FlutterDesktopEngineCreateViewController(
    FlutterDesktopEngineRef engine,
    const FlutterDesktopViewControllerProperties* properties);

using MessengerScopedLock =
    std::unique_ptr<FlutterDesktopMessenger,
                    decltype(&FlutterDesktopMessengerUnlock)>;

void ForwardEngineMessage(FlutterDesktopMessengerRef messenger,
                          const FlutterDesktopMessage* message,
                          void* user_data) {
  auto* response_handle = message->response_handle;
  auto messenger_ptr = std::shared_ptr<FlutterDesktopMessenger>(
      FlutterDesktopMessengerAddRef(messenger),
      &FlutterDesktopMessengerRelease);
  flutter::BinaryReply reply_handler = [messenger_ptr, response_handle](
                                           const uint8_t* reply,
                                           size_t reply_size) mutable {
    auto lock = MessengerScopedLock(
        FlutterDesktopMessengerLock(messenger_ptr.get()),
        &FlutterDesktopMessengerUnlock);
    if (!FlutterDesktopMessengerIsAvailable(messenger_ptr.get()) ||
        response_handle == nullptr) {
      return;
    }
    FlutterDesktopMessengerSendResponse(messenger_ptr.get(), response_handle,
                                        reply, reply_size);
    response_handle = nullptr;
  };

  const auto& handler =
      *static_cast<flutter::BinaryMessageHandler*>(user_data);
  handler(message->message, message->message_size, std::move(reply_handler));
}

}  // namespace

class FlutterWindow::EngineBinaryMessenger : public flutter::BinaryMessenger {
 public:
  explicit EngineBinaryMessenger(FlutterDesktopMessengerRef messenger)
      : messenger_(messenger) {}
  ~EngineBinaryMessenger() override = default;

  void Send(const std::string& channel,
            const uint8_t* message,
            size_t message_size,
            flutter::BinaryReply reply) const override {
    if (messenger_ == nullptr) {
      return;
    }
    if (reply == nullptr) {
      FlutterDesktopMessengerSend(messenger_, channel.c_str(), message,
                                  message_size);
      return;
    }
    struct Captures {
      flutter::BinaryReply reply;
    };
    auto* captures = new Captures{std::move(reply)};
    auto callback = [](const uint8_t* data, size_t data_size, void* user_data) {
      auto* cap = static_cast<Captures*>(user_data);
      cap->reply(data, data_size);
      delete cap;
    };
    if (!FlutterDesktopMessengerSendWithReply(
            messenger_, channel.c_str(), message, message_size, callback,
            captures)) {
      delete captures;
    }
  }

  void SetMessageHandler(const std::string& channel,
                         flutter::BinaryMessageHandler handler) override {
    if (messenger_ == nullptr) {
      return;
    }
    if (!handler) {
      handlers_.erase(channel);
      FlutterDesktopMessengerSetCallback(messenger_, channel.c_str(), nullptr,
                                         nullptr);
      return;
    }
    handlers_[channel] = std::move(handler);
    FlutterDesktopMessengerSetCallback(messenger_, channel.c_str(),
                                       ForwardEngineMessage,
                                       &handlers_[channel]);
  }

 private:
  FlutterDesktopMessengerRef messenger_ = nullptr;
  std::map<std::string, flutter::BinaryMessageHandler> handlers_;
};

UINT FlutterWindow::WakeUpMessage() {
  static const UINT kWakeUpMsg =
      ::RegisterWindowMessageW(L"GalleVR_WakeUpWindow");
  return kWakeUpMsg;
}

FlutterWindow::FlutterWindow(const std::wstring& data_directory,
                             std::vector<std::string> dart_entrypoint_arguments)
    : data_directory_(data_directory),
      dart_entrypoint_arguments_(std::move(dart_entrypoint_arguments)),
      minimize_to_tray_(true) {}

FlutterWindow::~FlutterWindow() {}

FlutterDesktopPluginRegistrarRef FlutterWindow::GetRegistrarForPlugin(
    const std::string& plugin_name) {
  if (engine_ == nullptr) {
    return nullptr;
  }
  return FlutterDesktopEngineGetPluginRegistrar(engine_, plugin_name.c_str());
}

bool FlutterWindow::CreateAndRunEngine() {
  std::wstring assets_path = data_directory_ + L"\\flutter_assets";
  std::wstring icu_data_path = data_directory_ + L"\\icudtl.dat";
  std::wstring aot_library_path = data_directory_ + L"\\app.so";

  std::vector<const char*> argv;
  argv.reserve(dart_entrypoint_arguments_.size());
  for (const auto& arg : dart_entrypoint_arguments_) {
    argv.push_back(arg.c_str());
  }

  FlutterDesktopEngineProperties props{};
  props.assets_path = assets_path.c_str();
  props.icu_data_path = icu_data_path.c_str();
  props.aot_library_path = aot_library_path.c_str();
  props.dart_entrypoint = nullptr;
  props.dart_entrypoint_argc = static_cast<int>(argv.size());
  props.dart_entrypoint_argv = argv.empty() ? nullptr : argv.data();
  props.gpu_preference = LowPowerPreference;
  props.ui_thread_policy = RunOnPlatformThread;
  props.accessibility_mode = DefaultAccessibilityMode;
  props.impeller_switch = EnabledImpeller;
  props.enable_flutter_gpu = false;

  engine_ = FlutterDesktopEngineCreate(&props);
  if (engine_ == nullptr) {
    return false;
  }

  messenger_ = std::make_unique<EngineBinaryMessenger>(
      FlutterDesktopEngineGetMessenger(engine_));

  RegisterPlugins(this);

  window_channel_ = std::make_unique<flutter::MethodChannel<>>(
      messenger_.get(), "gallevr/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "updateMinimizeToTray") {
          const auto* val = std::get_if<bool>(call.arguments());
          minimize_to_tray_ = val ? *val : true;
          result->Success();
        } else if (call.method_name() == "setDaemonMode") {
          const auto* val = std::get_if<bool>(call.arguments());
          daemon_mode_ = val ? *val : false;
          result->Success();
        } else if (call.method_name() == "savePlacement") {
          SavePlacement();
          result->Success();
        } else if (call.method_name() == "showWindow") {
          CancelMemoryTrim();
          is_hidden_state_ = false;
          if (view_controller_ == nullptr) {
            AttachView(/*show_after_frame=*/true);
          } else {
            ShowAndFocus();
            FlutterDesktopViewControllerForceRedraw(view_controller_);
          }
          result->Success();
        } else if (call.method_name() == "hideWindow") {
          HideToTray(/*notify_dart=*/false);
          result->Success();
        } else if (call.method_name() == "trimMemory") {
          TrimProcessMemory();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  if (!FlutterDesktopEngineRun(engine_, nullptr)) {
    return false;
  }

  return true;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RestorePlacement();

  if (!CreateAndRunEngine()) {
    return false;
  }

  bool start_minimized = false;
  for (const auto& arg : dart_entrypoint_arguments_) {
    if (arg == "--start-minimized") {
      start_minimized = true;
      break;
    }
  }

  if (start_minimized) {
    is_hidden_state_ = true;
    ScheduleMemoryTrim(2500);
    return true;
  }

  is_hidden_state_ = false;
  return AttachView(/*show_after_frame=*/true);
}

bool FlutterWindow::AttachView(bool show_after_frame) {
  if (engine_ == nullptr) {
    return false;
  }

  CancelMemoryTrim();

  if (view_controller_ != nullptr) {
    if (show_after_frame) {
      ShowAndFocus();
    }
    FlutterDesktopViewControllerForceRedraw(view_controller_);
    return true;
  }

  RECT frame = GetClientArea();
  int width = frame.right - frame.left;
  int height = frame.bottom - frame.top;
  if (width <= 0 || height <= 0) {
    width = 1280;
    height = 720;
  }

  FlutterDesktopViewControllerProperties view_props{};
  view_props.width = width;
  view_props.height = height;

  view_controller_ =
      FlutterDesktopEngineCreateViewController(engine_, &view_props);
  if (view_controller_ == nullptr) {
    return false;
  }

  FlutterDesktopViewRef view =
      FlutterDesktopViewControllerGetView(view_controller_);
  if (view == nullptr) {
    FlutterDesktopViewControllerDestroy(view_controller_);
    view_controller_ = nullptr;
    return false;
  }

  HWND view_hwnd = FlutterDesktopViewGetHWND(view);
  SetChildContent(view_hwnd);
  ::ShowWindow(view_hwnd, SW_SHOW);

  if (show_after_frame) {
    pending_show_on_next_frame_ = true;
    FlutterDesktopEngineSetNextFrameCallback(
        engine_,
        [](void* user_data) {
          auto* self = static_cast<FlutterWindow*>(user_data);
          if (self->pending_show_on_next_frame_) {
            self->pending_show_on_next_frame_ = false;
            if (self->GetHandle() != nullptr) {
              ::KillTimer(self->GetHandle(), kShowFallbackTimerId);
            }
            self->ShowAndFocus();
          }
        },
        this);
    if (GetHandle() != nullptr) {
      ::SetTimer(GetHandle(), kShowFallbackTimerId, 150, nullptr);
    }
  }

  FlutterDesktopViewControllerForceRedraw(view_controller_);
  return true;
}

void FlutterWindow::ShowAndFocus() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, restore_maximized_ ? SW_SHOWMAXIMIZED : SW_RESTORE);
  } else {
    ShowWithRestoredState();
  }
  ::BringWindowToTop(hwnd);
  ::SetForegroundWindow(hwnd);
  HWND child = ::GetWindow(hwnd, GW_CHILD);
  if (child != nullptr) {
    ::ShowWindow(child, SW_SHOW);
    ::UpdateWindow(child);
    ::SetFocus(child);
  }
}

void FlutterWindow::HideToTray(bool notify_dart) {
  HWND hwnd = GetHandle();
  if (hwnd != nullptr && ::IsWindowVisible(hwnd) && !::IsIconic(hwnd)) {
    SavePlacement();
  }

  is_hidden_state_ = true;

  if (hwnd != nullptr) {
    ::ShowWindow(hwnd, SW_HIDE);
  }

  if (view_controller_ != nullptr) {
    FlutterDesktopViewRef view =
        FlutterDesktopViewControllerGetView(view_controller_);
    if (view != nullptr) {
      HWND child = FlutterDesktopViewGetHWND(view);
      if (child != nullptr) {
        ::ShowWindow(child, SW_HIDE);
      }
    }
  }

  if (notify_dart) {
    NotifyDart("onWindowHidden");
  }

  if (!daemon_mode_) {
    ScheduleMemoryTrim(500);
  }
}

void FlutterWindow::RestorePlacement() {
  WINDOWPLACEMENT placement{};
  DWORD size = sizeof(placement);
  if (::RegGetValueW(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
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

  ::RegSetKeyValueW(HKEY_CURRENT_USER, kSettingsKey, kPlacementValue,
                    REG_BINARY, &placement, sizeof(placement));
}

void FlutterWindow::ShowWithRestoredState() {
  ::ShowWindow(GetHandle(),
               restore_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
}

void FlutterWindow::ScheduleMemoryTrim(UINT delay_ms) {
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    ::SetTimer(hwnd, kMemoryTrimTimerId, delay_ms, nullptr);
  }
}

void FlutterWindow::CancelMemoryTrim() {
  HWND hwnd = GetHandle();
  if (hwnd != nullptr) {
    ::KillTimer(hwnd, kMemoryTrimTimerId);
  }
}

void FlutterWindow::TrimProcessMemory() {
  if (messenger_) {
    const char* kSystemChannel = "flutter/system";
    const char* kMemoryPressureMsg = "{\"type\":\"memoryPressure\"}";
    messenger_->Send(kSystemChannel,
                     reinterpret_cast<const uint8_t*>(kMemoryPressureMsg),
                     strlen(kMemoryPressureMsg), nullptr);
  }

  ::HeapCompact(::GetProcessHeap(), 0);
  ::SetProcessWorkingSetSizeEx(::GetCurrentProcess(), static_cast<SIZE_T>(-1),
                               static_cast<SIZE_T>(-1), 0);
}

void FlutterWindow::NotifyDart(const std::string& method) {
  if (window_channel_) {
    window_channel_->InvokeMethod(method, nullptr);
  }
}

void FlutterWindow::OnDestroy() {
  CancelMemoryTrim();
  if (view_controller_ != nullptr) {
    FlutterDesktopViewControllerRef controller = view_controller_;
    view_controller_ = nullptr;
    SetChildContent(nullptr);
    FlutterDesktopViewControllerDestroy(controller);
  }
  window_channel_.reset();
  messenger_.reset();
  if (engine_ != nullptr) {
    FlutterDesktopEngineDestroy(engine_);
    engine_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WakeUpMessage()) {
    CancelMemoryTrim();
    is_hidden_state_ = false;
    NotifyDart("onWindowRestored");
    if (view_controller_ == nullptr) {
      AttachView(/*show_after_frame=*/true);
    } else {
      ShowAndFocus();
      FlutterDesktopViewRef view =
          FlutterDesktopViewControllerGetView(view_controller_);
      if (view != nullptr) {
        HWND child = FlutterDesktopViewGetHWND(view);
        if (child != nullptr) {
          ::ShowWindow(child, SW_SHOW);
          ::UpdateWindow(child);
        }
      }
      FlutterDesktopViewControllerForceRedraw(view_controller_);
    }
    return 0;
  }

  if (message == WM_TIMER) {
    if (wparam == kMemoryTrimTimerId) {
      ::KillTimer(hwnd, kMemoryTrimTimerId);
      if (is_hidden_state_) {
        TrimProcessMemory();
      }
      return 0;
    }
    if (wparam == kShowFallbackTimerId) {
      ::KillTimer(hwnd, kShowFallbackTimerId);
      if (pending_show_on_next_frame_) {
        pending_show_on_next_frame_ = false;
        ShowAndFocus();
      }
      return 0;
    }
  }

  if (message == WM_ENTERSIZEMOVE) {
    in_size_move_ = true;
  }

  if (message == WM_EXITSIZEMOVE) {
    in_size_move_ = false;
    SavePlacement();
  }

  if (message == WM_WINDOWPOSCHANGED && !in_size_move_ &&
      ::IsWindowVisible(hwnd) && !::IsIconic(hwnd)) {
    const auto* pos = reinterpret_cast<const WINDOWPOS*>(lparam);
    if ((pos->flags & (SWP_NOMOVE | SWP_NOSIZE)) !=
        (SWP_NOMOVE | SWP_NOSIZE)) {
      SavePlacement();
    }
  }

  if (message == WM_CLOSE) {
    SavePlacement();
    if (minimize_to_tray_) {
      HideToTray(/*notify_dart=*/true);
      return 0;
    } else {
      NotifyDart("onWindowCloseRequest");
      return 0;
    }
  }

  if (message == WM_SIZE) {
    if (wparam == SIZE_MINIMIZED) {
      is_hidden_state_ = true;
      if (view_controller_ != nullptr) {
        FlutterDesktopViewRef view =
            FlutterDesktopViewControllerGetView(view_controller_);
        if (view != nullptr) {
          HWND child = FlutterDesktopViewGetHWND(view);
          if (child != nullptr) {
            ::ShowWindow(child, SW_HIDE);
          }
        }
      }
      NotifyDart("onWindowMinimized");
      ScheduleMemoryTrim(500);
      return 0;
    } else if (wparam == SIZE_RESTORED || wparam == SIZE_MAXIMIZED) {
      bool maximized = wparam == SIZE_MAXIMIZED;
      if (maximized != restore_maximized_ && ::IsWindowVisible(hwnd)) {
        restore_maximized_ = maximized;
        SavePlacement();
      }
      if (::IsWindowVisible(hwnd)) {
        CancelMemoryTrim();
        is_hidden_state_ = false;
        NotifyDart("onWindowRestored");
        if (view_controller_ == nullptr) {
          AttachView(/*show_after_frame=*/false);
        } else {
          FlutterDesktopViewRef view =
              FlutterDesktopViewControllerGetView(view_controller_);
          if (view != nullptr) {
            HWND child = FlutterDesktopViewGetHWND(view);
            if (child != nullptr) {
              ::ShowWindow(child, SW_SHOW);
              ::UpdateWindow(child);
            }
          }
          FlutterDesktopViewControllerForceRedraw(view_controller_);
        }
      }
    }
  }

  if (view_controller_ != nullptr) {
    LRESULT flutter_result = 0;
    if (FlutterDesktopViewControllerHandleTopLevelWindowProc(
            view_controller_, hwnd, message, wparam, lparam, &flutter_result)) {
      return flutter_result;
    }
  } else if (engine_ != nullptr) {
    LRESULT engine_result = 0;
    if (FlutterDesktopEngineProcessExternalWindowMessage(
            engine_, hwnd, message, wparam, lparam, &engine_result)) {
      return engine_result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (engine_ != nullptr) {
        FlutterDesktopEngineReloadSystemFonts(engine_);
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
