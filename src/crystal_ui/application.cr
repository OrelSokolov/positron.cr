require "json"
require "base64"

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
    # in the current subclass. It also records command manifests (built
    # from the method signatures) for the TypeScript bindings generator.
    macro command_registry
      {% manifests = [] of ::String %}
      {% for method in @type.methods %}
        {% if method.annotation(CrystalUI::Command) %}
          {% arg_list = [] of ::String %}
          {% for arg in method.args %}
            {% arg_list << "CrystalUI::ArgumentManifest.new(name: #{arg.name.stringify}, type: #{arg.restriction ? arg.restriction.stringify : "Any".inspect})" %}
          {% end %}
          registry.register({{method.name.stringify}}) do |request|
            CrystalUI::CommandResult.new(
              success: true,
              data: JSON.parse(self.{{method.name}}.to_json)
            )
          end
          @command_manifest_list[{{method.name.stringify}}] = CrystalUI::CommandManifest.new(
            name: {{method.name.stringify}},
            args: [{{arg_list.splat}}] of CrystalUI::ArgumentManifest,
          )
        {% end %}
      {% end %}
    end

    # Manifests for @[Command] methods, used by the TypeScript bindings
    # generator. Populated automatically by `command_registry`.
    def command_manifests : Hash(String, CommandManifest)
      @command_manifest_list
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

    # Embed a single file at compile time as a String literal. `path` must be
    # a plain string literal (relative paths resolve against the compiler's
    # working directory). Expands to the file contents, so it can be used in
    # constants:
    #
    #   ICON_SVG = embed_file("assets/icon.svg")
    macro embed_file(path)
      {{ run("./embed_file.cr", path) }}
    end

    # Embed a whole directory tree at compile time (Base64-encoded, safe for
    # binary files) — e.g. a built web app with hashed asset names. Exposes:
    #
    #   embedded_directory     : Hash(String, String)  # "/path" => Base64
    #   embedded_file?(path)   : Bytes?                # decoded, cached
    #   embedded_file(path)    : Bytes                 # raises when missing
    #
    # Paths are "/"-rooted relative to the embedded directory. Pair with
    # `webview.register_uri_scheme` to serve them from the host process.
    #
    # NOTE: `dir` must be a plain string literal (run() passes macro-variable
    # expressions through unevaluated). Relative paths resolve against the
    # directory the compiler runs from — typically the shard root, e.g.
    # `embed_directory("frontend")`.
    macro embed_directory(dir)
      def embedded_directory : Hash(String, String)
        @@embedded_directory ||= {{ run("./embed_directory.cr", dir) }}
      end

      @embedded_file_cache = {} of String => Bytes

      def embedded_file?(path : String) : Bytes?
        if bytes = @embedded_file_cache[path]?
          bytes
        elsif b64 = embedded_directory[path]?
          bytes = Base64.decode(b64)
          @embedded_file_cache[path] = bytes
          bytes
        end
      end

      def embedded_file(path : String) : Bytes
        embedded_file?(path) || raise "no embedded file: #{path}"
      end
    end

    # Embed frontend assets into the compiled binary at compile time.
    #
    # This macro also embeds the application icon and exposes:
    #   - `embedded_icon` : String
    #   - `embedded_icon_html` : String (SVG inline or base64 <img>)
    #   - `icon_bytes` : Bytes
    #   - `icon_path` : String (writes a temporary file on first call)
    #   - `icon_source` : IconSource
    #
    # The icon file is selected per platform using `IconAdapter`:
    #   - Linux   -> .svg (fallback .png, .ico)
    #   - Windows -> .ico (fallback .png, .svg)
    #   - macOS   -> .png (fallback .svg, .ico)
    #   - Mobile  -> .png (fallback .svg, .ico)
    #
    # Usage in your Application subclass:
    #   embed_application_files(__DIR__)
    #   embed_application_files(__DIR__, "icon")
    #   embed_application_files(__DIR__, "../assets/crystal-icon")
    macro embed_application_files(dir, icon = "icon")
      {% known_exts = [".svg", ".png", ".ico"] %}
      {% preferred_ext = CrystalUI::IconAdapter::PREFERRED_EXTENSION %}

      # Strip a known extension from the provided icon path so we can append
      # the platform-preferred extension.
      {% icon_base = icon %}
      {% for ext in known_exts %}
        {% if icon.ends_with?(ext) %}
          {% icon_base = icon[0..-(ext.size + 1)] %}
        {% end %}
      {% end %}

      # Resolve the actual icon file at compile time, falling back through
      # common formats if the platform-preferred file is missing.
      {% resolved = run("./resolve_icon_path.cr", dir + "/" + icon_base, preferred_ext, ".svg", ".png", ".ico") %}
      {% resolved_lines = resolved.split("\n") %}
      {% icon_file = resolved_lines[0] %}
      {% icon_ext = resolved_lines[1] %}
      {% icon_fmt = (icon_ext == ".svg") ? :svg : (icon_ext == ".png") ? :png : :ico %}

      private def embedded_icon : String
        {{ run("./embed_file.cr", icon_file) }}
      end

      private def embedded_icon_html : String
        case {{ icon_fmt.stringify }}
        when "svg"
          embedded_icon
        when "png"
          "<img src=\"data:image/png;base64,#{Base64.strict_encode(icon_bytes)}\" alt=\"icon\">"
        when "ico"
          "<img src=\"data:image/x-icon;base64,#{Base64.strict_encode(icon_bytes)}\" alt=\"icon\">"
        else
          ""
        end
      end

      private def application_html : String
        html = {{ run("./embed_file.cr", dir + "/frontend/application.html") }}
        css = {{ run("./embed_file.cr", dir + "/frontend/application.css") }}
        js = {{ run("./embed_file.cr", dir + "/frontend/application.js") }}
        build_application_html(html, css, js, embedded_icon_html)
      end

      def icon_bytes : Bytes
        embedded_icon.to_slice
      end

      def icon_path : String
        @icon_temp_path ||= begin
          ext = {{ icon_ext.stringify }}
          path = File.join(Dir.tempdir, "crystalui-icon-#{Process.pid}#{ext}")
          File.write(path, embedded_icon)
          path
        end
      end

      def icon_source(format : Symbol = {{ icon_fmt }}) : CrystalUI::IconSource
        CrystalUI::IconSource.new(icon_bytes, format)
      end
    end

    private def build_application_html(html : String, css : String, js : String, icon_html : String) : String
      html
        .sub("{{CSS}}", css)
        .sub("{{JS}}", js)
        .sub("{{ICON_HTML}}", icon_html)
        .sub("{{RUNTIME_JS}}", runtime_js)
        .sub("{{HYDRATE_JS}}", hydrate_js)
    end

    private def runtime_js : String
      CrystalUI::JSFacadeGenerator.new(plugins.to_a).runtime_js
    end

    private def hydrate_js : String
      CrystalUI::JSFacadeGenerator.new(plugins.to_a).hydrate_js(state_manager.snapshot)
    end

    # Dev-mode counterpart of `embed_directory`: serve a frontend directory
    # from disk over a local HTTP server, with live reload.
    #
    # Call this inside `on_ready` and load the returned URL:
    #
    #   def on_ready
    #     url = serve_directory("frontend")
    #     webview.create(CrystalUI::WebViewConfig.new(title: "MyApp", close_to_tray: false))
    #     webview.load_url(url)
    #   end
    #
    # Served HTML pages get the CrystalUI runtime (facade + current state)
    # injected, so they have the same `CrystalUI.*` API as embedded pages.
    # When a file under `dir` changes, the WebView reloads — no recompile
    # needed. Pair with `CrystalUI::Dev.enabled?` (CRYSTAL_UI_DEV=1) to
    # switch between serving and embedded assets in one binary.
    def serve_directory(dir : String, fallback_path : String = "/index.html") : String
      host_ref = -> { host }
      server = Dev::AssetServer.new(
        File.expand_path(dir),
        fallback_path: fallback_path,
        runtime_provider: -> {
          facade = CrystalUI::JSFacadeGenerator.new(plugins.to_a)
          [facade.runtime_js, facade.hydrate_js(host_ref.call.state_manager.snapshot)]
        },
      ) do
        h = host_ref.call
        h.run_on_main { h.eval_js("location.reload()") }
      end
      server.start
      @dev_asset_server = server

      # Regenerate TypeScript bindings so the frontend editor picks up
      # new plugin and app commands on every dev start.
      begin
        bindings = CrystalUI::BindingsGenerator.new(plugins.to_a, self).typescript
        File.write(File.join(File.expand_path(dir), "crystal-ui.d.ts"), bindings)
      rescue ex
        Log.warn { "bindings generation failed: #{ex.message}" }
      end

      server.base_url
    end

    @dev_asset_server : Dev::AssetServer?
    @command_manifest_list = {} of String => CommandManifest

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
