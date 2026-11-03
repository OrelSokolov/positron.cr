// iOS driver: Crystal owns the process entry.
//
// The iOS build is cross-compiled with a Crystal compiler patched for
// ios targets (see ios/build_ios.sh). Under `flag?(:ios)` the patched
// stdlib exposes the program entry as `crystal_main_entry` instead of
// `main` (see egui.cr tmp/crystal-ios, src/crystal/system/unix/main.cr),
// so the C driver owns main() and hands over to the Crystal runtime on
// the main thread — the same boot model as the egui.cr phase 3/4
// pipeline. UIApplicationMain is called later by
// Positron::EventLoop::IOS#run and never returns.

#include <mach-o/dyld.h>
#include <string.h>

int crystal_main_entry(int argc, char **argv);

// Forwarded to Positron::EventLoop::IOS through the LibShim externs:
// UIApplicationMain wants the real argc/argv, not NULL.
int g_positron_argc = 0;
char **g_positron_argv = 0;

// --- Boehm GC static-root filter -------------------------------------
//
// bdwgc registers the writable data of every dyld image as GC roots
// (dyn_load.c GC_dyld_image_add). UIKit soft-links many frameworks
// lazily (dlopen on first use), and every dlopen drags in hundreds of
// images; the accumulated root segments exhaust bdwgc's MAX_ROOT_SETS
// and abort the process with "Too many root sets" (seen as SIGABRT in
// GC_add_roots_inner <- GC_dyld_image_add when a WKWebView text
// selection menu loaded DataDetectorsUILibrary).
//
// No Crystal object can be referenced from a system framework's static
// data (the adapters keep the Crystal side of every ObjC callback in
// class variables of the main image), so only the main executable's
// own image is worth scanning. The filter below answers the GC's
// GC_has_static_roots callback accordingly and must be installed
// before the first allocation (i.e. before crystal_main_entry).

typedef int (*GC_has_static_roots_func)(const char *path, void *start,
                                        size_t size);
extern void GC_register_has_static_roots_callback(GC_has_static_roots_func);

static const char *g_app_image_path = 0;

static int positron_gc_root_filter(const char *path, void *start,
                                   size_t size) {
  (void)start;
  (void)size;
  // NULL path (image not found in the dyld list — should not happen):
  // stay conservative and accept.
  if (path == 0 || g_app_image_path == 0) return 1;
  return strcmp(path, g_app_image_path) == 0;
}

int main(int argc, char *argv[]) {
  g_positron_argc = argc;
  g_positron_argv = argv;

  // Index 0 of the dyld image list is always the main executable; use
  // its name (owned by dyld, stable for the process lifetime) so the
  // comparison sees exactly the same string the GC passes in.
  g_app_image_path = _dyld_get_image_name(0);
  GC_register_has_static_roots_callback(positron_gc_root_filter);

  return crystal_main_entry(argc, argv);
}
