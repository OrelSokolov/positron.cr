require "log"
require "./adapter"

module CrystalUI::Plugins
  # macOS theme adapter (stub).
  class MacOSThemeAdapter < ThemeAdapter
    def info : ThemeInfo
      Log.for("crystalui.plugins.theme").warn { "macOS theme detection not yet implemented" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end
  end
end
