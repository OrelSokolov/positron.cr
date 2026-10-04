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
  are fully working today** — of the macOS plugin adapters only
  notifications is ported, the rest are stubs;
  see the checklist below and `ROADMAP.md`.

This repository contains the reference implementation of the
**Positron Host-Shim Pattern** described in `positron-architecture.md`.

## Status checklist

What is already there ✔ and what is still needed ☐:

### Core framework

- [x] Host core: `EventBus`, `CommandRegistry`, `StateManager`,
      `PluginManager`, `DesktopHost`, GTK event loop + Crystal fibers
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
- [~] macOS plugin adapter ports (notifications done; clipboard, dialogs,
      … still stubs) — M5.3
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
- [ ] Local (scheduled) notifications with actions
- [ ] Share sheet, badges, taskbar progress, global hotkeys, system sounds
- [ ] Media & hardware plugins (camera, microphone, audio/video player,
      geolocation, sensors, biometrics) — Tier 2+ in `plugins.txt`
- [ ] Plugin ports to macOS (adapter-by-adapter with M5.3; notifications
      done)

### Mobile (non-goal for now)

- [ ] Android / iOS hosts — architecture supports them, deliberately
      deferred until the desktop story is complete

## Platform support matrix

Current status per platform: **Linux, macOS and Windows are working**;
on macOS the plugin adapters are stubs except notifications (ported) —
they port with M5.3 in `ROADMAP.md`. Legend: ✅ works · 🔶 stub
(compiles, no implementation) · ❌ not implemented (planned).

| Feature | Linux | macOS | Windows |
|---|:---:|:---:|:---:|
| **Core (host, EventBus, commands, plugins, StateManager)** — platform-pure | ✅ | ✅ | ✅ |
| **JS facade + TS bindings generation** — platform-pure | ✅ | ✅ | ✅ |
| **`positron` CLI (init/build/doctor)** | ✅ | ✅ | ✅ |
| WebView surface | ✅ WebKitGTK 4.1 | ✅ WKWebView | ✅ WebView2 (vendored `webview.dll`) |
| Event loop | ✅ GTK + fibers | ✅ NSApp run loop + fibers | ✅ Win32 message pump + fibers |
| System tray | ✅ AppIndicator | ✅ NSStatusItem | ✅ Shell_NotifyIcon |
| Window management API (M3) | ✅ | ✅ | ✅ |
| Custom URI schemes + embedded assets serving | ✅ | ✅ | ✅ (virtual https host; absolute `app://` URLs in assets unsupported) |
| Dev mode / live reload (`POSITRON_DEV=1`) | ✅ | ✅ | ✅ |
| Devtools | ✅ | ✅ (right-click Inspect / `_inspectElement`) | 🔶 (F12 in dev builds; the window API raises) |
| Drag & drop (`dnd.files`) | ✅ | ❌ (WKWebView consumes drops) | ❌ |
| All 16 core plugins (clipboard, fs, dialogs, …) | ✅ | 🔶 (notifications ✅; rest with M5.3) | ✅ |
| Packaging | ✅ .desktop / AppImage / deb | ✅ .app + codesign (dmg pending) | ✅ MSI via `crosspack pack` |
| `positron package` | ✅ | ✅ (`.app`; `MACOS_SIGN_IDENTITY`, `MACOS_BUNDLE_ID`) | ❌ (use `crosspack pack`) |

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
└─────────────────────────────────────────┘
```

## Project structure

```
src/
  positron.cr                          # Main entry point
  positron/
    event_bus.cr                         # Internal pub/sub
    command_registry.cr                  # Command dispatch
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
`lifecycle.*`, `deep_link.opened` and plugin callbacks all use it.

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
