require "./adapter"
require "./linux"
require "./macos"
require "./windows"
require "./android"
require "./ios"

module CrystalUI::Plugins
  # Compile-time factory that picks the correct native save dialog adapter
  # for the current target platform.
  module SaveFileDialogAdapterFactory
    def self.create : SaveFileDialogAdapter
      {% if flag?(:linux) && !flag?(:android) %}
        LinuxSaveFileDialogAdapter.new
      {% elsif flag?(:darwin) && !flag?(:ios) %}
        MacOSSaveFileDialogAdapter.new
      {% elsif flag?(:win32) %}
        WindowsSaveFileDialogAdapter.new
      {% elsif flag?(:android) %}
        AndroidSaveFileDialogAdapter.new
      {% elsif flag?(:ios) %}
        IOSSaveFileDialogAdapter.new
      {% else %}
        {% raise "SaveFileDialog plugin is not supported on this platform" %}
      {% end %}
    end
  end
end
