// NOTICE: This file was modified by the OciDeck project.
// Original: desktop_multi_window (c) 2021 Mixin, Apache License 2.0 (see
// ../LICENSE), commit 58a5868d1cb9031defa5db5868d6aaea0486d24a.
// Change: implemented window_close, window_setFrame and window_coverScreen on Win32.
// Modification notice per Apache-2.0 section 4(b); see ../MODIFICATIONS.md.

#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_FLUTTER_WINDOW_WRAPPER_H_

#include <Windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <memory>
#include <string>
#include <vector>

namespace {

struct MonitorSearch {
  HMONITOR current = nullptr;
  HMONITOR external = nullptr;
  HMONITOR fallback = nullptr;
  // All monitors in EnumDisplayMonitors order, so a caller-supplied screen
  // index maps to the same monitor the platform enumerates (#1913).
  std::vector<HMONITOR> monitors;
};

inline BOOL CALLBACK FindPresentationMonitor(HMONITOR monitor,
                                             HDC,
                                             LPRECT,
                                             LPARAM data) {
  auto* search = reinterpret_cast<MonitorSearch*>(data);
  search->monitors.push_back(monitor);
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
    } else if (method == "window_setFrame") {
      if (!hwnd_) {
        result->Error("-1", "window is not available");
        return;
      }
      if (arguments) {
        auto xIt = arguments->find(flutter::EncodableValue("x"));
        auto yIt = arguments->find(flutter::EncodableValue("y"));
        auto wIt = arguments->find(flutter::EncodableValue("width"));
        auto hIt = arguments->find(flutter::EncodableValue("height"));
        if (xIt != arguments->end() && yIt != arguments->end() &&
            wIt != arguments->end() && hIt != arguments->end()) {
          const double x = std::get<double>(xIt->second);
          const double y = std::get<double>(yIt->second);
          const double width = std::get<double>(wIt->second);
          const double height = std::get<double>(hIt->second);
          ::SetWindowPos(hwnd_, nullptr, static_cast<int>(x),
                         static_cast<int>(y), static_cast<int>(width),
                         static_cast<int>(height),
                         SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
      }
      result->Success();
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

      HMONITOR target = nullptr;
      // Prefer the screen the presenter is NOT on, when told which one that is
      // (index in the same EnumDisplayMonitors order). The `external` heuristic
      // below picks the non-primary screen, which is only right when the
      // presenter sits on the primary screen; in a reversed setup it would pile
      // both windows on the external display (#1913).
      if (arguments) {
        const auto it = arguments->find(flutter::EncodableValue("presenterScreen"));
        if (it != arguments->end()) {
          // The standard codec may deliver the index as int32 or int64.
          int presenter_index = -1;
          if (const auto* i32 = std::get_if<int>(&it->second)) {
            presenter_index = *i32;
          } else if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
            presenter_index = static_cast<int>(*i64);
          }
          if (presenter_index >= 0 &&
              presenter_index < static_cast<int>(search.monitors.size()) &&
              search.monitors.size() > 1) {
            HMONITOR presenter = search.monitors[presenter_index];
            for (HMONITOR m : search.monitors) {
              if (m != presenter) {
                target = m;
                break;
              }
            }
          }
        }
      }
      if (!target) {
        target = search.current;
        if (ReadExternalArgument(arguments) && search.external) {
          target = search.external;
        } else if (!target) {
          target = search.fallback;
        }
      }

      MONITORINFO monitor_info{sizeof(MONITORINFO)};
      if (!target || !::GetMonitorInfo(target, &monitor_info)) {
        result->Error("-1", "unable to find a display");
        return;
      }

      const RECT bounds = monitor_info.rcMonitor;
      ::SetWindowLongPtr(hwnd_, GWL_STYLE, WS_POPUP | WS_VISIBLE);
      ::SetWindowLongPtr(hwnd_, GWL_EXSTYLE,
                         (::GetWindowLongPtr(hwnd_, GWL_EXSTYLE) &
                          ~WS_EX_WINDOWEDGE) |
                             WS_EX_TOPMOST);
      ::SetWindowPos(hwnd_, HWND_TOPMOST, bounds.left, bounds.top,
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
