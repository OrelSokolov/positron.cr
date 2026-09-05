require "log"
require "./adapter"

module CrystalUI::Plugins
  # Windows dialogs adapter (stub).
  class WindowsDialogsAdapter < DialogsAdapter
    def alert(message : String, title : String, kind : String) : Nil
      Log.for("crystalui.plugins.dialogs").warn { "Windows dialogs not yet implemented" }
    end

    def confirm(message : String, title : String) : Bool
      false
    end

    def prompt(message : String, default : String, title : String) : String?
      nil
    end
  end
end
