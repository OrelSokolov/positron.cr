require "./adapter"

# Platform adapter sources are gated by target flags so their @[Link]
# annotations (Linux C libs) never reach non-Linux builds.
{% if flag?(:linux) && !flag?(:android) %}
  require "./linux"
{% end %}
{% if flag?(:darwin) && !flag?(:ios) %}
  require "./macos"
{% end %}
{% if flag?(:win32) %}
  require "./windows"
{% end %}
{% if flag?(:android) %}
  require "./android"
{% end %}
{% if flag?(:ios) %}
  require "./ios"
{% end %}

module Positron::Plugins
  # Compile-time factory that picks the correct native file picker adapter
  # for the current target platform.
  module FilePickerAdapterFactory
    def self.create : FilePickerAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxFilePickerAdapter.new
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSFilePickerAdapter.new
      {% elsif flag?(:win32) %}
        WindowsFilePickerAdapter.new
      {% elsif flag?(:android) %}
        AndroidFilePickerAdapter.new
      {% elsif flag?(:ios) %}
        IOSFilePickerAdapter.new
      {% else %}
        {% raise "FilePicker plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
