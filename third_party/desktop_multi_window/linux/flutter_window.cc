#include "flutter_window.h"

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
    } else if (strcmp(method, "window_coverScreen") == 0) {
    if (!window_) {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("-1", "window is not available",
                                       nullptr));
    } else {
      GtkWindow* window = GTK_WINDOW(window_);
      GdkScreen* screen = gtk_window_get_screen(window);
      GdkWindow* gdk_window = gtk_widget_get_window(window_);
      const gint monitor_count = gdk_screen_get_n_monitors(screen);
      gint current_monitor = gdk_window
                                 ? gdk_screen_get_monitor_at_window(screen,
                                                                    gdk_window)
                                 : gdk_screen_get_primary_monitor(screen);
      if (current_monitor < 0) {
        current_monitor = 0;
      }

      gint target_monitor = current_monitor;
      if (ReadExternalArgument(arguments) && monitor_count > 1) {
        for (gint i = 0; i < monitor_count; ++i) {
          if (i != current_monitor) {
            target_monitor = i;
            break;
          }
        }
      }

      GdkRectangle bounds;
      gdk_screen_get_monitor_geometry(screen, target_monitor, &bounds);
      gtk_window_unfullscreen(window);
      gtk_window_set_decorated(window, FALSE);
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
