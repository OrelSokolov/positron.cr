#!/bin/zsh
# Build + run the +[AVCaptureDevice authorizationStatusForMediaType:]
# segfault reproducer (ios/repro_auth_status.cr) — fully automatic, no
# user interaction: every step is appended to
# /private/tmp/repro_auth.log, which survives the crash.
#
# Usage:
#   ios/repro_auth_status.sh          # build, then run variant 1
#   VARIANT=7 ios/repro_auth_status.sh
#
# Requires the egui.cr iOS toolchain (see ios/build_ios.sh header) and
# a booted simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

VARIANT="${VARIANT:-1}"
IOS_CRYSTAL="${IOS_CRYSTAL:-$HOME/egui.cr/tmp/crystal-ios/.build/crystal}"
IOS_CRYSTAL_SRC="$HOME/egui.cr/tmp/crystal-ios/src"
IOS_LIBDIR="${IOS_LIBDIR:-$HOME/egui.cr/tmp/ios}"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export PATH=/opt/homebrew/bin:$PATH
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

BUILD=build/ios-repro
mkdir -p "$BUILD"

echo "==> cross-compiling repro"
CRYSTAL_PATH="$IOS_CRYSTAL_SRC" "$IOS_CRYSTAL" build --cross-compile --no-color \
  --target="arm64-apple-ios17.0-simulator" \
  -o "$BUILD/repro" ios/repro_auth_status.cr

echo "==> linking (AVFoundation linked directly, -rdynamic for symbols)"
cc -O2 -rdynamic -target "arm64-apple-ios17.0-simulator" -isysroot "$SDK" \
  ios/main.c "$BUILD/repro.o" \
  "$IOS_LIBDIR/pcre2/build-ios-sim/libpcre2-8.a" \
  "$IOS_LIBDIR/bdwgc/build-ios-sim/libgc.a" \
  -liconv -lz \
  -framework Foundation -framework AVFoundation \
  -o "$BUILD/positron_app"

APP_DIR="$BUILD/positron_app.app"
rm -rf "$APP_DIR"; mkdir -p "$APP_DIR"
cp "$BUILD/positron_app" "$APP_DIR/"
sed -e "s/\${APP_EXECUTABLE}/positron_app/g" \
    -e "s/\${APP_BUNDLE_ID}/cr.positron.repro/g" \
    -e "s/\${APP_DISPLAY_NAME}/Repro/g" \
    ios/Info.plist > "$APP_DIR/Info.plist"

echo "==> install + run variant $VARIANT"
xcrun simctl uninstall booted cr.positron.repro 2>/dev/null || true
xcrun simctl install booted "$APP_DIR"
rm -f /private/tmp/repro_auth.log
SIMCTL_CHILD_VARIANT="$VARIANT" xcrun simctl launch --console-pty booted cr.positron.repro \
  > "$BUILD/console.log" 2>&1 || true
sleep 2
echo "--- /private/tmp/repro_auth.log ---"
cat /private/tmp/repro_auth.log 2>/dev/null || echo "NO LOG"
echo "--- console (crash dump) ---"
strings "$BUILD/console.log" | grep -m1 "Invalid memory access" || echo "(no crash)"
