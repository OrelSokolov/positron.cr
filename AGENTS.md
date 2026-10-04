# Positron — Agent Notes

## What this is

Positron is a **cross-platform UI framework for JS + CSS apps with a
Crystal backend** — "Electron on Crystal": OS WebView instead of a bundled
Chromium (see `README.md`). The frontend
runs in the OS WebView; Crystal owns all state and logic; the native
shim (GTK/WebKitGTK on Linux) is a passive adapter. Assets embed at
compile time into a single binary.

Currently a **Linux + macOS (arm64) + Windows reference implementation**
of the Host-Shim pattern described in `positron-architecture.md`: Linux
uses GTK/WebKitGTK, macOS uses WKWebView/NSWindow/NSStatusItem through a
pure-Crystal Objective-C runtime layer (`adapters/macos/objc.cr` — see the
header comment there for the dispatch-strategy constraints of Crystal's
one-declaration-per-C-symbol rule), Windows uses WebView2 via the
vendored `webview.dll` (`adapters/windows/`). The macOS plugin adapters
(clipboard etc.) are still stubs except notifications (M5.3 in
`ROADMAP.md`).
`README.md` carries a status checklist (done vs missing) — keep it in sync
with the actual state when features land.

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
the binaries into `builds/<target>/`. On a Windows host `crosspack build`
runs the `windows` matrix entry with the real M5.2 adapters (the
GTK/WebKitGTK host deps verify as satisfied — they are Linux-only).
`crosspack pack` packages the built artifacts per the `package:` section:
an MSI via WiX on Windows (`wix` from `dotnet tool install -g wix`),
deb/rpm on Linux. Keep the `version:` in `crosspack.yml` in sync
with `shard.yml`.

All 8 examples must build cleanly and all specs must pass before a change
is considered done.

CI (`.github/workflows/ci.yml`) runs `crystal spec` and builds all examples
on Ubuntu, macOS and Windows runners. The macOS job builds the **real**
WKWebView/NSStatusItem adapters (pure-Crystal ObjC runtime layer, system
frameworks — no extra installs beyond `openssl@3` for secure_storage); the
Windows job builds the **real** M5.2 adapters (webview.dll is vendored
in-repo; SQLite links the SDK's winsqlite3 import lib; secure_storage
uses the OpenSSL DLLs bundled with Crystal). Plugin factories gate
platform requires by target flags so Linux C libraries never leak into
non-Linux link lines. Platform-specific specs (unix sockets, SQLite FFI)
are flag-gated.

## Requirements

- Crystal >= 1.10
- Linux: GTK 3, WebKitGTK 4.1, Ayatana AppIndicator 3 dev files,
  libnotify (notifications plugin), libsqlite3 dev files (opt-in SQLite
  plugin), rsvg-convert or ImageMagick + appimagetool (packaging)
- macOS: Xcode command line tools (includes `codesign`, used by
  `positron package` — ad-hoc by default, `MACOS_SIGN_IDENTITY` for a
  real certificate); the adapters use the system
  AppKit/WebKit frameworks through the pure-Crystal ObjC runtime layer
  (no bindings shard). secure_storage needs OpenSSL
  (`brew install openssl@3`)
- Windows: the Microsoft Edge WebView2 runtime (preinstalled on Win10/11)
  and the vendored `third_party/webview/webview.dll` (shipped next to the
  exe by `crosspack build`); Win10+ for the deep-links AF_UNIX handshake;
  the opt-in SQLite plugin links the system `winsqlite3.dll` (import
  library comes with the Windows SDK — no vendoring needed)

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
  event_loop/macos.cr   # NSApp run loop + CFRunLoopTimer fiber tick
  event_loop/windows.cr # Win32 message pump + WM_TIMER fiber tick
  adapters/linux/       # WebKitGTK (window API, devtools, drag&drop),
                        # AppIndicator, icon
  adapters/macos/       # WKWebView/NSWindow/NSStatusItem + the pure-
                        # Crystal ObjC runtime layer (objc.cr)
  adapters/windows/     # WebView2 via vendored webview.dll, Win32,
                        # tray, WebResourceRequested COM interception
  plugins/              # clipboard, deep_links, dialogs, display,
                        # file_picker, filesystem, keyboard, lifecycle,
                        # logger, notifications, permissions,
                        # save_file_dialog, secure_storage, sqlite
                        # (opt-in), theme, window
spec/                   # headless specs for core components
examples/               # demo apps (each has frontend/ HTML/CSS/JS)
```

## Conventions

- **Linux, macOS (arm64) and Windows are the working platforms.** Linux
  is the reference platform. macOS: real WKWebView/NSWindow/NSStatusItem
  adapters (M5.1) — the macOS *plugin* adapters (clipboard, dialogs, …)
  are stubs except notifications (real `UNUserNotificationCenter` port —
  see the header of `plugins/notifications/macos.cr`; bare dev binaries
  fall back to `osascript display notification` automatically), do not assume
  the rest work. Windows (M5.2 stage 1:
  WebView2 window + JS bridge + event loop + tray + theme via the
  vendored `third_party/webview/webview.dll`, loaded at runtime — keep
  the DLL next to the exe or under `third_party/webview/`; stage 2:
  clipboard, dialogs, file picker, save dialog, notifications, display,
  preferences adapters; stage 3: POSIX-neutral plugins fixed — fs dirs
  (`APPDATA`/`LOCALAPPDATA`), deep_links single instance over AF_UNIX,
  secure_storage under `%APPDATA%`, SQLite via the system
  `winsqlite3.dll`).
- **Platform code stays behind ports.** Any GTK/WebKit call belongs in
  `src/positron/adapters/linux/`, `src/positron/event_loop/linux.cr` or
  `src/positron/plugins/*/linux.cr`. Any AppKit/WebKit/ObjC call belongs
  in `src/positron/adapters/macos/`, `src/positron/event_loop/macos.cr`
  or `src/positron/plugins/*/macos.cr`. Any Win32/WebView2 call belongs
  in `src/positron/adapters/windows/`,
  `src/positron/event_loop/windows.cr` or
  `src/positron/plugins/*/windows.cr`. Core files must stay
  platform-pure — future ports (M5.3, mobile) depend on that.
- macOS ObjC bindings rules (`adapters/macos/objc.cr`): Crystal allows one
  `fun` declaration per C symbol program-wide, so there is exactly one
  fixed-arity `objc_msgSend` shape — go through `ObjC.send*` helpers,
  `ObjC.invoke_rect3` (NSRect-by-value), `ObjC.send_size` (NSSize-by-value)
  or `ObjC::Call` (NSInvocation: float args, 4+ args, struct returns).
  Never hand-roll another `objc_msgSend` declaration. NSInvocation cannot
  pass HFA struct *arguments* on arm64 — keep that in mind for new calls.
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

- Windows: custom URI schemes are served over a virtual https host
  (`app://x` → `https://app.positron.local/x` via WebView2's
  WebResourceRequested interception); absolute `app://` URLs inside
  frontend assets do not resolve — use relative paths (the adapter
  rewrites `load_url`). Devtools via the window API raise
  (F12 works when running with `POSITRON_DEV=1`). Deep-link scheme
  *registration* (registry keys) is a packaging concern on Windows,
  like `.desktop` on Linux.
- macOS plugin adapters (clipboard, dialogs, …) are stubs — port with
  M5.3 (notifications is done). No `dnd.files` on macOS: WKWebView
  consumes file drops with no public hook.
- No mobile entry points (`src/positron/entry/`).
- Multi-window is intentionally out of scope.
- Many Tier-2+ plugins from `plugins.txt` are not yet implemented.
