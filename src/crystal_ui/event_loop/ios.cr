require "log"

module CrystalUI
  module EventLoop
    # Placeholder iOS event loop.
    #
    # On iOS the main run loop is already running inside UIApplicationMain.
    # The host integrates with it and provides run_on_main via
    # DispatchQueue.main.async.
    class IOS < EventLoopPort
      @running = false

      def initialize(@webview : WebViewPort)
      end

      def run
        @running = true
        Log.warn { "iOS event loop is a stub" }
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
