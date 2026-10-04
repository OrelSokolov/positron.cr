require "log"
require "../adapters/windows/lib_webview"
require "../adapters/windows/win32"

module Positron
  module EventLoop
    # Windows event loop integration.
    #
    # `webview_run` blocks the main fiber inside the native message pump.
    # Crystal fibers get their turn through a Win32 timer: WM_TIMER is
    # delivered by the pump whenever the message queue runs empty, and its
    # callback calls Fiber.yield — the same cooperative tick the Linux loop
    # implements with a GLib idle source.
    class Windows < EventLoopPort
      TICK_MS  = 15
      TIMER_ID = 1_u64
      @@instance : Windows?

      TIMER_PROC = ->(hwnd : Void*, msg : UInt32, id : UInt64, dwtime : UInt32) do
        Fiber.yield
      end

      @running = false
      @webview : Adapters::Windows::WebView2

      def initialize(webview : WebViewPort)
        @webview = webview.as(Adapters::Windows::WebView2)
        @@instance = self
      end

      def run
        @running = true
        @@instance = self

        Adapters::Windows::Win32::LibUser32.SetTimer(
          Pointer(Void).null, TIMER_ID, TICK_MS, TIMER_PROC.pointer)
        @webview.show
        @webview.run_event_loop
        Adapters::Windows::Win32::LibUser32.KillTimer(Pointer(Void).null, TIMER_ID)
        @running = false
      end

      def stop
        @running = false
        # Thread-safe: terminates the message pump from any fiber.
        @webview.close
      end

      def running? : Bool
        @running
      end

      # Schedule a block on the UI thread via webview_dispatch (the moral
      # equivalent of g_idle_add in the Linux loop).
      def run_on_main(&block : ->) : Nil
        @webview.dispatch_on_ui(&block)
      end
    end
  end
end
