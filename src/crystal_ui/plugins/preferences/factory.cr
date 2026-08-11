require "./adapter"
require "./linux"
require "./macos"
require "./windows"
require "./android"
require "./ios"

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
