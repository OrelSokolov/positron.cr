require "log"
require "./adapter"

module Positron::Plugins
  # Android notification adapter (stub).
  #
  # A real implementation would call `NotificationManager` through the
  # JNI bridge in the Android shim.
  class AndroidNotificationsAdapter < NotificationsAdapter
    def send(id : String, title : String, body : String) : String
      Log.for("positron.plugins.notifications").warn { "Android notifications not yet implemented" }
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
