require "log"
require "../adapters/macos/objc"

module Positron
  # macOS event loop integration.
  #
  # `run` enters `[NSApp run]`; a repeating CFRunLoopTimer (added to
  # the common run-loop modes so it keeps firing during menu tracking)
  # drains the run_on_main queue and yields to the Crystal fiber
  # scheduler once per pass — the same cooperative pattern the Linux
  # adapter achieves with a GLib idle source. The timer uses the
  # CoreFoundation C API directly (no ObjC message shapes involved).
  class EventLoop::MacOS < EventLoopPort
    TICK_INTERVAL = 0.01 # seconds; 100 Hz, fiber-friendly

    @running = false
    @webview : WebViewPort
    @queue = [] of Proc(Nil)

    alias TimerContext = Positron::Adapters::MacOS::LibCF::CFRunLoopTimerContext
    ObjC  = Positron::Adapters::MacOS::ObjC
    LibCF = Positron::Adapters::MacOS::LibCF

    # Kept alive for the lifetime of the process: the C callback and
    # its context (the boxed self passed through `info`). The context
    # itself lives in heap memory we own: Crystal boxes struct class
    # variables, so `pointerof(@@…)` would point at a pointer slot —
    # CoreFoundation must see raw struct bytes instead.
    @@timer_callout : Proc(Void*, Void*, Nil)?
    @@timer_context_box : Void*?

    @timer_context : Pointer(TimerContext)

    def initialize(@webview : WebViewPort)
      Adapters::MacOS::App.ensure_app
      @timer_context = Pointer(TimerContext).malloc(1)
    end

    def run
      @running = true

      install_fiber_timer

      @webview.show
      ObjC.send0(Adapters::MacOS::App.nsapp, ObjC.sel("run"))
      @running = false
    end

    def stop
      @running = false
      Adapters::MacOS::App.request_stop
    end

    def running? : Bool
      @running
    end

    # Schedule a block on the main/GUI thread. Everything (fibers
    # included) lives on one OS thread, so this just enqueues work for
    # the next timer pass; the wake-up covers the idle-loop case.
    def run_on_main(&block : ->) : Nil
      @queue << block
      LibCF.CFRunLoopWakeUp(LibCF.CFRunLoopGetMain)
    end

    # --- Internals ---

    protected def drain_queue : Nil
      while (block = @queue.shift?)
        block.call
      end
    end

    private def install_fiber_timer : Nil
      @@timer_callout = ->(timer : Void*, info : Void*) {
        loop = Box(EventLoop::MacOS).unbox(info)
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

      timer = LibCF.CFRunLoopTimerCreate(
        Pointer(Void).null, # default allocator
        LibCF.CFAbsoluteTimeGetCurrent + TICK_INTERVAL,
        TICK_INTERVAL,
        0_u64, 0_i64,
        @@timer_callout.not_nil!,
        @timer_context)

      LibCF.CFRunLoopAddTimer(
        LibCF.CFRunLoopGetMain,
        timer, LibCF.kCFRunLoopCommonModes)
    end
  end
end
