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
| Application API | `src/crystal_ui/application.cr` | `on_ready`, lifecycle, deep links, permissions |
| Desktop Host | `src/crystal_ui/desktop_host.cr` | Wires WebView, tray, commands, EventBus |
| Linux EventLoop | `src/crystal_ui/event_loop/linux.cr` | GTK main loop + Crystal fiber idle source |
| WebView Adapter | `src/crystal_ui/adapters/linux/webkit_gtk.cr` | WebKitGTK 4.1 with JS bridge |
| Tray Adapter | `src/crystal_ui/adapters/linux/app_indicator_tray.cr` | Ayatana AppIndicator |
| Windows Tray Stub | `src/crystal_ui/adapters/windows/tray.cr` | `NotifyIconTray` interface placeholder |
| macOS Tray Stub | `src/crystal_ui/adapters/macos/tray.cr` | `StatusBarTray` interface placeholder |

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
via `window.webkit.messageHandlers.crystal.postMessage(...)`.

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
    application.cr                       # Application base class
    desktop_host.cr                      # Desktop wiring
    ports/                               # Abstract ports
      webview_port.cr
      tray_port.cr
    event_loop/                          # Platform event loops
      linux.cr
      factory.cr
    adapters/
      linux/                             # Linux shims
        webkit_gtk.cr
        app_indicator_tray.cr
        factory.cr
      windows/                           # Windows shims (stub)
        tray.cr
        factory.cr
      macos/                             # macOS shims (stub)
        tray.cr
        factory.cr
examples/
  hello.cr                               # Polished demo app
assets/
  crystal-icon.svg                       # Blue crystal icon
```

## Tray API

The tray follows the cross-platform design of `getlantern/systray`:

```crystal
tray.set_icon(File.read("icon.png").to_slice)
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

From JavaScript:

```javascript
window.webkit.messageHandlers.crystal.postMessage({
  id: "1",
  name: "greet",
  args: { name: "Crystal" }
});
```

The Host dispatches the call in Crystal and resolves the promise with
`window.__crystalResolve(id, success, data, error)`.

## License

MIT
