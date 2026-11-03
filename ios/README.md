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

Known quirk: `+[AVCaptureDevice
authorizationStatusForMediaType:]` segfaults when called from our
binary (other class methods answer fine), so the optional permission
pre-check is skipped — see the note in `ios.cr`.
