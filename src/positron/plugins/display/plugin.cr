require "json"
require "./adapter"
require "./factory"

module Positron::Plugins
  # Display / screen information plugin.
  #
  # Exposes a host-side API to the frontend:
  #   - display.get_info() -> DisplayInfo
  #
  # Platform adapters live in `src/positron/plugins/display/` and are
  # selected at compile time by `DisplayAdapterFactory`.
  #
  # The Linux adapter reads from GDK and reports DPI, resolution, position,
  # refresh rate, manufacturer/model and orientation for each monitor.
  class Display < Positron::Plugin
    @adapter : DisplayAdapter

    def initialize
      @adapter = DisplayAdapterFactory.create
    end

    def name : String
      "display"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "display.get_info" => Positron::CommandManifest.new(
          name: "display.get_info",
          returns: "Object",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("display.get_info") do |_request|
        info = @adapter.info

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(info.to_json)
        )
      end
    end
  end
end
