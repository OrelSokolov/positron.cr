require "../src/positron"
require "spec"
require "json"

# Headless specs for the camera plugin. The iOS AVFoundation adapter is
# flag-gated (`plugins/camera/ios.cr`); on the spec host the factory
# picks UnsupportedCameraAdapter, which is exactly what these specs
# exercise — plus the platform-pure frame-header format.

# Build a dispatch-ready command request.
def camera_spec_request(name : String, args = {} of String => JSON::Any)
  Positron::CommandRequest.new(
    id: "spec", name: name, args: JSON.parse(args.to_json))
end

describe Positron::Plugins::Camera do
  plugin = Positron::Plugins::Camera.new
  registry = Positron::CommandRegistry.new
  state = Positron::StateManager.new
  plugin.bind(registry, state)

  it "exposes its command manifest" do
    manifest = plugin.manifest
    manifest.keys.should contain("camera.supported")
    manifest.keys.should contain("camera.devices")
    manifest.keys.should contain("camera.start")
    manifest.keys.should contain("camera.stop")
  end

  it "answers supported() according to the platform" do
    {% if flag?(:ios) %}
      registry.dispatch(camera_spec_request("camera.supported")).data.as_bool.should be_true
    {% else %}
      registry.dispatch(camera_spec_request("camera.supported")).data.as_bool.should be_false
    {% end %}
  end

  {% unless flag?(:ios) %}
    it "reports an empty device list and a start error without a native adapter" do
      registry.dispatch(camera_spec_request("camera.devices")).data.as_a.should be_empty

      started = registry.dispatch(camera_spec_request("camera.start"))
      started.success.should be_false
      started.data["ok"].as_bool.should be_false
      started.data["error"].as_s.should contain("not available")

      stopped = registry.dispatch(camera_spec_request("camera.stop"))
      stopped.data.as_bool.should be_true
    end
  {% end %}

  it "encodes the frame header (magic + u32 LE width/height)" do
    header = Positron::Plugins::Camera.frame_header(1280, 720)
    header.size.should eq(12)
    header[0, 4].should eq(Bytes[0x50, 0x52, 0x46, 0x41]) # "PRFA"
    header[4, 4].should eq(Bytes[0x00, 0x05, 0x00, 0x00]) # 1280 LE (0x500)
    header[8, 4].should eq(Bytes[0xD0, 0x02, 0x00, 0x00]) # 720 LE
  end
end
