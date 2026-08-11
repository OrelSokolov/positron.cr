require "json"
require "./adapter"
require "./factory"

module CrystalUI::Plugins
  # System theme / appearance plugin.
  #
  # Exposes a small host-side API to the frontend:
  #   - theme.get_info()
  #
  # Platform adapters live in `src/crystal_ui/plugins/theme/` and are
  # selected at compile time by `ThemeAdapterFactory`.
  #
  # The Linux/Ubuntu adapter reads from `gsettings`:
  #   - org.gnome.desktop.interface color-scheme
  #   - org.gnome.desktop.interface accent-color
  #   - org.gnome.desktop.a11y.interface high-contrast
  class Theme < CrystalUI::Plugin
    @adapter : ThemeAdapter

    def initialize
      @adapter = ThemeAdapterFactory.create
    end

    def name : String
      "theme"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "theme.get_info" => CrystalUI::CommandManifest.new(
          name: "theme.get_info",
          returns: "Object",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("theme.get_info") do |_request|
        info = @adapter.info

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(info.to_json)
        )
      end
    end
  end
end
