require "uri"
require "json"
require "time"
require "../../src/crystal_ui"

# Example plugin demonstrating the RailsWay architecture:
# - explicit command binding via bind()
# - manifest for JS facade generation
# - observable state via StateManager
class SettingsPlugin < CrystalUI::Plugin
  property theme : String = "dark"

  def name : String
    "settings"
  end

  def supported_platforms : Array(Symbol)
    [:desktop, :android, :ios]
  end

  def state : Hash(String, JSON::Any)
    {
      "theme" => JSON.parse(@theme.to_json),
    }
  end

  def manifest : Hash(String, CrystalUI::CommandManifest)
    {
      "settings.current_theme" => CrystalUI::CommandManifest.new(
        name: "settings.current_theme",
        returns: "String"
      ),
      "settings.set_theme" => CrystalUI::CommandManifest.new(
        name: "settings.set_theme",
        args: [
          CrystalUI::ArgumentManifest.new(name: "theme", type: "String"),
        ],
        returns: "String"
      ),
    }
  end

  def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
    registry.register("settings.current_theme") do |request|
      CrystalUI::CommandResult.new(
        success: true,
        data: JSON.parse(@theme.to_json)
      )
    end

    registry.register("settings.set_theme") do |request|
      @theme = request.args["theme"].as_s
      set_state("theme", @theme)
      CrystalUI::CommandResult.new(
        success: true,
        data: JSON.parse(@theme.to_json)
      )
    end
  end
end

class HelloApp < CrystalUI::Application
  # Embed frontend/application.html, application.css, application.js and icon.
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use SettingsPlugin
    use CrystalUI::Plugins::Logger
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(CrystalUI::WebViewConfig.new(
      title: "CrystalUI",
      width: 900,
      height: 640,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") do |json|
      STDOUT.puts "[Crystal Host] received from JS: #{json}"
      STDOUT.flush
      host.dispatch(json)
    end

    webview.load_html(application_html)

    tray.set_icon(icon_source(:svg))
    tray.set_title("CrystalUI")
    tray.add_or_update_item(CrystalUI::TrayItem.new(id: 1, title: "Open"))
    tray.add_or_update_item(CrystalUI::TrayItem.new(id: 2, title: "Quit"))
    tray.on_item_click do |id|
      case id
      when 1 then webview.show
      when 2 then stop
      end
    end
    tray.show
  end

  @[CrystalUI::Command]
  def hello : Hash(String, String)
    {
      "message" => "Hello from the Crystal Host!",
      "time"    => Time.utc.to_rfc3339,
      "pid"     => Process.pid.to_s,
    }
  end

  def stop
    host = @host
    host.stop if host
  end
end

HelloApp.new.run
