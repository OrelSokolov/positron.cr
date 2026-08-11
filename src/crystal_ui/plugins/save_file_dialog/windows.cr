require "log"
require "./adapter"

module CrystalUI::Plugins
  # Windows save file dialog adapter (stub).
  #
  # A real implementation would call `IFileDialog` with `FOS_OVERWRITEPROMPT`
  # through the native Windows COM shim and return the selected target path.
  class WindowsSaveFileDialogAdapter < SaveFileDialogAdapter
    def save(suggested_name : String) : String?
      Log.for("crystalui.plugins.save_file_dialog").warn { "Windows save file dialog not yet implemented" }
      nil
    end
  end
end
