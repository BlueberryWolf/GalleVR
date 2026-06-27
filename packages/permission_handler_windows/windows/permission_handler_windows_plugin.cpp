#include "include/permission_handler_windows/permission_handler_windows_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>
#include <windows.h>

#include <memory>
#include <map>
#include <string>
#include <vector>

#include "permission_constants.h"

namespace {

using namespace flutter;

class PermissionHandlerWindowsPlugin : public Plugin {
 public:
  static void RegisterWithRegistrar(PluginRegistrar* registrar);

  PermissionHandlerWindowsPlugin() = default;
  virtual ~PermissionHandlerWindowsPlugin() = default;

  PermissionHandlerWindowsPlugin(const PermissionHandlerWindowsPlugin&) = delete;
  PermissionHandlerWindowsPlugin& operator=(const PermissionHandlerWindowsPlugin&) = delete;

  void HandleMethodCall(const MethodCall<>& method_call,
                        std::unique_ptr<MethodResult<>> result);
};

// static
void PermissionHandlerWindowsPlugin::RegisterWithRegistrar(
    PluginRegistrar* registrar) {
  auto channel = std::make_unique<MethodChannel<>>(
    registrar->messenger(), "flutter.baseflow.com/permissions/methods",
    &StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PermissionHandlerWindowsPlugin>();

  channel->SetMethodCallHandler(
    [plugin_pointer = plugin.get()](const auto& call, auto result) {
      plugin_pointer->HandleMethodCall(call, std::move(result));
    });

  registrar->AddPlugin(std::move(plugin));
}

void PermissionHandlerWindowsPlugin::HandleMethodCall(
    const MethodCall<>& method_call,
    std::unique_ptr<MethodResult<>> result) {
  const std::string& methodName = method_call.method_name();

  if (methodName.compare("checkServiceStatus") == 0) {
    result->Success(EncodableValue((int)PermissionConstants::ServiceStatus::NOT_APPLICABLE));
  } else if (methodName.compare("checkPermissionStatus") == 0) {
    result->Success(EncodableValue((int)PermissionConstants::PermissionStatus::GRANTED));
  } else if (methodName.compare("requestPermissions") == 0) {
    auto permissionsEncoded = std::get<EncodableList>(*method_call.arguments());
    EncodableMap requestResults;
    for (const auto& permissionVal : permissionsEncoded) {
      requestResults.insert({permissionVal, EncodableValue((int)PermissionConstants::PermissionStatus::GRANTED)});
    }
    result->Success(EncodableValue(requestResults));
  } else if (methodName.compare("shouldShowRequestPermissionRationale") == 0) {
    result->Success(EncodableValue(false));
  } else if (methodName.compare("openAppSettings") == 0) {
    result->Success(EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

} // namespace

void PermissionHandlerWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  PermissionHandlerWindowsPlugin::RegisterWithRegistrar(
      PluginRegistrarManager::GetInstance()
          ->GetRegistrar<PluginRegistrarWindows>(registrar));
}
