require "json"

module CrystalUI::Plugins
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
  # Window state changes arrive as events: CrystalUI.on("window.resized", ...).
  #
  # This plugin is adapter-free: it talks to the platform-agnostic
  # WebViewPort, so it works wherever the host's adapter implements the
  # window methods (currently Linux / WebKitGTK).
  class Window < CrystalUI::Plugin
    def name : String
      "window"
    end

    def supported_platforms : Array(Symbol)
      [:desktop]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "window.set_title" => CrystalUI::CommandManifest.new(
          name: "window.set_title",
          args: [CrystalUI::ArgumentManifest.new(name: "title", type: "String")],
        ),
        "window.resize" => CrystalUI::CommandManifest.new(
          name: "window.resize",
          args: [
            CrystalUI::ArgumentManifest.new(name: "width", type: "Int32"),
            CrystalUI::ArgumentManifest.new(name: "height", type: "Int32"),
          ],
        ),
        "window.center" => CrystalUI::CommandManifest.new(name: "window.center"),
        "window.set_minimum_size" => CrystalUI::CommandManifest.new(
          name: "window.set_minimum_size",
          args: [
            CrystalUI::ArgumentManifest.new(name: "width", type: "Int32"),
            CrystalUI::ArgumentManifest.new(name: "height", type: "Int32"),
          ],
        ),
        "window.set_maximum_size" => CrystalUI::CommandManifest.new(
          name: "window.set_maximum_size",
          args: [
            CrystalUI::ArgumentManifest.new(name: "width", type: "Int32"),
            CrystalUI::ArgumentManifest.new(name: "height", type: "Int32"),
          ],
        ),
        "window.maximize" => CrystalUI::CommandManifest.new(name: "window.maximize"),
        "window.unmaximize" => CrystalUI::CommandManifest.new(name: "window.unmaximize"),
        "window.is_maximized" => CrystalUI::CommandManifest.new(
          name: "window.is_maximized",
          returns: "Bool",
        ),
        "window.fullscreen" => CrystalUI::CommandManifest.new(name: "window.fullscreen"),
        "window.unfullscreen" => CrystalUI::CommandManifest.new(name: "window.unfullscreen"),
        "window.set_always_on_top" => CrystalUI::CommandManifest.new(
          name: "window.set_always_on_top",
          args: [CrystalUI::ArgumentManifest.new(name: "enabled", type: "Bool")],
        ),
        "window.set_decorated" => CrystalUI::CommandManifest.new(
          name: "window.set_decorated",
          args: [CrystalUI::ArgumentManifest.new(name: "enabled", type: "Bool")],
        ),
        "window.focus" => CrystalUI::CommandManifest.new(name: "window.focus"),
        "window.get_size" => CrystalUI::CommandManifest.new(
          name: "window.get_size",
          returns: "Object",
        ),
        "window.get_position" => CrystalUI::CommandManifest.new(
          name: "window.get_position",
          returns: "Object",
        ),
        "window.open_devtools" => CrystalUI::CommandManifest.new(name: "window.open_devtools"),
        "window.close_devtools" => CrystalUI::CommandManifest.new(name: "window.close_devtools"),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      register registry, "window.set_title" do |webview, args|
        webview.set_title(arg_string(args, "title"))
        nil
      end

      register registry, "window.resize" do |webview, args|
        webview.resize(arg_int(args, "width"), arg_int(args, "height"))
        nil
      end

      register registry, "window.center" do |webview, _args|
        webview.center
        nil
      end

      register registry, "window.set_minimum_size" do |webview, args|
        webview.set_minimum_size(arg_int(args, "width"), arg_int(args, "height"))
        nil
      end

      register registry, "window.set_maximum_size" do |webview, args|
        webview.set_maximum_size(arg_int(args, "width"), arg_int(args, "height"))
        nil
      end

      register registry, "window.maximize" do |webview, _args|
        webview.maximize
        nil
      end

      register registry, "window.unmaximize" do |webview, _args|
        webview.unmaximize
        nil
      end

      register registry, "window.is_maximized" do |webview, _args|
        webview.maximized?
      end

      register registry, "window.fullscreen" do |webview, _args|
        webview.fullscreen
        nil
      end

      register registry, "window.unfullscreen" do |webview, _args|
        webview.unfullscreen
        nil
      end

      register registry, "window.set_always_on_top" do |webview, args|
        webview.set_always_on_top(arg_bool(args, "enabled"))
        nil
      end

      register registry, "window.set_decorated" do |webview, args|
        webview.set_decorated(arg_bool(args, "enabled"))
        nil
      end

      register registry, "window.focus" do |webview, _args|
        webview.focus
        nil
      end

      register registry, "window.get_size" do |webview, _args|
        width, height = webview.size
        {width: width, height: height}
      end

      register registry, "window.get_position" do |webview, _args|
        x, y = webview.position
        {x: x, y: y}
      end

      register registry, "window.open_devtools" do |webview, _args|
        webview.open_devtools
        nil
      end

      register registry, "window.close_devtools" do |webview, _args|
        webview.close_devtools
        nil
      end
    end

    # Register a window command. The block receives the WebViewPort; its
    # return value becomes the command data (nil → empty object). When the
    # platform adapter does not implement the capability, the call raises
    # and the command resolves with an error on the JS side.
    private def register(registry : CrystalUI::CommandRegistry, name : String,
                         &block : CrystalUI::WebViewPort, JSON::Any -> _)
      registry.register(name) do |request|
        webview = host.try(&.webview)
        next unsupported(name) unless webview

        begin
          data = block.call(webview, request.args)
          CrystalUI::CommandResult.new(
            success: true,
            data: data.nil? ? JSON.parse("{}") : JSON.parse(data.to_json)
          )
        rescue ex
          CrystalUI::CommandResult.new(
            success: false,
            data: JSON.parse("{}"),
            error: "#{name} failed: #{ex.message}"
          )
        end
      end
    end

    private def unsupported(name : String)
      CrystalUI::CommandResult.new(
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
