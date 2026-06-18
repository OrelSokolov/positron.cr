require "log"
require "./adapter"

module CrystalUI::Plugins
  # Windows notification adapter (stub).
  #
  # A real implementation would bridge to the Windows Runtime
  # `Windows.UI.Notifications` API through the native Windows shim.
  class WindowsNotificationsAdapter < NotificationsAdapter
    def send(id : String, title : String, body : String) : String
      Log.for("crystalui.plugins.notifications").warn { "Windows notifications not yet implemented" }
      id
    end

    def clear(id : String) : Bool
      false
    end

    def request_permission : Bool
      false
    end

    def check_permission : Bool
      false
    end
  end
end
