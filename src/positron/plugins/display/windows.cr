require "log"
require "json"
require "./adapter"
require "../../adapters/windows/win32"

module Positron::Plugins
  # Windows implementation of the Display plugin.
  #
  # Monitors come from EnumDisplayMonitors + GetMonitorInfoExW; the scale
  # factor from GetDpiForMonitor (per-monitor v2 aware value), the refresh
  # rate from EnumDisplaySettingsW and the physical size from the monitor
  # DC (HORZSIZE/VERTSIZE in mm).
  class WindowsDisplayAdapter < DisplayAdapter
    include ::Positron::Adapters::Windows # Win32 FFI bindings
    Log = ::Log.for("positron.plugins.display")

    MONITORINFOF_PRIMARY = 1_u32

    # DEVMODEW offsets we care about (see docs; accessed through a raw
    # byte buffer to avoid spelling out the whole ~220-byte struct).
    DEVMODE_SIZE           = 220
    DEVMODE_DM_SIZE_OFFSET = 68
    DEVMODE_FREQUENCY_OFF  = 184 # dmDisplayFrequency (DWORD)

    def info : DisplayInfo
      handles = [] of Void*
      rects = [] of Win32::LibUser32::Rect

      callback = Box.box({handles, rects})
      enum_proc = ->(monitor : Void*, hdc : Void*, rect : Win32::LibUser32::Rect*, data : Int64) {
        pair = Box(Tuple(Array(Void*), Array(Win32::LibUser32::Rect))).unbox(Pointer(Void).new(data.to_u64!))
        pair[0] << monitor
        pair[1] << rect.value
        1 # continue
      }

      if Win32::LibUser32.EnumDisplayMonitors(Pointer(Void).null, Pointer(Void).null,
           enum_proc.pointer, callback.address.to_i64!) == 0 || handles.empty?
        return fallback_info("no monitors enumerated")
      end

      screens = [] of DisplayMonitorInfo
      primary_id : String? = nil

      handles.each_with_index do |monitor, index|
        screen = build_screen(monitor, rects[index], index)
        screens << screen
        primary_id = screen.id if screen.primary
      end

      total_width = Win32::LibUser32.GetSystemMetrics(Win32::SM_CXVIRTUALSCREEN)
      total_height = Win32::LibUser32.GetSystemMetrics(Win32::SM_CYVIRTUALSCREEN)
      orientation = total_width >= total_height ? "landscape" : "portrait"

      DisplayInfo.new(
        screens: screens,
        primary_screen_id: primary_id,
        total_width: total_width,
        total_height: total_height,
        orientation: orientation
      )
    end

    private def build_screen(monitor : Void*, rect : Win32::LibUser32::Rect, index : Int32) : DisplayMonitorInfo
      info = Win32::LibUser32::MonitorInfoExW.new
      info.cb_size = sizeof(Win32::LibUser32::MonitorInfoExW)
      if Win32::LibUser32.GetMonitorInfoW(monitor, pointerof(info).as(Void*)) == 0
        return fallback_monitor(index)
      end

      primary = (info.dw_flags & MONITORINFOF_PRIMARY) != 0
      scale = scale_factor(monitor)
      refresh = refresh_rate(info.sz_device)
      width_mm, height_mm = physical_size(info.sz_device)

      dpi = compute_dpi(info.rc_monitor, width_mm, height_mm, scale)
      orientation = rect.right - rect.left >= rect.bottom - rect.top ? "landscape" : "portrait"

      DisplayMonitorInfo.new(
        id: "monitor-#{index}",
        name: "Monitor #{index + 1}",
        x: info.rc_monitor.left,
        y: info.rc_monitor.top,
        width: info.rc_monitor.right - info.rc_monitor.left,
        height: info.rc_monitor.bottom - info.rc_monitor.top,
        scale_factor: scale,
        dpi: dpi,
        refresh_rate: refresh,
        orientation: orientation,
        primary: primary,
        width_mm: width_mm > 0 ? width_mm : nil,
        height_mm: height_mm > 0 ? height_mm : nil
      )
    end

    private def scale_factor(monitor : Void*) : Float64
      dpi_x = 0_u32
      dpi_y = 0_u32
      return 1.0 if Win32::LibShCore.GetDpiForMonitor(monitor, 0, pointerof(dpi_x), pointerof(dpi_y)) != 0
      return 1.0 if dpi_x == 0
      (dpi_x / 96.0).round(2)
    end

    private def refresh_rate(device : UInt16[32]) : Float64
      devmode = Pointer(UInt8).malloc(DEVMODE_SIZE)
      devmode[DEVMODE_DM_SIZE_OFFSET] = (DEVMODE_SIZE & 0xFF).to_u8
      devmode[DEVMODE_DM_SIZE_OFFSET + 1] = (DEVMODE_SIZE >> 8).to_u8

      device_ptr = device.to_unsafe
      if Win32::LibUser32.EnumDisplaySettingsW(device_ptr, Win32::ENUM_CURRENT_SETTINGS, devmode) != 0
        hz = devmode[DEVMODE_FREQUENCY_OFF].to_i32 |
             (devmode[DEVMODE_FREQUENCY_OFF + 1].to_i32 << 8) |
             (devmode[DEVMODE_FREQUENCY_OFF + 2].to_i32 << 16) |
             (devmode[DEVMODE_FREQUENCY_OFF + 3].to_i32 << 24)
        return hz > 0 ? hz.to_f : 60.0
      end
      60.0
    end

    private def physical_size(device : UInt16[32]) : {Int32, Int32}
      device_ptr = device.to_unsafe
      dc = Win32::LibGdi.CreateDCW(Pointer(UInt16).null, device_ptr, Pointer(UInt16).null, Pointer(Void).null)
      return {0, 0} if dc.null?

      width_mm = Win32::LibGdi.GetDeviceCaps(dc, Win32::HORZSIZE)
      height_mm = Win32::LibGdi.GetDeviceCaps(dc, Win32::VERTSIZE)
      Win32::LibGdi.DeleteDC(dc)
      {width_mm, height_mm}
    end

    private def compute_dpi(rect : Win32::LibUser32::Rect, width_mm : Int32, height_mm : Int32, scale : Float64) : Float64
      if width_mm > 0 && height_mm > 0
        width = (rect.right - rect.left).abs
        height = (rect.bottom - rect.top).abs
        diagonal_px = Math.sqrt(width ** 2 + height ** 2)
        diagonal_mm = Math.sqrt(width_mm ** 2 + height_mm ** 2)
        return (diagonal_px / diagonal_mm * 25.4).round(2)
      end

      scale * 96.0
    end

    private def fallback_monitor(index : Int32) : DisplayMonitorInfo
      DisplayMonitorInfo.new(
        id: "monitor-#{index}", name: "Monitor #{index + 1}",
        x: 0, y: 0, width: 1920, height: 1080,
        scale_factor: 1.0, dpi: 96.0, refresh_rate: 60.0,
        orientation: "landscape", primary: false
      )
    end

    private def fallback_info(reason : String) : DisplayInfo
      Log.warn { "#{reason}; returning fallback display info" }
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
  end
end
