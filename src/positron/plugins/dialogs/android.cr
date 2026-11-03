require "log"
require "./adapter"
require "../../adapters/android/async_bridge"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android dialogs adapter: `AlertDialog` through the JNI bridge.
  #
  # `alert` is fire-and-forget. `confirm`/`prompt` cannot return
  # synchronously — the dialog runs on the OS UI thread and the answer
  # arrives through the shim event queue (`dialog_result`), so only the
  # callback forms of the adapter API work; the blocking forms warn and
  # return the cancel value (the plugin only uses the callback forms).
  class AndroidDialogsAdapter < DialogsAdapter
    Log = ::Log.for("positron.plugins.dialogs")

    LEVELS = {"info" => 0, "warning" => 1, "error" => 2}

    def alert(message : String, title : String, kind : String) : Nil
      level = LEVELS[kind]? || 0
      jni = Positron::Adapters::Android::JNI.instance
      jni.call_void(
        Positron::Adapters::Android::LibShim.positron_shim_bridge,
        "msgbox", "(ILjava/lang/String;Ljava/lang/String;)V",
        [level.to_i64,
         jni.to_java(title).address.to_i64,
         jni.to_java(message).address.to_i64])
    end

    def confirm(message : String, title : String) : Bool
      Log.warn { "blocking #confirm is not available on Android; use the callback form" }
      false
    end

    def confirm(message : String, title : String, &on_done : Bool ->) : Nil
      jni = Positron::Adapters::Android::JNI.instance
      seq = Positron::Adapters::Android::AsyncBridge.start do |payload|
        on_done.call(begin
          JSON.parse(payload)["ok"]?.try(&.as?(Bool)) == true
        rescue JSON::ParseException
          false
        end)
      end
      jni.call_void(
        Positron::Adapters::Android::LibShim.positron_shim_bridge,
        "confirmAsk", "(ILjava/lang/String;Ljava/lang/String;)V",
        [seq.to_i64,
         jni.to_java(title).address.to_i64,
         jni.to_java(message).address.to_i64])
    end

    def prompt(message : String, default : String, title : String) : String?
      Log.warn { "blocking #prompt is not available on Android; use the callback form" }
      nil
    end

    def prompt(message : String, default : String, title : String,
               &on_done : String? ->) : Nil
      jni = Positron::Adapters::Android::JNI.instance
      seq = Positron::Adapters::Android::AsyncBridge.start do |payload|
        on_done.call(begin
          parsed = JSON.parse(payload)
          parsed["canceled"]? ? nil : parsed["value"]?.try(&.as_s?)
        rescue JSON::ParseException
          nil
        end)
      end
      jni.call_void(
        Positron::Adapters::Android::LibShim.positron_shim_bridge,
        "promptAsk", "(ILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
        [seq.to_i64,
         jni.to_java(title).address.to_i64,
         jni.to_java(message).address.to_i64,
         jni.to_java(default).address.to_i64])
    end
  end
end
