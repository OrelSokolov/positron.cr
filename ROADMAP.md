# Positron Roadmap: From Reference Implementation to Real Framework

This document describes what stands between the current Linux reference
implementation and a usable desktop framework in the spirit of Wails:
a batteries-included toolkit with CLI tooling, hot reload, cross-platform
WebView adapters, typed frontend bindings and packaging.

**Status 2026-09:** M0–M4 and the Linux part of M6 are implemented and
tested on Linux. M5.2 (Windows) is implemented and tested on Windows
11: real WebView2 window, event loop, tray, theme (stage 1); the M4
plugin adapters (stage 2); and the POSIX-neutral plugins — fs dirs,
deep_links single instance, secure_storage, SQLite via the system
winsqlite3 (stage 3). M5.1 (macOS) is the next block. The architecture
keeps all platform code behind ports so it stays a pure adapter job.
**Multi-window support is intentionally out of scope.**

## Where we are today

Working (Linux only):

- Host core: `EventBus`, `CommandRegistry`, `StateManager`, `PluginManager`,
  `Host`/`DesktopHost` wiring, GTK event loop with Crystal fiber integration.
- WebView adapter (WebKitGTK 4.1), tray adapter (Ayatana AppIndicator),
  custom URI schemes backed by compile-time embedded assets.
- JS runtime facade (`Positron.call/emit/on/state`) with plugin namespaces
  and `Host#emit_to_js` for Crystal → JS events.
- Dev mode: `Positron::Dev::AssetServer` + `Application#serve_directory`
  (serve `frontend/` from disk, live reload, marker substitution, TS
  bindings regenerated on start).
- Window management API on `WebViewPort` (title/size/position/fullscreen/
  always-on-top/frameless/min-max constraints, devtools) + window events.
- Plugins: clipboard, display info, file picker, save file dialog,
  keyboard, logger, notifications, preferences, theme, window,
  filesystem, dialogs, lifecycle, permissions, deep links,
  secure storage, SQLite (opt-in require).
- `positron` CLI: `init` / `dev` / `build` / `doctor` / `package`.
- Packaging helpers: `.desktop` entries, hicolor icon pipeline,
  AppDir/AppImage scaffolding, deb control templates.
- Headless specs (48+) for core, plugins, dev server, bindings,
  packaging, SQLite.

## Milestones

Ordered by dependency and impact. Effort markers are rough:
**S** ≤ 1 week, **M** 1–4 weeks, **L** 1+ month for one contributor.

---

### M0. Project hygiene (S) — ✅ done

- [x] Resolve the license contradiction — MIT everywhere (`LICENSE`,
      `shard.yml`, `README.md`).
- [x] Add a `CONTRIBUTING.md`.
- [x] Specs for `JSFacadeGenerator`, `Host#dispatch`, `emit_to_js`.
- [x] `CHANGELOG.md` (tagged releases pending — see M7).

---

### M1. Dev experience (M) — ✅ done

**1.1 Dev asset server + live reload**

- [x] `Positron::Dev::AssetServer` (`src/positron/dev/asset_server.cr`):
      serves a directory from disk over HTTP on 127.0.0.1 with mime
      detection, SPA fallback and path-traversal protection.
- [x] `Application#serve_directory(dir)` — dev counterpart of
      `embed_directory`; reloads the WebView when files change
      (mtime polling, portable).
- [x] Served HTML is rewritten to match release builds: `{{CSS}}`,
      `{{JS}}`, `{{RUNTIME_JS}}`, `{{HYDRATE_JS}}` markers substituted
      from disk; plain SPAs get the runtime injected into `<head>`.
- [x] `POSITRON_DEV=1` switches one binary between embedded and
      served assets (used by the `positron dev` scaffold).

**1.2 Formalized Crystal → JS event bridge**

- [x] `Host#emit_to_js(event, payload)` with main-thread marshalling.
- [x] All plugins migrated off raw `eval_js` notify strings (also fixed
      a bug where notifications called `Positron.__positronNotify`,
      which was only defined on `window`).

**Done when:** a developer can edit HTML/CSS/JS and see changes in the
running window without recompiling. ✅ verified by
`positron init && positron dev`.

---

### M2. CLI and typed bindings (M) — ✅ done (Linux)

**2.1 `positron` executable** (`src/positron/cli.cr`, `rake build:cli`)

- [x] `positron init <name>` — scaffold: `shard.yml` (path dep on the
      framework), `src/<name>.cr`, `src/frontend/`, icon, README.
