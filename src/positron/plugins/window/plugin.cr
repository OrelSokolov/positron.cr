require "json"

module Positron::Plugins
  # Window management plugin.
  #
  # Bridges the WebViewPort window API to the frontend:
  #   - window.set_title(title)
  #   - window.resize(width, height)
  #   - window.center()
  #   - window.set_minimum_size(width, height)
  #   - window.set_maximum_size(width, height)
  #   - window.maximize() / window.unmaximize() / window.is_maximized()
  #   - window.fullscreen() / window.unfullscreen()
  #   - window.set_always_on_top(enabled)
  #   - window.set_decorated(enabled)   # false = frameless
  #   - window.focus()
  #   - window.get_size() / window.get_position()
  #   - window.open_devtools() / window.close_devtools()
  #
  # Window state changes arrive as events: Positron.on("window.resized", ...).
  #
  # This plugin is adapter-free: it talks to the platform-agnostic
  # WebViewPort, so it works wherever the host's adapter implements the
  # window methods (currently Linux / WebKitGTK).
  class Window < Positron::Plugin
    def name : String
      "window"
    end

    def supported_platforms : Array(Symbol)
      [:desktop]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "window.set_title" => Positron::CommandManifest.new(
          name: "window.set_title",
          args: [Positron::ArgumentManifest.new(name: "title", type: "String")],
        ),
        "window.resize" => Positron::CommandManifest.new(
          name: "window.resize",
          args: [
            Positron::ArgumentManifest.new(name: "width", type: "Int32"),
            Positron::ArgumentManifest.new(name: "height", type: "Int32"),
          ],
        ),
        "window.center"           => Positron::CommandManifest.new(name: "window.center"),
        "window.set_minimum_size" => Positron::CommandManifest.new(
          name: "window.set_minimum_size",
          args: [
            Positron::ArgumentManifest.new(name: "width", type: "Int32"),
            Positron::ArgumentManifest.new(name: "height", type: "Int32"),
          ],
        ),
        "window.set_maximum_size" => Positron::CommandManifest.new(
          name: "window.set_maximum_size",
          args: [
            Positron::ArgumentManifest.new(name: "width", type: "Int32"),
            Positron::ArgumentManifest.new(name: "height", type: "Int32"),
          ],
        ),
        "window.maximize"     => Positron::CommandManifest.new(name: "window.maximize"),
        "window.unmaximize"   => Positron::CommandManifest.new(name: "window.unmaximize"),
        "window.is_maximized" => Positron::CommandManifest.new(
          name: "window.is_maximized",
          returns: "Bool",
        ),
        "window.fullscreen"        => Positron::CommandManifest.new(name: "window.fullscreen"),
        "window.unfullscreen"      => Positron::CommandManifest.new(name: "window.unfullscreen"),
        "window.set_always_on_top" => Positron::CommandManifest.new(
          name: "window.set_always_on_top",
          args: [Positron::ArgumentManifest.new(name: "enabled", type: "Bool")],
        ),
        "window.set_decorated" => Positron::CommandManifest.new(
          name: "window.set_decorated",
          args: [Positron::ArgumentManifest.new(name: "enabled", type: "Bool")],
        ),
        "window.focus"    => Positron::CommandManifest.new(name: "window.focus"),
        "window.get_size" => Positron::CommandManifest.new(
          name: "window.get_size",
          returns: "Object",
        ),
        "window.get_position" => Positron::CommandManifest.new(
          name: "window.get_position",
          returns: "Object",
        ),
        "window.open_devtools"  => Positron::CommandManifest.new(name: "window.open_devtools"),
        "window.close_devtools" => Positron::CommandManifest.new(name: "window.close_devtools"),
      }
    end

    # Blocks return JSON::Any directly (never nil) so the command block's
    # Proc type is fully explicit — newer Crystal compilers reject
    # uninferred block return types here. Blocks whose return value is
    # derived from a WebViewPort call additionally need a trailing
    # `.as(JSON::Any)`: without it Crystal >= 1.21 crashes in codegen
    # ("Cast from Nil to ProcInstanceType failed", cf. crystal-lang/crystal
    # #11653) when the captured block is called from the register block.
    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      register registry, "window.set_title" do |webview, args|
        webview.set_title(arg_string(args, "title"))
        void
      end

      register registry, "window.resize" do |webview, args|
        webview.resize(arg_int(args, "width"), arg_int(args, "height"))
        void
      end

      register registry, "window.center" do |webview, _args|
        webview.center
        void
      end

      register registry, "window.set_minimum_size" do |webview, args|
        webview.set_minimum_size(arg_int(args, "width"), arg_int(args, "height"))
        void
      end

      register registry, "window.set_maximum_size" do |webview, args|
        webview.set_maximum_size(arg_int(args, "width"), arg_int(args, "height"))
        void
      end

      register registry, "window.maximize" do |webview, _args|
        webview.maximize
        void
      end

      register registry, "window.unmaximize" do |webview, _args|
        webview.unmaximize
        void
      end

      register registry, "window.is_maximized" do |webview, _args|
        json(webview.maximized?).as(JSON::Any)
      end

      register registry, "window.fullscreen" do |webview, _args|
        webview.fullscreen
        void
      end

      register registry, "window.unfullscreen" do |webview, _args|
        webview.unfullscreen
        void
      end

      register registry, "window.set_always_on_top" do |webview, args|
        webview.set_always_on_top(arg_bool(args, "enabled"))
        void
      end

      register registry, "window.set_decorated" do |webview, args|
        webview.set_decorated(arg_bool(args, "enabled"))
        void
      end

      register registry, "window.focus" do |webview, _args|
        webview.focus
        void
      end

      register registry, "window.get_size" do |webview, _args|
        width, height = webview.size
        json({width: width, height: height}).as(JSON::Any)
      end

      register registry, "window.get_position" do |webview, _args|
        x, y = webview.position
        json({x: x, y: y}).as(JSON::Any)
      end

      register registry, "window.open_devtools" do |webview, _args|
        webview.open_devtools
        void
      end

      register registry, "window.close_devtools" do |webview, _args|
        webview.close_devtools
        void
      end
    end

    # Register a window command. The block receives the WebViewPort and
    # returns the command data as JSON::Any. When the platform adapter
    # does not implement the capability, the call raises and the command
    # resolves with an error on the JS side.
    private def register(registry : Positron::CommandRegistry, name : String,
                         &block : Positron::WebViewPort, JSON::Any -> JSON::Any)
      registry.register(name) do |request|
        webview = host.try(&.webview)
        next unsupported(name) unless webview

        begin
          Positron::CommandResult.new(
            success: true,
            data: block.call(webview, request.args)
          )
        rescue ex
          Positron::CommandResult.new(
            success: false,
            data: JSON.parse("{}"),
            error: "#{name} failed: #{ex.message}"
          )
        end
      end
    end

    private def void : JSON::Any
      JSON.parse("{}")
    end

    private def json(value) : JSON::Any
      JSON.parse(value.to_json)
    end

    private def unsupported(name : String)
      Positron::CommandResult.new(
        success: false,
        data: JSON.parse("{}"),
        error: "#{name}: no window available on this host"
      )
    end

    private def arg_string(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end

    private def arg_int(args : JSON::Any, key : String) : Int32
      args[key]?.try(&.as_i?) || 0
    end

    private def arg_bool(args : JSON::Any, key : String) : Bool
      args[key]?.try(&.as_bool?) || false
    end
  end
end
