:
# CrystalUI — Linux Reference Implementation

This repository contains a working Linux desktop implementation of the
**CrystalUI Host-Shim Pattern** described in `crystal-ui-architecture.md`.

## Philosophy

- **Crystal Host** owns state, business logic, navigation, plugins and lifecycle.
- **Native Shim** is a thin, passive adapter that exposes OS APIs
  (WebView, System Tray, Notifications) to Crystal.
- **Single process** on desktop — no Electron-style multi-process overhead.

## What is implemented for Linux

| Component | File | Notes |
|---|---|---|
| EventBus | `src/crystal_ui/event_bus.cr` | Internal pub/sub with per-handler fibers |
| Command Registry | `src/crystal_ui/command_registry.cr` | JSON command dispatch + `@[Command]` macro support |
| Plugin System | `src/crystal_ui/plugin.cr` | Base plugin + `PluginManager` |
| Tray Item | `src/crystal_ui/tray_item.cr` | Cross-platform menu item abstraction |
| Icon Source | `src/crystal_ui/icon_source.cr` | Cross-platform icon descriptor (SVG/PNG/ICO) |
| WebView Config | `src/crystal_ui/web_view_config.cr` | Platform-agnostic WebView creation config |
| Host Abstraction | `src/crystal_ui/host.cr` | Shared dispatch/bind logic + `emit_to_js` |
| Application API | `src/crystal_ui/application.cr` | `on_ready`, lifecycle, deep links, permissions |
| Desktop Host | `src/crystal_ui/desktop_host.cr` | Wires WebView, tray, commands, EventBus |
| Mobile Host | `src/crystal_ui/mobile_host.cr` | Base for Android/iOS host integration |
| Linux EventLoop | `src/crystal_ui/event_loop/linux.cr` | GTK main loop + Crystal fiber idle source |
| Dev Asset Server | `src/crystal_ui/dev/asset_server.cr` | Serve frontend from disk + live reload |
| TS Bindings | `src/crystal_ui/bindings_generator.cr` | Typed `crystal-ui.d.ts` from manifests |
| CLI | `src/crystal_ui/cli.cr` | `crystal-ui init/dev/build/doctor/package` |
| Packaging | `src/crystal_ui/packaging.cr` | `.desktop`, hicolor icons, AppDir/AppImage, deb |
| Clipboard Plugin | `src/crystal_ui/plugins/clipboard/` | Text / image / file clipboard access |
| Window Plugin | `src/crystal_ui/plugins/window/` | Window control from JS (title, size, fullscreen…) |
| Filesystem Plugin | `src/crystal_ui/plugins/filesystem/` | XDG dirs, read/write/list, optional sandbox |
| Dialogs Plugin | `src/crystal_ui/plugins/dialogs/` | Native alert / confirm / prompt |
| Lifecycle Plugin | `src/crystal_ui/plugins/lifecycle/` | `lifecycle.*` events to the frontend |
| Deep Links Plugin | `src/crystal_ui/plugins/deep_links/` | Single instance + URL forwarding |
| Permissions Plugin | `src/crystal_ui/plugins/permissions/` | Desktop trust model, mobile-ready shape |
| Secure Storage Plugin | `src/crystal_ui/plugins/secure_storage/` | AES-256-CBC + HMAC, PBKDF2 (stdlib crypto) |
| SQLite Plugin | `src/crystal_ui/plugins/sqlite/` | Direct FFI to libsqlite3 (opt-in require) |
| WebView Adapter | `src/crystal_ui/adapters/linux/webkit_gtk.cr` | WebKitGTK 4.1, window API, devtools, drag&drop |
| Tray Adapter | `src/crystal_ui/adapters/linux/app_indicator_tray.cr` | Ayatana AppIndicator |
| Windows Adapters (stub) | `src/crystal_ui/adapters/windows/` | WebView2 + NotifyIcon placeholders |
| macOS Adapters (stub) | `src/crystal_ui/adapters/macos/` | WKWebView + StatusBar placeholders |
| Android Host (stub) | `src/crystal_ui/adapters/android/host.cr` | Mobile host placeholder |
| iOS Host (stub) | `src/crystal_ui/adapters/ios/host.cr` | Mobile host placeholder |

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
via the generic `CrystalBridge.postMessage` runtime, which the Linux adapter
wires to `window.webkit.messageHandlers.crystal.postMessage` under the hood.

## Architecture

