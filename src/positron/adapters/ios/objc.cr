# Minimal Objective-C runtime layer for the iOS adapters.
#
# Port of `adapters/macos/objc.cr` (see the dispatch-strategy notes
# there — they apply unchanged): Positron talks to UIKit / WebKit
# through the ObjC runtime directly (objc_msgSend + dynamically
# registered classes), so no external bindings shard is needed.
#
# Differences from the macOS layer:
#   * Links UIKit instead of AppKit (WebKit stays — WKWebView exists
#     on iOS).
#   * No `NSApplication` helpers: on iOS `UIApplicationMain` is called
#     by the event loop (`event_loop/ios.cr`) and owns the process.
#   * `bind_target` accepts the iOS adapter types.
#
# Crystal allows exactly ONE declaration per C symbol program-wide;
# this file never compiles together with `adapters/macos/objc.cr`
# (mutually exclusive target flags), so the parallel `lib LibMsg`
# declaration is safe.
require "log"

module Positron
  module Adapters
    module IOS
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

        # Method dispatch with a typed NSRect (== CGRect on iOS) first
        # argument — see `adapters/macos/objc.cr` module docs
        # (`method_invoke` path for HFA-struct arguments). Works for
        # `initWithFrame:` too: extra trailing arguments are ignored.
        def invoke_rect3(receiver : Void*, selector : String, rect : LibObjC::NSRect,
                         a2 : Void* = Pointer(Void).null,
                         a3 : Void* = Pointer(Void).null,
                         a4 : Void* = Pointer(Void).null) : Void*
          method = LibObjC.class_getInstanceMethod(LibObjC.object_getClass(receiver), sel(selector))
          raise "no instance method '#{selector}'" if method.null?
          LibInvoke.invoke_rect3(receiver, method, rect, a2, a3, a4)
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

        # Invoke an Objective-C block literal taking one pointer-sized
        # argument — WebKit hands delegate answers back through such
        # blocks. The third word of a block literal is its invoke
        # function, whose implicit first argument is the block itself.
        def call_block1(block : Void*, arg : Void*) : Nil
          return if block.null?
          invoke = (block.as(UInt8*) + 16).as(Pointer(Void*)).value
          Proc(Void*, Void*, Nil).new(invoke, Pointer(Void).null).call(block, arg)
        end

        # --- Autorelease pools ---
        # UIKit calls produce autoreleased objects; keep them bounded
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
        def bind_target(objc_obj : Void*, target : WebViewPort | TrayPort | EventLoop::IOS) : Nil
          @@targets[objc_obj] = target
        end

        def target_for(objc_obj : Void*) : WebViewPort | TrayPort | EventLoop::IOS | Nil
          @@targets[objc_obj]?
        end

        @@targets = {} of Void* => WebViewPort | TrayPort | EventLoop::IOS

        # The adapter that UIApplicationMain's application delegate
        # forwards to. Unlike desktop delegates, the AppDelegate
        # instance is created by UIKit itself (from the class name
        # passed to UIApplicationMain), so it cannot be registered in
        # `bind_target` beforehand — the event loop sets this class var
        # before handing control to UIApplicationMain.
        class_property app_delegate_target : (WebViewPort | EventLoop::IOS | Nil)
      end

      # A message send through NSInvocation — for signatures the fixed
      # `objc_msgSend` declaration cannot express: struct or float
      # arguments, 4+ arguments, struct returns (`bounds`, ...).
      # Identical to `Adapters::MacOS::ObjC::Call` — see the notes
      # there.
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

        def bool(index : Int32, value : Bool) : self
          int(index, value ? 1 : 0)
        end

        def rect(index : Int32, rect : LibObjC::NSRect) : self
          buffer = Pointer(LibObjC::NSRect).malloc(1)
          buffer.value = rect
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

        def ret_rect : LibObjC::NSRect
          buffer = Pointer(LibObjC::NSRect).malloc(1)
          ObjC.send1(@invocation, ObjC.sel("getReturnValue:"), buffer.as(Void*))
          buffer.value
        end
      end

      # Objective-C runtime functions plus the C structs used by value.
      # CGFloat is 64-bit on all arm64 Apple targets (device and
      # simulator), so Float64 struct fields are exact.
      @[Link("objc")]
      @[Link(framework: "UIKit")]
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

      # Dispatch path for methods whose first argument is an NSRect
      # (CGRect) by value: `method_invoke` is a public libobjc
      # trampoline with the same ABI as the invoked method, so a typed
      # rect parameter is marshalled by the compiler (HFA → FP
      # registers) exactly the way the callee expects.
      @[Link("objc")]
      lib LibInvoke
        fun invoke_rect3 = method_invoke(receiver : Void*, method : Void*, rect : LibObjC::NSRect, a2 : Void*, a3 : Void*, a4 : Void*) : Void*
      end

      @[Link(framework: "UIKit")]
      lib LibUIKit
        # Never returns on success (it runs the main run loop); the
        # event loop calls it once the fiber timer is installed and the
        # AppDelegate class is registered. `delegate_class_name` is an
        # NSString (NOT a C string — passing one crashes the first
        # objc_retain inside UIApplicationMain); it names a class
        # registered through `ObjC.new_class` with Crystal-proc IMPs,
        # which UIKit instantiates itself.
        fun UIApplicationMain(argc : Int32, argv : UInt8**,
                              principal_class_name : Void*,
                              delegate_class_name : Void*) : Int32
      end

      # Process arguments forwarded by the iOS C driver (ios/main.c) so
      # UIApplicationMain sees the real argc/argv.
      lib LibShim
        $g_positron_argc : Int32
        $g_positron_argv : UInt8**
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
