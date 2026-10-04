require "log"

module Positron
  module Adapters
    module Windows
      # Placeholder Windows WebView2 adapter.
      #
      # Satisfies the WebViewPort contract; a full implementation uses the
      # Microsoft Edge WebView2 COM API to create a window, host the WebView2
      # control, and wire JS messages through `chrome.webview.postMessage`.
      class WebView2 < WebViewPort
        def initialize
        end

        def create(config : WebViewConfig)
          Log.warn { "Windows WebView2 adapter is a stub" }
        end

        def load_url(url : String)
        end

        def load_html(html : String, base_url : String? = nil)
        end

        def eval_js(script : String)
        end

        def show
        end

        def hide
        end

        def close
        end

        def bind(name : String, &handler : String -> String)
        end
      end
    end
  end
end
