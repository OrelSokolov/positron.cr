#!/bin/bash
# Wrap any built binary into a minimal, ad-hoc codesigned .app bundle
# whose Info.plist carries NSCameraUsageDescription /
# NSMicrophoneUsageDescription. Output: builds/macos/<Name>.app
#
# Why the bundle: TCC attributes camera/microphone permission checks
# to the "responsible process" — a binary run straight from a shell
# inherits the terminal's identity, and Terminal.app declares no usage
# keys, so the system prompt never shows. Inside a bundle the app
# itself is responsible and the standard prompt appears. (The WebKit
# level of the permission is granted by the WKUIDelegate in the macOS
# adapter; this bundle covers the OS level.)
#
# Usage: scripts/create_bundle.sh <binary> [app-name] [bundle-id]
#   scripts/create_bundle.sh examples/camera/camera PositronCamera
#   <binary>    path relative to the repo root (or absolute)
#   [app-name]  defaults to the binary's basename
#   [bundle-id] defaults to dev.positron.<lowercased app-name>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

BIN="${1:?usage: create_bundle.sh <binary> [app-name] [bundle-id]}"
BIN_PATH="$BIN"
[ -f "$BIN_PATH" ] || BIN_PATH="$ROOT/$BIN"
[ -x "$BIN_PATH" ] || { echo "no such executable: $BIN" >&2; exit 1; }

NAME="${2:-$(basename "$BIN_PATH")}"
BUNDLE_ID="${3:-dev.positron.$(echo "$NAME" | tr '[:upper:]' '[:lower:]')}"
APP="$ROOT/builds/macos/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_PATH" "$APP/Contents/MacOS/$NAME"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>This app can use the camera when a page requests it.</string>
  <key>NSMicrophoneUsageDescription</key><string>This app can use the microphone when a page requests it.</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP" >/dev/null
  echo "→ codesigned (ad-hoc)"
fi
echo "$APP — launch with: open $APP"
