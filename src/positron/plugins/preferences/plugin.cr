require "json"
require "./adapter"
require "./factory"

module Positron::Plugins
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
  # Platform adapters live in `src/positron/plugins/preferences/` and are
  # selected at compile time by `PreferencesAdapterFactory`.
  class Preferences < Positron::Plugin
    @adapter : PreferencesAdapter

    def initialize(@app_id : String = "positron")
      @adapter = PreferencesAdapterFactory.create(@app_id)
    end

    def name : String
      "preferences"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "preferences.get" => Positron::CommandManifest.new(
          name: "preferences.get",
          args: [
            Positron::ArgumentManifest.new(name: "key", type: "String"),
            Positron::ArgumentManifest.new(name: "default", type: "Any"),
          ],
          returns: "Any",
        ),
        "preferences.set" => Positron::CommandManifest.new(
          name: "preferences.set",
          args: [
            Positron::ArgumentManifest.new(name: "key", type: "String"),
            Positron::ArgumentManifest.new(name: "value", type: "Any"),
          ],
          returns: "Bool",
        ),
        "preferences.remove" => Positron::CommandManifest.new(
          name: "preferences.remove",
          args: [
            Positron::ArgumentManifest.new(name: "key", type: "String"),
          ],
          returns: "Bool",
        ),
        "preferences.clear" => Positron::CommandManifest.new(
          name: "preferences.clear",
          returns: "Bool",
        ),
        "preferences.has" => Positron::CommandManifest.new(
          name: "preferences.has",
          args: [
            Positron::ArgumentManifest.new(name: "key", type: "String"),
          ],
          returns: "Bool",
        ),
        "preferences.get_all" => Positron::CommandManifest.new(
          name: "preferences.get_all",
          returns: "Object",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("preferences.get") do |request|
        key = request.args["key"].as_s
        default = request.args["default"]?

        value = @adapter.get(key, default)

        Positron::CommandResult.new(
          success: true,
          data: value
        )
      end

      registry.register("preferences.set") do |request|
        key = request.args["key"].as_s
        value = request.args["value"]

        ok = @adapter.set(key, value)

        Positron::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end

      registry.register("preferences.remove") do |request|
        key = request.args["key"].as_s
        ok = @adapter.remove(key)

        Positron::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end

      registry.register("preferences.clear") do |_request|
        ok = @adapter.clear

        Positron::CommandResult.new(
          success: ok,
          data: JSON.parse(ok.to_json)
        )
      end

      registry.register("preferences.has") do |request|
        key = request.args["key"].as_s
        exists = @adapter.has?(key)

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(exists.to_json)
        )
      end

      registry.register("preferences.get_all") do |_request|
        values = @adapter.all

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(values.to_json)
        )
      end
    end
  end
end
