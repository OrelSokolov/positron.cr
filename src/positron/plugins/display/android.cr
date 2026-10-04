require "log"
require "./adapter"

module Positron::Plugins
  # Android display adapter (stub).
  class AndroidDisplayAdapter < DisplayAdapter
    def info : DisplayInfo
      Log.for("positron.plugins.display").warn { "Android display detection not yet implemented" }
      fallback_screen
    end

    private def fallback_screen : DisplayInfo
      screen = DisplayMonitorInfo.new(
        id: "fallback",
        name: "Fallback monitor",
        x: 0,
        y: 0,
        width: 1080,
        height: 1920,
        scale_factor: 2.0,
        dpi: 420.0,
        refresh_rate: 60.0,
        orientation: "portrait",
        primary: true
      )
      DisplayInfo.new(
        screens: [screen],
        primary_screen_id: "fallback",
        total_width: 1080,
        total_height: 1920,
        orientation: "portrait"
      )
    end
  end
end