- [x] `positron dev` — rebuild when Crystal sources are stale, then
      run with `POSITRON_DEV=1` (live reload of frontend changes).
- [x] `positron build` — release build with embedded assets.
- [x] `positron doctor` — checks crystal, GTK, WebKitGTK, AppIndicator,
      libnotify, sqlite3, icon converter, appimagetool.

**2.2 Binding generation** (`Positron::BindingsGenerator`)

- [x] `@[Command]` methods expose manifests via the `command_registry`
      macro (arg names + types from signatures).
- [x] TypeScript declarations generated from plugin + app manifests:
      typed namespaces (`Positron.fs.read(args: {path: string})`),
      type mapping String→string, Int/Float→number, Bool→boolean.
- [x] Written to `<frontend>/positron.d.ts` on every dev-server start.

**Done when:** `positron init && positron dev` gives a working app
with hot reload and TS autocomplete. ✅

---

### M3. Window API (M) — ✅ done (Linux; **multi-window dropped by design**)

- [x] `WebViewPort` window API (default raises on platforms without it):
      `set_title`, `resize`, `center`, `set_minimum_size`,
      `set_maximum_size`, `maximize`/`unmaximize`/`maximized?`,
      `fullscreen`/`unfullscreen`, `set_always_on_top`,
      `set_decorated` (frameless), `focus`, `size`, `position`.
- [x] WebKitGTK implementation incl. GdkGeometry min/max constraints.
- [x] Window events on the EventBus (`window.resized/moved/maximized/
      unmaximized/fullscreened/unfullscreened`), forwarded to JS.
- [x] Devtools: `open_devtools`/`close_devtools` (WebKitGTK inspector).
- [x] `window` plugin exposing the whole surface to the frontend
      (`Positron.window.set_title(...)` etc.).
- [~] Multi-window: **explicitly out of scope** per maintainer decision.
      If it ever lands, it changes the JS bridge envelope (window id) —
      decide before the M5 port, not after.

---

### M4. Core plugin gaps (M) — ✅ done (Linux)

From the "first 10 core" list in `top_20.txt`:

- [x] **File System Access** — `fs.*` commands, XDG dirs, optional
      `root:` sandbox with traversal protection.
- [x] **Dialogs & Alerts** — GtkMessageDialog alert/confirm/prompt,
      marshalled to the GUI thread, promise-based for JS.
- [x] **App Lifecycle** — `lifecycle` plugin: state tracking +
      `lifecycle.resumed/paused/destroyed` events to JS.
- [x] **Deep Links** — single-instance unix-socket handshake in
      `$XDG_RUNTIME_DIR`, URL forwarding to the first instance,
      `deep_link.opened` delivery (argv URLs + socket).
- [x] **Permissions Manager** — desktop trust model ("granted" always),
      stable API shape for future mobile hosts.
- [x] **Secure Storage** — AES-256-CBC + HMAC-SHA256 encrypt-then-MAC,
      PBKDF2-HMAC-SHA256 (stdlib-only crypto, RFC-vector tested),
      env or per-install key file.
- [x] **SQLite** — direct FFI to libsqlite3 (no shard), `sqlite.query/
      exec/close` with positional binds; opt-in require.
- [x] **Drag and Drop** — URI targets on the GTK window, dropped files
      forwarded as `dnd.files` events to the frontend.

---

### M5. Cross-platform: macOS and Windows (L) — ⬜ next up

The largest single chunk. The port discipline added in M3/M4 (all
platform code in `adapters/linux/`, `event_loop/linux.cr`,
`plugins/*/linux.cr` or behind `WebViewPort` defaults) keeps this a
pure adapter job.

**5.1 macOS (WKWebView)**

- [ ] Crystal ObjC bindings for `NSApplication`, `NSWindow`, `WKWebView`,
      `WKScriptMessageHandler`.
- [ ] Replace `adapters/macos/webview.cr` stub: message handler →
      `Host#dispatch`, `evaluateJavaScript` → `eval_js`,
      `WKURLSchemeHandler` for custom schemes.
- [ ] `event_loop/macos.cr`: NSRunLoop + Crystal scheduler integration.
- [ ] Tray via `NSStatusItem`; window API from M3 on NSWindow.

**5.2 Windows (WebView2)**

- [x] WebView2 window via the vendored `webview.dll` 0.12.0 C API
      (`third_party/webview/`), loaded at runtime — no import library,
      loader statically linked inside the DLL.