```
┌─────────────────────────────────────────┐
│           CrystalUI Host                │
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
  crystal_ui.cr                          # Main entry point
  crystal_ui/
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
      windows/                           # Windows shims (stub)
        webview2.cr
        tray.cr
        icon.cr
        factory.cr
      macos/                             # macOS shims (stub)
        webview.cr
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
tray.set_title("CrystalUI")
tray.add_or_update_item(CrystalUI::TrayItem.new(id: 1, title: "Open"))
tray.add_separator(2)
tray.add_or_update_item(CrystalUI::TrayItem.new(id: 3, title: "Quit"))

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
  webview.create(CrystalUI::WebViewConfig.new(
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
class HelloApp < CrystalUI::Application
  def register_commands(registry)
    command_registry
  end

  @[CrystalUI::Command]
  def greet(name : String) : String
    "Hello, #{name}!"
  end
end
```

From JavaScript the runtime uses the platform-agnostic bridge:

```javascript
CrystalUI.call("greet", { name: "Crystal" }).then(result => {
  console.log(result);
});
```

The Host dispatches the call in Crystal and resolves the promise with
`window.__crystalResolve(id, success, data, error)`.

## Embedding assets & custom URI schemes

`Application#embed_directory("frontend")` bakes a whole directory tree into
the binary at compile time (Base64-encoded, binary-safe) — intended for
built web apps with hashed asset names. `Application#embed_file("assets/icon.svg")`
bakes a single file as a String. Both arguments must be plain string
literals; relative paths resolve against the compiler's working directory.

Serve the embedded tree to the WebView without any HTTP server:

```crystal
class MyApp < CrystalUI::Application
  embed_directory("frontend")

  def on_ready
    webview.register_uri_scheme("app") do |path|
      if bytes = embedded_file?(path)
        CrystalUI::SchemeResponse.new(bytes, "text/html; charset=utf-8")
      end
    end
    webview.create(CrystalUI::WebViewConfig.new(title: "MyApp", close_to_tray: false))
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
  webview.create(CrystalUI::WebViewConfig.new(title: "MyApp", close_to_tray: false))
  webview.bind("crystal") { |json| host.dispatch(json) }

  if CrystalUI::Dev.enabled?   # CRYSTAL_UI_DEV=1
    webview.load_url(serve_directory(File.join(__DIR__, "frontend")))
  else
    webview.load_html(application_html)
  end
end
```

On every dev start, typed TypeScript declarations are regenerated into
`<frontend>/crystal-ui.d.ts` from the plugin manifests and your
`@[Command]` methods.

## The `crystal-ui` CLI

```bash
rake build:cli                       # builds bin/crystal-ui

CRYSTAL_UI_PATH=/path/to/crystalui bin/crystal-ui init my-app
cd my-app && shards install
bin/crystal-ui dev                   # rebuild-if-stale + live reload
bin/crystal-ui build                 # release binary in bin/
bin/crystal-ui doctor                # toolchain and native deps check
bin/crystal-ui package [--install]   # icons, .desktop entry, AppDir/AppImage
```

## Window management

`WebViewPort` exposes a window API (`set_title`, `resize`, `center`,
min/max size, `maximize`, `fullscreen`, `set_always_on_top`,
`set_decorated(false)` for frameless, devtools) implemented by the
WebKitGTK adapter. Window changes are broadcast as events
(`window.resized`, `window.moved`, `window.maximized`, …) and forwarded
to JS. The `window` plugin exposes the same surface to the frontend:

```javascript
await CrystalUI.window.fullscreen();
CrystalUI.on("window.resized", ({width, height}) => console.log(width, height));
```

Multi-window support is intentionally out of scope.

## Events from Crystal to JS

`Host#emit_to_js(event, payload)` is the single supported channel — it
marshals to the GUI thread and notifies all `CrystalUI.on(event, …)`
subscribers. Window events, `dnd.files` (drag & drop),
`lifecycle.*`, `deep_link.opened` and plugin callbacks all use it.

## Opt-in SQLite plugin

The SQLite plugin binds libsqlite3 directly (no shard dependency).
Enable it explicitly so apps without a database don't link it:

```crystal
require "crystal_ui/plugins/sqlite/plugin"

class MyApp < CrystalUI::Application
  def configure_plugins
    register_plugin(CrystalUI::Plugins::Sqlite.new(app_id: "myapp"))
  end
end
```

```javascript
await CrystalUI.sqlite.exec(
  "CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT)");
await CrystalUI.sqlite.query("SELECT * FROM notes");
```

## License

MIT
