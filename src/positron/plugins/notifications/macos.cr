require "log"
require "./adapter"

module Positron::Plugins
  # macOS notification adapter (stub).
  #
  # A real implementation would bridge to `NSUserNotificationCenter` or
  # `UNUserNotificationCenter` through the native macOS shim.
  class MacOSNotificationsAdapter < NotificationsAdapter
    def send(id : String, title : String, body : String) : String
      Log.for("positron.plugins.notifications").warn { "macOS notifications not yet implemented" }
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
