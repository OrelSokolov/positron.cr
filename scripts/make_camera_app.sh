#!/bin/bash
# Build (if needed) and wrap the camera example into a minimal .app
# bundle with an NSCameraUsageDescription-bearing Info.plist, then
# codesign it ad-hoc.
#
# Why the bundle is mandatory: TCC attributes the camera-permission
# check to the "responsible process" — a binary run straight from a
# shell inherits the terminal's identity, and Terminal.app declares no
# NSCameraUsageDescription, so the system prompt never shows and
# getUserMedia fails. Inside a bundle the app itself is responsible
# and the standard permission prompt appears. (The WKUIDelegate grant
# in the macOS adapter handles the WebKit-level permission; this
# bundle handles the OS-level one.)
#
# Usage: scripts/make_camera_app.sh
#   (or `rake build:camera_app`)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/examples/camera/camera"
APP="$ROOT/builds/macos/PositronCamera.app"

if [ ! -x "$BIN" ]; then
  echo "→ building examples/camera"
  (cd "$ROOT" && crystal build examples/camera/camera.cr -o examples/camera/camera)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/PositronCamera"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.positron.camera</string>
  <key>CFBundleName</key><string>PositronCamera</string>
  <key>CFBundleExecutable</key><string>PositronCamera</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>Shows a live camera preview.</string>
  <key>NSMicrophoneUsageDescription</key><string>Can use the microphone when a page requests it.</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP" >/dev/null
  echo "→ codesigned (ad-hoc)"
fi
echo "$APP — launch with: open $APP"
