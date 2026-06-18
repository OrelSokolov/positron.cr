require "log"

module CrystalUI
  # Base class for mobile hosts (Android/iOS).
  #
  # The native Activity/ViewController creates the host through the C-ABI
  # entry points and passes the platform WebView pointer. The host then
  # drives the same Application, plugins and command registry as the desktop.
  abstract class MobileHost < Host
    @webview_ptr : Void*
    @context_ptr : Void*

    def initialize(app : Application, @webview_ptr : Void*, @context_ptr : Void*)
      super(app)
    end

    # Mobile hosts talk to the WebView through the native shim, not through a
    # WebViewPort. Use eval_js instead.
    def webview : WebViewPort
      raise "Mobile hosts do not expose a WebViewPort; use eval_js to talk to the WebView"
    end

    # Mobile platforms do not have a system tray.
    def tray : TrayPort
      raise "Mobile hosts do not support a system tray"
    end
  end
end
