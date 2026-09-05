# Contributing to CrystalUI

Thanks for your interest in contributing!

## Getting started

```bash
# Install build dependencies (Ubuntu/Debian)
sudo apt install crystal libgtk-3-dev libwebkit2gtk-4.1-dev \
  libayatana-appindicator3-dev libnotify-dev

# Build all examples (writes logs to logs/)
rake build:examples

# Run the test suite (headless, no GUI required)
rake spec
```

All 8 examples must build cleanly and all specs must pass before a change
is considered done.

## Code conventions

- **Linux is the only working platform.** Windows, macOS, Android, iOS
  adapters exist as stubs — do not assume they work.
- **Platform code stays behind ports.** Any GTK/WebKit/native call belongs
  in `src/crystal_ui/adapters/linux/`, `src/crystal_ui/event_loop/linux.cr`
  or `src/crystal_ui/plugins/*/linux.cr`. Core files (`host.cr`,
  `application.cr`, `command_registry.cr`, `event_bus.cr`,
  `state_manager.cr`, `js_facade_generator.cr`) must stay platform-pure —
  non-Linux ports depend on that.
- **Plugins expose two things and they must stay in sync:** a `manifest`
  (used by JS facade / TypeScript bindings generation) and the commands
  registered in `bind`. Every command registered in `bind` must appear in
  the manifest with matching argument names.
- **Never hand-roll `eval_js` strings to push events to the frontend.**
  Use `Host#emit_to_js(event, payload)`.
- Match the surrounding style: `crystal tool format` before committing,
  keep FFI `lib` declarations local to the adapter that uses them.

## Adding a plugin

1. Create `src/crystal_ui/plugins/<name>/plugin.cr` (subclass
   `CrystalUI::Plugin`, define `name`, `supported_platforms`, `manifest`,
   `bind`).
2. Add platform adapters (`linux.cr`, plus stubs for other platforms) and
   a `factory.cr` that selects one at compile time via target flags.
3. Register commands in `bind`, list them in `manifest`.
4. Add a headless spec where possible (command dispatch, state handling).
5. Wire the plugin require into `src/crystal_ui.cr` and, if it ships a
   demo, an example under `examples/`.

## Commit style

Short imperative subject line, optional body explaining *why*. Reference
the milestone from `ROADMAP.md` when relevant, e.g.
`M1: add dev asset server with live reload`.

## Reporting bugs

Include: OS, WebKitGTK version (`pkg-config --modversion webkit2gtk-4.1`),
Crystal version, a minimal reproducer, and relevant logs from `logs/`.
