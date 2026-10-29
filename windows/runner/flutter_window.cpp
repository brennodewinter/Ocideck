#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>

#include <flutter/standard_method_codec.h>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "mic_capture.h"
#include "system_capture.h"
#include "flutter/generated_plugin_registrant.h"

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
  // Dezelfde naam als het macOS-kanaal: OpenFileChannel.activate luistert
  // hier naar `openFiles`, waar WM_COPYDATA van een tweede starter landt.
  open_file_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "ocideck/open_file",
          &flutter::StandardMethodCodec::GetInstance());
  RegisterMicCapture(flutter_controller_->engine()->messenger(), GetHandle());
  RegisterSystemCapture(flutter_controller_->engine()->messenger(), GetHandle());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(flutter_view_controller->engine());
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  ShutdownMicCapture();
  ShutdownSystemCapture();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (message == kMicCaptureMessage) {
    HandleMicCaptureMessage(wparam, lparam);
    return 0;
  }
  if (message == kSystemCaptureMessage) {
    HandleSystemCaptureMessage(wparam, lparam);
    return 0;
  }
  if (message == WM_COPYDATA && HandleOpenFilesCopyData(hwnd, lparam)) {
    // WM_COPYDATA vraagt TRUE van de ontvanger als het bericht verwerkt is.
    return TRUE;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::HandleOpenFilesCopyData(HWND hwnd,
                                            LPARAM lparam) noexcept {
  const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (data == nullptr || data->dwData != kOpenFilesCopyDataId ||
      data->lpData == nullptr || data->cbData == 0) {
    return false;
  }
  // Payload: '\n'-gescheiden UTF-8-paden — '\n' kan niet in een Windows-
  // bestandsnaam, dus er is geen ontsnapping nodig.
  const std::string payload(static_cast<const char*>(data->lpData),
                            data->cbData);
  flutter::EncodableList paths;
  size_t start = 0;
  while (start <= payload.size()) {
    const size_t end = payload.find('\n', start);
    const size_t n = end == std::string::npos ? payload.size() : end;
    if (n > start) {
      paths.emplace_back(
          flutter::EncodableValue(payload.substr(start, n - start)));
    }
    if (end == std::string::npos) break;
    start = end + 1;
  }
  if (paths.empty()) return false;
  if (open_file_channel_) {
    open_file_channel_->InvokeMethod(
        "openFiles",
        std::make_unique<flutter::EncodableValue>(std::move(paths)));
  }
  // Zelf naar voren: de tweede starter mag AllowSetForegroundWindow hebben
  // gegeven, maar de echte boodschap ("toon je") landt hier.
  ::ShowWindow(hwnd, SW_RESTORE);
  ::SetForegroundWindow(hwnd);
  return true;
}
