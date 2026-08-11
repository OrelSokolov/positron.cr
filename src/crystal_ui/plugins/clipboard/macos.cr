require "log"
require "./adapter"

module CrystalUI::Plugins
  # macOS clipboard adapter (stub).
  #
  # A real implementation would call `NSPasteboard` through the native
  # macOS Cocoa shim.
  class MacOSClipboardAdapter < ClipboardAdapter
    def read_text : String?
      Log.for("crystalui.plugins.clipboard").warn { "macOS clipboard not yet implemented" }
      nil
    end

    def read_image : {mime: String, data: Bytes}?
      nil
    end

    def read_files : Array(String)
      [] of String
    end

    def has_text? : Bool
      false
    end

    def has_image? : Bool
      false
    end

    def has_files? : Bool
      false
    end

    def write_text(text : String) : Bool
      false
    end

    def write_image(base64 : String, mime : String) : Bool
      false
    end
  end
end
