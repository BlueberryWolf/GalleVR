#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Whether close was initiated by a system command (Alt+F4, user click, etc.)
  bool system_command_close_ = false;

  // Whether the app should minimize to tray on close
  bool minimize_to_tray_ = true;

  // Method channel for window actions
  std::unique_ptr<flutter::MethodChannel<>> window_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
