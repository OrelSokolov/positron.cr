module CrystalUI
  # Abstract UI surface exposed to the Crystal Host.
  #
  # On Linux this is backed by WebKitGTK, on macOS by WKWebView,
  # on Windows by WebView2, and on mobile by the platform WebView.
  abstract class WebViewPort
    abstract def create(title : String, width : Int32, height : Int32, icon_path : String? = nil)
    abstract def navigate(url : String)
    abstract def eval_js(script : String)
    abstract def show
    abstract def hide
    abstract def bind(name : String, &block : String -> String)
    abstract def run_event_loop
    abstract def close
  end
end
