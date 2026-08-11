require "log"
require "./adapter"

module CrystalUI::Plugins
  # macOS file picker adapter (stub).
  #
  # A real implementation would call `NSOpenPanel` through the native
  # macOS Cocoa shim and return the selected path.
  class MacOSFilePickerAdapter < FilePickerAdapter
    def pick(accept : String) : String?
      Log.for("crystalui.plugins.file_picker").warn { "macOS file picker not yet implemented" }
      nil
    end
  end
end
