require "log"
require "./adapter"

module Positron::Plugins
  # Linux implementation of system notifications using libnotify.
  #
  # This is a thin FFI wrapper: Crystal Host owns the lifecycle, libnotify
  # just renders the bubble. Click actions are wired back through
  # `EventBus` via the adapter's `on_click` handler.
  class LinuxNotificationsAdapter < NotificationsAdapter
    @active = {} of String => Void*
    @action_callback : Proc(Void*, LibC::Char*, Void*, Nil)?

    def initialize
      LibNotify.notify_init("Positron")
    end

    def finalize
      LibNotify.notify_uninit
    end

    def send(id : String, title : String, body : String) : String
      notification = LibNotify.notify_notification_new(title, body, Pointer(LibC::Char).null)

      # Keep the callback alive for the lifetime of the adapter.
      @action_callback ||= ->(_notification : Void*, _action : LibC::Char*, data : Void*) do
        notification_id = String.new(data.as(LibC::Char*))
        EventBus.emit("notification.clicked", {id: notification_id})
      end

      # Store the id as a null-terminated C string so libnotify can pass it
      # back in the action callback without allocating Crystal objects in C.
      id_ptr = id.to_unsafe

      LibNotify.notify_notification_add_action(
        notification,
        "default",
        "Open",
        @action_callback.not_nil!.pointer.as(Void*),
        id_ptr.as(Void*),
        Pointer(Void).null
      )

      LibNotify.notify_notification_show(notification, Pointer(Pointer(Void)).null)
      @active[id] = notification
      id
    end

    def clear(id : String) : Bool
      if notification = @active.delete(id)
        LibNotify.notify_notification_close(notification, Pointer(Pointer(Void)).null)
        true
      else
        false
      end
    end

    def request_permission : Bool
      # libnotify does not have a permission prompt on desktop Linux.
      # We treat the ability to init as granted.
      true
    end

    def check_permission : Bool
      LibNotify.notify_is_initted != 0
    end

    @[Link("notify")]
    lib LibNotify
      fun notify_init(app_name : LibC::Char*) : Int32
      fun notify_uninit
      fun notify_is_initted : Int32

      fun notify_notification_new(
        summary : LibC::Char*,
        body : LibC::Char*,
        icon : LibC::Char*,
      ) : Void*

      fun notify_notification_show(notification : Void*, error : Void**) : Int32
      fun notify_notification_close(notification : Void*, error : Void**) : Int32

      fun notify_notification_add_action(
        notification : Void*,
        action : LibC::Char*,
        label : LibC::Char*,
        callback : Void*,
        user_data : Void*,
        free_func : Void*,
      )
    end
  end
end
