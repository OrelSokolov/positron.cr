# Minimal Objective-C runtime layer for the macOS adapters.
#
# Positron talks to AppKit / WebKit through the ObjC runtime directly
# (objc_msgSend + dynamically registered classes), so no external
# bindings shard is needed.
#
# Crystal allows exactly ONE declaration per C symbol, so the layer is
# built on several dispatch paths:
#
#   * `ObjC.send*` — a single fixed-arity `objc_msgSend(recv, cmd, a1,
#     a2, a3)` declaration. Pointer, integer and bool arguments are
#     register-compatible with this shape (integers are passed as
#     `Pointer(Void).new(value)`); unused trailing arguments are NULL.
#     bool/NSInteger returns are reinterpreted from the id return.
#
#   * `ObjC.invoke_rect3` — `method_invoke(receiver, method, rect, ...)`
#     with a typed NSRect parameter for methods whose first argument is
#     a struct-by-value (`initWithContentRect:…`,
#     `initWithFrame:configuration:`, ...).
#
#   * `ObjC.send_size` — `objc_msgSendSuper` with a typed NSSize
#     parameter for `setContentSize:`-style methods.
#
#   * `ObjC::Call` — NSInvocation-based invocation for everything else
#     with non-HFA arguments: float arguments, 4+ arguments, and all
#     struct RETURNS (`frame`, via `getReturnValue:` — which works even
#     though HFA *arguments* are broken in NSInvocation on arm64).
require "log"

