require "../src/crystal_ui/command_registry"
require "../src/crystal_ui/state_manager"
require "../src/crystal_ui/plugin"
require "../src/crystal_ui/js_facade_generator"
require "../src/crystal_ui/bindings_generator"
require "../src/crystal_ui/dev/asset_server"
require "../src/crystal_ui/ports/webview_port"
require "../src/crystal_ui/ports/tray_port"
require "../src/crystal_ui/host"
require "../src/crystal_ui/application"
require "spec"
require "json"

# Plugin with a manifest for bindings generation tests.
class BindingsPlugin < CrystalUI::Plugin
  def name : String
    "fs"
  end

  def supported_platforms : Array(Symbol)
    [:desktop]
  end

  def manifest : Hash(String, CrystalUI::CommandManifest)
    {
      "fs.read" => CrystalUI::CommandManifest.new(
        name: "fs.read",
        args: [CrystalUI::ArgumentManifest.new(name: "path", type: "String")],
        returns: "String",
      ),
      "fs.write" => CrystalUI::CommandManifest.new(
        name: "fs.write",
        args: [
          CrystalUI::ArgumentManifest.new(name: "path", type: "String"),
          CrystalUI::ArgumentManifest.new(name: "size", type: "Int32"),
          CrystalUI::ArgumentManifest.new(name: "force", type: "Bool"),
        ],
        returns: "Bool",
      ),
    }
  end
end

# Application with @[Command] methods exercising the macro-generated manifest.
class BindingsApp < CrystalUI::Application
  def on_ready; end

  def application_html : String
    ""
  end

  def register_commands(registry)
    command_registry
  end

  @[CrystalUI::Command]
  def greet : String
    "hi"
  end

  @[CrystalUI::Command]
  def ping : Bool
    true
  end
end

describe CrystalUI::BindingsGenerator do
  it "maps Crystal types to TypeScript" do
    CrystalUI::BindingsGenerator.crystal_type_to_ts("String").should eq("string")
    CrystalUI::BindingsGenerator.crystal_type_to_ts("Int32").should eq("number")
    CrystalUI::BindingsGenerator.crystal_type_to_ts("Float64").should eq("number")
    CrystalUI::BindingsGenerator.crystal_type_to_ts("Bool").should eq("boolean")
    CrystalUI::BindingsGenerator.crystal_type_to_ts(nil).should eq("any")
    CrystalUI::BindingsGenerator.crystal_type_to_ts("JSON::Any").should eq("any")
  end

  it "generates typed plugin namespaces" do
    ts = CrystalUI::BindingsGenerator.new(
      [BindingsPlugin.new] of CrystalUI::Plugin).typescript

    ts.should contain("declare namespace CrystalUI")
    ts.should contain("function call(name: string")
    ts.should contain("namespace fs {")
    ts.should contain("function read(args: { path: string }): Promise<string>;")
    ts.should contain("function write(args: { path: string, size: number, force: boolean }): Promise<boolean>;")
  end

  it "includes app commands from the macro-generated manifest" do
    app = BindingsApp.new
    # Command manifests are populated when commands are registered —
    # in a real app this happens before on_ready/serve_directory.
    app.register_commands(CrystalUI::CommandRegistry.new)

    ts = CrystalUI::BindingsGenerator.new([] of CrystalUI::Plugin, app).typescript

    ts.should contain("function greet(args?: Record<string, any>): Promise<any>;")
    ts.should contain("function ping(args?: Record<string, any>): Promise<any>;")
  end

  it "produces the same manifests the macro registers as commands" do
    app = BindingsApp.new
    registry = CrystalUI::CommandRegistry.new
    app.register_commands(registry)

    manifests = app.command_manifests
    manifests.has_key?("greet").should be_true
    manifests.has_key?("ping").should be_true
    manifests["ping"].args.should be_empty
  end
end
