require "json"

module Positron::Plugins
  # Platform-agnostic interface for the Camera plugin.
  #
  # A real adapter captures in the host process (in-process AVFoundation
  # on iOS — see `ios.cr`) and hands the latest frame to the frontend,
  # which pulls it over the app's custom URI scheme. Platforms where the
  # WebView's own `getUserMedia` works (or no native stack is wired up)
  # get the `UnsupportedCameraAdapter` and the frontend falls back to the
  # web API.
  abstract class CameraAdapter
    # Whether this platform has a native capture stack behind this
    # adapter. The frontend branches on this answer.
    abstract def supported? : Bool

    # Available capture devices: `{id, label}` pairs.
    abstract def devices : Array({id: String, label: String})

    # Starts capture. Returns `nil` on success or a human-readable
    # error message. `device_id` nil/empty picks the default device.
    abstract def start(device_id : String?, width : Int32, height : Int32) : String?

    # Stops capture and releases the session.
    abstract def stop : Nil

    # The most recent frame converted to RGBA, or `nil` if none arrived
    # yet (or capture is not running). The bytes stay valid until the
    # next call.
    abstract def latest_frame : {width: Int32, height: Int32, bytes: Bytes}?
  end

  # Fallback adapter for platforms without a native camera bridge.
  class UnsupportedCameraAdapter < CameraAdapter
    def supported? : Bool
      false
    end

    def devices : Array({id: String, label: String})
      [] of {id: String, label: String}
    end

    def start(device_id : String?, width : Int32, height : Int32) : String?
      "native camera capture is not available on this platform"
    end

    def stop : Nil
    end

    def latest_frame : {width: Int32, height: Int32, bytes: Bytes}?
      nil
    end
  end
end
