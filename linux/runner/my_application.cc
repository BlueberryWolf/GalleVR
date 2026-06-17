#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char **dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication *self, FlView *view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Called when window state (like minimized/restored) changes.
static gboolean on_window_state_event(GtkWidget *widget,
                                      GdkEventWindowState *event,
                                      gpointer user_data) {
  FlView *view = FL_VIEW(user_data);

  if (event->changed_mask & GDK_WINDOW_STATE_ICONIFIED) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    FlEngine *engine = fl_view_get_engine(view);
    g_autoptr(FlMethodChannel) channel =
        fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                              "gallevr/window", FL_METHOD_CODEC(codec));

    if (event->new_window_state & GDK_WINDOW_STATE_ICONIFIED) {
      // Hide widget and notify Dart
      gtk_widget_hide(GTK_WIDGET(view));
      fl_method_channel_invoke_method(channel, "onWindowMinimized", nullptr,
                                      nullptr, nullptr, nullptr);
    } else {
      // Show widget and notify Dart
      gtk_widget_show(GTK_WIDGET(view));
      fl_method_channel_invoke_method(channel, "onWindowRestored", nullptr,
                                      nullptr, nullptr, nullptr);
    }
  }
  return FALSE; // Propagate the event
}

// Implements GApplication::activate.
static void my_application_activate(GApplication *application) {
  MyApplication *self = MY_APPLICATION(application);
  GtkWindow *window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use GTK HeaderBar (CSD) only when running under GNOME or Unity.
  // These DEs expect client-side decorations and have no SSD window manager.
  // All other WMs/compositors (KDE Plasma, i3, Sway, Xfce, etc.) provide their
  // own server-side decorations and look wrong with a GTK HeaderBar on top.
  gboolean use_header_bar = FALSE;

  // Check the current desktop environment via standard env vars first,
  // since this works on both X11 and Wayland.
  const gchar *xdg_desktop = g_getenv("XDG_CURRENT_DESKTOP");
  const gchar *gdmsession = g_getenv("GDMSESSION");
  const gchar *desktop_session = g_getenv("DESKTOP_SESSION");

  if (xdg_desktop != nullptr) {
    // XDG_CURRENT_DESKTOP can be a colon-separated list (e.g. "GNOME:gnome")
    if (g_strstr_len(xdg_desktop, -1, "GNOME") != nullptr ||
        g_strstr_len(xdg_desktop, -1, "Unity") != nullptr) {
      use_header_bar = TRUE;
    }
  } else if (gdmsession != nullptr &&
             (g_str_has_prefix(gdmsession, "gnome") ||
              g_str_has_prefix(gdmsession, "ubuntu"))) {
    use_header_bar = TRUE;
  } else if (desktop_session != nullptr &&
             (g_str_has_prefix(desktop_session, "gnome") ||
              g_str_has_prefix(desktop_session, "ubuntu"))) {
    use_header_bar = TRUE;
  }

#ifdef GDK_WINDOWING_X11
  // On X11, also check the actual WM name as a fallback.
  if (!use_header_bar) {
    GdkScreen *screen = gtk_window_get_screen(window);
    if (GDK_IS_X11_SCREEN(screen)) {
      const gchar *wm_name = gdk_x11_screen_get_window_manager_name(screen);
      if (g_strcmp0(wm_name, "GNOME Shell") == 0) {
        use_header_bar = TRUE;
      }
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar *header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "GalleVR");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "GalleVR");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // Set window icon
  g_autofree gchar *exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path) {
    g_autofree gchar *exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar *icon_path =
        g_build_filename(exe_dir, "data", "flutter_assets", "assets", "images",
                         "app_icon_32.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      g_message("Setting window icon to: %s", icon_path);
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
      gtk_window_set_default_icon_from_file(icon_path, nullptr);
    } else {
      g_warning("Window icon not found at: %s", icon_path);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView *view = fl_view_new(project);
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

  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(on_window_state_event), view);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication *application,
                                                  gchar ***arguments,
                                                  int *exit_status) {
  MyApplication *self = MY_APPLICATION(application);
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
static void my_application_startup(GApplication *application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication *application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject *object) {
  MyApplication *self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass *klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication *self) {}

MyApplication *my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("GalleVR");

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
