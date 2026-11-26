// NOTICE: This file was modified by the OciDeck project.
// Original: desktop_multi_window (c) 2021 Mixin, Apache License 2.0 (see
// ../LICENSE), commit 0c9aa50455106503cacfdb54ef1acfd217af2614.
// Change: implemented window_close, window_setFrame and window_coverScreen on GTK.
// Modification notice per Apache-2.0 section 4(b); see ../MODIFICATIONS.md.

#include "flutter_window.h"
#include "../display_selection.h"

#include <cstring>
#include <iostream>

namespace {

bool ReadExternalArgument(FlValue* arguments) {
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    return true;
  }
  FlValue* external = fl_value_lookup_string(arguments, "external");
  if (external == nullptr ||
      fl_value_get_type(external) != FL_VALUE_TYPE_BOOL) {
    return true;
  }
  return fl_value_get_bool(external);
}

gboolean CloseWindowOnIdle(gpointer data) {
  GtkWidget* window = GTK_WIDGET(data);
  gtk_widget_destroy(window);
  g_object_unref(window);
  return G_SOURCE_REMOVE;
}

}  // namespace

FlutterWindow::FlutterWindow(const std::string& id,
                             const std::string& argument,
                             GtkWidget* window)
    : id_(id), window_argument_(argument), window_(window) {}

FlutterWindow::~FlutterWindow() = default;

void FlutterWindow::SetChannel(FlMethodChannel* channel) {
  channel_ = channel;
}

void FlutterWindow::NotifyWindowEvent(const gchar* event, FlValue* data) {
  if (channel_) {
    fl_method_channel_invoke_method(channel_, event, data, nullptr, nullptr, nullptr);
  }
}

void FlutterWindow::Show() {
  if (window_) {
    gtk_widget_show(GTK_WIDGET(window_));
  }
}

void FlutterWindow::Hide() {
  if (window_) {
    gtk_widget_hide(GTK_WIDGET(window_));
  }
}

