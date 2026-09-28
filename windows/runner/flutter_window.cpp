#include <winsock2.h>
#include <ws2tcpip.h>

#include "flutter_window.h"

#include <iphlpapi.h>

#include <array>
#include <optional>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "wifi_tunnel.h"

namespace {
constexpr UINT kWifiChangedMessage = WM_APP + 0x151;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

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

  wifi_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.mel0ny.linkup/windowsWifi",
      &flutter::StandardMethodCodec::GetInstance());
  wifi_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "getSnapshot") {
          result->Success(flutter::EncodableValue(
              WifiPayload(RefreshWifiSnapshot())));
        } else if (call.method_name() == "openTunnel") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!args) {
            result->Error("invalid_target", "Missing tunnel target");
            return;
          }
          const auto host = args->find(flutter::EncodableValue("host"));
          const auto port = args->find(flutter::EncodableValue("port"));
          if (host == args->end() || port == args->end() ||
              !std::holds_alternative<std::string>(host->second) ||
              !std::holds_alternative<int32_t>(port->second)) {
            result->Error("invalid_target", "Invalid tunnel target");
            return;
          }
          const auto snapshot = RefreshWifiSnapshot();
          if (snapshot.address.empty() || snapshot.interface_index == 0) {
            result->Error("wifi_unavailable", "Wi-Fi unavailable");
            return;
          }
          const auto local_port = OpenWifiTunnel(
              std::get<std::string>(host->second),
              std::get<int32_t>(port->second), snapshot.address,
              snapshot.interface_index);
          if (!local_port) {
            result->Error("tunnel_unavailable", "Wi-Fi tunnel unavailable");
            return;
          }
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("port"),
               flutter::EncodableValue(local_port->port)},
              {flutter::EncodableValue("token"),
               flutter::EncodableValue(local_port->token)},
          }));
        } else {
          result->NotImplemented();
        }
      });

  notification_window_ = GetHandle();
  DWORD negotiated_version = 0;
  if (WlanOpenHandle(2, nullptr, &negotiated_version, &wlan_handle_) ==
      ERROR_SUCCESS) {
    if (WlanRegisterNotification(wlan_handle_, WLAN_NOTIFICATION_SOURCE_ACM,
                                 TRUE, OnWlanNotification, this, nullptr,
                                 nullptr) != ERROR_SUCCESS) {
      WlanCloseHandle(wlan_handle_, nullptr);
      wlan_handle_ = nullptr;
    }
  }
  if (NotifyUnicastIpAddressChange(AF_INET, OnIpAddressChange, this, FALSE,
                                   &ip_notification_) != NO_ERROR) {
    ip_notification_ = nullptr;
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (ip_notification_) {
    CancelMibChangeNotify2(ip_notification_);
    ip_notification_ = nullptr;
  }
  if (wlan_handle_) {
    WlanCloseHandle(wlan_handle_, nullptr);
    wlan_handle_ = nullptr;
  }
  wifi_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kWifiChangedMessage) {
    if (wparam != 0) ++association_epoch_;
    PublishWifiSnapshot();
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void WINAPI FlutterWindow::OnWlanNotification(PWLAN_NOTIFICATION_DATA data,
                                               PVOID context) {
  if (data->NotificationSource != WLAN_NOTIFICATION_SOURCE_ACM) return;
  if (data->NotificationCode != wlan_notification_acm_connection_complete &&
      data->NotificationCode != wlan_notification_acm_disconnected) return;
  auto* window = static_cast<FlutterWindow*>(context);
  PostMessage(window->notification_window_, kWifiChangedMessage, 1, 0);
}

void WINAPI FlutterWindow::OnIpAddressChange(PVOID context,
                                              PMIB_UNICASTIPADDRESS_ROW row,
                                              MIB_NOTIFICATION_TYPE type) {
  auto* window = static_cast<FlutterWindow*>(context);
  PostMessage(window->notification_window_, kWifiChangedMessage, 0, 0);
}

FlutterWindow::WifiSnapshot FlutterWindow::ReadWifiSnapshot() {
  WifiSnapshot snapshot;
  snapshot.association_epoch = association_epoch_;
  if (!wlan_handle_) return snapshot;

  PWLAN_INTERFACE_INFO_LIST interfaces = nullptr;
  if (WlanEnumInterfaces(wlan_handle_, nullptr, &interfaces) != ERROR_SUCCESS)
    return snapshot;

  ULONG size = 0;
  DWORD status = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST |
                                                 GAA_FLAG_SKIP_MULTICAST |
                                                 GAA_FLAG_SKIP_DNS_SERVER,
                                      nullptr, nullptr, &size);
  std::vector<unsigned char> buffer(size);
  if (status == ERROR_BUFFER_OVERFLOW) {
    status = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST |
                                                   GAA_FLAG_SKIP_MULTICAST |
                                                   GAA_FLAG_SKIP_DNS_SERVER,
                                  nullptr,
                                  reinterpret_cast<PIP_ADAPTER_ADDRESSES>(
                                      buffer.data()),
                                  &size);
  }

  if (status == NO_ERROR) {
    auto* adapters = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data());
    for (DWORD i = 0; i < interfaces->dwNumberOfItems; ++i) {
      const auto& wlan_info = interfaces->InterfaceInfo[i];
      if (wlan_info.isState != wlan_interface_state_connected) continue;
      NET_LUID luid{};
      if (ConvertInterfaceGuidToLuid(&wlan_info.InterfaceGuid, &luid) !=
          NO_ERROR) continue;
      for (auto* adapter = adapters; adapter; adapter = adapter->Next) {
        if (adapter->Luid.Value != luid.Value ||
            adapter->OperStatus != IfOperStatusUp) continue;
        for (auto* address = adapter->FirstUnicastAddress; address;
             address = address->Next) {
          if (address->Address.lpSockaddr->sa_family != AF_INET) continue;
          const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(
              address->Address.lpSockaddr);
          std::array<char, INET_ADDRSTRLEN> text{};
          if (InetNtopA(AF_INET, &ipv4->sin_addr, text.data(),
                        static_cast<DWORD>(text.size())) == nullptr) continue;
          snapshot.adapter = std::to_string(luid.Value);
          snapshot.address = text.data();
          snapshot.interface_index = adapter->IfIndex;
          break;
        }
        if (!snapshot.address.empty()) break;
      }
      if (!snapshot.address.empty()) break;
    }
  }
  WlanFreeMemory(interfaces);
  return snapshot;
}

