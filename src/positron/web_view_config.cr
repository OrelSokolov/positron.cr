module Positron
  # Platform-agnostic configuration for creating a WebView surface.
  record WebViewConfig,
    title : String = "",
    width : Int32 = 800,
    height : Int32 = 600,
    icon : IconSource? = nil,
    transparent : Bool = false,
    resizable : Bool = true,
    # true  → the close button hides the window (tray-style apps bring it
    #         back via `show`); the default keeps existing apps working.
    # false → the close button quits the event loop (apps without a tray).
    close_to_tray : Bool = true
end
