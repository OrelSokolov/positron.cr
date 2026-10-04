require "uri"
require "json"
require "time"
require "../../src/positron"

# Example plugin demonstrating the RailsWay architecture:
# - explicit command binding via bind()
# - manifest for JS facade generation
# - observable state via StateManager
class SettingsPlugin < Positron::Plugin
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

  def manifest : Hash(String, Positron::CommandManifest)
    {
      "settings.current_theme" => Positron::CommandManifest.new(
        name: "settings.current_theme",
        returns: "String"
      ),
      "settings.set_theme" => Positron::CommandManifest.new(
        name: "settings.set_theme",
        args: [
          Positron::ArgumentManifest.new(name: "theme", type: "String"),
        ],
        returns: "String"
      ),
    }
  end

  def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
    registry.register("settings.current_theme") do |request|
      Positron::CommandResult.new(
        success: true,
        data: JSON.parse(@theme.to_json)
      )
    end

    registry.register("settings.set_theme") do |request|
      @theme = request.args["theme"].as_s
      set_state("theme", @theme)
      Positron::CommandResult.new(
        success: true,
        data: JSON.parse(@theme.to_json)
      )
    end
  end
end

class HelloApp < Positron::Application
  # Embed frontend/application.html, application.css, application.js and icon.
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use SettingsPlugin
    use Positron::Plugins::Logger
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron",
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
    tray.set_title("Positron")
    tray.add_or_update_item(Positron::TrayItem.new(id: 1, title: "Open"))
    tray.add_or_update_item(Positron::TrayItem.new(id: 2, title: "Quit"))
    tray.on_item_click do |id|
      case id
      when 1 then webview.show
      when 2 then stop
      end
    end
    tray.show
  end

  @[Positron::Command]
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
