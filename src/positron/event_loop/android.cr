require "log"

module Positron
  module EventLoop
    # Placeholder Android event loop.
    #
    # On Android the UI thread already runs a Looper; Crystal fibers live on a
    # separate native thread. This adapter provides run_on_main marshalling to
    # the Android UI thread.
    class Android < EventLoopPort
      @running = false

      def initialize(@webview : WebViewPort)
      end

      def run
        @running = true
        Log.warn { "Android event loop is a stub" }
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
