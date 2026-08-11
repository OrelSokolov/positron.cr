require "json"
require "./adapter"
require "./factory"

module CrystalUI::Plugins
  # Display / screen information plugin.
  #
  # Exposes a host-side API to the frontend:
  #   - display.get_info() -> DisplayInfo
  #
  # Platform adapters live in `src/crystal_ui/plugins/display/` and are
  # selected at compile time by `DisplayAdapterFactory`.
  #
  # The Linux adapter reads from GDK and reports DPI, resolution, position,
  # refresh rate, manufacturer/model and orientation for each monitor.
  class Display < CrystalUI::Plugin
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

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "display.get_info" => CrystalUI::CommandManifest.new(
          name: "display.get_info",
          returns: "Object",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("display.get_info") do |_request|
        info = @adapter.info

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(info.to_json)
        )
      end
    end
  end
end
