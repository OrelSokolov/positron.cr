require "log"
require "./adapter"

module Positron::Plugins
  # Android dialogs adapter (stub).
  #
  # A real implementation would show an AlertDialog through the JNI
  # bridge in the Android shim; until then the JS `window.confirm`
  # family keeps working in the WebView.
  class AndroidDialogsAdapter < DialogsAdapter
    def alert(message : String, title : String, kind : String) : Nil
      Log.for("positron.plugins.dialogs").warn { "Android dialogs not yet implemented" }
    end

    def confirm(message : String, title : String) : Bool
      Log.for("positron.plugins.dialogs").warn { "Android dialogs not yet implemented" }
      false
    end

    def prompt(message : String, default : String, title : String) : String?
      Log.for("positron.plugins.dialogs").warn { "Android dialogs not yet implemented" }
      nil
    end
  end
end
