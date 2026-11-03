#!/bin/zsh
# Build a Positron app for the iOS simulator (arm64), install and
# launch it. Mirrors the egui.cr iOS pipeline (phases 2–4 of
# egui.cr/plans/IOS_SUPPORT_PLAN.md).
#
# Prerequisites (all from the egui.cr iOS toolchain, reused verbatim):
#   IOS_CRYSTAL    patched Crystal compiler built for ios targets
#                  (default ~/egui.cr/tmp/crystal-ios/.build/crystal;
#                  its src/ provides the patched stdlib whose
#                  `flag?(:ios)` entry symbol is crystal_main_entry)
#   IOS_LIBDIR     prebuilt static libs for the simulator:
#                  libgc.a (bdwgc, GC_DARWIN_THREADS) and
#                  libpcre2-8.a (pcre2, no JIT)
#                  (default ~/egui.cr/tmp/ios)
#
#   libgc MUST be built with -Denable_large_config=ON (MAX_ROOT_SETS
#   8192 instead of the default 2048). Boehm's dyld callback registers
#   the __DATA/__bss sections of every loaded image; a simulator app
#   under recent runtimes sits at ~1500 root sets at idle and ~1900
#   once WebKit warms up, so the first runtime dlopen that crosses
#   2048 (e.g. DataDetectorsUILibrary, soft-linked by UIKit's text
#   edit menu) aborts with "Too many root sets" (SIGABRT from
#   GC_add_roots_inner). Rebuild with:
#     cmake -S <bdwgc> -B <bdwgc>/build-ios-sim -Denable_large_config=ON
#     cmake --build <bdwgc>/build-ios-sim --target gc
#   Xcode          DEVELOPER_DIR is exported below; xcode-select may
#                  point at CommandLineTools
#
# Usage:
#   ios/build_ios.sh                          # hello example
#   ios/build_ios.sh examples/hello/hello.cr  # explicit source
#
# Environment overrides: APP_BUNDLE_ID (default cr.positron.hello),
# SIMULATOR (default "iPhone 17 Pro"). Add LAUNCH=0 to skip install
# and launch.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

SOURCE="${1:-examples/hello/hello.cr}"
APP_EXECUTABLE="positron_app"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-cr.positron.hello}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Positron}"
SIMULATOR="${SIMULATOR:-iPhone 17 Pro}"
IOS_CRYSTAL="${IOS_CRYSTAL:-$HOME/egui.cr/tmp/crystal-ios/.build/crystal}"
IOS_CRYSTAL_SRC="$(cd "$(dirname "$IOS_CRYSTAL")/.." && pwd)/src"
IOS_LIBDIR="${IOS_LIBDIR:-$HOME/egui.cr/tmp/ios}"
DEPLOYMENT_TARGET=17.0

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

if [[ ! -x "$IOS_CRYSTAL" ]]; then
  echo "error: patched Crystal compiler not found: $IOS_CRYSTAL" >&2
  echo "       (see the header of ios/build_ios.sh)" >&2
  exit 1
fi
for lib in bdwgc/build-ios-sim/libgc.a pcre2/build-ios-sim/libpcre2-8.a; do
  if [[ ! -f "$IOS_LIBDIR/$lib" ]]; then
    echo "error: simulator library missing: $IOS_LIBDIR/$lib" >&2
    exit 1
  fi
done

BUILD=build/ios
mkdir -p "$BUILD"

# 1) Cross-compile the app (object file only; we link ourselves).
#    The patched compiler miscompiles HOST release binaries (the
#    `run()` macro helpers it builds crash with `kevent: ENOENT` on
#    this machine — verified against hello release builds), so after
#    the patched compiler has written its cache manifests we replace
#    the cached macro_run helpers with builds from a working host
#    crystal and retry. The cache reuse check only compares the
#    requires manifests + mtimes, so this is transparent to it.
HOST_CRYSTAL="${HOST_CRYSTAL:-$(command -v crystal || true)}"
[[ -n "$HOST_CRYSTAL" ]] || HOST_CRYSTAL=/opt/homebrew/bin/crystal
[[ -x "$HOST_CRYSTAL" ]] || {
  echo "error: no working host crystal found (needed to rebuild macro helpers)" >&2
  exit 1
}

