require "log"
require "./adapter"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android theme adapter: UI_MODE night mode through the JNI bridge.
  class AndroidThemeAdapter < ThemeAdapter
    private def bridge : Positron::Adapters::Android::LibJNI::JObject
      Positron::Adapters::Android::LibShim.positron_shim_bridge
    end

    def info : ThemeInfo
      mode = Positron::Adapters::Android::JNI.instance.call_string(bridge, "uiTheme", "()Ljava/lang/String;") || "light"
      ThemeInfo.new(
        mode: mode,
        accent_color: nil,
        # Material You dynamic color exists on the device, but reading
        # the palette needs the androidx graphics APIs — not wired yet.
        material_you: false,
        high_contrast: false
      )
    rescue ex
      Log.for("positron.plugins.theme").error(exception: ex) { "theme detection failed" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end
  end
end
