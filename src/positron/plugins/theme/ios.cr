require "log"
require "./adapter"
require "../../adapters/ios/objc"

module Positron::Plugins
  # iOS theme adapter reading the UIKit trait collection: the main
  # screen's `userInterfaceStyle` for dark mode and the accessibility
  # Increase Contrast flag. iOS exposes no system-wide accent color
  # (tint colors are per-app), so `accent_color` stays nil.
  class IOsThemeAdapter < ThemeAdapter
    ObjC = Positron::Adapters::IOS::ObjC

    def info : ThemeInfo
      info = ObjC.with_autorelease_pool do
        ThemeInfo.new(
          mode: dark_mode? ? "dark" : "light",
          accent_color: nil,
          material_you: false,
          high_contrast: high_contrast?
        )
      end
      info
    rescue ex
      Log.for("positron.plugins.theme").warn { "failed to read iOS appearance: #{ex.message}" }
      ThemeInfo.new(mode: "light", accent_color: nil, material_you: false, high_contrast: false)
    end

    # --- Internals ---

    private def dark_mode? : Bool
      screen = ObjC.send0(ObjC.cls("UIScreen"), ObjC.sel("mainScreen"))
      return false if screen.null?

      traits = ObjC.send0(screen, ObjC.sel("traitCollection"))
      return false if traits.null?

      # UIUserInterfaceStyle: 0 unspecified, 1 light, 2 dark.
      ObjC.send0_i(traits, ObjC.sel("userInterfaceStyle")) == 2
    end

    private def high_contrast? : Bool
      LibUIKitAccessibility.UIAccessibilityDarkerSystemColorsEnabled
    end

    # Plain C function (not a method) — new symbol, no clash with the
    # one-fun-per-C-symbol rule. (The UIAccessibilityIs… spelling is an
    # inline header wrapper; this is the exported UIKit symbol.)
    lib LibUIKitAccessibility
      fun UIAccessibilityDarkerSystemColorsEnabled : Bool
    end
  end
end
