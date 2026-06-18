require "json"

module CrystalUI
  # Base class for end-user CrystalUI applications.
  #
  # Developers subclass Application, implement lifecycle hooks,
  # and expose business logic via @[Command] annotated methods.
  abstract class Application
    @host : Host?
    @icon_temp_path : String?
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

    # DSL helper for plugin registration.
    #
    #   use CrystalUI::Plugins::Logger
    #   use MyCustomPlugin
    #
    # Plugins instantiated this way are enabled for this application.
    macro use(plugin_class)
      register_plugin({{plugin_class}}.new)
    end

    # Explicit plugin registration for instances that need constructor args.
    def use(plugin : Plugin)
      register_plugin(plugin)
    end

    # Override to declare the plugins this application needs.
    #
    # By default CrystalUI ships with *no* plugins enabled. The developer
    # opts-in by listing the required plugins here.
    def configure_plugins
      # override in subclass
    end

    # Inject the CrystalUI JS runtime and hydrate state.
    # Call this inside on_ready after navigating the webview.
    def inject_js_runtime
      host.inject_js_runtime
    end

    # Return the complete HTML document for the WebView.
    #
    # This method must be implemented by embedding frontend assets at compile
    # time using the `embed_application_files` macro. There is no runtime file
    # loading: the desktop binary is self-contained.
    abstract def application_html : String

    # Embed frontend assets into the compiled binary at compile time.
    #
    # This macro also embeds the application icon and exposes:
    #   - `embedded_icon_svg` : String
    #   - `icon_bytes` : Bytes
    #   - `icon_path` : String (writes a temporary file on first call)
    #
    # Usage in your Application subclass:
    #   embed_application_files(__DIR__)
    #   embed_application_files(__DIR__, "icon.svg")
    #   embed_application_files(__DIR__, "../assets/crystal-icon.svg")
    macro embed_application_files(dir, icon = "icon.svg")
      private def embedded_icon_svg : String
        {{ run(__DIR__ + "/embed_file.cr", dir + "/" + icon) }}
      end

      private def application_html : String
        html = {{ run(__DIR__ + "/embed_file.cr", dir + "/frontend/application.html") }}
        css = {{ run(__DIR__ + "/embed_file.cr", dir + "/frontend/application.css") }}
        js = {{ run(__DIR__ + "/embed_file.cr", dir + "/frontend/application.js") }}
        build_application_html(html, css, js, embedded_icon_svg)
      end

      def icon_bytes : Bytes
        embedded_icon_svg.to_slice
      end

      def icon_path : String
        @icon_temp_path ||= begin
          path = File.join(Dir.tempdir, "crystalui-icon-#{Process.pid}.svg")
          File.write(path, embedded_icon_svg)
          path
        end
      end

      def icon_source(format : Symbol = :svg) : CrystalUI::IconSource
        CrystalUI::IconSource.new(icon_bytes, format)
      end
    end

    private def build_application_html(html : String, css : String, js : String, icon_svg : String) : String
      html
        .sub("{{CSS}}", css)
        .sub("{{JS}}", js)
        .sub("{{ICON_SVG}}", icon_svg)
        .sub("{{RUNTIME_JS}}", runtime_js)
        .sub("{{HYDRATE_JS}}", hydrate_js)
    end

    private def runtime_js : String
      CrystalUI::JSFacadeGenerator.new(plugins.to_a).runtime_js
    end

    private def hydrate_js : String
      CrystalUI::JSFacadeGenerator.new(plugins.to_a).hydrate_js(state_manager.snapshot)
    end

    # Run the application.
    #
    # On desktop this creates the DesktopHost and starts the event loop.
    # On mobile the native shim owns the lifecycle; calling run() is an error.
    def run
      configure_plugins
      {% if flag?(:android) || flag?(:ios) %}
        raise "Do not call Application.run on mobile; the native shim owns the lifecycle"
      {% else %}
        DesktopHost.new(self).run
      {% end %}
    end

    protected def host : Host
      @host.not_nil!
    end

    protected def host=(@host : Host)
    end
  end
end
