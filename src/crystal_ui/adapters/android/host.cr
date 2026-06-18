require "log"

module CrystalUI
  module Adapters
    module Android
      # Placeholder Android mobile host.
      #
      # A full implementation keeps a JNI reference to the Android WebView and
      # Activity, calls evaluateJavascript on the UI thread, and forwards OS
      # events (lifecycle, deep links, permissions, push) to the Crystal Host.
      class Host < MobileHost
        def eval_js(script : String)
          Log.warn { "Android eval_js not implemented" }
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
