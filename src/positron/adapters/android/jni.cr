# JNI access layer for the Android host.
#
# IMPORTANT: Crystal never dereferences the JNI function tables
# (JNINativeInterface / JNIInvokeInterface) here. Indirect calls
# through table slots from cross-compiled Crystal segfault on
# aarch64-linux-android (observed as SIGSEGV on the first table call,
# reported by Zygote as a clean exit(11) in release builds), while the
# identical C calls from the same thread work — root cause unknown.
# Every JNIEnv access therefore goes through plain C trampolines in the
# seam (`positron_jni_*` in android/positron_shim.c); this file keeps
# the typed wrapper API (method caching, marshalling, exception
# handling) on top of them.
#
# Threading rules: only the Crystal host thread may touch this module.
# The seam attaches that thread before the Crystal runtime boots (see
# ps_host_thread in positron_shim.c), so the trampolines' GetEnv
# always succeeds there. Native (Java) threads enter through the C
# shim's queue, never through here.
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
      end

      # Convenience layer over the C-seam trampolines. All methods
      # expect to be called from the Crystal host thread (see the
      # threading note at the top of the file).
      #
      # FIBER RULE: Java method invocation must happen on the GUI
      # fiber's stack. Command handlers run in spawned fibers whose
      # stacks are mmap'd regions far from the stack bounds ART
      # recorded for the attached host thread — the first Java frame
      # pushed there trips ART's stack-overflow check and the call dies
      # with a spurious java.lang.StackOverflowError. Every call_*
      # therefore marshals to the GUI fiber (via the host's
      # run_on_main) when invoked from another fiber, blocking on a
      # channel until the answer arrives. The pump keeps draining the
      # run_on_main queue, so this cannot deadlock.
      class JNI
        Log = ::Log.for("positron.android.jni")

        @method_cache = {} of {UInt64, String, String} => LibJNI::JMethodID

        # Injected by the Android host at boot: answers whether the
        # current fiber is the GUI fiber and schedules a block on it.
        @gui_fiber_check : (-> Bool)?
        @run_on_main : ((->) ->)?

        class_property instance = JNI.new

        def configure_dispatcher(@gui_fiber_check : -> Bool, @run_on_main : (->) ->) : Nil
        end

        # Run the block on the GUI fiber when the caller is elsewhere
        # (see the fiber note above). Without a configured dispatcher
        # (specs, non-host tools) the block runs inline.
        private def on_gui_fiber(&block : -> T) : T forall T
          gui_check = @gui_fiber_check
          runner = @run_on_main
          if gui_check && runner && !gui_check.call
            channel = Channel(T).new
            runner.call(-> { channel.send(block.call) })
            channel.receive
          else
            block.call
          end
        end

        def initialize
          if LibShim.positron_jni_attached == 0
            raise "JNI: host thread is not attached (the C seam attaches it before boot)"
          end
        end

        # True when a Java exception is pending; describes and clears
        # it, logging through the standard Crystal logger.
        def check_exception : Bool
          return false unless LibShim.positron_jni_exception_check != 0
          Log.warn { "pending Java exception:" }
          LibShim.positron_jni_exception_describe
          LibShim.positron_jni_exception_clear
          true
        end

        # GetMethodID with a per-object cache. All our calls target the
        # long-lived bridge object, whose class never changes.
        def method_id(obj : LibJNI::JObject, name : String, sig : String) : LibJNI::JMethodID
          key = {obj.address, name, sig}
          if mid = @method_cache[key]?
            return mid
          end
          mid = LibShim.positron_jni_get_method_id(obj, name.to_unsafe, sig.to_unsafe)
          check_exception
          raise "GetMethodID failed: #{name}#{sig}" unless mid
          @method_cache[key] = mid
          mid
        end

        # Zero-argument default for the Indexable-based call helpers.
        EMPTY_ARGS = [] of Int64

        def call_void(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : Nil
          on_gui_fiber do
            mid = method_id(obj, name, sig)
            LibShim.positron_jni_call_void_a(obj, mid, args_buffer(args))
            check_exception
          end
        end

        def call_string(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : String?
          on_gui_fiber do
            mid = method_id(obj, name, sig)
            result = LibShim.positron_jni_call_object_a(obj, mid, args_buffer(args))
            check_exception
            next nil unless result
            str = from_java(result.as(LibJNI::JString))
            LibShim.positron_jni_delete_local_ref(result)
            str
          end
        end

        def call_bool(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : Bool
          on_gui_fiber do
            mid = method_id(obj, name, sig)
            result = LibShim.positron_jni_call_boolean_a(obj, mid, args_buffer(args))
            check_exception
            result != 0
          end
        end

        def call_int(obj : LibJNI::JObject, name : String, sig : String, args : Indexable(Int64) = EMPTY_ARGS) : Int32
          on_gui_fiber do
            mid = method_id(obj, name, sig)
            result = LibShim.positron_jni_call_int_a(obj, mid, args_buffer(args))
            check_exception
            result
          end
        end

        # --- Marshalling helpers ---

        def to_java(str : String) : LibJNI::JString
          jstr = LibShim.positron_jni_new_string_utf(str.to_unsafe)
          check_exception
          raise "NewStringUTF failed" unless jstr
          jstr
        end

        def from_java(jstr : LibJNI::JString) : String?
          chars = LibShim.positron_jni_string_utf(jstr)
          return nil unless chars
          # The seam already copied the Java buffer; the copy is
          # released after the Crystal String takes its own.
          str = String.new(chars)
          LibShim.positron_shim_free(chars)
          str
        end

        def new_byte_array(bytes : Bytes) : LibJNI::JByteArray
          arr = LibShim.positron_jni_new_byte_array(bytes.to_unsafe, bytes.size)
          check_exception
          raise "NewByteArray failed" unless arr
          arr
        end

        def from_byte_array(arr : LibJNI::JByteArray) : Bytes
          len = LibShim.positron_jni_array_length(arr)
          bytes = Bytes.new(len)
          LibShim.positron_jni_get_byte_array(arr, bytes.to_unsafe, len)
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
