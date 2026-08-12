require "uri"
require "json"
require "../../src/crystal_ui"
require "../../src/crystal_ui/plugins/logger"
require "../../src/crystal_ui/plugins/notifications/plugin"

class SystemNotificationsApp < CrystalUI::Application
  # Embed frontend/application.html, application.css, application.js and icon.
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use CrystalUI::Plugins::Logger
    use CrystalUI::Plugins::Notifications
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(CrystalUI::WebViewConfig.new(
      title: "System Notifications — CrystalUI",
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

    CrystalUI::EventBus.on("notification.clicked") do |payload|
      STDOUT.puts "[Crystal Host] notification clicked: #{payload}"
      STDOUT.flush
    end

    tray.set_icon(icon_source(:svg))
    tray.set_title("Notifications")
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

  def stop
    host = @host
    host.stop if host
  end
end

SystemNotificationsApp.new.run
