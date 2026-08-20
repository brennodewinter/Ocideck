#include "my_application.h"

#include <string.h>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // The clipboard write path: the pasteboard package has no Linux branch for
  // writeImage, so the Dart side calls this channel instead (issue #758).
  FlMethodChannel* clipboard_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void set_window_icon(GtkWindow* window) {
  gtk_window_set_default_icon_name(APPLICATION_ID);

  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) {
    return;
  }

  g_autofree gchar* executable_dir = g_path_get_dirname(executable_path);
  g_autofree gchar* icon_path =
      g_build_filename(executable_dir, "data", "icons", "app_icon.png", nullptr);
  gtk_window_set_icon_from_file(window, icon_path, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Puts encoded image bytes (PNG/JPEG/…) on the GTK clipboard as a pixbuf.
// Returns whether the bytes decoded to an image and were handed to GTK; a
// false result is what the Dart side reports to the user as a failed copy.
static gboolean write_image_to_clipboard(const uint8_t* bytes, size_t length) {
  GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
  gboolean decoded = gdk_pixbuf_loader_write(loader, bytes, length, nullptr);
  // Always close the loader: required before reading the pixbuf, and it
  // releases the decoder state on the failure path too.
  decoded = gdk_pixbuf_loader_close(loader, nullptr) && decoded;
  GdkPixbuf* pixbuf =
      decoded ? gdk_pixbuf_loader_get_pixbuf(loader) : nullptr;
  if (pixbuf != nullptr) {
    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_image(clipboard, pixbuf);
    // Ask the clipboard manager (if any) to keep the content after exit.
    gtk_clipboard_store(clipboard);
  }
  g_object_unref(loader);
  return pixbuf != nullptr;
}

// Zet klembordinhoud naar UTF-8. Chromium op Linux levert text/html soms
// als UTF-16 (met of zonder BOM); de Dart-kant verwacht een gewone string.
static gchar* selection_to_utf8(const guchar* data, gint length) {
  if (data == nullptr || length <= 0) {
    return nullptr;
  }
  if (length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
    return g_utf16_to_utf8(reinterpret_cast<const gunichar2*>(data + 2),
                           (length - 2) / 2, nullptr, nullptr, nullptr);
  }
  if (length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
    const gint units = (length - 2) / 2;
    g_autofree gunichar2* swapped = static_cast<gunichar2*>(
        g_malloc(static_cast<gsize>(units) * sizeof(gunichar2)));
    const guchar* src = data + 2;
    for (gint i = 0; i < units; i++) {
      swapped[i] = static_cast<gunichar2>((src[2 * i] << 8) | src[2 * i + 1]);
    }
    return g_utf16_to_utf8(swapped, units, nullptr, nullptr, nullptr);
  }
  return g_strndup(reinterpret_cast<const gchar*>(data),
                   static_cast<gsize>(length));
}

// HTML-variant van het GTK-klembord. Het pasteboard-pakket leest die op
// Linux niet; webeditors zetten de neststructuur hier neer (#1595).
static gchar* read_html_from_clipboard() {
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  const char* atoms[] = {"text/html", "TEXT/HTML"};
  for (gsize i = 0; i < G_N_ELEMENTS(atoms); i++) {
    GdkAtom atom = gdk_atom_intern(atoms[i], FALSE);
    GtkSelectionData* sel = gtk_clipboard_wait_for_contents(clipboard, atom);
    if (sel == nullptr) {
      continue;
    }
    const guchar* data = gtk_selection_data_get_data(sel);
    const gint length = gtk_selection_data_get_length(sel);
    gchar* out = selection_to_utf8(data, length);
    gtk_selection_data_free(sel);
    if (out != nullptr && out[0] != '\0') {
      return out;
    }
    g_free(out);
  }
  return nullptr;
}

// Handles calls on the ocideck/clipboard channel (see ImageService in Dart).
static void clipboard_method_call_cb(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "writeImage") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_UINT8_LIST) {
      gboolean ok = write_image_to_clipboard(fl_value_get_uint8_list(args),
                                             fl_value_get_length(args));
      g_autoptr(FlValue) result = fl_value_new_bool(ok);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad-args", "writeImage expects a byte list", nullptr));
    }
  } else if (strcmp(fl_method_call_get_name(method_call), "html") == 0) {
    g_autofree gchar* html = read_html_from_clipboard();
    g_autoptr(FlValue) result =
        html != nullptr ? fl_value_new_string(html) : fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  set_window_icon(window);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "ocideck");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "ocideck");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) { fl_register_plugins(registry); });

  // The channel lives on the struct so it survives this scope; disposed with
  // the application.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->clipboard_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "ocideck/clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->clipboard_channel, clipboard_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->clipboard_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
