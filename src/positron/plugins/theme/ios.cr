require "log"
require "./adapter"

module Positron::Plugins
  # iOS theme adapter (stub).
  class IOsThemeAdapter < ThemeAdapter
    def info : ThemeInfo
      Log.for("positron.plugins.theme").warn { "iOS theme detection not yet implemented" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end
  end
end
