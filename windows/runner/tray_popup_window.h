#ifndef RUNNER_TRAY_POPUP_WINDOW_H_
#define RUNNER_TRAY_POPUP_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <functional>
#include <memory>
#include <string>

#include "win32_window.h"

// A second Flutter view for status only. Authentication stays in the main
// engine; this window receives a small presentation snapshot over a channel.
class TrayPopupWindow : public Win32Window {
 public:
  TrayPopupWindow(flutter::DartProject project, flutter::EncodableMap state,
                  std::function<void(const std::string&)> on_action,
                  std::function<bool()> should_hide_on_deactivate);
  ~TrayPopupWindow() override;

  void ShowAt(const RECT& bounds);
  void Hide();
  bool IsOpen() const;
  void UpdateState(flutter::EncodableMap state);

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept override;

 private:
  flutter::DartProject project_;
  flutter::EncodableMap state_;
  RECT pending_bounds_{};
  bool ready_ = false;
  bool open_ = false;
  std::function<void(const std::string&)> on_action_;
  std::function<bool()> should_hide_on_deactivate_;
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_TRAY_POPUP_WINDOW_H_
