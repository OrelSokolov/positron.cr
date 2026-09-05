# Changelog

All notable changes to CrystalUI are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Relicensed the project to MIT (`LICENSE`, `shard.yml`); previously the
  LICENSE file granted non-commercial rights only while `README.md`
  claimed MIT. All three now agree on MIT.

### Added

- `CONTRIBUTING.md` with build, style and plugin authoring conventions.
- Specs for `JSFacadeGenerator`, `Host#dispatch` envelope handling and
  `Host#emit_to_js`.
- `Host#emit_to_js(event, payload)` — the single supported way to push
  events from Crystal to the frontend (main-thread marshalled); plugins
  migrated off raw `eval_js` strings. Also fixes notifications calling
  `CrystalUI.__crystalNotify`, which was only defined on `window`. (M1)
- Dev mode with live reload: `CrystalUI::Dev::AssetServer` +
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
- `crystal-ui` CLI (`src/crystal_ui/cli.cr`, `rake build:cli`): `init`,
  `dev` (rebuild-if-stale + live reload), `build`, `doctor`,
  `package`. (M2/M6)
- TypeScript bindings generation
  (`CrystalUI::BindingsGenerator`): `@[Command]` manifests from the
  `command_registry` macro, typed plugin namespaces, written to
  `<frontend>/crystal-ui.d.ts` on every dev-server start. (M2)
- Linux packaging helpers (`CrystalUI::Packaging`): `.desktop` files,
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
