# CrystalUI Roadmap: From Reference Implementation to Real Framework

This document describes what stands between the current Linux reference
implementation and a usable desktop framework in the spirit of Wails:
a batteries-included toolkit with CLI tooling, hot reload, cross-platform
WebView adapters, typed frontend bindings and packaging.

## Where we are today

Working (Linux only):

- Host core: `EventBus`, `CommandRegistry`, `StateManager`, `PluginManager`,
  `Host`/`DesktopHost` wiring, GTK event loop with Crystal fiber integration.
- WebView adapter (WebKitGTK 4.1), tray adapter (Ayatana AppIndicator),
  custom URI schemes backed by compile-time embedded assets.
- JS runtime facade (`CrystalUI.call/emit/on/state`) with plugin namespaces.
- Plugins: clipboard, display info, file picker, save file dialog,
  keyboard, logger, notifications, preferences, theme.
- Headless specs for `EventBus`, `CommandRegistry`, `StateManager`.

Known gaps (see also `AGENTS.md`): no CLI, no dev mode, no hot reload,
non-Linux adapters are stubs, no window management API, no packaging
story, thin test coverage.

## Milestones

Ordered by dependency and impact. Effort markers are rough:
**S** ≤ 1 week, **M** 1–4 weeks, **L** 1+ month for one contributor.

---

### M0. Project hygiene (S)

Unblock everything that touches publishing and contributions.

- [ ] Resolve the license contradiction: `shard.yml` says `Non-Commercial`,
      `README.md` and `LICENSE` say MIT. Pick one (MIT recommended) and
      align all three files.
- [ ] Add a `CONTRIBUTING.md` (build commands, spec expectations,
      plugin manifest/`bind` sync rule from `AGENTS.md`).
- [ ] Set up test coverage for what exists: adapter-independent specs for
      `JSFacadeGenerator` (runtime JS generation, namespace grouping),
      `Host#dispatch` (command / event / fallback envelopes), plugin
      manifest→`bind` consistency.
- [ ] Tag releases (`v0.x`) and maintain a `CHANGELOG.md`.

**Done when:** license is unambiguous, `rake spec` covers the core beyond
the 3 existing spec files, and there is at least one tagged release.

---

### M1. Dev experience: asset server, hot reload, event bridge (M)

The single biggest usability gap. Today all assets are baked into the
binary at compile time (`Application#embed_directory`), so every frontend
change requires a full Crystal rebuild. No framework can be used that way.

**1.1 Dev asset server**

- [ ] Add an opt-in in-process HTTP server (`src/crystal_ui/dev/`) that
      serves `frontend/` from disk instead of embedded assets:
      - `Application#serve_directory(dir)` — runtime counterpart of
        `embed_directory`, dev builds only.
      - Mime type detection, SPA fallback (serve `index.html` for unknown
        paths), optional `--port`.
      - WebView loads `http://127.0.0.1:<port>/` in dev mode instead of
        the custom URI scheme.
- [ ] Make `Application` choose serving mode from an environment variable
      (`CRYSTAL_UI_DEV=1`) or a compile flag, so the same binary works in
      both modes.

**1.2 Live reload**

- [ ] File watcher on the served directory (inotify on Linux; keep the
      interface portable for later kqueue/ReadDirectoryChangesW adapters).
- [ ] Inject a small reload client in dev mode (via the existing
      `inject_js_runtime` path): on change → `location.reload()` for
      content, or HMR-style partial reload if the frontend provides it.
- [ ] Crystal-side restart story: document that backend changes still
      require recompile; optionally auto-rebuild+relaunch when the entry
      source tree changes (a `crystal-ui dev` concern, M2).

**1.3 Formalize the Crystal → JS event bridge**

The JS side already has `__crystalNotify`, but plugins hand-roll
`eval_js` strings (see `plugins/save_file_dialog/plugin.cr`,
`plugins/file_picker/plugin.cr`).

- [ ] Add a public `Host#emit_to_js(event : String, payload)` that wraps
      `eval_js` + JSON encoding, with automatic main-thread marshalling
      via `run_on_main`.
- [ ] Migrate all plugins to `emit_to_js` and remove ad-hoc eval strings.
- [ ] Spec: emitting from a non-main fiber is safe (no GTK re-entrancy).

**Done when:** a developer can edit HTML/CSS/JS and see changes in the
running window without recompiling, and plugins push events through one
API.

