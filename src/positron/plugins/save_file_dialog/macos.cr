require "log"
require "./adapter"

module Positron::Plugins
  # macOS save file dialog adapter (stub).
  #
  # A real implementation would call `NSSavePanel` through the native
  # macOS Cocoa shim and return the selected target path.
  class MacOSSaveFileDialogAdapter < SaveFileDialogAdapter
    def save(suggested_name : String) : String?
      Log.for("positron.plugins.save_file_dialog").warn { "macOS save file dialog not yet implemented" }
      nil
    end
  end
end
