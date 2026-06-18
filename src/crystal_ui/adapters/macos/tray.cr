module CrystalUI
  module Adapters
    module MacOS
      # Placeholder macOS tray adapter.
      #
      # Uses NSStatusBar / NSStatusItem. This is a stub that satisfies the
      # TrayPort contract; a full implementation follows the pattern in
      # getlantern/systray's systray_darwin.m.
      class StatusBarTray < TrayPort
        def initialize
        end

        def supported? : Bool
          true
        end

        def create(icon : IconSource? = nil, title : String? = nil)
          Log.warn { "macOS tray adapter is a stub" }
        end

        def set_icon(icon : IconSource)
        end

        def set_title(title : String)
        end

        def set_tooltip(tooltip : String)
        end

        def add_or_update_item(item : TrayItem)
        end

        def add_separator(id : Int32)
        end

        def remove_item(id : Int32)
        end

        def show_item(id : Int32)
        end

        def hide_item(id : Int32)
        end

        def on_item_click(&block : Int32 ->)
        end

        def show
        end

        def hide
        end

        def quit
        end
      end
    end
  end
end
