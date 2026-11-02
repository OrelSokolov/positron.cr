require "log"

module Positron
  # Linux event loop integration.
  #
  # The architecture document prescribes libuv + GTK cooperative integration.
  # This concrete implementation uses Crystal's native fiber scheduler together
  # with a GLib idle source that yields control back to GTK every tick.
  # This keeps the implementation self-contained (no external libuv shard)
  # while still satisfying the design goal: a unified dispatcher that lets
  # Crystal fibers and the native GUI loop coexist.
  class EventLoop::Linux < EventLoopPort
    @running = false
    @gui_fiber : Fiber?
    @webview : WebViewPort
    # Pending run_on_main callbacks keyed by id. The GLib side only ever
    # sees the id (a plain integer packed into the data pointer), so no
    # GC-heap pointer ever crosses the FFI boundary.
    @main_callbacks = {} of UInt64 => Proc(Nil)
    @next_callback_id : UInt64 = 0
    # Single GTK loop per process; the idle trampoline needs to reach the
    # owning instance and C callbacks cannot capture.
    @@current : self?

    def initialize(@webview : WebViewPort)
      @@current = self
      # GTK must be initialized before any native tray or window code runs.
      argc = 0
      LibGTK.gtk_init(pointerof(argc), nil)
    end

    def run
      @running = true
      # Remember the GUI fiber: the native loop and every callback it
      # fires (idles, GTK signals) run here. gui_thread? compares
      # against it so background helpers can refuse UI-blocking waits.
      @gui_fiber = Fiber.current

      # Bridge Crystal fibers into GTK: an idle callback drains pending
      # Crystal scheduler work and then returns to GTK.
      LibGLib.g_idle_add_full(
        LibGLib::G_PRIORITY_DEFAULT_IDLE,
        ->(data : Void*) {
          Fiber.yield
          1 # continue calling this idle source
        },
        nil,
        nil
      )

      # Show the window and enter the GTK main loop.
      @webview.show
      @webview.run_event_loop
    end

    def stop
      @running = false
      LibGTK.gtk_main_quit
    end

    def running? : Bool
      @running
    end

    def gui_thread? : Bool
      Fiber.current == @gui_fiber
    end

    # Schedule a block on the GTK main thread.
    #
    # GC-safe by construction: the Boehm GC never scans GLib's idle
    # queue, so handing it a Box pointer (as this method used to) let
    # the GC collect the box — and everything its closure captured,
    # command payloads included — before the idle fired: lost promise
    # resolves, garbage command strings, segfaults. Instead the closure
    # lives in @main_callbacks (a GC-scanned Hash) and GLib receives
    # only its integer id encoded as the data pointer. The id is
    # removed only after the block has run, keeping the Proc rooted for
    # the duration of its own execution.
    def run_on_main(&block : ->) : Nil
      id = @next_callback_id += 1
      @main_callbacks[id] = block

      LibGLib.g_idle_add(
        ->(data : Void*) {
          if owner = @@current
            if callback = owner.main_callbacks[data.address]?
              callback.call
              owner.main_callbacks.delete(data.address)
            end
          end
          0 # G_SOURCE_REMOVE
        }.pointer.as(Void*),
        Pointer(Void).new(id)
      )
    end

    # Read access for the idle trampoline (C callbacks cannot capture).
    protected def main_callbacks
      @main_callbacks
    end

    # Minimal GLib bindings required by the Linux event loop and adapters.
    @[Link("glib-2.0")]
    lib LibGLib
      G_PRIORITY_DEFAULT_IDLE = 200

      fun g_idle_add_full(priority : Int32, func : Void* -> Int32, data : Void*, notify : Void*) : UInt32
      fun g_idle_add(func : Void*, data : Void*) : UInt32
      fun g_free(mem : Void*)
    end

    # Minimal GTK binding for initialization and quitting the main loop.
    @[Link("gtk-3")]
    lib LibGTK
      fun gtk_init(argc : Int32*, argv : Void**)
      fun gtk_main_quit
    end
  end
end
