require "log"
require "./adapter"

module Positron::Plugins
  # iOS file picker adapter (stub).
  #
  # A real implementation would call `UIDocumentPickerViewController`
  # through the C-ABI/Swift shim on iOS and return the selected URL.
  class IOSFilePickerAdapter < FilePickerAdapter
    def pick(accept : String) : String?
      Log.for("positron.plugins.file_picker").warn { "iOS file picker not yet implemented" }
      nil
    end
  end
end
