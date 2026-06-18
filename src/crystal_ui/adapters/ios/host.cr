require "log"

module CrystalUI
  module Adapters
    module IOS
      # Placeholder iOS mobile host.
      #
      # A full implementation keeps a reference to the WKWebView and
      # UIViewController, calls evaluateJavaScript on the main thread, and
      # forwards OS events to the Crystal Host through the C-ABI.
      class Host < MobileHost
        def eval_js(script : String)
          Log.warn { "iOS eval_js not implemented" }
        end

        def run_on_main(&block : ->) : Nil
          yield
        end

        def run
          @app.on_ready
        end

        def stop
        end
      end
    end
  end
end
