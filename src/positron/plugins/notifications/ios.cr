require "log"
require "./adapter"

module Positron::Plugins
  # iOS notification adapter (stub).
  #
  # A real implementation would bridge to `UNUserNotificationCenter` through
  # the C-ABI/Swift shim on iOS.
  class IOSNotificationsAdapter < NotificationsAdapter
    def send(id : String, title : String, body : String) : String
      Log.for("positron.plugins.notifications").warn { "iOS notifications not yet implemented" }
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
