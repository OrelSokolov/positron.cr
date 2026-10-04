require "log"

module Positron
  module EventLoop
    # Placeholder Windows event loop.
    #
    # A full implementation integrates the Win32 message pump with the Crystal
    # fiber scheduler (e.g. via a hidden message window, PeekMessage and a
    # scheduler hook).
    class Windows < EventLoopPort
      @running = false

      def initialize(@webview : WebViewPort)
      end

      def run
        @running = true
        Log.warn { "Windows event loop is a stub" }
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
