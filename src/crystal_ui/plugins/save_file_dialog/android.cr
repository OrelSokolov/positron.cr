require "log"
require "./adapter"

module CrystalUI::Plugins
  # Android save file dialog adapter (stub).
  #
  # A real implementation would start `Intent.ACTION_CREATE_DOCUMENT`
  # through the JNI bridge in the Android shim and return the selected URI.
  class AndroidSaveFileDialogAdapter < SaveFileDialogAdapter
    def save(suggested_name : String) : String?
      Log.for("crystalui.plugins.save_file_dialog").warn { "Android save file dialog not yet implemented" }
      nil
    end
  end
end
