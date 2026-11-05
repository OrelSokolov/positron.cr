#!/bin/bash
# Build a Positron APK (arm64): cross-compile the Crystal host, link it
# with the C seam, dex the Java shim and package with aapt — no gradle,
# no androidx (the perevodilka APK pipeline).
#
#   android/build_android.sh                          # hello example
#   APP=examples/hello/hello.cr android/build_android.sh
#   OPT= android/build_android.sh                      # dev (no --release)
#
# Requirements: crystal >= 1.10, JDK (javac/keytool/d8 via build-tools),
# Android SDK (ANDROID_SDK, default ~/android-sdk on Linux,
# ~/Library/Android/sdk on macOS) with NDK 25.2, build-tools 34+,
# platform 34, rsvg-convert or ImageMagick (launcher icon).
#
# Per-example identity (like the iOS pipeline): APP_ID (default
# crystal.positron.<source basename>) and APP_LABEL — several examples
# can coexist on one device.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$ROOT/android"
APP="${APP:-$ROOT/examples/hello/hello.cr}"
BUILD="$HERE/build"
APKDIR="$HERE/apk"
RES="$HERE/res"

SDK="${ANDROID_SDK:-}"
if [ -z "$SDK" ]; then
  if [ -d "$HOME/android-sdk" ]; then SDK="$HOME/android-sdk"
  elif [ -d "$HOME/Library/Android/sdk" ]; then SDK="$HOME/Library/Android/sdk"
  else echo "ERROR: no Android SDK (set ANDROID_SDK)"; exit 1; fi
fi
NDK="${ANDROID_NDK:-$SDK/ndk/25.2.9519653}"
[ -d "$NDK" ] || { echo "ERROR: no Android NDK at $NDK"; exit 1; }
BT="$SDK/build-tools/34.0.0"
[ -x "$BT/aapt" ] || { echo "ERROR: no build-tools 34.0.0 in $SDK"; exit 1; }
PLATFORM_JAR="$SDK/platforms/android-34/android.jar"
[ -f "$PLATFORM_JAR" ] || { echo "ERROR: no platforms/android-34 in $SDK"; exit 1; }

# NDK prebuilt host tag (macOS hosts run the x86_64 toolchain under
# Rosetta — NDK 25 ships no darwin-aarch64).
case "$(uname -s)" in
  Darwin) HOST_TAG=darwin-x86_64 ;;
  *)      HOST_TAG=linux-x86_64 ;;
esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
CC="$TOOLCHAIN/bin/clang"

# JDK: any javac <= 17 (JAVA_HOME, the macOS JVM registry, Homebrew's
# keg-only openjdk, PATH — in that order). javac 21+ emits
# MethodParameters entries with a NULL parameter name for the
# anonymous-class constructor params, and that crashes the d8 shipped
# in build-tools 34 (R8 8.2.2-dev NPE: "Cannot invoke String.length()").
# The build-tools wrappers (d8/apksigner) also need a plain `java` on
# PATH. Only a >= 21 JDK installed? We use it with a warning.
find_java() {
  local -a cands=()
  local dir major
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
    cands+=("$JAVA_HOME/bin")
  fi
  if [ "$(uname -s)" = "Darwin" ] && /usr/libexec/java_home >/dev/null 2>&1; then
    cands+=("$(/usr/libexec/java_home)/bin")
  fi
  for brew_java in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17 \
                   /opt/homebrew/opt/openjdk /usr/local/opt/openjdk; do
    [ -x "$brew_java/bin/javac" ] && cands+=("$brew_java/bin")
  done
  # A bare `command -v` is not enough on macOS: /usr/bin/javac is a
  # stub that only prints "Unable to locate a Java Runtime" and exits 1.
  if command -v javac >/dev/null && javac -version >/dev/null 2>&1; then
    cands+=("$(dirname "$(command -v javac)")")
  fi

  if [ "${#cands[@]}" -gt 0 ]; then
    for dir in "${cands[@]}"; do
      major="$("$dir/javac" -version 2>&1 | awk '{print $2}')"; major="${major%%.*}"
      if [ "$major" -le 17 ] 2>/dev/null; then
        export PATH="$dir:$PATH"; return 0
      fi
    done
    echo "WARNING: no javac <= 17 found — using ${cands[0]}/javac," \
         "whose class files crash the d8 in build-tools 34 (install openjdk@17)"
    export PATH="${cands[0]}:$PATH"; return 0
  fi
  echo "ERROR: no JDK found (javac/keytool) — install one or set JAVA_HOME"; exit 1
}
find_java

# Per-example identity from the source path (examples/<name>/<name>.cr).
# The rake tasks pass a prettified APP_LABEL; the default is the basename.
APP_BASE="$(basename "$APP" .cr)"
APP_ID="${APP_ID:-crystal.positron.$APP_BASE}"
APP_LABEL="${APP_LABEL:-$APP_BASE}"

