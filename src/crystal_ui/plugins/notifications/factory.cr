require "./adapter"
require "./linux"
require "./macos"
require "./windows"
require "./android"
require "./ios"

module CrystalUI::Plugins
  # Compile-time factory that picks the correct native notification adapter
  # for the current target platform.
  module NotificationsAdapterFactory
    def self.create : NotificationsAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxNotificationsAdapter.new
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSNotificationsAdapter.new
      {% elsif flag?(:win32) %}
        WindowsNotificationsAdapter.new
      {% elsif flag?(:android) %}
        AndroidNotificationsAdapter.new
      {% elsif flag?(:ios) %}
        IOSNotificationsAdapter.new
      {% else %}
        {% raise "Notifications plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
