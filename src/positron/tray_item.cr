module Positron
  # A single entry in the system tray menu.
  #
  # Mirrors the cross-platform menu item abstraction used by getlantern/systray.
  class TrayItem
    getter id : Int32
    getter parent_id : Int32
    property title : String
    property tooltip : String
    property disabled : Bool
    property checked : Bool
    property checkable : Bool
    property hidden : Bool

    def initialize(
      @id : Int32,
      @title : String,
      @tooltip : String = "",
      @disabled : Bool = false,
      @checked : Bool = false,
      @checkable : Bool = false,
      @parent_id : Int32 = 0,
      @hidden : Bool = false,
    )
    end

    def separator? : Bool
      @title == "-"
    end
  end
end
