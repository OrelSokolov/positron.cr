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
