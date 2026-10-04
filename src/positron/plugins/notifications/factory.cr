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
