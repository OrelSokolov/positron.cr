require "log"

module CrystalUI
  module EventLoop
    # Placeholder macOS event loop.
    #
    # A full implementation integrates NSRunLoop/CFRunLoop with the Crystal
    # fiber scheduler (e.g. via a CFRunLoopSource or timer hooked into libuv).
    class MacOS < EventLoopPort
      @running = false

      def initialize(@webview : WebViewPort)
      end

      def run
        @running = true
        Log.warn { "macOS event loop is a stub" }
      end

      def stop
        @running = false
      end

      def running? : Bool
        @running
      end

      def run_on_main(&block : ->) : Nil
        yield
      end
    end
  end
end
