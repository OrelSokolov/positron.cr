require "log"
require "./adapter"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android camera adapter: camera2 through the NDK (the capture lives
  # in `android/positron_shim.c`; these bindings call it on the host
  # thread). An AImageReader surface is the capture target and frames
  # are pulled with acquireLatestImage in `latest_frame` — the same
  # pull-based contract as the iOS adapter: the app's scheme handler
  # calls it on every frontend fetch of `/native-frame` (on Android the
  # fetch rides the virtual https host's shouldInterceptRequest
  # roundtrip). The shim converts YUV_420_888 → RGBA and applies the
  # sensor orientation (+ front-camera mirror), so frames arrive
  # upright in portrait.
  #
  # The WebView's own `getUserMedia` works on Android too (the Activity
  # grants the WebView request and the permissions plugin covers the OS
  # runtime permission) — this adapter is the host-side path for apps
  # that want frames in Crystal, parity with iOS.
  #
  # Runtime permission: opening the camera device without holding
  # android.permission.CAMERA fails at the HAL, and unlike iOS there is
  # no automatic TCC prompt — `start` checks and (asynchronously)
  # requests the permission through the PositronBridge before opening,
  # and answers with a human-readable error so the frontend can retry
  # once the `permission.result` event lands.
  class AndroidCameraAdapter < CameraAdapter
    Log = ::Log.for("positron.plugins.camera")

    @session : Pointer(Void) = Pointer(Void).null

    def initialize
    end

    def supported? : Bool
      true
    end

    def devices : Array({id: String, label: String})
      count = Adapters::Android::LibShim.positron_cam_devices
      (0...count).map do |i|
        {
          id:    String.new(Adapters::Android::LibShim.positron_cam_dev_id(i)),
          label: String.new(Adapters::Android::LibShim.positron_cam_dev_name(i)),
        }
      end
    rescue ex
      Log.error(exception: ex) { "devices failed" }
      [] of {id: String, label: String}
    end

    def start(device_id : String?, width : Int32, height : Int32) : String?
      stop
      return "camera permission required — grant it and press Start again" unless camera_permission_granted?

      id_ptr = (device_id && !device_id.empty?) ? device_id.to_unsafe : Pointer(UInt8).null
      @session = Adapters::Android::LibShim.positron_cam_open(id_ptr, width, height)
      if @session.null?
        err = String.new(Adapters::Android::LibShim.positron_cam_last_error)
        Log.warn { "camera open failed: #{err}" }
        err
      else
        Log.info { "camera: session open (#{width}x#{height} hint)" }
        nil
      end
    end

    def stop : Nil
      unless @session.null?
        Adapters::Android::LibShim.positron_cam_close(@session)
        @session = Pointer(Void).null
      end
    end

    def latest_frame : {width: Int32, height: Int32, bytes: Bytes}?
      return nil if @session.null?

      data = Pointer(UInt8).null
      width, height = 0, 0
      if Adapters::Android::LibShim.positron_cam_frame(@session, pointerof(data), pointerof(width), pointerof(height)) == 1
        # Shim-owned bytes, valid until the next positron_cam_frame —
        # exactly the CameraAdapter contract.
        {width: width, height: height, bytes: Slice.new(data, width * height * 4, read_only: true)}
      end
    end

    private def camera_permission_granted? : Bool
      state = Positron::Adapters::Android::JNI.instance.call_string(
        bridge, "checkOsPermission", "(Ljava/lang/String;)Ljava/lang/String;",
        [Positron::Adapters::Android::JNI.instance.to_java("camera").address.to_i64])
      return true if state == "granted"
      # "prompt"/"denied": fire the OS dialog (the answer arrives later
      # as the permission.result event); retry is the frontend's job.
      if state == "prompt"
        Positron::Adapters::Android::JNI.instance.call_bool(
          bridge, "requestOsPermission", "(Ljava/lang/String;)Z",
          [Positron::Adapters::Android::JNI.instance.to_java("camera").address.to_i64])
      end
      false
    end

    private def bridge : Positron::Adapters::Android::LibJNI::JObject
      Positron::Adapters::Android::LibShim.positron_shim_bridge
    end
  end
end
