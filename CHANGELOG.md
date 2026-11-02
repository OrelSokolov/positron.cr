# Changelog

All notable changes to Positron are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] — 2026-11-03

### Added

- `Positron.async_work` DSL — the single rule for background work, used
  by the framework itself (`Host#dispatch` routes through it):
  - `Positron.async_work { ... }` — concurrent fiber (IO, subprocesses,
    waiting);
  - `Positron.parallel_work { ... }` — true parallelism on a
    `Fiber::ExecutionContext::Parallel` worker thread (Crystal >= 1.21;
    concurrent-fiber fallback on older toolchains); the result crosses
    as JSON, block errors arrive as `_parallel_error`;
  - `task.value` — await (parks the calling fiber, refuses to run on
    the GUI fiber — the "window froze" bug class);
  - `Positron.on_main { ... }` — touch the UI from any task.
- `Host.current` / `Host#gui_context?` — the plumbing behind the DSL's
  GUI-thread guard.
- `CommandRegistry#register(name, execution:)` — declarative execution
  context for command handlers: `:fiber` (default) or `:parallel`
  (handler body on a worker thread; UI access forbidden inside, a
  crashing handler becomes an error result). Plus instance-level
  `async_work`/`parallel_work`/`on_main` on `Positron::Application`.
- Virtual HTTP layer — resource routing without a server:
  - `Positron.http.{get,post,put,patch,delete}` on the JS side (fetch
    semantics: the promise always resolves with `{status, body}`) and
    opt-in `Positron.installFetch()` interception of relative paths;
  - `Positron::Router` on the Crystal side: block routes, `namespace`
    nesting, `:param` extraction with percent-decoding, query-string
    parsing, `heavy` groups;
  - `Positron::Controller` with the `actions` macro and Rails-style
    `resources` (index/show/create/update/destroy);
    `@[Positron::Heavy]` on an action auto-routes it to the Parallel
    worker pool at registration;
  - `Positron::Router.use` middleware chain (return a `Response` to
    short-circuit, `nil` to pass through);
  - handler exceptions become `{status: 500, body: {error}}`, unknown
    routes 404 — never a rejected promise.

### Fixed

- `Host#dispatch` executed the whole command handler inside the GLib
  idle callback — i.e. on the GUI thread — so even a yielding CPU burn
  froze the UI (`Fiber.yield` from inside an idle callback never
  returns control to GTK). Handlers now run in their dispatch fiber;
  only the promise resolve is marshalled to the GUI thread.
- `EventLoop::Linux#run_on_main` handed Boehm-GC box pointers to
  `g_idle_add`; the GC never scans GLib's idle queue, so boxes (and
  their captured command payloads) could be collected before the idle
  fired — lost promise resolves, garbage command strings, segfaults.
  GLib now receives only an integer id; the closure lives in a
  GC-scanned Hash until after it runs.
- The GTK adapter passed unrooted `Box.box(self)` pointers to
  `g_signal_connect_data` (same GC hazard, for the adapter's whole
  lifetime). All connects now share one memoized, ivar-rooted box.

### Added

