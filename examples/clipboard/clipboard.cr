require "../../src/crystal_ui"

# Demo application for the Clipboard plugin.
#
# Shows how to paste text and images from the OS clipboard into a WebView
# and display them immediately in an input field and a thumbnail.
class ClipboardApp < CrystalUI::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use CrystalUI::Plugins::Clipboard
    use CrystalUI::Plugins::Logger
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(CrystalUI::WebViewConfig.new(
      title: "CrystalUI Clipboard",
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
    tray.set_title("Clipboard")
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
  def ping : String
    "pong"
  end

  def stop
    host = @host
    host.stop if host
  end
end

ClipboardApp.new.run
