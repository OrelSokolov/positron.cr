require "log"
require "./adapter"
require "../../adapters/android/async_bridge"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android save file dialog adapter: the SAF picker
  # (`ACTION_CREATE_DOCUMENT`) started through the JNI bridge. The
  # staged `content` travels with the request; the Java side writes it
  # to the picked destination in `onActivityResult` (the content://
  # URI is not writable through File IO) and the result path is that
  # URI — hence #writes_content? == true, the iOS export-mode model.
  #
  # Blocking model: same as the file picker — the callback form
  # registers in `AsyncBridge`, the `saf_result` event completes it.
  class AndroidSaveFileDialogAdapter < SaveFileDialogAdapter
    Log = ::Log.for("positron.plugins.save_file_dialog")

    KIND_CREATE = 2

    SAF_SIG = "(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"

    def save(suggested_name : String, content : String) : String?
      Log.warn { "blocking #save is not available on Android; use the callback form" }
      nil
    end

    def save(suggested_name : String, content : String,
             &on_done : String? ->) : Nil
      jni = Positron::Adapters::Android::JNI.instance
      seq = Positron::Adapters::Android::AsyncBridge.start do |payload|
        on_done.call(path_from(payload))
      end
      started = jni.call_bool(
        Positron::Adapters::Android::LibShim.positron_shim_bridge,
        "safStart", SAF_SIG,
        [seq.to_i64, KIND_CREATE.to_i64,
         jni.to_java("*/*").address.to_i64,
         jni.to_java(suggested_name).address.to_i64,
         jni.to_java(content).address.to_i64])
      unless started
        Positron::Adapters::Android::AsyncBridge.cancel(seq)
        on_done.call(nil)
      end
    end

    # The Java side writes the staged content to the picked URI — the
    # plugin must not try to File.write a content:// path.
    def writes_content? : Bool
      true
    end

    private def path_from(payload : String) : String?
      parsed = JSON.parse(payload)
      if path = parsed["path"]?.try(&.as_s?)
        path
      else
        parsed["error"]?.try { |e| Log.warn { "SAF save error: #{e}" } }
        nil
      end
    rescue JSON::ParseException
      nil
    end
  end
end
