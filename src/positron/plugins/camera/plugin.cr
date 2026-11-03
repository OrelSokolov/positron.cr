require "json"
require "log"
require "./adapter"
require "./factory"

module Positron::Plugins
  # Camera plugin.
  #
  # Native host-side capture where the WebView cannot do it itself —
  # on iOS WKWebView the `getUserMedia` pipeline lives in the
  # WebContent/GPU XPC processes, outside the app's reach, so the
  # adapter captures in-process (AVFoundation) and the frontend pulls
  # frames over the app's custom URI scheme (see `examples/camera`).
  #
  # Exposes a host-side API to the frontend:
  #   - camera.supported() -> Bool
  #   - camera.devices() -> Array({id, label})
  #   - camera.start({ deviceId?, width?, height? }) -> {ok, error?}
  #   - camera.stop() -> Bool
  #
  # On platforms without a native adapter `supported()` answers false
  # and the frontend keeps using the plain web APIs.
  class Camera < Positron::Plugin
    # Frame payload header served by the app's scheme handler:
    # magic "PRFA", width, height (u32 little-endian), followed by
    # width*height*4 RGBA bytes.
    MAGIC = "PRFA"

    @adapter : CameraAdapter

    def initialize
      @adapter = CameraAdapterFactory.create
    end

    def name : String
      "camera"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    # The adapter owning native capture (the app's scheme handler calls
    # `latest_frame` per frontend fetch).
    getter adapter : CameraAdapter

    def self.frame_header(width : Int32, height : Int32) : Bytes
      io = IO::Memory.new(12)
      io.write(MAGIC.to_slice)
      io.write_bytes(width.to_u32, IO::ByteFormat::LittleEndian)
      io.write_bytes(height.to_u32, IO::ByteFormat::LittleEndian)
      io.to_slice
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "camera.supported" => Positron::CommandManifest.new(
          name: "camera.supported",
          returns: "Bool"
        ),
        "camera.devices" => Positron::CommandManifest.new(
          name: "camera.devices",
          returns: "Array({id, label})"
        ),
        "camera.start" => Positron::CommandManifest.new(
          name: "camera.start",
          args: [
            Positron::ArgumentManifest.new(name: "deviceId", type: "String?"),
            Positron::ArgumentManifest.new(name: "width", type: "Int32?"),
            Positron::ArgumentManifest.new(name: "height", type: "Int32?"),
          ],
          returns: "{ok: Bool, error: String?}"
        ),
        "camera.stop" => Positron::CommandManifest.new(
          name: "camera.stop",
          returns: "Bool"
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("camera.supported") do |_request|
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(@adapter.supported?.to_json)
        )
      end

      registry.register("camera.devices") do |_request|
        devices = @adapter.devices.map { |d| {id: d[:id], label: d[:label]} }
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(devices.to_json)
        )
      end

      registry.register("camera.start") do |request|
        device_id = request.args["deviceId"]?.try &.as_s?
        width = request.args["width"]?.try(&.as_i?).try(&.to_i32) || 1280
        height = request.args["height"]?.try(&.as_i?).try(&.to_i32) || 720

        error = begin
          @adapter.start(device_id, width, height)
        rescue ex
          Log.error { "camera.start failed: #{ex.class}: #{ex.message.inspect}\n#{ex.backtrace.try &.first(6).join("\n")}" }
          ex.message || "start crashed"
        end
        payload = error ? {ok: false, error: error} : {ok: true, error: nil}
        Positron::CommandResult.new(
          success: error.nil?,
          data: JSON.parse(payload.to_json),
          error: error
        )
      end

      registry.register("camera.stop") do |_request|
        @adapter.stop
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(true.to_json)
        )
      end
    end
  end
end