---

### M2. CLI and typed bindings (M–L)

**2.1 `crystal-ui` executable**

- [ ] New target in `shard.yml` building `bin/crystal-ui` from
      `src/crystal_ui/cli/`. Commands:
      - `crystal-ui init <name>` — scaffold `shard.yml`, `src/app.cr`,
        `frontend/` (plain HTML or a vite template), icon assets.
      - `crystal-ui dev` — build (if stale) + run with dev asset server,
        watch entry sources, rebuild on backend change.
      - `crystal-ui build` — release build with embedded assets.
      - `crystal-ui doctor` — check Crystal version, GTK/WebKit/AppIndicator
        dev packages, report what is missing.

**2.2 Binding generation**

- [ ] At build/dev time, reflect over `@[Command]` methods (the macro
      infrastructure in `command_registry.cr` already captures them) and
      emit a TypeScript declaration file:
      - `CrystalUI.call` overload per command with inferred arg and
        return types where expressible in TS.
      - Plugin namespaces matching the generated JS facade.
- [ ] Write output to `frontend/crystal-ui.d.ts` (configurable path).
- [ ] Document the mapping rules (Crystal union types → TS unions,
      `JSON::Any` → `unknown`, nilable → `T | null`).

**Done when:** `crystal-ui init && crystal-ui dev` gives a working app
with hot reload, and TS autocomplete for app commands works in the
scaffolded frontend.

---

### M3. Window API (M)

The current surface is one window configured once
(`WebViewConfig#title/width/height/close_to_tray`). Real apps need more.

- [ ] Extend `WebViewPort` and `ports/` with a `WindowPort`-level API
      (keep it abstract so macOS/Windows can implement it later):
      - `set_title`, `resize`, `center`, `set_minimum_size`,
        `set_maximum_size`, `focus`, `hide/show`, `is_visible`.
      - `fullscreen` / `unfullscreen`, `set_always_on_top`.
      - `set_icon(icon_source)` at runtime.
- [ ] Window lifecycle events into the EventBus: `window.resized`,
      `window.moved`, `window.maximized`, `window.restored`,
      `window.fullscreened`.
- [ ] Frameless window support (GTK: `GtkWindow` decorations toggle;
      document CSS-region dragging for the frontend).
- [ ] Multi-window: `Host#create_window(config) : WebViewPort` returning
      an id-addressable surface; command responses routed by window id.
      This requires threading a window id through the JS bridge envelope
      — design the envelope change together with M5 adapter work.
- [ ] Native context menu / devtools toggle: WebKitGTK
      `webkit_web_view_get_inspector` wiring behind a dev flag.

**Done when:** the `theme_demo` example demonstrates runtime window
control, and window events are observable from JS.

---

### M4. Core plugin gaps (M)

From our own `top_20.txt` "first 10 core" list, these are missing:

- [ ] **File System Access** — app dirs (`XDG_*` on Linux), temp, read,
      write, exists, list. Pure Crystal + `XDG` handling; no adapter needed.
- [ ] **Dialogs & Alerts** — alert/confirm/prompt via GTK
      `GtkMessageDialog` on the main thread; JS-facing wrappers that
      return promises through the existing command bridge.
- [ ] **App Lifecycle** — formalize `window.focused/blurred` wiring in
      `Host#wire_event_bus` into documented `lifecycle.*` events plus
      terminate handling (`close_to_tray: false` path).
- [ ] **Deep Links** — Linux: `.desktop` `MimeType`/`Exec` registration
      helpers + single-instance handshake (DBus or socket lock) that
      forwards the URL to a running instance.
- [ ] **Permissions Manager** — desktop stub that reports "granted"
      always (mobile hosts will override); keeps API shape stable.
- [ ] **Secure Storage** — `libsecret` adapter on Linux with a
      file-encrypted fallback for WM-less environments.
- [ ] **SQLite** — wrap `crystal-sqlite3` (add as optional dependency
      behind a require guard so the core stays dependency-free).
- [ ] **Drag and Drop** — WebKitGTK `drag-data-received` → EventBus →
      `emit_to_js('dnd.files', ...)`.

**Done when:** every item in the "first 10" list of `top_20.txt` is
implemented on Linux, each with a headless spec where possible.

---

### M5. Cross-platform: macOS and Windows (L)

