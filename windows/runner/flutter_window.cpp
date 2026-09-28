#include <winsock2.h>
#include <ws2tcpip.h>

#include "flutter_window.h"

#include <iphlpapi.h>
#include <shellapi.h>
#include <flutter_windows.h>

#include <algorithm>
#include <array>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "wifi_tunnel.h"

namespace {
constexpr UINT kWifiChangedMessage = WM_APP + 0x151;
constexpr UINT kTrayCallbackMessage = WM_APP + 0x152;
constexpr UINT kExitApplicationMessage = WM_APP + 0x154;
constexpr UINT kTrayIconId = 1;
constexpr UINT kMenuOpen = 1001;
constexpr UINT kMenuCheck = 1002;
constexpr UINT kMenuSettings = 1003;
constexpr UINT kMenuLogs = 1004;
constexpr UINT kMenuExit = 1005;
constexpr wchar_t kAutoStartSubkey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kAutoStartValueName[] = L"LinkUp";

std::optional<std::wstring> AutoStartCommandLine() {
  std::vector<wchar_t> executable_path(32768);
  const auto buffer_size = static_cast<DWORD>(executable_path.size());
  const DWORD length = GetModuleFileNameW(
      nullptr, executable_path.data(), buffer_size);
  if (length == 0 || length >= buffer_size) return std::nullopt;

  return L"\"" + std::wstring(executable_path.data(), length) +
         L"\" --background";
}

bool ReadAutoStartEnabled(bool* enabled) {
  if (enabled == nullptr) return false;
  *enabled = false;

  const auto expected_command = AutoStartCommandLine();
  if (!expected_command) return false;

  HKEY run_key = nullptr;
  LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, kAutoStartSubkey, 0,
                              KEY_QUERY_VALUE, &run_key);
  if (status == ERROR_FILE_NOT_FOUND) return true;
  if (status != ERROR_SUCCESS) return false;

  DWORD value_type = 0;
  DWORD value_size = 0;
  status = RegQueryValueExW(run_key, kAutoStartValueName, nullptr, &value_type,
                            nullptr, &value_size);
  if (status == ERROR_FILE_NOT_FOUND) {
    RegCloseKey(run_key);
    return true;
  }
  if (status != ERROR_SUCCESS || value_type != REG_SZ) {
    RegCloseKey(run_key);
    return status == ERROR_SUCCESS;
  }

  std::vector<wchar_t> value(value_size / sizeof(wchar_t) + 1, L'\0');
  status = RegQueryValueExW(run_key, kAutoStartValueName, nullptr, &value_type,
                            reinterpret_cast<LPBYTE>(value.data()),
                            &value_size);
  RegCloseKey(run_key);
  if (status != ERROR_SUCCESS) return false;

  *enabled = *expected_command == value.data();
  return true;
}

bool WriteAutoStartEnabled(bool enabled) {
  if (!enabled) {
    HKEY run_key = nullptr;
    LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, kAutoStartSubkey, 0,
                                KEY_SET_VALUE, &run_key);
    if (status == ERROR_FILE_NOT_FOUND) return true;
    if (status != ERROR_SUCCESS) return false;
    status = RegDeleteValueW(run_key, kAutoStartValueName);
    RegCloseKey(run_key);
    return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
  }

  const auto command = AutoStartCommandLine();
  if (!command) return false;

  HKEY run_key = nullptr;
  LONG status = RegCreateKeyExW(HKEY_CURRENT_USER, kAutoStartSubkey, 0,
                                nullptr, 0, KEY_SET_VALUE, nullptr, &run_key,
                                nullptr);
  if (status != ERROR_SUCCESS) return false;

  const DWORD value_size =
      static_cast<DWORD>((command->size() + 1) * sizeof(wchar_t));
  status = RegSetValueExW(
      run_key, kAutoStartValueName, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command->c_str()), value_size);
  RegCloseKey(run_key);
  return status == ERROR_SUCCESS;
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (size <= 1) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, result.data(), size);
  result.pop_back();
  return result;
}