- `examples/scheduler_demo`: demonstrates how CPU-bound work interacts
  with Crystal's cooperative scheduler — a naive 10 s loop freezes the
  whole host (the GTK loop included), periodic `Fiber.yield` keeps the
  UI alive, and a child-process burn is true parallelism (the pattern
  for blocking code you don't own). The frontend shows a host
  heartbeat age as the freeze indicator (JS timers live in the WebKit
  process and keep running while the host is blocked). Headless
  coverage in `spec/scheduler_demo_spec.cr` — the freeze claim runs in
  a clean subprocess because the spec framework itself adds fiber
  yield points that mask starvation.
- Frameless windows + CSS-drag (Wails `--wails-draggable` analogue):
  `WebViewConfig.frameless = true` creates an undecorated window and
  enables drag handles — elements (or their ancestors) with the
  `--positron-drag: drag` custom CSS property start a native window
  move on button press; double-click on a handle toggles maximize
  (`no-drag` stops the walk). The DOM hit-test runs synchronously
  through the JSC C API inside the GTK button-press handler, so the
  drag begins while the button is held. Linux/WebKitGTK only.
- Notification actions: `notifications.send(title, body, id?, actions?)`
  accepts `[{id, title}]` button pairs (libnotify on Linux); clicks
  arrive as `notification.action` {id, action} events (JS via
  `Positron.on`, Crystal via EventBus), the body click stays
  `notification.clicked` and now also reaches the JS side on Linux.
- Dev error overlay: every HTML page served by the dev asset server
  gets a script that catches `window.onerror` / `unhandledrejection`,
  renders a floating overlay and posts a `dev.error` bridge event; the
  host duplicates it to STDERR (`[positron] frontend error: …`).
  Release builds never see the script.
- `window.reload()` / `window.exec_js(script)` window-plugin commands
  (Wails `WindowReload` / `WindowExecJS` analogues) — implemented via
  `eval_js`, so they work on every platform without adapter support.
- Async command dispatch: `Host#dispatch` now runs every command
  handler in a Crystal fiber (the Wails/Tauri model), so slow commands
  never freeze the GUI thread; the promise resolve is marshalled back
  via `run_on_main`. The envelope is parsed once and the response
  serialized once — `CommandResult.raw_json` is used verbatim by
  `to_js_resolve` as the single-serialization fast path, and
  `CommandRegistry.parse` gained a `JSON::Any` overload to skip the
  string round-trip. `Host#dispatch_now` is the synchronous variant
  (tests/embedders); the EventBus `command.invoked` resolve is now
  correctly marshalled to the GUI thread.
- Close-veto hook (Wails `OnBeforeClose` analogue):
  `Application#on_before_close : Bool` is called on the GUI thread when
  the user requests window close; returning false keeps the window
  open. Wired by `DesktopHost` into the new `WebViewPort#before_close`
  callback (`#allow_close?`), consulted in all three platform close
  paths — WebKitGTK `delete-event`, WebView2 `WM_CLOSE`, macOS
  `windowShouldClose:`. Programmatic `Host#stop` never consults it.
  Headless coverage in `spec/close_veto_spec.cr`.
- All remaining macOS plugin adapter ports (M5.3), driven through the
  pure-Crystal ObjC runtime layer (`adapters/macos/objc.cr`):
  clipboard (`NSPasteboard` — text, PNG/TIFF image data, file URLs via
  `readObjectsForClasses:`; image writes go through an
  `NSPasteboardItem` with raw `setData:forType:` bytes), dialogs
  (`NSAlert` + an `NSTextField` accessory view for prompt, window
  title mapped from the `title` argument), file picker (`NSOpenPanel`,
  `accept` translated to extensions incl. common MIME types),
  save file dialog (`NSSavePanel`), display info (CoreGraphics online
  display list — logical bounds, current-mode pixel size for the scale
  factor, physical mm for DPI, y flipped to the top-left origin,
  refresh rate from the display mode) and theme (dark mode via
  `NSAppearance bestMatch`, accent color from
  `NSColor.controlAccentColor` converted to sRGB, high-contrast flag
  from `NSWorkspace`). ObjC layer gained `send1_i`/`send2_b` helpers,
  `ObjC::Call#ret_f64` (CGFloat returns) and `LibCF.CFRelease`.
  Verified on arm64 (text/image clipboard round-trip, theme accent
  `#007AFF`, Retina `scale_factor: 2.0`); specs for the file picker
  `accept` filter.
- macOS host support in `crosspack`: `darwin:` stub rules for the
  Linux-only GTK/WebKitGTK/AppIndicator/libnotify host deps (the macOS
  adapters use the system frameworks) and a `macos` matrix entry
  (darwin/arm64) in `crosspack build`, fanning the CLI and all example
  binaries into `builds/macos/` (debug `.dwarf` files stripped).
- Real macOS notifications adapter (first M5.3 plugin port):
  `UNUserNotificationCenter` driven through the pure-Crystal ObjC layer —
  permission request/check, send/clear by id, click callbacks via a
  dynamically registered delegate (banner|list|sound while frontmost).
  The async UN APIs take ObjC blocks, which the adapter builds by hand
  (global block literals with an NSBlock-subclass isa and no-op dealloc);
  completion handlers run on a background queue while the command fiber
  polls. macOS requires the host to run from a signed app bundle
  registered with Launch Services; a bare binary (dev mode) instead
  falls back to `osascript display notification` — banners work with no
  bundle or signature, permission checks report granted (no click
  callbacks or clear on that path). Verified end-to-end on arm64:
  bare dev binary → osascript banner; signed .app → permission prompt →
  Allow → native banner delivered.
- macOS `.app` packaging (`positron package` + `Packaging.build_app_bundle`):
  Info.plist rendering, bundle scaffolding and codesign (ad-hoc default,
  `MACOS_SIGN_IDENTITY` for a real certificate, `MACOS_BUNDLE_ID` for the
  bundle id; `--install` copies into /Applications). This is the supported
  way to get system notifications working — signing a bare binary is not
  enough, UNUserNotificationCenter validates the bundle identity through
  Launch Services.
- Windows host support in `crosspack`: a `windows` matrix entry (specs +
  CLI + all examples against the native adapters) and Windows host rules
  for the GTK build deps (the GUI stack is not linked on Windows).
- Real Windows adapters (M5.2 stage 1): WebView2 window via the vendored
  `webview.dll` 0.12.0 (`third_party/webview/`, loaded at runtime — no
  import library), Win32 message pump event loop with Crystal fiber
  integration (WM_TIMER cooperative tick, `run_on_main` via
  `webview_dispatch`), `Shell_NotifyIcon` tray with popup menu, window
  management (resize/min/max/fullscreen/topmost/frameless/center) with
  `window.*` events, close-to-tray via a subclassed WndProc, and the JS
  bridge through `webview_bind`/`webview_eval`. `hello`, `theme_demo` and
  the other examples now open real windows on Windows.
- Windows theme adapter: dark/light + accent color from the registry
  (`reg query`), replacing the "not yet implemented" stub warning.
- Windows M4 plugin adapters: clipboard (text/files/BMP images via
  CF_UNICODETEXT/CF_HDROP/CF_DIB, GDI+ for image writing), dialogs
  (MessageBoxW for alert/confirm, a native prompt window for input),
  file_picker and save_file_dialog (comdlg32 Get{Open,Save}FileNameW),
  notifications (Shell_NotifyIcon balloons with click-through), and
  display info (EnumDisplayMonitors, GetDpiForMonitor, physical size in
  mm). Verified headlessly: clipboard round-trip (UTF-8/Cyrillic),
  monitor enumeration (resolution/scale/Hz/mm) and theme/accent.
- Windows support for the platform-neutral plugins that still assumed
  POSIX: `fs` dirs (`USERPROFILE`/`APPDATA`/`LOCALAPPDATA` instead of
  `HOME`/XDG), `deep_links` single-instance handshake over AF_UNIX
  (Win10+) with the socket in `%LOCALAPPDATA%`, `secure_storage` store
  under `%APPDATA%`, and the opt-in SQLite plugin linking the system
  `winsqlite3.dll`. The previously unix-gated specs (deep_links,
  secure_storage, sqlite) now run on win32 too.
- `register_uri_scheme` on Windows: `app://x` is served from the host
  process over the virtual host `https://app.positron.local/x` using
  WebView2's WebResourceRequested interception (raw COM vtable calls
  from the browser-controller handle `webview_get_native_handle`
  exposes — see `adapters/windows/webview2_com.cr`). Navigations to
  registered schemes are rewritten and held back until the interception
  is installed; relative asset paths work as on Linux.
