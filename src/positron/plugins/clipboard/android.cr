require "log"
require "./adapter"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android clipboard adapter: ClipboardManager through the JNI bridge
  # (PositronBridge in android/src/com/positron/shim/PositronActivity.java).
  class AndroidClipboardAdapter < ClipboardAdapter
    Log = ::Log.for("positron.plugins.clipboard")

    private def bridge : Positron::Adapters::Android::LibJNI::JObject
      Positron::Adapters::Android::LibShim.positron_shim_bridge
    end

    def read_text : String?
      Positron::Adapters::Android::JNI.instance.call_string(bridge, "readClipboardText", "()Ljava/lang/String;")
    rescue ex
      Log.error(exception: ex) { "read_text failed" }
      nil
    end

    def read_image : {mime: String, data: Bytes}?
      # ClipData image URIs point at content:// providers the host
      # cannot read directly; left for the file_picker/contentResolver
      # adapter.
      nil
    end

    def read_files : Array(String)
      [] of String
    end

    def has_text? : Bool
      Positron::Adapters::Android::JNI.instance.call_bool(bridge, "clipboardHasText", "()Z")
    rescue ex
      Log.error(exception: ex) { "has_text? failed" }
      false
    end

    def has_image? : Bool
      false
    end

    def has_files? : Bool
      false
    end

    def write_text(text : String) : Bool
      jni = Positron::Adapters::Android::JNI.instance
      jni.call_bool(bridge, "writeClipboardText", "(Ljava/lang/String;)Z",
        [jni.to_java(text).address.to_i64])
    rescue ex
      Log.error(exception: ex) { "write_text failed" }
      false
    end

    def write_image(base64 : String, mime : String) : Bool
      false
    end
  end
end