API=28
TRIPLE=aarch64-linux-android
RUNTIME="$ROOT/third_party/android"

mkdir -p "$BUILD" "$APKDIR/lib/arm64-v8a" "$RES/drawable"

log() { printf '\033[1;35m▶ %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- icon
make_icon() {
  [ -s "$RES/drawable/icon.png" ] && return 0
  local svg="$ROOT/assets/crystal-icon.svg"
  [ -f "$svg" ] || { echo "ERROR: no icon source at $svg"; exit 1; }
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w 192 -h 192 "$svg" -o "$RES/drawable/icon.png"
  elif command -v convert >/dev/null; then
    convert -background none -density 384 "$svg" -resize 192x192 "$RES/drawable/icon.png"
  else
    echo "ERROR: need rsvg-convert or ImageMagick for the launcher icon"; exit 1
  fi
}

# --------------------------------------------------------------- crystal
build_crystal() {
  log "cross-compiling Crystal → $BUILD/positron.o (${OPT:---release})"
  (cd "$ROOT" && ANDROID_PLATFORM=$API crystal build --cross-compile ${OPT:---release} \
    --target=$TRIPLE -o "$BUILD/positron.o" "$APP")
}

build_shim() {
  log "compiling the C seam (NDK clang, $TRIPLE$API)"
  # -funwind-tables: Crystal raises walking back through these C
  # frames need CFI; without it libunwind's FDE parsing crashes.
  "$CC" --target=$TRIPLE$API -O2 -fPIC -funwind-tables -c "$HERE/positron_shim.c" -o "$BUILD/positron_shim.o"
}

build_dex() {
  log "javac + d8 (activity + bridge)"
  rm -rf "$BUILD/classes"; mkdir -p "$BUILD/classes"
  javac --release 8 -nowarn -cp "$PLATFORM_JAR" -d "$BUILD/classes" \
    $(find "$HERE/src" -name '*.java')
  local d8="$SDK/build-tools/35.0.0/d8"
  [ -x "$d8" ] || d8="$BT/d8"
  "$d8" --release --lib "$PLATFORM_JAR" --output "$APKDIR" \
    $(find "$BUILD/classes" -name '*.class')
}

link_and_pack() {
  log "linking libpositron_android.so"
  "$CC" --target=$TRIPLE$API -shared \
    -o "$APKDIR/lib/arm64-v8a/libpositron_android.so" \
    "$BUILD/positron.o" "$BUILD/positron_shim.o" \
    -L"$RUNTIME" -lgc -lpcre2-8 -levent -lssl -lcrypto \
    -llog -landroid -lz -lm -ldl -lcamera2ndk -lmediandk

  # sanity: the JNI entry points must be exported. NOTE: plain grep
  # (not -q) — with `set -o pipefail`, grep -q closing the pipe early
  # SIGPIPEs llvm-nm and fails the build on big libraries.
  "$TOOLCHAIN/bin/llvm-nm" -D --defined-only "$APKDIR/lib/arm64-v8a/libpositron_android.so" \
    | grep positron_android_host_main > /dev/null \
    || { echo "ERROR: libpositron_android.so without the host entry"; exit 1; }

  log "packaging APK (aapt + zipalign + apksigner) — $APP_ID / $APP_LABEL"
  # Per-example identity: stamp the package id + label into a build-tree
  # copy of the manifest (several examples coexist on one device).
  sed -e "s/crystal\.positron\.hello/$APP_ID/g" \
      -e "s/Positron Hello/$APP_LABEL/g" \
      "$HERE/AndroidManifest.xml" > "$BUILD/AndroidManifest.xml"
  if [ ! -f "$HERE/debug.keystore" ]; then
    keytool -genkeypair -keystore "$HERE/debug.keystore" -storepass android \
      -keypass android -alias androiddebugkey \
      -dname "CN=Android Debug,O=Android,C=US" \
      -keyalg RSA -keysize 2048 -validity 10000
  fi
  "$BT/aapt" package -f \
    -M "$BUILD/AndroidManifest.xml" \
    -I "$PLATFORM_JAR" \
    -S "$RES" \
    -F "$HERE/positron.unaligned.apk" \
    "$APKDIR"
  "$BT/zipalign" -f 4 "$HERE/positron.unaligned.apk" "$HERE/positron.apk"
  "$BT/apksigner" sign --ks "$HERE/debug.keystore" --ks-pass pass:android \
    --ks-key-alias androiddebugkey --ks-pass pass:android \
    "$HERE/positron.apk"
}

cd "$ROOT"
make_icon
build_crystal
build_shim
build_dex
link_and_pack

echo
echo "APK DONE: $HERE/positron.apk ($(du -h "$HERE/positron.apk" | cut -f1))"
echo "install:  adb install -r $HERE/positron.apk"
