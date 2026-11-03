require "json"
require "log"
require "./adapter"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android display adapter: DisplayMetrics through the JNI bridge.
  # The bridge returns the metrics as a JSON string (see
  # PositronBridge.displayInfo in the Java shim).
  class AndroidDisplayAdapter < DisplayAdapter
    private def bridge : Positron::Adapters::Android::LibJNI::JObject
      Positron::Adapters::Android::LibShim.positron_shim_bridge
    end

    def info : DisplayInfo
      raw = Positron::Adapters::Android::JNI.instance.call_string(bridge, "displayInfo", "()Ljava/lang/String;")
      metrics = raw ? JSON.parse(raw) : nil
      return fallback_screen unless metrics

      width = metrics["width"].as_i
      height = metrics["height"].as_i
      dpi = metrics["dpi"].as_i.to_f
      scale = metrics["scale"].as_f
      orientation = metrics["orientation"].as_s

      screen = DisplayMonitorInfo.new(
        id: "main",
        name: "Android display",
        x: 0,
        y: 0,
        width: width,
        height: height,
        scale_factor: scale,
        dpi: dpi,
        refresh_rate: 60.0,
        orientation: orientation,
        primary: true,
        width_mm: nil,
        height_mm: nil
      )
      DisplayInfo.new(
        screens: [screen],
        primary_screen_id: "main",
        total_width: width,
        total_height: height,
        orientation: orientation
      )
    rescue ex
      Log.for("positron.plugins.display").error(exception: ex) { "display detection failed" }
      fallback_screen
    end

    private def fallback_screen : DisplayInfo
      screen = DisplayMonitorInfo.new(
        id: "fallback",
        name: "Fallback monitor",
        x: 0,
        y: 0,
        width: 1080,
        height: 1920,
        scale_factor: 2.0,
        dpi: 420.0,
        refresh_rate: 60.0,
        orientation: "portrait",
        primary: true
      )
      DisplayInfo.new(
        screens: [screen],
        primary_screen_id: "fallback",
        total_width: 1080,
        total_height: 1920,
        orientation: "portrait"
      )
    end
  end
end
