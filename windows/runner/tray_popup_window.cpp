#include "tray_popup_window.h"

#include <optional>
#include <utility>

TrayPopupWindow::TrayPopupWindow(
    flutter::DartProject project, flutter::EncodableMap state,
    std::function<void(const std::string&)> on_action,
    std::function<bool()> should_hide_on_deactivate)
    : project_(std::move(project)),
      state_(std::move(state)),
      on_action_(std::move(on_action)),
      should_hide_on_deactivate_(std::move(should_hide_on_deactivate)) {}

TrayPopupWindow::~TrayPopupWindow() {}

bool TrayPopupWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;

  HWND window = GetHandle();
  SetWindowLongPtrW(window, GWL_STYLE, WS_POPUP);
  SetWindowLongPtrW(window, GWL_EXSTYLE, WS_EX_TOOLWINDOW);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                   SWP_NOZORDER | SWP_NOACTIVATE);

  project_.set_dart_entrypoint("popupMain");
  const RECT frame = GetClientArea();
  controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!controller_->engine() || !controller_->view()) return false;
  SetChildContent(controller_->view()->GetNativeWindow());

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      controller_->engine()->messenger(), "com.mel0ny.linkup/windowsPopup",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "getState") {
      result->Success(flutter::EncodableValue(state_));
    } else if (call.method_name() == "ready") {
      ready_ = true;
      if (open_) ShowAt(pending_bounds_);
      result->Success();
    } else if (call.method_name() == "manualCheck") {
      on_action_("manualCheck");
      result->Success();
    } else if (call.method_name() == "openDetails") {
      Hide();
      on_action_("openMain");
      result->Success();
    } else if (call.method_name() == "hidePopup") {
      Hide();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  return true;
}

void TrayPopupWindow::OnDestroy() {
  channel_.reset();
  controller_.reset();
  Win32Window::OnDestroy();
}

void TrayPopupWindow::ShowAt(const RECT& bounds) {
  HWND window = GetHandle();
  if (!window) return;
  pending_bounds_ = bounds;
  open_ = true;
  if (!ready_) return;
  SetWindowPos(window, HWND_TOPMOST, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  SetForegroundWindow(window);
}

void TrayPopupWindow::Hide() {
  open_ = false;
  if (GetHandle()) ShowWindow(GetHandle(), SW_HIDE);
}

bool TrayPopupWindow::IsOpen() const {
  return open_;
}

void TrayPopupWindow::UpdateState(flutter::EncodableMap state) {
  state_ = std::move(state);
  if (channel_) {
    channel_->InvokeMethod(
        "updateState", std::make_unique<flutter::EncodableValue>(state_));
  }
}

LRESULT TrayPopupWindow::MessageHandler(HWND window, UINT message,
                                        WPARAM wparam,
                                        LPARAM lparam) noexcept {
  if (message == WM_CLOSE) {
    Hide();
    return 0;
  }
  if (message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE &&
      should_hide_on_deactivate_()) {
    Hide();
    return 0;
  }
  if (controller_) {
    std::optional<LRESULT> result = controller_->HandleTopLevelWindowProc(
        window, message, wparam, lparam);
    if (result) return *result;
  }
  return Win32Window::MessageHandler(window, message, wparam, lparam);
}
