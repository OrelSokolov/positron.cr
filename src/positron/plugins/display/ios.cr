require "log"
require "./adapter"

module Positron::Plugins
  # iOS display adapter (stub).
  class IOsDisplayAdapter < DisplayAdapter
    def info : DisplayInfo
      Log.for("positron.plugins.display").warn { "iOS display detection not yet implemented" }
      fallback_screen
    end

    private def fallback_screen : DisplayInfo
      screen = DisplayMonitorInfo.new(
        id: "fallback",
        name: "Fallback monitor",
        x: 0,
        y: 0,
        width: 1170,
        height: 2532,
        scale_factor: 3.0,
        dpi: 460.0,
        refresh_rate: 60.0,
        orientation: "portrait",
        primary: true
      )
      DisplayInfo.new(
        screens: [screen],
        primary_screen_id: "fallback",
        total_width: 1170,
        total_height: 2532,
        orientation: "portrait"
      )
    end
  end
end