- Distribution via crosspack: a `package:` section in `crosspack.yml`
  — `crosspack pack` produces a WiX MSI on Windows (positron CLI +
  examples + runtime DLLs under Program Files, Start Menu/Desktop
  shortcuts) and deb/rpm payloads for Linux builds.
- CI: the Windows runner now builds the real M5.2 adapters (webview.dll
  vendored in-repo, winsqlite3 import lib from the SDK, OpenSSL DLLs
  bundled with Crystal) and the macOS runner builds the real
  WKWebView/NSStatusItem adapters, instead of the stubs.
- `crosspack build` on Windows fans `webview.dll` into the artifact tree.
- **macOS tray adapter rewritten to follow the reference implementation**
  in OrelSokolov/systray (`systray_darwin.m`, a getlantern/systray fork):
  the status item is explicitly `setVisible:` after creation (a
  user-⌘-drag-hidden item stays hidden otherwise), the item and its menu
  are retained (the event loop's per-tick autorelease pool drain would
  otherwise release the autoreleased item), icons are normalized to
  16×16 via `setSize:` (SVG sources keep their natural size, e.g.
  128×128, without it) and the button's `imagePosition` is kept explicit
  (NSImageOnly / NSImageLeft / NSNoImage) instead of relying on AppKit's
  default. Verified programmatically: visible item, 16×16 icon, correct
  imagePosition, 3-entry menu (item + separator + checkable).
- **macOS adapters (M5.1):** real WKWebView/NSWindow WebViewPort, NSStatusItem
  tray and NSApp event loop on top of a pure-Crystal Objective-C runtime
  layer (`src/positron/adapters/macos/objc.cr`) — no bindings shard. The
  layer works around Crystal's one-declaration-per-C-symbol rule with one
  fixed-arity `objc_msgSend` shape plus `method_invoke` (NSRect-by-value
  args), `objc_msgSendSuper` (NSSize args) and NSInvocation (float args,
  4+ args, struct returns). Bridge shim injected as a WKUserScript,
  messages received via a dynamically registered WKScriptMessageHandler,
  custom URI schemes via WKURLSchemeHandler, full M3 window API on
  NSWindow (`contentMinSize`/`contentMaxSize` — macOS 26 dropped
  `minContentSize`/`maxContentSize`), devtools via `developerExtrasEnabled`
  + `_inspectElement`, tray menus with checkable items/submenus, and a
  CFRunLoopTimer fiber tick mirroring the Linux GLib idle source.
  Verified on arm64 macOS 26 (all 8 examples build, 53 specs green,
  end-to-end JS bridge smoke test through `app://`). Known gap: no
  `dnd.files` — WKWebView consumes file drops with no public hook.

