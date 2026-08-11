require "./adapter"
require "./linux"
require "./macos"
require "./windows"
require "./android"
require "./ios"

module CrystalUI::Plugins
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
