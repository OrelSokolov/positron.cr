require "log"
require "./adapter"

module Positron::Plugins
  # iOS dialogs adapter (stub).
  #
  # A real implementation would present a UIAlertController over the
  # window's root view controller through the ObjC runtime layer
  # (`adapters/ios/objc.cr`), answering confirm/prompt through static
  # delivery + a pump like the Android adapter does.
  class IOSDialogsAdapter < DialogsAdapter
    def alert(message : String, title : String, kind : String) : Nil
      Log.for("positron.plugins.dialogs").warn { "iOS alert not yet implemented: #{title} — #{message}" }
    end

    def confirm(message : String, title : String) : Bool
      Log.for("positron.plugins.dialogs").warn { "iOS confirm not yet implemented: #{message}" }
      false
    end

    def prompt(message : String, default : String, title : String) : String?
      Log.for("positron.plugins.dialogs").warn { "iOS prompt not yet implemented: #{message}" }
      nil
    end
  end
end