### Changed

- Relicensed the project to MIT (`LICENSE`, `shard.yml`); previously the
  LICENSE file granted non-commercial rights only while `README.md`
  claimed MIT. All three now agree on MIT.
- Plugin/CI gating: `deep_links` and `secure_storage` are included on
  unix **and Windows** (deep_links speaks AF_UNIX on Win10+,
  secure_storage uses the OpenSSL DLLs shipped with Crystal); the
  opt-in SQLite plugin links `sqlite3` on unix and the system
  `winsqlite3` (SDK import lib) on Windows. Specs are flag-gated
  accordingly. CI installs `openssl@3` (with `PKG_CONFIG_PATH`) on
  macOS and `libsqlite3-dev` on Linux, and builds the `positron` CLI on
  every runner.
- Window plugin: command blocks now return explicit `JSON::Any` (was an
  uninferred block return type), fixing compilation on newer Crystal
  releases where the `-> _` inference is rejected.

### Added

- `rake precommit` (format check + specs) and `rake hooks_install`,
  plus a `.githooks/pre-commit` hook that runs the checks when staged
  files touch `src/` or `spec/` (bypass with `--no-verify`).
- CI: `mkdir -p bin` before building the CLI (`bin/` is gitignored and
  absent on fresh runners).

### Added

- `CONTRIBUTING.md` with build, style and plugin authoring conventions.
- Specs for `JSFacadeGenerator`, `Host#dispatch` envelope handling and
  `Host#emit_to_js`.
- `Host#emit_to_js(event, payload)` — the single supported way to push
  events from Crystal to the frontend (main-thread marshalled); plugins
  migrated off raw `eval_js` strings. Also fixes notifications calling
  `Positron.__positronNotify`, which was only defined on `window`. (M1)
- Dev mode with live reload: `Positron::Dev::AssetServer` +
  `Application#serve_directory` — serve `frontend/` from disk, reload
  the WebView on change without recompiling; release-template markers
  (`{{CSS}}`, `{{JS}}`, `{{RUNTIME_JS}}`, `{{HYDRATE_JS}}`) are
  substituted from disk, SPA fallback, traversal protection. (M1)
- Window management API on `WebViewPort` (title, size, position,
  center, min/max constraints, maximize, fullscreen, always-on-top,
  frameless via `set_decorated`, devtools) with WebKitGTK
  implementation, window events on the EventBus forwarded to JS, and a
  `window` plugin exposing it all to the frontend. Multi-window is
  explicitly out of scope. (M3)
- Core plugins: filesystem access (XDG dirs, optional sandbox),
  dialogs & alerts (GtkMessageDialog alert/confirm/prompt), app
  lifecycle, deep links (single-instance unix socket + URL forwarding),
  permissions manager (desktop trust model). (M4)
- Secure storage plugin: AES-256-CBC + HMAC-SHA256 encrypt-then-MAC,
  PBKDF2-HMAC-SHA256 key derivation, stdlib-only crypto. (M4)
- SQLite plugin on direct FFI to libsqlite3 (opt-in require, no shard
  dependency): `sqlite.query/exec/close` with positional binds. (M4)
- Drag and drop: files dropped on the window are forwarded to the
  frontend as `dnd.files` events. (M4)
- `positron` CLI (`src/positron/cli.cr`, `rake build:cli`): `init`,
  `dev` (rebuild-if-stale + live reload), `build`, `doctor`,
  `package`. (M2/M6)
- TypeScript bindings generation
  (`Positron::BindingsGenerator`): `@[Command]` manifests from the
  `command_registry` macro, typed plugin namespaces, written to
  `<frontend>/positron.d.ts` on every dev-server start. (M2)
- Linux packaging helpers (`Positron::Packaging`): `.desktop` files,
  hicolor icon pipeline (rsvg-convert/ImageMagick), AppDir/AppImage
  scaffolding, deb control templates. (M6)
- Specs for plugins (fs sandbox, secure storage round-trip, deep links
  handshake, SQLite CRUD), dev asset server, bindings generator and
  packaging (48+ examples total).

## [0.1.0] — reference implementation

Initial Linux reference implementation of the Host-Shim pattern:
EventBus, CommandRegistry, StateManager, PluginManager, DesktopHost with
WebKitGTK + AppIndicator, JS runtime facade, clipboard / display /
file_picker / keyboard / logger / notifications / preferences /
save_file_dialog / theme plugins, compile-time asset embedding and
custom URI schemes.
