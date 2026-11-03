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
int crystal_main_entry(int argc, char **argv);

// Forwarded to Positron::EventLoop::IOS through the LibShim externs:
// UIApplicationMain wants the real argc/argv, not NULL.
int g_positron_argc = 0;
char **g_positron_argv = 0;

int main(int argc, char *argv[]) {
  g_positron_argc = argc;
  g_positron_argv = argv;
  return crystal_main_entry(argc, argv);
}
