module CrystalUI
  # A response to a custom URI scheme request (see WebViewPort#register_uri_scheme):
  # raw body bytes plus the MIME type to serve them with.
  struct SchemeResponse
    getter bytes : Bytes
    getter mime_type : String

    def initialize(@bytes : Bytes, @mime_type : String)
    end
  end

  # Abstract UI surface exposed to the Crystal Host.
  #
  # The frontend runtime communicates with the host through a generic
  # `CrystalBridge.postMessage` object that each adapter injects. The host
  # sends data back via `eval_js` (e.g. calling `window.__crystalResolve`).
  abstract class WebViewPort
    abstract def create(config : WebViewConfig)
    abstract def load_url(url : String)
    abstract def load_html(html : String, base_url : String? = nil)
    abstract def eval_js(script : String)
    abstract def show
    abstract def hide
    abstract def close

    # Bind a JS message channel.
    #
    # The adapter must:
    #   1. Inject a platform shim that defines `window.CrystalBridge.postMessage`
    #      and forwards JS messages to the given handler.
    #   2. Call `handler` with the JSON string received from JS.
    #   3. If the handler returns a non-empty string, evaluate it as JS.
    abstract def bind(name : String, &handler : String -> String)

    # Serve a custom URI scheme (e.g. `app://`) from the host process, so
    # embedded assets can be loaded without any HTTP server. The handler
    # receives the request path ("/index.html") and returns a SchemeResponse,
    # or nil for "not found" (served as an empty body).
    #
    # Call this BEFORE `create` — on some platforms schemes must be
    # registered before the WebView instantiates. Platform adapters that do
    # not support custom schemes raise.
    def register_uri_scheme(scheme : String, &handler : String -> SchemeResponse?)
      raise "register_uri_scheme is not implemented on this platform"
    end
  end
end
