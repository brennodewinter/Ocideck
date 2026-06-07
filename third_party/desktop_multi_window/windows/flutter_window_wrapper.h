#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_

#include <Windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <memory>
#include <string>

namespace {

struct MonitorSearch {
  HMONITOR current = nullptr;
  HMONITOR external = nullptr;
  HMONITOR fallback = nullptr;
};

inline BOOL CALLBACK FindPresentationMonitor(HMONITOR monitor,
                                             HDC,
                                             LPRECT,
                                             LPARAM data) {
  auto* search = reinterpret_cast<MonitorSearch*>(data);
  if (!search->fallback) {
    search->fallback = monitor;
  }
  if (monitor != search->current && !search->external) {
    search->external = monitor;
  }
  return TRUE;
}

inline bool ReadExternalArgument(const flutter::EncodableMap* arguments) {
  if (!arguments) {
    return true;
  }
  const auto it = arguments->find(flutter::EncodableValue("external"));
  if (it == arguments->end()) {
    return true;
  }
  const auto* external = std::get_if<bool>(&it->second);
  return external ? *external : true;
}

}  // namespace

class FlutterWindowWrapper {
 public:
  FlutterWindowWrapper(const std::string& window_id,
                       HWND hwnd,
                       const std::string& window_argument = "")
      : window_id_(window_id), hwnd_(hwnd), window_argument_(window_argument) {}

  ~FlutterWindowWrapper() = default;

  std::string GetWindowId() const { return window_id_; }

  std::string GetWindowArgument() const { return window_argument_; }

  HWND GetWindowHandle() { return hwnd_; }

  void SetChannel(
      std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
          channel) {
    channel_ = channel;
  }

  void NotifyWindowEvent(const std::string& event,
                         const flutter::EncodableMap& data) {
    if (channel_) {
      channel_->InvokeMethod(event,
                             std::make_unique<flutter::EncodableValue>(data));
    }
  }

  void HandleWindowMethod(
      const std::string& method,
      const flutter::EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (method == "window_show") {
      if (hwnd_) {
        ::ShowWindow(hwnd_, SW_SHOW);
      }
      result->Success();
    } else if (method == "window_hide") {
      if (hwnd_) {
        ::ShowWindow(hwnd_, SW_HIDE);
      }
      result->Success();
    } else if (method == "window_close") {
      result->Success();
      if (hwnd_) {
        ::PostMessage(hwnd_, WM_CLOSE, 0, 0);
      }
    } else if (method == "window_coverScreen") {
      if (!hwnd_) {
        result->Error("-1", "window is not available");
        return;
      }

      MonitorSearch search;
      search.current = ::MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST);
      ::EnumDisplayMonitors(
          nullptr, nullptr, FindPresentationMonitor,
          reinterpret_cast<LPARAM>(&search));

      HMONITOR target = search.current;
      if (ReadExternalArgument(arguments) && search.external) {
        target = search.external;
      } else if (!target) {
        target = search.fallback;
      }

      MONITORINFO monitor_info{sizeof(MONITORINFO)};
      if (!target || !::GetMonitorInfo(target, &monitor_info)) {
        result->Error("-1", "unable to find a display");
        return;
      }

      const RECT bounds = monitor_info.rcMonitor;
      ::SetWindowLongPtr(hwnd_, GWL_STYLE, WS_POPUP | WS_VISIBLE);
      ::SetWindowLongPtr(hwnd_, GWL_EXSTYLE,
                         ::GetWindowLongPtr(hwnd_, GWL_EXSTYLE) &
                             ~WS_EX_WINDOWEDGE);
      ::SetWindowPos(hwnd_, HWND_TOP, bounds.left, bounds.top,
                     bounds.right - bounds.left, bounds.bottom - bounds.top,
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
      result->Success();
    } else {
      result->Error("-1", "unknown method: " + method);
    }
  }

 protected:
  void SetWindowHandle(HWND hwnd) { hwnd_ = hwnd; }

 private:
  std::string window_id_;
  HWND hwnd_;
  std::string window_argument_;
  std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_
