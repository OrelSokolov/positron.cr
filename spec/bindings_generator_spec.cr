require "../src/positron/command_registry"
require "../src/positron/state_manager"
require "../src/positron/plugin"
require "../src/positron/js_facade_generator"
require "../src/positron/bindings_generator"
require "../src/positron/dev/asset_server"
require "../src/positron/ports/webview_port"
require "../src/positron/ports/tray_port"
require "../src/positron/host"
require "../src/positron/application"
require "spec"
require "json"

# Plugin with a manifest for bindings generation tests.
class BindingsPlugin < Positron::Plugin
  def name : String
    "fs"
  end

  def supported_platforms : Array(Symbol)
    [:desktop]
  end

  def manifest : Hash(String, Positron::CommandManifest)
    {
      "fs.read" => Positron::CommandManifest.new(
        name: "fs.read",
        args: [Positron::ArgumentManifest.new(name: "path", type: "String")],
        returns: "String",
      ),
      "fs.write" => Positron::CommandManifest.new(
        name: "fs.write",
        args: [
          Positron::ArgumentManifest.new(name: "path", type: "String"),
          Positron::ArgumentManifest.new(name: "size", type: "Int32"),
          Positron::ArgumentManifest.new(name: "force", type: "Bool"),
        ],
        returns: "Bool",
      ),
    }
  end
end

# Application with @[Command] methods exercising the macro-generated manifest.
class BindingsApp < Positron::Application
  def on_ready; end

  def application_html : String
    ""
  end

  def register_commands(registry)
    command_registry
  end

  @[Positron::Command]
  def greet : String
    "hi"
  end

  @[Positron::Command]
  def ping : Bool
    true
  end
end

describe Positron::BindingsGenerator do
  it "maps Crystal types to TypeScript" do
    Positron::BindingsGenerator.crystal_type_to_ts("String").should eq("string")
    Positron::BindingsGenerator.crystal_type_to_ts("Int32").should eq("number")
    Positron::BindingsGenerator.crystal_type_to_ts("Float64").should eq("number")
    Positron::BindingsGenerator.crystal_type_to_ts("Bool").should eq("boolean")
    Positron::BindingsGenerator.crystal_type_to_ts(nil).should eq("any")
    Positron::BindingsGenerator.crystal_type_to_ts("JSON::Any").should eq("any")
  end

  it "generates typed plugin namespaces" do
    ts = Positron::BindingsGenerator.new(
      [BindingsPlugin.new] of Positron::Plugin).typescript

    ts.should contain("declare namespace Positron")
    ts.should contain("function call(name: string")
    ts.should contain("namespace fs {")
    ts.should contain("function read(args: { path: string }): Promise<string>;")
    ts.should contain("function write(args: { path: string, size: number, force: boolean }): Promise<boolean>;")
  end

  it "includes app commands from the macro-generated manifest" do
    app = BindingsApp.new
    # Command manifests are populated when commands are registered —
    # in a real app this happens before on_ready/serve_directory.
    app.register_commands(Positron::CommandRegistry.new)

    ts = Positron::BindingsGenerator.new([] of Positron::Plugin, app).typescript

    ts.should contain("function greet(args?: Record<string, any>): Promise<any>;")
    ts.should contain("function ping(args?: Record<string, any>): Promise<any>;")
  end

  it "produces the same manifests the macro registers as commands" do
    app = BindingsApp.new
    registry = Positron::CommandRegistry.new
    app.register_commands(registry)

    manifests = app.command_manifests
    manifests.has_key?("greet").should be_true
    manifests.has_key?("ping").should be_true
    manifests["ping"].args.should be_empty
  end
end
