require "log"
require "./adapter"

module Positron::Plugins
  # Android theme adapter (stub).
  class AndroidThemeAdapter < ThemeAdapter
    def info : ThemeInfo
      Log.for("positron.plugins.theme").warn { "Android theme detection not yet implemented" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end
  end
end
