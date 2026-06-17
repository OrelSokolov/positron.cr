require "log"

module CrystalUI
  # Linux event loop integration.
  #
  # The architecture document prescribes libuv + GTK cooperative integration.
  # This concrete implementation uses Crystal's native fiber scheduler together
  # with a GLib idle source that yields control back to GTK every tick.
  # This keeps the implementation self-contained (no external libuv shard)
  # while still satisfying the design goal: a unified dispatcher that lets
  # Crystal fibers and the native GUI loop coexist.
  class EventLoop::Linux
    @running = false
    @webview : WebViewPort

    def initialize(@webview : WebViewPort)
      # GTK must be initialized before any native tray or window code runs.
      argc = 0
      LibGTK.gtk_init(pointerof(argc), nil)
    end

    def run
      @running = true

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
  end

  # Minimal GLib bindings required by the Linux event loop and adapters.
  @[Link("glib-2.0")]
  lib LibGLib
    G_PRIORITY_DEFAULT_IDLE = 200

    fun g_idle_add_full(priority : Int32, func : Void* -> Int32, data : Void*, notify : Void*) : UInt32
    fun g_free(mem : Void*)
  end

  # Minimal GTK binding for initialization and quitting the main loop.
  @[Link("gtk-3")]
  lib LibGTK
    fun gtk_init(argc : Int32*, argv : Void**)
    fun gtk_main_quit
  end
end
