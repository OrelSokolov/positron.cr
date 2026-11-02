require "json"

module Positron::Plugins
  # Platform-agnostic interface for system notifications.
  #
  # Each platform provides a thin adapter that forwards host commands to the
  # native notification API and routes user interactions back through the
  # EventBus as `notification.clicked` events.
  abstract class NotificationsAdapter
    alias ClickHandler = Proc(String, Nil)
    # (notification_id, action_id)
    alias ActionHandler = Proc(String, String, Nil)

    @click_handler : ClickHandler?
    @action_handler : ActionHandler?

    # Send a notification. `actions` is a list of {action_id, label}
    # button pairs shown with the notification (platform support varies;
    # adapters ignore unsupported actions). Returns the id used to
    # reference it later.
    abstract def send(id : String, title : String, body : String,
                      actions : Array({String, String}) = [] of {String, String}) : String

    # Clear (close) a previously shown notification by id.
    abstract def clear(id : String) : Bool

    # Request permission from the OS to show notifications.
    abstract def request_permission : Bool

    # Check whether permission has been granted.
    abstract def check_permission : Bool

    # Register a callback for notification clicks/actions.
    def on_click(&block : ClickHandler)
      @click_handler = block
    end

    def on_action(&block : ActionHandler)
      @action_handler = block
    end

    protected def emit_click(id : String)
      if handler = @click_handler
        handler.call(id)
      end
    end

    protected def emit_action(id : String, action : String)
      if handler = @action_handler
        handler.call(id, action)
      end
    end
  end
end
