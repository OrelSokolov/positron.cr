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
