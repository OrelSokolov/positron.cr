require "json"
require "log"

module CrystalUI
  # Desktop host: single process, Crystal owns everything.
  #
  # The DesktopHost wires together the WebView, tray, command registry,
  # plugins, EventBus, state manager, and the platform event loop.
  class DesktopHost
    getter app : Application
    getter webview : WebViewPort
    getter tray : TrayPort
    getter event_loop : PlatformEventLoop
    getter state_manager : StateManager
    @js_facade : JSFacadeGenerator?

    def initialize(@app : Application)
      @webview = WebViewAdapter.new
      @tray = TrayAdapter.new
      @event_loop = PlatformEventLoop.new(@webview)
      @state_manager = StateManager.new

      @app.host = self
      bind_plugins
      @app.register_commands(@app.registry)
      wire_event_bus

      @tray.create
    end

    def run
      ready_plugins
      @app.on_ready
      @event_loop.run
    end

    def stop
      @event_loop.stop
      @tray.quit
      @webview.close
    end

    # Dispatch a JSON payload coming from the WebView.
    #
    # Two message shapes are supported:
    #   - HWAPI calls: { "hwapi": { "id", "name", "args" } }
    #   - User events: { "event": "name", "payload": {} }
    def dispatch(json : String) : String
      parsed = JSON.parse(json)

      # User events go directly to the EventBus.
      if event_name = parsed["event"]?.try(&.as_s?)
        EventBus.emit(event_name, parsed["payload"]? || JSON.parse("{}"))
        return ""
      end

      # HWAPI calls are dispatched through the command registry.
      hwapi_json = parsed["hwapi"]?.try(&.to_json) || json
      request = CommandRegistry.parse(hwapi_json)
      result = @app.registry.dispatch(request)
      CommandRegistry.to_js_resolve(request, result)
    end

    # Inject the CrystalUI JS runtime and hydrate initial state into the WebView.
    def inject_js_runtime
      facade = JSFacadeGenerator.new(@app.plugins.to_a)
      @webview.eval_js(facade.runtime_js)
      @webview.eval_js(facade.hydrate_js(@state_manager.snapshot))
    end

    private def bind_plugins
      @app.plugins.each do |plugin|
        plugin.host = self
        plugin.bind(@app.registry, @state_manager)
        @state_manager.load_plugin_state(plugin.name, plugin.state)
      end
    end

    private def ready_plugins
      @app.plugins.each do |plugin|
        plugin.on_ready(self)
      end
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

      EventBus.on("state.changed") do |payload|
        plugin = payload["plugin"].as_s
        key = payload["key"].as_s
        value = payload["value"]
        @webview.eval_js(js_facade.patch_js(plugin, key, value))
      end
    end

    private def js_facade : JSFacadeGenerator
      @js_facade ||= JSFacadeGenerator.new(@app.plugins.to_a)
    end
  end
end
