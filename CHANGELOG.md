# Changelog

All notable changes to Positron are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

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
- Windows/macOS CI builds: `deep_links` (unix sockets) and
  `secure_storage` (OpenSSL) plugins are now required only on unix
  targets, so Windows stub builds link no native libraries; the
  corresponding specs are flag-gated. CI installs `openssl@3` (with
  `PKG_CONFIG_PATH`) on macOS and `libsqlite3-dev` on Linux for the
  unix-gated specs, and builds the `positron` CLI on every runner.
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
