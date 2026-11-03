require "log"
require "./adapter"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android permissions adapter: runtime permissions through the JNI
  # bridge (`checkOsPermission` / `requestOsPermission` on the
  # PositronBridge). The OS dialog is async — `request` returns the
  # current state and the answer lands later as a `permission_result`
  # shim event, which the host already routes to the app and the
  # EventBus (`permission.result`).
  #
  # Known names map to OS permissions (camera → CAMERA, microphone →
  # RECORD_AUDIO, location → ACCESS_FINE_LOCATION, notifications →
  # POST_NOTIFICATIONS); "clipboard"/"files" need no runtime permission
  # and report "granted"; unknown names report "denied".
  class AndroidPermissionsAdapter < PermissionsAdapter
    Log = ::Log.for("positron.plugins.permissions")

    private def bridge : Positron::Adapters::Android::LibJNI::JObject
      Positron::Adapters::Android::LibShim.positron_shim_bridge
    end

    def check(permission : String) : String
      state = Positron::Adapters::Android::JNI.instance.call_string(
        bridge, "checkOsPermission", "(Ljava/lang/String;)Ljava/lang/String;",
        [Positron::Adapters::Android::JNI.instance.to_java(permission).address.to_i64])
      state || "denied"
    rescue ex
      Log.error(exception: ex) { "check(#{permission}) failed" }
      "denied"
    end

    def request(permission : String) : String
      state = Positron::Adapters::Android::JNI.instance.call_bool(
        bridge, "requestOsPermission", "(Ljava/lang/String;)Z",
        [Positron::Adapters::Android::JNI.instance.to_java(permission).address.to_i64])
      # True means already granted; false covers "prompt" (dialog fired,
      # answer follows as permission.result) and "denied".
      state ? "granted" : check(permission)
    rescue ex
      Log.error(exception: ex) { "request(#{permission}) failed" }
      "denied"
    end
  end
end
