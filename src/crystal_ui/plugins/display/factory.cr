require "./adapter"
require "./linux"
require "./macos"
require "./windows"
require "./android"
require "./ios"

module CrystalUI::Plugins
  # Compile-time factory that picks the correct native display adapter
  # for the current target platform.
  module DisplayAdapterFactory
    def self.create : DisplayAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxDisplayAdapter.new
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSDisplayAdapter.new
      {% elsif flag?(:win32) %}
        WindowsDisplayAdapter.new
      {% elsif flag?(:android) %}
        AndroidDisplayAdapter.new
      {% elsif flag?(:ios) %}
        IOsDisplayAdapter.new
      {% else %}
        {% raise "Display plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