replace_macro_helpers() {
  for src in src/positron/*.cr; do
    # Cache dirs are named from the absolute path with "/" → "-"; the
    # leading "/" of $PWD becomes a leading dash Crystal does NOT use.
    cache_dir="$HOME/.cache/crystal/$(echo "${PWD#/}/$src" | tr / -)"
    if [[ -d "$cache_dir" && -f "$cache_dir/requires" ]]; then
      if "$HOST_CRYSTAL" build --no-color -o "$cache_dir/macro_run" "$src" >/dev/null 2>&1; then
        echo "    (rebuilt helper: $src)"
      else
        echo "    (helper rebuild FAILED: $src)" >&2
      fi
    fi
  done
}

OBJ="$BUILD/app.o"
echo "==> cross-compiling $SOURCE"
cross_ok=0
for attempt in 1 2 3; do
  if CRYSTAL_PATH="$ROOT/src:$IOS_CRYSTAL_SRC" \
      "$IOS_CRYSTAL" build --cross-compile --no-color \
      --target="arm64-apple-ios${DEPLOYMENT_TARGET}-simulator" \
      -o "$BUILD/app" "$SOURCE" >"$BUILD/cross.log" 2>&1; then
    cross_ok=1
    break
  fi
  if grep -q "Error executing run" "$BUILD/cross.log"; then
    echo "    (macro helper cache poisoned by release miscompile; replacing helpers, attempt $attempt)"
    replace_macro_helpers
  else
    cat "$BUILD/cross.log"
    exit 1
  fi
done
if [[ "$cross_ok" != 1 ]]; then
  echo "error: cross-compilation still failing after macro-helper replacement" >&2
  cat "$BUILD/cross.log"
  exit 1
fi
[[ -f "$OBJ" ]] || { echo "error: cross-compilation produced no object file" >&2; cat "$BUILD/cross.log"; exit 1; }

# 2) Link: driver + app + Boehm + PCRE2 + UIKit/WebKit frameworks.
echo "==> linking $APP_EXECUTABLE"
cc -O2 -target "arm64-apple-ios${DEPLOYMENT_TARGET}-simulator" -isysroot "$SDK" \
  ios/main.c "$OBJ" \
  "$IOS_LIBDIR/pcre2/build-ios-sim/libpcre2-8.a" \
  "$IOS_LIBDIR/bdwgc/build-ios-sim/libgc.a" \
  -liconv -lz \
  -framework UIKit -framework Foundation -framework WebKit \
  -framework UniformTypeIdentifiers \
  -framework CoreFoundation -framework CoreGraphics \
  -framework CoreMedia -framework CoreVideo \
  -o "$BUILD/$APP_EXECUTABLE"

# 3) Bundle.
APP_DIR="$BUILD/${APP_EXECUTABLE}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp "$BUILD/$APP_EXECUTABLE" "$APP_DIR/"
sed -e "s/\${APP_EXECUTABLE}/$APP_EXECUTABLE/g" \
    -e "s/\${APP_BUNDLE_ID}/$APP_BUNDLE_ID/g" \
    -e "s/\${APP_DISPLAY_NAME}/$APP_DISPLAY_NAME/g" \
    ios/Info.plist > "$APP_DIR/Info.plist"

if [[ "${LAUNCH:-1}" != "1" ]]; then
  echo "bundle: $ROOT/$APP_DIR"
  exit 0
fi

# 4) Install + launch in the simulator. Launch is fire-and-forget:
#    the app runs UIApplicationMain forever; use `simctl launch
#    --console-pty booted <bundle>` manually to stream its stdout.
echo "==> launching in simulator: $SIMULATOR"
xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
xcrun simctl uninstall booted "$APP_BUNDLE_ID" 2>/dev/null || true
xcrun simctl install booted "$APP_DIR"
xcrun simctl launch booted "$APP_BUNDLE_ID"
echo "launched: $APP_BUNDLE_ID (bundle: $ROOT/$APP_DIR)"
xcrun simctl io booted screenshot build/ios/shot.png 2>/dev/null || true
sleep 3
xcrun simctl io booted screenshot build/ios/shot.png
echo "screenshot: $ROOT/build/ios/shot.png"
