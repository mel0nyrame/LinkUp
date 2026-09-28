#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <winsock2.h>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <wlanapi.h>
#include <netioapi.h>

#include <cstdint>
#include <memory>
#include <string>

#include "win32_window.h"

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
  struct WifiSnapshot {
    std::string adapter;
    std::string address;
    unsigned int interface_index = 0;
    int64_t association_epoch = 0;
    int64_t revision = 0;

    bool operator==(const WifiSnapshot& other) const {
      return adapter == other.adapter && address == other.address &&
             interface_index == other.interface_index &&
             association_epoch == other.association_epoch;
    }
  };

  static void WINAPI OnWlanNotification(PWLAN_NOTIFICATION_DATA data,
                                        PVOID context);
  static void WINAPI OnIpAddressChange(PVOID context,
                                       PMIB_UNICASTIPADDRESS_ROW row,
                                       MIB_NOTIFICATION_TYPE type);
  WifiSnapshot ReadWifiSnapshot();
  WifiSnapshot RefreshWifiSnapshot();
  void PublishWifiSnapshot();
  flutter::EncodableMap WifiPayload(const WifiSnapshot& snapshot) const;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> wifi_channel_;
  HANDLE wlan_handle_ = nullptr;
  HANDLE ip_notification_ = nullptr;
  HWND notification_window_ = nullptr;
  WifiSnapshot wifi_snapshot_;
  bool has_wifi_snapshot_ = false;
  int64_t association_epoch_ = 0;
  int64_t wifi_revision_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
