require "json"
require "../../src/positron"

class FilePickerApp < Positron::Application
  # Embed frontend/application.html, application.css, application.js and icon.
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use Positron::Plugins::FilePicker
    use Positron::Plugins::Logger
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "File Picker Demo",
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
    tray.set_title("File Picker Demo")
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

  def stop
    host = @host
    host.stop if host
  end
end

FilePickerApp.new.run
