# Pure-Crystal JNI bindings for the Android host (the objc.cr
# precedent: no bindings shard, just the minimal C surface).
#
# The JNINativeInterface function table below is generated from the
# NDK's jni.h (229 slots, fixed order per the JNI spec) — only the
# functions the host calls are typed, the rest are opaque Void* slots
# that keep every offset exact. All method calls go through the
# non-variadic *MethodA variants: Crystal cannot express a variadic C
# function pointer in a struct field, and the jvalue-array form is the
# ABI-stable way anyway. jvalue is an 8-byte union; the arg arrays are
# modeled as raw Int64* (one 8-byte slot per argument).
#
# Threading rules (learned the hard way in the perevodilka port):
# only the Crystal host thread may touch this module. Native (Java)
# threads enter through the C shim (android/positron_shim.c), never
# through here.
module Positron
  module Adapters
    module Android
      lib LibJNI
        alias JInt = Int32
        alias JLong = Int64
        alias JBoolean = UInt8
        alias JObject = Void*
        alias JClass = Void*
        alias JMethodID = Void*
        alias JString = Void*
        alias JByteArray = Void*
        alias JavaVM = JNIInvokeInterface*

        # JNIEnv on Android C is `const struct JNINativeInterface*`.
        alias Env = JNINativeInterface*

        struct JNINativeInterface
          get_version : Void*
          define_class : Void*
          find_class : (Env, UInt8*) -> JClass
          from_reflected_method : Void*
          from_reflected_field : Void*
          to_reflected_method : Void*
          get_superclass : Void*
          is_assignable_from : Void*
          to_reflected_field : Void*
          throw : Void*
          throw_new : Void*
          exception_occurred : Void*
          exception_describe : (Env) -> Void
          exception_clear : (Env) -> Void
          fatal_error : Void*
          push_local_frame : Void*
          pop_local_frame : Void*
          new_global_ref : (Env, JObject) -> JObject
          delete_global_ref : (Env, JObject) -> Void
          delete_local_ref : Void*
          is_same_object : Void*
          new_local_ref : Void*
          ensure_local_capacity : Void*
          alloc_object : Void*
          new_object : Void*
          new_object_v : Void*
          new_object_a : Void*
          get_object_class : (Env, JObject) -> JClass
          is_instance_of : Void*
          get_method_id : (Env, JClass, UInt8*, UInt8*) -> JMethodID
          call_object_method : Void*
          call_object_method_v : Void*
          call_object_method_a : (Env, JObject, JMethodID, Int64*) -> JObject
          call_boolean_method : Void*
          call_boolean_method_v : Void*
          call_boolean_method_a : (Env, JObject, JMethodID, Int64*) -> UInt8
          call_byte_method : Void*
          call_byte_method_v : Void*
          call_byte_method_a : Void*
          call_char_method : Void*
          call_char_method_v : Void*
          call_char_method_a : Void*
          call_short_method : Void*
          call_short_method_v : Void*
          call_short_method_a : Void*
          call_int_method : Void*
          call_int_method_v : Void*
          call_int_method_a : (Env, JObject, JMethodID, Int64*) -> Int32
          call_long_method : Void*
          call_long_method_v : Void*
          call_long_method_a : Void*
          call_float_method : Void*
          call_float_method_v : Void*
          call_float_method_a : Void*
          call_double_method : Void*
          call_double_method_v : Void*
          call_double_method_a : Void*
          call_void_method : Void*
          call_void_method_v : Void*
          call_void_method_a : (Env, JObject, JMethodID, Int64*) -> Void
          call_nonvirtual_object_method : Void*
          call_nonvirtual_object_method_v : Void*
          call_nonvirtual_object_method_a : Void*
          call_nonvirtual_boolean_method : Void*
          call_nonvirtual_boolean_method_v : Void*
          call_nonvirtual_boolean_method_a : Void*
          call_nonvirtual_byte_method : Void*
          call_nonvirtual_byte_method_v : Void*
          call_nonvirtual_byte_method_a : Void*
          call_nonvirtual_char_method : Void*
          call_nonvirtual_char_method_v : Void*
          call_nonvirtual_char_method_a : Void*
          call_nonvirtual_short_method : Void*
          call_nonvirtual_short_method_v : Void*
          call_nonvirtual_short_method_a : Void*
          call_nonvirtual_int_method : Void*
          call_nonvirtual_int_method_v : Void*
          call_nonvirtual_int_method_a : Void*
          call_nonvirtual_long_method : Void*
          call_nonvirtual_long_method_v : Void*
          call_nonvirtual_long_method_a : Void*
          call_nonvirtual_float_method : Void*
          call_nonvirtual_float_method_v : Void*
          call_nonvirtual_float_method_a : Void*
          call_nonvirtual_double_method : Void*
          call_nonvirtual_double_method_v : Void*
          call_nonvirtual_double_method_a : Void*
          call_nonvirtual_void_method : Void*
          call_nonvirtual_void_method_v : Void*
          call_nonvirtual_void_method_a : Void*
          get_field_i_d : Void*
          get_object_field : Void*
          get_boolean_field : Void*
          get_byte_field : Void*
          get_char_field : Void*
          get_short_field : Void*
          get_int_field : Void*
          get_long_field : Void*
          get_float_field : Void*
          get_double_field : Void*
          set_object_field : Void*
          set_boolean_field : Void*
          set_byte_field : Void*
          set_char_field : Void*
          set_short_field : Void*
          set_int_field : Void*
          set_long_field : Void*
          set_float_field : Void*
          set_double_field : Void*
          get_static_method_i_d : Void*
          call_static_object_method : Void*
          call_static_object_method_v : Void*
          call_static_object_method_a : Void*
          call_static_boolean_method : Void*
          call_static_boolean_method_v : Void*
          call_static_boolean_method_a : Void*
          call_static_byte_method : Void*
          call_static_byte_method_v : Void*
          call_static_byte_method_a : Void*
          call_static_char_method : Void*
          call_static_char_method_v : Void*
          call_static_char_method_a : Void*
          call_static_short_method : Void*
          call_static_short_method_v : Void*
          call_static_short_method_a : Void*
          call_static_int_method : Void*
          call_static_int_method_v : Void*
          call_static_int_method_a : Void*
          call_static_long_method : Void*
          call_static_long_method_v : Void*
          call_static_long_method_a : Void*
          call_static_float_method : Void*
          call_static_float_method_v : Void*
          call_static_float_method_a : Void*
          call_static_double_method : Void*
          call_static_double_method_v : Void*
          call_static_double_method_a : Void*
          call_static_void_method : Void*
          call_static_void_method_v : Void*
          call_static_void_method_a : Void*
          get_static_field_i_d : Void*
          get_static_object_field : Void*
          get_static_boolean_field : Void*
          get_static_byte_field : Void*
          get_static_char_field : Void*
          get_static_short_field : Void*
          get_static_int_field : Void*
          get_static_long_field : Void*
          get_static_float_field : Void*
          get_static_double_field : Void*
          set_static_object_field : Void*
          set_static_boolean_field : Void*
          set_static_byte_field : Void*
          set_static_char_field : Void*
          set_static_short_field : Void*
          set_static_int_field : Void*
          set_static_long_field : Void*
          set_static_float_field : Void*
          set_static_double_field : Void*
          new_string : Void*
          get_string_length : Void*
          get_string_chars : Void*
          release_string_chars : Void*
          new_string_utf : (Env, UInt8*) -> JString
          get_string_utf_length : (Env, JString) -> Int32
          get_string_utf_chars : (Env, JString, UInt8*) -> UInt8*
          release_string_utf_chars : (Env, JString, UInt8*) -> Void
          get_array_length : (Env, JObject) -> Int32
          new_object_array : Void*
          get_object_array_element : Void*
          set_object_array_element : Void*
          new_boolean_array : Void*
          new_byte_array : (Env, Int32) -> JByteArray
          new_char_array : Void*
          new_short_array : Void*
          new_int_array : Void*
          new_long_array : Void*
          new_float_array : Void*
          new_double_array : Void*
          get_boolean_array_elements : Void*
          get_byte_array_elements : Void*
          get_char_array_elements : Void*
          get_short_array_elements : Void*
          get_int_array_elements : Void*
          get_long_array_elements : Void*
          get_float_array_elements : Void*
          get_double_array_elements : Void*
          release_boolean_array_elements : Void*
          release_byte_array_elements : Void*
          release_char_array_elements : Void*
          release_short_array_elements : Void*
          release_int_array_elements : Void*
          release_long_array_elements : Void*
          release_float_array_elements : Void*
          release_double_array_elements : Void*
          get_boolean_array_region : Void*
          get_byte_array_region : (Env, JByteArray, Int32, Int32, UInt8*) -> Void
          get_char_array_region : Void*
          get_short_array_region : Void*
          get_int_array_region : Void*
          get_long_array_region : Void*
          get_float_array_region : Void*
          get_double_array_region : Void*
          set_boolean_array_region : Void*
          set_byte_array_region : (Env, JByteArray, Int32, Int32, UInt8*) -> Void
          set_char_array_region : Void*
          set_short_array_region : Void*
          set_int_array_region : Void*
          set_long_array_region : Void*
          set_float_array_region : Void*
          set_double_array_region : Void*
          register_natives : Void*
          unregister_natives : Void*
          monitor_enter : Void*
          monitor_exit : Void*
          get_java_v_m : Void*
          get_string_region : Void*
          get_string_u_t_f_region : Void*
          get_primitive_array_critical : Void*
          release_primitive_array_critical : Void*
          get_string_critical : Void*
          release_string_critical : Void*
          new_weak_global_ref : Void*
          delete_weak_global_ref : Void*
          exception_check : (Env) -> UInt8
          new_direct_byte_buffer : Void*
          get_direct_buffer_address : Void*
          get_direct_buffer_capacity : Void*
          get_object_ref_type : Void*
        end

        # const struct JNIInvokeInterface* — reserved0..2 then the
        # invocation functions (Android's AttachCurrentThread takes a
        # plain void*, not varargs, in C).
        struct JNIInvokeInterface
          reserved0 : Void*
          reserved1 : Void*
          reserved2 : Void*
          destroy_java_vm : (JavaVM) -> Int32
          attach_current_thread : (JavaVM, Env*, Void*) -> Int32
          detach_current_thread : (JavaVM) -> Int32
          get_env : (JavaVM, Env*, Int32) -> Int32
          attach_current_thread_as_daemon : (JavaVM, Env*, Void*) -> Int32
        end
      end

      # Convenience layer over the raw tables. All methods expect to be
      # called from the Crystal host thread (see the threading note at
      # the top of the file).
      class JNI
        Log = ::Log.for("positron.android.jni")

        @vm : LibJNI::JavaVM?
        @env : LibJNI::Env?
        @method_cache = {} of {UInt64, String, String} => LibJNI::JMethodID

        class_property instance = JNI.new

        # Called once by the boot entry with the JavaVM cached by the
        # C shim's JNI_OnLoad.
        def self.vm=(vm : LibJNI::JavaVM) : Nil
          instance.set_vm(vm)
        end

        def set_vm(@vm) : Nil
        end

        # The env of the (attached) Crystal host thread.
        def env : LibJNI::Env
          env = @env
          return env if env

          vm = @vm.not_nil! "JNI vm not set (call JNI.vm= from the boot entry)"
          envp = Pointer(LibJNI::Env).malloc(1)
          # AttachCurrentThread is idempotent for already-attached
          # threads, so this is safe to repeat.
          rc = vm.value.attach_current_thread.call(vm, envp, Pointer(Void).null)
          unless rc == 0
            raise "AttachCurrentThread failed: #{rc}"
          end
          @env = envp.value
        end

        # True when a Java exception is pending; describes and clears
        # it, logging through the standard Crystal logger.
        def check_exception : Bool
          e = env
          return false unless e.value.exception_check.call(e) != 0
          Log.warn { "pending Java exception:" }
          e.value.exception_describe.call(e)
          e.value.exception_clear.call(e)
          true
        end

        # GetMethodID with a per-object cache. All our calls target the
        # long-lived bridge object, whose class never changes.
        def method_id(obj : LibJNI::JObject, name : String, sig : String) : LibJNI::JMethodID
          key = {obj.address, name, sig}
          if mid = @method_cache[key]?
            return mid
          end
          e = env
          cls = e.value.get_object_class.call(e, obj)
          mid = e.value.get_method_id.call(e, cls, name.to_unsafe, sig.to_unsafe)
          check_exception
          raise "GetMethodID failed: #{name}#{sig}" unless mid
          @method_cache[key] = mid
          mid
        end

        # Zero-argument default for the Indexable-based call helpers.
        EMPTY_ARGS = [] of Int64

        def call_void(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : Nil
          e = env
          mid = method_id(obj, name, sig)
          e.value.call_void_method_a.call(e, obj, mid, args_buffer(args))
          check_exception
        end

        def call_string(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : String?
          e = env
          mid = method_id(obj, name, sig)
          result = e.value.call_object_method_a.call(e, obj, mid, args_buffer(args))
          check_exception
          result ? from_java(result.as(LibJNI::JString)) : nil
        end

        def call_bool(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : Bool
          e = env
          mid = method_id(obj, name, sig)
          result = e.value.call_boolean_method_a.call(e, obj, mid, args_buffer(args))
          check_exception
          result != 0
        end

        def call_int(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : Int32
          e = env
          mid = method_id(obj, name, sig)
          result = e.value.call_int_method_a.call(e, obj, mid, args_buffer(args))
          check_exception
          result
        end

        # --- Marshalling helpers ---

        def to_java(str : String) : LibJNI::JString
          e = env
          jstr = e.value.new_string_utf.call(e, str.to_unsafe)
          check_exception
          raise "NewStringUTF failed" unless jstr
          jstr
        end

        def from_java(jstr : LibJNI::JString) : String?
          e = env
          chars = e.value.get_string_utf_chars.call(e, jstr, Pointer(UInt8).null)
          return nil unless chars
          # The Java-allocated buffer is copied immediately, so the
          # String never outlives the release below.
          str = String.new(chars)
          e.value.release_string_utf_chars.call(e, jstr, chars)
          str
        end

        def new_byte_array(bytes : Bytes) : LibJNI::JByteArray
          e = env
          arr = e.value.new_byte_array.call(e, bytes.size)
          check_exception
          raise "NewByteArray failed" unless arr
          e.value.set_byte_array_region.call(e, arr, 0, bytes.size, bytes.to_unsafe)
          arr
        end

        def from_byte_array(arr : LibJNI::JByteArray) : Bytes
          e = env
          len = e.value.get_array_length.call(e, arr)
          bytes = Bytes.new(len)
          e.value.get_byte_array_region.call(e, arr, 0, len, bytes.to_unsafe)
          check_exception
          bytes
        end

        # Materialize a splat into a jvalue[] the C ABI expects. The
        # buffer is heap-allocated and GC-scanned for the duration of
        # the call; the callee does not retain it (JNI jvalue arrays
        # are copied by the VM, never stored).
        private def args_buffer(args : Indexable(Int64))
          ptr = Pointer(Int64).malloc(args.size)
          args.each_with_index { |v, i| ptr[i] = v }
          ptr
        end
      end
    end
  end
end
