module CrystalUI
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
  end
end
