#include "include/permission_handler_windows/permission_handler_windows_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <algorithm>
#include <memory>
#include <string>
#include <variant>
#include <vector>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Geolocation.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>

#include "permission_constants.h"

namespace {

using namespace flutter;
using namespace winrt;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Geolocation;
using namespace winrt::Windows::Devices::Radios;

class PermissionHandlerWindowsPlugin : public Plugin {
 public:
  static void RegisterWithRegistrar(PluginRegistrar* registrar);

  PermissionHandlerWindowsPlugin() = default;
  ~PermissionHandlerWindowsPlugin() override = default;

  PermissionHandlerWindowsPlugin(const PermissionHandlerWindowsPlugin&) =
      delete;
  PermissionHandlerWindowsPlugin& operator=(
      const PermissionHandlerWindowsPlugin&) = delete;

  void HandleMethodCall(const MethodCall<>& method_call,
                        std::unique_ptr<MethodResult<>> result);

 private:
  void IsLocationServiceEnabled(std::unique_ptr<MethodResult<>> result);
  winrt::fire_and_forget IsBluetoothServiceEnabled(
      std::unique_ptr<MethodResult<>> result);
};

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
  const auto& method_name = method_call.method_name();
  if (method_name == "checkServiceStatus") {
    const auto permission = static_cast<PermissionConstants::PermissionGroup>(
        std::get<int>(*method_call.arguments()));
    if (permission == PermissionConstants::PermissionGroup::LOCATION ||
        permission == PermissionConstants::PermissionGroup::LOCATION_ALWAYS ||
        permission ==
            PermissionConstants::PermissionGroup::LOCATION_WHEN_IN_USE) {
      IsLocationServiceEnabled(std::move(result));
      return;
    }
    if (permission == PermissionConstants::PermissionGroup::BLUETOOTH) {
      IsBluetoothServiceEnabled(std::move(result));
      return;
    }
    if (permission == PermissionConstants::PermissionGroup::
                          IGNORE_BATTERY_OPTIMIZATIONS) {
      result->Success(EncodableValue(
          static_cast<int>(PermissionConstants::ServiceStatus::ENABLED)));
      return;
    }
    result->Success(EncodableValue(
        static_cast<int>(PermissionConstants::ServiceStatus::NOT_APPLICABLE)));
    return;
  }

  if (method_name == "checkPermissionStatus") {
    result->Success(EncodableValue(
        static_cast<int>(PermissionConstants::PermissionStatus::GRANTED)));
    return;
  }

  if (method_name == "requestPermissions") {
    const auto permissions_encoded =
        std::get<EncodableList>(*method_call.arguments());
    EncodableMap request_results;
    for (const auto& encoded : permissions_encoded) {
      request_results.insert(
          {encoded,
           EncodableValue(static_cast<int>(
               PermissionConstants::PermissionStatus::GRANTED))});
    }
    result->Success(request_results);
    return;
  }

  if (method_name == "shouldShowRequestPermissionRationale" ||
      method_name == "openAppSettings") {
    result->Success(EncodableValue(false));
    return;
  }

  result->NotImplemented();
}

void PermissionHandlerWindowsPlugin::IsLocationServiceEnabled(
    std::unique_ptr<MethodResult<>> result) {
  // Upstream stores Geolocator plus a PositionChanged subscription on the
  // plugin object. Windows consequently reports that TaskMaster Pro is using
  // location for the lifetime of the process, even though no position is
  // requested. Create the object only for this explicit status query and let
  // it be released before returning to the app.
  const Geolocator one_shot_geolocator;
  const auto status = one_shot_geolocator.LocationStatus();
  result->Success(EncodableValue(static_cast<int>(
      status != PositionStatus::NotAvailable
          ? PermissionConstants::ServiceStatus::ENABLED
          : PermissionConstants::ServiceStatus::DISABLED)));
}

winrt::fire_and_forget
PermissionHandlerWindowsPlugin::IsBluetoothServiceEnabled(
    std::unique_ptr<MethodResult<>> result) {
  const auto bluetooth_adapter = co_await BluetoothAdapter::GetDefaultAsync();
  if (bluetooth_adapter == nullptr ||
      !bluetooth_adapter.IsCentralRoleSupported()) {
    result->Success(EncodableValue(
        static_cast<int>(PermissionConstants::ServiceStatus::DISABLED)));
    co_return;
  }

  const auto radios = co_await Radio::GetRadiosAsync();
  for (uint32_t index = 0; index < radios.Size(); index++) {
    const auto radio = radios.GetAt(index);
    if (radio.Kind() == RadioKind::Bluetooth) {
      // A service-status query must never turn Bluetooth on. Report the
      // current OS state and leave the user's radio setting untouched.
      result->Success(EncodableValue(static_cast<int>(
          radio.State() == RadioState::On
              ? PermissionConstants::ServiceStatus::ENABLED
              : PermissionConstants::ServiceStatus::DISABLED)));
      co_return;
    }
  }

  result->Success(EncodableValue(
      static_cast<int>(PermissionConstants::ServiceStatus::DISABLED)));
}

}  // namespace

void PermissionHandlerWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  PermissionHandlerWindowsPlugin::RegisterWithRegistrar(
      PluginRegistrarManager::GetInstance()
          ->GetRegistrar<PluginRegistrarWindows>(registrar));
}
