require "json"
require "log"

module CrystalUI
  # Abstract host that wires an Application to the native platform.
  #
  # Desktop and mobile hosts share the same dispatch, plugin binding and JS
  # runtime injection logic. Concrete implementations provide the native
  # plumbing (window/WebView, event loop, thread marshalling).
  abstract class Host
    getter app : Application
    getter registry : CommandRegistry
    getter state_manager : StateManager
    getter plugins : PluginManager

    def initialize(@app : Application)
      @registry = @app.registry
      @state_manager = StateManager.new
      @plugins = @app.plugins
      @app.host = self
      bind_plugins
      @app.register_commands(@registry)
      wire_event_bus
    end

    # Access the WebView surface. May raise on platforms without a desktop WebView.
    abstract def webview : WebViewPort

    # Access the system tray surface. May raise on platforms without a tray.
    abstract def tray : TrayPort

    # Evaluate JavaScript in the frontend.
    abstract def eval_js(script : String)

    # Run a block on the main/GUI thread.
    abstract def run_on_main(&block : ->) : Nil

    # Start the host's main loop (desktop) or finish initialization (mobile).
    abstract def run

    # Stop the host.
    abstract def stop

    # Dispatch a JSON payload coming from the WebView.
    #
    # Supports the generic bridge envelope:
    #   - command: { "type": "command", "id", "name", "args" }
    #   - event:   { "type": "event", "event", "payload" }
    def dispatch(json : String) : String
      parsed = JSON.parse(json)

      case parsed["type"]?.try(&.as_s?)
      when "event"
        event_name = parsed["event"].as_s
        EventBus.emit(event_name, parsed["payload"]? || JSON.parse("{}"))
        ""
      when "command"
        request = CommandRegistry.parse(parsed.to_json)
        result = @registry.dispatch(request)
        CommandRegistry.to_js_resolve(request, result)
      else
        # Fallback: treat the whole payload as a command request.
        request = CommandRegistry.parse(json)
        result = @registry.dispatch(request)
        CommandRegistry.to_js_resolve(request, result)
      end
    end

    # Inject the CrystalUI JS runtime and hydrate initial state into the WebView.
    def inject_js_runtime
      facade = JSFacadeGenerator.new(@plugins.to_a)
      eval_js(facade.runtime_js)
      eval_js(facade.hydrate_js(@state_manager.snapshot))
    end

    # Push an event to the frontend. Subscribers registered with
    # `CrystalUI.on(name, callback)` in JS receive the payload.
    #
    # This is the single supported way to notify the UI from Crystal:
    # plugins must not hand-roll `eval_js` strings. The call is marshalled
    # to the GUI thread so it is safe to call from any fiber.
    def emit_to_js(event : String, payload) : Nil
      run_on_main { eval_js("window.__crystalNotify(#{event.to_json}, #{payload.to_json})") }
    end

    protected def bind_plugins
      @plugins.each do |plugin|
        plugin.host = self
        plugin.bind(@registry, @state_manager)
        @state_manager.load_plugin_state(plugin.name, plugin.state)
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
        eval_js(result)
      end

      EventBus.on("state.changed") do |payload|
        plugin = payload["plugin"].as_s
        key = payload["key"].as_s
        value = payload["value"]
        eval_js(js_facade.patch_js(plugin, key, value))
      end

      # Window state changes and dropped files are broadcast to the
      # frontend so JS can subscribe with
      # CrystalUI.on("window.resized", ...) / CrystalUI.on("dnd.files", ...).
      {"window.resized", "window.moved", "window.maximized", "window.unmaximized",
       "window.fullscreened", "window.unfullscreened", "dnd.files"}.each do |event|
        EventBus.on(event) do |payload|
          emit_to_js(event, payload)
        end
      end
    end

    private def js_facade : JSFacadeGenerator
      @js_facade ||= JSFacadeGenerator.new(@plugins.to_a)
    end

    @js_facade : JSFacadeGenerator?
  end
end
