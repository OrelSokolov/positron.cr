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

module CrystalUI::Plugins
  # Compile-time factory that picks the correct native dialogs adapter
  # for the current target platform.
  module DialogsAdapterFactory
    def self.create : DialogsAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxDialogsAdapter.new
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSDialogsAdapter.new
      {% elsif flag?(:win32) %}
        WindowsDialogsAdapter.new
      {% else %}
        {% raise "Dialogs plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