void FlutterWindow::HandleWindowMethod(const gchar* method,
                                       FlValue* arguments,
                                       FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "window_show") == 0) {
    Show();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "window_hide") == 0) {
    Hide();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "window_close") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    if (window_) {
      g_idle_add(CloseWindowOnIdle, g_object_ref(window_));
    }
    } else if (strcmp(method, "window_setFrame") == 0) {
      if (!window_) {
        response = FL_METHOD_RESPONSE(
            fl_method_error_response_new("-1", "window is not available",
                                       nullptr));
      } else {
        FlValue* x_val = fl_value_lookup_string(arguments, "x");
        FlValue* y_val = fl_value_lookup_string(arguments, "y");
        FlValue* w_val = fl_value_lookup_string(arguments, "width");
        FlValue* h_val = fl_value_lookup_string(arguments, "height");
        if (x_val == nullptr || y_val == nullptr || w_val == nullptr ||
            h_val == nullptr) {
          response = FL_METHOD_RESPONSE(
              fl_method_error_response_new("-1", "missing frame arguments",
                                         nullptr));
        } else {
          gtk_window_resize(GTK_WINDOW(window_),
                            fl_value_get_int(w_val),
                            fl_value_get_int(h_val));
          gtk_window_move(GTK_WINDOW(window_), fl_value_get_int(x_val),
                          fl_value_get_int(y_val));
          response =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        }
      }
    } else if (strcmp(method, "window_cancelDisplayMove") == 0) {
      // GTK moves finish synchronously on this UI thread.
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (strcmp(method, "window_coverScreen") == 0 ||
             strcmp(method, "window_moveToDisplay") == 0) {
    const bool moving = strcmp(method, "window_moveToDisplay") == 0;
    if (!window_) {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("-1", "window is not available",
                                       nullptr));
    } else {
      GtkWindow* window = GTK_WINDOW(window_);
      GdkScreen* screen = gtk_window_get_screen(window);
      GdkDisplay* display = gdk_screen_get_display(screen);
      GdkWindow* gdk_window = gtk_widget_get_window(window_);
      const gint monitor_count = gdk_display_get_n_monitors(display);
      // gtk_window_fullscreen_on_monitor still takes an index, so map the
      // GdkMonitor back to its position on the display.
      GdkMonitor* current = gdk_window
                                ? gdk_display_get_monitor_at_window(display,
                                                                    gdk_window)
                                : gdk_display_get_primary_monitor(display);
      gint current_monitor = 0;
      if (current != nullptr) {
        for (gint i = 0; i < monitor_count; ++i) {
          if (gdk_display_get_monitor(display, i) == current) {
            current_monitor = i;
            break;
          }
        }
      }

      // Prefer the screen the presenter is NOT on, when told which one that is
      // (index in gdk_display monitor order). The `external` heuristic below
      // picks the non-primary screen, which is only right when the presenter
      // sits on the primary screen; in a reversed setup it would pile both
      // windows on the external display (#1913).
      FlValue* presenter_screen =
          arguments ? fl_value_lookup_string(arguments, "presenterScreen")
                    : nullptr;
      const bool presenter_given =
          presenter_screen != nullptr &&
          fl_value_get_type(presenter_screen) == FL_VALUE_TYPE_INT;

      // Every caller asks for the screen the presenter is NOT on. With one
      // monitor left — the beamer unplugged between the Dart-side display
      // check and this call — covering would take over the presenter's own
      // screen; refuse so Dart can fall back to single-screen (#3162).
      if (monitor_count < 2 &&
          (ReadExternalArgument(arguments) || presenter_given)) {
        response = FL_METHOD_RESPONSE(
            fl_method_error_response_new("-1", "no other display available",
                                         nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }

      gint target_monitor = current_monitor;
      FlValue* presenter_id = arguments ? fl_value_lookup_string(arguments, "presenterDisplay") : nullptr;
      FlValue* target_id = arguments ? fl_value_lookup_string(arguments, "targetDisplay") : nullptr;
      const bool identity_given = presenter_id != nullptr || target_id != nullptr;
      if (identity_given) {
        std::vector<std::string> identities;
        for (gint i = 0; i < monitor_count; ++i) {
          auto* monitor = gdk_display_get_monitor(display, i);
          identities.push_back(std::to_string(reinterpret_cast<guintptr>(monitor)));
        }
        target_monitor = presenter_id && target_id &&
            fl_value_get_type(presenter_id) == FL_VALUE_TYPE_STRING &&
            fl_value_get_type(target_id) == FL_VALUE_TYPE_STRING
            ? FindAudienceDisplay(identities, fl_value_get_string(presenter_id), fl_value_get_string(target_id)) : -1;
      }
      if ((moving && !identity_given) || (identity_given && target_monitor < 0) ||
          (presenter_given && (fl_value_get_int(presenter_screen) < 0 ||
                              fl_value_get_int(presenter_screen) >= monitor_count))) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "-1", "display snapshot is stale", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }

      if (!identity_given && presenter_given && monitor_count > 1) {
        gint presenter = fl_value_get_int(presenter_screen);
        if (presenter >= 0 && presenter < monitor_count) {
          for (gint i = 0; i < monitor_count; ++i) {
            if (i != presenter) {
              target_monitor = i;
              break;
            }
          }
        }
      } else if (!identity_given && ReadExternalArgument(arguments) && monitor_count > 1) {
        for (gint i = 0; i < monitor_count; ++i) {
          if (i != current_monitor) {
            target_monitor = i;
            break;
          }
        }
      }

      // A monitor can disappear between enumeration and this call (dock or
      // cable pulled mid-presentation). gdk_monitor_get_geometry on a null
      // monitor leaves bounds undefined; refuse instead of feeding that to
      // fullscreen_on_monitor.
      GdkMonitor* target =
          gdk_display_get_monitor(display, target_monitor);
      if (target == nullptr || (identity_given &&
          std::to_string(reinterpret_cast<guintptr>(target)) != fl_value_get_string(target_id))) {
        response = FL_METHOD_RESPONSE(
            fl_method_error_response_new("-1", "display no longer available",
                                         nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      GdkRectangle bounds;
      gdk_monitor_get_geometry(target, &bounds);
      if (bounds.width <= 0 || bounds.height <= 0) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "-1", "invalid display bounds", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      gtk_window_unfullscreen(window);
      if (!moving) gtk_window_set_decorated(window, FALSE);
      gtk_window_move(window, bounds.x, bounds.y);
      gtk_window_resize(window, bounds.width, bounds.height);
      gtk_window_fullscreen_on_monitor(window, screen, target_monitor);
      gtk_widget_show(window_);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else {
    g_autofree gchar* error_msg = g_strdup_printf("unknown method: %s", method);
    response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("-1", error_msg, nullptr));
  }

  fl_method_call_respond(method_call, response, nullptr);
}
