require "log"

module Positron
  module Adapters
    module Android
      # Android has no system tray; the TrayPort surface is a no-op so
      # user tray code in on_ready works unchanged (the same pattern as
      # the iOS NullTray — see `adapters/ios/tray.cr`).
      class NullTray < TrayPort
        def supported? : Bool
          false
        end

        def create(icon : IconSource? = nil, title : String? = nil)
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
