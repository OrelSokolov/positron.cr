require "log"
require "./adapter"
require "../../adapters/ios/objc"

module Positron::Plugins
  # iOS display adapter enumerating UIScreen objects: logical `bounds`
  # in points, `nativeBounds` pixels for the scale factor and
  # `maximumFramesPerSecond` for the refresh rate. iOS reports no
  # physical screen size, so DPI uses the documented
  # `scale_factor * 96.0` fallback. Screens are all positioned at
  # (0,0) — iOS exposes no virtual-desktop coordinates.
  class IOsDisplayAdapter < DisplayAdapter
    ObjC = Positron::Adapters::IOS::ObjC

    def info : DisplayInfo
      screens_obj = ObjC.send0(ObjC.cls("UIScreen"), ObjC.sel("screens"))
      return fallback_info("no screens detected") if screens_obj.null?

      main = ObjC.send0(ObjC.cls("UIScreen"), ObjC.sel("mainScreen"))

      screens = (0...ObjC.send0_i(screens_obj, ObjC.sel("count"))).map do |i|
        build_screen(
          ObjC.send1(screens_obj, ObjC.sel("objectAtIndex:"), ObjC.int_arg(i)),
          i, main)
      end
      return fallback_info("screens could not be enumerated") if screens.empty?

      total_width = screens.max_of(&.width)
      total_height = screens.max_of(&.height)
      orientation = total_width >= total_height ? "landscape" : "portrait"

      DisplayInfo.new(
        screens: screens,
        primary_screen_id: screens.find(&.primary).try(&.id),
        total_width: total_width,
        total_height: total_height,
        orientation: orientation
      )
    rescue ex
      fallback_info("display detection failed: #{ex.message}")
    end

    # --- Internals ---

    private def build_screen(screen : Void*, index : Int32, main : Void*) : DisplayMonitorInfo
      bounds = rect_value(screen, "bounds")
      native = rect_value(screen, "nativeBounds")

      logical_width = bounds.size.width
      logical_height = bounds.size.height
      # nativeBounds is pixel-sized and always set; derive the scale
      # from it instead of a second CGFloat call.
      scale = logical_width > 0 ? native.size.width / logical_width : 1.0

      fps = ObjC.send0_i(screen, ObjC.sel("maximumFramesPerSecond"))

      DisplayMonitorInfo.new(
        id: "screen-#{index}",
        name: screen == main ? "Main Screen" : "Screen #{index + 1}",
        x: 0,
        y: 0,
        width: logical_width.round.to_i,
        height: logical_height.round.to_i,
        scale_factor: scale.round(2),
        dpi: (scale * 96.0).round(2),
        refresh_rate: fps > 0 ? fps.to_f : 60.0,
        orientation: logical_width >= logical_height ? "landscape" : "portrait",
        primary: screen == main
      )
    end

    # CGRect returns must go through the NSInvocation path (struct
    # returns — see objc.cr dispatch-strategy docs).
    private def rect_value(screen : Void*, selector : String) : Adapters::IOS::LibObjC::NSRect
      call = Adapters::IOS::ObjC::Call.new(screen, selector)
      call.invoke
      call.ret_rect
    end

    private def fallback_info(reason : String) : DisplayInfo
      Log.for("positron.plugins.display").warn { "#{reason}; returning fallback display info" }
      screen = DisplayMonitorInfo.new(
        id: "fallback",
        name: "Fallback screen",
        x: 0,
        y: 0,
        width: 1170,
        height: 2532,
        scale_factor: 3.0,
        dpi: 460.0,
        refresh_rate: 60.0,
        orientation: "portrait",
        primary: true
      )
      DisplayInfo.new(
        screens: [screen],
        primary_screen_id: "fallback",
        total_width: 1170,
        total_height: 2532,
        orientation: "portrait"
      )
    end
  end
end