int ScaleForDpi(int logical_size, UINT dpi) {
  return MulDiv(logical_size, static_cast<int>(dpi), 96);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

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

  tray_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.mel0ny.linkup/windowsTray",
      &flutter::StandardMethodCodec::GetInstance());
  tray_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "attach") {
          tray_attach_attempted_ = true;
          if (!AddTrayIcon()) {
            result->Error("tray_unavailable", "Could not add tray icon");
            return;
          }
          result->Success();
          if (close_to_tray_pending_) {
            close_to_tray_pending_ = false;
            HideToTray();
          }
        } else if (call.method_name() == "setTooltip") {
          const auto* text = std::get_if<std::string>(call.arguments());
          if (!text) {
            result->Error("invalid_tooltip", "Tooltip must be a string");
            return;
          }
          UpdateTrayTooltip(*text);
          result->Success();
        } else if (call.method_name() == "showMain") {
          ShowMainWindow();
          DispatchTrayAction("openMain");
          result->Success();
        } else if (call.method_name() == "exitComplete") {
          exiting_ = true;
          result->Success();
          PostMessageW(GetHandle(), kExitApplicationMessage, 0, 0);
        } else {
          result->NotImplemented();
        }
      });

  startup_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.mel0ny.linkup/windowsStartup",
      &flutter::StandardMethodCodec::GetInstance());
  startup_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() == "getEnabled") {
          bool enabled = false;
          if (!ReadAutoStartEnabled(&enabled)) {
            result->Error("startup_read_failed",
                          "Could not read the Windows startup entry");
            return;
          }
          result->Success(flutter::EncodableValue(enabled));
        } else if (call.method_name() == "setEnabled") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled == nullptr) {
            result->Error("invalid_startup_setting",
                          "Expected a boolean startup setting");
            return;
          }
          if (!WriteAutoStartEnabled(*enabled)) {
            result->Error("startup_write_failed",
                          "Could not update the Windows startup entry");
            return;
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  GetWindowRect(GetHandle(), &normal_window_bounds_);
  normal_bounds_saved_ = true;
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
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
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (ip_notification_) {
    CancelMibChangeNotify2(ip_notification_);
    ip_notification_ = nullptr;
  }
  if (wlan_handle_) {
    WlanCloseHandle(wlan_handle_, nullptr);
    wlan_handle_ = nullptr;
  }
  notification_window_ = nullptr;
  tray_channel_.reset();
  startup_channel_.reset();
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
  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    if (tray_attach_attempted_) {
      tray_icon_added_ = false;
      AddTrayIcon();
    }
    return 0;
  }
  if (message == kLinkUpActivateExistingMessage) {
    ShowMainWindow();
    DispatchTrayAction("openMain");
    return 0;
  }
  if (message == kTrayCallbackMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case NIN_SELECT:
      case NIN_KEYSELECT:
        if (popup_mode_) {
          HideToTray();
        } else {
          ShowPopup();
          DispatchTrayAction("togglePopup");
        }
        return 0;
      case WM_LBUTTONDBLCLK:
        ShowMainWindow();
        DispatchTrayAction("openMain");
        return 0;
      case WM_RBUTTONUP:
      case WM_RBUTTONDBLCLK:
      case WM_CONTEXTMENU:
        ShowTrayMenu();
        return 0;
    }
  }
  if (message == WM_CLOSE) {
    if (exiting_) return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    if (!close_notice_shown_) {
      close_notice_shown_ = true;
      MessageBoxW(
          hwnd,
          L"关闭窗口后，LinkUp 会继续在系统托盘运行。要停止认证，请右键托盘图标并选择“退出 LinkUp”。",
          L"LinkUp 仍在运行", MB_OK | MB_ICONINFORMATION);
    }
    if (!tray_attach_attempted_) {
      close_to_tray_pending_ = true;
      return 0;
    }
    if (!tray_icon_added_) {
      MessageBoxW(hwnd, L"系统托盘不可用，LinkUp 将停止运行。", L"LinkUp",
                  MB_OK | MB_ICONWARNING);
      DispatchTrayAction("exitRequested");
      return 0;
    }
    HideToTray();
    return 0;
  }
  if (message == kExitApplicationMessage) {
    DestroyWindow(hwnd);
    return 0;
  }
  if (message == WM_ACTIVATE && popup_mode_ && LOWORD(wparam) == WA_INACTIVE) {
    HideToTray();
    return 0;
  }
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

bool FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_) return true;

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = notification_window_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = LoadIconW(GetModuleHandle(nullptr),
                         MAKEINTRESOURCEW(IDI_APP_ICON));
  wcsncpy_s(data.szTip, tray_tooltip_.c_str(), _TRUNCATE);
  if (!Shell_NotifyIconW(NIM_ADD, &data)) return false;

  tray_icon_added_ = true;
  data.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &data);
  return true;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = notification_window_;
  data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_icon_added_ = false;
}

void FlutterWindow::UpdateTrayTooltip(const std::string& text) {
  tray_tooltip_ = Utf8ToWide(text);
  if (tray_tooltip_.empty()) tray_tooltip_ = L"LinkUp";
  if (!tray_icon_added_) return;

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  data.uFlags = NIF_TIP;
  wcsncpy_s(data.szTip, tray_tooltip_.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void FlutterWindow::ShowPopup() {
  HWND window = GetHandle();
  if (!window) return;
  if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
  SetPopupWindowMode(true);
  const RECT bounds = PopupBounds();
  SetWindowPos(window, HWND_TOPMOST, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  SetForegroundWindow(window);
}

void FlutterWindow::ShowMainWindow() {
  HWND window = GetHandle();
  if (!window) return;
  SetPopupWindowMode(false);
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW | SWP_FRAMECHANGED);
  if (!SetForegroundWindow(window)) FlashWindow(window, TRUE);
}

void FlutterWindow::HideToTray(bool notify_dart) {
  HWND window = GetHandle();
  if (!window) return;
  SetPopupWindowMode(false);
  ShowWindow(window, SW_HIDE);
  if (notify_dart) DispatchTrayAction("hidePopup");
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, kMenuOpen, L"打开 LinkUp");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuCheck, L"立即检查");
  AppendMenuW(menu, MF_STRING, kMenuSettings, L"设置");
  AppendMenuW(menu, MF_STRING, kMenuLogs, L"查看日志");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExit, L"退出 LinkUp");

  HWND window = GetHandle();
  SetForegroundWindow(window);
  POINT cursor{};
  GetCursorPos(&cursor);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_BOTTOMALIGN,
      cursor.x, cursor.y, 0, window, nullptr);
  PostMessageW(window, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (command != 0) HandleTrayCommand(command);
}

