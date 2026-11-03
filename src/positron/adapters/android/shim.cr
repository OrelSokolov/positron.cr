require "./jni"

module Positron
  module Adapters
    module Android
      # Bindings to the C seam in `android/positron_shim.c`.
      #
      # The shim is the ONLY entry point for native (Java) threads:
      # everything they hand over crosses as copied C strings through
      # its mutex-guarded queue, never as GC-heap pointers.
      lib LibShim
        # Event kinds (keep in sync with PS_EVT_* in positron_shim.c).
        EVT_MESSAGE = 1
        EVT_EVENT   = 2
        EVT_STOP    = 3

        # Pop one pending message; returns 0 when the queue is empty.
        # The caller owns a/b and releases them with positron_shim_free.
        fun positron_shim_pop(kind : Int32*, a : UInt8**, b : UInt8**) : Int32
        fun positron_shim_free(p : Void*)

        fun positron_shim_vm : LibJNI::JavaVM
        fun positron_shim_activity : LibJNI::JObject
        fun positron_shim_webview : LibJNI::JObject
        fun positron_shim_bridge : LibJNI::JObject

        # Synchronous asset roundtrip (shouldInterceptRequest path).
        # take: pending request or NULL. path: borrowed, valid until
        # done. done: copies data/mime into the request and wakes the
        # waiting Java thread.
        fun positron_shim_asset_take : Void*
        fun positron_shim_asset_path(req : Void*) : UInt8*
        fun positron_shim_asset_done(req : Void*, data : UInt8*, len : UInt32, mime : UInt8*) : Void
      end
    end
  end
end
