require "../src/crystal_ui/command_registry"
require "../src/crystal_ui/state_manager"
require "../src/crystal_ui/plugin"
require "../src/crystal_ui/js_facade_generator"
require "spec"
require "json"

# A minimal plugin carrying a manifest, for facade generation tests.
class ManifestPlugin < CrystalUI::Plugin
  getter command_manifest : Hash(String, CrystalUI::CommandManifest)

  def initialize(@plugin_name : String, @command_manifest)
  end

  def name : String
    @plugin_name
  end

  def supported_platforms : Array(Symbol)
    [:desktop]
  end

  def manifest : Hash(String, CrystalUI::CommandManifest)
    @command_manifest
  end
end

describe CrystalUI::JSFacadeGenerator do
  it "generates the core runtime API" do
    js = CrystalUI::JSFacadeGenerator.new([] of CrystalUI::Plugin).runtime_js

    js.should contain("call: function(name, args)")
    js.should contain("emit: function(event, payload)")
    js.should contain("on: function(event, callback)")
    js.should contain("__crystalResolve")
    js.should contain("__crystalNotify")
    js.should contain("CrystalBridge.postMessage")
  end

  it "generates plugin namespaces from manifests" do
    plugin = ManifestPlugin.new("storage", {
      "storage.get" => CrystalUI::CommandManifest.new(
        name: "storage.get",
        args: [CrystalUI::ArgumentManifest.new(name: "key", type: "String")],
        returns: "String",
      ),
      "storage.set" => CrystalUI::CommandManifest.new(
        name: "storage.set",
        args: [
          CrystalUI::ArgumentManifest.new(name: "key", type: "String"),
          CrystalUI::ArgumentManifest.new(name: "value", type: "String"),
        ],
      ),
    })

    js = CrystalUI::JSFacadeGenerator.new([plugin] of CrystalUI::Plugin).runtime_js

    js.should contain("storage: {")
    js.should contain("get: function(args)")
    js.should contain("set: function(args)")
    js.should contain("CrystalUI.call('storage.get'")
    js.should contain("CrystalUI.call('storage.set'")
  end

  it "groups nested namespaces under one object" do
    plugin = ManifestPlugin.new("deep", {
      "deep.nested.one" => CrystalUI::CommandManifest.new(name: "deep.nested.one"),
      "deep.nested.two" => CrystalUI::CommandManifest.new(name: "deep.nested.two"),
      "deep.top"        => CrystalUI::CommandManifest.new(name: "deep.top"),
    })

    js = CrystalUI::JSFacadeGenerator.new([plugin] of CrystalUI::Plugin).runtime_js

    js.should contain("nested: {")
    js.should contain("one: function(args)")
    js.should contain("two: function(args)")
    js.should contain("top: function(args)")
  end

  it "skips namespaces entirely when no plugin has a manifest" do
    plugin = ManifestPlugin.new("empty", {} of String => CrystalUI::CommandManifest)
    js = CrystalUI::JSFacadeGenerator.new([plugin] of CrystalUI::Plugin).runtime_js

    js.should_not contain("empty: {")
  end

  it "builds hydrate and state patch scripts" do
    generator = CrystalUI::JSFacadeGenerator.new([] of CrystalUI::Plugin)

    hydrate = generator.hydrate_js({"theme" => JSON.parse(%({"mode":"dark"}))})
    hydrate.should contain("__crystalHydrate(")
    hydrate.should contain(%("mode":"dark"))

    patch = generator.patch_js("theme", "mode", JSON.parse(%("light")))
    patch.should contain("__crystalPatchState(")
    patch.should contain(%("plugin":"theme"))
    patch.should contain(%("key":"mode"))
    patch.should contain(%("value":"light"))
  end
end
