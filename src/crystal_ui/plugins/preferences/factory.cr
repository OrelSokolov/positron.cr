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
  # Compile-time factory that picks the correct native preferences adapter
  # for the current target platform.
  module PreferencesAdapterFactory
    def self.create(app_id : String = "crystalui") : PreferencesAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxPreferencesAdapter.new(app_id)
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSPreferencesAdapter.new(app_id)
      {% elsif flag?(:win32) %}
        WindowsPreferencesAdapter.new(app_id)
      {% elsif flag?(:android) %}
        AndroidPreferencesAdapter.new(app_id)
      {% elsif flag?(:ios) %}
        IOSPreferencesAdapter.new(app_id)
      {% else %}
        {% raise "Preferences plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
