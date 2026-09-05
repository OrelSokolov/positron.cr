require "log"
require "./adapter"

module CrystalUI::Plugins
  # macOS dialogs adapter (stub).
  class MacOSDialogsAdapter < DialogsAdapter
    def alert(message : String, title : String, kind : String) : Nil
      Log.for("crystalui.plugins.dialogs").warn { "macOS dialogs not yet implemented" }
    end

    def confirm(message : String, title : String) : Bool
      false
    end

    def prompt(message : String, default : String, title : String) : String?
      nil
    end
  end
end
