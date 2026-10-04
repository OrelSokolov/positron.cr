require "log"
require "./adapter"

module Positron::Plugins
  # macOS display adapter (stub).
  class MacOSDisplayAdapter < DisplayAdapter
    def info : DisplayInfo
      Log.for("positron.plugins.display").warn { "macOS display detection not yet implemented" }
      fallback_screen
    end

    private def fallback_screen : DisplayInfo
      screen = DisplayMonitorInfo.new(
        id: "fallback",
        name: "Fallback monitor",
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
        scale_factor: 1.0,
        dpi: 96.0,
        refresh_rate: 60.0,
        orientation: "landscape",
        primary: true
      )
      DisplayInfo.new(
        screens: [screen],
        primary_screen_id: "fallback",
        total_width: 1920,
        total_height: 1080,
        orientation: "landscape"
      )
    end
  end
end
