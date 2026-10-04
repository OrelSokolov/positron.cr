require "log"

module Positron
  module Adapters
    module MacOS
      # Placeholder macOS WKWebView adapter.
      #
      # A full implementation uses WKWebView and WKScriptMessageHandler to
      # host the frontend and bridge JS messages to the Crystal Host.
      class WKWebView < WebViewPort
        def initialize
        end

        def create(config : WebViewConfig)
          Log.warn { "macOS WKWebView adapter is a stub" }
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