- [x] Win32 message loop (`event_loop/windows.cr`) with a WM_TIMER
      cooperative tick (Fiber.yield in the pump — same pattern as the
      GLib idle source on Linux); `run_on_main` via `webview_dispatch`.
- [x] `webview_bind` → `Host#dispatch`; `webview_eval` → `eval_js`
      (always marshalled to the UI thread).
- [ ] Custom asset schemes: `register_uri_scheme` raises (C API has no
      hook; future: SetVirtualHostNameToFolderMapping). Examples are
      unaffected — embedded assets are inlined into the HTML.
- [x] Tray via `Shell_NotifyIcon` (hidden message window +
      `TrackPopupMenu`, KB135788 foreground fix).
- [x] M3 window API on the Win32 HWND (subclass WndProc for
      WM_CLOSE→hide and `window.*` events); devtools: F12 in dev builds
      only (`open_devtools` raises).
- [x] Theme plugin: dark/light + accent from the registry.
- [x] M4 plugin adapters on Windows: clipboard (CF_UNICODETEXT /
      CF_HDROP / CF_DIB, images via GDI+), dialogs (MessageBoxW + a
      hand-rolled prompt window), file_picker & save_file_dialog
      (comdlg32), notifications (Shell_NotifyIcon balloons), display
      (EnumDisplayMonitors + per-monitor DPI). The keyboard plugin has
      no adapter — it is frontend-driven.
- [x] POSIX-neutral plugins on Windows: `fs` dirs from
      `USERPROFILE`/`APPDATA`/`LOCALAPPDATA`, `deep_links`
      single-instance handshake over AF_UNIX (Win10+, socket in
      `%LOCALAPPDATA%`), `secure_storage` store under `%APPDATA%`,
      opt-in SQLite against the system `winsqlite3.dll` (Win10+).

**5.3 Cross-cutting**

- [ ] Extend CI to build real adapters on macOS/Windows runners.
- [ ] Port the M3 window API and M4 plugins adapter-by-adapter;
      capability gaps must raise, not no-op.

**Done when:** `hello`, `theme_demo` and the plugin examples run natively
on macOS and Windows with feature parity for the M4 core plugins.

---

### M6. Packaging and distribution (M) — ✅ Linux done

- [x] `Positron::Packaging` (`src/positron/packaging.cr`):
      `.desktop` entry rendering/install (user-local, no root),
      hicolor icon pipeline (rsvg-convert/ImageMagick, 16–512 px),
      AppDir scaffolding + appimagetool invocation, deb control
      templates.
- [x] `positron package [--install]` ties it together (verified:
      release build → icons → .desktop → AppDir).
- [ ] AppImage end-to-end once appimagetool is available in the env.
- [ ] Windows (NSIS) and macOS (.app/dmg) templates — after M5.
- [ ] Document code signing — manual docs only.

---

### M7. Ecosystem: docs, publishing, community (M, ongoing)

- [ ] Documentation site or `docs/` tree: getting started, Host API
      reference, plugin authoring guide, bridge envelope spec,
      platform support matrix.
- [ ] Publish the shard (github + shardbox); `shard.yml` metadata.
- [ ] A real-world example app (e.g. markdown notes exercising fs +
      dialogs + preferences + SQLite).
- [ ] Tag releases (`v0.x`) and maintain `CHANGELOG.md` per release.
- [ ] Issue templates, plugin contribution guide.

---

## Non-goals (for now)

- **Multi-window.** Dropped by maintainer decision; revisit only with a
  bridge-envelope design (window ids) done up front.
- **Mobile (Android/iOS).** The architecture (`positron-architecture.md`
  §7–8) is sound; implement after the desktop story is complete.
- **Hot reload of Crystal code inside a running process.** Rebuild+relaunch
  (`positron dev`) is the pragmatic first step.
- **The full `plugins.txt` catalog.** Tier 2+ plugins come from real user
  demand; the core (M4) came first.
- **Custom rendering / non-WebView UI.** The WebView is the product.

## Suggested sequence

```
M0 ─▶ M1 ─▶ M2 ─▶ M4 ─▶ M3 ─▶ M6(Linux)   ✅ done
                          │
                          └──▶ M5 (macOS ∥ Windows)   ⬜ next
M7 runs continuously.
```

M5 ports the completed Linux story adapter-by-adapter; the API surface
(ports, plugin manifests, bridge envelope) is now considered stable
enough to port against.
