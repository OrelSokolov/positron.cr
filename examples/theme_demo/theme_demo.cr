require "../../src/positron"

class ThemeDemoApp < Positron::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use Positron::Plugins::Theme
  end

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron Theme Demo",
      width: 640,
      height: 480,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") do |json|
      host.dispatch(json)
    end

    webview.load_html(application_html)
  end
end

ThemeDemoApp.new.run