FlutterWindow::WifiSnapshot FlutterWindow::RefreshWifiSnapshot() {
  auto snapshot = ReadWifiSnapshot();
  if (!has_wifi_snapshot_ || !(snapshot == wifi_snapshot_)) {
    snapshot.revision = ++wifi_revision_;
    wifi_snapshot_ = snapshot;
    has_wifi_snapshot_ = true;
  }
  return wifi_snapshot_;
}

flutter::EncodableMap FlutterWindow::WifiPayload(
    const WifiSnapshot& snapshot) const {
  return {{flutter::EncodableValue("connected"),
           flutter::EncodableValue(!snapshot.address.empty())},
          {flutter::EncodableValue("address"),
           flutter::EncodableValue(snapshot.address)},
          {flutter::EncodableValue("adapter"),
           flutter::EncodableValue(snapshot.adapter)},
          {flutter::EncodableValue("revision"),
           flutter::EncodableValue(snapshot.revision)}};
}

void FlutterWindow::PublishWifiSnapshot() {
  if (!wifi_channel_) return;
  const auto previous_revision = wifi_revision_;
  const auto snapshot = RefreshWifiSnapshot();
  if (snapshot.revision == previous_revision) return;
  wifi_channel_->InvokeMethod(
      "onChanged", std::make_unique<flutter::EncodableValue>(
                       WifiPayload(snapshot)));
}