The largest single chunk. Keep the host core platform-pure (it already
is — platform code lives in `adapters/` and `event_loop/`).

**5.1 macOS (WKWebView)**

- [ ] Crystal ObjC bindings (`@[Link(framework: ...)]` libs) for
      `NSApplication`, `NSWindow`, `WKWebView`, `WKScriptMessageHandler`.
- [ ] `adapters/macos/webview.cr`: replace the stub — script message
      handler → `Host#dispatch`, `evaluateJavaScript` → `eval_js`,
      custom URI scheme via `WKURLSchemeHandler`.
- [ ] `event_loop/macos.cr`: NSRunLoop + Crystal scheduler integration
      (the CFRunLoop-source approach outlined in
      `crystal-ui-architecture.md` §4).
- [ ] Tray via `NSStatusItem`.

**5.2 Windows (WebView2)**

- [ ] Use the official WebView2 C API (ICoreWebView2*) via FFI — no C++
      shim needed; loader `CreateCoreWebView2EnvironmentWithOptions`.
- [ ] Win32 window creation + message loop in `event_loop/windows.cr`
      with the PeekMessage/UV_NOWAIT cooperative pattern from the
      architecture doc.
- [ ] `WebMessageReceived` → `Host#dispatch`; `ExecuteScript` →
      `eval_js`; `SetVirtualHostNameToFolderMapping` for embedded assets.
- [ ] Tray via `Shell_NotifyIcon`.

**5.3 Cross-cutting**

- [ ] CI already builds non-Linux against stubs; extend it to build real
      adapters on macOS/Windows runners with SDKs installed.
- [ ] Audit plugin factories (`plugins/*/factory.cr`) so each platform
      either has a real implementation or an explicit
      `PlatformNotSupported` error — no silent no-op stubs.

**Done when:** `hello`, `theme_demo` and the plugin examples run natively
on macOS and Windows with feature parity for the M4 core plugins.

---

### M6. Packaging and distribution (M)

- [ ] `crystal-ui package` (or extend `build`):
      - Linux: AppImage (appimage tooling), `.desktop` file + icon
        install, deb metadata helpers.
      - Windows: NSIS installer template, version-info resource, icon
        embedded in the exe.
      - macOS: `.app` bundle layout, Info.plist generation, ad-hoc
        signing, dmg.
- [ ] Icon pipeline: generate `.png` sizes + `.ico` from the master
      `.svg` at package time (we already have per-platform
      `IconSource` format selection).
- [ ] Document code signing (Windows Authenticode, macOS notarization)
      without building infrastructure for it.

**Done when:** one command produces a distributable artifact per platform
from an application directory.

---

### M7. Ecosystem: docs, publishing, community (M, ongoing)

- [ ] Documentation site or a well-structured `docs/` tree: getting
      started, Host API reference, plugin authoring guide, bridge
      envelope spec, platform support matrix.
- [ ] Publish the shard to the crystal-shards ecosystem (github + entry
      in shardbox); `shard.yml` metadata complete.
- [ ] A real-world example app (not a demo): e.g. a small markdown notes
      app exercising fs + dialogs + preferences + updater-less releases.
- [ ] Issue templates, `good first issue` labeling, and a plugin
      contribution guide (manifest/`bind` sync, spec requirements).

---

## Non-goals (for now)

- **Mobile (Android/iOS).** The architecture (`crystal-ui-architecture.md`
  §7–8) is sound; the cost is a separate project. Keep the `mobile_host`
  abstraction and JNI/C-ABI entry point designs, implement after the
  desktop story is complete.
- **Hot reload of Crystal code inside a running process.** Rebuild+relaunch
  (M2) is the pragmatic first step.
- **The full `plugins.txt` catalog.** Tier 2+ plugins come from real user
  demand; the core (M4) comes first.
- **Custom rendering / non-WebView UI.** The WebView is the product.

## Suggested sequence

```
M0 ──▶ M1 ──▶ M2 ──▶ M4 ──▶ M3 ──▶ M6
                │
                └────▶ M5 (macOS ∥ Windows, independent of M3/M4)
M7 runs continuously from M1 onward.
```

Rationale: dev experience (M1) makes the framework usable and makes every
later milestone faster to build and verify; CLI/bindings (M2) lock in the
public API shape before multi-platform work multiplies the cost of API
changes; core plugins (M4) and window API (M3) complete the Linux story
that then gets ported in M5.
