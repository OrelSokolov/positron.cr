require "log"
require "./adapter"

module CrystalUI::Plugins
  # Windows theme adapter (stub).
  class WindowsThemeAdapter < ThemeAdapter
    def info : ThemeInfo
      Log.for("crystalui.plugins.theme").warn { "Windows theme detection not yet implemented" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end
  end
end
