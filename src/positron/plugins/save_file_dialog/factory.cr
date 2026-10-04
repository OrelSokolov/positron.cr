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
