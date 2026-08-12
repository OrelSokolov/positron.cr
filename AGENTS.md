# CrystalUI — Agent Notes

## What this is

CrystalUI is a **Linux-only reference implementation** of the Host-Shim
pattern described in `crystal-ui-architecture.md`. Crystal owns all state
and logic; the native shim (GTK/WebKitGTK) is a passive adapter.

## Build & Test

```bash
# Build all examples (writes logs to logs/)
rake build:examples

# Run the test suite (headless, no GUI required)
rake spec

# Build a single example
crystal build examples/hello/hello.cr -o examples/hello/hello
```

All 8 examples must build cleanly and all specs must pass before a change
is considered done.

## Requirements

- Crystal >= 1.10
- GTK 3, WebKitGTK 4.1, Ayatana AppIndicator 3 dev files
- libnotify (for the notifications plugin)

## Project layout

```
src/crystal_ui/
  event_bus.cr          # internal pub/sub (fibers per handler)
  command_registry.cr   # JSON command dispatch + @[Command] macro
  state_manager.cr      # observable host state
  plugin.cr             # base plugin + PluginManager
  host.cr               # abstract host (shared dispatch/bind logic)
  desktop_host.cr       # Linux desktop wiring (WebView + tray + loop)
  application.cr        # base class for user apps
  js_facade_generator.cr # generates CrystalUI.* JS runtime
  event_loop/linux.cr   # GTK main loop + Crystal fiber integration
  adapters/linux/       # WebKitGTK, AppIndicator, icon
  plugins/              # clipboard, display, file_picker, keyboard,
                        # logger, notifications, preferences,
                        # save_file_dialog, theme
spec/                   # headless specs for core components
examples/               # demo apps (each has frontend/ HTML/CSS/JS)
```

## Conventions

- **Linux is the only working platform.** Windows, macOS, Android, iOS
  adapters exist as stubs — do not assume they work.
- Plugins expose a `manifest` (for JS facade generation) and a `bind`
  method (for command registration). Both must stay in sync.
- `Plugin#on_ready(host)` is called by `DesktopHost#run` after the app's
  `on_ready`. Use it for adapter callbacks (e.g. notification clicks).
- The JS bridge envelope: `{"type":"command","id","name","args"}`.
  Responses go back via `window.__crystalResolve(id, success, data, error)`.
- Examples use `embed_application_files(__DIR__, icon_path)` to bake
  HTML/CSS/JS and the icon into the binary at compile time.

## Known gaps (by design, not bugs)

- No CLI (`crystal-ui init/build` from the architecture doc).
- No mobile entry points (`src/crystal_ui/entry/`).
- Non-Linux adapters are stubs.
- Many Top-20 plugins are not yet implemented (see `top_20.txt`).
