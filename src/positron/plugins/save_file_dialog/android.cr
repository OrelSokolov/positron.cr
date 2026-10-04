require "log"
require "./adapter"

module Positron::Plugins
  # Android save file dialog adapter (stub).
  #
  # A real implementation would start `Intent.ACTION_CREATE_DOCUMENT`
  # through the JNI bridge in the Android shim and return the selected URI.
  class AndroidSaveFileDialogAdapter < SaveFileDialogAdapter
    def save(suggested_name : String) : String?
      Log.for("positron.plugins.save_file_dialog").warn { "Android save file dialog not yet implemented" }
      nil
    end
  end
end
