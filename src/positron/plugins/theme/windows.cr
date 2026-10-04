require "log"
require "./adapter"

module Positron::Plugins
  # Windows implementation of the theme adapter.
  #
  # Reads appearance settings through `reg query` (the same
  # subprocess-based pattern the Linux adapter uses with gsettings):
  #   - dark/light: HKCU\...\Themes\Personalize\AppsUseLightTheme
  #   - accent:     HKCU\Software\Microsoft\Windows\DWM\AccentColor (ABGR)
  #   - high contrast: HKCU\Control Panel\Accessibility\HighContrast\Flags
  class WindowsThemeAdapter < ThemeAdapter
    PERSONALIZE_KEY = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
    DWM_KEY         = "HKCU\\Software\\Microsoft\\Windows\\DWM"
    HIGH_CONTRAST_KEY = "HKCU\\Control Panel\\Accessibility\\HighContrast"

    def info : ThemeInfo
      ThemeInfo.new(
        mode: detect_mode,
        accent_color: detect_accent_color,
        material_you: false,
        high_contrast: detect_high_contrast
      )
    end

    private def detect_mode : String
      value = reg_get_dword(PERSONALIZE_KEY, "AppsUseLightTheme")
      value == 0 ? "dark" : "light"
    end

    private def detect_accent_color : String?
      raw = reg_get_dword(DWM_KEY, "AccentColor")
      return nil unless raw
      # The registry stores the accent as 0xAABBGGRR.
      r = (raw >> 0) & 0xFF
      g = (raw >> 8) & 0xFF
      b = (raw >> 16) & 0xFF
      "##{hex_byte(r)}#{hex_byte(g)}#{hex_byte(b)}"
    rescue ex
      Log.for("positron.plugins.theme").warn { "failed to detect accent color: #{ex.message}" }
      nil
    end

    private def hex_byte(value : Int32) : String
      value.to_s(16).rjust(2, '0').upcase
    end

    private def detect_high_contrast : Bool
      flags = reg_get_string(HIGH_CONTRAST_KEY, "Flags")
      flags.try(&.includes?("HighContrastOn")) == true
    end

    private def reg_query(key : String, value : String) : String?
      output = IO::Memory.new
      status = Process.run(
        "reg",
        ["query", key, "/v", value],
        output: output,
        error: Process::Redirect::Close
      )
      return nil unless status.success?

      result = output.to_s
      return nil unless result.includes?("REG_DWORD") || result.includes?("REG_SZ")

      result.each_line do |line|
        next unless line.includes?(value)
        parts = line.strip.split(/\s{2,}/)
        return parts.last?
      end
      nil
    rescue ex
      Log.for("positron.plugins.theme").warn { "reg query #{key} #{value} failed: #{ex.message}" }
      nil
    end

    private def reg_get_dword(key : String, value : String) : Int32?
      raw = reg_query(key, value)
      return nil unless raw
      raw.to_i32?(base: 16, prefix: true) || raw.to_i32?
    end

    private def reg_get_string(key : String, value : String) : String?
      reg_query(key, value)
    end
  end
end
