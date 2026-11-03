require "../ports/webview_port"

module Positron
  module Mobile
    # Serves embedded frontend assets for mobile WebViews.
    #
    # Mobile WebView engines reject custom URI schemes (the same gap as
    # the Windows WebView2 port), so embedded trees are served from the
    # virtual HTTPS host `https://app.positron.local/`: the Java/Swift
    # shim intercepts requests for that host and asks the Crystal host
    # for the bytes through the bridge. This router is the platform-pure
    # half of that path: path normalization, MIME detection and handler
    # dispatch (the shim provides the actual interception).
    class AssetRouter
      # Extensions the frontend is likely to request. Unknown extensions
      # fall back to application/octet-stream, which is enough for
      # fetch() downloads.
      MIME_TYPES = {
        ".html"  => "text/html; charset=utf-8",
        ".htm"   => "text/html; charset=utf-8",
        ".css"   => "text/css; charset=utf-8",
        ".js"    => "text/javascript; charset=utf-8",
        ".mjs"   => "text/javascript; charset=utf-8",
        ".json"  => "application/json; charset=utf-8",
        ".map"   => "application/json; charset=utf-8",
        ".txt"   => "text/plain; charset=utf-8",
        ".svg"   => "image/svg+xml",
        ".png"   => "image/png",
        ".jpg"   => "image/jpeg",
        ".jpeg"  => "image/jpeg",
        ".gif"   => "image/gif",
        ".webp"  => "image/webp",
        ".ico"   => "image/x-icon",
        ".bmp"   => "image/bmp",
        ".woff"  => "font/woff",
        ".woff2" => "font/woff2",
        ".ttf"   => "font/ttf",
        ".otf"   => "font/otf",
        ".wasm"  => "application/wasm",
        ".pdf"   => "application/pdf",
        ".mp3"   => "audio/mpeg",
        ".mp4"   => "video/mp4",
        ".webm"  => "video/webm",
      }

      @handlers = {} of String => (String -> SchemeResponse?)

      # Register the handler for a URI scheme (same contract as
      # `WebViewPort#register_uri_scheme`): receives the request path
      # ("/index.html") and returns the response, or nil for "not
      # found" (served as an empty 404 body).
      def register_uri_scheme(scheme : String, &handler : String -> SchemeResponse?) : Nil
        @handlers[scheme] = handler
      end

      def scheme_registered?(scheme : String) : Bool
        @handlers.has_key?(scheme)
      end

      # Serve by path alone, using the first registered scheme handler.
      # Mobile shims ask for `https://app.positron.local/<path>` and do
      # not carry the original scheme through, so there is exactly one
      # meaningful handler per app.
      def serve_path(path : String) : SchemeResponse?
        scheme = @handlers.each_key.first?
        scheme ? serve(scheme, path) : nil
      end

      # Resolve a request path against the registered scheme handler.
      # `path` arrives URL-decoded from the shim; normalization mirrors
      # what a static file server would do. Returns nil when no handler
      # is registered for the scheme.
      def serve(scheme : String, path : String) : SchemeResponse?
        handler = @handlers[scheme]?
        return nil unless handler

        normalized = normalize_path(path)
        return nil unless normalized

        handler.call(normalized)
      end

      # Strip query string and fragment, map "" and "/" to the index
      # document. Returns nil for paths that escape the root
      # ("/../secrets" — the WebView should not be able to probe the
      # host filesystem).
      def self.normalize_path(path : String) : String?
        cleaned = path.split('?')[0].split('#')[0]
        return nil if cleaned.includes?("..")

        cleaned = "/" if cleaned.empty?
        cleaned = "/index.html" if cleaned == "/"
        cleaned
      end

      def self.mime_for(path : String) : String
        ext = File.extname(path).downcase
        MIME_TYPES[ext]? || "application/octet-stream"
      end

      # Convenience used by the host when answering shim asset requests
      # for which the frontend never registered a scheme: no handler,
      # no bytes.
      def serve_bytes(scheme : String, path : String) : SchemeResponse?
        serve(scheme, path)
      end

      private def normalize_path(path : String) : String?
        self.class.normalize_path(path)
      end
    end
  end
end
