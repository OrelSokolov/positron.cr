require "log"
require "./adapter"

module Positron::Plugins
  # Windows theme adapter (stub).
  class WindowsThemeAdapter < ThemeAdapter
    def info : ThemeInfo
      Log.for("positron.plugins.theme").warn { "Windows theme detection not yet implemented" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end
  end
end