module Positron
  module Adapters
    module MacOS
      module ObjC
        extend self

        # --- Classes & selectors ---

        def cls(name : String) : Void*
          ptr = LibObjC.objc_getClass(name)
          raise "Objective-C class not found: #{name}" if ptr.null?
          ptr
        end

        def cls?(name : String) : Void*?
          ptr = LibObjC.objc_getClass(name)
          ptr.null? ? nil : ptr
        end

        def sel(name : String) : Void*
          LibObjC.sel_registerName(name)
        end

        # --- Fixed-arity message sends ---
        # Extra register arguments beyond the method's real signature
        # are ignored by the callee, so short calls just pass NULLs.

        def send0(recv : Void*, cmd : Void*) : Void*
          LibMsg.msg(recv, cmd, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
        end

        def send1(recv : Void*, cmd : Void*, a1 : Void*) : Void*
          LibMsg.msg(recv, cmd, a1, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
        end

        def send2(recv : Void*, cmd : Void*, a1 : Void*, a2 : Void*) : Void*
          LibMsg.msg(recv, cmd, a1, a2, Pointer(Void).null, Pointer(Void).null)
        end

        def send3(recv : Void*, cmd : Void*, a1 : Void*, a2 : Void*, a3 : Void*) : Void*
          LibMsg.msg(recv, cmd, a1, a2, a3, Pointer(Void).null)
        end

        def send4(recv : Void*, cmd : Void*, a1 : Void*, a2 : Void*, a3 : Void*, a4 : Void*) : Void*
          LibMsg.msg(recv, cmd, a1, a2, a3, a4)
        end

        # Pass an integer-sized value (NSInteger, NSUInteger, BOOL) as a
        # message argument.
        def int_arg(value : Int) : Void*
          Pointer(Void).new(value.to_u64!)
        end

        def bool_arg(value : Bool) : Void*
          int_arg(value ? 1 : 0)
        end

        # BOOL returns come back in the low byte of the id return.
        def send0_b(recv : Void*, cmd : Void*) : Bool
          (send0(recv, cmd).address & 0xFF) != 0
        end

        def send1_b(recv : Void*, cmd : Void*, a1 : Void*) : Bool
          (send1(recv, cmd, a1).address & 0xFF) != 0
        end

        def send2_b(recv : Void*, cmd : Void*, a1 : Void*, a2 : Void*) : Bool
          (send2(recv, cmd, a1, a2).address & 0xFF) != 0
        end

        # NSInteger/NSUInteger returns occupy the full return register.
        def send0_i(recv : Void*, cmd : Void*) : Int64
          send0(recv, cmd).address.to_i64
        end

        def send1_i(recv : Void*, cmd : Void*, a1 : Void*) : Int64
          send1(recv, cmd, a1).address.to_i64
        end

        # Method dispatch with a typed NSRect first argument — see
        # module docs (`method_invoke` path for HFA-struct arguments).
        def invoke_rect3(receiver : Void*, selector : String, rect : LibObjC::NSRect,
                         a2 : Void* = Pointer(Void).null,
                         a3 : Void* = Pointer(Void).null,
                         a4 : Void* = Pointer(Void).null) : Void*
          method = LibObjC.class_getInstanceMethod(LibObjC.object_getClass(receiver), sel(selector))
          raise "no instance method '#{selector}'" if method.null?
          LibInvoke.invoke_rect3(receiver, method, rect, a2, a3, a4)
        end

        # Method dispatch with a typed NSSize argument (`setContentSize:`
        # family) — the `objc_msgSendSuper` path from the module docs.
        def send_size(receiver : Void*, selector : String, size : LibObjC::NSSize) : Void*
          super_ = LibSuper::ObjCSuper.new(
            receiver: receiver,
            cls: LibObjC.object_getClass(receiver))
          LibSuper.super_size(pointerof(super_), sel(selector), size)
        end

        # --- Bridging values ---

        # Autoreleased NSString (released by the pool drained each event
        # loop tick; wrap pre-run setup in `with_autorelease_pool`).
        def nsstr(s : String) : Void*
          send1(cls("NSString"), sel("stringWithUTF8String:"), s.to_unsafe.as(Void*))
        end

        def to_s(obj : Void*) : String?
          return nil if obj.null?
          cstr = send0(obj, sel("UTF8String"))
          cstr.null? ? nil : String.new(cstr.as(UInt8*))
        end

        # Autoreleased NSData copying `bytes`.
        def nsdata(bytes : Bytes) : Void*
          send2(cls("NSData"), sel("dataWithBytes:length:"),
            bytes.to_unsafe.as(Void*), int_arg(bytes.size))
        end

        def nsurl(url : String) : Void*
          send1(cls("NSURL"), sel("URLWithString:"), nsstr(url))
        end

        def nsbool(value : Bool) : Void*
          send1(cls("NSNumber"), sel("numberWithBool:"), bool_arg(value))
        end

        # --- Autorelease pools ---
        # AppKit calls produce autoreleased objects; keep them bounded
        # by draining a pool per event loop tick (and around setup).

        def with_autorelease_pool(&)
          pool = send0(cls("NSAutoreleasePool"), sel("new"))
          begin
            yield
          ensure
            send0(pool, sel("drain"))
          end
        end

        # --- Dynamic classes for delegate / handler objects ---

        # Creates (or returns an already registered) ObjC class pair
        # deriving from `superclass`. Used to build delegate objects
        # whose methods are Crystal procs installed as IMPs.
        def new_class(name : String, superclass : String = "NSObject") : Void*
          if existing = cls?(name)
            existing
          else
            new_cls = LibObjC.objc_allocateClassPair(cls(superclass), name, 0)
            raise "cannot allocate ObjC class #{name}" if new_cls.null?
            LibObjC.objc_registerClassPair(new_cls)
            new_cls
          end
        end

        def add_protocol(objc_class : Void*, name : String) : Nil
          proto = LibObjC.objc_getProtocol(name)
          LibObjC.class_addProtocol(objc_class, proto) unless proto.null?
        end

        # Associate a native ObjC object with its Crystal adapter so IMP
        # callbacks (which only receive the ObjC receiver) can find the
        # adapter instance. The registry keeps the adapters alive, too.
        def bind_target(objc_obj : Void*, target : WebViewPort | TrayPort | EventLoop::MacOS) : Nil
          @@targets[objc_obj] = target
        end

        def target_for(objc_obj : Void*) : WebViewPort | TrayPort | EventLoop::MacOS | Nil
          @@targets[objc_obj]?
        end

        @@targets = {} of Void* => WebViewPort | TrayPort | EventLoop::MacOS
      end

      # A message send through NSInvocation — for signatures the fixed
      # `objc_msgSend` declaration cannot express: struct or float
      # arguments, 4+ arguments, struct returns (`frame`, NSSize, ...).
      #
      #   call = ObjC::Call.new(receiver, "setContentSize:")
      #   call.size(2, width.to_f64, height.to_f64)
      #   call.invoke
      class ObjC::Call
        @invocation : Void*
        @signature : Void*

        def initialize(receiver : Void*, selector : String)
          @signature = ObjC.send1(receiver, ObjC.sel("methodSignatureForSelector:"), ObjC.sel(selector))
          raise "no method signature for #{selector} on #{receiver}" if @signature.null?
          @invocation = ObjC.send1(ObjC.cls("NSInvocation"), ObjC.sel("invocationWithMethodSignature:"), @signature)
          ObjC.send1(@invocation, ObjC.sel("setTarget:"), receiver)
          ObjC.send1(@invocation, ObjC.sel("setSelector:"), ObjC.sel(selector))
        end

        # Argument indices follow the ObjC convention: 0 = self,
        # 1 = _cmd, first real argument = 2.

        def ptr(index : Int32, value : Void*) : self
          ObjC.send2(@invocation, ObjC.sel("setArgument:atIndex:"), value, ObjC.int_arg(index))
          self
        end

        def int(index : Int32, value : Int64) : self
          buffer = Pointer(Int64).malloc(1)
          buffer.value = value
          ptr(index, buffer.as(Void*))
        end

        def double(index : Int32, value : Float64) : self
          buffer = Pointer(Float64).malloc(1)
          buffer.value = value
          ptr(index, buffer.as(Void*))
        end

        def bool(index : Int32, value : Bool) : self
          int(index, value ? 1 : 0)
        end

        def rect(index : Int32, rect : LibObjC::NSRect) : self
          buffer = Pointer(LibObjC::NSRect).malloc(1)
          buffer.value = rect
          ptr(index, buffer.as(Void*))
        end

        def size(index : Int32, size : LibObjC::NSSize) : self
          buffer = Pointer(LibObjC::NSSize).malloc(1)
          buffer.value = size
          ptr(index, buffer.as(Void*))
        end

        def invoke : self
          ObjC.send0(@invocation, ObjC.sel("invoke"))
          self
        end

        def return_length : Int64
          ObjC.send0_i(@signature, ObjC.sel("methodReturnLength"))
        end

        def ret_ptr : Void*
          buffer = Pointer(Void*).malloc(1)
          ObjC.send1(@invocation, ObjC.sel("getReturnValue:"), buffer.as(Void*))
          buffer.value
        end

        def ret_bool : Bool
          buffer = Pointer(UInt8).malloc(1)
          ObjC.send1(@invocation, ObjC.sel("getReturnValue:"), buffer.as(Void*))
          buffer.value != 0
        end

        def ret_i64 : Int64
          buffer = Pointer(Int64).malloc(1)
          ObjC.send1(@invocation, ObjC.sel("getReturnValue:"), buffer.as(Void*))
          buffer.value
        end

        # CGFloat / double returns (e.g. NSColor component getters).
        def ret_f64 : Float64
          buffer = Pointer(Float64).malloc(1)
          ObjC.send1(@invocation, ObjC.sel("getReturnValue:"), buffer.as(Void*))
          buffer.value
        end

        def ret_rect : LibObjC::NSRect
          buffer = Pointer(LibObjC::NSRect).malloc(1)
          ObjC.send1(@invocation, ObjC.sel("getReturnValue:"), buffer.as(Void*))
          buffer.value
        end

        def ret_size : LibObjC::NSSize
          buffer = Pointer(LibObjC::NSSize).malloc(1)
          ObjC.send1(@invocation, ObjC.sel("getReturnValue:"), buffer.as(Void*))
          buffer.value
        end
      end

      # Shared NSApplication helpers. Every adapter calls `App.ensure_app`
      # before touching AppKit, so setup order between the host, the
      # tray and the webview does not matter.
      module App
        extend self

        @@nsapp : Void*?

        def nsapp : Void*
          @@nsapp ||= ObjC.send0(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication"))
        end

        # NSApplicationActivationPolicyRegular (0): regular dock app,
        # matching the Linux reference behaviour.
        def ensure_app : Nil
          ObjC.with_autorelease_pool do
            ObjC.send1(nsapp, ObjC.sel("setActivationPolicy:"), ObjC.int_arg(0))
          end
        end

        def activate! : Nil
          ObjC.send1(nsapp, ObjC.sel("activateIgnoringOtherApps:"), ObjC.bool_arg(true))
        end

        def request_stop : Nil
          return if @@stop_requested
          @@stop_requested = true
          ObjC.send1(nsapp, ObjC.sel("stop:"), nsapp)
          LibCF.CFRunLoopStop(LibCF.CFRunLoopGetMain)
        end

        @@stop_requested = false
      end

      # Objective-C runtime functions plus the C structs used by value.
      @[Link("objc")]
      @[Link(framework: "AppKit")]
      @[Link(framework: "WebKit")]
      lib LibObjC
        fun objc_getClass(name : LibC::Char*) : Void*
        fun sel_registerName(str : LibC::Char*) : Void*
        fun objc_allocateClassPair(superclass : Void*, name : LibC::Char*, extraBytes : Int32) : Void*
        fun objc_registerClassPair(cls : Void*) : Nil
        fun objc_getProtocol(name : LibC::Char*) : Void*
        fun object_getClass(obj : Void*) : Void*
        fun class_addMethod(cls : Void*, name : Void*, imp : Void*, types : LibC::Char*) : UInt8
        fun class_addProtocol(cls : Void*, protocol : Void*) : UInt8
        fun class_getInstanceMethod(cls : Void*, name : Void*) : Void*

        struct NSPoint
          x : Float64
          y : Float64
        end

        struct NSSize
          width : Float64
          height : Float64
        end

        struct NSRect
          origin : NSPoint
          size : NSSize
        end
      end

      # The single objc_msgSend declaration (see module docs). Pointer,
      # integer and bool arguments are all register-compatible; unused
      # trailing arguments must be NULL.
      @[Link("objc")]
      lib LibMsg
        fun msg = objc_msgSend(recv : Void*, cmd : Void*, a1 : Void*, a2 : Void*, a3 : Void*, a4 : Void*) : Void*
      end

      # Dispatch path for methods whose first argument is an NSRect by
      # value: `method_invoke` is a public libobjc trampoline with the
      # same ABI as the invoked method, so a typed NSRect parameter is
      # marshalled by the compiler (HFA → FP registers) exactly the way
      # the callee expects. Extra trailing arguments are ignored.
      @[Link("objc")]
      lib LibInvoke
        fun invoke_rect3 = method_invoke(receiver : Void*, method : Void*, rect : LibObjC::NSRect, a2 : Void*, a3 : Void*, a4 : Void*) : Void*
      end

      # Dispatch path for NSSize-by-value methods (`setContentSize:`
      # family) via objc_msgSendSuper with a typed NSSize parameter.
      # The super struct names the receiver's own class, so the method
      # lookup behaves like a normal send.
      @[Link("objc")]
      lib LibSuper
        struct ObjCSuper
          receiver : Void*
          cls : Void*
        end

        fun super_size = objc_msgSendSuper(super_ : ObjCSuper*, cmd : Void*, size : LibObjC::NSSize) : Void*
      end

      @[Link(framework: "CoreFoundation")]
      lib LibCF
        fun CFRelease(cf : Void*)
        fun CFRunLoopGetMain : Void*
        fun CFRunLoopStop(run_loop : Void*) : Nil
        fun CFRunLoopWakeUp(run_loop : Void*) : Nil
        fun CFAbsoluteTimeGetCurrent : Float64
        fun CFRunLoopTimerCreate(allocator : Void*, fire_time : Float64, interval : Float64,
                                 flags : UInt64, order : Int64, callout : (Void*, Void*) -> Nil,
                                 context : CFRunLoopTimerContext*) : Void*
        fun CFRunLoopAddTimer(run_loop : Void*, timer : Void*, mode : Void*) : Nil
        fun CFRunLoopTimerInvalidate(timer : Void*) : Nil

        $kCFRunLoopCommonModes : Void*

        struct CFRunLoopTimerContext
          version : Int64
          info : Void*
          retain : Void*
          release : Void*
          copy_description : Void*
        end
      end
    end
  end
end
