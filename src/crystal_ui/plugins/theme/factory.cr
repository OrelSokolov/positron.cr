require "./adapter"
require "./linux"
require "./macos"
require "./windows"
require "./android"
require "./ios"

module CrystalUI::Plugins
  # Compile-time factory that picks the correct native theme adapter
  # for the current target platform.
  module ThemeAdapterFactory
    def self.create : ThemeAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxThemeAdapter.new
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSThemeAdapter.new
      {% elsif flag?(:win32) %}
        WindowsThemeAdapter.new
      {% elsif flag?(:android) %}
        AndroidThemeAdapter.new
      {% elsif flag?(:ios) %}
        IOsThemeAdapter.new
      {% else %}
        {% raise "Theme plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
