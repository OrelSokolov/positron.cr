require "log"
require "./adapter"

module Positron::Plugins
  # iOS save file dialog adapter (stub).
  #
  # A real implementation would call `UIDocumentPickerViewController`
  # in export mode through the C-ABI/Swift shim on iOS and return the URL.
  class IOSSaveFileDialogAdapter < SaveFileDialogAdapter
    def save(suggested_name : String) : String?
      Log.for("positron.plugins.save_file_dialog").warn { "iOS save file dialog not yet implemented" }
      nil
    end
  end
end
