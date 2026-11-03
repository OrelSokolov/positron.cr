# Positron — Electron on Crystal

**Positron is a cross-platform UI framework for building desktop apps with a
JS + CSS frontend and a Crystal backend — Electron's model, with Crystal
instead of Node.js, and without the bundled Chromium**: the OS WebView
renders your frontend while all state and logic live in a single Crystal
process (the same lightweight approach as [Wails](https://wails.io) for Go
or Tauri for Rust).

```crystal
class MyApp < Positron::Application
  @[Positron::Command]
  def greet(name : String) : String
    "Hello, #{name}!"
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(title: "MyApp"))
    webview.load_url("app://myapp/")
  end
end
```

- **Frontend:** plain HTML/CSS/JS (or any framework) rendered in the native
  WebView.
- **Backend:** Crystal — typed `@[Command]` methods callable from JS as
  promises, events in both directions.
- **Single binary:** assets are embedded at compile time; no runtime deps
  beyond the OS WebView.
- **Cross-platform by design:** all platform code sits behind ports and
  adapters. **Linux (WebKitGTK), macOS (WKWebView) and Windows (WebView2)
  are fully working today** — all macOS plugin adapters are ported too
  (drag & drop of files remains unavailable on macOS, WKWebView consumes
  drops with no public hook);
  see the checklist below and `ROADMAP.md`.

This repository contains the reference implementation of the
**Positron Host-Shim Pattern** described in `positron-architecture.md`.

## Status checklist

What is already there ✔ and what is still needed ☐:

### Core framework

- [x] Host core: `EventBus`, `CommandRegistry`, `StateManager`,
      `PluginManager`, `DesktopHost`, GTK event loop + Crystal fibers
- [x] Async command dispatch: handlers run in fibers off the GUI
      thread, promise resolve marshalled back via `run_on_main`
      (`Host#dispatch`; `dispatch_now` for synchronous use)
- [x] Cancellable/pausable background jobs: `Positron.async_job` (a
      Token for `pause!`/`resume!`/`cancel!`, cooperative checkpoints)
      and `Positron.async_work_n_threads` — one job on N Parallel
      worker threads sharing a single token (~N× faster CPU-bound
      jobs); demos: `async_work_with_pause_and_stop`,
      `async_work_n_threads`
- [x] Virtual HTTP layer: `Positron.http.*` (fetch semantics) over the
      bridge, `Router` with block routes, `namespace`, Rails-style
      controllers (`@[Positron::Heavy]`, `resources`), middleware,
      light/heavy work semantics shared with async_work
- [x] WebView adapter (WebKitGTK 4.1): window API, devtools, drag & drop,
      custom URI schemes
- [x] System tray (Ayatana AppIndicator) with cross-platform tray API
- [x] Compile-time asset embedding (`embed_directory` / `embed_file`) —
      single-binary apps
- [x] JS runtime facade (`Positron.call/on/emit/state`) + generated
      TypeScript declarations (`positron.d.ts`)
- [x] Crystal → JS event bridge (`Host#emit_to_js`, main-thread marshalling)
- [x] Dev mode: asset server with live reload (`POSITRON_DEV=1`),
      no recompiling for frontend changes
- [x] Window management API (title/size/fullscreen/frameless/
      always-on-top/min-max, window events in JS)
- [x] Frameless windows + CSS-drag (`--positron-drag: drag`,
      Wails `--wails-draggable` analogue; Linux)
- [x] Dev error overlay + STDERR duplication (dev asset server)
- [x] Close-veto hook (`Application#on_before_close`, Wails
      `OnBeforeClose` analogue): return false to keep the window open;
      user-initiated close only — `Host#stop` bypasses it (Linux/macOS/
      Windows adapters)
- [x] `positron` CLI: `init` / `dev` / `build` / `doctor` / `package`
- [x] Packaging: `.desktop` entries, hicolor icons, AppDir/AppImage, deb
- [x] Headless test suite (53 specs)
- [x] macOS adapter (WKWebView + NSWindow, NSStatusBar tray, NSApp event
      loop) via a pure-Crystal Objective-C runtime layer
      (`adapters/macos/objc.cr`) — no bindings shard needed
- [x] Windows adapter (M5.2): WebView2 window + JS bridge + event loop +
      tray + theme via the vendored `webview.dll`, the M4 plugin
      adapters and the POSIX-neutral plugins (fs dirs, deep_links over
      AF_UNIX, secure_storage, SQLite via the system winsqlite3) — see
      `CHANGELOG.md` for details
- [x] macOS plugin adapter ports (M5.3 done): notifications
      (UNUserNotificationCenter), clipboard (NSPasteboard), dialogs
      (NSAlert), file picker (NSOpenPanel), save file dialog
      (NSSavePanel), display info (CoreGraphics), theme
      (NSAppearance/NSColor/NSWorkspace)
- [ ] macOS dmg packaging templates (.app bundling + codesign is done)
- [ ] Documentation site / `docs/` tree, shard publishing, tagged releases

### Plugins (Linux + Windows; macOS adapters still stubs except notifications)

- [x] Clipboard (text / image / files)
- [x] Window control from JS
- [x] Filesystem (XDG dirs, read/write/list, optional sandbox)
- [x] Dialogs (native alert / confirm / prompt)
- [x] File picker + save file dialog
- [x] Notifications (libnotify / UNUserNotificationCenter, click callbacks).
      On macOS, a bare dev binary automatically falls back to
      `osascript display notification` (no bundle needed, no click
      callbacks); from a signed `.app` bundle the native
      UNUserNotificationCenter path is used — `positron package
      --install`
- [x] App lifecycle (`lifecycle.*` events)
- [x] Deep links (single instance + URL forwarding)
- [x] Permissions manager (desktop trust model, mobile-ready shape)
- [x] Secure storage (AES-256-CBC + HMAC, PBKDF2)
- [x] SQLite (direct FFI, opt-in)
- [x] Theme / appearance (dark/light)
- [x] Display info, keyboard events, logger, preferences
- [x] WebView media permissions: `getUserMedia` (camera/microphone),
      geolocation and other web permission requests are granted by the
      host — WebKitGTK `permission-request` (Linux), WebView2
      `PermissionRequested` (Windows), WKUIDelegate
      `requestMediaCapturePermissionFor…` (macOS); every grant is
      broadcast to the frontend as `permission.requested`.
      macOS additionally needs a `.app` bundle declaring
      `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` (TCC
      attributes capture to the "responsible process" — a bare binary
      inherits the terminal's identity and the OS prompt never shows;
      `rake build:camera_app` wraps the camera example into one).
      Note: `navigator.mediaDevices` requires a secure context — serve
      the frontend with `serve_directory` (dev) or a custom URI scheme,
      not `load_html`
- [ ] Local (scheduled) notifications with actions
- [ ] Share sheet, badges, taskbar progress, global hotkeys, system sounds
- [ ] Media & hardware plugins (camera, microphone, audio/video player,
      geolocation, sensors, biometrics) — Tier 2+ in `plugins.txt`;
      frontend `getUserMedia` already works (see media permissions above)

### Mobile

- [x] Android host (arm64): real `Adapters::Android::Host` + `WebViewPort`
      over a Java Activity/WebView shim, pure-Crystal JNI layer
      (`adapters/android/jni.cr`), host-thread event loop pump, C seam
      for Java-thread events (`android/positron_shim.c`), embedded
      assets over the virtual `https://app.positron.local/` host
      (shouldInterceptRequest), JS bridge via `addJavascriptInterface`,
      APK packaging without gradle (`rake build:android` — aapt/d8/
      apksigner, vendored static Crystal runtime libs in
      `third_party/android/`)
- [x] Android plugin adapters: clipboard (ClipboardManager), theme
      (UI_MODE), display (DisplayMetrics), preferences
      (SharedPreferences), lifecycle (Activity callbacks) — the rest
      (file_picker, save_file_dialog, notifications, secure_storage)
      stay stubs/absent for now
- [ ] iOS host (architecture §8 ready, not implemented)

## Android

Build the hello example into an APK (arm64; no gradle, no androidx):

    rake build:android          # → android/positron.apk
    adb install -r android/positron.apk

Requirements: Android SDK with NDK 25.2, build-tools 34+, platform 34,
JDK, `rsvg-convert` or ImageMagick (launcher icon). Apps register for
the mobile entry instead of calling `Application#run`:

    {% if flag?(:android) %}
      Positron::EntryAndroid.app(HelloApp)
    {% else %}
      HelloApp.new.run
    {% end %}

The Crystal runtime lives on a dedicated host thread created by
`android/positron_shim.c`; Java threads (UI, JS bridge, WebView IO)
never touch Crystal — everything crosses the C seam as copied strings.
Under ndk_translation (arm64 app on an x86_64 emulator) the Boehm GC
is disabled automatically before boot.

## Platform support matrix

Current status per platform: **Linux, macOS and Windows are working;
Android works for the core host + 5 plugin adapters** (arm64 APK).
on macOS all plugin adapters are ported (`dnd.files` is not possible
there — WKWebView consumes file drops with no public hook). Legend: ✅ works · 🔶 stub
(compiles, no implementation) · ❌ not implemented (planned).

| Feature | Linux | macOS | Windows | Android |
|---|:---:|:---:|:---:|:---:|
| **Core (host, EventBus, commands, plugins, StateManager)** — platform-pure | ✅ | ✅ | ✅ | ✅ |
| **JS facade + TS bindings generation** — platform-pure | ✅ | ✅ | ✅ | ✅ |
| **`positron` CLI (init/build/doctor)** | ✅ | ✅ | ✅ | — (use `rake build:android`) |
| WebView surface | ✅ WebKitGTK 4.1 | ✅ WKWebView | ✅ WebView2 (vendored `webview.dll`) | ✅ android.webkit (Java shim) |
| Event loop | ✅ GTK + fibers | ✅ NSApp run loop + fibers | ✅ Win32 message pump + fibers | ✅ host-thread pump + fibers |
| System tray | ✅ AppIndicator | ✅ NSStatusItem | ✅ Shell_NotifyIcon | ❌ (no tray on mobile) |
| Window management API (M3) | ✅ | ✅ | ✅ | 🔶 (manifest-level; ops raise) |
| Custom URI schemes + embedded assets serving | ✅ | ✅ | ✅ (virtual https host; absolute `app://` URLs in assets unsupported) | ✅ virtual https host (same as Windows) |
| Dev mode / live reload (`POSITRON_DEV=1`) | ✅ | ✅ | ✅ | 🔶 (devtools via `chrome://inspect` on debuggable builds) |
| Devtools | ✅ | ✅ (right-click Inspect / `_inspectElement`) | 🔶 (F12 in dev builds; the window API raises) | 🔶 (debuggable builds) |
| Drag & drop (`dnd.files`) | ✅ | ❌ (WKWebView consumes drops) | ❌ | ❌ |
| Media permissions (`getUserMedia`) | ✅ | ✅ (packaged `.app` only — bare binaries get no system prompt) | ✅ | 🔶 (granted; OS permission prompts pending) |
| All 16 core plugins (clipboard, fs, dialogs, …) | ✅ | ✅ | ✅ | 🔶 (clipboard/theme/display/preferences/lifecycle real; rest stubs) |
| Packaging | ✅ .desktop / AppImage / deb | ✅ .app + codesign (dmg pending) | ✅ MSI via `crosspack pack` | ✅ APK via `rake build:android` (debug-signed) |
| `positron package` | ✅ | ✅ (`.app`; `MACOS_SIGN_IDENTITY`, `MACOS_BUNDLE_ID`) | ❌ (use `crosspack pack`) | ❌ (use `rake build:android`) |

## Philosophy

- **Crystal Host** owns state, business logic, navigation, plugins and lifecycle.
- **Native Shim** is a thin, passive adapter that exposes OS APIs
  (WebView, System Tray, Notifications) to Crystal.
- **Single process** on desktop — no Electron-style multi-process overhead.

## What is implemented for Linux

| Component | File | Notes |
|---|---|---|
| EventBus | `src/positron/event_bus.cr` | Internal pub/sub with per-handler fibers |
| Command Registry | `src/positron/command_registry.cr` | JSON command dispatch + `@[Command]` macro support |
| Virtual HTTP Router | `src/positron/http_router.cr` | Fetch-semantics resource routing, controllers, middleware, light/heavy |
| Plugin System | `src/positron/plugin.cr` | Base plugin + `PluginManager` |
| Tray Item | `src/positron/tray_item.cr` | Cross-platform menu item abstraction |
| Icon Source | `src/positron/icon_source.cr` | Cross-platform icon descriptor (SVG/PNG/ICO) |
| WebView Config | `src/positron/web_view_config.cr` | Platform-agnostic WebView creation config |
| Host Abstraction | `src/positron/host.cr` | Shared dispatch/bind logic + `emit_to_js` |
| Application API | `src/positron/application.cr` | `on_ready`, lifecycle, deep links, permissions |
| Desktop Host | `src/positron/desktop_host.cr` | Wires WebView, tray, commands, EventBus |
| Mobile Host | `src/positron/mobile_host.cr` | Base for Android/iOS host integration |
| Linux EventLoop | `src/positron/event_loop/linux.cr` | GTK main loop + Crystal fiber idle source |
| macOS EventLoop | `src/positron/event_loop/macos.cr` | `[NSApp run]` + CFRunLoopTimer fiber tick |
| Dev Asset Server | `src/positron/dev/asset_server.cr` | Serve frontend from disk + live reload |
| TS Bindings | `src/positron/bindings_generator.cr` | Typed `positron.d.ts` from manifests |
| CLI | `src/positron/cli.cr` | `positron init/dev/build/doctor/package` |
| Packaging | `src/positron/packaging.cr` | `.desktop`, hicolor icons, AppDir/AppImage, deb, macOS `.app` + codesign |
| Clipboard Plugin | `src/positron/plugins/clipboard/` | Text / image / file clipboard access |
| Window Plugin | `src/positron/plugins/window/` | Window control from JS (title, size, fullscreen…) |
| Filesystem Plugin | `src/positron/plugins/filesystem/` | XDG dirs, read/write/list, optional sandbox |
| Dialogs Plugin | `src/positron/plugins/dialogs/` | Native alert / confirm / prompt |
| Lifecycle Plugin | `src/positron/plugins/lifecycle/` | `lifecycle.*` events to the frontend |
| Deep Links Plugin | `src/positron/plugins/deep_links/` | Single instance + URL forwarding |
| Permissions Plugin | `src/positron/plugins/permissions/` | Desktop trust model, mobile-ready shape |
| Secure Storage Plugin | `src/positron/plugins/secure_storage/` | AES-256-CBC + HMAC, PBKDF2 (stdlib crypto) |
| SQLite Plugin | `src/positron/plugins/sqlite/` | Direct FFI to libsqlite3 (opt-in require) |
| WebView Adapter | `src/positron/adapters/linux/webkit_gtk.cr` | WebKitGTK 4.1, window API, devtools, drag&drop |
| Tray Adapter | `src/positron/adapters/linux/app_indicator_tray.cr` | Ayatana AppIndicator |
| Windows Adapters | `src/positron/adapters/windows/` | WebView2 via vendored `webview.dll`, Win32 tray, COM interception |
| macOS ObjC Layer | `src/positron/adapters/macos/objc.cr` | Pure-Crystal Objective-C runtime bindings |
| macOS WebView Adapter | `src/positron/adapters/macos/webview.cr` | WKWebView + NSWindow, bridge, URI schemes |
| macOS Tray Adapter | `src/positron/adapters/macos/tray.cr` | NSStatusBar / NSStatusItem |
| Android Host (stub) | `src/positron/adapters/android/host.cr` | Mobile host placeholder |
| iOS Host (stub) | `src/positron/adapters/ios/host.cr` | Mobile host placeholder |

## Requirements

- Crystal >= 1.10
- GTK 3 development files
- WebKitGTK 4.1 development files
- Ayatana AppIndicator 3 development files

On Ubuntu/Debian:

```bash
sudo apt install crystal libgtk-3-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev
```

A portable Crystal binary is also bundled in `.crystal/crystal-1.20.2-1/` for
this reference workspace.

## Build

```bash
crystal build examples/hello.cr -o examples/hello
```

All examples at once — in parallel through
[taskforge](https://github.com/OrelSokolov/taskforge) (memory-aware
worker width, per-worker compiler caches):

```bash
bundle install        # once: sysmonitor + taskforge (GitHub git sources)
rake build:examples   # ~24 s instead of ~2 min; TASKFORGE_JOBS=N forces width
```

Or with the bundled compiler:

```bash
.crystal/crystal-1.20.2-1/bin/crystal build examples/hello.cr -o examples/hello
```

## Run

```bash
./examples/hello
```

A GTK window with a WebKitGTK web view and a system tray icon will appear.

### Clipboard demo

```bash
crystal build examples/clipboard.cr -o examples/clipboard-bin
./examples/clipboard-bin
```

Copy text or an image to the system clipboard, then press `Ctrl+V` inside the
webview (or use the buttons) to paste it back through the Crystal Host.
Clicking the button in the web page sends a JSON message to the Crystal Host
via the generic `PositronBridge.postMessage` runtime, which the Linux adapter
wires to `window.webkit.messageHandlers.crystal.postMessage` under the hood.

## Architecture

```
┌─────────────────────────────────────────┐
│           Positron Host                │
│  Application  →  DesktopHost            │
│  CommandRegistry  →  EventBus           │
│  PluginManager                          │
└───────────────┬─────────────────────────┘
                │ FFI / direct calls
┌───────────────▼─────────────────────────┐
│         Linux Native Shim               │
│  WebKitGTK   AppIndicatorTray           │
│  GTK Main Loop + Crystal fibers         │
└───────────────┬─────────────────────────┘
                │ Positron.async_work rule
┌───────────────▼─────────────────────────┐
│   Fiber::ExecutionContext::Parallel     │
│   (worker threads for CPU-bound work)   │
└─────────────────────────────────────────┘
```

## Background work: the async_work rule

All background work goes through one DSL — the framework itself uses it
for command dispatch, so app code cannot pick the wrong pattern:

```crystal
Positron.async_work { ... }      # конкурентно (fiber): IO, сабпроцессы, ожидание
Positron.parallel_work { ... }   # параллельно (рабочий поток): CPU-циклы
Positron.async_job { |token| }   # async_work + пауза/стоп (job.pause!/cancel!)
Positron.async_work_n_threads(threads: n) { |token, i| }
                                 # одна задача, n воркеров на Parallel-потоках
task.value                       # ждать результат (паркует fiber)
Positron.on_main { ... }         # тронуть UI из любой задачи
```

Expanded, with the contracts:

```crystal
# Concurrent (a fiber): for work that waits — IO, subprocesses,
# sleeps, channels. Never tight-loop here.
task = Positron.async_work { parse_large_file(path) }

# Truly parallel (a worker thread, Crystal >= 1.21): for CPU-bound
# loops that would starve the cooperative scheduler and freeze the
# GUI. Never touch the UI inside the block; the return value crosses
# as JSON (nothing mutable is shared).
task = Positron.parallel_work { heavy_computation(input) }

# Cancellable/pausable async_work: the block gets a Token whose
# sleep/checkpoint! are the cooperative stop/pause points. The Job
# handle flips atomic flags — safe to call from the GUI fiber.
job = Positron.async_job do |token|
  items.each do |item|
    process(item)
    token.checkpoint!        # raises AsyncWork::Cancelled after cancel!
  end
end
job.pause!                   # token.sleep parks while paused
job.resume!
job.cancel!                  # next checkpoint aborts the block
job.value                    # => {"results": [...], "cancelled": bool}

# One CPU-bound job, N workers on Parallel threads (~N× faster): the
# block runs once per worker with its index — split the work by it.
# All workers share one token, so pause!/cancel! cover the whole
# fleet. Same no-UI-inside contract as parallel_work.
job = Positron.async_work_n_threads(threads: 4) do |token, index|
  burn_my_slice(index)       # report progress via a shared atomic
  token.checkpoint!
end

# Await — parks the calling fiber. Raises on the GUI fiber instead of
# freezing the UI.
result = task.value

# Touch the UI from any task.
Positron.on_main { label.text = result.to_s }
```

Errors surface as `_async_error` / `_parallel_error` keys in the
result. `Host#dispatch` routes every command through `async_work`, and
`command.invoked` through `dispatch` — there is no code path that runs
a handler on the GUI fiber.

For command handlers the choice is declarative — declare the character
of the work at registration and the framework picks the context:

```crystal
registry.register("project.load") do |req|          # :fiber (default)
  load_project(req.args["path"].as_s)                # IO-bound: waits
end

registry.register("project.reindex", execution: :parallel) do |req|
  reindex_everything                                # CPU-bound: the
end                                                 # body runs on a
                                                    # worker thread and
                                                    # cannot freeze the
                                                    # GUI (no touching
                                                    # the UI inside; a
                                                    # crash becomes an
                                                    # error result)
```

The DSL is also available as instance methods on the application
(`async_work`, `parallel_work`, `on_main`) so app code reads naturally.

## Virtual HTTP: resource routing without a server

The frontend can talk to the backend the way browser apps talk to
servers — method + path + body — over the same bridge. No network is
involved: `Positron.http.get("/api/...")` becomes a `type: "http"`
envelope, matched against routes drawn in `Application#draw_routes`,
and the promise always resolves with `{status, body}` (fetch
semantics: 404/500 are statuses, not rejections; only a dead bridge
rejects).

JS side (generated facade):

```js
const res = await Positron.http.get(`/api/projects/${id}/tasks?page=2&q=привет`)
if (res.status === 200) render(res.body.tasks)

await Positron.http.put(`/api/tasks/${taskId}`, { stressedText: "при́мер" })
// Opt-in fetch interception for path-relative URLs (real fetch stays
// available for the dev server / HMR):
Positron.installFetch()
```

Crystal side — block routes:

```crystal
def draw_routes(r : Positron::Router)
  r.namespace "/api" do
    r.get "/projects" { |req| list_projects(req.query) }
    r.heavy do                       # CPU/blocking work: worker pool
      r.get "/projects/:id/tasks" { |req| task_page(req.params["id"], req.query) }
    end
    r.put "/tasks/:id" { |req| update_task(req.params["id"], req.body) }
  end
end
```

Or Rails-style controllers — `@[Positron::Heavy]` on an action marks it
for the worker pool automatically; `resources` maps the five RESTful
actions in one line:

```crystal
class TasksController < Positron::Controller
  @[Positron::Heavy]
  def index(request)                 # GET /api/tasks
    Db.task_page(request.query)
  end

  def update(request)                # PUT /api/tasks/:id
    Db.update_task(request.params["id"], request.body)
  end

  actions                            # macro: generates the dispatch table
end

def draw_routes(r)
  r.resources "/api/tasks", TasksController
end
```

Middleware (cross-cutting concerns — logging, timings, error capture):

```crystal
Positron::Router.use do |req|
  t = Time.instant
  nil # pass through; return a Response to short-circuit
end
```

Work semantics are shared with the async_work rule: `light` routes run
in the dispatch fiber (sub-second handlers), `heavy` routes
(`r.heavy`, `heavy: true`, or `@[Positron::Heavy]`) run on the Parallel
worker pool and can never freeze the GUI. Actions may return any
JSON-able value (→ 200) or a `Positron::Response` for custom statuses;
handler exceptions become `{status: 500, body: {error}}`, unknown
paths become 404.

Binary payloads (audio samples, images) should keep using commands —
the bridge envelope is JSON.

## Project structure

```
src/
  positron.cr                          # Main entry point
  positron/
    event_bus.cr                         # Internal pub/sub
    command_registry.cr                  # Command dispatch
    http_router.cr                       # Virtual HTTP: Router/Controller/middleware
    plugin.cr                            # Plugin base + manager
    tray_item.cr                         # Cross-platform tray menu item
    icon_source.cr                       # Cross-platform icon descriptor
    web_view_config.cr                   # WebView creation config
    host.cr                              # Abstract host (desktop + mobile)
    desktop_host.cr                      # Desktop wiring
    mobile_host.cr                       # Mobile wiring base
    application.cr                       # Application base class
    ports/                               # Abstract ports
      event_loop_port.cr
      webview_port.cr
      tray_port.cr
      icon_port.cr
    event_loop/                          # Platform event loops
      linux.cr
      windows.cr
      macos.cr
      android.cr
      ios.cr
      factory.cr
    adapters/
      linux/                             # Linux shims
        webkit_gtk.cr
        app_indicator_tray.cr
        icon.cr
        factory.cr
      macos/                             # macOS shims (WKWebView/NSWindow;
        objc.cr                          #   objc.cr is the ObjC runtime layer)
        webview.cr
        tray.cr
        icon.cr
        factory.cr
      windows/                           # Windows shims (WebView2 via
        webview2.cr                      #   the vendored webview.dll)
        tray.cr
        icon.cr
        factory.cr
      android/                           # Android mobile host (stub)
        host.cr
        icon.cr
        factory.cr
      ios/                               # iOS mobile host (stub)
        host.cr
        icon.cr
        factory.cr
examples/
  hello.cr                               # Demo entry point
  hello/
    hello.cr                             # Polished demo app
    frontend/                            # HTML/CSS/JS assets
  camera/                                # getUserMedia live preview over
    camera.cr                            # the app:// scheme (embedded
    frontend/                            # tree; permission grants) —
                                         # on macOS run via
                                         # rake build:camera_app (needs
                                         # a bundled NSCameraUsage…)
  scheduler_demo/                        # CPU burn vs cooperative
    scheduler_demo.cr                    # scheduler: freeze / yield /
    burn.cr                              # subprocess strategies
    frontend/
  async_progress/                        # background job pushing
    async_progress.cr                    # progress events to the UI
    worker.cr                            # (async_work + emit_to_js)
    frontend/
  eta_progress/                          # 10 workers, tqdm-style
    eta_progress.cr                      # bars with %, elapsed, rate,
    worker.cr                            # ETA (async_work per worker)
    frontend/
  async_work_with_pause_and_stop/        # async_job: pause/resume/
    async_work_with_pause_and_stop.cr    # stop a background job
    worker.cr                            # through its Token
    frontend/
  async_work_n_threads/                  # one CPU-bound job on N
    async_work_n_threads.cr              # Parallel threads (~N×
    worker.cr                            # faster), shared token
    frontend/
assets/
  crystal-icon.svg                       # Blue crystal icon
```

## Tray API

The tray follows the cross-platform design of `getlantern/systray`:

```crystal
# icon_source is generated by embed_application_files and picks the right
# format (.svg on Linux, .ico on Windows, .png on macOS) at compile time.
tray.set_icon(icon_source)
tray.set_title("Positron")
tray.add_or_update_item(Positron::TrayItem.new(id: 1, title: "Open"))
tray.add_separator(2)
tray.add_or_update_item(Positron::TrayItem.new(id: 3, title: "Quit"))

tray.on_item_click do |id|
  case id
  when 1 then webview.show
  when 3 then stop
  end
end

tray.show
```

## Icon assets

The `embed_application_files` macro selects the right icon format per platform
at compile time using `IconAdapter`:

| Platform | Preferred | Fallbacks |
|---|---|---|
| Linux | `.svg` | `.png`, `.ico` |
| Windows | `.ico` | `.png`, `.svg` |
| macOS | `.png` | `.svg`, `.ico` |
| Android / iOS | `.png` | `.svg`, `.ico` |

Place icons next to each other with the same base name, e.g.:

```
assets/
  crystal-icon.svg
  crystal-icon.png
  crystal-icon.ico
```

Then in your application:

```crystal
embed_application_files(__DIR__, "../assets/crystal-icon")

def on_ready
  webview.create(Positron::WebViewConfig.new(
    title: "MyApp",
    icon: icon_source
  ))
  tray.set_icon(icon_source)
end
```

The macro embeds the preferred format and exposes `icon_bytes`, `icon_path`
and `icon_source` with the correct `IconSource` format tag.

## Extending

Add a `@[Command]` method to the example application:

```crystal
class HelloApp < Positron::Application
  def register_commands(registry)
    command_registry
  end

  @[Positron::Command]
  def greet(name : String) : String
    "Hello, #{name}!"
  end
end
```

From JavaScript the runtime uses the platform-agnostic bridge:

```javascript
Positron.call("greet", { name: "Crystal" }).then(result => {
  console.log(result);
});
```

The Host dispatches the call in Crystal and resolves the promise with
`window.__positronResolve(id, success, data, error)`.

## Embedding assets & custom URI schemes

`Application#embed_directory("frontend")` bakes a whole directory tree into
the binary at compile time (Base64-encoded, binary-safe) — intended for
built web apps with hashed asset names. `Application#embed_file("assets/icon.svg")`
bakes a single file as a String. Both arguments must be plain string
literals; relative paths resolve against the compiler's working directory.

Serve the embedded tree to the WebView without any HTTP server:

```crystal
class MyApp < Positron::Application
  embed_directory("frontend")

  def on_ready
    webview.register_uri_scheme("app") do |path|
      if bytes = embedded_file?(path)
        Positron::SchemeResponse.new(bytes, "text/html; charset=utf-8")
      end
    end
    webview.create(Positron::WebViewConfig.new(title: "MyApp", close_to_tray: false))
    webview.load_url("app://myapp/")
  end
end
```

`WebViewConfig#close_to_tray = false` makes the window close button quit the
event loop instead of hiding the window for a tray "Open" action.

## Development mode: hot reload without recompiling

`Application#serve_directory(dir)` is the runtime counterpart of asset
embedding: an in-process HTTP server serves the frontend from disk and
reloads the WebView whenever a file changes. Release-template markers
(`{{CSS}}`, `{{JS}}`, `{{RUNTIME_JS}}`, `{{HYDRATE_JS}}`) are substituted
on the fly, so one frontend source serves both modes:

```crystal
def on_ready
  webview.create(Positron::WebViewConfig.new(title: "MyApp", close_to_tray: false))
  webview.bind("crystal") { |json| host.dispatch(json) }

  if Positron::Dev.enabled?   # POSITRON_DEV=1
    webview.load_url(serve_directory(File.join(__DIR__, "frontend")))
  else
    webview.load_html(application_html)
  end
end
```

On every dev start, typed TypeScript declarations are regenerated into
`<frontend>/positron.d.ts` from the plugin manifests and your
`@[Command]` methods.

## The `positron` CLI

```bash
rake build:cli                       # builds bin/positron

POSITRON_PATH=/path/to/positron bin/positron init my-app
cd my-app && shards install
bin/positron dev                   # rebuild-if-stale + live reload
bin/positron build                 # release binary in bin/
bin/positron doctor                # toolchain and native deps check
bin/positron package [--install]   # Linux: icons, .desktop, AppDir/AppImage
                                    # macOS: codesigned .app (ad-hoc by default;
                                    #   MACOS_SIGN_IDENTITY / MACOS_BUNDLE_ID)
```

## Window management

`WebViewPort` exposes a window API (`set_title`, `resize`, `center`,
min/max size, `maximize`, `fullscreen`, `set_always_on_top`,
`set_decorated(false)` for frameless, devtools) implemented by the
WebKitGTK adapter. Window changes are broadcast as events
(`window.resized`, `window.moved`, `window.maximized`, …) and forwarded
to JS. The `window` plugin exposes the same surface to the frontend:

```javascript
await Positron.window.fullscreen();
Positron.on("window.resized", ({width, height}) => console.log(width, height));
```

Multi-window support is intentionally out of scope.

## Events from Crystal to JS

`Host#emit_to_js(event, payload)` is the single supported channel — it
marshals to the GUI thread and notifies all `Positron.on(event, …)`
subscribers. Window events, `dnd.files` (drag & drop),
`permission.requested` (every WebView permission grant — camera,
microphone, geolocation, …), `lifecycle.*`, `deep_link.opened` and
plugin callbacks all use it.

## Opt-in SQLite plugin

The SQLite plugin binds libsqlite3 directly (no shard dependency).
Enable it explicitly so apps without a database don't link it:

```crystal
require "positron/plugins/sqlite/plugin"

class MyApp < Positron::Application
  def configure_plugins
    register_plugin(Positron::Plugins::Sqlite.new(app_id: "myapp"))
  end
end
```

```javascript
await Positron.sqlite.exec(
  "CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT)");
await Positron.sqlite.query("SELECT * FROM notes");
```

## License

MIT
