require "log"
require "./adapter"
require "../../adapters/macos/objc"

module Positron::Plugins
  # macOS display adapter using the CoreGraphics C API: the online
  # display list, per-display bounds in logical points, pixel size (for
  # the scale factor), the physical screen size in millimetres (for DPI)
  # and the current display mode's refresh rate.
  #
  # CG bounds use a bottom-left origin; the y coordinates are flipped
  # into the top-left space of the Linux reference (primary monitor at
  # (0,0), displays below it at positive y).
  class MacOSDisplayAdapter < DisplayAdapter
    def info : DisplayInfo
      ids = display_ids
      return fallback_info("no displays detected") if ids.empty?

      main = LibCG.CGMainDisplayID
      main_bounds = LibCG.CGDisplayBounds(main)
      main_top = main_bounds.origin.y + main_bounds.size.height

      screens = ids.each_with_index.map do |id, index|
        build_screen(id, index, main, main_top)
      end.to_a
      return fallback_info("displays could not be enumerated") if screens.empty?

      min_x = screens.min_of(&.x)
      min_y = screens.min_of(&.y)
      total_width = screens.max_of { |s| s.x + s.width } - min_x
      total_height = screens.max_of { |s| s.y + s.height } - min_y
      orientation = total_width >= total_height ? "landscape" : "portrait"

      DisplayInfo.new(
        screens: screens,
        primary_screen_id: screens.find(&.primary).try(&.id),
        total_width: total_width,
        total_height: total_height,
        orientation: orientation
      )
    end

    # --- Internals ---

    private def display_ids : Array(UInt32)
      buffer = Pointer(UInt32).malloc(16)
      count = Pointer(UInt32).malloc(1)
      if LibCG.CGGetOnlineDisplayList(16, buffer, count) != 0 || count.value == 0
        return [] of UInt32
      end
      Slice.new(buffer, Math.min(count.value, 16)).to_a
    end

    private def build_screen(id : UInt32, index : Int32, main_id : UInt32, main_top : Float64) : DisplayMonitorInfo
      bounds = LibCG.CGDisplayBounds(id)

      # CGDisplayPixelsWide returns *logical* points on HiDPI displays —
      # the physical pixel size of the current mode gives the scale.
      mode = LibCG.CGDisplayCopyDisplayMode(id)
      if mode.null?
        pixel_width = bounds.size.width
        refresh_rate = 60.0
      else
        pixel_width = LibCG.CGDisplayModeGetPixelWidth(mode).to_f
        rate = LibCG.CGDisplayModeGetRefreshRate(mode)
        LibCF.CFRelease(mode)
        refresh_rate = rate > 0 ? rate : 60.0
      end
      scale = bounds.size.width > 0 ? pixel_width / bounds.size.width : 1.0

      size_mm = LibCG.CGDisplayScreenSize(id)
      width_mm = size_mm.width.round.to_i
      height_mm = size_mm.height.round.to_i

      dpi = compute_dpi(bounds.size.width, bounds.size.height, width_mm, height_mm, scale)

      DisplayMonitorInfo.new(
        id: "monitor-#{index}",
        name: "Display #{index + 1}",
        x: bounds.origin.x.round.to_i,
        y: (main_top - (bounds.origin.y + bounds.size.height)).round.to_i,
        width: bounds.size.width.round.to_i,
        height: bounds.size.height.round.to_i,
        scale_factor: scale.round(2),
        dpi: dpi,
        refresh_rate: refresh_rate,
        orientation: bounds.size.width >= bounds.size.height ? "landscape" : "portrait",
        primary: id == main_id || LibCG.CGDisplayIsMain(id) != 0,
        width_mm: width_mm > 0 ? width_mm : nil,
        height_mm: height_mm > 0 ? height_mm : nil
      )
    end

    private def compute_dpi(width : Float64, height : Float64, width_mm : Int32, height_mm : Int32, scale : Float64) : Float64
      if width_mm > 0 && height_mm > 0
        diagonal_px = Math.sqrt(width ** 2 + height ** 2)
        diagonal_mm = Math.sqrt(width_mm ** 2 + height_mm ** 2)
        return (diagonal_px / diagonal_mm * 25.4).round(2)
      end

      scale * 96.0
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

    private LibCF = Positron::Adapters::MacOS::LibCF

    # Plain C functions — struct returns (CGRect, CGSize) are marshalled
    # natively by the compiler, no objc_msgSend dispatch involved.
    @[Link(framework: "CoreGraphics")]
    lib LibCG
      struct CGPoint
        x : Float64
        y : Float64
      end

      struct CGSize
        width : Float64
        height : Float64
      end

      struct CGRect
        origin : CGPoint
        size : CGSize
      end

      fun CGMainDisplayID : UInt32
      fun CGGetOnlineDisplayList(max_displays : UInt32, active_displays : UInt32*, display_count : UInt32*) : Int32
      fun CGDisplayBounds(display : UInt32) : CGRect
      fun CGDisplayScreenSize(display : UInt32) : CGSize
      fun CGDisplayIsMain(display : UInt32) : UInt32
      fun CGDisplayCopyDisplayMode(display : UInt32) : Void*
      fun CGDisplayModeGetRefreshRate(mode : Void*) : Float64
      fun CGDisplayModeGetPixelWidth(mode : Void*) : Int64
    end
  end
end
