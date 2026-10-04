require "json"
require "./adapter"
require "./factory"

module Positron::Plugins
  # System theme / appearance plugin.
  #
  # Exposes a small host-side API to the frontend:
  #   - theme.get_info()
  #
  # Platform adapters live in `src/positron/plugins/theme/` and are
  # selected at compile time by `ThemeAdapterFactory`.
  #
  # The Linux/Ubuntu adapter reads from `gsettings`:
  #   - org.gnome.desktop.interface color-scheme
  #   - org.gnome.desktop.interface accent-color
  #   - org.gnome.desktop.a11y.interface high-contrast
  class Theme < Positron::Plugin
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

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "theme.get_info" => Positron::CommandManifest.new(
          name: "theme.get_info",
          returns: "Object",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("theme.get_info") do |_request|
        info = @adapter.info

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(info.to_json)
        )
      end
    end
  end
end
