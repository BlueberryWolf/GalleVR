#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <malloc.h>
#include <cstring>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* window_channel;
  gboolean minimize_to_tray;
  gboolean is_hidden;
  guint trim_timer_id;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void notify_dart(MyApplication* self, const gchar* method) {
  if (self->window_channel != nullptr) {
    fl_method_channel_invoke_method(self->window_channel, method, nullptr,
                                    nullptr, nullptr, nullptr);
  }
}

static void cancel_memory_trim(MyApplication* self) {
  if (self->trim_timer_id != 0) {
    g_source_remove(self->trim_timer_id);
    self->trim_timer_id = 0;
  }
}

static gboolean memory_trim_timeout_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->trim_timer_id = 0;
  if (self->is_hidden) {
    malloc_trim(0);
  }
  return G_SOURCE_REMOVE;
}

static void schedule_memory_trim(MyApplication* self, guint delay_ms) {
  cancel_memory_trim(self);
  self->trim_timer_id =
      g_timeout_add(delay_ms, memory_trim_timeout_cb, self);
}

static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->is_hidden && self->window != nullptr) {
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_present(self->window);
  }
}

static void show_window(MyApplication* self) {
  cancel_memory_trim(self);
  self->is_hidden = FALSE;

  if (self->view != nullptr) {
    gtk_widget_show(GTK_WIDGET(self->view));
  }
  if (self->window != nullptr) {
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_deiconify(self->window);
    gtk_window_present(self->window);
  }
  if (self->view != nullptr) {
    gtk_widget_grab_focus(GTK_WIDGET(self->view));
  }
}

static void hide_to_tray(MyApplication* self, gboolean notify) {
  self->is_hidden = TRUE;
  if (self->window != nullptr) {
    gtk_widget_hide(GTK_WIDGET(self->window));
  }
  if (notify) {
    notify_dart(self, "onWindowHidden");
  }
  schedule_memory_trim(self, 350);
}

static gboolean on_delete_event(GtkWidget* widget,
                                GdkEvent* event,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->minimize_to_tray) {
    hide_to_tray(self, TRUE);
    return TRUE;
  }
  notify_dart(self, "onWindowCloseRequest");
  return TRUE;
}

static gboolean on_window_state_event(GtkWidget* widget,
                                      GdkEventWindowState* event,
                                      gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  if (event->changed_mask & GDK_WINDOW_STATE_ICONIFIED) {
    if (event->new_window_state & GDK_WINDOW_STATE_ICONIFIED) {
      if (!self->is_hidden) {
        self->is_hidden = TRUE;
        notify_dart(self, "onWindowMinimized");
        schedule_memory_trim(self, 350);
      }
    } else if (gtk_widget_get_visible(widget)) {
      cancel_memory_trim(self);
      if (self->is_hidden) {
        self->is_hidden = FALSE;
        notify_dart(self, "onWindowRestored");
      }
    }
  }
  return FALSE;
}

static void window_channel_method_call_cb(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (std::strcmp(method, "updateMinimizeToTray") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
      self->minimize_to_tray = fl_value_get_bool(args);
    } else {
      self->minimize_to_tray = TRUE;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (std::strcmp(method, "showWindow") == 0) {
    show_window(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (std::strcmp(method, "hideWindow") == 0) {
    hide_to_tray(self, FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (std::strcmp(method, "trimMemory") == 0) {
    malloc_trim(0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send window channel response: %s", error->message);
  }
}

static gboolean has_start_minimized_arg(char** args) {
  if (args == nullptr) {
    return FALSE;
  }
  for (int i = 0; args[i] != nullptr; ++i) {
    if (std::strcmp(args[i], "--start-minimized") == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  g_application_hold(application);

  gboolean use_header_bar = FALSE;

  const gchar* xdg_desktop = g_getenv("XDG_CURRENT_DESKTOP");
  const gchar* gdmsession = g_getenv("GDMSESSION");
  const gchar* desktop_session = g_getenv("DESKTOP_SESSION");

  if (xdg_desktop != nullptr) {
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
  if (!use_header_bar) {
    GdkScreen* screen = gtk_window_get_screen(window);
    if (GDK_IS_X11_SCREEN(screen)) {
      const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
      if (g_strcmp0(wm_name, "GNOME Shell") == 0) {
        use_header_bar = TRUE;
      }
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "GalleVR");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "GalleVR");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path =
        g_build_filename(exe_dir, "data", "flutter_assets", "assets", "images",
                         "app_icon_32.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
      gtk_window_set_default_icon_from_file(icon_path, nullptr);
    }
  }

  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(on_window_state_event), self);
  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete_event), self);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#050508");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "gallevr/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_channel_method_call_cb, self, nullptr);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);

  if (has_start_minimized_arg(self->dart_entrypoint_arguments)) {
    self->is_hidden = TRUE;
    gtk_widget_realize(GTK_WIDGET(window));
    gtk_widget_realize(GTK_WIDGET(view));
    schedule_memory_trim(self, 2500);
  } else {
    self->is_hidden = FALSE;
    gtk_widget_show(GTK_WIDGET(window));
    gtk_widget_grab_focus(GTK_WIDGET(view));
  }
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
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

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  cancel_memory_trim(self);
  g_clear_object(&self->window_channel);
  self->view = nullptr;
  self->window = nullptr;
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  cancel_memory_trim(self);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
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

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->view = nullptr;
  self->window_channel = nullptr;
  self->minimize_to_tray = TRUE;
  self->is_hidden = FALSE;
  self->trim_timer_id = 0;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("GalleVR");

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
