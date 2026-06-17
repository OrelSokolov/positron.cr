require "json"
require "log"

module CrystalUI
  # Desktop host: single process, Crystal owns everything.
  #
  # The DesktopHost wires together the WebView, tray, command registry,
  # plugins, EventBus and the platform event loop.
  class DesktopHost
    getter app : Application
    getter webview : WebViewPort
    getter tray : TrayPort
    getter event_loop : PlatformEventLoop

    def initialize(@app : Application)
      @webview = WebViewAdapter.new
      @tray = TrayAdapter.new
      @event_loop = PlatformEventLoop.new(@webview)
      @app.host = self

      @tray.create
      @app.register_commands(@app.registry)
      wire_event_bus
    end

    def run
      @app.on_ready
      @event_loop.run
    end

    def stop
      @event_loop.stop
      @tray.quit
      @webview.close
    end

    # Dispatch a JSON command request coming from the WebView.
    def dispatch(json : String) : String
      request = CommandRegistry.parse(json)
      result = @app.registry.dispatch(request)
      CommandRegistry.to_js_resolve(request, result)
    end

    private def wire_event_bus
      EventBus.on("window.focused") do |payload|
        @app.on_lifecycle("resume")
      end

      EventBus.on("window.blurred") do |payload|
        @app.on_lifecycle("pause")
      end

      EventBus.on("command.invoked") do |payload|
        result = dispatch(payload.to_json)
        @webview.eval_js(result)
      end
    end
  end
end
