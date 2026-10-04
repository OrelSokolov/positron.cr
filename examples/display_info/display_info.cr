require "../../src/positron"

# Demo application for the Display plugin.
#
# Queries the OS for screen information (DPI, resolution, monitors,
# orientation) and renders it in the WebView.
class DisplayInfoApp < Positron::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use Positron::Plugins::Display
    use Positron::Plugins::Logger
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron Display Info",
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

    tray.set_icon(icon_source(:svg))
    tray.set_title("Display Info")
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
  def ping : String
    "pong"
  end

  def stop
    host = @host
    host.stop if host
  end
end

DisplayInfoApp.new.run
