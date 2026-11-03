require "log"
require "./adapter"
require "./saf_mime"
require "../../adapters/android/async_bridge"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android file picker adapter: the SAF picker (`ACTION_OPEN_DOCUMENT`)
  # started through the JNI bridge. The pick arrives asynchronously on
  # the Java UI thread (`onActivityResult`); the Java side copies the
  # document into the cache dir, so the result path is a plain readable
  # file — no content:// bookkeeping on the Crystal side.
  #
  # Blocking model: the callback form of #pick registers a continuation
  # in `AsyncBridge` and returns immediately (the GUI fiber is the
  # event-loop pump and must not block); the shim event drain completes
  # it when the `saf_result` event lands.
  class AndroidFilePickerAdapter < FilePickerAdapter
    Log = ::Log.for("positron.plugins.file_picker")

    KIND_OPEN = 1

    # Matches safStart(int, int, String, String, String) on the bridge.
    SAF_SIG = "(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"

    # Common extensions → MIME types (SAF filters by MIME, not glob).
    def self.mime_for(accept : String) : String
      SafMime.mime_for(accept)
    end

    def pick(accept : String) : String?
      Log.warn { "blocking #pick is not available on Android; use the callback form" }
      nil
    end

    def pick(accept : String, &on_done : String? ->) : Nil
      jni = Positron::Adapters::Android::JNI.instance
      seq = Positron::Adapters::Android::AsyncBridge.start do |payload|
        on_done.call(path_from(payload))
      end
      started = jni.call_bool(
        Positron::Adapters::Android::LibShim.positron_shim_bridge,
        "safStart", SAF_SIG,
        [seq.to_i64, KIND_OPEN.to_i64,
         jni.to_java(self.class.mime_for(accept)).address.to_i64,
         jni.to_java("").address.to_i64,
         jni.to_java("").address.to_i64])
      unless started
        Positron::Adapters::Android::AsyncBridge.cancel(seq)
        on_done.call(nil)
      end
    end

    # Translates the `accept` filter into the single MIME type the SAF
    # intent accepts: bare MIME items pass through, extension items map
    # through MIME; mixed/unknown filters fall back to */*.
    def self.mime_for(accept : String) : String
      mimes = accept.split(",").map do |raw|
        item = raw.strip.downcase
        next nil if item.empty? || item == "*"
        if item.includes?('/')
          item
        elsif item.starts_with?('.')
          MIME[item[1..]]?
        end
      end.compact.uniq
      mimes.size == 1 ? mimes.first : "*/*"
    end

    private def path_from(payload : String) : String?
      parsed = JSON.parse(payload)
      if path = parsed["path"]?.try(&.as_s?)
        path
      else
        parsed["error"]?.try { |e| Log.warn { "SAF picker error: #{e}" } }
        nil
      end
    rescue JSON::ParseException
      nil
    end
  end
end
