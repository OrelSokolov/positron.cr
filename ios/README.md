# Positron on iOS (simulator)

Pipeline for running Positron apps in the iOS simulator (arm64),
mirroring the egui.cr iOS toolchain (patched Crystal compiler + Boehm
+ PCRE2; see the header of `build_ios.sh`).

    rake build:ios                                  # hello
    ios/build_ios.sh examples/camera/camera.cr      # any example

## Camera in the simulator

The simulator has no camera hardware, and WKWebView's `getUserMedia`
cannot be fed by
[SimulatorCamera](https://github.com/dautovri/SimulatorCamera): its
injection dylib rides on `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES`, which
reaches only the app process — WKWebView runs capture inside its
sandboxed XPC extensions (`com.apple.WebKit.WebContent` /
`com.apple.WebKit.GPU`), and those strip `DYLD_*` variables at spawn
(also with `launchctl setenv` inside the simulator).

`examples/camera` therefore has two capture modes, picked at runtime
(`Positron.camera.supported()`): plain web APIs where they work
(Linux/Windows/macOS), and the **native camera plugin** on iOS —
in-process AVFoundation capture through the pure-Crystal ObjC layer
(`src/positron/plugins/camera/ios.cr`), with the frontend pulling
frames over the app's custom URI scheme (`/native-frame`: 12-byte
header + RGBA) onto a canvas. On a real device the same code talks to
the actual camera (no injection needed; `Info.plist` already carries
`NSCameraUsageDescription`, and iOS raises the TCC prompt when the
device input is created).

To feed the native capture from the host webcam in the simulator,
launch with the injected dylib (bundle path —
`/tmp/SimulatorCamera/build/...` is gone in current builds):

    SIMCTL_CHILD_DYLD_INSERT_LIBRARIES="/Applications/SimulatorCamera.app/Contents/Resources/libSimCamInject.dylib" \
      xcrun simctl launch booted cr.positron.camera

Known quirk: the TCC-authorization methods of `AVCaptureDevice`
(`authorizationStatusForMediaType:` and the newer
`authorizationStatusForAVMediaType:` spelling) segfault when executed
from our pure-Crystal-ObjC binary — every calling convention
(objc_msgSend, NSInvocation, method_invoke) dies inside the TCC IMP,
with or without the injection dylib, while non-TCC class methods of
the same class answer cleanly. Fully reproduced and classified in
`ios/repro_auth_status.{cr,sh}` (automatic — no user interaction, one
variant per run). The optional permission pre-check is therefore
skipped in `plugins/camera/ios.cr`; iOS raises the TCC prompt at
device-input creation anyway, so capture on a real device is not
affected.

## Boehm GC static-root filter (`ios/main.c`)

UIKit soft-links many frameworks lazily (`dlopen` on first use), and
bdwgc's `GC_dyld_image_add` registers the writable data of every
loaded image as GC roots. In the simulator that piles up ~1500 root
segments at boot plus several hundred per lazy-load cascade, which
exhausted bdwgc's `MAX_ROOT_SETS` and aborted the process ("Too many
root sets" in `GC_add_roots_inner`) the first time a WKWebView text
selection menu loaded `DataDetectorsUILibrary`. `main()` therefore
installs a `GC_has_static_roots` callback (before `crystal_main_entry`
— it must precede the first allocation) that accepts only the main
executable's own image. No Crystal object can be referenced from a
system framework's static data: the adapters keep the Crystal side of
every ObjC callback in class variables of the main image. Measured
effect: 1510 → 3 root segments, ~36 MB → ~0.9 MB scanned static roots
per collection. If you ever move late-bound Crystal code into a
separately dlopen'ed library, extend `positron_gc_root_filter` to
accept that image's path too.
