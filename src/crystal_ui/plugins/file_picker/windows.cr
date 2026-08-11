require "log"
require "./adapter"

module CrystalUI::Plugins
  # Windows file picker adapter (stub).
  #
  # A real implementation would call `IFileDialog` through the native
  # Windows COM shim and return the selected path.
  class WindowsFilePickerAdapter < FilePickerAdapter
    def pick(accept : String) : String?
      Log.for("crystalui.plugins.file_picker").warn { "Windows file picker not yet implemented" }
      nil
    end
  end
end
