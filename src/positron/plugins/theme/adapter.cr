require "json"

module Positron::Plugins
  # Description of the current system appearance.
  struct ThemeInfo
    include JSON::Serializable

    # "light" or "dark".
    property mode : String

    # OS accent color as an RGB hex string (e.g. "#E95420"), or nil if unknown.
    property accent_color : String?

    # True when the OS uses Material You / dynamic color (Android only).
    property material_you : Bool

    # True when high contrast mode is enabled.
    property high_contrast : Bool

    def initialize(@mode : String, @accent_color : String?, @material_you : Bool, @high_contrast : Bool)
    end
  end

  # Platform-agnostic interface for reading the system theme / appearance.
  abstract class ThemeAdapter
    # Returns the current system appearance information.
    abstract def info : ThemeInfo
  end
end
