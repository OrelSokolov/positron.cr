require "json"
require "log"

module Positron
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

    # The most recently constructed host. Positron.async_work/on_main
    # route through it; without one (tests, scripts) on_main runs
    # inline and GUI guards stay off.
    class_property current : Host?

    def initialize(@app : Application)
      @registry = @app.registry
      @state_manager = StateManager.new
      @plugins = @app.plugins
      @app.host = self
      bind_plugins
      @app.register_commands(@registry)
      wire_event_bus
      # Publish only once fully initialized: letting a partially built
      # host escape would expose nil ivars to async_work consumers.
      Host.current = self
    end

    # True when called from the GUI fiber. Base hosts have no fiber
    # loop, so false; DesktopHost delegates to its event loop.
    def gui_context? : Bool
      false
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
    # Async by default (the Wails/Tauri model): the command handler runs
    # in a Crystal fiber, so a slow command never freezes the GUI
    # thread, and the promise resolve is marshalled back to the GUI
    # thread via `run_on_main`. The envelope is parsed once and the
    # response serialized once. Returns "" — adapters skip evaluating
    # empty bridge responses.
    #
    # Supports the generic bridge envelope:
    #   - command: { "type": "command", "id", "name", "args" }
    #   - event:   { "type": "event", "event", "payload" }
    def dispatch(json : String) : String
      # The single rule: handlers run through Positron.async_work (a
      # background fiber — never the GUI fiber), and only the resolve
      # is marshalled back with on_main. Running the handler inside the
      # GUI idle callback froze the UI even for yielding work, because
      # Fiber.yield from inside an idle callback never returns control
      # to GTK.
      Positron.async_work(name: "dispatch") do
        response = dispatch_now(json)
        Positron.on_main { eval_js(response) }
        nil
      end
      ""
    end

    # Synchronous dispatch: parse + run the handler + build the resolve
    # JS. Used by `dispatch` internally and directly by tests/embedders
    # that need the response string (e.g. without a GUI loop).
    def dispatch_now(json : String) : String
      dispatch_envelope(JSON.parse(json))
    end

    private def dispatch_envelope(parsed : JSON::Any) : String
      case parsed["type"]?.try(&.as_s?)
      when "event"
        event_name = parsed["event"].as_s
        EventBus.emit(event_name, parsed["payload"]? || JSON.parse("{}"))
        ""
      else
        # Commands (and the fallback: a bare command request).
        request = CommandRegistry.parse(parsed)
        result = @registry.dispatch(request)
        CommandRegistry.to_js_resolve(request, result)
      end
    end

    # Inject the Positron JS runtime and hydrate initial state into the WebView.
    def inject_js_runtime
      facade = JSFacadeGenerator.new(@plugins.to_a)
      eval_js(facade.runtime_js)
      eval_js(facade.hydrate_js(@state_manager.snapshot))
    end

    # Push an event to the frontend. Subscribers registered with
    # `Positron.on(name, callback)` in JS receive the payload.
    #
    # This is the single supported way to notify the UI from Crystal:
    # plugins must not hand-roll `eval_js` strings. The call is marshalled
    # to the GUI thread so it is safe to call from any fiber.
    def emit_to_js(event : String, payload) : Nil
      run_on_main { eval_js("window.__positronNotify(#{event.to_json}, #{payload.to_json})") }
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
        # Route through #dispatch so the handler obeys the async_work
        # rule (a background fiber) instead of running synchronously on
        # the GUI fiber.
        dispatch(payload.to_json)
      end

      EventBus.on("state.changed") do |payload|
        plugin = payload["plugin"].as_s
        key = payload["key"].as_s
        value = payload["value"]
        eval_js(js_facade.patch_js(plugin, key, value))
      end

      # Window state changes and dropped files are broadcast to the
      # frontend so JS can subscribe with
      # Positron.on("window.resized", ...) / Positron.on("dnd.files", ...).
      {"window.resized", "window.moved", "window.maximized", "window.unmaximized",
       "window.fullscreened", "window.unfullscreened", "dnd.files"}.each do |event|
        EventBus.on(event) do |payload|
          emit_to_js(event, payload)
        end
      end

      # Dev error overlay (Dev::OVERLAY_JS posts "dev.error" through the
      # bridge): duplicate frontend errors to STDERR so the backend
      # console/log carries them too.
      EventBus.on("dev.error") do |payload|
        message = payload["message"]?.try(&.to_s) || "unknown error"
        file = payload["file"]?.try(&.to_s)
        line = payload["line"]?.try(&.as_i?) || 0
        column = payload["column"]?.try(&.as_i?) || 0
        location = (file && !file.empty?) ? " (#{file}:#{line}:#{column})" : ""
        STDERR.puts "[positron] frontend error: #{message}#{location}"
      end
    end

    private def js_facade : JSFacadeGenerator
      @js_facade ||= JSFacadeGenerator.new(@plugins.to_a)
    end

    @js_facade : JSFacadeGenerator?
  end
end
