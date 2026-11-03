require "log"
require "../adapters/ios/objc"

module Positron
  # iOS event loop integration.
  #
  # Same cooperative pattern as `EventLoop::MacOS`: a repeating
  # CFRunLoopTimer on the main run loop (common modes) drains the
  # run_on_main queue and yields to the Crystal fiber scheduler once
  # per pass. The difference is run-loop ownership: on macOS the
  # adapter enters `[NSApp run]`, on iOS `run` registers a
  # dynamically-built UIApplicationDelegate (whose IMPs are Crystal
  # procs, like every other adapter callback) and hands the process
  # over to `UIApplicationMain`, which never returns. The application
  # delegate boots the WebView adapter (`Adapters::IOS::WKWebView#boot`)
  # from `application:didFinishLaunchingWithOptions:` — UI objects may
  # only be created once UIApplication exists — and forwards UIKit
  # lifecycle notifications to `Application#on_lifecycle` with the same
  # state names as the Android shim.
  class EventLoop::IOS < EventLoopPort
    TICK_INTERVAL = 0.01 # seconds; 100 Hz, fiber-friendly

    APP_DELEGATE_CLASS = "PositronAppDelegate"

    @running = false
    @webview : Adapters::IOS::WKWebView
    @queue = [] of Proc(Nil)

    ObjC = Positron::Adapters::IOS::ObjC

    alias TimerContext = Positron::Adapters::IOS::LibCF::CFRunLoopTimerContext

    # Kept alive for the lifetime of the process (see the notes in
    # event_loop/macos.cr): the C callback, its context (the boxed
    # self passed through `info`) and the delegate IMPs.
    @@timer_callout : Proc(Void*, Void*, Nil)?
    @@timer_context_box : Void*?
    @@did_finish_imp : Proc(Void*, Void*, Void*, Void*, Int32)?

    @timer_context : Pointer(TimerContext)

    def initialize(@webview : Adapters::IOS::WKWebView)
      @timer_context = Pointer(TimerContext).malloc(1)
    end

    def run
      @running = true

      install_fiber_timer
      build_app_delegate

      # Never returns on success: UIApplicationMain runs the main run
      # loop (the fiber timer fires from there) and instantiates the
      # app delegate from the class name. argc/argv come from the C
      # driver — UIKit parses argv (passing NULL has been seen to
      # crash early inside UIApplicationMain).
      status = Adapters::IOS::LibUIKit.UIApplicationMain(
        Adapters::IOS::LibShim.g_positron_argc, Adapters::IOS::LibShim.g_positron_argv,
        Pointer(Void).null, ObjC.nsstr(APP_DELEGATE_CLASS))
      @running = false
      raise "UIApplicationMain exited with status #{status}" unless status == 0
    end

    def stop
      @running = false
      # There is no supported way to tear UIApplicationMain down; exit
      # the process like the Android shim does on onDestroy (the
      # Crystal runtime cannot reboot in a reused process anyway).
      LibC.exit(0)
    end

    def running? : Bool
      @running
    end

    # Schedule a block on the main/GUI thread. Everything (fibers
    # included) lives on one OS thread, so this just enqueues work for
    # the next timer pass; the wake-up covers the idle-loop case.
    def run_on_main(&block : ->) : Nil
      @queue << block
      Adapters::IOS::LibCF.CFRunLoopWakeUp(Adapters::IOS::LibCF.CFRunLoopGetMain)
    end

    # --- Internals ---

    protected def drain_queue : Nil
      while (block = @queue.shift?)
        block.call
      end
    end

    private def install_fiber_timer : Nil
      lib_cf = Adapters::IOS::LibCF
      @@timer_callout = ->(timer : Void*, info : Void*) {
        loop = Box(EventLoop::IOS).unbox(info)
        pool = ObjC.send0(ObjC.cls("NSAutoreleasePool"), ObjC.sel("new"))
        begin
          loop.drain_queue
          Fiber.yield
        ensure
          ObjC.send0(pool, ObjC.sel("drain"))
        end
      }

      @@timer_context_box = Box.box(self)
      @timer_context.value = TimerContext.new(
        version: 0,
        info: @@timer_context_box.not_nil!,
        retain: Pointer(Void).null,
        release: Pointer(Void).null,
        copy_description: Pointer(Void).null)

      timer = lib_cf.CFRunLoopTimerCreate(
        Pointer(Void).null, # default allocator
        lib_cf.CFAbsoluteTimeGetCurrent + TICK_INTERVAL,
        TICK_INTERVAL,
        0_u64, 0_i64,
        @@timer_callout.not_nil!,
        @timer_context)

      lib_cf.CFRunLoopAddTimer(
        lib_cf.CFRunLoopGetMain,
        timer, lib_cf.kCFRunLoopCommonModes)
    end

    # Registers the UIApplicationDelegate class UIKit will instantiate.
    # The delegate instance is created by UIApplicationMain itself, so
    # the IMPs reach back through `ObjC.app_delegate_target` instead of
    # the per-instance target registry.
    private def build_app_delegate : Nil
      objc_class = ObjC.new_class(APP_DELEGATE_CLASS)
      ObjC.app_delegate_target = self

      # Lifecycle forwarding — same state names as the Android shim
      # (Application#on_lifecycle "resume"/"pause"/"destroy"). The IMPs
      # must not capture closures (an IMP is called as a plain C
      # function; a capturing Proc expects its context as the first
      # argument), so each selector gets its own capture-free proc —
      # the same pattern as @@message_imp in the webview adapter.
      @@did_finish_imp = ->(objc_self : Void*, _cmd : Void*, application : Void*, launch_options : Void*) : Int32 {
        if (loop = ObjC.app_delegate_target.as?(EventLoop::IOS))
          puts "[positron] didFinishLaunching — booting UI"
          loop.webview.boot
        end
        Log.info { "ios: application did finish launching" }
        1 # YES — launch handled
      }
      Adapters::IOS::LibObjC.class_addMethod(
        objc_class,
        ObjC.sel("application:didFinishLaunchingWithOptions:"),
        @@did_finish_imp.not_nil!.pointer.as(Void*), "i@:@")

      @@did_become_active_imp = ->(objc_self : Void*, _cmd : Void*, application : Void*) {
        Host.current.try(&.app.on_lifecycle("resume"))
      }
      Adapters::IOS::LibObjC.class_addMethod(
        objc_class, ObjC.sel("applicationDidBecomeActive:"),
        @@did_become_active_imp.not_nil!.pointer.as(Void*), "v@:")

      @@did_enter_background_imp = ->(objc_self : Void*, _cmd : Void*, application : Void*) {
        Host.current.try(&.app.on_lifecycle("pause"))
      }
      Adapters::IOS::LibObjC.class_addMethod(
        objc_class, ObjC.sel("applicationDidEnterBackground:"),
        @@did_enter_background_imp.not_nil!.pointer.as(Void*), "v@:")

      @@will_terminate_imp = ->(objc_self : Void*, _cmd : Void*, application : Void*) {
        Host.current.try(&.app.on_lifecycle("destroy"))
      }
      Adapters::IOS::LibObjC.class_addMethod(
        objc_class, ObjC.sel("applicationWillTerminate:"),
        @@will_terminate_imp.not_nil!.pointer.as(Void*), "v@:")
    end

    @@did_become_active_imp : Proc(Void*, Void*, Void*, Nil)?
    @@did_enter_background_imp : Proc(Void*, Void*, Void*, Nil)?
    @@will_terminate_imp : Proc(Void*, Void*, Void*, Nil)?

    protected def webview : Adapters::IOS::WKWebView
      @webview
    end
  end
end
