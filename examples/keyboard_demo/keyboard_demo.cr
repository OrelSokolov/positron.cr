require "json"
require "../../src/crystal_ui"
require "../../src/crystal_ui/plugins/logger"
require "../../src/crystal_ui/plugins/keyboard/plugin"

class KeyboardDemoApp < CrystalUI::Application
  # Embed frontend/application.html, application.css, application.js and icon.
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use CrystalUI::Plugins::Logger
    use CrystalUI::Plugins::Keyboard
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(CrystalUI::WebViewConfig.new(
      title: "Keyboard Events — CrystalUI",
      width: 900,
      height: 700,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") do |json|
      STDOUT.puts "[Crystal Host] received from JS: #{json}"
      STDOUT.flush
      host.dispatch(json)
    end

    webview.load_html(application_html)

    # Log matched shortcuts on the host side.
    CrystalUI::EventBus.on("keyboard.shortcut") do |payload|
      STDOUT.puts "[Crystal Host] shortcut matched: #{payload}"
      STDOUT.flush
    end

    tray.set_icon(icon_source(:svg))
    tray.set_title("Keyboard Demo")
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
  def demo_action : Hash(String, String)
    {
      "message" => "Demo action executed from Crystal Host!",
      "time"    => Time.utc.to_rfc3339,
    }
  end

  def stop
    host = @host
    host.stop if host
  end
end

KeyboardDemoApp.new.run
