require "../src/positron/command_registry"
require "../src/positron/state_manager"
require "../src/positron/plugin"
require "../src/positron/js_facade_generator"
require "spec"
require "json"

# A minimal plugin carrying a manifest, for facade generation tests.
class ManifestPlugin < Positron::Plugin
  getter command_manifest : Hash(String, Positron::CommandManifest)

  def initialize(@plugin_name : String, @command_manifest)
  end

  def name : String
    @plugin_name
  end

  def supported_platforms : Array(Symbol)
    [:desktop]
  end

  def manifest : Hash(String, Positron::CommandManifest)
    @command_manifest
  end
end

describe Positron::JSFacadeGenerator do
  it "generates the core runtime API" do
    js = Positron::JSFacadeGenerator.new([] of Positron::Plugin).runtime_js

    js.should contain("call: function(name, args)")
    js.should contain("emit: function(event, payload)")
    js.should contain("on: function(event, callback)")
    js.should contain("__positronResolve")
    js.should contain("__positronNotify")
    js.should contain("PositronBridge.postMessage")
  end

  it "generates plugin namespaces from manifests" do
    plugin = ManifestPlugin.new("storage", {
      "storage.get" => Positron::CommandManifest.new(
        name: "storage.get",
        args: [Positron::ArgumentManifest.new(name: "key", type: "String")],
        returns: "String",
      ),
      "storage.set" => Positron::CommandManifest.new(
        name: "storage.set",
        args: [
          Positron::ArgumentManifest.new(name: "key", type: "String"),
          Positron::ArgumentManifest.new(name: "value", type: "String"),
        ],
      ),
    })

    js = Positron::JSFacadeGenerator.new([plugin] of Positron::Plugin).runtime_js

    js.should contain("storage: {")
    js.should contain("get: function(args)")
    js.should contain("set: function(args)")
    js.should contain("Positron.call('storage.get'")
    js.should contain("Positron.call('storage.set'")
  end

  it "groups nested namespaces under one object" do
    plugin = ManifestPlugin.new("deep", {
      "deep.nested.one" => Positron::CommandManifest.new(name: "deep.nested.one"),
      "deep.nested.two" => Positron::CommandManifest.new(name: "deep.nested.two"),
      "deep.top"        => Positron::CommandManifest.new(name: "deep.top"),
    })

    js = Positron::JSFacadeGenerator.new([plugin] of Positron::Plugin).runtime_js

    js.should contain("nested: {")
    js.should contain("one: function(args)")
    js.should contain("two: function(args)")
    js.should contain("top: function(args)")
  end

  it "skips namespaces entirely when no plugin has a manifest" do
    plugin = ManifestPlugin.new("empty", {} of String => Positron::CommandManifest)
    js = Positron::JSFacadeGenerator.new([plugin] of Positron::Plugin).runtime_js

    js.should_not contain("empty: {")
  end

  it "builds hydrate and state patch scripts" do
    generator = Positron::JSFacadeGenerator.new([] of Positron::Plugin)

    hydrate = generator.hydrate_js({"theme" => JSON.parse(%({"mode":"dark"}))})
    hydrate.should contain("__positronHydrate(")
    hydrate.should contain(%("mode":"dark"))

    patch = generator.patch_js("theme", "mode", JSON.parse(%("light")))
    patch.should contain("__positronPatchState(")
    patch.should contain(%("plugin":"theme"))
    patch.should contain(%("key":"mode"))
    patch.should contain(%("value":"light"))
  end
end
