require "../src/crystal_ui/event_bus"
require "../src/crystal_ui/command_registry"
require "../src/crystal_ui/state_manager"
require "../src/crystal_ui/plugin"
require "../src/crystal_ui/js_facade_generator"
require "../src/crystal_ui/ports/webview_port"
require "../src/crystal_ui/ports/tray_port"
require "../src/crystal_ui/application"
require "../src/crystal_ui/host"
require "spec"
require "json"

# Headless fakes so Host#dispatch can be exercised without a GUI.
class NullWebView < CrystalUI::WebViewPort
  property evals = [] of String

  def create(config : CrystalUI::WebViewConfig); end
  def load_url(url : String); end
  def load_html(html : String, base_url : String? = nil); end

  def eval_js(script : String)
    evals << script
  end

  def show; end
  def hide; end
  def close; end
  def bind(name : String, &handler : String -> String); end
end

class NullTray < CrystalUI::TrayPort
  def supported? : Bool
    false
  end

  def create(icon : CrystalUI::IconSource? = nil, title : String? = nil); end
  def set_icon(icon : CrystalUI::IconSource); end
  def set_title(title : String); end
  def set_tooltip(tooltip : String); end
  def add_or_update_item(item : CrystalUI::TrayItem); end
  def add_separator(id : Int32); end
  def remove_item(id : Int32); end
  def show_item(id : Int32); end
  def hide_item(id : Int32); end
  def on_item_click(&block : Int32 ->); end
  def show; end
  def hide; end
  def quit; end
end

class FakeHost < CrystalUI::Host
  getter webview : CrystalUI::WebViewPort
  getter tray : CrystalUI::TrayPort
  getter main_calls = 0

  def initialize(app : CrystalUI::Application)
    @webview = NullWebView.new
    @tray = NullTray.new
    super(app)
  end

  def eval_js(script : String)
    webview.eval_js(script)
  end

  def run_on_main(&block : ->) : Nil
    @main_calls += 1
    block.call
  end

  def run; end
  def stop; end
end

class DispatchApp < CrystalUI::Application
  getter greeted = [] of String

  def on_ready; end

  def application_html : String
    ""
  end

  def register_commands(registry : CrystalUI::CommandRegistry)
    registry.register("greet") do |request|
      name = request.args["name"]?.try(&.as_s?) || "world"
      @greeted << name
      CrystalUI::CommandResult.new(
        success: true,
        data: JSON.parse("Hello, #{name}!".to_json)
      )
    end
  end
end

def build_host
  app = DispatchApp.new
  host = FakeHost.new(app)
  {host, app}
end

describe CrystalUI::Host do
  it "dispatches command envelopes and resolves the JS promise" do
    host, app = build_host

    response = host.dispatch(%({"type":"command","id":"abc","name":"greet","args":{"name":"Crystal"}}))

    app.greeted.should eq(["Crystal"])
    response.should contain(%("abc"))
    response.should contain("true")
    response.should contain(%("Hello, Crystal!"))
    host.webview.as(NullWebView).evals.should be_empty
  end

  it "routes event envelopes into the EventBus and returns an empty string" do
    host, _app = build_host

    received = [] of String
    CrystalUI::EventBus.on("spec.hostevent") do |payload|
      received << payload["url"].to_s
    end

    response = host.dispatch(%({"type":"event","event":"spec.hostevent","payload":{"url":"app://open"}}))

    response.should eq("")
    sleep 50.milliseconds
    received.should eq(["app://open"])
  end

  it "treats a payload without a type as a command request" do
    host, app = build_host

    response = host.dispatch(%({"id":"xyz","name":"greet","args":{"name":"Fallback"}}))

    app.greeted.should eq(["Fallback"])
    response.should contain("Fallback")
  end

  it "reports unknown commands as failures" do
    host, _app = build_host

    response = host.dispatch(%({"type":"command","id":"err","name":"missing","args":{}}))

    response.should contain("false")
    response.should contain("Unknown command: missing")
  end

  it "emits events to the frontend via emit_to_js" do
    host, _app = build_host

    host.emit_to_js("plugin.event", {value: 42})

    evals = host.webview.as(NullWebView).evals
    evals.size.should eq(1)
    evals[0].should contain("window.__crystalNotify(\"plugin.event\"")
    evals[0].should contain("\"value\":42")
  end
end
