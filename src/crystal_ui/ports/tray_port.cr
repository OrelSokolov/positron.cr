module CrystalUI
  # Cross-platform system tray / status bar surface.
  #
  # Design mirrors getlantern/systray: the Crystal Host drives the tray
  # through a single interface; each platform provides a thin adapter.
  abstract class TrayPort
    # Initialize the native tray surface. Must be called on the GUI thread.
    abstract def create

    # Set the tray icon from raw image bytes (PNG/ICO/etc).
    abstract def set_icon(icon_bytes : Bytes, template : Bool = false)

    # Set the tray title (macOS/Linux label).
    abstract def set_title(title : String)

    # Set the tray tooltip (macOS/Windows).
    abstract def set_tooltip(tooltip : String)

    # Add or update a menu item.
    abstract def add_or_update_item(item : TrayItem)

    # Add a separator.
    abstract def add_separator(id : Int32)

    # Remove an item from the menu.
    abstract def remove_item(id : Int32)

    # Show a previously hidden item.
    abstract def show_item(id : Int32)

    # Hide an item.
    abstract def hide_item(id : Int32)

    # Register a callback for menu item clicks.
    abstract def on_item_click(&block : Int32 ->)

    # Show the tray icon.
    abstract def show

    # Hide the tray icon.
    abstract def hide

    # Quit the tray and release resources.
    abstract def quit
  end
end
