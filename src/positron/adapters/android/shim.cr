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

        fun positron_shim_activity : LibJNI::JObject
        fun positron_shim_webview : LibJNI::JObject
        fun positron_shim_bridge : LibJNI::JObject

        # Host-thread logging → logcat (tag "positron"): the Crystal
        # stdout/stderr go to /dev/null on Android.
        fun positron_shim_log(msg : UInt8*) : Void

        # JNIEnv trampolines (see positron_shim.c): the seam owns every
        # JNI table access; Crystal never dereferences the tables.
        fun positron_jni_attached : Int32
        fun positron_jni_new_string_utf(s : UInt8*) : LibJNI::JString
        fun positron_jni_string_utf(s : LibJNI::JString) : UInt8*
        fun positron_jni_exception_check : Int32
        fun positron_jni_exception_describe : Void
        fun positron_jni_exception_clear : Void
        fun positron_jni_get_object_class(obj : LibJNI::JObject) : LibJNI::JClass
        fun positron_jni_get_method_id(obj : LibJNI::JObject, name : UInt8*, sig : UInt8*) : LibJNI::JMethodID
        fun positron_jni_call_void_a(obj : LibJNI::JObject, mid : LibJNI::JMethodID, args : Int64*) : Void
        fun positron_jni_call_object_a(obj : LibJNI::JObject, mid : LibJNI::JMethodID, args : Int64*) : LibJNI::JObject
        fun positron_jni_call_boolean_a(obj : LibJNI::JObject, mid : LibJNI::JMethodID, args : Int64*) : UInt8
        fun positron_jni_call_int_a(obj : LibJNI::JObject, mid : LibJNI::JMethodID, args : Int64*) : Int32
        fun positron_jni_new_byte_array(bytes : UInt8*, len : Int32) : LibJNI::JByteArray
        fun positron_jni_array_length(arr : LibJNI::JByteArray) : Int32
        fun positron_jni_get_byte_array(arr : LibJNI::JByteArray, out : UInt8*, len : Int32) : UInt8
        fun positron_jni_delete_local_ref(obj : LibJNI::JObject) : Void

        # Synchronous asset roundtrip (shouldInterceptRequest path).
        # take: pending request or NULL. path: borrowed, valid until
        # done. done: copies data/mime into the request and wakes the
        # waiting Java thread. len is UInt64 to match the C `size_t`
        # exactly — a 32-bit declaration leaves garbage in the upper
        # half of the argument register on aarch64 and the 4 GB memcpy
        # segfaults the host.
        fun positron_shim_asset_take : Void*
        fun positron_shim_asset_path(req : Void*) : UInt8*
        fun positron_shim_asset_done(req : Void*, data : UInt8*, len : UInt64, mime : UInt8*) : Void

        # Camera capture over the camera2 NDK (the camera plugin's
        # Android adapter). All calls happen on the host thread; see the
        # camera section of positron_shim.c. cam_frame hands out
        # shim-owned RGBA bytes valid until the next cam_frame call.
        fun positron_cam_devices : Int32
        fun positron_cam_dev_id(index : Int32) : UInt8*
        fun positron_cam_dev_name(index : Int32) : UInt8*
        fun positron_cam_open(devid : UInt8*, width : Int32, height : Int32) : Void*
        fun positron_cam_frame(session : Void*, data : UInt8**, width : Int32*, height : Int32*) : Int32
        fun positron_cam_close(session : Void*) : Void
        fun positron_cam_last_error : UInt8*
      end
    end
  end
end
