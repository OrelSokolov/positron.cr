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
| Host Abstraction | `src/crystal_ui/host.cr` | Shared base for desktop and mobile hosts |
| Application API | `src/crystal_ui/application.cr` | `on_ready`, lifecycle, deep links, permissions |
| Desktop Host | `src/crystal_ui/desktop_host.cr` | Wires WebView, tray, commands, EventBus |
| Mobile Host | `src/crystal_ui/mobile_host.cr` | Base for Android/iOS host integration |
| Linux EventLoop | `src/crystal_ui/event_loop/linux.cr` | GTK main loop + Crystal fiber idle source |
| WebView Adapter | `src/crystal_ui/adapters/linux/webkit_gtk.cr` | WebKitGTK 4.1 with generic JS bridge shim |
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
        factory.cr
      windows/                           # Windows shims (stub)
        webview2.cr
        tray.cr
        factory.cr
      macos/                             # macOS shims (stub)
        webview.cr
        tray.cr
        factory.cr
      android/                           # Android mobile host (stub)
        host.cr
        factory.cr
      ios/                               # iOS mobile host (stub)
        host.cr
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
tray.set_icon(CrystalUI::IconSource.new(File.read("icon.png").to_slice, :png))
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

## License

MIT
