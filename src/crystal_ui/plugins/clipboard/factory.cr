require "./adapter"
require "./linux"
require "./macos"
require "./windows"
require "./android"
require "./ios"

module CrystalUI::Plugins
  # Compile-time factory that picks the correct native clipboard adapter
  # for the current target platform.
  module ClipboardAdapterFactory
    def self.create : ClipboardAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxClipboardAdapter.new
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSClipboardAdapter.new
      {% elsif flag?(:win32) %}
        WindowsClipboardAdapter.new
      {% elsif flag?(:android) %}
        AndroidClipboardAdapter.new
      {% elsif flag?(:ios) %}
        IOSClipboardAdapter.new
      {% else %}
        {% raise "Clipboard plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
