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
