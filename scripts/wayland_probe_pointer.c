/* Keep a wlroots virtual pointer attached to the private test compositor. */
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>

static const struct wl_interface pointer_interface = {
    "zwlr_virtual_pointer_v1", 1, 0, NULL, 0, NULL,
};
static const struct wl_interface *create_types[] = {
    &wl_seat_interface, &pointer_interface,
};
static const struct wl_message manager_requests[] = {
    {"create_virtual_pointer", "?on", create_types},
};
static const struct wl_interface manager_interface = {
    "zwlr_virtual_pointer_manager_v1", 1, 1, manager_requests, 0, NULL,
};

static void bind_global(void *data, struct wl_registry *registry, uint32_t id,
                        const char *name, uint32_t version) {
  struct wl_proxy **manager = data;
  if (!*manager && version >= 1 && !strcmp(name, manager_interface.name)) {
    *manager = wl_registry_bind(registry, id, &manager_interface, 1);
  }
}

static void remove_global(void *data, struct wl_registry *registry, uint32_t id) {
  (void)data;
  (void)registry;
  (void)id;
}

int main(void) {
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) {
    fputs("Could not connect a virtual pointer to the test compositor\n", stderr);
    return 1;
  }
  struct wl_proxy *manager = NULL;
  struct wl_registry *registry = wl_display_get_registry(display);
  const struct wl_registry_listener listener = {
      .global = bind_global,
      .global_remove = remove_global,
  };
  wl_registry_add_listener(registry, &listener, &manager);
  if (wl_display_roundtrip(display) < 0 || !manager) {
    fputs("The test compositor did not advertise a virtual pointer manager\n", stderr);
    wl_display_disconnect(display);
    return 1;
  }
  struct wl_proxy *pointer = wl_proxy_marshal_flags(
      manager, 0, &pointer_interface, 1, 0, NULL, NULL);
  if (!pointer || wl_display_roundtrip(display) < 0) {
    fputs("The test compositor could not attach the virtual pointer\n", stderr);
    wl_display_disconnect(display);
    return 1;
  }
  while (wl_display_dispatch(display) >= 0) {
  }
  wl_display_disconnect(display);
  return 0;
}
