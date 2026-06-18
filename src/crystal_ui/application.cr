require "json"

module CrystalUI
  # Base class for end-user CrystalUI applications.
  #
  # Developers subclass Application, implement lifecycle hooks,
  # and expose business logic via @[Command] annotated methods.
  abstract class Application
    @host : DesktopHost?
    getter plugins = PluginManager.new
    getter registry = CommandRegistry.new

    # Called once the native window and event loop are ready.
    abstract def on_ready

    # Lifecycle events forwarded from the native shim.
    def on_lifecycle(state : String)
      case state
      when "resume"
        on_resume
      when "pause"
        on_pause
      when "destroy"
        on_destroy
      end
    end

    def on_resume
    end

    def on_pause
    end

    def on_destroy
    end

    # Deep link handling.
    def on_deep_link(url : String)
    end

    # Permission result handling.
    def on_permission_result(permission : String, granted : Bool)
    end

    # Override to register application commands into the registry.
    # Use the `command_registry` macro to auto-wire @[Command] methods:
    #
    #   def register_commands(registry)
    #     command_registry
    #   end
    def register_commands(registry : CommandRegistry)
    end

    # Macro that registers every method annotated with @[CrystalUI::Command]
    # in the current subclass.
    macro command_registry
      {% for method in @type.methods %}
        {% if method.annotation(CrystalUI::Command) %}
          registry.register({{method.name.stringify}}) do |request|
            CrystalUI::CommandResult.new(
              success: true,
              data: JSON.parse(self.{{method.name}}.to_json)
            )
          end
        {% end %}
      {% end %}
    end

    # Access the WebView surface.
    def webview : WebViewPort
      host.webview
    end

    # Access the system tray surface.
    def tray : TrayPort
      host.tray
    end

    # Access the shared state manager.
    def state_manager : StateManager
      host.state_manager
    end

    # Convenience helper to register a plugin.
    def register_plugin(plugin : Plugin)
      plugins.register(plugin)
    end

    # Inject the CrystalUI JS runtime and hydrate state.
    # Call this inside on_ready after navigating the webview.
    def inject_js_runtime
      host.inject_js_runtime
    end

    # Run the application.
    def run
      DesktopHost.new(self).run
    end

    protected def host : DesktopHost
      @host.not_nil!
    end

    protected def host=(@host : DesktopHost)
    end
  end
end
