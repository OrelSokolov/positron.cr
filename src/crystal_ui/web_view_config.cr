module CrystalUI
  # Platform-agnostic configuration for creating a WebView surface.
  record WebViewConfig,
    title : String = "",
    width : Int32 = 800,
    height : Int32 = 600,
    icon : IconSource? = nil,
    transparent : Bool = false,
    resizable : Bool = true
end
