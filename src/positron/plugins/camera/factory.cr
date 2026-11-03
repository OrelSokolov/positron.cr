require "./adapter"

# Platform adapter sources are gated by target flags (same pattern as
# the clipboard factory) so iOS-only @[Link]/ObjC code never reaches
# other builds.
{% if flag?(:ios) %}
  require "./ios"
{% end %}

module Positron::Plugins
  # Compile-time factory that picks the native camera adapter for the
  # current target platform.
  module CameraAdapterFactory
    def self.create : CameraAdapter
      {% if flag?(:ios) %}
        IOSCameraAdapter.new
      {% else %}
        UnsupportedCameraAdapter.new
      {% end %}
    end
  end
end
