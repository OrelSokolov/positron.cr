require "log"
require "./adapter"

module Positron::Plugins
  # Linux (GTK/GDK) implementation of the Display plugin.
  #
  # Reads monitor information through GDK, which works on both X11 and
  # Wayland sessions.
  class LinuxDisplayAdapter < DisplayAdapter
    def info : DisplayInfo
      display = default_display
      return fallback_info("no default display") if display.null?

      n = LibGDK.gdk_display_get_n_monitors(display)
      return fallback_info("no monitors detected") if n <= 0

      screens = [] of DisplayMonitorInfo
      primary = LibGDK.gdk_display_get_primary_monitor(display)
      primary_id : String? = nil

      n.times do |i|
        monitor = LibGDK.gdk_display_get_monitor(display, i)
        next if monitor.null?

        screen = build_screen(monitor, primary, i)
        screens << screen
        primary_id = screen.id if screen.primary
      end

      if screens.empty?
        return fallback_info("monitors could not be enumerated")
      end

      min_x = screens.min_of(&.x)
      min_y = screens.min_of(&.y)
      max_right = screens.max_of { |s| s.x + s.width }
      max_bottom = screens.max_of { |s| s.y + s.height }
      total_width = max_right - min_x
      total_height = max_bottom - min_y
      orientation = total_width >= total_height ? "landscape" : "portrait"

      DisplayInfo.new(
        screens: screens,
        primary_screen_id: primary_id,
        total_width: total_width,
        total_height: total_height,
        orientation: orientation
      )
    end

    private def default_display : Void*
      LibGDK.gdk_display_get_default
    end

    private def build_screen(monitor : Void*, primary : Void*, index : Int32) : DisplayMonitorInfo
      rect = LibGDK::GdkRectangle.new
      LibGDK.gdk_monitor_get_geometry(monitor, pointerof(rect))

      scale = LibGDK.gdk_monitor_get_scale_factor(monitor)
      width_mm = LibGDK.gdk_monitor_get_width_mm(monitor)
      height_mm = LibGDK.gdk_monitor_get_height_mm(monitor)
      refresh_mhz = LibGDK.gdk_monitor_get_refresh_rate(monitor)

      manufacturer_ptr = LibGDK.gdk_monitor_get_manufacturer(monitor)
      model_ptr = LibGDK.gdk_monitor_get_model(monitor)

      manufacturer = manufacturer_ptr.null? ? nil : String.new(manufacturer_ptr)
      model = model_ptr.null? ? nil : String.new(model_ptr)
      name = model || manufacturer || "Monitor #{index + 1}"
      id = "monitor-#{index}"

      is_primary = monitor == primary

      dpi = compute_dpi(rect.width, rect.height, width_mm, height_mm, scale)
      refresh_rate = refresh_mhz > 0 ? refresh_mhz / 1000.0 : 60.0
      orientation = rect.width >= rect.height ? "landscape" : "portrait"

      DisplayMonitorInfo.new(
        id: id,
        name: name,
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        scale_factor: scale.to_f,
        dpi: dpi,
        refresh_rate: refresh_rate,
        orientation: orientation,
        primary: is_primary,
        width_mm: width_mm > 0 ? width_mm : nil,
        height_mm: height_mm > 0 ? height_mm : nil,
        manufacturer: manufacturer,
        model: model
      )
    end

    private def compute_dpi(width : Int32, height : Int32, width_mm : Int32, height_mm : Int32, scale : Int32) : Float64
      # Prefer physical size when the OS reports something reasonable.
      if width_mm > 0 && height_mm > 0
        diagonal_px = Math.sqrt(width ** 2 + height ** 2)
        diagonal_mm = Math.sqrt(width_mm ** 2 + height_mm ** 2)
        return (diagonal_px / diagonal_mm * 25.4).round(2)
      end

      scale.to_f * 96.0
    end

    private def fallback_info(reason : String) : DisplayInfo
      Log.for("positron.plugins.display").warn { "#{reason}; returning fallback display info" }
      screen = DisplayMonitorInfo.new(
        id: "fallback",
        name: "Fallback monitor",
        x: 0,
        y: 0,
        width: 1920,
        height: 1080,
        scale_factor: 1.0,
        dpi: 96.0,
        refresh_rate: 60.0,
        orientation: "landscape",
        primary: true
      )
      DisplayInfo.new(
        screens: [screen],
        primary_screen_id: "fallback",
        total_width: 1920,
        total_height: 1080,
        orientation: "landscape"
      )
    end

    @[Link("gdk-3")]
    lib LibGDK
      struct GdkRectangle
        x : Int32
        y : Int32
        width : Int32
        height : Int32
      end

      fun gdk_display_get_default : Void*
      fun gdk_display_get_n_monitors(display : Void*) : Int32
      fun gdk_display_get_monitor(display : Void*, index : Int32) : Void*
      fun gdk_display_get_primary_monitor(display : Void*) : Void*
      fun gdk_monitor_get_geometry(monitor : Void*, rect : GdkRectangle*)
      fun gdk_monitor_get_scale_factor(monitor : Void*) : Int32
      fun gdk_monitor_get_width_mm(monitor : Void*) : Int32
      fun gdk_monitor_get_height_mm(monitor : Void*) : Int32
      fun gdk_monitor_get_refresh_rate(monitor : Void*) : Int32
      fun gdk_monitor_get_manufacturer(monitor : Void*) : LibC::Char*
      fun gdk_monitor_get_model(monitor : Void*) : LibC::Char*
    end
  end
end