void FlutterWindow::HandleTrayCommand(UINT command) {
  switch (command) {
    case kMenuOpen:
      ShowMainWindow();
      DispatchTrayAction("openMain");
      break;
    case kMenuCheck:
      DispatchTrayAction("manualCheck");
      break;
    case kMenuSettings:
      ShowMainWindow();
      DispatchTrayAction("openSettings");
      break;
    case kMenuLogs:
      ShowMainWindow();
      DispatchTrayAction("openLogs");
      break;
    case kMenuExit:
      DispatchTrayAction("exitRequested");
      break;
  }
}

void FlutterWindow::DispatchTrayAction(const std::string& action) {
  if (!tray_channel_) return;
  tray_channel_->InvokeMethod(
      "onAction", std::make_unique<flutter::EncodableValue>(action));
}

void FlutterWindow::SetPopupWindowMode(bool popup) {
  HWND window = GetHandle();
  if (!window || popup == popup_mode_) return;
  if (popup) {
    GetWindowRect(window, &normal_window_bounds_);
    normal_bounds_saved_ = true;
  }

  LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
  LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  if (popup) {
    style = (style & ~WS_OVERLAPPEDWINDOW) | WS_POPUP;
    extended_style = (extended_style & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;
  } else {
    style = (style & ~WS_POPUP) | WS_OVERLAPPEDWINDOW;
    extended_style = (extended_style & ~WS_EX_TOOLWINDOW) | WS_EX_APPWINDOW;
  }
  SetWindowLongPtrW(window, GWL_STYLE, style);
  SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style);
  popup_mode_ = popup;

  if (!popup && normal_bounds_saved_) {
    SetWindowPos(window, HWND_NOTOPMOST, normal_window_bounds_.left,
                 normal_window_bounds_.top,
                 normal_window_bounds_.right - normal_window_bounds_.left,
                 normal_window_bounds_.bottom - normal_window_bounds_.top,
                 SWP_FRAMECHANGED | SWP_NOACTIVATE);
  } else {
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
  }
}

RECT FlutterWindow::PopupBounds() {
  RECT icon_bounds{};
  NOTIFYICONIDENTIFIER identifier{};
  identifier.cbSize = sizeof(identifier);
  identifier.hWnd = GetHandle();
  identifier.uID = kTrayIconId;
  const bool has_icon_bounds =
      SUCCEEDED(Shell_NotifyIconGetRect(&identifier, &icon_bounds));
  if (!has_icon_bounds) {
    POINT cursor{};
    GetCursorPos(&cursor);
    icon_bounds = {cursor.x, cursor.y, cursor.x + 1, cursor.y + 1};
  }

  HMONITOR monitor = MonitorFromRect(&icon_bounds, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{sizeof(monitor_info)};
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    monitor_info.rcWork = {0, 0, GetSystemMetrics(SM_CXSCREEN),
                           GetSystemMetrics(SM_CYSCREEN)};
  }
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const LONG width = std::min<LONG>(
      ScaleForDpi(380, dpi),
      monitor_info.rcWork.right - monitor_info.rcWork.left);
  const LONG height = std::min<LONG>(
      ScaleForDpi(340, dpi),
      monitor_info.rcWork.bottom - monitor_info.rcWork.top);
  LONG x = monitor_info.rcWork.right - width;
  LONG y = monitor_info.rcWork.bottom - height;
  if (has_icon_bounds) {
    const LONG icon_x = (icon_bounds.left + icon_bounds.right) / 2;
    if (icon_bounds.left < monitor_info.rcWork.left) {
      x = monitor_info.rcWork.left;
    } else if (icon_bounds.right > monitor_info.rcWork.right) {
      x = monitor_info.rcWork.right - width;
    } else {
      x = icon_x - width / 2;
    }
    if (icon_bounds.top < monitor_info.rcWork.top) {
      y = monitor_info.rcWork.top;
    } else if (icon_bounds.bottom > monitor_info.rcWork.bottom) {
      y = monitor_info.rcWork.bottom - height;
    } else if ((icon_bounds.top + icon_bounds.bottom) / 2 <
               (monitor_info.rcWork.top + monitor_info.rcWork.bottom) / 2) {
      y = icon_bounds.bottom;
    } else {
      y = icon_bounds.top - height;
    }
  }
  x = std::clamp<LONG>(x, monitor_info.rcWork.left,
                       monitor_info.rcWork.right - width);
  y = std::clamp<LONG>(y, monitor_info.rcWork.top,
                       monitor_info.rcWork.bottom - height);
  return {x, y, x + width, y + height};
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
