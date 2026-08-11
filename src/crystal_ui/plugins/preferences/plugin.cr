require "json"
require "./adapter"
require "./factory"

module CrystalUI::Plugins
  # Persistent key-value preferences plugin.
  #
  # Exposes a small host-side API to the frontend:
  #   - preferences.get(key, default?)
  #   - preferences.set(key, value)
  #   - preferences.remove(key)
  #   - preferences.clear()
  #   - preferences.has(key)
  #   - preferences.get_all()
  #
  # Platform adapters live in `src/crystal_ui/plugins/preferences/` and are
  # selected at compile time by `PreferencesAdapterFactory`.
  class Preferences < CrystalUI::Plugin
    @adapter : PreferencesAdapter

    def initialize(@app_id : String = "crystalui")
      @adapter = PreferencesAdapterFactory.create(@app_id)
    end

    def name : String
      "preferences"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "preferences.get" => CrystalUI::CommandManifest.new(
          name: "preferences.get",
          args: [
            CrystalUI::ArgumentManifest.new(name: "key", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "default", type: "Any"),
          ],
          returns: "Any",
        ),
        "preferences.set" => CrystalUI::CommandManifest.new(
          name: "preferences.set",
          args: [
            CrystalUI::ArgumentManifest.new(name: "key", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "value", type: "Any"),
          ],
          returns: "Bool",
        ),
        "preferences.remove" => CrystalUI::CommandManifest.new(
          name: "preferences.remove",
          args: [
            CrystalUI::ArgumentManifest.new(name: "key", type: "String"),
          ],
          returns: "Bool",
        ),
        "preferences.clear" => CrystalUI::CommandManifest.new(
          name: "preferences.clear",
          returns: "Bool",
        ),
        "preferences.has" => CrystalUI::CommandManifest.new(
          name: "preferences.has",
          args: [
            CrystalUI::ArgumentManifest.new(name: "key", type: "String"),
          ],
          returns: "Bool",
        ),
        "preferences.get_all" => CrystalUI::CommandManifest.new(
          name: "preferences.get_all",
          returns: "Object",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("preferences.get") do |request|
        key = request.args["key"].as_s
        default = request.args["default"]?

        value = @adapter.get(key, default)

        CrystalUI::CommandResult.new(
          success: true,
          data: value
        )
      end

      registry.register("preferences.set") do |request|
        key = request.args["key"].as_s
        value = request.args["value"]

        ok = @adapter.set(key, value)

        CrystalUI::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end

      registry.register("preferences.remove") do |request|
        key = request.args["key"].as_s
        ok = @adapter.remove(key)

        CrystalUI::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end

      registry.register("preferences.clear") do |_request|
        ok = @adapter.clear

        CrystalUI::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end

      registry.register("preferences.has") do |request|
        key = request.args["key"].as_s
        exists = @adapter.has?(key)

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(exists.to_json)
        )
      end

      registry.register("preferences.get_all") do |_request|
        values = @adapter.all

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(values.to_json)
        )
      end
    end
  end
end
