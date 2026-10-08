#include "my_application.h"
#include <stdlib.h> // For setenv

int main(int argc, char** argv) {
  // Suppress aggressive GDBus pxbackend-WARNING spam on Linux snap environments
  // by forcing GLib to use the basic network monitor instead of the desktop portal.
  setenv("GIO_USE_NETWORK_MONITOR", "base", 1);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
