#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registry.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

class FlutterWindow : public Win32Window, public flutter::PluginRegistry {
 public:
  FlutterWindow(const std::wstring& data_directory,
                std::vector<std::string> dart_entrypoint_arguments);
  virtual ~FlutterWindow();

  static UINT WakeUpMessage();

  FlutterDesktopPluginRegistrarRef GetRegistrarForPlugin(
      const std::string& plugin_name) override;

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  class EngineBinaryMessenger;

  bool CreateAndRunEngine();
  bool AttachView(bool show_after_frame);
  void ShowAndFocus();
  void HideToTray(bool notify_dart);
  void RestorePlacement();
  void SavePlacement();
  void ShowWithRestoredState();
  void ScheduleMemoryTrim(UINT delay_ms);
  void CancelMemoryTrim();
  void TrimProcessMemory();
  void NotifyDart(const std::string& method);

  std::wstring data_directory_;
  std::vector<std::string> dart_entrypoint_arguments_;

  FlutterDesktopEngineRef engine_ = nullptr;
  std::unique_ptr<EngineBinaryMessenger> messenger_;

  FlutterDesktopViewControllerRef view_controller_ = nullptr;

  std::unique_ptr<flutter::MethodChannel<>> window_channel_;

  bool minimize_to_tray_ = true;
  bool daemon_mode_ = false;
  bool restore_maximized_ = false;
  bool in_size_move_ = false;
  bool pending_show_on_next_frame_ = false;
  bool is_hidden_state_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
