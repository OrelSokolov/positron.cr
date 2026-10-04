require "log"
require "./adapter"
require "../../adapters/macos/objc"

module Positron::Plugins
  # macOS theme adapter reading the AppKit appearance: NSApp's effective
  # appearance matched against NSAppearanceNameDark, the system control
  # accent color (NSColor.controlAccentColor, 10.14+) and the NSWorkspace
  # accessibility contrast flag.
  class MacOSThemeAdapter < ThemeAdapter
    OBJC = Positron::Adapters::MacOS::ObjC
    App  = Positron::Adapters::MacOS::App

    DARK_APPEARANCE = "NSAppearanceNameDark"

    def info : ThemeInfo
      info = OBJC.with_autorelease_pool do
        ThemeInfo.new(
          mode: dark_mode? ? "dark" : "light",
          accent_color: accent_color,
          material_you: false,
          high_contrast: high_contrast?
        )
      end
      info
    rescue ex
      Log.for("positron.plugins.theme").warn { "failed to read macOS appearance: #{ex.message}" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end

    # --- Internals ---

    private def dark_mode? : Bool
      appearance = OBJC.send0(App.nsapp, OBJC.sel("effectiveAppearance"))
      return false if appearance.null?

      names = OBJC.send1(OBJC.cls("NSArray"), OBJC.sel("arrayWithObject:"),
        OBJC.nsstr(DARK_APPEARANCE))
      match = OBJC.send1(appearance, OBJC.sel("bestMatchFromAppearancesWithNames:"), names)
      OBJC.to_s(match) == DARK_APPEARANCE
    end

    # NSColor.controlAccentColor converted to sRGB and formatted as
    # "#RRGGBB"; nil when the color cannot be resolved.
    private def accent_color : String?
      color = OBJC.send0(OBJC.cls("NSColor"), OBJC.sel("controlAccentColor"))
      return nil if color.null?

      srgb_space = OBJC.send0(OBJC.cls("NSColorSpace"), OBJC.sel("sRGBColorSpace"))
      color = OBJC.send1(color, OBJC.sel("colorUsingColorSpace:"), srgb_space)
      return nil if color.null?

      r = component(color, "redComponent")
      g = component(color, "greenComponent")
      b = component(color, "blueComponent")
      return nil if r.nil? || g.nil? || b.nil?

      "#%02X%02X%02X" % {channel(r), channel(g), channel(b)}
    end

    # CGFloat component getter — float returns need the NSInvocation
    # path (see objc.cr dispatch-strategy docs).
    private def component(color : Void*, selector : String) : Float64?
      call = Positron::Adapters::MacOS::ObjC::Call.new(color, selector)
      call.invoke
      call.ret_f64
    rescue ex
      Log.for("positron.plugins.theme").warn { "#{selector} failed: #{ex.message}" }
      nil
    end

    private def channel(value : Float64) : Int32
      (value.clamp(0.0, 1.0) * 255.0).round.to_i
    end

    private def high_contrast? : Bool
      workspace = OBJC.send0(OBJC.cls("NSWorkspace"), OBJC.sel("sharedWorkspace"))
      return false if workspace.null?
      OBJC.send0_b(workspace, OBJC.sel("accessibilityDisplayShouldIncreaseContrast"))
    end
  end
end
