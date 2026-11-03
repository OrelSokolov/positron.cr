# Static libraries for the Android (aarch64) port

Vendored binaries — the same precedent as `third_party/webview/webview.dll`
for the Windows port. The APK link step needs these built for
`aarch64-linux-android`; the Android NDK does not ship them and there
is no system package:

- `libgc.a` — Boehm GC (Crystal runtime)
- `libpcre2-8.a` — PCRE2 (Crystal regex)
- `libevent.a` — libevent (Crystal fiber scheduler on Android)
- `libssl.a` / `libcrypto.a` — OpenSSL 3.4.1: the Crystal stdlib's
  HTTP/TLS surface (pulled in by the framework's dev asset server
  require) references SSL_* symbols, so every APK links them statically

## Origin

`libgc`/`libpcre2-8`/`libevent` were cross-compiled for the egui.cr
Android port (NDK r25 / API 33), copied from `~/egui.cr/etc/arm64-v8a/`.
`libssl`/`libcrypto` come from the perevodilka Android port
(`./Configure android-arm64 no-shared no-tests no-docs
-D__ANDROID_API__=33` — see the "Android" section of its README).
Identical build inputs work for any Crystal program targeting
`aarch64-linux-android`.

To rebuild from sources:

    # Boehm GC (libatomic_ops included)
    git clone https://github.com/ivmai/bdwgc && cd bdwgc && git clone https://github.com/ivmai/libatomic_ops
    cmake -B build -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
      -DBUILD_SHARED_LIBS=OFF -Denable_munmap=OFF && cmake --build build
    # → build/libgc.a

    # PCRE2 (8-bit, JIT)
    cmake -B build -DCMAKE_TOOLCHAIN_FILE=... -DANDROID_ABI=arm64-v8a \
      -DPCRE2_SUPPORT_JIT=ON -DPCRE2_BUILD_PCRE2_8=ON \
      -DPCRE2_BUILD_PCRE2_16=OFF -DPCRE2_BUILD_PCRE2_32=OFF \
      -DPCRE2_BUILD_TESTS=OFF && cmake --build build
    # → build/libpcre2-8.a

    # libevent (no OpenSSL needed)
    ./configure --host=aarch64-linux-android \
      CC=$TOOLCHAIN/bin/aarch64-linux-android26-clang \
      --disable-openssl --disable-shared --enable-static
    # → .libs/libevent.a

## Licenses

- `libgc.a` — Boehm-Demers-Weiser GC (MIT-like, see bdwgc README)
- `libpcre2-8.a` — PCRE2 (BSD 3-clause)
- `libevent.a` — libevent (BSD 3-clause)
- `libssl.a` / `libcrypto.a` — OpenSSL (Apache-2.0)
