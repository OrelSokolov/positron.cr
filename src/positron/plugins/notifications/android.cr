require "log"
require "json"
require "./adapter"
require "../../event_bus"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android notifications adapter: `NotificationManager` through the
  # JNI bridge (channel "positron", the app icon as the small icon).
  # On API 33+ the first `send` after install triggers the
  # `POST_NOTIFICATIONS` request from the Activity; until the user
  # grants it the system silently drops the notification — `send`
  # never fails the command (same contract as egui.cr's port).
  #
  # Taps and action buttons arrive as `notification_click` broadcasts,
  # routed by the host into `EventBus` ("android.notification_click");
  # the subscription here turns them into the adapter's click/action
  # callbacks (registered by the plugin in #on_ready).
  class AndroidNotificationsAdapter < NotificationsAdapter
    Log = ::Log.for("positron.plugins.notifications")

    def initialize
      # Taps/action buttons arrive as notification_click broadcasts,
      # routed by the host into EventBus; turn them into the adapter's
      # click/action callbacks (registered by the plugin in #on_ready).
      Positron::EventBus.on("android.notification_click") do |payload|
        id = payload["id"]?.try(&.as_s?) || next
        if action = payload["action"]?.try(&.as_s?)
          emit_action(id, action)
        else
          emit_click(id)
        end
      end
    end

    private def bridge : Positron::Adapters::Android::LibJNI::JObject
      Positron::Adapters::Android::LibShim.positron_shim_bridge
    end

    def send(id : String, title : String, body : String,
             actions : Array({String, String}) = [] of {String, String}) : String
      jni = Positron::Adapters::Android::JNI.instance
      actions_json = actions.map { |a_id, label| {id: a_id, title: label} }.to_json
      jni.call_bool(bridge, "notify",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z",
        [jni.to_java(id).address.to_i64,
         jni.to_java(title).address.to_i64,
         jni.to_java(body).address.to_i64,
         jni.to_java(actions_json).address.to_i64])
      id
    rescue ex
      Log.error(exception: ex) { "send failed" }
      id
    end

    def clear(id : String) : Bool
      Positron::Adapters::Android::JNI.instance.call_bool(
        bridge, "clearNotification", "(Ljava/lang/String;)Z",
        [Positron::Adapters::Android::JNI.instance.to_java(id).address.to_i64])
    rescue ex
      Log.error(exception: ex) { "clear failed" }
      false
    end

    def request_permission : Bool
      Positron::Adapters::Android::JNI.instance.call_bool(
        bridge, "requestNotificationsPermission", "()Z")
    rescue ex
      Log.error(exception: ex) { "request_permission failed" }
      false
    end

    def check_permission : Bool
      Positron::Adapters::Android::JNI.instance.call_bool(
        bridge, "notificationsEnabled", "()Z")
    rescue ex
      Log.error(exception: ex) { "check_permission failed" }
      false
    end
  end
end
