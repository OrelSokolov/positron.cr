require "log"
require "./adapter"

module Positron::Plugins
  # Linux (Ubuntu/GNOME) implementation of the theme adapter.
  #
  # Reads appearance settings through `gsettings`, which is the canonical
  # way to query the GNOME desktop environment used by Ubuntu.
  class LinuxThemeAdapter < ThemeAdapter
    # Approximate GNOME / Yaru accent palette.
    ACCENT_COLORS = {
      "blue"   => "#3584E4",
      "teal"   => "#26A269",
      "green"  => "#33D17A",
      "yellow" => "#F6D32D",
      "orange" => "#FF7800",
      "red"    => "#E01B24",
      "pink"   => "#F30088",
      "purple" => "#9141AC",
      "slate"  => "#6C6F75",
      "brown"  => "#986A44",
    }

    def info : ThemeInfo
      ThemeInfo.new(
        mode: detect_mode,
        accent_color: detect_accent_color,
        material_you: false,
        high_contrast: detect_high_contrast
      )
    end

    private def detect_mode : String
      value = gsettings_get("org.gnome.desktop.interface", "color-scheme")
      value.try(&.downcase) == "prefer-dark" ? "dark" : "light"
    end

    private def detect_accent_color : String?
      # GNOME 47+ exposes an explicit accent-color key.
      if raw = gsettings_get("org.gnome.desktop.interface", "accent-color")
        color = ACCENT_COLORS[raw.downcase]?
        return color if color
      end

      # Older Ubuntu releases encode the accent in the GTK theme name, e.g.
      # "Yaru-purple-dark" or "Yaru-red".
      if theme = gsettings_get("org.gnome.desktop.interface", "gtk-theme")
        if match = theme.match(/Yaru-([a-z]+)(?:-dark)?$/i)
          return ACCENT_COLORS[match[1].downcase]?
        end
      end

      nil
    rescue ex
      Log.for("positron.plugins.theme").warn { "failed to detect accent color: #{ex.message}" }
      nil
    end

    private def detect_high_contrast : Bool
      value = gsettings_get("org.gnome.desktop.a11y.interface", "high-contrast")
      value.try(&.downcase) == "true"
    end

    private def gsettings_get(schema : String, key : String) : String?
      output = IO::Memory.new
      status = Process.run(
        "gsettings",
        ["get", schema, key],
        output: output,
        error: Process::Redirect::Close
      )
      return nil unless status.success?

      value = output.to_s.strip
      if value.size >= 2 && value.starts_with?("'") && value.ends_with?("'")
        value = value[1..-2]
      end

      value.empty? ? nil : value
    rescue ex
      Log.for("positron.plugins.theme").warn { "gsettings get #{schema} #{key} failed: #{ex.message}" }
      nil
    end
  end
end
