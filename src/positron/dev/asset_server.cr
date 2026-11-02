require "http/server"
require "log"

module Positron
  # Development-mode tooling.
  #
  # Dev mode is enabled by setting `POSITRON_DEV=1` in the environment
  # (or by using `Application#serve_directory`, which implies dev mode).
  module Dev
    def self.enabled? : Bool
      value = ENV["POSITRON_DEV"]?
      return false unless value
      !{"", "0", "false", "no"}.includes?(value.downcase)
    end

    MIME_TYPES = {
      "html"  => "text/html; charset=utf-8",
      "htm"   => "text/html; charset=utf-8",
      "css"   => "text/css; charset=utf-8",
      "js"    => "application/javascript; charset=utf-8",
      "mjs"   => "application/javascript; charset=utf-8",
      "json"  => "application/json; charset=utf-8",
      "svg"   => "image/svg+xml",
      "png"   => "image/png",
      "jpg"   => "image/jpeg",
      "jpeg"  => "image/jpeg",
      "gif"   => "image/gif",
      "webp"  => "image/webp",
      "ico"   => "image/x-icon",
      "woff"  => "font/woff",
      "woff2" => "font/woff2",
      "ttf"   => "font/ttf",
      "otf"   => "font/otf",
      "txt"   => "text/plain; charset=utf-8",
      "wasm"  => "application/wasm",
      "mp3"   => "audio/mpeg",
      "mp4"   => "video/mp4",
    }

    def self.mime_type(path : String) : String
      ext = File.extname(path).downcase.lchop('.')
      MIME_TYPES[ext]? || "application/octet-stream"
    end

    # Injected into every HTML page served by the dev asset server:
    # catches window.onerror / unhandledrejection, renders a floating
    # red overlay and forwards the error to the host as a "dev.error"
    # bridge event (the host duplicates it to STDERR). Release builds
    # never see this script.
    OVERLAY_JS = <<-JS
      (function(){
        if (window.__positronDevOverlay) return; window.__positronDevOverlay = true;
        function post(payload) {
          try {
            if (window.PositronBridge)
              PositronBridge.postMessage(JSON.stringify({type:'event',event:'dev.error',payload:payload}));
          } catch (e) {}
        }
        function show(msg, detail) {
          var box = document.getElementById('__positron_overlay');
          if (!box) {
            box = document.createElement('div'); box.id = '__positron_overlay';
            box.style.cssText = 'position:fixed;bottom:12px;right:12px;z-index:2147483647;max-width:60%;font:12px/1.45 monospace;background:#b91c1c;color:#fff;padding:8px 10px;border-radius:6px;box-shadow:0 4px 14px rgba(0,0,0,.3);white-space:pre-wrap;word-break:break-word';
            (document.body || document.documentElement).appendChild(box);
          }
          var line = document.createElement('div');
          line.textContent = msg + (detail ? '\\n' + detail : '');
          box.appendChild(line);
          while (box.children.length > 5) box.removeChild(box.firstChild);
          clearTimeout(box.__t);
          box.__t = setTimeout(function(){ box.remove(); }, 10000);
        }
        window.addEventListener('error', function(e) {
          var msg = e.message || 'Error';
          var where = e.filename ? ' (' + e.filename + ':' + e.lineno + ':' + e.colno + ')' : '';
          show(msg + where, e.error && e.error.stack);
          post({message: msg, file: e.filename || '', line: e.lineno || 0,
                column: e.colno || 0, stack: (e.error && e.error.stack) || ''});
        });
        window.addEventListener('unhandledrejection', function(e) {
          var r = e.reason;
          var msg = 'Unhandled rejection: ' + ((r && (r.message || r.stack)) || r);
          show(msg);
          post({message: msg, file: '', line: 0, column: 0,
                stack: (r && r.stack) || String(r)});
        });
      })();
      JS

    # Serves a frontend directory from disk over HTTP for development.
    #
    # This is the runtime counterpart of `Application#embed_directory`:
    # instead of baking assets into the binary at compile time, the WebView
    # loads `http://127.0.0.1:<port>/` and assets are read from disk on
    # every request — so frontend edits show up without recompiling.
    #
    # Features:
    #   - HTML responses get the Positron runtime (facade + state hydration)
    #     and the bridge shim injected, so pages served from disk have the
    #     same `Positron.*` API as embedded ones.
    #   - SPA fallback: unknown extensionless paths serve `index.html`.
    #   - Live reload: the directory is watched (mtime polling, portable);
    #     on change the `on_reload` callback fires — wire it to
    #     `host.eval_js("location.reload()")` for a full page reload.
    class AssetServer
      getter base_url : String
      getter port : Int32

      @server : HTTP::Server
      @watch_fiber : Fiber?

      # - `root`: directory to serve (e.g. the built or source frontend dir)
      # - `runtime_provider`: called on every HTML response; returns HTML
      #   snippets (<script>…) injected into the document — evaluate the
      #   JS facade and state hydration here so reloads get fresh state
      # - `on_reload`: called (from a watcher fiber) when a file changes
      # - `fallback_path`: served when a path is missing and has no
      #   extension (SPA routing); defaults to "/index.html"
      def initialize(
        @root : String,
        *, base_url_prefix : String? = nil,
        @fallback_path : String = "/index.html",
        runtime_provider : -> Array(String) = -> { [] of String },
        &@on_reload : -> Nil
      )
        @runtime_provider = runtime_provider
        @server = HTTP::Server.new do |context|
          handle(context)
        end
        address = @server.bind_tcp("127.0.0.1", 0)
        @port = address.port
        @base_url = base_url_prefix || "http://127.0.0.1:#{@port}"
      end

      # Start serving and watching. Non-blocking.
      def start : Nil
        spawn { @server.listen }
        start_watcher
      end

      def stop : Nil
        @server.close unless @server.closed?
      end

      private def handle(context : HTTP::Server::Context)
        path = URI.decode(context.request.path.not_nil!)
        path = "/" if path.empty?
        return serve_404(context) unless sane?(path)

        file_path = resolve(path)
        return serve_404(context) unless file_path && File.file?(file_path)

        bytes = File.read(file_path)
        mime = Dev.mime_type(file_path)

        if mime.starts_with?("text/html")
          context.response.content_type = mime
          context.response.print transform(bytes, path)
        else
          context.response.content_type = mime
          context.response.write(bytes.to_slice)
        end
      rescue ex
        Log.error { "Dev asset server error for #{context.request.path}: #{ex.message}" }
        context.response.status_code = 500
      end

      # Reject path traversal: only clean, rooted, normalized paths pass.
      private def sane?(path : String) : Bool
        return false unless path.starts_with?('/')
        return false if path.includes?("..")
        !path.includes?('\0')
      end

      private def resolve(path : String) : String?
        candidate = File.join(@root, path.lchop('/'))
        return candidate if File.file?(candidate)

        # SPA fallback: extensionless deep links fall back to index.html.
        if File.extname(path).empty? && @fallback_path
          fallback = File.join(@root, @fallback_path.lchop('/'))
          return fallback if File.file?(fallback)
        end

        nil
      end

      # Rewrite a served HTML document so it matches what
      # `Application#application_html` produces for release builds:
      #
      #   - {{RUNTIME_JS}} / {{HYDRATE_JS}} are replaced with the current
      #     JS facade and state hydration from `runtime_provider`.
      #   - {{CSS}} / {{JS}} are inlined from `application.css` /
      #     `application.js` next to the served document.
      #   - Pages without markers simply get the runtime injected into
      #     <head>, so plain SPAs work too.
      private def transform(html : String, request_path : String) : String
        snippets = @runtime_provider.call
        runtime = snippets[0]? || ""
        hydrate = snippets[1]? || ""

        dir = File.dirname(File.join(@root, request_path.lchop('/')))
        css = read_sibling(dir, "application.css")
        js = read_sibling(dir, "application.js")

        html = html
          .sub("{{CSS}}", css)
          .sub("{{JS}}", js)
          .sub("{{RUNTIME_JS}}", runtime)
          .sub("{{HYDRATE_JS}}", hydrate)

        # No markers (plain SPA page): inject the runtime into <head>.
        unless html.includes?("__positronResolve")
          snippet = snippets.map { |s| "<script>#{s}</script>" }.join('\n')
          unless snippet.empty?
            if head = html.match(/<head[^>]*>/i)
              html = html.insert(head.end.not_nil!, snippet)
            else
              html = snippet + html
            end
          end
        end

        # Dev error overlay (see Dev::OVERLAY_JS) — every page, marker
        # or not.
        overlay = "<script>#{Dev::OVERLAY_JS}</script>"
        if closing = html.match(/<\/head>/i)
          html = html.insert(closing.begin.not_nil!, overlay)
        else
          html = overlay + html
        end

        html
      end

      private def read_sibling(dir : String, name : String) : String
        path = File.join(dir, name)
        File.file?(path) ? File.read(path) : ""
      end

      private def serve_404(context : HTTP::Server::Context)
        context.response.status_code = 404
        context.response.content_type = "text/plain; charset=utf-8"
        context.response.print "Not found"
      end

      private def start_watcher
        snapshot = scan

        @watch_fiber = spawn do
          loop do
            sleep 500.milliseconds
            current = scan
            next if current == snapshot
            snapshot = current
            begin
              @on_reload.call
            rescue ex
              Log.error { "Dev reload callback failed: #{ex.message}" }
            end
          end
        end
      end

      # Map of "relative/path" => mtime, for the served tree.
      private def scan : Hash(String, Int64)
        map = {} of String => Int64
        scan_dir(@root, map)
        map
      rescue
        {} of String => Int64
      end

      private def scan_dir(dir : String, map : Hash(String, Int64))
        Dir.each_child(dir) do |name|
          path = File.join(dir, name)
          if File.directory?(path)
            scan_dir(path, map)
          elsif File.file?(path)
            map[path] = File.info(path).modification_time.to_unix_ms
          end
        end
      rescue
        # unreadable dir — skip
      end
    end
  end
end
