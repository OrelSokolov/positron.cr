require "log"
require "./adapter"

module CrystalUI::Plugins
  # Android theme adapter (stub).
  class AndroidThemeAdapter < ThemeAdapter
    def info : ThemeInfo
      Log.for("crystalui.plugins.theme").warn { "Android theme detection not yet implemented" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end
  end
end
