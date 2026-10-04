require "json"

module Positron::Plugins
  # Description of a single display / monitor.
  struct DisplayMonitorInfo
    include JSON::Serializable

    # Stable identifier for this monitor (platform specific).
    property id : String

    # Human readable name, e.g. "DP-1" or "Built-in Retina Display".
    property name : String?

    # Position of the monitor in the virtual desktop coordinate space.
    property x : Int32
    property y : Int32

    # Logical resolution in pixels.
    property width : Int32
    property height : Int32

    # UI scale factor reported by the OS (e.g. 1.0, 1.5, 2.0).
    property scale_factor : Float64

    # Approximate DPI. Calculated from the physical size when available,
    # otherwise falls back to `scale_factor * 96.0`.
    property dpi : Float64

    # Refresh rate in Hz.
    property refresh_rate : Float64

    # "landscape" or "portrait".
    property orientation : String

    # True when this is the primary / main monitor.
    property primary : Bool

    # Physical width in millimeters, if known.
    property width_mm : Int32?

    # Physical height in millimeters, if known.
    property height_mm : Int32?

    # Monitor manufacturer, if reported by the OS.
    property manufacturer : String?

    # Monitor model, if reported by the OS.
    property model : String?

    def initialize(
      @id : String,
      @name : String?,
      @x : Int32,
      @y : Int32,
      @width : Int32,
      @height : Int32,
      @scale_factor : Float64,
      @dpi : Float64,
      @refresh_rate : Float64,
      @orientation : String,
      @primary : Bool,
      @width_mm : Int32? = nil,
      @height_mm : Int32? = nil,
      @manufacturer : String? = nil,
      @model : String? = nil,
    )
    end
  end

  # Aggregated information about the system's screens.
  struct DisplayInfo
    include JSON::Serializable

    # All detected monitors.
    property screens : Array(DisplayMonitorInfo)

    # ID of the primary monitor, if any.
    property primary_screen_id : String?

    # Bounding box of the virtual desktop.
    property total_width : Int32
    property total_height : Int32

    # Overall orientation hint. "landscape" when the combined desktop is wider
    # than it is tall, otherwise "portrait".
    property orientation : String

    def initialize(
      @screens : Array(DisplayMonitorInfo),
      @primary_screen_id : String?,
      @total_width : Int32,
      @total_height : Int32,
      @orientation : String,
    )
    end
  end

  # Platform-agnostic interface for reading display / screen information.
  abstract class DisplayAdapter
    # Returns information about all connected displays and the virtual desktop.
    abstract def info : DisplayInfo
  end
end
