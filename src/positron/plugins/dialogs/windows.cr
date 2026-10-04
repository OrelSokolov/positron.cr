require "log"
require "./adapter"

module Positron::Plugins
  # Windows dialogs adapter (stub).
  class WindowsDialogsAdapter < DialogsAdapter
    def alert(message : String, title : String, kind : String) : Nil
      Log.for("positron.plugins.dialogs").warn { "Windows dialogs not yet implemented" }
    end

    def confirm(message : String, title : String) : Bool
      false
    end

    def prompt(message : String, default : String, title : String) : String?
      nil
    end
  end
end
