require "log"
require "./adapter"

module CrystalUI::Plugins
  # Android file picker adapter (stub).
  #
  # A real implementation would start `Intent.ACTION_OPEN_DOCUMENT`
  # through the JNI bridge in the Android shim and return the selected URI.
  class AndroidFilePickerAdapter < FilePickerAdapter
    def pick(accept : String) : String?
      Log.for("crystalui.plugins.file_picker").warn { "Android file picker not yet implemented" }
      nil
    end
  end
end
