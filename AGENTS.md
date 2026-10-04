# Positron — Agent Notes

## What this is

Positron is a **cross-platform UI framework for JS + CSS apps with a
Crystal backend** — "Electron on Crystal": OS WebView instead of a bundled
Chromium (see `README.md`). The frontend
runs in the OS WebView; Crystal owns all state and logic; the native
shim (GTK/WebKitGTK on Linux) is a passive adapter. Assets embed at
compile time into a single binary.

Currently a **Linux-only reference implementation** of the Host-Shim
pattern described in `positron-architecture.md`: macOS/Windows adapters
are stubs (M5 in `ROADMAP.md`). `README.md` carries a status checklist
(done vs missing) — keep it in sync with the actual state when features
land.

## Build & Test

```bash
# Build all examples (writes logs to logs/)
rake build:examples

# Run the test suite (headless, no GUI required)
rake spec

# Build the positron CLI into bin/
rake build:cli

# Build a single example
crystal build examples/hello/hello.cr -o examples/hello/hello
```

Build orchestration lives in `crosspack.yml` (the [crosspack](https://rubygems.org/gems/crosspack)
gem, Ruby >= 3.2): `crosspack deps` verifies/installs the build-host
dependencies, `crosspack build` runs specs + CLI + all examples and fans
the binaries into `builds/<target>/`. There is intentionally **no
`package:` section** — Positron is a library, not an end product; packing
belongs to applications. Keep the `version:` in `crosspack.yml` in sync
with `shard.yml`.

All 8 examples must build cleanly and all specs must pass before a change
is considered done.

CI (`.github/workflows/ci.yml`) runs `crystal spec` and builds all examples
on Ubuntu, macOS and Windows runners. Non-Linux jobs build against the
adapter stubs; plugin factories gate platform requires by target flags so
Linux C libraries never leak into non-Linux link lines. Platform-specific
specs (unix sockets, SQLite FFI) are flag-gated.

## Requirements

- Crystal >= 1.10
- GTK 3, WebKitGTK 4.1, Ayatana AppIndicator 3 dev files
- libnotify (for the notifications plugin)
- libsqlite3 dev files (only for the opt-in SQLite plugin)
- rsvg-convert or ImageMagick, appimagetool (only for `positron package`)

## Project layout

```
src/positron/
  event_bus.cr          # internal pub/sub (fibers per handler)
  command_registry.cr   # JSON command dispatch + @[Command] macro
  state_manager.cr      # observable host state
  plugin.cr             # base plugin + PluginManager
  host.cr               # abstract host (shared dispatch/bind logic)
  desktop_host.cr       # Linux desktop wiring (WebView + tray + loop)
  application.cr        # base class for user apps
  embed_directory.cr    # compile-time helper for Application#embed_directory
  js_facade_generator.cr # generates Positron.* JS runtime
  bindings_generator.cr # generates positron.d.ts from manifests
  dev/asset_server.cr   # dev-mode HTTP server + live reload
  packaging.cr          # .desktop / icons / AppDir / deb helpers
  cli.cr                # positron init/dev/build/doctor/package
  event_loop/linux.cr   # GTK main loop + Crystal fiber integration
  adapters/linux/       # WebKitGTK (window API, devtools, drag&drop),
                        # AppIndicator, icon
  plugins/              # clipboard, deep_links, dialogs, display,
                        # file_picker, filesystem, keyboard, lifecycle,
                        # logger, notifications, permissions,
                        # save_file_dialog, secure_storage, sqlite
                        # (opt-in), theme, window
spec/                   # headless specs for core components
examples/               # demo apps (each has frontend/ HTML/CSS/JS)
```

## Conventions

- **Linux is the only working platform.** Windows, macOS, Android, iOS
  adapters exist as stubs — do not assume they work.
- **Platform code stays behind ports.** Any GTK/WebKit/native call
  belongs in `src/positron/adapters/linux/`,
  `src/positron/event_loop/linux.cr` or `src/positron/plugins/*/linux.cr`.
  Core files must stay platform-pure — the macOS/Windows port (M5 in
  `ROADMAP.md`) depends on that.
- Plugins expose a `manifest` (for JS facade / TypeScript bindings
  generation) and a `bind` method (for command registration). Both must
  stay in sync.
- `Plugin#on_ready(host)` is called by `DesktopHost#run` after the app's
  `on_ready`. Use it for adapter callbacks (e.g. notification clicks).
- The JS bridge envelope: `{"type":"command","id","name","args"}`.
  Responses go back via `window.__positronResolve(id, success, data, error)`.
- **Never hand-roll `eval_js` strings to push events to the frontend** —
  use `Host#emit_to_js(event, payload)`.
- Examples use `embed_application_files(__DIR__, icon_path)` to bake
  HTML/CSS/JS and the icon into the binary at compile time.
- `Application#embed_directory(dir)` bakes a whole tree (base64, binary-safe)
  — e.g. a built web app; `Application#embed_file(path)` bakes one file.
  Both take plain string literals (relative paths resolve from the
  compiler's working directory).
- `WebViewPort#register_uri_scheme(scheme) { |path| SchemeResponse? }` serves
  embedded trees from the host process (WebKitGTK: register_uri_scheme) —
  no local HTTP server needed. Call it before `create`.
- `WebViewConfig#close_to_tray` (default true): false makes the window close
  button quit the event loop instead of hiding to the tray.
- Dev mode: `Application#serve_directory(dir)` serves the frontend from
  disk with live reload; `POSITRON_DEV=1` switches one binary between
  served and embedded assets (this is what `positron dev` sets).

## Known gaps (by design, not bugs)

- No macOS/Windows adapters yet (M5 in `ROADMAP.md`) — stubs only.
- No mobile entry points (`src/positron/entry/`).
- Multi-window is intentionally out of scope.
- Many Tier-2+ plugins from `plugins.txt` are not yet implemented.
