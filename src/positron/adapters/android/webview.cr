require "./jni"
require "./shim"

module Positron
  module Adapters
    module Android
      # WebViewPort over the Java shim's PositronBridge.
      #
      # The Activity owns the real android.webkit.WebView; this port
      # drives it through JNI method calls on the bridge object (which
      # marshal to the UI thread on the Java side). JS→Crystal traffic
      # enters through `Host` (the shim's message queue), which calls
      # the handler registered with #bind.
      #
      # Window management (title, size, decorations) is manifest-level
      # on mobile; those operations keep the base-class raises.
      class WebView < WebViewPort
        # Fixed virtual host serving embedded assets (the WebView2
        # trick: mobile WebViews reject custom URI schemes).
        ASSET_HOST = "https://app.positron.local/"

        @host : Host
        @bind_handler : (String -> String)?
        @created = false

        def initialize(@host)
        end

        def create(config : WebViewConfig)
          # The WebView exists since Activity.onCreate; nothing to
          # instantiate. Width/height/title/icon are manifest-level on
          # mobile, devtools follow android:debuggable.
          @created = true
        end

        def load_url(url : String)
          bridge_call_void("loadUrl", "(Ljava/lang/String;)V", rewrite_asset_url(url))
        end

        def load_html(html : String, base_url : String? = nil)
          base = base_url || ASSET_HOST
          bridge_call_void("loadHtml", "(Ljava/lang/String;Ljava/lang/String;)V", html, base)
        end

        def eval_js(script : String)
          # Serialized JSON strings can be large; evaluateJavascript
          # handles them fine on the UI thread.
          bridge_call_void("evalJs", "(Ljava/lang/String;)V", script)
        end

        def show
          bridge_call_void("showWebview", "()V")
        end

        def hide
          bridge_call_void("hideWebview", "()V")
        end

        def close
          bridge_call_void("finishApp", "()V")
        end

        # Register the JS message channel. The Java side injects the
        # bridge object as window.PositronBridge at WebView creation
        # (before any page loads), matching the facade's
        # `PositronBridge.postMessage` calls; `name` is unused, kept
        # for WebViewPort signature parity.
        def bind(name : String, &handler : String -> String)
          @bind_handler = handler
        end

        # Called by the host (GUI fiber) when a message arrives from
        # the JS bridge. Non-empty handler results are evaluated as JS
        # (the WebViewPort#bind contract).
        def handle_message(json : String) : Nil
          handler = @bind_handler
          return unless handler

          response = handler.call(json)
          eval_js(response) unless response.empty?
        end

        def register_uri_scheme(scheme : String, &handler : String -> SchemeResponse?)
          @host.asset_router.register_uri_scheme(scheme) { |path| handler.call(path) }
        end

        # `scheme://host/path` → `https://app.positron.local/path` for
        # schemes registered through #register_uri_scheme (anything
        # else passes through unchanged): mobile WebViews reject
        # custom URI schemes, so embedded trees live on the virtual
        # host the Java shim intercepts. Unlike the Windows port the
        # scheme-specific authority is dropped — the interceptor
        # matches the fixed ASSET_HOST and the asset router dispatches
        # by path alone.
        private def rewrite_asset_url(url : String) : String
          scheme = url.split("://", 2)[0]?
          return url unless scheme && @host.asset_router.scheme_registered?(scheme)
          rest = url.byte_slice(scheme.size + 3)
          slash = rest.index('/')
          path = slash ? rest.byte_slice(slash) : "/"
          "#{ASSET_HOST}#{path.lchop('/')}"
        end

        # NOTE: the splat must stay unrestricted — Crystal 1.21 treats
        # `*string_args : String` as requiring at least one argument,
        # breaking the zero-arg bridge calls (showWebview etc.).
        private def bridge_call_void(name : String, sig : String, *string_args)
          bridge = @host.bridge
          jni = Positron::Adapters::Android::JNI.instance
          jvalues = Array(Int64).new(string_args.size)
          string_args.each { |s| jvalues << jni.to_java(s).address.to_i64 }
          jni.call_void(bridge, name, sig, jvalues)
        end
      end
    end
  end
end
